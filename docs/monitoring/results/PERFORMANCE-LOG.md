# B-axis 성능 측정 누적 로그

> **최신 항목이 맨 위.** 측정 라운드마다 아래 "작성 방법"에 따라 새 블록을 상단에 추가한다.
> 원시 출력(k6 json, HikariCP log)은 `docs/monitoring/baselines/`(gitignore)에 두고, 여기엔 **요약·결론만** 남긴다.
> 상세 판정은 [`../saturation-redis-verdict.md`](../saturation-redis-verdict.md), 시나리오 설계는 [`../plans/saturation-scenario-matrix.md`](../plans/saturation-scenario-matrix.md) 참고.

## 작성 방법
- 새 측정을 하면 이 파일의 **`---` 구분선 바로 아래(가장 최근 항목 위)** 에 새 블록을 끼워넣는다.
- **방법 1 (권장):** Claude에게 *"이번 측정 결과를 성능 로그에 추가해줘"* → 자동으로 아래 템플릿 형식으로 정리·삽입.
- **방법 2 (수동):** 아래 템플릿을 복사해 값을 채운다.
- **방법 3 (자동):** `monitoring/scripts/run-saturation.sh <SCENARIO> <LABEL> [메모]` 실행 → k6 포화 + HikariCP 샘플링 후 관측값 블록을 아래 `AUTO-LOG-INSERT` 마커 바로 밑에 자동 삽입. (기존 결과 파일만 다시 기록하려면 `monitoring/scripts/log-run.sh <k6.json> <hikari.log> "<제목>"`)
- 원칙: **무엇을 바꿨나(변경) → 어떻게 쟀나(조건) → 숫자(표) → 해석 한두 줄.** 원시 파일 경로도 남겨 재현 가능하게.

### 템플릿
```
## YYYY-MM-DD — <제목: 무엇을 측정/변경했나>
- **변경**: <이번에 바꾼 것 / 없으면 "측정만">
- **조건**: <엔드포인트, 부하 도구·VU, 데이터 규모, 대상 challenge_id>
- **원시**: <docs/monitoring/baselines/... 경로>

| 지표 | before | after |
|---|---|---|
| ... | ... | ... |

**해석**: <한두 줄 결론>
```

---

<!-- AUTO-LOG-INSERT -->

## 2026-07-08 — team-detail Caffeine 캐시 현실 재검증 + evict + refreshAfterWrite
- **변경**: team-detail에 Caffeine 로컬 캐시(@Cacheable) + 체크인 시 챌린지 단위 evict(`TeamDetailCacheEvictor`) + `refreshAfterWrite(10s)`/`expireAfterWrite(60s)`(stampede 완화, LoadingCache+CacheLoader).
- **조건**: 현실 데이터 RT_ 50챌린지(hot 10/normal 40, 10명 5:5, 부분 체크인). k6 mixed-key(`team-detail-realistic.js`) ramp 50→400. 무캐시 기준선은 S3(1,641 rps).
- **원시**: `baselines/tdr-{hot,dist,dist-noref}-*`

| 시나리오 | 히트율 | RPS | p95 | p99 | pending peak |
|---|---|---|---|---|---|
| 무캐시 (S3) | 0% | 1,641 | 303 | 566 | 169 |
| hot (100키) | 99.91% | 26,030 | 12.2 | 19.2 | 0 |
| dist (500키, expire만) | 99.66% | 22,512 | 17.0 | 31.1 | **144** |
| dist (500키, +refresh) | 99.98% | 27,367 | 12.5 | 19.4 | **0** |

- **캐시 효과**: 현실 mixed-key에서도 무캐시 대비 ~14~16배 RPS. 단 **포화 부하는 모든 키를 warm 유지**해 hot·dist 히트율 차이가 거의 없음(99.9%대) — 진짜 히트율 저하는 포화가 아닌 **실트래픽 분포(Zipfian·저RPS·cold-tail)** 로만 재현 가능. 이번 검증이 증명한 건 "용량"이지 "현실 히트율"이 아님.
- **evict**: 체크인 후 재조회가 hard miss로 최신 반영(합계 +1, miss 카운터 +1) 확인. evict 비용 무시 가능(체크인 p50 14.3ms, evict 없던 것과 동일).
- **stampede**: expireAfterWrite만일 때 dist에서 pending 144 순간 스파이크(만료 herd). `refreshAfterWrite`로 stale 반환+단일 비동기 갱신 → **pending 0, active 30→7, hard miss 9060→498**. 복잡한 분산락 불필요.

