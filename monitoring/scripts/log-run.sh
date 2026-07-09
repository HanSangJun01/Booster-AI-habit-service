#!/usr/bin/env bash
# log-run.sh <k6.json> <hikari.log> "<제목>"
# 포화 실행 결과 파일(k6 JSON + HikariCP 로그)에서 관측값을 뽑아
# docs/monitoring/saturation-cache/PERFORMANCE-LOG.md 의 <!-- AUTO-LOG-INSERT --> 마커 바로 밑에 블록을 삽입한다.
# 테스트/다른 파일에 쓰려면 PERF_LOG 환경변수로 대상 경로를 덮어쓸 수 있다.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
K6JSON="$1"; HIKLOG="$2"; TITLE="$3"
LOG="${PERF_LOG:-$ROOT/docs/monitoring/saturation-cache/PERFORMANCE-LOG.md}"

python3 - "$K6JSON" "$HIKLOG" "$TITLE" "$LOG" "$ROOT" <<'PY'
import json, sys, os
k6json, hiklog, title, logpath, root = sys.argv[1:6]

m = json.load(open(k6json))['metrics']
dur = m['http_req_duration']['values']
reqs = m['http_reqs']['values']
failed = m.get('http_req_failed', {}).get('values', {})
rps = reqs.get('rate', 0.0); total = int(reqs.get('count', 0))
fail_rate = failed.get('rate', 0.0)

active_peak = pending_peak = 0.0
first_to = last_to = None
for line in open(hiklog):
    if line.startswith('#') or not line.strip():
        continue
    p = line.split()
    try:
        a, pend, to = float(p[1]), float(p[3]), float(p[4])
    except (IndexError, ValueError):
        continue
    active_peak = max(active_peak, a); pending_peak = max(pending_peak, pend)
    if first_to is None:
        first_to = to
    last_to = to
new_to = int((last_to or 0) - (first_to or 0))

def rel(p):
    try:
        return os.path.relpath(os.path.abspath(p), root)
    except ValueError:
        return p

block = f"""## {title}
- **자동 기록** (log-run.sh) · 원시: `{rel(k6json)}` · `{rel(hiklog)}`

| 관측값 | 값 |
|---|---|
| RPS | {rps:,.0f}/s |
| 총 요청 | {total:,} |
| 에러율 | {fail_rate*100:.2f}% |
| p50 / p95 / p99 | {dur['p(50)']:.1f} / {dur['p(95)']:.1f} / {dur['p(99)']:.1f} ms |
| max (꼬리) | {dur['max']:.0f}ms |
| HikariCP active / pending peak | {active_peak:.0f} / {pending_peak:.0f} |
| 신규 connectionTimeout | {new_to} |
"""

MARK = "<!-- AUTO-LOG-INSERT -->"
text = open(logpath, encoding='utf-8').read()
if MARK not in text:
    sys.exit(f"marker not found in {logpath}: {MARK}")
open(logpath, 'w', encoding='utf-8').write(text.replace(MARK, MARK + "\n\n" + block, 1))
print(f"logged: {title} -> {logpath}")
PY
