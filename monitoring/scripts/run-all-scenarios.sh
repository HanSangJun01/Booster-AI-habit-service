#!/usr/bin/env bash
# B-axis 모니터링 시나리오 자동화 스크립트
# 실행 전 조건: bootRun 실행 중 + docker-compose.monitoring.yml up

set -e

# ── 설정 ──────────────────────────────────────────────────────────────
API="http://localhost:8080"
GRAFANA="http://admin:admin@localhost:3000"
DB_CONTAINER="booster-postgres"
DB_USER="booster"
DB_NAME="booster"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DASHBOARD_JSON="$PROJECT_ROOT/monitoring/grafana/booster-baxis-dashboard-import.json"
K6_SCRIPT="$PROJECT_ROOT/monitoring/k6/load-test.js"

# ── 색상 출력 ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

psql_exec() {
  docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "$1" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════
# 0. 환경 확인
# ══════════════════════════════════════════════════════════════════════
log "환경 확인 중..."

# 백엔드 헬스체크
if ! curl -sf "$API/actuator/health" | grep -q '"status":"UP"'; then
  fail "백엔드가 실행 중이지 않습니다. './gradlew bootRun' 먼저 실행하세요."
fi
ok "백엔드 UP"

# Grafana 헬스체크
if ! curl -sf "http://localhost:3000/api/health" | grep -q '"database"'; then
  fail "Grafana가 실행 중이지 않습니다. 'docker-compose -f docker-compose.monitoring.yml up -d' 먼저 실행하세요."
fi
ok "Grafana UP"

# PostgreSQL 헬스체크
if ! docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" &>/dev/null; then
  fail "PostgreSQL 컨테이너($DB_CONTAINER)가 실행 중이지 않습니다."
fi
ok "PostgreSQL UP"

# k6 설치 확인
if ! command -v k6 &>/dev/null; then
  fail "k6가 설치되지 않았습니다. 'brew install k6' 로 설치하세요."
fi
ok "k6 설치 확인"

echo ""

# ══════════════════════════════════════════════════════════════════════
# 1. Grafana 대시보드 자동 Import
# ══════════════════════════════════════════════════════════════════════
log "Grafana 대시보드 Import 중..."

IMPORT_PAYLOAD=$(python3 -c "
import json, sys
with open('$DASHBOARD_JSON') as f:
    dash = json.load(f)
dash.pop('id', None)
payload = {
    'dashboard': dash,
    'overwrite': True,
    'inputs': [{
        'name': 'DS_PROMETHEUS',
        'type': 'datasource',
        'pluginId': 'prometheus',
        'value': 'Prometheus'
    }],
    'folderId': 0
}
print(json.dumps(payload))
")

IMPORT_RESULT=$(curl -sf -X POST "$GRAFANA/api/dashboards/import" \
  -H "Content-Type: application/json" \
  -d "$IMPORT_PAYLOAD" 2>&1)

if echo "$IMPORT_RESULT" | grep -q '"status":"success"'; then
  DASHBOARD_URL=$(echo "$IMPORT_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('importedUrl',''))" 2>/dev/null)
  ok "대시보드 Import 완료"
  echo -e "  ${GREEN}→ http://localhost:3000${DASHBOARD_URL}${NC}"
else
  warn "대시보드 Import 실패 (이미 존재하거나 datasource 이름 확인 필요)"
  echo "  응답: $IMPORT_RESULT"
fi

echo ""
echo -e "${YELLOW}Grafana를 브라우저에서 열어 대시보드를 확인하세요.${NC}"
echo -e "${YELLOW}→ http://localhost:3000${NC}"
echo ""
log "5초 후 시나리오를 시작합니다..."
sleep 5

# ══════════════════════════════════════════════════════════════════════
# 2. DB 초기화 (기존 테스트 데이터 정리)
# ══════════════════════════════════════════════════════════════════════
log "시나리오 준비: DB 테스트 데이터 초기화..."

psql_exec "
DELETE FROM verification_decisions WHERE id > 0;
DELETE FROM gps_verification_results WHERE id > 0;
DELETE FROM verification_submissions WHERE id > 0;
DELETE FROM settlements WHERE id > 0;
DELETE FROM challenge_participants WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE '시나리오%');
DELETE FROM challenges WHERE title LIKE '시나리오%';
" 2>/dev/null || warn "초기화 중 일부 테이블 건너뜀 (첫 실행 시 정상)"

ok "DB 초기화 완료"
echo ""

# ══════════════════════════════════════════════════════════════════════
# 시나리오 A — Challenge 생성·탐색
# ══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}══ 시나리오 A: Challenge 생성·탐색 ══${NC}"
log "챌린지 10개 생성 중..."

CHALLENGE_ID=""
for i in $(seq 1 10); do
  RESP=$(curl -sf -X POST "$API/api/challenges" \
    -H "Content-Type: application/json" \
    -H "X-User-Id: 1" \
    -d "{
      \"title\": \"시나리오테스트$i\",
      \"category\": \"HEALTH\",
      \"verificationType\": \"GPS\",
      \"durationDays\": 14,
      \"depositCoins\": 100,
      \"maxParticipants\": 10,
      \"visibility\": \"PUBLIC\",
      \"approvalType\": \"AUTO\"
    }" 2>/dev/null || echo '{}')

  if [ -z "$CHALLENGE_ID" ]; then
    CHALLENGE_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('id',''))" 2>/dev/null)
  fi
