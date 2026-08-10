#!/usr/bin/env bash
# 프론트 블로킹 이슈 수정 검증 프로브 (F1~F10)
#
# 대상: docs/backend/frontend-blocking-backend-issues.md 의 #1~#8 (7번 제외)
#       + 백엔드 리뷰에서 추가로 찾은 항목(submissionId / multipart / 가입토큰 / 에러코드 / 좀비타입)
# 방식: 시나리오를 던지고 응답으로 [OK]/[BUG] 판정한다.
set -u

BASE="${BASE:-http://localhost:8080/api}"
DB_CONTAINER="${DB_CONTAINER:-booster-db}"
PASS=0; BUG=0

ok()  { echo "  [OK]  $1"; PASS=$((PASS+1)); }
bug() { echo "  [BUG] $1"; BUG=$((BUG+1)); }
hdr() { echo; echo "── $1"; }
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
body() { curl -s "$@"; }
jget() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(-\?[0-9][0-9.]*\|\"[^\"]*\"\|true\|false\|null\).*/\1/p" <<<"$1" | head -1 | tr -d '"'; }
psql_q() { docker exec "$DB_CONTAINER" psql -U booster -d booster -tAc "$1" 2>/dev/null | tr -d '\r'; }

STAMP=$(date +%s%N | tail -c 8)
# 사용자 생성 + 로그인 (전역 TOKEN/USER_ID 설정)
mkuser() {
  local tag="$1"
  local email="fb-${tag}-${STAMP}@test.com"
  local s
  s=$(body -X POST "$BASE/auth/signup" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"password1234\",\"nickname\":\"$tag\"}")
  USER_ID=$(jget "$s" userId)
  SIGNUP_BODY="$s"
  TOKEN=$(jget "$s" accessToken)
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    local l=$(body -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
      -d "{\"email\":\"$email\",\"password\":\"password1234\"}")
    TOKEN=$(jget "$l" accessToken)
  fi
  AUTH="Authorization: Bearer $TOKEN"
}
setloc() { code -X POST "$BASE/users/me/location" -H "$AUTH" -H 'Content-Type: application/json' \
    -d '{"lat":37.5,"lng":127.0,"radiusMeters":50,"placeName":"home"}' >/dev/null; }
givecoins() { psql_q "update users set coin_balance=$2 where id=$1" >/dev/null; }

echo "════════ 프론트 블로킹 이슈 수정 검증 ════════"

# ── F1. 가입 응답에 accessToken (BCrypt 2회 제거) ──────────────
hdr "F1  가입 응답에 accessToken 포함"
mkuser leader
tok=$(jget "$SIGNUP_BODY" accessToken)
[ -n "$tok" ] && [ "$tok" != "null" ] \
  && ok "가입 응답만으로 인증 가능 (로그인 재호출 불필요)" || bug "accessToken 없음"
c=$(code "$BASE/users/me" -H "Authorization: Bearer $tok")
[ "$c" = "200" ] && ok "가입 토큰으로 즉시 API 호출 성공" || bug "가입 토큰이 안 먹힘: $c"

# ── F2. 정원 10명 고정 ─────────────────────────────────────────
hdr "F2  정원 10명 고정 (#1)"
setloc
givecoins "$USER_ID" 100000
mk() { body -X POST "$BASE/challenges" -H "$AUTH" -H 'Content-Type: application/json' -d "$1"; }
mkc() { code -X POST "$BASE/challenges" -H "$AUTH" -H 'Content-Type: application/json' -d "$1"; }
BASE_CH='"category":"EXERCISE","title":"probe","verificationType":"GPS","durationDays":7,"depositCoins":100,"visibility":"PUBLIC","approvalType":"AUTO"'
for v in 4 6 8 2; do
  c=$(mkc "{$BASE_CH,\"maxParticipants\":$v}")
  [ "$c" = "400" ] && ok "정원 $v → 400 거절" || bug "정원 $v → $c (400 기대)"
done
c=$(mkc "{$BASE_CH,\"maxParticipants\":10}")
[ "$c" = "201" ] && ok "정원 10 → 201 생성" || bug "정원 10 → $c (201 기대)"

