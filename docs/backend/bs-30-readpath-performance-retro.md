# BS-30 조회 경로 성능 개선 회고 — 리더보드 · team-detail · 캐시 판단

> 세션 날짜: 2026-07-08 · 브랜치: `test/BS-30-backend-validation-b-axis`
> 관점: 문제해결 사고흐름 (질문 → 측정 → 병목 진단 → 처방 → 검증)
> 한 줄: **"조회가 느린가?"에서 출발해, 성급하게 Redis를 넣는 대신 매 단계 측정으로 병목을 확인하며, 리더보드는 커넥션 풀 사이징으로·team-detail은 로컬 캐시로 — 서로 다른 처방에 도달했다.**

---

## 0. 전체 아크

```
모니터링 뭘 할까? → Redis 어디 적용? → (측정) 다 빠름, 캐시 불필요
  → N+1 발견·수정 → 대규모 포화 테스트(team) → 병목 = 커넥션 풀(캐시 아님!)
  → 풀+점유시간 튜닝(붕괴 소멸) → 리포트 체계화 → B-axis 코어 재조명
  → team-detail 최적화 실패(음성 결과) → 캐시가 답 → 현실 재검증(evict+stampede)
```

핵심 성과는 **두 번의 "성급한 Redis"를 측정으로 막은 것**, 그리고 **같은 "느린 조회"에 서로 다른 처방(풀 vs 캐시)을 내린 것**.

---

## 1. 단계별 상세 (사고흐름)

### 단계 ① — 출발점: "모니터링 → Redis 캐시 적용처 탐색"
- **질문**: 조회 API 중 Redis 캐시가 이득일 곳은?
- **접근**: 코드 탐색 → Redis/캐시 전무(clean slate). 후보 = 리더보드(N+1 의심), team-detail(~8쿼리).
- **측정(단건 baseline, challenge 132, N=50)**: PERSONAL 리더보드 p95 12.8ms, team-detail p95 12.9ms, 나머지 <10ms. **전부 <15ms.**
- **결과/깨달음**: 단건 레이턴시로는 **어떤 것도 캐시가 정당화되지 않음.** "빠른 걸 더 빠르게"는 오버엔지니어링. 대신 리더보드 개인 순위에서 **N+1**(참가자마다 count, 1+N 쿼리) 발견.

### 단계 ② — 개념 정립 (질문 폭발 구간)
- **동시부하 vs 부하**: 트래픽 = 총량(RPS) × 동시성(VU). `RPS ≈ VU / (처리시간 + think-time)`. VU만으론 트래픽 표현 불가.
- **부하 테스트 vs 스트레스 테스트**: 전자는 "예상 트래픽 견디나"(think-time 有), 후자는 "언제 무너지나"(think-time 0).
- **포화 테스트의 산출물**: "느린 곳"이 아니라 **임계점 + 병목 자원**. 평상시 느린 것 ≠ 부하에서 먼저 무너지는 것(공유 자원이 병목).

### 단계 ③ — N+1 수정 + 전후 측정
- **수정**: `getPersonalLeaderboard`의 반복 count → 단일 `GROUP BY` 집계(`countByChallengeIdAndStatusGroupByParticipant`). 11쿼리 → **2쿼리(고정)**.
- **측정(challenge 132)**: p50 9.4→7.8, p95 13.0→10.9. 개선 ~2ms.
- **결과**: 구조적 승리(쿼리가 참가자 수와 무관)지만 **10명 스케일에선 레이턴시 개선 작음.** 효과는 스케일/부하에서 드러남.

### 단계 ④ — `team 3:` 대규모 포화 테스트 (Redis 판단) ⭐ 전환점
- **구성**: AI 3명 파이프라인 — Data(시딩), Load(k6), Bottleneck(분석).
- **데이터**: SAT_ 500챌린지 / 5,000참가자 / **102,307 체크인** (도메인 10명 캡 때문에 "많은 챌린지 + 깊은 히스토리"로 포화 유도).
- **부하(challenge 145, 50→800 VU, think-time 0)**:
  - S1 HOT PERSONAL: p99 572ms, **max 16.7s, connectionTimeout 256 → 붕괴**
  - S2 TEAM(대조군, DB행~0)·S4 BREADTH: 에러 0, 안 무너짐
