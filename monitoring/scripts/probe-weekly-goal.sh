#!/usr/bin/env bash
# 주간 목표 모델 프로브 (W1~W12)
#
# 대상: 복귀 미션 폐지 → 주간 채점 + 구제권 전환 후의 A축 개인 트랙 HTTP 계약.
# 방식: 가설 기반 탐침 — 시나리오를 던지고 응답으로 [OK]/[BUG] 판정한다.
#
# 범위 밖(단위테스트가 담당):
#   · 주간 채점 자체(매주 월 00:01 스케줄러) — HTTP 트리거가 없어 프로브로 호출 불가
#     → WeeklyEvaluationServiceTest 10개가 ACHIEVED/RESCUED/FAILED·멱등·이월을 검증
#   · 날짜 갭이 스트릭을 끊지 않는 것 — 서버가 실시계라 프로브로 날짜 이동 불가
#     → PersonalCheckInServiceTest.gapDay_doesNotBreakStreak
set -u

BASE="${BASE:-http://localhost:8080/api}"
DB_CONTAINER="${DB_CONTAINER:-booster-db}"
PASS=0; BUG=0

ok()  { echo "  [OK]  $1"; PASS=$((PASS+1)); }
bug() { echo "  [BUG] $1"; BUG=$((BUG+1)); }
hdr() { echo; echo "── $1"; }

# HTTP 상태코드만
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
# 본문만
body() { curl -s "$@"; }
# JSON 스칼라 추출 (중첩 없는 평면 응답 전용)
jget() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(-\?[0-9][0-9]*\|\"[^\"]*\"\|true\|false\|null\).*/\1/p" <<<"$1" | head -1 | tr -d '"'; }

psql_q() { docker exec "$DB_CONTAINER" psql -U booster -d booster -tAc "$1" 2>/dev/null | tr -d '\r'; }

echo "════════ 주간 목표 프로브 ════════"
echo "BASE=$BASE"

# ── 사용자 준비 ────────────────────────────────────────────────
STAMP=$(date +%s)
EMAIL="wk-probe-${STAMP}@test.com"
signup=$(body -X POST "$BASE/auth/signup" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"password1234\",\"nickname\":\"probe\"}")
USER_ID=$(jget "$signup" userId)
login=$(body -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"password1234\"}")
TOKEN=$(jget "$login" accessToken)
AUTH="Authorization: Bearer $TOKEN"

if [ -z "${TOKEN:-}" ] || [ "$TOKEN" = "null" ]; then
  echo "치명적: 로그인 실패. 백엔드가 떠 있는지 확인하세요."; exit 1
fi
echo "userId=$USER_ID"

# ── W1. 신규 가입 기본값 ────────────────────────────────────────
hdr "W1  신규 가입 기본값 (구제권 1개 지급)"
tickets=$(psql_q "select free_recovery_tickets + paid_recovery_tickets from users where id=$USER_ID")
coins=$(psql_q "select coin_balance from users where id=$USER_ID")
[ "$tickets" = "1" ] && ok "구제권 1개 지급됨" || bug "구제권이 1이 아님: '$tickets'"
[ "$coins" = "500" ] && ok "가입 보너스 500" || bug "코인이 500이 아님: '$coins'"

# ── W2. 위치 미등록 상태 조회 ──────────────────────────────────
hdr "W2  위치 미등록 상태에서 목표 조회"
c=$(code "$BASE/personal/weekly-goal" -H "$AUTH")
[ "$c" = "400" ] && ok "400 LOCATION_NOT_REGISTERED" || bug "400이어야 하는데 $c"

# ── 위치 등록 ──────────────────────────────────────────────────
code -X POST "$BASE/users/me/location" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"lat":37.5,"lng":127.0,"radiusMeters":50,"placeName":"home"}' >/dev/null

