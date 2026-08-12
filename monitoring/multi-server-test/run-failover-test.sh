#!/usr/bin/env bash
# =====================================================================
# 멀티서버 Failover 테스트 — Docker 기반 재현 가능한 자동 검증
# =====================================================================
# 검증 대상: 인스턴스 1대가 중지돼도 nginx 로드밸런서가 이를 감지해
#   살아있는 인스턴스로만 트래픽을 보내 서비스가 무중단(zero-downtime)으로 유지된다.
#
# 시나리오:
#   1) 기준선 — 3대가 모두 트래픽을 받는지(분산) 확인
#   2) 장애 — backend-1 강제 중지 후 요청 폭 → 성공률 100% + 죽은 대는 응답 안 함 + 남은 2대만 서빙
#   3) 복구 — backend-1 재기동 → 헬스 UP 후 다시 3대에 합류
#
# 원칙: Spring 메인 코드(src/main/**)는 절대 건드리지 않는다. 오케스트레이션 전용.
#   (읽기 엔드포인트 /actuator/health 만 쓰므로 별도 데이터 시드 불필요)
# 사용: bash monitoring/multi-server-test/run-failover-test.sh
# =====================================================================
set -uo pipefail

COMPOSE="docker-compose.multi.yml"
NGINX_URL="http://localhost:8080/actuator/health"
BACKENDS="booster-backend-1 booster-backend-2 booster-backend-3"
VICTIM="booster-backend-1"
N=60   # 배치당 요청 수

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "  ✅ PASS: $1  (=$2)"; pass=$((pass+1)); else echo "  ❌ FAIL: $1  (got '$2', want '$3')"; fail=$((fail+1)); fi }
ip_of() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1" 2>/dev/null; }

# N개 요청 동시 발사 → 성공(200) 수를 OK_CNT 에, 실제 서빙한 인스턴스 IP 목록을 SERVED 에 담는다.
send_batch() {
  local codes
  codes=$(seq 1 "$N" | xargs -P 12 -I{} curl -s -o /dev/null -w '%{http_code}\n' "$NGINX_URL" 2>/dev/null)
  OK_CNT=$(printf '%s\n' "$codes" | grep -c '^200$')
  # 실제로 응답한 업스트림 = X-Upstream 의 마지막 항목(재시도 시 "죽은IP, 산IP" → 마지막이 서빙한 대)
  SERVED=$(seq 1 "$N" | xargs -P 12 -I{} curl -s -o /dev/null -D - "$NGINX_URL" 2>/dev/null \
            | grep -i '^x-upstream' | tr -d '\r' | awk '{print $NF}')
  DISTINCT=$(printf '%s\n' "$SERVED" | sort -u | grep -c ':')
}

echo "############ 멀티서버 Failover 테스트 ############"

echo "=== [1/5] 멀티 스택 기동 + 3대 health 확인 ==="
docker compose -f "$COMPOSE" up -d >/dev/null 2>&1
for c in $BACKENDS; do
  for _ in $(seq 1 40); do
    docker exec "$c" sh -c 'wget -qO- http://localhost:8080/actuator/health 2>/dev/null' 2>/dev/null | grep -q '"status":"UP"' && break
    sleep 2
  done
done
VICTIM_IP=$(ip_of "$VICTIM")
echo "  3대 UP. 중지 대상 $VICTIM IP=$VICTIM_IP"

echo "=== [2/5] 기준선: 3대가 모두 트래픽을 받는가 ==="
send_batch
echo "  성공 $OK_CNT/$N, 서빙 인스턴스 수=$DISTINCT"
check "기준선 성공률 100%"        "$OK_CNT"   "$N"
check "기준선 서빙 인스턴스 = 3"  "$DISTINCT" "3"

echo "=== [3/5] 장애 주입: $VICTIM 강제 중지 ==="
docker stop "$VICTIM" >/dev/null 2>&1
echo "  $VICTIM STOPPED. 트래픽 폭 발사..."
# nginx max_fails 도달(죽은 대 축출)을 위해 먼저 한 번 흘려보낸 뒤 측정
send_batch >/dev/null 2>&1 || true
send_batch
dead_served=$(printf '%s\n' "$SERVED" | grep -c "$VICTIM_IP")
echo "  성공 $OK_CNT/$N, 서빙 인스턴스 수=$DISTINCT, 죽은대($VICTIM_IP) 서빙=$dead_served"
check "장애 중 성공률 100% (무중단)"       "$OK_CNT"      "$N"
check "죽은 인스턴스가 서빙한 요청 = 0"     "$dead_served" "0"
check "남은 인스턴스만 서빙 = 2"           "$DISTINCT"    "2"

echo "=== [4/5] 복구: $VICTIM 재기동 + health 대기 ==="
docker start "$VICTIM" >/dev/null 2>&1
for _ in $(seq 1 40); do
  docker exec "$VICTIM" sh -c 'wget -qO- http://localhost:8080/actuator/health 2>/dev/null' 2>/dev/null | grep -q '"status":"UP"' && break
  sleep 2
done
sleep 6   # nginx fail_timeout(5s) 경과 대기 → 죽었던 대 재편입 허용
echo "  $VICTIM 재기동 완료"

echo "=== [5/5] 복구 확인: 다시 3대에 분산되는가 ==="
send_batch
echo "  성공 $OK_CNT/$N, 서빙 인스턴스 수=$DISTINCT"
check "복구 후 성공률 100%"        "$OK_CNT"   "$N"
check "복구 후 서빙 인스턴스 = 3"  "$DISTINCT" "3"

echo ""
echo "############ 결과: PASS=$pass  FAIL=$fail ############"
[ "$fail" = "0" ] && echo "🎉 전체 통과 — 1대 중지 중에도 무중단, 복구 시 자동 재편입 실증" || echo "⚠️  실패 있음 — 점검 필요"
exit "$fail"
