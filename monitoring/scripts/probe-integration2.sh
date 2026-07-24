#!/usr/bin/env bash
# A×B 통합면 버그 프로브 2차 — 돈 정합성 · 동시성 · 엣지케이스.
#
# 1차(probe-integration.sh)는 권한·입력검증 위주였다. 여기선 코드리뷰로 새로 의심된
# "돈이 새거나 겹치는" 지점과 동시성 경쟁을 찌른다. 전부 참가비(deposit) 흐름:
#   참여 = coin 차감(무조건),  취소 = 환불(status=CONFIRMED 일 때만),  정산 = 지급.
#
# 판정:  [BUG] 재현됨 · [OK] 정상 · [??] 판단보류
#
# 실행: monitoring/scripts/probe-integration2.sh
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

declare -a TOK UID_
mkuser() { # $1 = slot
  local email="p2_${STAMP}_$1@booster.test"
  curl -s -X POST "$API/api/auth/signup" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PW\",\"nickname\":\"p2u$1\"}" >/dev/null 2>&1
  local body; body=$(curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PW\"}")
  TOK[$1]=$(echo "$body" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
  UID_[$1]=$(echo "$body" | grep -o '"userId":[0-9]*' | cut -d: -f2)
  [ -n "${TOK[$1]:-}" ] || { echo "로그인 실패 slot=$1: $body"; exit 1; }
}

# 챌린지 생성 → id 반환. $1=approvalType(AUTO|LEADER) $2=deposit $3=creatorSlot
mkchallenge() {
  local resp; resp=$(curl -s -X POST "$API/api/challenges" -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${TOK[$3]}" \
    -d "{\"title\":\"p2_${1}_${STAMP}_$RANDOM\",\"category\":\"HEALTH\",\"verificationType\":\"GPS\",
         \"durationDays\":14,\"depositCoins\":$2,\"maxParticipants\":10,
         \"visibility\":\"PUBLIC\",\"approvalType\":\"$1\"}")
  echo "$resp" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2
}

join() { # $1=challengeId $2=slot  → HTTP code
  curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/challenges/$1/participants" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOK[$2]}" \
    -d '{"personalStatement":"join","gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,"gpsPlaceName":"CityHall"}'
}

hdr "준비: 유저 14명 생성"
for i in $(seq 1 14); do mkuser "$i"; done
ok "유저 준비 완료 (user_id ${UID_[1]}..${UID_[14]})"

# ── Q1: LEADER 승인형에서 PENDING 참여자 취소 → 보증금 환불되나 ────────────────
# 참여 시 코인은 무조건 차감되지만, 취소 환불은 status=CONFIRMED 일 때만.
# LEADER 승인형은 참여 직후 PENDING → 취소하면 환불 없이 보증금 증발 의심.
hdr "Q1: PENDING(LEADER 승인대기) 취소 시 보증금 환불"
CH_L=$(mkchallenge LEADER 100 1)
if [ -z "${CH_L:-}" ]; then skip "LEADER 챌린지 생성 실패"; else
  B_BEFORE=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[2]};")
  JC=$(join "$CH_L" 2)
  ST=$(psql_q "SELECT status FROM challenge_participants WHERE challenge_id=$CH_L AND user_id=${UID_[2]};")
  B_JOINED=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[2]};")
  echo "  참여 HTTP=$JC / 상태=$ST / 코인 ${B_BEFORE}→${B_JOINED}"
  # 취소
  CC=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$API/api/challenges/$CH_L/participants/${UID_[2]}" \
    -H "Authorization: Bearer ${TOK[2]}")
  B_AFTER=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[2]};")
  echo "  취소 HTTP=$CC / 코인 ${B_JOINED}→${B_AFTER}"
  if [ "$ST" = "PENDING" ] && [ "${B_AFTER:-0}" -lt "${B_BEFORE:-0}" ]; then
    bug "PENDING 참여자 취소 후 코인 ${B_BEFORE}→${B_AFTER} — 보증금 100 증발(차감은 됐는데 환불 안 됨)"
  elif [ "${B_AFTER:-0}" -eq "${B_BEFORE:-0}" ]; then
    ok "PENDING 취소 후 보증금 원복 (${B_AFTER})"
  else
    skip "판단보류: 상태=$ST, before=$B_BEFORE after=$B_AFTER"
  fi
fi

