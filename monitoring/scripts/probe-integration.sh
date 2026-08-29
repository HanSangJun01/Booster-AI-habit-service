#!/usr/bin/env bash
# A×B 통합면 버그 프로브 — 부하가 아니라 "논리 버그"를 한 방씩 찔러 확인한다.
#
# 왜 따로 있나:
#   b-axis-run-scenarios.sh 는 B축만, a-axis-realistic.js 는 A축만 본다.
#   두 축이 만나는 지점(코인 = A축이 주고 B축이 뺏는 공유자원, 체크인 연쇄, 권한)은
#   아무도 안 보고 있었다. 여기서 그 지점만 정확히 찌른다.
#
# 판정 표기:  [BUG] 재현됨 · [OK] 정상 · [??] 판단보류(환경/전제 미충족)
#
# 실행: monitoring/scripts/probe-integration.sh
#   전제: docker compose up -d (백엔드 8080 + booster-db)

set -uo pipefail

API="${API:-http://localhost:8080}"
DB_CONTAINER="${DB_CONTAINER:-booster-db}"
DB_USER="${DB_USER:-booster}"
DB_NAME="${DB_NAME:-booster}"
PW="probe1234"
STAMP="$(date +%s)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YEL='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BUGS=0
bug()  { echo -e "${RED}[BUG]${NC} $1"; BUGS=$((BUGS+1)); }
ok()   { echo -e "${GREEN}[OK]${NC}  $1"; }
skip() { echo -e "${YEL}[??]${NC}  $1"; }
hdr()  { echo -e "\n${CYAN}══ $1 ══${NC}"; }

psql_q() { docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null | tr -d '\r'; }

# ── 유저 준비 ────────────────────────────────────────────────────────────────
# 팀 자동편성에 10명이 필요하고, 비참여자(침입자) 1명을 더 만든다.
declare -a TOK UID_
mkuser() { # $1 = slot
  local email="probe${STAMP}_$1@booster.test"
  curl -s -X POST "$API/api/auth/signup" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PW\",\"nickname\":\"probe$1\"}" >/dev/null 2>&1
  local body; body=$(curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PW\"}")
  TOK[$1]=$(echo "$body" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
  UID_[$1]=$(echo "$body" | grep -o '"userId":[0-9]*' | cut -d: -f2)
  [ -n "${TOK[$1]:-}" ] || { echo "로그인 실패 slot=$1: $body"; exit 1; }
}

hdr "준비: 유저 11명 생성 (10명=팀편성, 1명=비참여 침입자)"
for i in $(seq 1 11); do mkuser "$i"; done
ok "유저 준비 완료 (user_id ${UID_[1]}..${UID_[11]})"

AUTH1=(-H "Authorization: Bearer ${TOK[1]}")

# ── P1: 코인 보존 — A축이 주고 B축이 뺏는 공유자원 ──────────────────────────
hdr "P1: 코인 보존 (B축 참가비 차감이 정확히 depositCoins 만큼인가)"
COIN_BEFORE=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[1]};")
CH=$(curl -s -X POST "$API/api/challenges" -H 'Content-Type: application/json' "${AUTH1[@]}" \
  -d '{"title":"probe_coin","category":"HEALTH","verificationType":"GPS","durationDays":14,
       "depositCoins":100,"maxParticipants":10,"visibility":"PUBLIC","approvalType":"AUTO","gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,"gpsPlaceName":"CityHall"}')
CH_ID=$(echo "$CH" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
if [ -z "${CH_ID:-}" ]; then skip "챌린지 생성 실패 — 응답: $CH"; else
  curl -s -X POST "$API/api/challenges/$CH_ID/participants" -H 'Content-Type: application/json' "${AUTH1[@]}" \
    -d '{"personalStatement":"join","gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,"gpsPlaceName":"CityHall"}' >/dev/null
  COIN_AFTER=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[1]};")
  DIFF=$((COIN_BEFORE - COIN_AFTER))
  if [ "$DIFF" -eq 100 ]; then ok "참가비 차감 정확 (${COIN_BEFORE} → ${COIN_AFTER}, -100)"
  else bug "참가비 차감 불일치: ${COIN_BEFORE} → ${COIN_AFTER} (차이 ${DIFF}, 기대 100)"; fi
fi

# ── P2: 잔액 초과 동시 참여 — 잔액 100인데 100짜리 2개 동시 신청 ────────────
hdr "P2: 잔액 초과 동시 참여 (코인 음수 가능한가)"
psql_q "UPDATE users SET coin_balance=100 WHERE id=${UID_[2]};" >/dev/null
A2=(-H "Authorization: Bearer ${TOK[2]}")
for n in 1 2; do
  R=$(curl -s -X POST "$API/api/challenges" -H 'Content-Type: application/json' "${AUTH1[@]}" \
    -d "{\"title\":\"probe_bal$n\",\"category\":\"HEALTH\",\"verificationType\":\"GPS\",\"durationDays\":14,
         \"depositCoins\":100,\"maxParticipants\":10,\"visibility\":\"PUBLIC\",\"approvalType\":\"AUTO\",\"gpsLat\":37.5665,\"gpsLng\":126.9780,\"gpsRadiusMeters\":100,\"gpsPlaceName\":\"CityHall\"}")
  eval "RACE_CH$n=$(echo "$R" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)"
done
# 동시에 쏜다
for cid in "$RACE_CH1" "$RACE_CH2"; do
  curl -s -o /dev/null -X POST "$API/api/challenges/$cid/participants" -H 'Content-Type: application/json' "${A2[@]}" \
    -d '{"personalStatement":"join","gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,"gpsPlaceName":"CityHall"}' &
done
wait
COIN_RACE=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[2]};")
if [ "${COIN_RACE:-0}" -lt 0 ]; then bug "동시 참여로 코인 음수: ${COIN_RACE} (잔액 100, 참가비 100×2)"
else ok "코인 음수 없음 (잔액 ${COIN_RACE})"; fi

