# monitoring/

B-axis 백엔드 성능·부하 테스트 **도구** 모음. 재사용 자산이라 **종류별**(grafana / k6 / scripts)로 둔다.
(측정 **결과·문서**는 [`docs/monitoring/`](../docs/monitoring/) 참고 — 거긴 phase별 내러티브.)

## grafana/ — 대시보드
| 파일 | 무엇 |
|---|---|
| `booster-baxis-dashboard-import.json` | B-axis 대시보드(21패널: 핵심지표·JVM·HTTP·DB 커넥션 등). Grafana에 import해서 사용 |

## k6/ — 부하 스크립트
| 파일 | 무엇 |
|---|---|
| `load-test.js` | Phase1 멀티 시나리오(normal_load·concurrent_same_user·edge_cases·soak·team_formation) |
| `saturation-test.js` | Phase2 포화(S1~S4, `SCENARIO` env). 리더보드 HOT/TEAM/BREADTH |
| `team-detail-realistic.js` | Phase2 team-detail 캐시(hot/dist, `SCENARIO` env). `rt-targets.json`을 읽음 |
| `rt-targets.json` | **생성 데이터**(스크립트 아님) — RT_ 시딩 결과(challenge→userIds). `team-detail-realistic.js`의 입력. 재시딩하면 갱신 |

## scripts/ — 시딩 · 실행 · 기록
**시딩**
| 파일 | 무엇 |
|---|---|
| `seed-saturation.sql` | SAT_ 대량(500챌린지 / 102k 체크인) — 풀 포화 유도용 |
| `seed-realistic-teamdetail.sql` | RT_ 현실(50챌린지 hot/normal, 5:5 팀·GPS·부분 체크인) — 캐시 재검증용 |

**러너**
| 파일 | 무엇 |
|---|---|
| `run-all-scenarios.sh` | Phase1 종합(환경확인→시딩→시나리오 A~H→k6→baseline 저장) |
| `run-saturation.sh` | Phase2 포화 1회 실행(k6 + HikariCP 샘플링) → PERFORMANCE-LOG 자동 기록 |

**헬퍼**
| 파일 | 무엇 |
|---|---|
| `sample-hikari.sh` | HikariCP 게이지(active/idle/pending/timeout)를 1초마다 폴링해 시계열 기록 |
| `log-run.sh` | k6 json + HikariCP log에서 관측값 파싱 → PERFORMANCE-LOG 마커에 append |

## 실행 순서 (Phase2 포화·캐시 예)
```
1. 백엔드 기동(dev/stub) + docker-compose.monitoring.yml (Prometheus·Grafana)
2. 시딩:   psql -f scripts/seed-realistic-teamdetail.sql   (또는 seed-saturation.sql)
3. 포화:   scripts/run-saturation.sh <S1|S3|...> <label> "메모"   → 자동 기록
4. 결과:   docs/monitoring/saturation-cache/PERFORMANCE-LOG.md 에 요약, baselines/ 에 원시
```
