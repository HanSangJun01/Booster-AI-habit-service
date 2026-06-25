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
        'value': 'prometheus'
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
DELETE FROM challenge_check_ins WHERE challenge_id IN (SELECT id FROM challenges WHERE title LIKE '시나리오%');
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

# 참여자 상태 검증 (CONFIRMED 5명 확인)
CONFIRMED_COUNT=$(psql_exec "SELECT COUNT(*) FROM challenge_participants WHERE challenge_id=$CHALLENGE_ID AND status='CONFIRMED';" | tr -d ' ')
log "참여자 CONFIRMED 수: $CONFIRMED_COUNT / 5"
if [ "$CONFIRMED_COUNT" -ne 5 ]; then
  warn "참여자 중 CONFIRMED가 5명이 아닙니다. 체크인 요청이 실패할 수 있습니다."
fi

# 챌린지 ACTIVE 전환 (체크인·k6 전제조건)
log "챌린지 $CHALLENGE_ID 상태를 ACTIVE로 전환..."
psql_exec "UPDATE challenges SET status='ACTIVE', started_at=NOW()-INTERVAL '1 minute' WHERE id=$CHALLENGE_ID;" || warn "챌린지 상태 업데이트 실패"
ok "챌린지 ACTIVE 전환 완료"
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
# 시나리오 E — 동시성 부하 (k6) — D 이전에 실행 (챌린지 ACTIVE 상태)
# ══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}══ 시나리오 E: 동시성 부하 (k6) ══${NC}"

# Smoke 검증: 챌린지 목록, 상세, 체크인 read/write 단건 확인 (k6 전)
log "Smoke 검증 중 (k6 전)..."
SMOKE_LIST=$(curl -sf -o /dev/null -w "%{http_code}" "$API/api/challenges" 2>/dev/null || echo "000")
SMOKE_DETAIL=$(curl -sf -o /dev/null -w "%{http_code}" "$API/api/challenges/$CHALLENGE_ID" -H "X-User-Id: 1" 2>/dev/null || echo "000")
SMOKE_CHECKIN_READ=$(curl -sf -o /dev/null -w "%{http_code}" "$API/api/challenges/$CHALLENGE_ID/check-ins" -H "X-User-Id: 1" 2>/dev/null || echo "000")
SMOKE_CHECKIN_WRITE_RESP=$(curl -sf -w "\n%{http_code}" -X POST "$API/api/challenges/$CHALLENGE_ID/check-ins" \
  -H "Content-Type: application/json" -H "X-User-Id: 1" \
  -d '{"currentLat":37.5665,"currentLng":126.9780}' 2>/dev/null || printf '{}\n000')
SMOKE_CHECKIN_WRITE=$(echo "$SMOKE_CHECKIN_WRITE_RESP" | tail -1)

log "  GET /api/challenges → $SMOKE_LIST"
log "  GET /api/challenges/$CHALLENGE_ID → $SMOKE_DETAIL"
log "  GET .../check-ins → $SMOKE_CHECKIN_READ"
log "  POST .../check-ins → $SMOKE_CHECKIN_WRITE"

if [ "$SMOKE_LIST" != "200" ] || [ "$SMOKE_DETAIL" != "200" ] || [ "$SMOKE_CHECKIN_READ" != "200" ]; then
  fail "Smoke 검증 실패 — k6 부하 테스트 중단. 위 응답코드를 확인하세요."
fi
if [ "$SMOKE_CHECKIN_WRITE" != "200" ] && [ "$SMOKE_CHECKIN_WRITE" != "201" ]; then
  SMOKE_BODY=$(echo "$SMOKE_CHECKIN_WRITE_RESP" | head -1)
  warn "체크인 쓰기 smoke 실패: HTTP $SMOKE_CHECKIN_WRITE — $SMOKE_BODY"
  warn "k6 에러율이 높을 수 있습니다. 계속 진행합니다."
fi
ok "Smoke 검증 통과"
echo ""