- **반전**: Load 담당은 "핫키 쿼리비용 → Redis 근거"로 기울었으나, Bottleneck 담당이 실측:
  - `pg_stat_activity`: 커넥션 5~8개가 `idle in transaction`, Lock/IO 대기 0 → **DB는 한가**
  - `EXPLAIN`: 리더보드 GROUP BY는 이미 **Index Scan 0.3ms**(Seq Scan 아님). `(challenge_id,status)` 인덱스 추가해도 플래너가 안 씀 → **인덱스는 레버 아님**
  - 근본 원인 = `application.yml`에 `maximum-pool-size` 미설정 = **기본 10**
- **판정**: **1차 병목 = HikariCP 풀(10) + 앱-사이드 커넥션 점유. Redis 시기상조.** 처방 = 풀 사이징 + 점유시간 단축.
- 산출물: `docs/monitoring/saturation-cache/saturation-redis-verdict.md`

### 단계 ⑤ — 풀 + 점유시간 튜닝 실증 (예측 → 실측)
- **질문들**: "포화→개선이 맞아?" / "점유시간이 왜 길어?" / "자바작업을 트랜잭션 밖에서 해?"
  - 점유시간이 긴 이유: 클래스 레벨 `@Transactional`이 메서드 전체를 감싸 **DB 안 쓰는 시간(왕복 사이·스케줄링 대기)까지 커넥션 점유**.
- **처방 2단계(변수 분리)**:
  - Phase 1 — 풀 10→30: **timeout 256→0, max 16.7s→2.15s, RPS 2,254→3,644 (+62%)** → 붕괴 소멸.
  - Phase 2 — + 점유단축(리더보드 `@Transactional(NOT_SUPPORTED)`): **RPS 4,539(baseline 대비 +101%), p99 572→280ms, max→833ms**.
- **결과**: worker-3 예측("풀만 올려도 붕괴 소멸") **실증**. Redis 없이 **설정·어노테이션 각 한 줄**로 해결.

### 단계 ⑥ — 리포트 파일 관리 체계화 (메타)
- **요구**: "성능 리포트를 계속 파일로 관리하고 싶다."
- **구축**: `docs/monitoring/saturation-cache/PERFORMANCE-LOG.md`(추적되는 누적 로그, 최신순, 작성법 내장) + `run-saturation.sh`/`log-run.sh`(실행/기록 분리 → 기존 결과 파일로 기록 로직 테스트 가능, 실제로 마커 버그를 이걸로 조기 발견).
- **파고든 질문**: "이미 하고 있나?"(절반—baselines는 gitignore), "어떻게 자동 추가?", "왜 스크립트 2개?"(관심사 분리·테스트성), "각 파일에 뭐 들어있어?"(hikari 시계열/k6 집계/stdout), "이름이 왜 달라?"(도구별 규칙 + 조건 인코딩으로 덮어쓰기 방지).

### 단계 ⑦ — "B-axis 중요한 서비스가 뭐야?" → 관점 교정
- **깨달음**: 그동안 최적화한 **리더보드는 `social`(Phase 4b)** — B-axis MVP 범위상 제외 영역. 진짜 코어 = **Challenge(P1)·체크인 GPS인증(P3)·정산(P4a)**.
- **코어 응답속도 측정**: 체크인 write 신규(3-INSERT) p50 **16.3ms**(코어 최고비용), 멱등 반환 5.8ms(BS-30 멱등 방어 효과), team-detail 9.5ms(최고비용 조회), 나머지 2.4~4.3ms.
- **뉘앙스**: 체크인 write는 무겁지만 **하루 1회라 저동시성** → 포화보다 단건 레이턴시가 중요, 16ms면 건강. 부하 위험은 오히려 고빈도 조회(team-detail).

### 단계 ⑧ — team-detail 최적화 시도 → 음성 결과 (정직한 실패)
- **상황/가설**: 코어 응답속도 스윕에서 team-detail이 최고비용 조회(9쿼리)로 나옴 → 부하에서 실제로 무너지는지 확인하고, 리더보드에 통한 처방(쿼리 축소 + 점유단축)을 그대로 적용하면 상한이 오를 것이라 가정.
- **team-detail S3 포화(pool30, 400VU)**: baseline 1,641 rps, p95 303, p99 566, max 1.9s, pending 144 — 붕괴는 안 하나 코어 조회 중 **가장 약함**(리더보드 대비 상한 1/3).
- **처방 시도**: 쿼리 9→7(`team.getParticipationRate()`로 중복 findById 제거) + `NOT_SUPPORTED`. → **결과: 1,568 rps, 개선 없음.**
- **왜**: 쿼리 −2는 DB 시간 미미(0.5ms), 상한은 커넥션 경합이 결정. `NOT_SUPPORTED`는 7쿼리 엔드포인트가 포화 시 **커넥션을 7번 재획득(재큐잉)** → 이득 상쇄/역효과.
- **결정**: **NOT_SUPPORTED 되돌리고 쿼리 −2만 유지**(strict 개선). **교훈: 같은 처방이 보편적이지 않다. team-detail엔 캐시가 답.**