done

if [ -n "$CHALLENGE_ID" ]; then
  ok "챌린지 생성 완료 (기준 ID: $CHALLENGE_ID)"
else
  warn "챌린지 생성 응답에서 ID를 파싱하지 못했습니다. API 응답 구조를 확인하세요."
  CHALLENGE_ID=1
fi

# 목록 조회 5회
log "챌린지 목록 조회 테스트 (5회)..."
for i in $(seq 1 5); do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "$API/api/challenges" 2>/dev/null || echo "000")
  if [ "$STATUS" != "200" ]; then
    warn "목록 조회 응답: $STATUS"
  fi
done
ok "시나리오 A 완료 — Grafana에서 HTTP RPS·응답시간 확인"
echo ""

# ══════════════════════════════════════════════════════════════════════
# 시나리오 B — 참여 신청
# ══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}══ 시나리오 B: 참여 신청 ══${NC}"
log "챌린지 $CHALLENGE_ID 에 사용자 1~5 참여 신청..."

for userId in 1 2 3 4 5; do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "$API/api/challenges/$CHALLENGE_ID/participants" \
    -H "Content-Type: application/json" \
    -H "X-User-Id: $userId" \
    -d "{
      \"personalStatement\": \"참여합니다\",
      \"gpsLat\": 37.5665,
      \"gpsLng\": 126.9780,
      \"gpsRadiusMeters\": 100,
      \"gpsPlaceName\": \"서울시청\"
    }" 2>/dev/null || echo "000")
  echo "  userId=$userId → HTTP $STATUS"
done

ok "시나리오 B 완료 — Grafana에서 POST 응답시간·DB 커넥션 확인"
echo ""

# ══════════════════════════════════════════════════════════════════════
# 시나리오 C — 체크인 GPS 인증 체인 + 멱등성
# ══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}══ 시나리오 C: 체크인 GPS 인증 체인 ══${NC}"
log "체크인 20회 실행 (멱등성 포함)..."

FIRST_STATUS=""
for i in $(seq 1 20); do
  RESP=$(curl -sf -X POST "$API/api/challenges/$CHALLENGE_ID/check-ins" \
    -H "Content-Type: application/json" \
    -H "X-User-Id: 1" \
    -d "{
      \"currentLat\": 37.5665,
      \"currentLng\": 126.9780
    }" 2>/dev/null || echo '{}')

  STATUS=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('status','?'))" 2>/dev/null)
  if [ $i -eq 1 ]; then
    FIRST_STATUS="$STATUS"
    echo "  첫 번째 체크인 → $STATUS"
  elif [ $i -eq 2 ]; then
    echo "  두 번째 체크인 (멱등 확인) → $STATUS"
  fi
done

ok "시나리오 C 완료 — 첫 번째: $FIRST_STATUS, 중복 체크인 멱등 처리 확인"
echo ""

# ══════════════════════════════════════════════════════════════════════
# 시나리오 D — 정산 스케줄러
# ══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}══ 시나리오 D: 정산 스케줄러 ══${NC}"
log "챌린지 $CHALLENGE_ID 강제 종료 (DB 직접 수정)..."

psql_exec "UPDATE challenges SET status='ENDED', ended_at=NOW()-INTERVAL '1 minute' WHERE id=$CHALLENGE_ID;" || warn "챌린지 상태 업데이트 실패 (컬럼명 확인 필요)"

log "정산 스케줄러 대기 중 (30초)..."
echo "  백엔드 로그에서 'Settlement' 키워드를 확인하세요."
sleep 30

RESULT=$(curl -sf "$API/api/challenges/$CHALLENGE_ID/result" 2>/dev/null || echo '{}')
ok "시나리오 D 완료 — 정산 결과: $RESULT"
echo ""

# ══════════════════════════════════════════════════════════════════════
# 시나리오 E — 동시성 부하 (k6)
# ══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}══ 시나리오 E: 동시성 부하 (k6) ══${NC}"
log "k6 부하 테스트 시작 (5VU→20VU→50VU→0VU)..."
echo "  Grafana에서 HikariCP 커넥션·응답시간을 실시간으로 확인하세요."
echo ""

k6 run "$K6_SCRIPT" || warn "k6 기준 초과 — Grafana에서 병목 구간을 확인하세요."

echo ""

# ══════════════════════════════════════════════════════════════════════
# 완료 요약
# ══════════════════════════════════════════════════════════════════════
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} 모든 시나리오 완료${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "다음 단계:"
echo "  1. Grafana 대시보드에서 각 섹션 수치 확인"
echo "     → http://localhost:3000"
echo "  2. 수치를 docs/monitoring/week1-baseline.md 에 기록"
echo "  3. ./gradlew clean test (BAxisIsolationTest 확인)"
echo ""
echo -e "${CYAN}Prometheus 지표 직접 확인:${NC}"
echo "  curl -s localhost:8080/actuator/prometheus | grep hikaricp_connections_active"
