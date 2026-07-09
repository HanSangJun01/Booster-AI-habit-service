#!/usr/bin/env bash
# Poll /actuator/prometheus every ~1s and log HikariCP pool gauges with a timestamp.
# Usage: sample-hikari.sh <output-file> [base-url]
# Stop with: kill <pid>  (find it via the caller's $! or `pgrep -f sample-hikari.sh`)

set -euo pipefail

OUT_FILE="${1:?usage: sample-hikari.sh <output-file> [base-url]}"
BASE_URL="${2:-http://localhost:8080}"

echo "# ts active idle pending timeout_total" > "$OUT_FILE"

while true; do
  METRICS=$(curl -s "${BASE_URL}/actuator/prometheus")
  ACTIVE=$(echo "$METRICS" | grep '^hikaricp_connections_active{' | awk '{print $2}')
  IDLE=$(echo "$METRICS" | grep '^hikaricp_connections_idle{' | awk '{print $2}')
  PENDING=$(echo "$METRICS" | grep '^hikaricp_connections_pending{' | awk '{print $2}')
  TIMEOUT=$(echo "$METRICS" | grep '^hikaricp_connections_timeout_total{' | awk '{print $2}')
  echo "$(date +%s.%N) ${ACTIVE:-NA} ${IDLE:-NA} ${PENDING:-NA} ${TIMEOUT:-NA}" >> "$OUT_FILE"
  sleep 1
done
