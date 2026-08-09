#!/usr/bin/env bash
# A×B 통합면 버그 프로브 3차 — 권한(멤버십)·라이프사이클·정보노출.
#
# 1차(권한/입력검증)·2차(돈/동시성)에서 A축식 가드는 대부분 방어됨을 확인했다.
# 여기선 아직 안 찔러본 표면을 본다:
#   - 조회 엔드포인트의 멤버십 검사 누락(정보노출)
#   - 회원 탈퇴(soft delete)와 진행중 챌린지의 연동 공백(고아 참여·예치금·좀비 토큰)
#   - 종료 전 정산결과 조회
#
# 판정:  [BUG] 재현됨 · [OK] 정상 · [??] 판단보류
# 실행: monitoring/scripts/probe-integration3.sh   (전제: docker compose up -d)

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
hdr()  { echo -e "\n${CYAN}== $1 ==${NC}"; }

psql_q() { docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null | tr -d '\r'; }

declare -a TOK UID_
mkuser() {
  local email="p3_${STAMP}_$1@booster.test"
  curl -s -X POST "$API/api/auth/signup" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PW\",\"nickname\":\"p3u$1\"}" >/dev/null 2>&1
  local body; body=$(curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PW\"}")
  TOK[$1]=$(echo "$body" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
  UID_[$1]=$(echo "$body" | grep -o '"userId":[0-9]*' | cut -d: -f2)
  [ -n "${TOK[$1]:-}" ] || { echo "login fail slot=$1: $body"; exit 1; }
}

mkchallenge() { # $1=approvalType $2=deposit $3=creatorSlot  -> id
  local resp; resp=$(curl -s -X POST "$API/api/challenges" -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${TOK[$3]}" \
    -d "{\"title\":\"p3_${1}_${STAMP}_$RANDOM\",\"category\":\"HEALTH\",\"verificationType\":\"GPS\",
         \"durationDays\":14,\"depositCoins\":$2,\"maxParticipants\":10,
         \"visibility\":\"PUBLIC\",\"approvalType\":\"$1\"}")
  echo "$resp" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2
}

join() { # $1=challengeId $2=slot -> HTTP code
  curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/challenges/$1/participants" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOK[$2]}" \
    -d '{"personalStatement":"join","gpsLat":37.5665,"gpsLng":126.9780,"gpsRadiusMeters":100,"gpsPlaceName":"CityHall"}'
}

hdr "prep: create 8 users"
for i in $(seq 1 8); do mkuser "$i"; done
ok "users ready (user_id ${UID_[1]}..${UID_[8]})"

# ── R1: 회원 탈퇴(soft delete)가 진행중 챌린지를 방치 ──────────────────────────
# withdraw()는 user.deactivate()만 한다(코드 주석: "B축 챌린지 연동은 통합 Phase에서 처리").
# → 탈퇴해도 CONFIRMED 참여/예치금/리더보드가 그대로 남는지 확인.
hdr "R1: 탈퇴 후 챌린지 참여·예치금 방치 (고아 데이터)"
CH1=$(mkchallenge AUTO 100 1)
if [ -z "${CH1:-}" ]; then skip "R1 챌린지 생성 실패"; else
  join "$CH1" 2 >/dev/null
  ST_BEFORE=$(psql_q "SELECT status FROM challenge_participants WHERE challenge_id=$CH1 AND user_id=${UID_[2]};")
  BAL_BEFORE=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[2]};")
  # 탈퇴
  WD=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$API/api/users/me" -H "Authorization: Bearer ${TOK[2]}")
  ST_AFTER=$(psql_q "SELECT status FROM challenge_participants WHERE challenge_id=$CH1 AND user_id=${UID_[2]};")
  BAL_AFTER=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[2]};")
  ACTIVE=$(psql_q "SELECT is_active FROM users WHERE id=${UID_[2]};")
  echo "  탈퇴 HTTP=$WD / 유저 is_active=$ACTIVE"
  echo "  참여상태 ${ST_BEFORE}→${ST_AFTER} / 예치금환불 코인 ${BAL_BEFORE}→${BAL_AFTER}"
  if [ "$ST_AFTER" = "CONFIRMED" ]; then
    bug "탈퇴해도 참여 CONFIRMED 유지 + 예치금 미환불(코인 ${BAL_AFTER}) — 정산 시 좀비 참여자로 집계됨"
  else
    ok "탈퇴 시 참여 정리됨 (status=$ST_AFTER)"
  fi
fi

# ── R2: 탈퇴한 유저의 토큰이 계속 먹히나 (좀비 세션) ───────────────────────────
# deactivate가 플래그만 세우고 기존 JWT를 막지 않으면, 탈퇴 유저가 계속 참여/체크인 가능.
hdr "R2: 탈퇴 유저 토큰으로 신규 참여 시도 (좀비 토큰)"
CH2=$(mkchallenge AUTO 0 3)
if [ -z "${CH2:-}" ]; then skip "R2 챌린지 생성 실패"; else
  ZC=$(join "$CH2" 2)   # slot2는 R1에서 이미 탈퇴함
  echo "  탈퇴 유저(slot2) 재참여 → HTTP $ZC"
  if [ "$ZC" = "201" ]; then bug "탈퇴 유저 토큰으로 신규 챌린지 참여 성공(201) — 세션 무효화 안 됨"
  elif [ "$ZC" = "401" ] || [ "$ZC" = "403" ]; then ok "탈퇴 유저 차단됨 (HTTP $ZC)"
  else skip "판단보류 HTTP $ZC"; fi
fi

