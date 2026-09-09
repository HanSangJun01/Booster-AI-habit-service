#!/usr/bin/env bash
# 부하 러너 — 성능 관점에서 앱이 잘 도는지 보기 위한 것
#
# k6 를 로컬에 깔 필요 없다. Docker 로 돌린다(grafana/k6).
# 터미널은 하나면 된다: 여기서 부하를 걸고, Grafana 를 띄워놓고 그래프가 움직이는 걸 본다.
#
#   ./load.sh load      읽기 5종, 0→20→50→100 VU, 3분   "트래픽 몰릴 때 어디가 느린가"
#   ./load.sh write     온보딩 쓰기, 0→20→50→100 VU, 3분 "BCrypt·코인 락 경합이 어디서 터지나"
#   ./load.sh stress    읽기 한계탐색, 100→300→500 VU, 3분 (선행: ./load.sh seed)
#   ./load.sh soak      30 VU 30분 지속                  "메모리·커넥션이 새는가"
#   ./load.sh seed      stress 용 고정 유저(seed3rd@booster.test) 시딩
#
# 시나리오 정의는 monitoring/k6/a-axis-realistic.js 안에 있다(stages target 을 바꾸면 세기 조절).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
K6_DIR="$ROOT/monitoring/k6"
BASE_URL="${BASE_URL:-http://host.docker.internal:8080}"
DB_CONTAINER="${DB_CONTAINER:-booster-db}"
DASH="http://localhost:3000/d/booster-a-axis"

c1() { printf '\033[1m%s\033[0m\n' "$*"; }
dim(){ printf '\033[2m%s\033[0m\n' "$*"; }

# Windows/Git Bash 는 -v 마운트에 Windows 경로가 필요하다.
hostpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

# 파일 첫머리 주석 블록(2행부터 첫 비주석 직전까지)을 그대로 사용법으로 쓴다.
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; }

SC="${1:-}"
case "$SC" in

seed)
  c1 "▶ stress 용 고정 유저 시딩 (seed3rd@booster.test)"
  docker exec -i "$DB_CONTAINER" psql -U booster -d booster < "$ROOT/monitoring/scripts/seed-3rd.sql" \
    && echo "  완료" || echo "  실패 — seed-3rd.sql 확인"
  ;;

load|write|stress|soak)
  # 백엔드가 떠 있는지 먼저 본다. 안 떠 있으면 k6 가 전부 실패로 3분을 낭비한다.
  if ! curl -s -o /dev/null http://localhost:8080/actuator/health; then
    echo "백엔드가 응답하지 않습니다. 먼저: ./watch-bugs.sh up"; exit 1
  fi

  c1 "▶ SCENARIO=$SC  →  $BASE_URL"
  echo
  c1 "  Grafana 를 띄워놓고 보세요:  $DASH"
  dim "  새로고침 10s / 시간범위 Last 15 minutes 로 두면 실시간으로 움직입니다."
  echo
  case "$SC" in
    load)
      echo "  볼 것 (3분)"
      echo "   · p95 응답시간   — VU 가 20→50→100 으로 오를 때 어느 엔드포인트만 유독 튀는가"
      echo "   · 요청량         — VU 를 올렸는데 처리량이 안 오르면 그게 한계점"
      echo "   · Hikari active/pending — pending 이 0 을 벗어나면 커넥션풀이 병목"
      echo "   · 에러율         — 100 VU 구간에서 5xx 가 나오는지"
      dim   "   합격선: 읽기 p95 < 500ms, 실패율 < 1%"
      ;;
    write)
      echo "  볼 것 (3분)"
      echo "   · signup / login p95 — BCrypt 는 CPU 를 쓴다. 여기가 제일 먼저 무너진다"
      echo "   · checkin p95        — 코인·스트릭이 User 비관락을 잡는다. 락 경합이 보이는 지점"
      echo "   · Hikari pending     — 쓰기는 트랜잭션이 길어 풀을 오래 잡는다"
      echo "   · JVM 힙             — 계속 우상향하면 회수가 안 되는 것"
      dim   "   합격선은 느슨하다(3s). 수치를 '드러내는' 게 목적이지 통과가 목적이 아님"
      ;;
    stress)
      echo "  볼 것 (3분) — 100→300→500 VU 한계탐색"
      echo "   · 어느 VU 구간에서 p95 가 꺾이는지 = 실질 수용량"
      echo "   · Hikari pending 이 치솟는 순간이 보통 무너지는 지점"
      echo "   · 에러율이 5% 를 넘으면 거기가 상한"
      dim   "   선행 조건: ./load.sh seed 로 seed3rd@booster.test 가 있어야 함"
      ;;
    soak)
      echo "  볼 것 (30분) — 30 VU 일정 유지"
      echo "   · JVM 힙이 톱니 모양으로 돌아오는가, 아니면 계단식으로 우상향하는가(누수)"
      echo "   · Hikari active 가 시간이 갈수록 안 돌아오는가(커넥션 누수)"
      echo "   · p95 가 초반과 후반이 같은가(서서히 새는 성능저하)"
      dim   "   길다. 걸어놓고 다른 일 하다가 나중에 그래프만 보세요."
      ;;
  esac
  echo
  dim "  중단은 Ctrl+C. 중단해도 그때까지의 그래프는 Grafana 에 남습니다."
  echo

  # MSYS_NO_PATHCONV: Git Bash 는 "/scripts/..." 같은 인자를 Windows 경로로 바꿔버린다
  # (C:/Program Files/Git/scripts/... 로 둔갑해 k6 가 파일을 못 찾는다). 이 명령에서만 끈다.
  MSYS_NO_PATHCONV=1 docker run --rm -i \
    -e BASE_URL="$BASE_URL" -e SCENARIO="$SC" \
    ${LOGIN_EMAIL:+-e LOGIN_EMAIL="$LOGIN_EMAIL"} \
    --add-host host.docker.internal:host-gateway \
    -v "$(hostpath "$K6_DIR"):/scripts" \
    grafana/k6 run /scripts/a-axis-realistic.js

  echo
  c1 "▶ 끝. 서버 쪽 진짜 수치는 Grafana 에서 보세요 — 위 stdout 은 클라이언트 관점입니다."
  dim "  $DASH  (시간범위를 방금 구간으로 맞추면 전체 곡선이 보입니다)"
  ;;

*) usage ;;
esac