### 단계 ⑨ — 캐시 적용 · 관측 · 결정 (로컬 vs 분산)

**왜 캐시로 왔나**
- ⑧에서 cheap fix(쿼리 −2·점유단축)로 team-detail 상한(~1.6k)이 안 움직였고, 그 상한을 정하는 건 **커넥션 경합**이었음. 캐시 히트는 DB 커넥션을 0개 쓰므로 그 상한을 직접 올릴 수 있음 → **"값싼 튜닝 소진 + 병목이 커넥션" = 캐시가 값어치를 하는 정확한 조건.** (리더보드에선 이 조건이 아니라 캐시가 시기상조였음)

**구현 & 첫 측정 (단일키 S3, `expireAfterWrite(10s)`만)**
- `@Cacheable`(cacheNames `teamDetail`, key `#challengeId + '_' + #userId`) 적용. 단건 히트 ~2ms(무캐시 ~10ms).
- 단일키 S3(145/1000001 고정 난타): **RPS 29,171, 히트율 99.98%**(hit 3,791,778 / miss 791, cache_size=1). 상한 1.6k → **~18배**.

**스스로 제기한 3가지 정직한 단서**
- (a) **99.98%는 best-case** — S3가 단일키만 때려서. 실트래픽은 히트율이 낮아짐.
- (b) **TTL 만료 herd** — miss 791건 = 10초마다 만료 순간 동시 미스 재계산, pending 140까지 순간 튐.
- (c) **stale + 무효화 미완** — 이 시점엔 TTL만 있고 체크인 evict 없음 → 라이브 뷰가 최대 10초 stale (TODO로 표시).

**질문: "왜 grafana엔 이 10초 TTL 만료 pending 스파이크가 안 떠?"**
- **aliasing**: Prometheus 스크레이프 15초 ≫ 스파이크 <1초. 1초 샘플러조차 123샘플 중 **1개만** 포착. 게이지는 순간값이라 스크레이프 사이 peak를 기록 못 함.
- 교훈: **"대시보드에 안 뜬다 ≠ 안 일어났다."** 서버 게이지(grafana) + 클라이언트 꼬리(k6 max)를 겹쳐 봐야 잡힌다 (실제로 이번 herd는 게이지가 대부분 0인데도 k6 max에 흔적이 남음).

**질문: 로컬(Caffeine) vs 분산(Redis)? 실무는 로컬 써?**
- **캐시 fit 4조건**: 읽기 많음 + 히트율 높음 + stale 허용 + 계산 비쌈. team-detail은 **stale 허용이 낮음**(라이브 뷰 → 짧은 TTL → 히트율 상한).
- **사다리**: 로컬(Caffeine, in-process·나노초·무인프라) → 분산(Redis, 공유·일관 무효화·네트워크 홉) → CDN. 실무는 흔히 **L1 로컬 + L2 Redis 2단(near cache)** — 로컬도 진지한 인프라.
- **결정 요인 = 인스턴스 수 + 무효화**: 단일 인스턴스면 로컬 압승(Redis는 순 오버헤드). 멀티 인스턴스 + 라이브 뷰면 evict를 인스턴스 간 전파해야 하니 분산(또는 하이브리드).
- **결정**: 현 단일 인스턴스 → **Caffeine 로컬** 채택. Redis는 수평 확장 시 승격 카드로 보류.
- **`refreshAfterWrite`란**: 만료 herd(엔트리 삭제 → 블로킹 미스 몰림)를 **"stale 즉시 반환 + 단일 비동기 갱신"** 으로 대체. 트레이드오프: 갱신 중 약간 stale, loader 필요. **evict(쓰기 즉시 삭제→최신)와 역할 분담** — 쓰기는 evict로 정확, 읽기 노화는 refresh로 herd 제거.

### 단계 ⑩ — 현실 재검증 (4파트 통합)

