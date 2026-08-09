#!/usr/bin/env bash
# b-axis-run-saturation.sh <SCENARIO> <LABEL> [메모]
# 포화 시나리오 1개를 실행(HikariCP 1초 샘플링 포함)하고, 관측값을 PERFORMANCE-LOG.md에 자동 기록한다.
#   예) b-axis-run-saturation.sh S1 pool30 "풀 30 검증"
# 원시 출력은 docs/monitoring/baselines/ (gitignore), 요약은 로그 파일(추적)에 남는다.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCEN="${1:?usage: b-axis-run-saturation.sh <SCENARIO> <LABEL> [note]}"
LABEL="${2:?usage: b-axis-run-saturation.sh <SCENARIO> <LABEL> [note]}"
NOTE="${3:-}"

DB_CONTAINER="${DB_CONTAINER:-booster-db}"
DB_USER="${DB_USER:-booster}"
DB_NAME="${DB_NAME:-booster}"

psql_val() { docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null; }

# [수정] SAT_ 챌린지 id는 시퀀스라 재시딩마다 바뀐다. env 미지정 시 DB에서 자동 해석해
# k6에 넘긴다(구: k6 기본값 145/147..644 하드코딩 — 재시딩 후 존재하지 않는 id를 난타).
if [ -z "${HOT_CHALLENGE_ID:-}" ]; then
  HOT_CHALLENGE_ID="$(psql_val "SELECT id FROM challenges WHERE title = 'SAT_HOT_1';")"
  [ -n "$HOT_CHALLENGE_ID" ] || { echo "[FAIL] SAT_HOT_1 없음 — b-axis-seed-saturation.sql 먼저 적용하세요." >&2; exit 1; }
fi
if [ -z "${BREADTH_MIN:-}" ] || [ -z "${BREADTH_MAX:-}" ]; then
  BREADTH_MIN="$(psql_val "SELECT MIN(id) FROM challenges WHERE title LIKE 'SAT\_BREADTH\_%';")"
  BREADTH_MAX="$(psql_val "SELECT MAX(id) FROM challenges WHERE title LIKE 'SAT\_BREADTH\_%';")"
  [ -n "$BREADTH_MIN" ] && [ -n "$BREADTH_MAX" ] || { echo "[FAIL] SAT_BREADTH_ 없음 — b-axis-seed-saturation.sql 먼저 적용하세요." >&2; exit 1; }
fi
echo "targets: HOT_CHALLENGE_ID=$HOT_CHALLENGE_ID BREADTH=$BREADTH_MIN..$BREADTH_MAX"

OUTDIR="$ROOT/docs/monitoring/baselines"; mkdir -p "$OUTDIR"
HIKLOG="$OUTDIR/sat-${SCEN}-${LABEL}-hikari.log"
K6JSON="$OUTDIR/sat-${SCEN}-${LABEL}-k6.json"
K6OUT="$OUTDIR/sat-${SCEN}-${LABEL}-stdout.log"

# HikariCP 샘플러 백그라운드 기동
bash "$ROOT/monitoring/scripts/b-axis-sample-hikari.sh" "$HIKLOG" >/dev/null 2>&1 &
SPID=$!
# k6 포화 실행
SCENARIO="$SCEN" OUT_JSON="$K6JSON" \
  HOT_CHALLENGE_ID="$HOT_CHALLENGE_ID" BREADTH_MIN="$BREADTH_MIN" BREADTH_MAX="$BREADTH_MAX" \
  k6 run "$ROOT/monitoring/k6/b-axis-saturation.js" >"$K6OUT" 2>&1
kill "$SPID" 2>/dev/null || true

TITLE="$(date +%Y-%m-%d) — 포화 ${SCEN} (${LABEL})${NOTE:+: ${NOTE}}"
bash "$ROOT/monitoring/scripts/b-axis-log-saturation.sh" "$K6JSON" "$HIKLOG" "$TITLE"
echo "done: $TITLE"
