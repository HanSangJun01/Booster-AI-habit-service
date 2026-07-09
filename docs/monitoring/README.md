# docs/monitoring

백엔드 성능·모니터링·검증 문서 (A축 + B축). 실제 도구(부하 스크립트·대시보드·시드)는
저장소 루트 [`monitoring/`](../../monitoring/)에 있다.

## 구조

| 폴더 | 무엇 |
|---|---|
| `harness/` | 테스트 하네스(**공유 도구**) — 사용 가이드(`MONITORING.md` 등) + 실행 이력 |
| `baseline-monitoring/` | **(B) Phase 1** 초기 happy-path 모니터링 (`b-axis-monitoring-validation-plan.md` → `week1-baseline.md`) |
| `saturation-cache/` | **(B) Phase 2** 포화·캐시 (`saturation-scenario-matrix.md` → `PERFORMANCE-LOG.md` + `saturation-redis-verdict.md`) |
| `load-findings/` | **(A)** 초기 부하·성능·오류 발견 (FINDINGS 1~4차) |
| `verification/` | **(A)** 출시검증·시나리오리뷰·재검증 (FINDINGS 5·6·7차) |
| `summary/` | **(A)** 종합요약·쉬운버전·버그 총정리표 |
| `baselines/` | 원시 실행 출력(k6 json, HikariCP log). **gitignore**, 로컬 전용 |

## 읽는 순서

**B축 (챌린지/정산 read-path)**
- `baseline-monitoring/` → `saturation-cache/PERFORMANCE-LOG.md` (누적, 최신순)
- 세션 회고: `docs/backend/bs-30-readpath-performance-retro.md`

**A축 (개인 GPS 습관 인증)**
1. `harness/MONITORING.md` — 무엇을·어떻게 측정하는지
2. `load-findings/FINDINGS_1차.md` → `_4차` — 부하 병목·오류
3. `verification/FINDINGS_6차-시나리오리뷰.md` — 확정 버그(동시성·로직)
4. `summary/SUMMARY-종합요약.md` — 전체 종합
