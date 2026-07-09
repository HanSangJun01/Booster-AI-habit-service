# docs/monitoring

B-axis 백엔드 성능·모니터링 문서. **참조 세트(phase)별로 묶여** 있고, 각 phase는 `[계획 → 결과]` 한 세트다.

## 구조

| 폴더 | 무엇 |
|---|---|
| `harness/` | 테스트 하네스(**공유 도구**) — 사용 가이드 + 실행 이력. 두 phase가 함께 씀 |
| `baseline-monitoring/` | **Phase 1** (초기 happy-path 모니터링) |
| `saturation-cache/` | **Phase 2** (포화·캐시 — 이번 세션) |
| `baselines/` | 원시 실행 출력(k6 json, HikariCP log). **gitignore**, 로컬 전용 |

## 각 phase = 계획 → 결과

| phase | 계획 | 결과 |
|---|---|---|
| `baseline-monitoring/` | `b-axis-monitoring-validation-plan.md` (시나리오 A~H) | `week1-baseline.md` |
| `saturation-cache/` | `saturation-scenario-matrix.md` (시나리오 S1~S6) | `PERFORMANCE-LOG.md` (누적 로그) + `saturation-redis-verdict.md` (판정) |

- **누적 성능 로그**: `saturation-cache/PERFORMANCE-LOG.md` — 측정 라운드마다 최신순으로 쌓음. `monitoring/scripts/run-saturation.sh`(실행+기록) / `log-run.sh`(기록)로 자동 append.
- **원시 vs 요약**: 원시 출력은 `baselines/`(gitignore), 사람이 읽는 요약·판정은 위 문서들(추적).
- 세션 전체 문제해결 회고는 `docs/backend/bs-30-readpath-performance-retro.md`.