**해석**: team-detail은 캐시가 정답(cheap fix로 안 오르던 상한을 ~16배로). evict로 정확성, refreshAfterWrite로 herd 제거까지 완성. 멀티 인스턴스 확장 시 evict 전파 위해 Redis 승격 검토.

## 2026-07-08 — 포화 S3 (cache): Caffeine 로컬캐시 TTL10s
- **자동 기록** (log-run.sh) · 원시: `docs/monitoring/baselines/sat-S3-cache-k6.json` · `docs/monitoring/baselines/sat-S3-cache-hikari.log`

| 관측값 | 값 |
|---|---|
| RPS | 29,171/s |
| 총 요청 | 3,792,565 |
| 에러율 | 0.00% |
| p50 / p95 / p99 | 3.0 / 12.2 / 18.8 ms |
| max (꼬리) | 158ms |
| HikariCP active / pending peak | 30 / 140 |
| 신규 connectionTimeout | 0 |


## 2026-07-08 — 포화 S3 (td-opt): team-detail 최적화(9→7쿼리+점유단축)
- **자동 기록** (log-run.sh) · 원시: `docs/monitoring/baselines/sat-S3-td-opt-k6.json` · `docs/monitoring/baselines/sat-S3-td-opt-hikari.log`

| 관측값 | 값 |
|---|---|
| RPS | 1,568/s |
| 총 요청 | 204,178 |
| 에러율 | 0.00% |
| p50 / p95 / p99 | 55.1 / 320.6 / 561.5 ms |
| max (꼬리) | 2019ms |
| HikariCP active / pending peak | 30 / 169 |
| 신규 connectionTimeout | 0 |


## 2026-07-08 — 포화 S3 (baseline): team-detail 코어 포화(풀30)
- **자동 기록** (log-run.sh) · 원시: `docs/monitoring/baselines/sat-S3-baseline-k6.json` · `docs/monitoring/baselines/sat-S3-baseline-hikari.log`

| 관측값 | 값 |
|---|---|
| RPS | 1,641/s |
| 총 요청 | 213,612 |
| 에러율 | 0.00% |
| p50 / p95 / p99 | 53.3 / 303.3 / 566.0 ms |
| max (꼬리) | 1895ms |
| HikariCP active / pending peak | 30 / 169 |
| 신규 connectionTimeout | 0 |


## 2026-07-08 — B-axis 코어 응답속도 스윕 (단건: 조회 + 체크인 write)
- **변경**: 없음 (측정만). 현재 백엔드 = 풀30 + N+1수정 + 점유단축 반영본.
- **조건**: warmed 단건, N=50(조회)/70(체크인 신규). challenge 145(hot). 체크인은 GPS 등록한 ACTIVE SAT 참가자 대상, 서로 다른 (challenge,user) 각 1회.
- **원시**: 세션 curl 측정 (`scratchpad/sweep.sh`, `measure-checkin.sh`)

| Phase | 오퍼레이션 | 유형 | p50 | p95 | p99 |
|---|---|---|---|---|---|
| P3 | 체크인 write (신규, GPS 3-INSERT) | write | 16.3 | 29.4 | 37.4 |
| P3 | 체크인 write (멱등 반환) | write | 5.8 | 8.0 | 8.4 |
| P3 | team-detail | read | 9.5 | 12.9 | 15.1 |
| P1 | challenge 상세 | read | 4.3 | 7.8 | 8.0 |
| P1 | challenge 목록 | read | 4.0 | 8.4 | 9.0 |
| P3 | check-ins 조회 | read | 3.8 | 7.2 | 8.6 |
| P4a | 정산 result | read | 2.9 | 7.1 | 8.8 |
| P1/3 | teams | read | 2.4 | 5.7 | 6.9 |

