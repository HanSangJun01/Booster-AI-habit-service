#!/usr/bin/env bash
# =====================================================================
# 멀티서버 P1 테스트 — Docker 기반 재현 가능한 자동 검증
# =====================================================================
# 검증 대상(P1): @Scheduled 정산 스케줄러가 3인스턴스에서 동시에 발화해도
#   ShedLock 분산락 + settlement.challenge_id unique 제약 + FAILED→PENDING CAS 로
#   각 챌린지가 "정확히 1회"만 정산되어 코인 이중지급이 없다.
#
# 방법:
#   1) 멀티 스택(nginx LB + backend 3대 + 공유 DB) 기동 확인
#   2) 실제 유저를 갖춘 ENDED 챌린지 20개 시드(p1-settlement-seed.sql)
#   3) 3대 동시 재시작 → 재시작 시 retryFailedSettlements 가 즉시 발화 = 최대 동시 경쟁
#   4) 정산 완료 폴링 후 불변식 검증(PASS/FAIL)
#
# 원칙: Spring 메인 코드(src/main/**)는 절대 건드리지 않는다. 데이터/오케스트레이션만.
# 사용: bash monitoring/multi-server-test/run-p1-test.sh
# =====================================================================
set -uo pipefail

COMPOSE="docker-compose.multi.yml"
DB="booster-multi-db"
SEED="monitoring/multi-server-test/p1-settlement-seed.sql"
BACKENDS="booster-backend-1 booster-backend-2 booster-backend-3"

q() { docker exec -i "$DB" psql -U booster -d booster -tAc "$1" 2>/dev/null | tr -d '[:space:]'; }

pass=0; fail=0
check() { # desc, actual, expected
  if [ "$2" = "$3" ]; then echo "  ✅ PASS: $1  (=$2)"; pass=$((pass+1))
  else echo "  ❌ FAIL: $1  (got '$2', want '$3')"; fail=$((fail+1)); fi
}

echo "############ 멀티서버 P1 테스트 ############"

echo "=== [1/6] 멀티 스택 기동 확인 ==="
docker compose -f "$COMPOSE" up -d >/dev/null 2>&1
for c in $BACKENDS; do
  for _ in $(seq 1 40); do
    if docker exec "$c" sh -c 'wget -qO- http://localhost:8080/actuator/health 2>/dev/null' 2>/dev/null | grep -q '"status":"UP"'; then break; fi
    sleep 2
  done
done
echo "  backend 3대 health UP"

echo "=== [2/6] 테스트 시드 적용 (실제 유저 200 + ENDED 챌린지 20, A팀 승리) ==="
docker exec -i "$DB" psql -U booster -d booster < "$SEED" 2>&1 | tail -1
echo "  MST 챌린지: $(q "SELECT count(*) FROM challenges WHERE title LIKE 'MST_%'") / 유저: $(q "SELECT count(*) FROM users WHERE id BETWEEN 2000001 AND 2000200")"

echo "=== [3/6] 정산 전 상태 (MST 정산 0건이어야) ==="
before=$(q "SELECT count(*) FROM settlements s JOIN challenges c ON c.id=s.challenge_id WHERE c.title LIKE 'MST_%'")
echo "  MST settlements(before) = $before"

echo "=== [4/6] 3대 동시 재시작 → retryFailedSettlements 동시 발화 ==="
RESTART_TS=$(date -u +%Y-%m-%dT%H:%M:%S)
docker restart $BACKENDS >/dev/null 2>&1
echo "  재시작 완료(ts=$RESTART_TS), 부팅+정산 대기..."

echo "=== [5/6] 정산 완료 폴링 (목표: MST 20건) ==="
for i in $(seq 1 50); do
  now=$(q "SELECT count(*) FROM settlements s JOIN challenges c ON c.id=s.challenge_id WHERE c.title LIKE 'MST_%'")
  echo "  [$i] MST settlements = ${now:-?}"
  [ "${now:-0}" = "20" ] && break
  sleep 3
done

echo "=== [6/6] P1 불변식 검증 ==="
total=$(q "SELECT count(*) FROM settlements s JOIN challenges c ON c.id=s.challenge_id WHERE c.title LIKE 'MST_%'")
completed=$(q "SELECT count(*) FROM settlements s JOIN challenges c ON c.id=s.challenge_id WHERE c.title LIKE 'MST_%' AND s.status='COMPLETED'")
failed=$(q "SELECT count(*) FROM settlements s JOIN challenges c ON c.id=s.challenge_id WHERE c.title LIKE 'MST_%' AND s.status='FAILED'")
dup=$(q "SELECT count(*) FROM (SELECT s.challenge_id FROM settlements s JOIN challenges c ON c.id=s.challenge_id WHERE c.title LIKE 'MST_%' GROUP BY s.challenge_id HAVING count(*)>1) x")
winners=$(q "SELECT count(*) FROM users WHERE id BETWEEN 2000001 AND 2000200 AND coin_balance=2000")
losers=$(q "SELECT count(*) FROM users WHERE id BETWEEN 2000001 AND 2000200 AND coin_balance=0")
bad=$(q "SELECT count(*) FROM users WHERE id BETWEEN 2000001 AND 2000200 AND coin_balance NOT IN (0,2000)")
txn=$(q "SELECT count(*) FROM coin_transactions WHERE type='SETTLEMENT_WIN' AND user_id BETWEEN 2000001 AND 2000200")
sumc=$(q "SELECT COALESCE(sum(amount),0) FROM coin_transactions WHERE type='SETTLEMENT_WIN' AND user_id BETWEEN 2000001 AND 2000200")

echo "  [정산 결과]"
check "MST 정산 총건수 = 20"            "$total"     "20"
check "COMPLETED = 20 (FAILED 없음)"    "$completed" "20"
check "FAILED = 0"                       "$failed"    "0"
echo "  [P1: 이중정산/이중지급 없음]"
check "이중정산된 챌린지 = 0"           "$dup"       "0"
check "승자 잔액 정확히 2000 = 100명"   "$winners"   "100"
check "패자 잔액 0 = 100명"             "$losers"    "100"
check "비정상 잔액(이중지급 흔적) = 0"  "$bad"       "0"
check "SETTLEMENT_WIN 거래 = 100건"     "$txn"       "100"
check "총 지급 코인 = 200000"           "$sumc"      "200000"

echo "  [P1: ShedLock 직렬화 — 정산 본문을 실행한 인스턴스]"
# 재시작 이후(--since) '정산 완료(Settlement completed)' 로그를 인스턴스별로 집계.
# 3대가 동시에 스케줄러를 발화해도 ShedLock 이 한 대만 본문에 진입시키므로,
# 정산을 실제로 수행한 인스턴스는 1대여야 한다.
ran=0
for c in $BACKENDS; do
  n=$(docker logs --since "$RESTART_TS" "$c" 2>&1 | grep -c 'Settlement completed')
  echo "     $c: Settlement completed 로그 $n 건"
  [ "$n" -gt 0 ] && ran=$((ran+1))
done
check "정산 수행 인스턴스 = 1 (동시 발화 → ShedLock 이 1대만 통과)" "$ran" "1"

echo ""
echo "############ 결과: PASS=$pass  FAIL=$fail ############"
[ "$fail" = "0" ] && echo "🎉 전체 통과 — P1(정산 이중지급 방지)이 멀티 인스턴스에서 실증됨" || echo "⚠️  실패 있음 — 시나리오/데이터 점검 필요"
exit "$fail"