# ── R3: 챌린지 체크인 목록 조회에 멤버십 검사 없음 (정보노출) ──────────────────
# GET /{id}/check-ins 컨트롤러엔 @AuthenticationPrincipal도 멤버십 검사도 없다.
# 비참여자(아무 로그인 유저)가 임의 challengeId로 남의 팀 체크인 현황을 통째로 읽나.
hdr "R3: 비참여자의 타 챌린지 체크인 목록 조회"
CH3=$(mkchallenge AUTO 0 1)
join "$CH3" 4 >/dev/null   # slot4만 참여
OUT_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$API/api/challenges/$CH3/check-ins" \
  -H "Authorization: Bearer ${TOK[5]}")   # slot5 = 완전 비참여자
echo "  비참여자(slot5) GET .../check-ins → HTTP $OUT_CODE"
if [ "$OUT_CODE" = "200" ]; then
  bug "비참여자가 임의 챌린지 체크인 목록 200 조회 — 멤버십 검사 없음(팀채팅 I2와 동일 계열)"
elif [ "$OUT_CODE" = "403" ] || [ "$OUT_CODE" = "404" ]; then ok "비참여자 차단 (HTTP $OUT_CODE)"
else skip "판단보류 HTTP $OUT_CODE"; fi

# ── R4: 종료 전 정산결과 조회 ────────────────────────────────────────────────
# GET /{id}/result 를 READY/ACTIVE 챌린지에 호출 시 500(미정 정산 접근)로 새는지.
hdr "R4: 종료 전(READY) 정산결과 조회 응답코드"
CH4=$(mkchallenge AUTO 0 6)
RES=$(curl -s -o /dev/null -w '%{http_code}' "$API/api/challenges/$CH4/result" -H "Authorization: Bearer ${TOK[6]}")
echo "  READY 챌린지 GET .../result → HTTP $RES"
if [ "$RES" = "500" ]; then bug "종료 전 정산결과 조회 500 (상태 가드 없음, 400/409여야)"
elif [ "$RES" = "200" ] || [ "$RES" = "400" ] || [ "$RES" = "404" ] || [ "$RES" = "409" ]; then ok "정산결과 조기조회 처리됨 (HTTP $RES)"
else skip "판단보류 HTTP $RES"; fi

# ── R5: 중복 참여(더블탭) → 409 (500 아님) ───────────────────────────────────
hdr "R5: 같은 챌린지 2회 참여 (Already applied)"
CH5=$(mkchallenge AUTO 0 1)
J1=$(join "$CH5" 7); J2=$(join "$CH5" 7)
echo "  1차 join=$J1 / 2차 join=$J2"
if [ "$J2" = "500" ]; then bug "중복 참여 → 500 (IllegalState 미매핑?)"
elif [ "$J2" = "409" ] || [ "$J2" = "400" ]; then ok "중복 참여 거부 (HTTP $J2)"
else skip "판단보류 2차 HTTP $J2"; fi

# ── R6: 비리더의 승인 시도 → 403 (권한상승 차단 확인) ─────────────────────────
hdr "R6: 비리더가 남을 승인 (권한상승)"
CH6=$(mkchallenge LEADER 0 1)   # 리더 = slot1
if [ -z "${CH6:-}" ]; then skip "R6 챌린지 생성 실패"; else
  join "$CH6" 7 >/dev/null       # slot7 PENDING
  PID=$(psql_q "SELECT id FROM challenge_participants WHERE challenge_id=$CH6 AND user_id=${UID_[7]};")
  # slot8(리더 아님)이 승인 시도
  AP=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/challenges/$CH6/participants/$PID/approve" \
    -H "Authorization: Bearer ${TOK[8]}")
  echo "  비리더(slot8) 승인 시도 → HTTP $AP"
  if [ "$AP" = "200" ]; then bug "비리더가 타인 승인 성공(200) — 권한상승"
  elif [ "$AP" = "403" ]; then ok "비리더 승인 차단 (403)"
  else skip "판단보류 HTTP $AP"; fi
fi

# ── R7: 잔액 부족 참여 → INSUFFICIENT_COIN 400, 잔액 음수 안 됨 ───────────────
hdr "R7: 예치금 > 잔액 참여 (음수/과차감)"
BAL7=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[8]};")
BIG=$(( ${BAL7:-0} + 100000 ))
CH7=$(mkchallenge AUTO "$BIG" 1)
if [ -z "${CH7:-}" ]; then skip "R7 챌린지 생성 실패(대형 예치금)"; else
  J7=$(join "$CH7" 8)
  BAL7A=$(psql_q "SELECT coin_balance FROM users WHERE id=${UID_[8]};")
  echo "  잔액 ${BAL7} / 예치금 ${BIG} / 참여 HTTP=$J7 / 참여후 잔액=${BAL7A}"
  if [ "${BAL7A:-0}" -lt 0 ]; then bug "잔액 음수(${BAL7A}) — 과차감"
  elif [ "$J7" = "400" ] && [ "${BAL7A:-0}" -eq "${BAL7:-0}" ]; then ok "잔액부족 거부(400) + 잔액 보존(${BAL7A})"
  elif [ "$J7" = "201" ]; then bug "잔액보다 큰 예치금인데 참여 성공(201) — 잔액검사 우회"
  else skip "판단보류 HTTP=$J7 잔액 ${BAL7}→${BAL7A}"; fi
fi

echo ""
echo -e "${CYAN}================================${NC}"
if [ "$BUGS" -eq 0 ]; then echo -e "${GREEN} 재현된 버그 없음${NC}"
else echo -e "${RED} 재현된 버그: ${BUGS}건${NC}"; fi
echo -e "${CYAN}================================${NC}"
