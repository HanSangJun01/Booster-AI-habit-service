# 포화 테스트 병목 분류 및 Redis 필요성 판정 (worker-3)

작성: 2026-07-08 · 대상: 조회 API(리더보드 PERSONAL) 포화 테스트 · 백엔드 stub http://localhost:8080 (재시작 없음)

## 0. 한 줄 결론

> **먼저 병목이 되는 자원은 HikariCP 커넥션 풀(pool=10)이며, 병목의 정체는 DB 쿼리 비용이 아니라 "커넥션 보유 시간"(대부분 앱-사이드 idle-in-transaction)이다. 처방은 (1) 풀 사이징, (2) 보유시간 단축이고, Redis는 현 규모에서 시기상조(불필요)다.**

인덱스 부재 / 행-스캔 비용 / DB 락 / IO / 핫키 read 집중 가설은 **측정으로 모두 반증**되었다.

---

## 1. 실험 요약

| 실험 | 방법 | 핵심 수치 | 함의 |
|---|---|---|---|
| EXPLAIN (HOT 145, ~1200행) | `EXPLAIN(ANALYZE,BUFFERS)` GROUP BY | **Index Scan** `idx_checkins_challenge_id`, 실행 **0.326ms**, shared **hit=21 read=0** | 쿼리는 인덱스로 이미 sub-ms |
| EXPLAIN (BREADTH 147, ~200행) | 동일 | Index Scan, 실행 **0.127ms**, hit=9 | 행수 차이 = 버퍼 21 vs 9 (사소) |
| 인덱스 추가 실험 | `CREATE INDEX (challenge_id,status)` 후 재-EXPLAIN | 플래너가 **새 인덱스를 채택조차 안 함**, 실행 0.27ms(노이즈) → **롤백 완료** | 인덱스는 레버가 아님 |
| pg_stat_activity 스냅샷 (S1 부하중, 14회/2s) | 상태·wait_event 집계 | **idle in transaction / Client / ClientRead 가 5~8개 지배**, active ≤3, **Lock·LWLock·IO wait = 0** | DB는 바쁘지 않다. 앱을 기다리며 커넥션만 점유 |
| 대조 버스트 400VU: 145 vs 147 | 동일 스크립트, 단일키 | 145=**3280 rps** p99 287ms / 147=**3260 rps** p99 298ms | 1200행 ≈ 200행. **행수는 붕괴 원인 아님** |
| 800VU: 단일키(145) vs 분산(147–644) | 800VU 20s 지속 | 단일=**3406 rps** p99 377ms·0에러 / 분산=**3680 rps** p99 355ms·0에러 | 둘 다 같은 풀 상한. 분산이 **~8%만** 우세 |

> 참고: 짧고 깨끗한 내 800VU 런에서는 단일키도 붕괴하지 않았다(0 에러). worker-2의 장시간 램프에서 S1만 붕괴한 것은 시스템이 **용량 한계(cliff)에 걸쳐 있는 준안정(metastable)** 상태이기 때문 — 아래 3절.

---

## 2. EXPLAIN 결과 (before/after 인덱스)

```
-- HOT 145 (~1200행, 840 SUCCESS, 참가자 10)
HashAggregate (actual time=0.280..0.284 rows=10)
  ->  Index Scan using idx_checkins_challenge_id  (actual time=0.027..0.193 rows=840)
        Index Cond: (challenge_id = 145)
        Filter: status = 'SUCCESS'   Rows Removed by Filter: 360
        Buffers: shared hit=21           -- 디스크 read 0
Execution Time: 0.326 ms

-- (challenge_id, status) 인덱스 추가 후 → 동일 플랜, 새 인덱스 미채택, 0.265ms (노이즈)
-- BREADTH 147 (~200행): Index Scan, hit=9, Execution 0.127 ms
```

**해석**: Seq Scan 아님. 이미 `challenge_id` 인덱스로 접근. `status` 복합 인덱스는 GROUP BY(participant_id 기준)를 도와주지 못해 플래너가 무시. 인덱스 부재·행스캔 비용 가설 **반증**. (실험 인덱스는 분석 후 `DROP` 완료, 테이블 원복 확인.)

---

## 3. 왜 S1만 무너졌나 — 커넥션 보유시간 & 준안정 붕괴

