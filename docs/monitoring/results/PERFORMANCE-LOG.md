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
