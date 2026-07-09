# A축 모니터링·검증 문서 인덱스

A축(개인 GPS 습관 인증) 백엔드의 성능·오류·정합성 측정과 검증 산출물을 단계(phase)별로 묶었다.
실제 도구(부하 스크립트·대시보드·시드)는 저장소 루트 [`monitoring/`](../../monitoring/)에 있다.

## 폴더 구성

| 폴더 | 내용 |
|------|------|
| [`harness/`](./harness/) | 측정 환경·실행 가이드 (`MONITORING.md`) |
| [`load-findings/`](./load-findings/) | 초기 부하·성능·오류 발견 (FINDINGS 1~4차) |
| [`verification/`](./verification/) | 출시검증·시나리오리뷰·재검증 (FINDINGS 5·6·7차) |
| [`summary/`](./summary/) | 종합요약, 쉬운 버전, 버그 총정리표 |

## 읽는 순서 (추천)

1. `harness/MONITORING.md` — 무엇을·어떻게 측정하는지
2. `load-findings/FINDINGS_1차.md` → `_4차` — 부하를 주며 발견한 병목·오류
3. `verification/FINDINGS_6차-시나리오리뷰.md` — 확정 버그 7건(동시성·로직)
4. `summary/SUMMARY-종합요약.md` — 전체 종합 (숫자·처방까지)