**왜**: 단일키 S3의 99.98% 히트는 인공적 → 현실 데이터·mixed-key로 진짜 히트율·evict·stampede를 검증. 독립 빌드 작업(시딩·k6)은 병렬 에이전트에 위임, evict 구현은 직접(정확성 중요).

**① 현실 시딩 (`RT_` prefix)**
- 50 ACTIVE 챌린지(hot 10=20% / normal 40=80%), 각 10명 CONFIRMED **5:5 팀**, **GPS 등록**(체크인 성공 위해 필수), 오늘 부분 체크인 223건(3~6/챌린지). user_id = `3000000 + offset*10 + memberIndex`, `RT_` prefix로 cleanup 가능.
- k6용 `rt-targets.json`(challenge → userIds 매핑) 생성.

**② mixed-key 부하 (`team-detail-realistic.js`, ramp 50→400)**
- **hot**: 10개 hot 챌린지 내 랜덤(=100키) → RPS 26,030, 히트율 99.91%, pending 0.
- **dist**: 20% hot / 80% normal(=500키) → RPS 22,512, 히트율 99.66%, **pending 144**.
- (히트율이 dist에서도 왜 거의 안 떨어졌는지는 아래 **정직한 발견** 참고.)

**③ evict-on-checkin**
- **설계**: 캐시 키가 `challengeId_userId`인데, 한 명 체크인이 **양 팀 모두의 뷰**를 바꿈 → 챌린지의 **모든 키**를 evict해야 함. Spring `@CacheEvict`은 와일드카드 미지원 → 네이티브 Caffeine 맵에서 `challengeId_` prefix로 제거(`TeamDetailCacheEvictor`). `CheckInOrchestrator`에서 `recordCheckIn` **커밋 후** 호출(커밋 전 evict는 동시 조회가 stale 재적재 위험).
- **정확성 검증**: 캐시 채움(합계 4·hit 2.5ms) → 미체크 멤버 체크인(SUCCESS) → 재조회 = **hard miss(19ms, miss 카운터 +1)** → 합계 **4→5 최신 반영**. (LoadingCache 전환 후에도 재검증)
- **비용**: 체크인+evict p50 **14.3ms** ≈ evict 없던 ~16ms → **무시 가능**(evict = 캐시 키 스캔+삭제, 마이크로초). 단 O(캐시 크기) — 10k 상한에도 빠르나 대규모면 보조 인덱스 고려(현재 불필요).

**④ stampede + refreshAfterWrite**
- **관측(evict 후 dist 재확인)**: `expireAfterWrite`만 → dist pending 144, active 30(풀 순간 포화), miss 9,060, max 938ms.
- **처방**: `refreshAfterWrite(10s)` + `expireAfterWrite(60s)`, LoadingCache + CacheLoader(키 파싱 → `computeTeamComparison` 재계산).
- **구현 함정(잡은 버그)**: refreshAfterWrite는 LoadingCache 필수 → `setCacheLoader`를 `setCaffeine`보다 **먼저** 호출해야 함. 순서가 뒤바뀌어 기동 시 `refreshAfterWrite requires a LoadingCache` 예외 → 순서 수정. 계산 로직을 `computeTeamComparison`(비캐시)로 분리해 @Cacheable 미스 경로와 loader가 공용 호출.
- **결과**: **pending 144→0, active 30→7, miss 9,060→498, RPS 22,512→27,367, p99 31→19ms, max 938→246ms**.
- **판단**: 복잡한 분산락/single-flight는 에러 0이라 오버킬 → **refreshAfterWrite(설정 두 줄)로 충분**.

| 시나리오 | 히트율 | RPS | p95 | p99 | pending |
|---|---|---|---|---|---|
| 무캐시(S3) | 0% | 1,641 | 303 | 566 | 169 |
| hot(100키) | 99.91% | 26,030 | 12.2 | 19.2 | 0 |
| dist(500키, expire) | 99.66% | 22,512 | 17.0 | 31.1 | 144 |
| dist(500키, +refresh) | 99.98% | 27,367 | 12.5 | 19.4 | 0 |

- **정직한 발견**: 포화 부하는 500키도 다 warm 유지 → hot/dist 히트율 차이 미미(99.9%대). **진짜 히트율 저하는 포화가 아닌 실트래픽 분포(Zipfian·저RPS·cold-tail)로만 재현 가능.** 이번 검증이 증명한 건 "용량"이지 "현실 히트율"이 아님.

