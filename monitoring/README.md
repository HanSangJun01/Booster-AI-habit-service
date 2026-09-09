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
| `b-axis-load.js` | (B) Phase1 멀티 시나리오(normal_load·concurrent_same_user·edge_cases·soak·team_formation) |
| `b-axis-saturation.js` | (B) Phase2 포화(S1~S4, `SCENARIO` env). 리더보드 HOT/TEAM/BREADTH |
| `b-axis-team-detail.js` | (B) Phase2 team-detail 캐시(hot/dist). `b-axis-team-detail-targets.json`을 읽음 |
| `b-axis-team-detail-targets.json` | (B) **생성 데이터** — RT_ 시딩 결과(challenge→앵커 로그인). **수동 편집 금지**, 재시딩 후 `scripts/b-axis-gen-team-detail-targets.sh`로 재생성 |
| `a-axis-realistic.js` | (A) 개인 인증 부하 시나리오 통합 러너 (`SCENARIO=load\|stress\|soak\|write`, 파일 상단 주석에 각 설명·실행법) |
| `integration-realistic.js` | **(A×B)** 통합면 부하 러너 (`SCENARIO=journey\|search\|teamdetail\|contention`). `setup()`이 유저10명+챌린지+팀편성까지 자가시딩. 엔드포인트별 p95를 `ep_*` 메트릭으로 출력 |

## scripts/ — 시딩 · 실행 · 기록
**시딩**
| 파일 | 무엇 |
|---|---|
| `b-axis-seed-saturation.sql` | (B) SAT_ 대량(500챌린지 / 102k 체크인) — 풀 포화 유도용 |
| `b-axis-seed-team-detail.sql` | (B) RT_ 현실(50챌린지 hot/normal, 5:5 팀·GPS·부분 체크인) — 캐시 재검증용 |
| `seed-3rd.sql` / `seed-big.sql` | (A) 부하테스트용 시드 |

**프로브 (A×B 통합면 — 논리 버그)**
| 파일 | 무엇 |
|---|---|
| `probe-integration.sh` | 통합면 논리버그를 한 방씩 찌름(부하 아님, P1~P8): 코인보존·잔액경합·팀채팅 권한·size 클램프·본문길이·응원 ID공간·A/B 체크인 연쇄·actuator 노출. 결과 `[BUG]`/`[OK]`/`[??]` |
| `probe-integration2.sh` | 2차 프로브 — 돈 정합성·동시성·엣지(Q1~Q5): PENDING 취소 환불·동시취소 이중환불·leaderboard 필수파라미터·정원 초과 동시참여·응원 중복. 발견 내역은 [FINDINGS_5차](../docs/monitoring/load-findings/FINDINGS_5차.md) |
| `probe-integration3.sh` | 3차 프로브 — 권한(멤버십)·라이프사이클·정보노출: 조회 API 멤버십 검사 누락, 탈퇴(soft delete)와 진행중 챌린지 연동 공백, 종료 전 정산결과 조회 |
| `probe-frontend-blockers.sh` | 프론트 블로킹 이슈 수정 검증(F1~F10) — 정원 고정·방장 자동참가·참가자 목록·내 챌린지·submissionId·multipart 상한·가입 토큰·에러코드·좀비 인증타입 |
| `probe-weekly-goal.sh` | 주간 목표 모델 전환 후 A축 개인 트랙 HTTP 계약(W1~W12) — 목표 예약·구제권·스트릭 |
| `probe-user-journey.sh` | **여정 프로브(J1~J8)** — 엔드포인트 단위가 아니라 사용자가 앱에서 밟는 순서 그대로 기능을 가로질러 따라간다(온보딩→AI 전환→사진→팀 챌린지→코인 고갈→구제 유예→탈퇴→전역 정합성). 기능 사이 경계의 결함 탐지용 |
| `watch-bugs.sh` | **버그 관측 러너** — 스택 전체를 한 번에 띄우고(`up`), 지표 현재값을 찍고(`status`), 결함을 눈앞에서 재현한다(`demo`). 아래 §버그 관측 참고 |
| `load.sh` | **부하 러너** — k6 를 Docker 로 돌린다(로컬 설치 불필요). `load` / `write` / `stress` / `soak`. 시나리오별로 "무슨 패널을 왜 봐야 하는지"를 실행 전에 안내한다 |

---

## 버그 관측 — 고치기 전에 지켜보기

`probe-user-journey.sh` 가 찾은 결함을 **수정하지 않고** 계속 관측하기 위한 세트. 애플리케이션 코드는 건드리지 않는다.