# ── P3: 남의 팀 채팅 훔쳐보기 (멤버십 검사 없음 의심) ────────────────────────
hdr "P3: 남의 팀 채팅 읽기 (GET /teams/{id}/chat 멤버십 검사)"
# 10명 채워 팀 자동편성 트리거
TEAMCH=$(curl -s -X POST "$API/api/challenges" -H 'Content-Type: application/json' "${AUTH1[@]}" \
  -d '{"title":"probe_team","category":"HEALTH","verificationType":"GPS","durationDays":14,
       "depositCoins":0,"maxParticipants":10,"visibility":"PUBLIC","approvalType":"AUTO","gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,"gpsPlaceName":"CityHall"}')
TEAMCH_ID=$(echo "$TEAMCH" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
for i in $(seq 1 10); do
  curl -s -o /dev/null -X POST "$API/api/challenges/$TEAMCH_ID/participants" -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${TOK[$i]}" \
    -d '{"personalStatement":"join","gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,"gpsPlaceName":"CityHall"}' >/dev/null
done
TEAM_ID=$(psql_q "SELECT id FROM teams WHERE challenge_id=$TEAMCH_ID LIMIT 1;")
if [ -z "${TEAM_ID:-}" ]; then skip "팀 미편성 — 채팅 프로브 불가 (challenge=$TEAMCH_ID)"; else
  # 멤버(u1)가 메시지 남김
  curl -s -o /dev/null -X POST "$API/api/teams/$TEAM_ID/chat" -H 'Content-Type: application/json' "${AUTH1[@]}" \
    -d '{"content":"team_secret_msg"}'
  # 비참여자(u11)가 읽기 시도
  INTRUDER=$(curl -s -o /dev/null -w '%{http_code}' "$API/api/teams/$TEAM_ID/chat" -H "Authorization: Bearer ${TOK[11]}")
  if [ "$INTRUDER" = "200" ]; then bug "비참여자가 남의 팀 채팅 조회 성공 (HTTP 200) — 멤버십 검사 없음"
  else ok "비참여자 채팅 조회 차단 (HTTP $INTRUDER)"; fi
  # 비참여자가 쓰기 시도 (이쪽은 검사 있다고 알려짐 — 대조군)
  INTRUDER_W=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/teams/$TEAM_ID/chat" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOK[11]}" -d '{"content":"intruder"}')
  if [ "$INTRUDER_W" = "200" ] || [ "$INTRUDER_W" = "201" ]; then bug "비참여자가 남의 팀 채팅 쓰기 성공 (HTTP $INTRUDER_W)"
  else ok "비참여자 채팅 쓰기 차단 (HTTP $INTRUDER_W)"; fi
