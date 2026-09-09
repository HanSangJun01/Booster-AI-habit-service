#!/usr/bin/env bash
# 버그 관측 러너 — 스택 기동 · 상태 확인 · 지표를 움직이는 시나리오 주입
#
# 목적: probe-user-journey.sh 가 찾은 결함을 "고치지 않고" Grafana 에서 지켜보기 위한 것.
#       지표가 실제로 움직이는 걸 봐야 무슨 뜻인지 이해되므로, 관측만이 아니라
#       각 결함을 눈앞에서 재현하는 시나리오까지 함께 넣는다.
#
# 터미널은 하나면 된다. 전부 detached 로 뜨므로 붙잡고 있을 창이 없다.
#
#   ./watch-bugs.sh up          스택 전부 기동 (DB · 백엔드 · Prometheus · Grafana · exporter)
#   ./watch-bugs.sh status      타깃/지표 현재값 한 번에 출력
#   ./watch-bugs.sh demo radius        ① 반경 상한 부재를 눈앞에서 재현
#   ./watch-bugs.sh demo rescue        구제 유예 파이프라인을 움직임
#   ./watch-bugs.sh demo doublepunish  ★③ 이중 처벌을 재현 (핵심)
#   ./watch-bugs.sh demo badradius     ② 400 대신 409 가 나가는 것
#   ./watch-bugs.sh reset       demo 가 만든 데이터만 지움
#   ./watch-bugs.sh down        스택 종료
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# 두 compose 파일이 같은 디렉터리를 공유해 서로를 orphan 으로 경고한다. 의도된 구성이므로 끈다.
export COMPOSE_IGNORE_ORPHANS=True
BASE="${BASE:-http://localhost:8080/api}"
DB_CONTAINER="${DB_CONTAINER:-booster-db}"
GRAFANA="http://localhost:3000/d/booster-bug-watch"

c1() { printf '\033[1m%s\033[0m\n' "$*"; }
dim(){ printf '\033[2m%s\033[0m\n' "$*"; }
psql_q() {
  local out rc
  out=$(docker exec "$DB_CONTAINER" psql -U booster -d booster -tAc "$1" 2>&1); rc=$?
  if [ $rc -ne 0 ] || grep -q '^ERROR:' <<<"$out"; then
    echo "  [SQL-ERR] $(grep -m1 '^ERROR:' <<<"$out" || head -1 <<<"$out")" >&2; return 1
  fi
  tr -d '\r' <<<"$out"
}
jget() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(-\?[0-9][0-9]*\|\"[^\"]*\"\|true\|false\|null\).*/\1/p" <<<"$1" | head -1 | tr -d '"'; }
mkuser() {
  local email="demo-$1-$(date +%s%N)@bugwatch.local" s
  s=$(curl -s -X POST "$BASE/auth/signup" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"password1234\",\"nickname\":\"$1\"}")
  echo "$(jget "$s" userId) $(jget "$s" accessToken)"
}
# 지표 한 개를 Prometheus 에서 즉시 읽는다 (대시보드와 같은 값)
promq() {
  curl -s --get http://localhost:9090/api/v1/query --data-urlencode "query=$1" \
    | sed -n 's/.*"value":\[[0-9.]*,"\([^"]*\)".*/\1/p' | head -1
}

case "${1:-}" in

up)
  c1 "▶ 스택 기동 (전부 detached — 이 터미널은 바로 돌려드립니다)"
  echo
  echo "1/2  DB · 백엔드"
  ( cd "$ROOT" && docker compose up -d db backend ) || exit 1
  echo "2/2  Prometheus · Grafana · postgres-exporter"
  ( cd "$ROOT" && docker compose -f docker-compose.monitoring.yml up -d ) || exit 1

  echo; echo -n "백엔드 기동 대기"
  for _ in $(seq 1 90); do
    curl -s -o /dev/null http://localhost:8080/actuator/health && break
    echo -n "."; sleep 2
  done; echo
  echo
  c1 "▶ 준비 완료"
  echo "  Grafana     $GRAFANA   (admin / admin)"
  echo "  Prometheus  http://localhost:9090"
  echo "  exporter    http://localhost:9187/metrics"
  echo "  백엔드      http://localhost:8080/actuator/health"
  echo
  dim "  Grafana 를 열어두고 다른 창 없이 여기서 바로 시나리오를 넣으세요:"
  dim "    ./watch-bugs.sh demo doublepunish"
  ;;