# ── F3. 방장 자동 참가 (#2) ────────────────────────────────────
hdr "F3  방장이 생성 즉시 CONFIRMED 참가자 (#2)"
coins_before=$(psql_q "select coin_balance from users where id=$USER_ID")
ch=$(mk "{$BASE_CH,\"maxParticipants\":10}")
CH_ID=$(jget "$ch" id)
coins_after=$(psql_q "select coin_balance from users where id=$USER_ID")
st=$(psql_q "select status from challenge_participants where challenge_id=$CH_ID and user_id=$USER_ID")
cnt=$(psql_q "select count(*) from challenge_participants where challenge_id=$CH_ID")
[ "$st" = "CONFIRMED" ] && ok "방장 participant status=CONFIRMED" || bug "방장 상태='$st' (CONFIRMED 기대)"
[ "$cnt" = "1" ]        && ok "생성 직후 참가자 1명"              || bug "참가자 $cnt 명"
[ "$((coins_before-coins_after))" = "100" ] \
  && ok "방장도 예치금 100 차감 (정산 풀 정합)" || bug "예치금 차감 $((coins_before-coins_after)) (100 기대)"
gps=$(psql_q "select gps_lat is not null and gps_radius_meters is not null from challenge_participants where challenge_id=$CH_ID and user_id=$USER_ID")
[ "$gps" = "t" ] && ok "개인 인증 위치로 GPS 기준 자동 설정" || bug "방장 GPS 미설정"

# ── F4. 참가자 목록 조회 (#3) ──────────────────────────────────
hdr "F4  참가자 목록 조회 API (#3)"
lst=$(body "$BASE/challenges/$CH_ID/participants" -H "$AUTH")
n=$(grep -o '"participantId"\|"id"' <<<"$lst" | wc -l)
[ "$(code "$BASE/challenges/$CH_ID/participants" -H "$AUTH")" = "200" ] \
  && ok "방장 조회 200" || bug "방장 조회 실패"
[ "$(code "$BASE/challenges/$CH_ID/participants?status=PENDING" -H "$AUTH")" = "200" ] \
  && ok "status=PENDING 필터 동작" || bug "status 필터 실패"
LEADER_TOKEN="$TOKEN"; LEADER_AUTH="$AUTH"; LEADER_ID="$USER_ID"
mkuser outsider
c=$(code "$BASE/challenges/$CH_ID/participants" -H "$AUTH")
[ "$c" = "403" ] && ok "비참여자 조회 차단 403 (정보노출 방지)" || bug "비참여자 → $c (403 기대)"

# ── F5. 참여여부 플래그 (#5) ───────────────────────────────────
hdr "F5  공개 목록의 joined 플래그 (#5)"
mine=$(body "$BASE/challenges?keyword=probe" -H "$LEADER_AUTH")
grep -q '"joined"' <<<"$mine" && ok "응답에 joined 필드 존재" || bug "joined 필드 없음"
grep -q '"joined":true' <<<"$mine" && ok "참여 중 챌린지가 joined=true" || bug "joined=true 항목 없음"
others=$(body "$BASE/challenges?keyword=probe" -H "$AUTH")
grep -q '"joined":false' <<<"$others" && ok "비참여자에겐 joined=false" || bug "비참여자 joined=false 없음"

# ── F6. 내 참여 챌린지 (#4) ────────────────────────────────────
hdr "F6  내가 참여 중인 챌린지 API (#4)"
my=$(body "$BASE/users/me/challenges" -H "$LEADER_AUTH")
grep -q "\"id\":$CH_ID" <<<"$my" && ok "방장 목록에 생성한 챌린지 포함" || bug "내 챌린지에 안 나옴"
mine_none=$(body "$BASE/users/me/challenges" -H "$AUTH")
grep -q "\"id\":$CH_ID" <<<"$mine_none" && bug "비참여자에게 남의 챌린지가 노출됨" || ok "비참여자 목록엔 없음"

# ── F7. 미지원 인증 방식 차단 (좀비 챌린지) ────────────────────
hdr "F7  PHOTO/GPS_PHOTO 챌린지 생성 차단"
AUTH="$LEADER_AUTH"
for vt in PHOTO GPS_PHOTO; do
  c=$(mkc "{\"category\":\"EXERCISE\",\"title\":\"z\",\"verificationType\":\"$vt\",\"durationDays\":7,\"depositCoins\":0,\"visibility\":\"PUBLIC\",\"approvalType\":\"AUTO\",\"maxParticipants\":10}")
  [ "$c" = "400" ] && ok "$vt → 400 (체크인 불가한 좀비 챌린지 차단)" || bug "$vt → $c (400 기대)"