# ── Q2: CONFIRMED 참여자 동시 취소 → 환불 2배 (participant 무락) ───────────────
# cancelParticipation은 챌린지만 findById(무락)하고 참여자엔 락이 없다.
# 동시 취소가 둘 다 status=CONFIRMED를 읽고 각각 환불하면 이중 환불.
hdr "Q2: CONFIRMED 동시 취소 → 이중 환불 (participant 락 경합)"
CH_A=$(mkchallenge AUTO 100 3)   # u3가 만들고 u4가 혼자 참여(정원 안 차 READY 유지 → 취소 가능)
if [ -z "${CH_A:-}" ]; then skip "AUTO 챌린지 생성 실패"; else
  B0=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[4]};")
  join "$CH_A" 4 >/dev/null
  ST4=$(psql_q "SELECT status FROM challenge_participants WHERE challenge_id=$CH_A AND user_id=${UID_[4]};")
  B1=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[4]};")
  echo "  참여 상태=$ST4 / 코인 ${B0}→${B1} (차감 100 기대)"
  # 동시에 8발 취소
  for n in $(seq 1 8); do
    curl -s -o /dev/null -X DELETE "$API/api/challenges/$CH_A/participants/${UID_[4]}" \
      -H "Authorization: Bearer ${TOK[4]}" &
  done
  wait
  B2=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[4]};")
  REFUNDS=$(psql_q "SELECT COUNT(*) FROM coin_transactions WHERE user_id=${UID_[4]} AND reference_id=$CH_A AND amount>0;")
  echo "  동시취소 8발 후 코인 ${B1}→${B2} / 환불성 거래 ${REFUNDS}건 (정상=1)"
  if [ "${B2:-0}" -gt "${B0:-0}" ]; then
    bug "이중 환불: 최종 코인 ${B2} > 참여 전 ${B0} — 취소 1번인데 환불 여러 번(거래 ${REFUNDS}건)"
  elif [ "${REFUNDS:-0}" -gt 1 ]; then
    bug "환불 거래 ${REFUNDS}건(>1) — 코인 총액은 우연히 맞아도 이중 환불 기록됨"
  else
    ok "환불 정확히 1회 (최종 ${B2}, 참여 전 ${B0})"
  fi
fi

# ── Q3: leaderboard type 파라미터 누락 → 400 이어야 (500이면 버그) ─────────────
hdr "Q3: GET /leaderboards (필수 type 누락) 응답코드"
CH_LB=$(mkchallenge AUTO 0 5)
LB=$(curl -s -o /dev/null -w '%{http_code}' "$API/api/challenges/$CH_LB/leaderboards" \
  -H "Authorization: Bearer ${TOK[5]}")
echo "  GET .../leaderboards (type 없음) → HTTP $LB"
if [ "$LB" = "500" ]; then bug "type 누락 → 500 (MissingServletRequestParameter 미매핑, 400이어야)"
elif [ "$LB" = "400" ]; then ok "type 누락 → 400 (정상)"
else skip "예상 밖 응답 $LB"; fi

# ── Q4: 정원 초과 동시 참여 → CONFIRMED 가 max_participants 넘나 ───────────────
# max=10 AUTO 챌린지에 12명 동시 참여. 챌린지 비관락이 제대로면 정확히 10명 CONFIRMED.
hdr "Q4: 정원(10) 초과 동시 참여 → 초과 confirmed 생기나"
CH_CAP=$(mkchallenge AUTO 0 1)
if [ -z "${CH_CAP:-}" ]; then skip "정원 테스트 챌린지 생성 실패"; else
  for i in $(seq 3 14); do   # 12명 동시
    join "$CH_CAP" "$i" >/dev/null &
  done
  wait
  CONF=$(psql_q "SELECT COUNT(*) FROM challenge_participants WHERE challenge_id=$CH_CAP AND status='CONFIRMED';")
  echo "  12명 동시 참여 후 CONFIRMED=${CONF} (정원 10)"
  if [ "${CONF:-0}" -gt 10 ]; then bug "정원 초과: CONFIRMED ${CONF} > 10 (참여 경쟁 락 실패)"
  else ok "정원 준수: CONFIRMED ${CONF} ≤ 10"; fi
fi

# ── Q5: 같은 대상에 응원 무한 중복 (dedup/rate-limit 없음) ─────────────────────
hdr "Q5: 응원 중복 스팸 (같은 from→to 반복)"
CH_CH=$(mkchallenge AUTO 0 6)
for i in $(seq 6 10); do join "$CH_CH" "$i" >/dev/null; done   # 팀 구성용 최소 인원
TO_PID=$(psql_q "SELECT id FROM challenge_participants WHERE challenge_id=$CH_CH AND user_id=${UID_[7]};")
if [ -z "${TO_PID:-}" ]; then skip "응원 대상 참여자 없음"; else
  CNT=0
  for n in $(seq 1 5); do
    R=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/challenges/$CH_CH/cheers" \
      -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOK[6]}" \
      -d "{\"toParticipantId\":$TO_PID,\"emojiType\":\"CLAP\"}")
    [ "$R" = "201" ] && CNT=$((CNT+1))
  done
  ROWS=$(psql_q "SELECT COUNT(*) FROM cheer_emojis WHERE challenge_id=$CH_CH AND to_participant_id=$TO_PID;")
  echo "  같은 대상에 5연타 → 201 ${CNT}회 / DB 저장 ${ROWS}행"
  if [ "${ROWS:-0}" -ge 5 ]; then bug "응원 중복 무제한: 같은 from→to 5행 저장 (dedup/rate-limit 없음)"
  else ok "응원 중복 억제됨 (${ROWS}행)"; fi
fi

echo ""
echo -e "${CYAN}════════════════════════════════${NC}"
if [ "$BUGS" -eq 0 ]; then echo -e "${GREEN} 재현된 버그 없음${NC}"
else echo -e "${RED} 재현된 버그: ${BUGS}건${NC}"; fi
echo -e "${CYAN}════════════════════════════════${NC}"