down)
  c1 "▶ 종료"
  ( cd "$ROOT" && docker compose -f docker-compose.monitoring.yml down )
  ( cd "$ROOT" && docker compose stop backend db )
  dim "  DB 데이터는 볼륨에 남습니다. 완전 삭제는 docker compose down -v"
  ;;

status)
  c1 "▶ Prometheus 타깃"
  curl -s http://localhost:9090/api/v1/targets \
    | python -c "import sys,json;[print('  %-18s %-6s %s'%(t['labels']['job'],t['health'],t['lastError'])) for t in json.load(sys.stdin)['data']['activeTargets']]" 2>/dev/null \
    || echo "  Prometheus 응답 없음 — ./watch-bugs.sh up 먼저"
  echo
  c1 "▶ 결함 지표 (0 이 아니면 그 결함이 실제로 발생 중)"
  printf '  %-34s %s\n' "③ 이중 처벌 사용자"      "$(promq booster_weekly_penalty_duplicate_penalty_users)"
  printf '  %-34s %s\n' "   벌칙 건수"            "$(promq booster_weekly_penalty_penalty_total)"
  printf '  %-34s %s  (벌칙과 같아야 정상)\n' "   FAILED 채점" "$(promq booster_weekly_penalty_failed_evaluations)"
  printf '  %-34s %s m\n' "① 개인 최대 반경"       "$(promq booster_gps_radius_personal_max_meters)"
  printf '  %-34s %s m\n' "① 팀 최대 반경"         "$(promq booster_gps_radius_team_max_meters)"
  printf '  %-34s %s\n' "   반경 100km 초과(개인)"  "$(promq booster_gps_radius_personal_over_100km)"
  printf '  %-34s %s\n' "   구제 대기"             "$(promq booster_rescue_pending)"
  printf '  %-34s %s\n' "   기한 지났는데 미확정"    "$(promq booster_rescue_overdue_not_expired)"
  printf '  %-34s %s\n' "   코인 정합성 위반"        "$(promq booster_integrity_coin_mismatch_users)"
  echo
  c1 "▶ ④ ShedLock 을 쓰는 스케줄러"
  psql_q "select '  ' || name from shedlock order by name"
  dim "  여기에 evaluateLastWeek / expireOverdueRescues / runMonthly 가 없다 = 결함 ④"
  ;;