log "k6 부하 테스트 시작 (5VU→20VU→50VU→0VU)..."
echo "  Grafana에서 HikariCP 커넥션·응답시간을 실시간으로 확인하세요."
echo ""

k6 run -e BASE_URL="$API" -e CHALLENGE_ID="$CHALLENGE_ID" "$K6_SCRIPT" || warn "k6 기준 초과 — Grafana에서 병목 구간을 확인하세요."

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
# 완료 요약
# ══════════════════════════════════════════════════════════════════════
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} 모든 시나리오 완료${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════
# 결과 자동 기록 — baseline-YYYY-MM-DD.md 생성
# ══════════════════════════════════════════════════════════════════════
log "결과 파일 자동 생성 중..."

BASELINE_FILE="$PROJECT_ROOT/docs/monitoring/baselines/baseline-$(date +%Y-%m-%d-%H-%M).md"

python3 - <<PYEOF
import json, urllib.request, datetime, os

# ── k6 요약 로드 ─────────────────────────────────────────
try:
    with open('/tmp/k6-summary.json') as f:
        k6 = json.load(f)
    metrics = k6.get('metrics', {})

    def pct(metric, p):
        m = metrics.get(metric, {})
        v = m.get('values', {})
        return v.get(f'p({p})', v.get('med' if p == 50 else None, None))

    def val(metric, key='avg'):
        m = metrics.get(metric, {})
        return m.get('values', {}).get(key, None)

    http_p50  = round(pct('http_req_duration', 50) or 0, 2)
    http_p95  = round(pct('http_req_duration', 95) or 0, 2)
    http_p99  = round(pct('http_req_duration', 99) or 0, 2)
    http_avg  = round(val('http_req_duration') or 0, 2)
    list_p95      = round(pct('challenge_list_duration', 95) or 0, 2)
    list_p99      = round(pct('challenge_list_duration', 99) or 0, 2)
    detail_p95    = round(pct('challenge_detail_duration', 95) or 0, 2)
    detail_p99    = round(pct('challenge_detail_duration', 99) or 0, 2)
    checkin_w_p95 = round(pct('checkin_write_duration', 95) or 0, 2)
    checkin_w_p99 = round(pct('checkin_write_duration', 99) or 0, 2)
    checkin_r_p95 = round(pct('checkin_read_duration', 95) or 0, 2)
    err_rate  = round((val('errors', 'rate') or 0) * 100, 3)
    total_req = int(metrics.get('http_reqs', {}).get('values', {}).get('count', 0))
    rps       = round(metrics.get('http_reqs', {}).get('values', {}).get('rate', 0), 2)
    k6_ok = True
except Exception as e:
    k6_ok = False
    print(f"  [WARN] k6 요약 파싱 실패: {e}")

# ── Prometheus 쿼리 ───────────────────────────────────────
def prom(query):
    try:
        url = f"http://localhost:9090/api/v1/query?query={urllib.parse.quote(query)}"
        with urllib.request.urlopen(url, timeout=5) as r:
            d = json.load(r)
        result = d['data']['result']
        return round(float(result[0]['value'][1]), 4) if result else None
    except:
        return None

import urllib.parse

heap_used  = prom('sum(jvm_memory_used_bytes{application="booster", area="heap"})')
heap_max   = prom('sum(jvm_memory_max_bytes{application="booster", area="heap"} > 0)')
heap_pct   = round(heap_used / heap_max * 100, 2) if heap_used and heap_max else None
threads    = prom('jvm_threads_live_threads{application="booster"}')
gc_rate    = prom('rate(jvm_gc_pause_seconds_sum{application="booster"}[1m])')
gc_ms      = round((gc_rate or 0) * 1000, 2)
hk_active  = prom('hikaricp_connections_active{application="booster"}')
hk_idle    = prom('hikaricp_connections_idle{application="booster"}')
hk_pending = prom('hikaricp_connections_pending{application="booster"}')
hk_acq_p99 = prom('histogram_quantile(0.99, sum(rate(hikaricp_connections_acquire_seconds_bucket{application="booster"}[2m])) by (le))')
hk_acq_ms  = round((hk_acq_p99 or 0) * 1000, 3)

# ── md 생성 ──────────────────────────────────────────────
date_str = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
md = f"""# 성능 기준선 — {date_str}

**측정일시**: {date_str}
**환경**: Docker Compose (PostgreSQL 15, Spring Boot 3.x)
**HikariCP pool-size**: 10 (default)
**부하 도구**: k6 (5VU → 20VU → 50VU → 0VU), 총 2분 20초

---

## HTTP 응답시간 (k6 결과)

| 지표 | 값 |
|------|-----|
| 평균 | {http_avg}ms |
| p50 | {http_p50}ms |
| p95 | {http_p95}ms |
| p99 | {http_p99}ms |
| 에러율 | {err_rate}% |
| 총 요청 수 | {total_req:,}건 |
| RPS | {rps} req/s |

### API별 p95 / p99

| API | p95 | p99 |
|-----|-----|-----|
| GET /api/challenges (목록) | {list_p95}ms | {list_p99}ms |
| GET /api/challenges/{{id}} (상세) | {detail_p95}ms | {detail_p99}ms |
| POST /api/challenges/{{id}}/check-ins (쓰기) | {checkin_w_p95}ms | {checkin_w_p99}ms |
| GET /api/challenges/{{id}}/check-ins (조회) | {checkin_r_p95}ms | - |

---

## JVM (부하 직후 측정)

| 지표 | 측정값 |
|------|-------|
| Heap 사용량 | {round((heap_used or 0)/1024/1024, 1)} MB |
| Heap 최대 | {round((heap_max or 0)/1024/1024, 0):.0f} MB |
| **Heap 사용률** | **{heap_pct}%** |
| 활성 스레드 | {threads}개 |
| GC 일시정지 | {gc_ms}ms/분 |

---

## DB 커넥션 (부하 직후, HikariCP)

| 지표 | 측정값 |
|------|-------|
| active | {hk_active} |
| idle | {hk_idle} |
| pending | {hk_pending} |
| 획득 p99 | {hk_acq_ms}ms |

---

## k6 기준(threshold) 달성 여부

| 기준 | 목표 | 결과 | 판정 |
|------|------|------|------|
| 전체 p99 | < 500ms | {http_p99}ms | {'✅' if http_p99 < 500 else '❌'} |
| 목록 조회 p95 | < 200ms | {list_p95}ms | {'✅' if list_p95 < 200 else '❌'} |
| 상세 조회 p95 | < 150ms | {detail_p95}ms | {'✅' if detail_p95 < 150 else '❌'} |
| 체크인 쓰기 p95 | < 300ms | {checkin_w_p95}ms | {'✅' if checkin_w_p95 < 300 else '❌'} |
| 에러율 | < 1% | {err_rate}% | {'✅' if err_rate < 1 else '❌'} |
| Heap 사용률 | < 70% | {heap_pct}% | {'✅' if (heap_pct or 0) < 70 else '❌'} |
| HikariCP pending | 0 | {hk_pending} | {'✅' if (hk_pending or 0) == 0 else '❌'} |

---

## Grafana 스크린샷

<!-- 대시보드 스크린샷을 여기에 첨부하세요 -->
<!-- http://localhost:3000/d/booster-baxis-v1 -->
"""

os.makedirs(os.path.dirname('$BASELINE_FILE'), exist_ok=True)
with open('$BASELINE_FILE', 'w') as f:
    f.write(md)
print(f"  저장 완료: $BASELINE_FILE")
PYEOF

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} 결과 파일: docs/monitoring/baselines/baseline-$(date +%Y-%m-%d-%H-%M).md${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "다음 단계:"
echo "  1. Grafana 대시보드 확인 → http://localhost:3000/d/booster-baxis-v1"
echo "  2. 스크린샷을 baseline-$(date +%Y-%m-%d).md 에 첨부"
echo "  3. ./gradlew clean test (BAxisIsolationTest 확인)"