fi

# ── P4: 페이지 사이즈 클램프 (A축은 막음, B축은?) ────────────────────────────
# 클램프는 200을 그대로 주되 반환 size 만 상한으로 깎는다(A축 F9 방식). 따라서 상태코드가
# 아니라 응답의 실제 page size 를 봐야 한다. size 필드가 100 초과면 클램프 안 된 것.
hdr "P4: 페이지 사이즈 클램프 (반환 size 가 100 이하로 깎이나)"
check_clamp() { # $1=라벨 $2=URL
  local body size
  body=$(curl -s "$2" "${AUTH1[@]}")
  size=$(echo "$body" | grep -o '"size":[0-9]*' | head -1 | cut -d: -f2)
  if [ -z "$size" ]; then skip "$1: size 필드 파싱 실패 — $(echo "$body" | head -c 100)"
  elif [ "$size" -gt 100 ]; then bug "$1: 반환 size=$size (클램프 안 됨, 100 초과)"
  else ok "$1: size=1000000 요청 → 반환 size=$size (클램프됨)"; fi
}
check_clamp "GET /api/challenges" "$API/api/challenges?size=1000000"
if [ -n "${TEAM_ID:-}" ]; then
  check_clamp "GET /teams/{id}/chat" "$API/api/teams/$TEAM_ID/chat?size=1000000"
fi

# ── P5: 채팅 본문 길이 제한 없음 ─────────────────────────────────────────────
hdr "P5: 채팅 본문 길이 제한"
if [ -n "${TEAM_ID:-}" ]; then
  # 인자로 넘기면 셸 ARG_MAX 에 걸려 curl 이 죽는다(= 서버 판정이 아님) → 파일로 보낸다.
  # 파일 경로는 상대경로여야 한다: Git Bash(MSYS)가 절대경로 /tmp/... 를 윈도우 경로로 뭉개
  # curl 의 @file 인자가 깨진다.
  BIG_FILE="./.probe-big-body.json"
  { printf '{"content":"'; head -c 100000 /dev/zero | tr '\0' 'A'; printf '"}'; } > "$BIG_FILE"
  BIG_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/teams/$TEAM_ID/chat" \
    -H 'Content-Type: application/json' "${AUTH1[@]}" --data-binary "@$BIG_FILE")
  rm -f "$BIG_FILE"
  if [ "$BIG_CODE" = "200" ] || [ "$BIG_CODE" = "201" ]; then
    bug "10만자 채팅 저장 성공 (HTTP $BIG_CODE) — content 길이 제한 없음"
  elif [ -z "$BIG_CODE" ]; then
    # 응답코드가 비면 curl 자체가 실패한 것 — 서버가 막았다는 증거가 아니므로 OK 로 세지 않는다.
    skip "요청 전송 실패(응답코드 없음) — 서버 판정 아님, 프로브 환경 확인 필요"
  else
    ok "과대 본문 차단 (HTTP $BIG_CODE)"
  fi
fi