demo)
  case "${2:-}" in

  radius)
    c1 "▶ ① 반경 상한 부재 — 지구 반대편에서 인증이 통과한다"
    dim "  볼 패널: '① 개인 최대 반경', '반경 초과 사용자 수'"
    echo
    echo "  현재 최대 반경: $(promq booster_gps_radius_personal_max_meters) m"
    for r in 500 5000 500000 20000000; do
      read -r _ T <<<"$(mkuser "rad$r")"
      A="Authorization: Bearer $T"
      cc=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/users/me/location" -H "$A" \
            -H 'Content-Type: application/json' \
            -d "{\"lat\":37.5,\"lng\":127.0,\"radiusMeters\":$r,\"placeName\":\"demo\"}")
      printf '  반경 %-10s m 등록 → %s' "$r" "$cc"
      # 서울에 등록해두고 시드니에서 인증을 시도한다
      st=$(jget "$(curl -s -X POST "$BASE/personal/check-in" -H "$A" \
            -H 'Content-Type: application/json' -d '{"lat":-33.8,"lng":151.2}')" status)
      if [ "$st" = "SUCCESS" ]; then echo "   시드니 인증 → SUCCESS  ← 우회 성립"
      else echo "   시드니 인증 → 거절"; fi
    done
    echo
    dim "  15초 뒤 scrape 되면 대시보드의 최대 반경이 2천만 m 로 튑니다."
    ;;

  rescue)
    c1 "▶ 구제 유예 파이프라인 — 대기 → 사후 구매 → 구제됨"
    dim "  볼 패널: '구제 유예 파이프라인'"
    echo
    read -r U T <<<"$(mkuser rescue)"; A="Authorization: Bearer $T"
    curl -s -o /dev/null -X POST "$BASE/users/me/location" -H "$A" \
      -H 'Content-Type: application/json' -d '{"lat":37.5,"lng":127.0,"radiusMeters":50}'
    # 코인은 거래내역과 함께 넣는다(직접 UPDATE 하면 정합성 지표를 우리가 깨뜨린다)
    psql_q "update users set coin_balance = coin_balance + 4500, free_recovery_tickets=0, paid_recovery_tickets=0 where id=$U;
            insert into coin_transactions(user_id,type,amount,balance_after)
            select $U,'SIGNUP_BONUS',4500,coin_balance from users where id=$U" >/dev/null
    WK=$(psql_q "select (date_trunc('week', current_date) - interval '7 day')::date")
    psql_q "insert into weekly_evaluations(user_id,week_start,target_days,success_count,result,rescue_deadline)
            values($U,'$WK',3,1,'PENDING_RESCUE', now() + interval '2 day')" >/dev/null
    echo "  userId=$U · $WK 주를 PENDING_RESCUE 로 만듦 → '구제 대기' +1"
    echo "  (대시보드 확인 후 계속하려면 Enter)"; read -r _ || true
    curl -s -o /dev/null -X POST "$BASE/personal/rescue" -H "$A"
    echo "  사후 구매 1,200 코인 결제 → '구제 대기' -1, '구제됨' +1"
    ;;

  doublepunish)
    c1 "▶ ★③ 구제 만료 이중 처벌 재현"
    echo
    dim "  실제 발동 조건은 '인스턴스 2대 이상 + KST 00:10 + 만료 대상 존재' 라 그냥 기다려서는"
    dim "  볼 수 없다. 그래서 expireOverdueRescues 가 내보내는 쓰기를 그대로 두 번 재현한다."
    dim "  — 인스턴스 A 가 처리하고, 락을 기다리던 B 가 낡은 스냅샷을 보고 또 처리하는 상황."
    echo
    read -r U T <<<"$(mkuser dp)"; A="Authorization: Bearer $T"
    curl -s -o /dev/null -X POST "$BASE/users/me/location" -H "$A" \
      -H 'Content-Type: application/json' -d '{"lat":37.5,"lng":127.0,"radiusMeters":50}'
    psql_q "update users set coin_balance = coin_balance + 4500 where id=$U;
            insert into coin_transactions(user_id,type,amount,balance_after)
            select $U,'SIGNUP_BONUS',4500,coin_balance from users where id=$U" >/dev/null
    WK=$(psql_q "select (date_trunc('week', current_date) - interval '7 day')::date")
    # RETURNING 은 psql -tA 에서 값 뒤에 "INSERT 0 1" 상태줄까지 같이 낸다 → 첫 줄만 쓴다.
    EV=$(psql_q "insert into weekly_evaluations(user_id,week_start,target_days,success_count,result,rescue_deadline)
                 values($U,'$WK',3,1,'PENDING_RESCUE', now() - interval '1 hour') returning id" | head -1)
    bal0=$(psql_q "select coin_balance from users where id=$U")
    echo "  userId=$U  기한 지난 PENDING_RESCUE 생성 (id=$EV), 잔액 $bal0"
    echo "  이중 처벌 사용자(현재): $(promq booster_weekly_penalty_duplicate_penalty_users)"
    echo
    for n in A B; do
      echo "  ── 인스턴스 $n 의 만료 처리"
      # markFailed() 는 더티체킹 UPDATE 라 WHERE 절이 id 뿐이다 → 이미 처리된 행도 그대로 덮는다.
      psql_q "update weekly_evaluations set result='FAILED', rescue_deadline=null where id=$EV;
              update streaks set current_streak=0 where user_id=$U;
              update users set coin_balance = coin_balance - 500 where id=$U;
              insert into coin_transactions(user_id,type,amount,balance_after)
              select $U,'WEEKLY_MISS_PENALTY',-500,coin_balance from users where id=$U" >/dev/null
      echo "     → 잔액 $(psql_q "select coin_balance from users where id=$U")"
    done
    echo
    bal1=$(psql_q "select coin_balance from users where id=$U")
    pen=$(psql_q "select count(*) from coin_transactions where user_id=$U and type='WEEKLY_MISS_PENALTY'")
    c1 "  결과: $bal0 → $bal1  (차감 $((bal0-bal1)) — 한 번의 미달인데 벌칙이 $pen 번)"
    [ "$pen" -gt 1 ] 2>/dev/null && c1 "  ✗ 이중 처벌 재현됨" || echo "  (재현 실패 — 위 SQL 오류 확인)"
    echo
    dim "  15초 뒤 scrape 되면 대시보드에서:"
    dim "    · '③ 이중 처벌 사용자' 가 0 → 1 로 빨갛게 바뀜"
    dim "    · '미달 벌칙 vs FAILED 채점' 두 선이 벌어짐"
    ;;

  badradius)
    c1 "▶ ② 반경 검증이 DTO 에 없어 400 대신 409 가 나간다"
    dim "  볼 패널: '② 참가 API 응답'"
    echo
    read -r UH TH <<<"$(mkuser bh)"; AH="Authorization: Bearer $TH"
    CH=$(jget "$(curl -s -X POST "$BASE/challenges" -H "$AH" -H 'Content-Type: application/json' \
      -d '{"category":"EXERCISE","title":"bugwatch","description":"d","verificationType":"GPS","durationDays":7,"depositCoins":0,"visibility":"PUBLIC","approvalType":"AUTO","maxParticipants":10,"gpsLat":37.5,"gpsLng":127.0,"gpsRadiusMeters":50}')" id)
    echo "  challengeId=$CH · 잘못된 반경으로 8회 참가 시도"
    for r in -1 0 -1 0 -5 0 -1 0; do
      read -r _ TX <<<"$(mkuser "bx")"
      cc=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/challenges/$CH/participants" \
            -H "Authorization: Bearer $TX" -H 'Content-Type: application/json' \
            -d "{\"gpsLat\":37.5,\"gpsLng\":127.0,\"gpsRadiusMeters\":$r}")
      printf '  반경 %-3s → %s\n' "$r" "$cc"
    done
    echo
    dim "  400(검증 실패)이 아니라 409(데이터 충돌)로 나갑니다 — 앱은 어느 필드가 문제인지 못 읽습니다."
    dim "  대시보드의 status=409 선이 올라갑니다."
    ;;

  *) echo "demo 시나리오: radius | rescue | doublepunish | badradius"; exit 1 ;;
  esac
  ;;

reset)
  c1 "▶ demo 가 만든 데이터만 삭제"
  n=$(psql_q "select count(*) from users where email like 'demo-%@bugwatch.local'")
  psql_q "delete from coin_transactions where user_id in (select id from users where email like 'demo-%@bugwatch.local');
          delete from weekly_evaluations  where user_id in (select id from users where email like 'demo-%@bugwatch.local');
          delete from personal_ai_verifications where personal_check_in_id in
            (select id from personal_check_ins where user_id in (select id from users where email like 'demo-%@bugwatch.local'));
          delete from personal_check_ins  where user_id in (select id from users where email like 'demo-%@bugwatch.local');
          delete from personal_locations  where user_id in (select id from users where email like 'demo-%@bugwatch.local');
          delete from streaks             where user_id in (select id from users where email like 'demo-%@bugwatch.local');
          delete from challenge_participants where user_id in (select id from users where email like 'demo-%@bugwatch.local');
          delete from users where email like 'demo-%@bugwatch.local'" >/dev/null
  echo "  사용자 $n 명과 딸린 레코드 삭제"
  dim "  probe-user-journey.sh 가 만든 j-* 사용자는 건드리지 않습니다."
  ;;

*)
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  ;;
esac