# ── W3. 목표 기본값 ────────────────────────────────────────────
hdr "W3  목표 기본값 · 구제권 노출"
g=$(body "$BASE/personal/weekly-goal" -H "$AUTH")
t=$(jget "$g" targetDays); p=$(jget "$g" pendingTargetDays)
rt=$(jget "$g" recoveryTickets); rd=$(jget "$g" remainingDays)
[ "$t" = "3" ]    && ok "기본 목표 3회"        || bug "targetDays=$t (3 기대)"
[ "$p" = "null" ] && ok "예약 목표 없음"        || bug "pendingTargetDays=$p (null 기대)"
[ "$rt" = "1" ]   && ok "구제권 1개 노출"       || bug "recoveryTickets=$rt (1 기대)"
{ [ "$rd" -ge 1 ] && [ "$rd" -le 7 ]; } && ok "남은 날수 $rd (1~7)" || bug "remainingDays=$rd 범위 밖"

# ── W4. 체크인은 코인을 주지 않는다 (보상은 주간 채점으로 이동) ──
hdr "W4  개인 체크인 — 스트릭만 오르고 코인은 불변"
ci=$(body -X POST "$BASE/personal/check-in" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"lat":37.5,"lng":127.0}')
s=$(jget "$ci" currentStreak); rg=$(jget "$ci" rewardGranted); cb=$(jget "$ci" coinBalance)
[ "$s" = "1" ]      && ok "스트릭 1"                   || bug "currentStreak=$s (1 기대)"
[ "$rg" = "false" ] && ok "1회 인증은 마일스톤(7회) 미도달 → 보상 없음" || bug "rewardGranted=$rg (false 기대)"
[ "$cb" = "500" ]   && ok "코인 불변 500"              || bug "coinBalance=$cb (500 기대)"

# ── W5. 중복 체크인 ────────────────────────────────────────────
hdr "W5  같은 날 중복 체크인"
c=$(code -X POST "$BASE/personal/check-in" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"lat":37.5,"lng":127.0}')
[ "$c" = "409" ] && ok "409 DUPLICATE_CHECK_IN" || bug "409여야 하는데 $c"

# ── W6. 이번 주 진행률 반영 ────────────────────────────────────
hdr "W6  이번 주 진행률"
g=$(body "$BASE/personal/weekly-goal" -H "$AUTH")
sc=$(jget "$g" successCount)
[ "$sc" = "1" ] && ok "successCount=1" || bug "successCount=$sc (1 기대)"

# ── W7. 목표 변경은 예약만 되고 진행 중인 주는 안 바뀐다 ───────
hdr "W7  목표 변경 — 예약만 되고 이번 주 기준은 불변"
u=$(body -X PUT "$BASE/personal/weekly-goal" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"targetDays":5}')
t=$(jget "$u" targetDays); p=$(jget "$u" pendingTargetDays)
[ "$t" = "3" ] && ok "이번 주 기준 3 유지 (주 중간 하향 회피 차단)" || bug "targetDays=$t (3 기대)"
[ "$p" = "5" ] && ok "다음 달 목표 5로 예약"                        || bug "pendingTargetDays=$p (5 기대)"

# ── W8. 목표 범위 검증 ─────────────────────────────────────────
hdr "W8  목표 범위 밖 값 거절 (2~7)"
for v in 1 8 0 -1; do
  c=$(code -X PUT "$BASE/personal/weekly-goal" -H "$AUTH" -H 'Content-Type: application/json' \
    -d "{\"targetDays\":$v}")
  [ "$c" = "400" ] && ok "targetDays=$v → 400" || bug "targetDays=$v → $c (400 기대)"
done

# ── W9. 구제권 구매 — 잔액 부족 ────────────────────────────────
hdr "W9  구제권 구매 — 잔액 부족(500 < 800)"
before=$(psql_q "select coin_balance from users where id=$USER_ID")
c=$(code -X POST "$BASE/personal/recovery-tickets" -H "$AUTH")
after=$(psql_q "select coin_balance from users where id=$USER_ID")
tk=$(psql_q "select free_recovery_tickets + paid_recovery_tickets from users where id=$USER_ID")
[ "$c" = "400" ]         && ok "400 거절"                 || bug "400이어야 하는데 $c"
[ "$before" = "$after" ] && ok "실패 시 코인 불변($after)" || bug "코인이 깎임: $before → $after"
[ "$tk" = "1" ]          && ok "구제권 불변(1)"            || bug "구제권=$tk (1 기대)"