# ── P6: 응원 ID 공간 혼선 (userId를 participantId 자리에 바인딩) ─────────────
hdr "P6: 응원(cheers) ID 공간 — userId vs participantId"
if [ -n "${TEAMCH_ID:-}" ]; then
  # u1의 participant_id (userId와 다른 값이어야 프로브 의미가 있음)
  P1_ID=$(psql_q "SELECT id FROM challenge_participants WHERE challenge_id=$TEAMCH_ID AND user_id=${UID_[1]};")
  echo "  u1: user_id=${UID_[1]} / participant_id=${P1_ID:-?}"
  if [ "${P1_ID:-}" = "${UID_[1]}" ]; then
    skip "user_id와 participant_id가 우연히 같음 — ID 혼선 판별 불가 (DB 초기화 후 재실행 권장)"
  else
    # 자기 자신 응원 시도: participantId 로 보내면? userId 로 보내면?
    SELF_BY_PID=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/challenges/$TEAMCH_ID/cheers" \
      -H 'Content-Type: application/json' "${AUTH1[@]}" -d "{\"toParticipantId\":${P1_ID},\"emojiType\":\"CLAP\"}")
    SELF_BY_UID=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/challenges/$TEAMCH_ID/cheers" \
      -H 'Content-Type: application/json' "${AUTH1[@]}" -d "{\"toParticipantId\":${UID_[1]},\"emojiType\":\"CLAP\"}")
    echo "  자기 participant_id(${P1_ID})로 응원 → HTTP $SELF_BY_PID  (차단 기대)"
    echo "  자기 user_id(${UID_[1]})로 응원      → HTTP $SELF_BY_UID  (participantId 자리에 userId — 통과하면 ID공간 혼선)"
    if [ "$SELF_BY_PID" = "200" ] || [ "$SELF_BY_PID" = "201" ]; then
      bug "자기 자신 응원이 통과함 (participant_id 기준) — 자기응원 가드가 userId와 비교 중이라 무력화"
    else ok "자기응원 차단됨 (participant_id 기준, HTTP $SELF_BY_PID)"; fi
  fi
fi

# ── P7: B축 체크인 → A축 개인체크인 연쇄 (실패 삼킴 의심) ────────────────────
hdr "P7: B축 체크인이 A축 개인 체크인으로 이어지는가 (CheckInOrchestrator 삼킴)"
if [ -n "${TEAMCH_ID:-}" ]; then
  psql_q "UPDATE challenges SET status='ACTIVE', started_at=NOW()-INTERVAL '1 minute' WHERE id=$TEAMCH_ID;" >/dev/null
  # A축 인증 장소를 등록하지 않은 유저(u3)로 B축 체크인 → A축 연쇄는 실패할 수밖에 없음
  A3=(-H "Authorization: Bearer ${TOK[3]}")
  HAS_LOC=$(psql_q "SELECT COUNT(*) FROM personal_locations WHERE user_id=${UID_[3]};")
  B_CODE2=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/challenges/$TEAMCH_ID/check-ins" \
    -H 'Content-Type: application/json' "${A3[@]}" -d '{"currentLat":37.5665,"currentLng":126.9780}')
  PERSONAL=$(psql_q "SELECT COUNT(*) FROM personal_check_ins WHERE user_id=${UID_[3]} AND check_in_date=CURRENT_DATE;")
  echo "  u3 A축 위치등록 여부: ${HAS_LOC:-?}건 / B축 체크인 HTTP $B_CODE2 / A축 개인체크인 생성: ${PERSONAL:-?}건"
  if { [ "$B_CODE2" = "200" ] || [ "$B_CODE2" = "201" ]; } && [ "${PERSONAL:-0}" = "0" ]; then
    bug "B축 체크인은 성공(HTTP $B_CODE2)했는데 A축 개인체크인 0건 — 연쇄 실패가 조용히 삼켜짐(코인 보상 증발)"
  elif [ "${PERSONAL:-0}" != "0" ]; then ok "B축 체크인 → A축 개인체크인 연쇄 성공 (${PERSONAL}건)"
  else skip "B축 체크인 자체가 실패 (HTTP $B_CODE2) — 연쇄 판별 불가"; fi
fi

# ── P8: actuator 무인증 노출 ─────────────────────────────────────────────────
hdr "P8: /actuator 무인증 노출"
ACT=$(curl -s -o /dev/null -w '%{http_code}' "$API/actuator/prometheus")
HEALTH_BODY=$(curl -s "$API/actuator/health" | head -c 120)
if [ "$ACT" = "200" ]; then bug "/actuator/prometheus 무인증 200 — 메트릭 전체 공개 (permitAll)"
else ok "/actuator/prometheus 차단 (HTTP $ACT)"; fi
echo "  /actuator/health 응답: $HEALTH_BODY"

# ── 요약 ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}════════════════════════════════${NC}"
if [ "$BUGS" -eq 0 ]; then echo -e "${GREEN} 재현된 버그 없음${NC}"
else echo -e "${RED} 재현된 버그: ${BUGS}건${NC}"; fi
echo -e "${CYAN}════════════════════════════════${NC}"