---

## 2. 흐름 속 궁금증 → 도달한 답

| 궁금증 | 답 |
|---|---|
| 동시부하가 트래픽 고려? | 트래픽의 한 축(동시성). think-time·분포도 필요 |
| 포화 테스트 = 느린 곳 찾기? | 아니 — 임계점 + 병목 자원 찾기 |
| 커넥션 점유시간이 왜 길어? | 트랜잭션이 메서드 전체를 감싸 DB 안 쓰는 시간도 점유 |
| 자바작업 트랜잭션 밖에서? | 외부호출·느린작업은 무조건, 가벼운 정렬은 측정된 핫스팟만 |
| grafana에 pending 왜 안 떠? | 15초 스크레이프가 <1초 스파이크를 못 봄(aliasing) |
| Caffeine vs Redis, 실무는? | 단일=로컬, 멀티+일관성=분산. 로컬도 매우 흔함(2단 캐시) |
| refreshAfterWrite가 뭐야? | 만료 herd → stale 반환 + 단일 비동기 갱신 |

---

## 3. 관통한 문제해결 원칙

1. **측정 없이 처방하지 않는다** — "Redis부터"가 아니라 "병목부터". 두 번의 성급한 Redis를 막음.
2. **같은 처방이 보편적이지 않다** — 리더보드=풀 사이징, team-detail=캐시. 병목 진단이 처방을 정한다.
3. **음성 결과도 성과다** — team-detail 미세최적화 실패·Redis 시기상조가 방향을 잡아줌.
4. **독립 검증의 힘** — 부하 담당(Redis?)을 분석 담당(풀!)이 뒤집음. 혼자였으면 성급히 Redis.
5. **값싼 사다리부터** — 쿼리 → 인덱스 → 풀 → 회복력 → 캐시 → 아키텍처. 위에서 풀리면 아래로 안 감.
6. **관측의 한계를 안다** — grafana aliasing, "포화 테스트는 용량이지 현실 히트율이 아님".
7. **정확성과 성능을 분리해 검증** — 캐시는 evict로 정확성, refreshAfterWrite로 herd 제거. 각각 실측.

---

## 4. 최종 결과물

### 코드 (커밋, 원격 푸시 완료)
| 대상 | 처방 | 효과 |
|---|---|---|
| 리더보드 개인 순위 | N+1 제거(11→2쿼리) | 구조적, 스케일에서 효과 |
| 조회 전반(공유) | HikariCP 풀 10→30 | 붕괴 소멸, RPS 2,254→3,644 |
| 리더보드 | 점유시간 단축(NOT_SUPPORTED) | RPS→4,539(2배), 꼬리 개선 |
| team-detail | 중복 team 재조회 제거(9→7) | DB 왕복 감소(상한 불변) |
| team-detail | Caffeine 캐시 + evict + refreshAfterWrite | 상한 1.6k→27k(~16x), stampede 제거 |

### 판정
- **리더보드 = Redis 불필요** (병목이 풀 → 풀 사이징으로 해결)
- **team-detail = 캐시가 정답** (cheap fix로 상한 불변 → 캐시로 16배). 단일 인스턴스는 Caffeine, 멀티 인스턴스 확장 시 Redis 승격.

### 자산 (재사용 가능)
- 포화 테스트 하네스: `monitoring/scripts/seed-saturation.sql`, `seed-realistic-teamdetail.sql`, `monitoring/k6/saturation-test.js`, `team-detail-realistic.js`, `run-saturation.sh`/`log-run.sh`
- 버전관리 성능 로그: `docs/monitoring/saturation-cache/PERFORMANCE-LOG.md`
- 판정 리포트: `docs/monitoring/saturation-cache/saturation-redis-verdict.md`, 시나리오 매트릭스

---

## 5. 남은 과제 / 열린 항목

- **현실 히트율 실측**: 포화가 아닌 실트래픽 분포(Zipfian) 모델로 team-detail 캐시 히트율 재검증.
- **멀티 인스턴스 대비**: 로컬 캐시 evict는 인스턴스 간 전파 안 됨 → 수평 확장 시 Redis(공유 캐시/pub-sub) 승격.
- **B-axis 코어 검증 확대**: 체크인 write·정산 흐름의 부하/정합성(지금까진 조회 위주).
- **테스트 데이터 정리**: SAT_(102k행)·RT_(50챌린지) cleanup.
