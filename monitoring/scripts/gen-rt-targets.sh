#!/usr/bin/env bash
# gen-rt-targets.sh — RT_ 시딩 결과에서 monitoring/k6/rt-targets.json 을 생성한다.
#
# seed-realistic-teamdetail.sql 적용 직후 실행할 것. challenge id는 시퀀스 값이라
# 재시딩마다 바뀌므로, rt-targets.json 을 수동 관리하지 말고 항상 이 스크립트로
# 재생성해야 한다(하드코딩된 옛 id가 남으면 team-detail-realistic.js의 setup 로그인이
# 전부 실패한다).
#
# 앵커 계정 규약(시더와 동일해야 함):
#   email    = rt_c<challengeId>@booster.test
#   password = seed1234
#
# Usage: monitoring/scripts/gen-rt-targets.sh
#   env: DB_CONTAINER(booster-db) DB_USER(booster) DB_NAME(booster) OUT(경로 재정의)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB_CONTAINER="${DB_CONTAINER:-booster-db}"
DB_USER="${DB_USER:-booster}"
DB_NAME="${DB_NAME:-booster}"
OUT="${OUT:-$ROOT/monitoring/k6/rt-targets.json}"
PASSWORD="seed1234"   # seed-realistic-teamdetail.sql 의 앵커 비밀번호와 동일해야 함

ROWS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c \
  "SELECT id, title FROM challenges WHERE title LIKE 'RT\_HOT\_%' OR title LIKE 'RT\_NORMAL\_%' ORDER BY id;")

if [ -z "$ROWS" ]; then
  echo "[FAIL] RT_ 챌린지가 없습니다 — seed-realistic-teamdetail.sql 먼저 적용하세요." >&2
  exit 1
fi

ROWS="$ROWS" python3 - "$OUT" "$PASSWORD" <<'PY'
import json, os, sys

out, password = sys.argv[1], sys.argv[2]
hot, normal = [], []
for line in os.environ['ROWS'].splitlines():
    line = line.strip()
    if not line:
        continue
    cid, title = line.split('|', 1)
    entry = {"challengeId": int(cid), "email": f"rt_c{cid}@booster.test", "password": password}
    (hot if title.startswith('RT_HOT_') else normal).append(entry)

with open(out, 'w', encoding='utf-8') as f:
    json.dump({"hot": hot, "normal": normal}, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"generated: {out} (hot={len(hot)}, normal={len(normal)})")
if len(hot) != 10 or len(normal) != 40:
    print(f"[WARN] 기대 수량(hot=10, normal=40)과 다릅니다 — 시드 상태를 확인하세요.", file=sys.stderr)
PY
