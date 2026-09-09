#!/usr/bin/env bash
# 사용자 여정 프로브 (J1~J8)
#
# 대상: 기존 프로브가 엔드포인트 단위 계약을 보는 것과 달리, 여기서는 실제 사용자가 앱에서
#       밟는 순서 그대로 여러 기능을 가로질러 따라간다. 버그는 기능 사이 경계에서 나온다.
#
# 방식: 여정을 실행하며 각 단계의 응답·DB 상태를 확인하고 [OK]/[BUG]/[INFO] 로 판정한다.
#       [INFO] 는 "틀렸다"가 아니라 사람이 판단해야 하는 관측치다.
#
# 범위 밖(단위테스트가 담당):
#   · 주간 채점(월 00:01) · 구제 만료(매일 00:10) · 월초 지급(1일 00:05) 스케줄러
#     → HTTP 트리거가 없다. J6 은 DB 로 상태를 심어 API 반응만 확인하고,
#       스케줄러 본문 자체는 WeeklyEvaluationServiceTest 가 검증한다.
#   · 날짜 이동이 필요한 것(주 경계, 월 경계) — 서버가 실시계라 프로브로 이동 불가
#
# 환경 주의(Windows/Git Bash):
#   · 요청 본문은 ASCII 로만 쓴다. mingw 셸이 인라인 한글을 CP949 로 망가뜨려 서버가
#     MALFORMED_REQUEST 를 돌려준다(서버는 UTF-8 정상 처리 — 셸 아티팩트).
#   · curl 은 mingw 빌드라 /tmp 절대경로를 못 읽는다. 업로드 파일은 상대경로로 넘긴다.
#
# 사용법: BASE=http://localhost:8080/api ./probe-user-journey.sh
set -u

BASE="${BASE:-http://localhost:8080/api}"
ROOT_URL="${BASE%/api}"
DB_CONTAINER="${DB_CONTAINER:-booster-db}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; BUG=0; INFO=0

ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
bug()  { echo "  [BUG]  $1"; BUG=$((BUG+1)); }
note() { echo "  [INFO] $1"; INFO=$((INFO+1)); }
hdr()  { echo; echo "── $1"; }
jrn()  { echo; echo "════════ $1 ════════"; }

code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
body() { curl -s "$@"; }
both() { curl -s -w "\n%{http_code}" "$@"; }   # 본문\n상태코드
jget() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(-\?[0-9][0-9]*\|\"[^\"]*\"\|true\|false\|null\).*/\1/p" <<<"$1" | head -1 | tr -d '"'; }
# psql: 오류를 삼키면 빈 문자열이 "0건"처럼 보여 오탐이 된다(컬럼명 오타 등). stderr 를 드러낸다.
psql_q() {
  local out rc
  out=$(docker exec "$DB_CONTAINER" psql -U booster -d booster -tAc "$1" 2>&1); rc=$?
  if [ $rc -ne 0 ] || grep -q '^ERROR:' <<<"$out"; then
    echo "  [SQL-ERR] $(grep -m1 '^ERROR:' <<<"$out" || head -1 <<<"$out")" >&2
    echo ""; return 1
  fi
  tr -d '\r' <<<"$out"
}
# 코인을 UPDATE 로 직접 넣으면 J5-3(잔액=거래합) 검사를 프로브가 스스로 깨뜨린다.
# 반드시 거래내역과 함께 넣는다.
grant_coins() {
  psql_q "update users set coin_balance = coin_balance + $2 where id=$1;
          insert into coin_transactions(user_id,type,amount,balance_after)
          select $1,'SIGNUP_BONUS',$2,coin_balance from users where id=$1" >/dev/null
}

STAMP=$(date +%s)
LAT=37.5; LNG=127.0
TMPD=".probe-$STAMP"          # curl 에 상대경로로 넘기기 위해 cwd 아래에 만든다
mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT

mkuser() {   # "userId TOKEN" 출력
  local tag="$1" email="j-${1}-${STAMP}@test.com" s
  s=$(body -X POST "$BASE/auth/signup" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"password1234\",\"nickname\":\"$tag\"}")
  echo "$(jget "$s" userId) $(jget "$s" accessToken)"
}
setloc() {   # $1=AUTH  ($2=radius)
  code -X POST "$BASE/users/me/location" -H "$1" -H 'Content-Type: application/json' \
    -d "{\"lat\":$LAT,\"lng\":$LNG,\"radiusMeters\":${2:-50},\"placeName\":\"home\"}"
}

echo "════════════════════════════════════════════"
echo " 사용자 여정 프로브   BASE=$BASE"
echo "════════════════════════════════════════════"
[ "$(code "$ROOT_URL/actuator/health")" = "200" ] || { echo "치명적: 백엔드 무응답"; exit 1; }

# ══════════════════════════════════════════════════════════════
jrn "J1  신규 사용자가 개인 습관을 시작한다"
# ══════════════════════════════════════════════════════════════
read -r U1 T1 <<<"$(mkuser a)"; A1="Authorization: Bearer $T1"; echo "userId=$U1"

hdr "J1-1  가입 직후 토큰으로 바로 API 를 쓸 수 있다 (login 재호출 불필요)"
[ "$(code "$BASE/personal/check-in/today" -H "$A1")" = "200" ] && ok "가입 토큰으로 인증 통과" || bug "가입 토큰이 안 먹힘"

