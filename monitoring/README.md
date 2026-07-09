# 모니터링·부하테스트 도구 (A축)

A축 성능/오류 측정에 쓰는 실행 도구 모음. 측정 결과·보고서 문서는
[`docs/monitoring/`](../docs/monitoring/)에 있다.

## 폴더 구성

| 폴더 | 내용 |
|------|------|
| [`grafana/`](./grafana/) | Grafana 대시보드 + provisioning (데이터소스·대시보드 자동 등록) |
| [`k6/`](./k6/) | k6 부하 시나리오 (`a-axis-load/write/stress/soak-test.js`) |
| [`scripts/`](./scripts/) | 부하테스트용 시드 SQL (`seed-3rd.sql`, `seed-big.sql`) |

관련 설정은 저장소 루트에 있다: `prometheus.yml`, `docker-compose.monitoring.yml`.

## 실행 (저장소 루트에서)

```bash
# 1) 백엔드 실행 (8080, actuator/prometheus 노출)
cd backend && ./gradlew bootRun

# 2) 모니터링 스택 (Prometheus + Grafana 자동 프로비저닝)
docker compose -f docker-compose.monitoring.yml up -d
#   - Grafana:    http://localhost:3000  (admin / admin)
#   - Prometheus: http://localhost:9090

# 3) 부하 (k6 미설치 시 Docker)
docker run --rm -i -e BASE_URL=http://host.docker.internal:8080 \
  -v ${PWD}/monitoring/k6:/scripts grafana/k6 run /scripts/a-axis-load-test.js
```

자세한 절차는 [`docs/monitoring/harness/MONITORING.md`](../docs/monitoring/harness/MONITORING.md) 참고.