**해석**: 코어 최고비용 = 체크인 write 신규(GPS 3-INSERT ~16ms). 단, 하루 1회라 저동시성 → 포화보다 단건 레이턴시가 중요하고 16ms면 건강. 멱등 반환은 1/3(~6ms, BS-30 3중 멱등 방어 효과). 조회 중엔 team-detail이 최고비용(8쿼리). 전부 절대값은 건강(write<30ms, read<15ms). 참고: 리더보드는 `social`(P4b)로 B-axis 코어 범위 밖.

## 2026-07-08 — 리더보드 커넥션 풀 사이징 + 점유시간 단축 (포화 재측정)
- **변경**: ① HikariCP `maximum-pool-size` 10→30 (`application.yml`) ② `LeaderboardService.getPersonalLeaderboard`를 `@Transactional(NOT_SUPPORTED)`로 전환(트랜잭션 밖 실행 → 커넥션 점유시간 단축)
- **조건**: k6 포화 S1(HOT PERSONAL, `/145/leaderboards?type=PERSONAL`), think-time 0, ramp 50→800 VU ~2m40s. 데이터: challenge 145(참가자 10·체크인 1200). stub 프로파일.
- **원시**: `baselines/sat-S1-k6.json`(baseline), `sat-S1-pool30-*`, `sat-S1-pool30-hold-*`

| 지표 | baseline (풀 10) | 풀 30 | 풀 30 + 점유단축 |
|---|---|---|---|
| connectionTimeout | **256 (붕괴)** | 0 | 0 |
| 에러율 | 0.07% | 0.00% | 0.00% |
| RPS | 2,254 | 3,644 | **4,539** |
| p95 | 364ms | 233ms | **180ms** |
| p99 | 572ms | 411ms | **280ms** |
| max (꼬리) | **16.7s** | 2.15s | **0.83s** |
| pending peak | ~189 | 169 | 170 |

**해석**: 1차 병목은 **커넥션 풀(기본 10)**. 풀 30으로 붕괴 소멸(timeout 256→0, max 16.7s→2.15s, RPS +62%). 여기에 점유시간 단축을 얹어 RPS 누적 +101%(2배)·p99 -32%·꼬리(max) -61%. **Redis 없이 설정·어노테이션 각 한 줄로 해결** — team 판정(Redis 시기상조) 실증됨.

---

## 2026-07-08 — 리더보드 개인 N+1 제거 (11→2 쿼리)
- **변경**: `getPersonalLeaderboard`의 참가자별 반복 count(1+N)를 단일 GROUP BY 집계로 교체 (`countByChallengeIdAndStatusGroupByParticipant`)
- **조건**: 단건 응답시간, curl N=50 warmup 5, challenge 132(참가자 10). (`scratchpad/baseline.sh`)
- **원시**: 세션 측정(미보존) — 재현은 baseline.sh

| 지표 | before (11쿼리) | after (2쿼리) |
|---|---|---|
| 요청당 쿼리 수 | 11 (1+N) | **2 (고정)** |
| p50 | 9.4~9.9ms | 7.8ms |
| p95 | 12.8~13.0ms | 10.9ms |
| p99 | 14.0ms | 13.8ms |

**해석**: 구조적 승리(쿼리 참가자수 무관 고정)지만, 10명 스케일에선 단건 레이턴시 개선 ~2ms로 작음. 효과는 부하/스케일에서 드러남(위 포화 항목 참고). 동작 보존(count DB 실측 일치).

---

## 이전 기준선 (2026-07-02, 지난 세션)
- 1주차 성능 기준선 4종은 `docs/monitoring/history/week1-baseline.md`(추적됨) 및 `baselines/baseline-2026-07-02-*.md`(gitignore, 로컬 전용)에 있음.
- 당시엔 참가자 10명 happy-path 단건 측정 위주 — 포화/병목 분석은 2026-07-08 라운드에서 처음 수행.
