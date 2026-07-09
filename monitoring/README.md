# monitoring/

백엔드 성능·부하 테스트 **도구** 모음 (A축 + B축 통합). 재사용 자산이라 **종류별**(grafana / k6 / scripts)로 둔다.
(측정 **결과·문서**는 [`docs/monitoring/`](../docs/monitoring/) 참고 — 거긴 phase별 내러티브.)

## grafana/ — 대시보드
모니터링 스택 기동 시 `provisioning/`이 데이터소스(Prometheus)와 `dashboards/` 폴더의 대시보드를
**자동 등록**한다(import 클릭 불필요). Grafana 폴더 "Booster" 아래에 A/B축 둘 다 뜬다.

| 파일 | 무엇 |
|---|---|
| `dashboards/a-axis-overview.json` | A축 개요 대시보드 (자동 로드) |
| `dashboards/b-axis-overview.json` | B축 대시보드(21패널: 핵심지표·JVM·HTTP·DB 커넥션 등, 자동 로드) |
| `provisioning/datasources/datasource.yml` | Prometheus 데이터소스(uid=`prometheus`) 자동 등록 |
| `provisioning/dashboards/dashboards.yml` | `dashboards/` 폴더를 읽는 provider 설정 |

## k6/ — 부하 스크립트
| 파일 | 무엇 |
|---|---|
| `load-test.js` | (B) Phase1 멀티 시나리오(normal_load·concurrent_same_user·edge_cases·soak·team_formation) |
| `saturation-test.js` | (B) Phase2 포화(S1~S4, `SCENARIO` env). 리더보드 HOT/TEAM/BREADTH |
| `team-detail-realistic.js` | (B) Phase2 team-detail 캐시(hot/dist). `rt-targets.json`을 읽음 |
| `rt-targets.json` | (B) **생성 데이터** — RT_ 시딩 결과(challenge→userIds). 재시딩하면 갱신 |
| `a-axis-load-test.js` / `a-axis-write-load-test.js` / `a-axis-stress-test.js` / `a-axis-soak-test.js` | (A) 개인 인증 부하/쓰기/스트레스/소크 시나리오 |

## scripts/ — 시딩 · 실행 · 기록
**시딩**
| 파일 | 무엇 |
|---|---|
| `seed-saturation.sql` | (B) SAT_ 대량(500챌린지 / 102k 체크인) — 풀 포화 유도용 |
| `seed-realistic-teamdetail.sql` | (B) RT_ 현실(50챌린지 hot/normal, 5:5 팀·GPS·부분 체크인) — 캐시 재검증용 |
| `seed-3rd.sql` / `seed-big.sql` | (A) 부하테스트용 시드 |

**러너 · 헬퍼 (B축)**
| 파일 | 무엇 |
|---|---|
| `run-all-scenarios.sh` | Phase1 종합(환경확인→시딩→시나리오 A~H→k6→baseline 저장) |
| `run-saturation.sh` | Phase2 포화 1회 실행(k6 + HikariCP 샘플링) → PERFORMANCE-LOG 자동 기록 |
| `sample-hikari.sh` | HikariCP 게이지(active/idle/pending/timeout)를 1초마다 폴링해 시계열 기록 |
| `log-run.sh` | k6 json + HikariCP log에서 관측값 파싱 → PERFORMANCE-LOG 마커에 append |

## 실행 (저장소 루트에서)
```bash
# 1) 백엔드 기동 (8080, actuator/prometheus 노출)
cd backend && ./gradlew bootRun

# 2) 모니터링 스택 (Prometheus + Grafana 자동 프로비저닝)
docker compose -f docker-compose.monitoring.yml up -d
#   - Grafana:    http://localhost:3000  (admin / admin)
#   - Prometheus: http://localhost:9090

# 3) 부하 예 (B축 포화)
#    시딩 → 포화 실행(자동 기록)
psql -f monitoring/scripts/seed-realistic-teamdetail.sql
monitoring/scripts/run-saturation.sh <S1|S3|...> <label> "메모"
```
자세한 절차는 [`docs/monitoring/harness/`](../docs/monitoring/harness/) 참고.