done
for vt in GPS AI GPS_PHOTO_AI; do
  c=$(mkc "{\"category\":\"EXERCISE\",\"title\":\"z\",\"verificationType\":\"$vt\",\"durationDays\":7,\"depositCoins\":0,\"visibility\":\"PUBLIC\",\"approvalType\":\"AUTO\",\"maxParticipants\":10}")
  [ "$c" = "201" ] && ok "$vt → 201 (지원 방식)" || bug "$vt → $c (201 기대)"
done

# ── F8. 에러코드 세분화 ────────────────────────────────────────
hdr "F8  409 에러코드 세분화 (ILLEGAL_STATE 뭉침 해소)"
ch2=$(mk "{$BASE_CH,\"maxParticipants\":10}")
CH2=$(jget "$ch2" id)
# 방장은 이미 참가자 → 재신청은 ALREADY_APPLIED
r=$(body -X POST "$BASE/challenges/$CH2/participants" -H "$AUTH" -H 'Content-Type: application/json' \
   -d '{"gpsLat":37.5,"gpsLng":127.0,"gpsRadiusMeters":50}')
ec=$(jget "$r" errorCode)
[ "$ec" = "ALREADY_APPLIED" ] && ok "중복 참가 → ALREADY_APPLIED" || bug "errorCode=$ec (ALREADY_APPLIED 기대)"
# READY 챌린지에서 체크인 → CHALLENGE_NOT_ACTIVE
r=$(body -X POST "$BASE/challenges/$CH2/check-ins" -H "$AUTH" -H 'Content-Type: application/json' \
   -d '{"currentLat":37.5,"currentLng":127.0}')
ec=$(jget "$r" errorCode)
[ "$ec" = "CHALLENGE_NOT_ACTIVE" ] && ok "미시작 체크인 → CHALLENGE_NOT_ACTIVE" || bug "errorCode=$ec (CHALLENGE_NOT_ACTIVE 기대)"
[ "$ec" != "ILLEGAL_STATE" ] && ok "더 이상 ILLEGAL_STATE 로 뭉치지 않음" || bug "여전히 ILLEGAL_STATE"

# ── F9. multipart 업로드 상한 ──────────────────────────────────
hdr "F9  AI 인증 multipart 상한 (기본 1MB → 10MB)"
# ※ 파일 경로는 curl(Windows 네이티브)이 읽을 수 있는 형태여야 한다. Git Bash 의 /tmp 경로를
#   그대로 넘기면 curl 이 파일을 못 읽고 exit=26 / HTTP=000 이 되어 "통과"로 오판된다.
UPDIR="${UPLOAD_DIR:-$PWD/.probe-tmp}"
mkdir -p "$UPDIR"
UPWIN=$(cd "$UPDIR" && pwd -W 2>/dev/null || echo "$UPDIR")
upload() { # $1=바이트
  head -c "$1" /dev/urandom > "$UPDIR/up.jpg"
  curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$BASE/verification-submissions/999999/ai-verification" \
    -H "$AUTH" -F "category=EXERCISE" -F "image=@${UPWIN}/up.jpg;type=image/jpeg"
}
r=$(upload 3000000)   # 3MB — 예전 1MB 상한이면 여기서 거부됐다
# 존재하지 않는 submissionId 이므로 404 가 정상 = multipart 를 통과해 서비스까지 도달했다는 뜻.
[ "$r" = "404" ] && ok "3MB 업로드가 서비스까지 도달 (404 = 상한 통과)" \
                 || bug "3MB 업로드 → $r (404 기대. 000이면 curl이 파일을 못 읽은 것)"
r=$(upload 11000000)  # 11MB — 상한 초과
[ "$r" = "413" ] && ok "11MB → 413 PAYLOAD_TOO_LARGE" \
                 || bug "11MB → $r (413 기대. 500이면 상한 초과가 서버 오류로 나감)"
rm -rf "$UPDIR"

# ── F10. 인증 결과 상세 조회 (#8) ──────────────────────────────
hdr "F10 인증 결과 상세 조회 API (#8)"
c=$(code "$BASE/check-ins/999999/verification-submissions" -H "$AUTH")
[ "$c" = "404" ] && ok "엔드포인트 존재 (없는 checkInId → 404)" || bug "→ $c (404 기대, 405/500이면 미구현)"
c=$(code "$BASE/check-ins/999999/verification-submissions")
[ "$c" = "401" ] && ok "토큰 없이 호출 → 401" || bug "→ $c (401 기대)"

echo
echo "════════════════════════════════"
echo "  OK  $PASS 건"
echo "  BUG $BUG 건"
echo "════════════════════════════════"
exit $BUG