기존 `a-axis-overview` / `b-axis-overview` 는 "요청이 얼마나 빨랐나"(actuator)를 본다. 이번 결함들은 HTTP 계층에 흔적이 없고 **남은 데이터의 상태**로만 드러나므로(반경이 얼마나 큰가, 벌칙이 몇 번 적용됐나), postgres_exporter 로 DB 를 직접 센다.

| 파일 | 무엇 |
|---|---|
| `postgres-exporter/queries.yaml` | DB → Prometheus 지표 변환 쿼리. `booster_gps_radius_*` / `booster_weekly_penalty_*` / `booster_rescue_*` / `booster_integrity_*` / `booster_shedlock_*` |
| `grafana/dashboards/bug-watch.json` | 대시보드 `booster-bug-watch`. 상단 4개 stat 이 0 이 아니면 그 결함이 실제로 발생 중 |
| `scripts/watch-bugs.sh` | 기동 · 상태 · 재현 · 정리 |

```bash
monitoring/scripts/watch-bugs.sh up      # DB·백엔드·Prometheus·Grafana·exporter 전부 detached
# → Grafana http://localhost:3000/d/booster-bug-watch  (admin/admin)

monitoring/scripts/watch-bugs.sh demo doublepunish   # ★ 구제 만료 이중 처벌 재현
monitoring/scripts/watch-bugs.sh demo radius         # 반경 상한 부재 (시드니에서 인증 통과)
monitoring/scripts/watch-bugs.sh demo badradius      # 반경 검증이 400 대신 409
monitoring/scripts/watch-bugs.sh demo rescue         # 구제 유예 파이프라인

monitoring/scripts/watch-bugs.sh status  # 지표 현재값
monitoring/scripts/watch-bugs.sh reset   # demo 가 만든 demo-*@bugwatch.local 만 삭제
monitoring/scripts/watch-bugs.sh down
```

**핵심 지표 읽는 법**

| 지표 | 정상 | 뜻 |
|---|---|---|
| `booster_weekly_penalty_duplicate_penalty_users` | 0 | 0 이 아니면 같은 날 미달 벌칙이 2회 이상 적용됨 = 구제 만료 중복 실행 |
| `penalty_total` vs `failed_evaluations` | 같음 | 벌어지면 위와 같은 원인 |
| `booster_gps_radius_*_max_meters` | 수백 m | 1km 넘으면 의심, 100km 넘으면 GPS 인증 우회 |
| `booster_rescue_overdue_not_expired` | 하루 내 0 | 계속 남으면 만료 스케줄러(00:10 KST)가 안 돌거나 실패 중 |
| `booster_integrity_*` | 전부 0 | 하나라도 오르면 회귀 |
| `booster_shedlock_age_seconds{name=...}` | — | 여기 나오는 스케줄러만 다중 인스턴스에서 1회 실행. 주간목표 3종이 없는 것이 결함 |

`demo doublepunish` 는 실제 발동 조건(인스턴스 2대 + KST 00:10 + 만료 대상)을 기다릴 수 없으므로, `expireOverdueRescues` 가 내보내는 쓰기를 그대로 두 번 재현한다 — 락을 기다리던 두 번째 인스턴스가 낡은 스냅샷을 보고 또 처리하는 상황.

**러너 · 헬퍼 (B축)**
| 파일 | 무엇 |
|---|---|
| `b-axis-run-scenarios.sh` | Phase1 종합(환경확인→시딩→시나리오 A~H→k6→baseline 저장) |
| `b-axis-run-saturation.sh` | Phase2 포화 1회 실행(k6 + HikariCP 샘플링) → PERFORMANCE-LOG 자동 기록. SAT_ 챌린지 id를 DB에서 자동 해석 |
| `b-axis-gen-team-detail-targets.sh` | `b-axis-seed-team-detail.sql` 적용 후 `k6/b-axis-team-detail-targets.json` 재생성 (id 시퀀스 변동 반영) |
| `b-axis-sample-hikari.sh` | HikariCP 게이지(active/idle/pending/timeout)를 1초마다 폴링해 시계열 기록 |
| `b-axis-log-saturation.sh` | k6 json + HikariCP log에서 관측값 파싱 → PERFORMANCE-LOG 마커에 append |

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
psql -f monitoring/scripts/b-axis-seed-team-detail.sql
monitoring/scripts/b-axis-run-saturation.sh <S1|S3|...> <label> "메모"
```
자세한 절차는 [`docs/monitoring/harness/`](../docs/monitoring/harness/) 참고.