hdr "J1-2  위치 등록 전 상태"
c=$(code "$ROOT_URL/api/dashboard/home" -H "$A1");  [ "$c" = "200" ] && ok "대시보드 200" || note "대시보드가 $c"
c=$(code "$BASE/personal/weekly-goal" -H "$A1");    [ "$c" = "400" ] && ok "주간목표 400 (위치 먼저)" || bug "주간목표가 $c"
c=$(code -X POST "$BASE/personal/check-in" -H "$A1" -H 'Content-Type: application/json' -d "{\"lat\":$LAT,\"lng\":$LNG}")
[ "$c" = "400" ] && ok "체크인 400 (위치 먼저)" || bug "체크인이 $c"

hdr "J1-3  위치를 등록한다"
c=$(setloc "$A1"); { [ "$c" = "200" ] || [ "$c" = "201" ]; } && ok "위치 등록 $c" || bug "위치 등록 실패: $c"

hdr "J1-4  등록 지점에서 멀리 떨어진 채 인증을 누른다"
r=$(both -X POST "$BASE/personal/check-in" -H "$A1" -H 'Content-Type: application/json' -d '{"lat":38.5,"lng":128.5}')
c=$(tail -1 <<<"$r"); b=$(head -1 <<<"$r")
[ "$c" = "400" ] && ok "400 즉시 거절" || bug "범위 밖 인증이 $c"
grep -q "GPS_OUT_OF_RANGE" <<<"$b" && ok "errorCode GPS_OUT_OF_RANGE" || bug "errorCode 없음: $(head -c 100 <<<"$b")"
grep -q "m " <<<"$b" && ok "거리 안내: $(sed -n 's/.*"message":"\([^"]*\)".*/\1/p' <<<"$b")" || note "거리 안내 없음"
[ "$(psql_q "select count(*) from personal_check_ins where user_id=$U1")" = "0" ] \
  && ok "실패는 레코드를 만들지 않음 (그날 재시도 가능)" || bug "실패인데 체크인 레코드가 생김"

hdr "J1-5  범위 안에서 인증"
r=$(body -X POST "$BASE/personal/check-in" -H "$A1" -H 'Content-Type: application/json' -d "{\"lat\":$LAT,\"lng\":$LNG}")
[ "$(jget "$r" status)" = "SUCCESS" ] && ok "SUCCESS 즉시 확정" || bug "status=$(jget "$r" status)"
cid=$(jget "$r" checkInId); { [ -n "$cid" ] && [ "$cid" != "null" ]; } && ok "checkInId 반환 ($cid)" || bug "checkInId 없음"
[ "$(jget "$r" currentStreak)" = "1" ] && ok "스트릭 1" || bug "스트릭=$(jget "$r" currentStreak)"

hdr "J1-6  같은 날 또 누른다 (앱 재시작 / 더블탭)"
r=$(both -X POST "$BASE/personal/check-in" -H "$A1" -H 'Content-Type: application/json' -d "{\"lat\":$LAT,\"lng\":$LNG}")
[ "$(tail -1 <<<"$r")" = "409" ] && ok "409 $(jget "$(head -1 <<<"$r")" errorCode)" || bug "중복이 $(tail -1 <<<"$r")"

hdr "J1-7  주간 목표에 반영됐는지"
g=$(body "$BASE/personal/weekly-goal" -H "$A1")
[ "$(jget "$g" successCount)" = "1" ]   && ok "successCount 1"  || bug "successCount=$(jget "$g" successCount)"
[ "$(jget "$g" targetDays)" = "3" ]     && ok "기본 목표 3회"    || bug "targetDays=$(jget "$g" targetDays)"
[ "$(jget "$g" verificationType)" = "GPS" ] && ok "기본 인증 GPS" || bug "vt=$(jget "$g" verificationType)"
[ "$(jget "$g" recoveryTickets)" = "1" ] && ok "가입 시 구제권 1" || bug "구제권=$(jget "$g" recoveryTickets)"

hdr "J1-8  반경을 아주 크게 잡는다 (상한이 있는가)"
read -r UR TR <<<"$(mkuser radius)"; AR="Authorization: Bearer $TR"
c=$(code -X POST "$BASE/users/me/location" -H "$AR" -H 'Content-Type: application/json' \
      -d '{"lat":37.5,"lng":127.0,"radiusMeters":20000000,"placeName":"earth"}')
if [ "$c" = "200" ] || [ "$c" = "201" ]; then
  note "반경 20,000km 등록이 $c 로 통과 — 지구 어디서나 인증 가능 (상한 미도입, 기존 인지 항목)"
  r=$(body -X POST "$BASE/personal/check-in" -H "$AR" -H 'Content-Type: application/json' -d '{"lat":-33.8,"lng":151.2}')
  [ "$(jget "$r" status)" = "SUCCESS" ] && bug "시드니 좌표로 인증 성공 — GPS 인증이 무력화됨" || ok "그래도 거절됨"
else
  ok "반경 상한 존재 ($c)"
fi

# ══════════════════════════════════════════════════════════════
jrn "J2  인증 방식을 AI 로 바꾸고 목표도 올린다"
# ══════════════════════════════════════════════════════════════
read -r U2 T2 <<<"$(mkuser b)"; A2="Authorization: Bearer $T2"; setloc "$A2" >/dev/null; echo "userId=$U2"

hdr "J2-1  목표 5회 + 인증방식 AI 로 변경"
g=$(body -X PUT "$BASE/personal/weekly-goal" -H "$A2" -H 'Content-Type: application/json' \
      -d '{"targetDays":5,"verificationType":"AI"}')
[ "$(jget "$g" targetDays)" = "3" ] && ok "목표는 아직 3 (예약만)" || bug "목표가 즉시 바뀜: $(jget "$g" targetDays)"
[ "$(jget "$g" pendingTargetDays)" = "5" ] && ok "pendingTargetDays 5 예약" || bug "pending=$(jget "$g" pendingTargetDays)"
[ "$(jget "$g" verificationType)" = "AI" ] \
  && note "인증방식은 즉시 반영 (목표=예약 / 방식=즉시 — 의도된 비대칭, DTO javadoc 에 근거 있음)" \
  || bug "vt=$(jget "$g" verificationType)"

hdr "J2-2  경계값 거절"
for p in '{"targetDays":3,"verificationType":"PHOTO"}:PHOTO' '{"targetDays":8}:목표8' '{"targetDays":1}:목표1' '{"targetDays":3,"verificationType":"GPS_PHOTO"}:GPS_PHOTO'; do
  d="${p%:*}"; n="${p##*:}"
  c=$(code -X PUT "$BASE/personal/weekly-goal" -H "$A2" -H 'Content-Type: application/json' -d "$d")
  [ "$c" = "400" ] && ok "$n 400 거절" || bug "$n 이 $c"
done
# 위 루프가 목표를 3 으로 되돌렸는지 무관하게 AI 로 되돌려 둔다
code -X PUT "$BASE/personal/weekly-goal" -H "$A2" -H 'Content-Type: application/json' \
  -d '{"targetDays":5,"verificationType":"AI"}' >/dev/null

hdr "J2-3  AI 목표에서 체크인하면 사진 대기가 된다"
r=$(body -X POST "$BASE/personal/check-in" -H "$A2" -H 'Content-Type: application/json' -d "{\"lat\":$LAT,\"lng\":$LNG}")
CID2=$(jget "$r" checkInId)
[ "$(jget "$r" status)" = "PENDING" ] && ok "PENDING (사진 대기)" || bug "status=$(jget "$r" status)"
{ [ -n "$CID2" ] && [ "$CID2" != "null" ]; } && ok "checkInId 반환 ($CID2)" || bug "checkInId 없음 → 사진 업로드 불가"
[ "$(jget "$r" currentStreak)" = "0" ] && ok "확정 전이라 스트릭 0" || bug "스트릭이 미리 오름: $(jget "$r" currentStreak)"

hdr "J2-4  AI 는 GPS 를 안 본다 (제주도에서 체크인)"
read -r U2B T2B <<<"$(mkuser b2)"; A2B="Authorization: Bearer $T2B"; setloc "$A2B" >/dev/null
code -X PUT "$BASE/personal/weekly-goal" -H "$A2B" -H 'Content-Type: application/json' -d '{"targetDays":3,"verificationType":"AI"}' >/dev/null
r=$(body -X POST "$BASE/personal/check-in" -H "$A2B" -H 'Content-Type: application/json' -d '{"lat":33.4,"lng":126.5}')
[ "$(jget "$r" status)" = "PENDING" ] && ok "AI 는 GPS 무시 → PENDING" || bug "제주도에서 status=$(jget "$r" status)"

hdr "J2-5  GPS_PHOTO_AI 는 GPS 를 먼저 본다"
read -r U2C T2C <<<"$(mkuser b3)"; A2C="Authorization: Bearer $T2C"; setloc "$A2C" >/dev/null
code -X PUT "$BASE/personal/weekly-goal" -H "$A2C" -H 'Content-Type: application/json' -d '{"targetDays":3,"verificationType":"GPS_PHOTO_AI"}' >/dev/null
c=$(code -X POST "$BASE/personal/check-in" -H "$A2C" -H 'Content-Type: application/json' -d '{"lat":33.4,"lng":126.5}')
[ "$c" = "400" ] && ok "범위 밖은 사진 전에 400" || bug "GPS_PHOTO_AI 범위밖이 $c"
r=$(body -X POST "$BASE/personal/check-in" -H "$A2C" -H 'Content-Type: application/json' -d "{\"lat\":$LAT,\"lng\":$LNG}")
[ "$(jget "$r" status)" = "PENDING" ] && ok "범위 안이면 PENDING" || bug "status=$(jget "$r" status)"

hdr "J2-6  사진을 안 올린 채 또 체크인을 누른다"
r=$(both -X POST "$BASE/personal/check-in" -H "$A2" -H 'Content-Type: application/json' -d "{\"lat\":$LAT,\"lng\":$LNG}")
[ "$(tail -1 <<<"$r")" = "409" ] && ok "409 $(jget "$(head -1 <<<"$r")" errorCode)" || bug "$(tail -1 <<<"$r")"

hdr "J2-7  사진 대기 중 오늘 상태 · 주간 집계"
[ "$(jget "$(body "$BASE/personal/check-in/today" -H "$A2")" status)" = "PENDING" ] && ok "today=PENDING" || bug "today 불일치"
[ "$(jget "$(body "$BASE/personal/weekly-goal" -H "$A2")" successCount)" = "0" ] \
  && ok "PENDING 은 successCount 에 안 셈" || bug "PENDING 이 집계됨"

# ══════════════════════════════════════════════════════════════
jrn "J3  사진을 올린다"
# ══════════════════════════════════════════════════════════════
IMG="$TMPD/img.png"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x0aIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\x0d\x0a-\xb4\x00\x00\x00\x00IEND\xaeB\x60\x82' > "$IMG"
echo "not an image" > "$TMPD/bad.txt"; : > "$TMPD/empty.png"

hdr "J3-1  남의 체크인에 사진을 올린다"
c=$(code -X POST "$BASE/personal/check-in/$CID2/ai-verification" -H "$A1" -F "image=@$IMG;type=image/png" -F "category=EXERCISE")
[ "$c" = "403" ] && ok "403 소유권 거절" || bug "소유권 검사가 $c"

hdr "J3-2  존재하지 않는 체크인"
c=$(code -X POST "$BASE/personal/check-in/99999999/ai-verification" -H "$A2" -F "image=@$IMG;type=image/png" -F "category=EXERCISE")
[ "$c" = "404" ] && ok "404" || bug "$c"

hdr "J3-3  형식 · 빈 파일 · 크기"
c=$(code -X POST "$BASE/personal/check-in/$CID2/ai-verification" -H "$A2" -F "image=@$TMPD/bad.txt;type=text/plain" -F "category=EXERCISE")
[ "$c" = "415" ] && ok "415 지원하지 않는 형식" || bug "text/plain 이 $c"
c=$(code -X POST "$BASE/personal/check-in/$CID2/ai-verification" -H "$A2" -F "image=@$TMPD/empty.png;type=image/png" -F "category=EXERCISE")
[ "$c" = "400" ] && ok "400 빈 파일" || bug "빈 파일이 $c"
head -c 11534336 /dev/urandom > "$TMPD/big.png"
c=$(code -X POST "$BASE/personal/check-in/$CID2/ai-verification" -H "$A2" -F "image=@$TMPD/big.png;type=image/png" -F "category=EXERCISE")
[ "$c" = "413" ] && ok "413 (10MB 초과)" || bug "11MB 가 $c"

hdr "J3-4  정상 이미지 업로드 (ai-service 연동)"
r=$(both -X POST "$BASE/personal/check-in/$CID2/ai-verification" -H "$A2" -F "image=@$IMG;type=image/png" -F "category=EXERCISE")
c=$(tail -1 <<<"$r"); b=$(head -1 <<<"$r")
echo "      → $c  $(head -c 150 <<<"$b")"
left=$(psql_q "select coalesce(max(status),'(deleted)') from personal_check_ins where id=$CID2")
if [ "$c" = "200" ]; then
  ok "AI 판정 수신 (passed=$(jget "$b" passed))"; note "체크인 상태: $left"
else
  note "ai-service 미기동/오류 ($c) — 실패 후 체크인이 어떻게 남는지가 관건"
  [ "$left" = "PENDING" ] && ok "PENDING 유지 → 그날 재시도 가능" \
    || bug "AI 호출 실패인데 체크인이 '$left' — 사용자가 그날 인증을 잃음"
fi

# ══════════════════════════════════════════════════════════════
jrn "J4  방장이 팀 챌린지를 열고 정원을 채운다"
# ══════════════════════════════════════════════════════════════
read -r UH TH <<<"$(mkuser host)"; AH="Authorization: Bearer $TH"; echo "hostId=$UH"
mkch() { # $1=추가필드
  echo "{\"category\":\"EXERCISE\",\"title\":\"probe-$STAMP\",\"description\":\"d\",\"verificationType\":\"GPS\",\"durationDays\":7,\"depositCoins\":100,\"visibility\":\"PUBLIC\",\"approvalType\":\"AUTO\",\"maxParticipants\":10${1:-}}"
}
GPSF=',"gpsLat":37.5,"gpsLng":127.0,"gpsRadiusMeters":50,"gpsPlaceName":"park"'

hdr "J4-1  생성 단계 거절 규칙"
c=$(code -X POST "$BASE/challenges" -H "$AH" -H 'Content-Type: application/json' -d "$(mkch)")
[ "$c" = "400" ] && ok "위치 없으면 400 LOCATION_REQUIRED" || bug "위치 없이 생성이 $c"
c=$(code -X POST "$BASE/challenges" -H "$AH" -H 'Content-Type: application/json' -d "$(mkch "$GPSF" | sed 's/"maxParticipants":10/"maxParticipants":6/')")
[ "$c" = "400" ] && ok "정원 6 은 400" || bug "정원 6 이 $c"
c=$(code -X POST "$BASE/challenges" -H "$AH" -H 'Content-Type: application/json' -d "$(mkch "$GPSF" | sed 's/"verificationType":"GPS"/"verificationType":"GPS_PHOTO"/')")
[ "$c" = "400" ] && ok "GPS_PHOTO 400 (좀비 챌린지 차단)" || bug "GPS_PHOTO 가 $c"

hdr "J4-2  정상 생성 — 방장 예치금"
before=$(psql_q "select coin_balance from users where id=$UH")
r=$(body -X POST "$BASE/challenges" -H "$AH" -H 'Content-Type: application/json' -d "$(mkch "$GPSF")")
CH=$(jget "$r" id); after=$(psql_q "select coin_balance from users where id=$UH")
{ [ -n "$CH" ] && [ "$CH" != "null" ]; } && ok "challengeId=$CH" || bug "생성 실패: $(head -c 140 <<<"$r")"
[ "$((before-after))" = "100" ] && ok "방장도 예치금 100 차감 ($before→$after)" || bug "방장 차감 $((before-after))"
[ "$(jget "$r" joined)" = "true" ] && ok "응답 joined=true" \
  || note "생성 응답 joined=false 인데 방장은 이미 CONFIRMED 참가자 — 앱이 '참가하기'를 노출할 수 있음"

hdr "J4-3  방장이 참가자 목록에 있는가"
p=$(body "$BASE/challenges/$CH/participants" -H "$AH")
n=$(grep -o '"userId"' <<<"$p" | wc -l | tr -d ' ')
[ "$n" = "1" ] && ok "참가자 1명(방장)" || bug "참가자 수=$n"
grep -q "\"userId\":$UH" <<<"$p" && ok "방장 포함" || bug "방장이 참가자가 아님"
grep -qi '"participantId"\|"id"' <<<"$p" && ok "participantId 노출 (승인 화면 필수)" || bug "participantId 없음"

hdr "J4-4  내 참여 챌린지 · 중복 참가"
grep -q "\"id\":$CH" <<<"$(body "$BASE/users/me/challenges" -H "$AH")" && ok "내 챌린지에 노출" || bug "내 챌린지에 없음"
c=$(code -X POST "$BASE/challenges/$CH/participants" -H "$AH" -H 'Content-Type: application/json' -d '{"gpsLat":37.5,"gpsLng":127.0,"gpsRadiusMeters":50}')
[ "$c" = "409" ] && ok "방장 재참가 409" || bug "방장 재참가가 $c"

hdr "J4-5  아직 정원이 안 찬(READY) 챌린지에서 체크인한다"
# ★ 순서 주의: 정원이 차면 TeamFormationService 가 startChallenge() 로 ACTIVE 를 만든다.
#   따라서 READY 검사는 반드시 9명이 들어오기 '전'에 해야 한다.
[ "$(psql_q "select status from challenges where id=$CH")" = "READY" ] || note "이미 READY 가 아님"
r=$(both -X POST "$BASE/challenges/$CH/check-ins" -H "$AH" -H 'Content-Type: application/json' -d '{"currentLat":37.5,"currentLng":127.0}')
c=$(tail -1 <<<"$r")
[ "$c" = "409" ] && ok "409 $(jget "$(head -1 <<<"$r")" errorCode)" || bug "READY 체크인이 $c: $(head -c 110 <<<"$(head -1 <<<"$r")")"

hdr "J4-6  나머지 9명이 참가한다 (10명 → 팀 편성)"
JOINED=0; PT=()
for i in $(seq 1 9); do
  read -r UU TT <<<"$(mkuser "p$i")"
  cc=$(code -X POST "$BASE/challenges/$CH/participants" -H "Authorization: Bearer $TT" \
        -H 'Content-Type: application/json' -d '{"gpsLat":37.5,"gpsLng":127.0,"gpsRadiusMeters":50}')
  { [ "$cc" = "201" ] || [ "$cc" = "200" ]; } && { JOINED=$((JOINED+1)); PT+=("$TT"); } || echo "      p$i 참가 실패: $cc"
done
[ "$JOINED" = "9" ] && ok "9명 참가 완료" || bug "참가 성공 $JOINED/9"

hdr "J4-7  정원이 찼으니 팀이 편성됐는가"
t=$(body "$BASE/challenges/$CH/teams" -H "$AH")
tn=$(grep -o '"teamId"\|"id"' <<<"$t" | wc -l | tr -d ' ')
assigned=$(psql_q "select count(*) from challenge_participants where challenge_id=$CH and team_id is not null")
[ "$assigned" = "10" ] && ok "10명 전원 팀 배정" || bug "팀 배정 인원=$assigned"
sizes=$(psql_q "select string_agg(c::text, '/') from (select count(*) c from challenge_participants where challenge_id=$CH group by team_id) x")
[ "$sizes" = "5/5" ] && ok "5:5 균등 편성" || note "팀 인원 분포 = $sizes"

hdr "J4-8  11번째가 참가를 시도한다"
read -r U11 T11 <<<"$(mkuser p11)"
c=$(code -X POST "$BASE/challenges/$CH/participants" -H "Authorization: Bearer $T11" -H 'Content-Type: application/json' -d '{"gpsLat":37.5,"gpsLng":127.0,"gpsRadiusMeters":50}')
{ [ "$c" = "409" ] || [ "$c" = "400" ]; } && ok "정원 초과 거절 ($c)" || bug "11번째가 $c"

hdr "J4-9  정원이 차면 자동으로 시작되는가"
st=$(psql_q "select status from challenges where id=$CH")
[ "$st" = "ACTIVE" ] && ok "팀 편성과 함께 ACTIVE 전환" || bug "정원이 찼는데 status=$st"

# ★ 체크인 검사는 매번 '아직 체크인 안 한' 참가자로 한다.
#   같은 사람으로 반복하면 첫 성공 뒤 멱등 응답(201)이 돌아와 GPS 우회처럼 오독된다.
hdr "J4-10  범위 밖에서 체크인 (미인증 참가자)"
PA="Authorization: Bearer ${PT[0]}"
r=$(both -X POST "$BASE/challenges/$CH/check-ins" -H "$PA" -H 'Content-Type: application/json' -d '{"currentLat":38.5,"currentLng":128.5}')
c=$(tail -1 <<<"$r"); b=$(head -1 <<<"$r")
[ "$c" = "400" ] && ok "400 즉시 거절 (개인 트랙과 통일)" || bug "팀 GPS 실패가 $c: $(head -c 120 <<<"$b")"
grep -q "GPS_OUT_OF_RANGE" <<<"$b" && ok "errorCode GPS_OUT_OF_RANGE (개인과 동일)" || note "errorCode: $(jget "$b" errorCode)"
grep -q "m " <<<"$b" && ok "거리 안내: $(sed -n 's/.*"message":"\([^"]*\)".*/\1/p' <<<"$b")" || note "거리 안내 없음"
[ "$(psql_q "select count(*) from challenge_check_ins where challenge_id=$CH and status='FAILED'")" = "0" ] \
  && ok "FAILED 레코드 0 (참여율 오염 없음)" || bug "FAILED 레코드가 남음"

hdr "J4-11  범위 안에서 체크인 (같은 참가자, 그날 아직 성공 전)"
r=$(both -X POST "$BASE/challenges/$CH/check-ins" -H "$PA" -H 'Content-Type: application/json' -d '{"currentLat":37.5,"currentLng":127.0}')
c=$(tail -1 <<<"$r"); b=$(head -1 <<<"$r")
{ [ "$c" = "200" ] || [ "$c" = "201" ]; } && ok "체크인 성공 $c" || bug "정상 체크인이 $c: $(head -c 120 <<<"$b")"
grep -qi "submissionId" <<<"$b" && ok "submissionId 반환 (AI 2단계 입력)" || note "submissionId 없음: $(head -c 120 <<<"$b")"

hdr "J4-12  같은 날 두 번 체크인 (멱등)"
r=$(both -X POST "$BASE/challenges/$CH/check-ins" -H "$PA" -H 'Content-Type: application/json' -d '{"currentLat":37.5,"currentLng":127.0}')
c=$(tail -1 <<<"$r")
n=$(psql_q "select count(*) from challenge_check_ins ci join challenge_participants p on p.id=ci.participant_id
            where ci.challenge_id=$CH and p.user_id=(select user_id from challenge_participants where id=(select participant_id from challenge_check_ins where challenge_id=$CH order by id desc limit 1))")
{ [ "$c" = "200" ] || [ "$c" = "201" ] || [ "$c" = "409" ]; } && ok "재체크인 $c" || bug "재체크인이 $c"
[ "$(psql_q "select count(*) from challenge_check_ins where challenge_id=$CH")" -le 2 ] 2>/dev/null \
  && ok "체크인 레코드가 중복 생성되지 않음" || note "체크인 레코드 수 확인 필요"

hdr "J4-14  참가 시 인증 반경 검증 (별도 챌린지)"
# ParticipationRequest.gpsRadiusMeters 는 @NotNull 뿐이다(개인 트랙의 LocationRequest 는 @Positive 있음).
# 하한은 DB CHECK(gps_radius_meters > 0) 가 대신 막고 있어 클라이언트 입력 오류가 409 로 나온다.
read -r UV TV <<<"$(mkuser rv)"; AV="Authorization: Bearer $TV"
CV=$(jget "$(body -X POST "$BASE/challenges" -H "$AV" -H 'Content-Type: application/json' \
      -d "$(mkch "$GPSF" | sed 's/"depositCoins":100/"depositCoins":0/')")" id)
for r in -1 0; do
  read -r _ TX <<<"$(mkuser "rv$r")"
  rr=$(both -X POST "$BASE/challenges/$CV/participants" -H "Authorization: Bearer $TX" \
        -H 'Content-Type: application/json' -d "{\"gpsLat\":37.5,\"gpsLng\":127.0,\"gpsRadiusMeters\":$r}")
  c=$(tail -1 <<<"$rr")
  if [ "$c" = "400" ]; then ok "반경 $r → 400 검증 거절"
  else bug "반경 $r 이 $c $(jget "$(head -1 <<<"$rr")" errorCode) — DTO 에 @Positive 가 없어 DB CHECK 가 대신 막는다(원인 불명 메시지)"; fi
done
read -r _ TX <<<"$(mkuser rvbig)"
c=$(code -X POST "$BASE/challenges/$CV/participants" -H "Authorization: Bearer $TX" \
      -H 'Content-Type: application/json' -d '{"gpsLat":37.5,"gpsLng":127.0,"gpsRadiusMeters":20000000}')
{ [ "$c" = "201" ] || [ "$c" = "200" ]; } \
  && bug "팀 참가 반경 20,000km 가 $c 로 통과 — 개인 트랙과 동일하게 GPS 인증 무력화" \
  || ok "반경 상한 존재 ($c)"

hdr "J4-13  범위 밖 체크인이 '이미 성공한 날' 을 덮지 않는가"
r=$(both -X POST "$BASE/challenges/$CH/check-ins" -H "$PA" -H 'Content-Type: application/json' -d '{"currentLat":38.5,"currentLng":128.5}')
c=$(tail -1 <<<"$r")
{ [ "$c" = "200" ] || [ "$c" = "201" ]; } \
  && note "이미 SUCCESS 한 날은 GPS 판정 전에 멱등 반환 ($c) — 성공이 보존되므로 의도된 순서로 보임" \
  || ok "범위 밖은 $c"

# ══════════════════════════════════════════════════════════════
jrn "J5  코인이 바닥난 사용자"
# ══════════════════════════════════════════════════════════════
read -r U5 T5 <<<"$(mkuser broke)"; A5="Authorization: Bearer $T5"; setloc "$A5" >/dev/null
echo "userId=$U5 (가입보너스 500 / 구제권 800)"

hdr "J5-1  500 코인으로 800 짜리 구제권을 산다"
r=$(both -X POST "$BASE/personal/recovery-tickets" -H "$A5")
[ "$(tail -1 <<<"$r")" = "400" ] && ok "400 잔액 부족" || bug "잔액 부족이 $(tail -1 <<<"$r")"
[ "$(psql_q "select coin_balance from users where id=$U5")" = "500" ] && ok "잔액 그대로 500" || bug "실패인데 잔액 변동"

hdr "J5-2  코인을 채우고 5회 반복 구매 (구매 한도 없음)"
grant_coins "$U5" 4500
for _ in 1 2 3 4 5; do code -X POST "$BASE/personal/recovery-tickets" -H "$A5" >/dev/null; done
bal=$(psql_q "select coin_balance from users where id=$U5")
tk=$(psql_q "select free_recovery_tickets||'/'||paid_recovery_tickets from users where id=$U5")
[ "$bal" = "1000" ] && ok "5×800=4000 정확히 차감 (무료/구매 = $tk)" || bug "잔액이 $bal (1000 이어야), 티켓 $tk"
note "구매 한도가 없다 — 코인만 있으면 무제한 비축 가능 (의도 확인 필요)"

hdr "J5-3  전역 코인 정합성"
[ "$(psql_q "select count(*) from users where coin_balance < 0")" = "0" ] && ok "음수 잔액 없음" || bug "음수 잔액 존재"
# ★ 이번 실행에서 만든 사용자만 본다. DB 는 이전 실행/수동 조작이 누적돼 있어 전수 검사는
#   과거 오염을 이번 회귀로 오독하게 만든다.
mm=$(psql_q "select count(*) from users u
             left join (select user_id, sum(amount) s from coin_transactions group by 1) t on t.user_id=u.id
             where u.email like 'j-%-$STAMP@test.com' and u.coin_balance <> coalesce(t.s,0)")
[ "$mm" = "0" ] && ok "이번 실행 사용자 전원 잔액 = 거래합" || bug "잔액≠거래합 $mm 명 (코인 증발/증식)"
old=$(psql_q "select count(*) from users u
              left join (select user_id, sum(amount) s from coin_transactions group by 1) t on t.user_id=u.id
              where u.email not like 'j-%-$STAMP@test.com' and u.coin_balance <> coalesce(t.s,0)")
[ "$old" = "0" ] || note "이전 데이터에 잔액≠거래합 $old 명 (과거 프로브의 직접 UPDATE 흔적 — 이번 회귀 아님)"

# ══════════════════════════════════════════════════════════════
jrn "J6  주간 목표를 놓쳐 구제 대기에 걸린다"
# ══════════════════════════════════════════════════════════════
read -r U6 T6 <<<"$(mkuser rescue)"; A6="Authorization: Bearer $T6"; setloc "$A6" >/dev/null
grant_coins "$U6" 4500
psql_q "update users set free_recovery_tickets=0, paid_recovery_tickets=0 where id=$U6" >/dev/null
WK=$(psql_q "select (date_trunc('week', current_date) - interval '7 day')::date")
echo "userId=$U6  대상주=$WK"

hdr "J6-1  미달 + 구제권 없음 → PENDING_RESCUE (스케줄러 대역)"
psql_q "insert into weekly_evaluations(user_id,week_start,target_days,success_count,result,rescue_deadline)
        values($U6,'$WK',3,1,'PENDING_RESCUE', now() + interval '2 day')" >/dev/null
EV=$(psql_q "select id from weekly_evaluations where user_id=$U6 and week_start='$WK'")
[ -n "$EV" ] && ok "생성 (id=$EV)" || bug "심기 실패"

hdr "J6-2  앱이 구제 안내 팝업을 띄울 수 있는가"
g=$(body "$BASE/personal/weekly-goal" -H "$A6")
[ "$(jget "$g" pendingRescueWeek)" = "$WK" ] && ok "pendingRescueWeek 노출" || bug "pendingRescueWeek=$(jget "$g" pendingRescueWeek)"
dl=$(jget "$g" rescueDeadline); { [ -n "$dl" ] && [ "$dl" != "null" ]; } && ok "rescueDeadline 노출" || bug "기한 없음"
[ "$(jget "$g" lateRescuePrice)" = "1200" ] && ok "사후 구매가 1200" || bug "lateRescuePrice=$(jget "$g" lateRescuePrice)"
[ "$(jget "$g" lastWeekResult)" = "PENDING_RESCUE" ] && ok "lastWeekResult 노출" || bug "lastWeekResult 불일치"

hdr "J6-3  확정 전에는 아무것도 안 깎인다 (유예의 핵심)"
[ "$(psql_q "select coin_balance from users where id=$U6")" = "5000" ] && ok "코인 그대로" || bug "미리 깎임"

hdr "J6-4  사후 구매로 구제한다"
before=$(psql_q "select coin_balance from users where id=$U6")
c=$(tail -1 <<<"$(both -X POST "$BASE/personal/rescue" -H "$A6")")
after=$(psql_q "select coin_balance from users where id=$U6")
[ "$c" = "200" ] && ok "구제 성공" || bug "구제가 $c"
[ "$((before-after))" = "1200" ] && ok "1200 차감 ($before→$after)" || bug "차감액 $((before-after))"
[ "$(psql_q "select result from weekly_evaluations where id=$EV")" = "RESCUED" ] && ok "RESCUED 확정" || bug "result 불일치"

hdr "J6-5  이미 구제한 주를 또 구제한다"
[ "$(tail -1 <<<"$(both -X POST "$BASE/personal/rescue" -H "$A6")")" = "404" ] && ok "404 NO_PENDING_RESCUE" || bug "재구제 허용됨"

hdr "J6-6  기한이 지난 구제를 사려 한다"
psql_q "insert into weekly_evaluations(user_id,week_start,target_days,success_count,result,rescue_deadline)
        values($U6,'$WK'::date - 7,3,0,'PENDING_RESCUE', now() - interval '1 hour')" >/dev/null
[ "$(tail -1 <<<"$(both -X POST "$BASE/personal/rescue" -H "$A6")")" = "400" ] && ok "400 RESCUE_DEADLINE_PASSED" || bug "기한 경과 구매가 통과"

hdr "J6-7  ★ 만료 스케줄러가 두 번 돌면 (다중 인스턴스)"
# expireOverdueRescues 는 HTTP 트리거가 없다. 그 메서드가 최종적으로 내보내는 UPDATE 를
# 그대로 재현해, DB 가 '이미 처리됨'을 막아주는지 본다. markFailed() 는 더티체킹 UPDATE 라
# WHERE 절이 id 뿐이다 → 두 번째 인스턴스의 쓰기를 막을 수단이 DB 에 있는지가 쟁점.
EV2=$(psql_q "select id from weekly_evaluations where user_id=$U6 and result='RESCUED' limit 1")
n=$(psql_q "with u as (update weekly_evaluations set result='FAILED', rescue_deadline=null where id=$EV2 returning 1) select count(*) from u")
if [ "$n" = "1" ]; then
  bug "RESCUED(구제 완료) 행이 조건 없는 UPDATE 로 FAILED 가 됨 — 만료 경로에 DB 방어 없음"
  echo "         · 주간 채점은 UNIQUE(user_id, week_start) 로 막히지만 만료 경로는 무방비"
  echo "         · 인스턴스 N대가 00:10 에 동시 실행되면 같은 사용자에게 벌칙이 N번 적용"
else
  ok "DB 가 중복 만료를 거부"
fi
psql_q "update weekly_evaluations set result='RESCUED' where id=$EV2" >/dev/null

hdr "J6-8  WeeklyGoalScheduler 에 분산락이 걸려 있는가"
WGS="$REPO_ROOT/backend/src/main/java/com/booster/weeklygoal/scheduler/WeeklyGoalScheduler.java"
CES="$REPO_ROOT/backend/src/main/java/com/booster/settlement/service/ChallengeEndScheduler.java"
if grep -qs "SchedulerLock" "$WGS"; then ok "@SchedulerLock 있음"
else
  grep -qs "SchedulerLock" "$CES" && extra=" (ChallengeEndScheduler 에는 있음)" || extra=""
  bug "WeeklyGoalScheduler 에 @SchedulerLock 없음$extra — docker-compose.multi.yml 구성에서 3중 실행"
fi

# ══════════════════════════════════════════════════════════════
jrn "J7  탈퇴한 사용자"
# ══════════════════════════════════════════════════════════════
read -r U7 T7 <<<"$(mkuser gone)"; A7="Authorization: Bearer $T7"; setloc "$A7" >/dev/null
grant_coins "$U7" 4500; psql_q "update users set is_active=false where id=$U7" >/dev/null
echo "userId=$U7 (탈퇴 처리, 토큰은 살아 있음)"

hdr "J7-1  탈퇴자의 살아 있는 토큰으로 쓰기 시도"
# JwtAuthenticationFilter 가 매 요청 is_active 를 확인해 401 로 끊는다(필터 주석에 근거).
# 서비스 계층의 403 INACTIVE_USER 까지 가지 않으므로 401/403 을 모두 '차단'으로 본다.
blocked() { [ "$1" = "401" ] || [ "$1" = "403" ]; }
c=$(code -X POST "$BASE/personal/check-in" -H "$A7" -H 'Content-Type: application/json' -d "{\"lat\":$LAT,\"lng\":$LNG}")
blocked "$c" && ok "체크인 차단 ($c)" || bug "체크인이 $c"
c=$(code -X POST "$BASE/personal/recovery-tickets" -H "$A7")
blocked "$c" && ok "구제권 구매 차단 ($c)" || bug "구제권 구매가 $c"
c=$(code -X POST "$BASE/challenges" -H "$A7" -H 'Content-Type: application/json' -d "$(mkch "$GPSF")")
blocked "$c" && ok "챌린지 생성 차단 ($c)" || bug "탈퇴자가 챌린지를 만듦: $c"
[ "$c" = "401" ] && note "차단 코드가 401 — 앱은 '토큰 만료'로 해석해 재로그인을 시도할 수 있다(탈퇴 안내 불가)"

hdr "J7-2  주간 채점 대상에서 빠지는가"
[ "$(psql_q "select is_active from users where id=$U7")" = "f" ] && ok "active=false (findAllByActiveTrue 로 제외)" || bug "active 불일치"

# ══════════════════════════════════════════════════════════════
jrn "J8  전역 정합성 점검"
# ══════════════════════════════════════════════════════════════
hdr "J8-1  고아 · 중복 레코드"
o=$(psql_q "select count(*) from personal_ai_verifications a left join personal_check_ins c on c.id=a.personal_check_in_id where c.id is null")
[ "$o" = "0" ] && ok "AI 판정 고아 0" || bug "고아 AI 판정 $o 건"
d=$(psql_q "select count(*) from (select user_id, week_start from weekly_evaluations group by 1,2 having count(*)>1) x")
[ "$d" = "0" ] && ok "중복 채점 없음" || bug "중복 채점 $d 건"
d=$(psql_q "select count(*) from (select user_id, check_in_date from personal_check_ins group by 1,2 having count(*)>1) x")
[ "$d" = "0" ] && ok "개인 인증 1일 1건 유지" || bug "하루 중복 인증 $d 건"

hdr "J8-2  방치된 PENDING 체크인"
p=$(psql_q "select count(*) from personal_check_ins where status='PENDING' and check_in_date < current_date")
[ "$p" = "0" ] && ok "과거 PENDING 없음" \
  || note "과거 PENDING $p 건 — 정리 주체가 없다(집계엔 안 들어가지만 계속 쌓임)"

hdr "J8-3  AI 거절 이력이 남는가"
av=$(psql_q "select count(*) from personal_ai_verifications where is_passed=false")
[ "$av" -gt 0 ] 2>/dev/null && ok "거절 이력 $av 건 보존" \
  || note "거절 이력 0건 — 거절 시 체크인을 지우면 CASCADE 로 판정도 함께 삭제된다(로그만 남음)"

hdr "J8-4  마이그레이션"
fv=$(psql_q "select count(*) from flyway_schema_history where success=false")
mx=$(psql_q "select max(version::numeric) from flyway_schema_history")
[ "$fv" = "0" ] && ok "실패한 마이그레이션 0 (최신 V$mx)" || bug "실패 마이그레이션 $fv 건"

echo
echo "════════════════════════════════════════════"
printf " OK %d   BUG %d   INFO %d\n" "$PASS" "$BUG" "$INFO"
echo "════════════════════════════════════════════"
[ "$BUG" -eq 0 ]