# ── W10. 구제권 구매 — 성공 ────────────────────────────────────
hdr "W10 구제권 구매 — 잔액 충분"
psql_q "update users set coin_balance=2000 where id=$USER_ID" >/dev/null
r=$(body -X POST "$BASE/personal/recovery-tickets" -H "$AUTH")
rt=$(jget "$r" recoveryTickets); pr=$(jget "$r" price); cb=$(jget "$r" coinBalance)
[ "$rt" = "2" ]    && ok "구제권 1 → 2"        || bug "recoveryTickets=$rt (2 기대)"
[ "$pr" = "800" ]  && ok "가격 800 노출"       || bug "price=$pr (800 기대)"
[ "$cb" = "1200" ] && ok "코인 2000 → 1200"    || bug "coinBalance=$cb (1200 기대)"
tx=$(psql_q "select count(*) from coin_transactions where user_id=$USER_ID and type='RECOVERY_TICKET_PURCHASE'")
[ "$tx" = "1" ] && ok "거래내역 RECOVERY_TICKET_PURCHASE 1건" || bug "거래내역 $tx건 (1 기대)"
fr=$(psql_q "select free_recovery_tickets from users where id=$USER_ID")
pd=$(psql_q "select paid_recovery_tickets from users where id=$USER_ID")
{ [ "$fr" = "1" ] && [ "$pd" = "1" ]; } && ok "무료1/구매1 로 분리 저장 (소멸 규칙이 달라서)"   || bug "무료=$fr 구매=$pd (각각 1 기대)"
g=$(body "$BASE/personal/weekly-goal" -H "$AUTH")
[ "$(jget "$g" ticketPrice)" = "800" ] && ok "응답에 ticketPrice=800 (앱이 구매 안내창 띄울 수 있음)" || bug "ticketPrice 미노출"
[ "$(jget "$g" freeTickets)" = "1" ] && ok "응답에 freeTickets 노출" || bug "freeTickets 미노출"
[ "$(jget "$g" paidTickets)" = "1" ] && ok "응답에 paidTickets 노출" || bug "paidTickets 미노출"

# ── W11. 폐지된 복귀 미션 API ──────────────────────────────────
hdr "W11 폐지된 복귀 미션 API가 살아있지 않은지"
for path in "/personal/recovery" "/personal/recovery/status"; do
  c=$(code "$BASE$path" -H "$AUTH")
  { [ "$c" = "404" ] || [ "$c" = "405" ]; } && ok "GET $path → $c (폐지됨)" || bug "GET $path → $c (404/405 기대)"
done

# ── W12. 인증 가드 ─────────────────────────────────────────────
hdr "W12 토큰 없이 호출"
for m in "GET $BASE/personal/weekly-goal" "POST $BASE/personal/recovery-tickets"; do
  set -- $m
  c=$(code -X "$1" "$2")
  [ "$c" = "401" ] && ok "$1 $(basename "$2") → 401" || bug "$1 $(basename "$2") → $c (401 기대)"
done

# ── W13. 스키마 ────────────────────────────────────────────────
hdr "W13 스키마 전환 확인"
rm_exists=$(psql_q "select count(*) from information_schema.tables where table_name='recovery_missions'")
we_exists=$(psql_q "select count(*) from information_schema.tables where table_name='weekly_evaluations'")
wt=$(psql_q "select count(*) from information_schema.columns where table_name='personal_locations' and column_name='weekly_target_days'")
uniq=$(psql_q "select count(*) from pg_indexes where tablename='weekly_evaluations' and indexdef like '%UNIQUE%'")
[ "$rm_exists" = "0" ] && ok "recovery_missions 테이블 제거됨"       || bug "recovery_missions 가 아직 있음"
[ "$we_exists" = "1" ] && ok "weekly_evaluations 테이블 생성됨"      || bug "weekly_evaluations 없음"
[ "$wt" = "1" ]        && ok "personal_locations.weekly_target_days" || bug "weekly_target_days 컬럼 없음"
[ "$uniq" -ge 1 ]      && ok "UNIQUE(user_id, week_start) 존재 (멱등성 보장)" || bug "UNIQUE 인덱스 없음"

# ── 결과 ───────────────────────────────────────────────────────
echo
echo "════════════════════════════════"
echo "  OK  $PASS 건"
echo "  BUG $BUG 건"
echo "════════════════════════════════"
exit $BUG