**커넥션 보유시간 산술(Little's Law)**
- 관측 처리량 ≈ 3300–3700 rps, pool=10 → 평균 커넥션 보유시간 ≈ `10 / 3400 ≈ 2.9 ms`.
- 그런데 GROUP BY 쿼리는 **0.3ms**. 즉 보유시간의 **~90%는 DB 실행이 아니다.**
- pg_stat_activity가 이를 직접 확증: 풀 커넥션 대부분이 **idle in transaction (ClientRead)** — 트랜잭션은 열린 채 Postgres가 **앱(클라이언트)의 다음 명령을 기다리는** 상태. 800VU·think-time=0에서 앱 스레드가 CPU 경합/JDBC 왕복/Spring 트랜잭션 관리로 커넥션을 붙들고 있는 시간이 지배적.

**용량 한계(cliff)와 준안정성**
- pool=10 × 보유 ~2.9ms → 용량 상한 ≈ **~3400 rps**. 800VU·think0가 만드는 부하(800 / 0.235s ≈ 3400 rps)가 **정확히 이 상한에 걸침**.
- 이 지점은 준안정: 지속시간이 길거나 GC 일시정지, 혹은 요청당 보유시간이 미세하게만 커져도 → 대기열이 발산 → Hikari `connection-timeout=5000ms` 초과 → 500 에러/타임아웃 **아발란치**. (worker-2의 max 16.7s, 256 timeout = 이 아발란치.)
- **S1(핫 단일키) vs S4(분산)의 차이는 ~8% 보유시간 우열**(핫키는 동일 1200행 위로 모든 요청이 직렬화 + GROUP BY가 소폭 무거움). 준안정 cliff에서 이 8%가 S1을 넘어뜨리고 S4는 아슬하게 버팀. **범주적 DB 차이가 아니라 임계 효과.**
- **S2(TEAM)가 안 무너진 이유**: 쿼리 1개·GROUP BY 없음 → 보유시간이 확연히 짧음 → 용량 상한이 높아 800VU를 견딤. (풀 이론과 정합.)

---

## 4. 병목 분류표

| 후보 병목 | 판정 | 근거 | 처방 |
|---|---|---|---|
| **커넥션 풀 크기 부족(pool=10)** | ✅ **1차 병목** | 용량 상한 ~3400rps가 pool/보유시간으로 결정. 800VU가 정확히 걸침 | **풀 사이징(10→30~50)** |
| **커넥션 보유시간(앱-사이드)** | ✅ **1차 병목(동일 원인축)** | idle-in-transaction 지배, 보유 ~2.9ms 중 DB 0.3ms | 보유시간 단축(쿼리 통합/tx 경계 축소) |
| 쿼리 비용(행 스캔) | ❌ 반증 | 0.326ms, 1200행≈200행 처리량 동일 | (불필요) |
| 인덱스 부재 | ❌ 반증 | 이미 Index Scan, 복합 인덱스 미채택·무개선 | (불필요) |
| 핫키 read 집중(DB 경합) | ❌ 반증 | Lock/LWLock/IO wait=0, MVCC read 무경합, 단일 vs 분산 ~8%차 | (DB단 캐시 불필요) |
| DB 락 | ❌ 없음 | wait_event에 Lock 계열 전무 | — |
| DB CPU/IO | ❌ 아님 | active ≤3/10, buffers 전부 cache hit, read=0 | — |

---

## 5. Redis 판정: **시기상조 / 현 규모 불필요**

**결정 규칙 적용**
- "인덱스로 S1이 살아나면 Redis 시기상조" → 실제로는 인덱스도 레버가 아님. 레버는 **풀 사이징**.
- "인덱스 있어도 핫키 동시성이 풀을 소진시키면 핫 PERSONAL 결과 캐시가 정당" → 풀 소진의 원인은 **핫키 동시성이 아니라 pool=10 자체**(분산 S4도 같은 상한). 핫키 페널티는 ~8%에 불과.
- BREADTH(S4)는 안 무너지므로 **blanket 캐시 불필요**는 확정.

**결론**: Redis는 지금 도입하면 캐시 무효화(체크인 write마다), 신규 장애면, 인프라 복잡도를 추가하면서 **~8%의 핫키 페널티만** 겨냥한다. 지배적 상한(pool)은 훨씬 싸게 제거 가능. → **시기상조.**

**Redis가 정당해지는 조건(미래)**: 풀 사이징 이후에도, (a) 참가자 수가 큰(테스트는 챌린지당 겨우 **10명**) 실제 바이럴 챌린지가 (b) 프로덕션에서 핫키 집중 트래픽으로 sized-pool+DB 처리량을 초과할 때. 그때는 **per-hot-challenge PERSONAL 결과 캐시 + 체크인시 무효화**(분산 키에는 캐시 금지). 규모가 커지면 GROUP BY 결과행·직렬화가 커져 이 케이스가 강해지지만, **현재 증거로는 아직 아님**.

---

## 6. 권장 조치 (우선순위)

1. **[최우선·최저비용] HikariCP `maximum-pool-size` 10 → 30~50 상향.** DB `max_connections=100`, 8 CPU, idle-in-transaction 상태라 여유 충분. 재측정 시 800VU S1 붕괴가 사라질 것으로 예상. (현 `application.yml`에는 `connection-timeout: 5000`만 있고 pool-size 미지정 → 기본 10.)
2. **커넥션 보유시간 단축**: `getPersonalLeaderboard`의 참가자 조회 + GROUP BY 2쿼리 `@Transactional(readOnly=true)` 경계를 재검토(단건 read라 tx 제거 또는 두 쿼리 결합 고려). `open-in-view=false`는 이미 양호.
3. **인덱스**: `(challenge_id, status)`는 현재 GROUP BY에 무익(플래너 미채택) → **추가하지 말 것**. 참가자 수가 크게 늘어 GROUP BY가 무거워지면 그때 재평가.
4. **Redis**: 보류. 1~2 적용·재측정 후, 특정 핫 챌린지(대형 참가자 수)가 DB 처리량을 초과 + 프로덕션 핫키 집중이 확인될 때만 per-challenge 결과 캐시 도입.

**검증 다음 스텝**: pool 상향 후 동일 800VU S1 재현 → 붕괴/타임아웃 소멸 여부로 처방 확정.

---

## 부록: 재현 커맨드 / 아티팩트

- EXPLAIN·pg_stat_activity: `docker exec booster-postgres psql -U booster -d booster`
- 대조 버스트 스크립트: scratchpad `s1-short.js`(400VU 단일키), `collapse800.js`(800VU single|spread MODE)
- 원시 출력: scratchpad `s1-short-k6.out`, `s1-147-k6.out`, `c800-single.out`, `c800-spread.out`
- worker-2 시계열: `docs/monitoring/baselines/sat-{S1,S2,S4}-hikari.log`, `sat-{S1,S2,S4}-k6.json`
- 실험 인덱스 `idx_test_challenge_status`: 생성 후 분석 완료·**DROP 롤백 확인**(테이블 원복 7개 인덱스).
