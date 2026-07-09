#!/usr/bin/env bash
# run-saturation.sh <SCENARIO> <LABEL> [메모]
# 포화 시나리오 1개를 실행(HikariCP 1초 샘플링 포함)하고, 관측값을 PERFORMANCE-LOG.md에 자동 기록한다.
#   예) run-saturation.sh S1 pool30 "풀 30 검증"
# 원시 출력은 docs/monitoring/baselines/ (gitignore), 요약은 로그 파일(추적)에 남는다.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCEN="${1:?usage: run-saturation.sh <SCENARIO> <LABEL> [note]}"
LABEL="${2:?usage: run-saturation.sh <SCENARIO> <LABEL> [note]}"
NOTE="${3:-}"

OUTDIR="$ROOT/docs/monitoring/baselines"; mkdir -p "$OUTDIR"
HIKLOG="$OUTDIR/sat-${SCEN}-${LABEL}-hikari.log"
K6JSON="$OUTDIR/sat-${SCEN}-${LABEL}-k6.json"
K6OUT="$OUTDIR/sat-${SCEN}-${LABEL}-stdout.log"

# HikariCP 샘플러 백그라운드 기동
bash "$ROOT/monitoring/scripts/sample-hikari.sh" "$HIKLOG" >/dev/null 2>&1 &
SPID=$!
# k6 포화 실행
SCENARIO="$SCEN" OUT_JSON="$K6JSON" k6 run "$ROOT/monitoring/k6/saturation-test.js" >"$K6OUT" 2>&1
kill "$SPID" 2>/dev/null || true

TITLE="$(date +%Y-%m-%d) — 포화 ${SCEN} (${LABEL})${NOTE:+: ${NOTE}}"
bash "$ROOT/monitoring/scripts/log-run.sh" "$K6JSON" "$HIKLOG" "$TITLE"
echo "done: $TITLE"
