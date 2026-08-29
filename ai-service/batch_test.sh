#!/bin/bash
# 프롬프트 튜닝용 배치 테스트.
# ai-service/samples/<CATEGORY>/<pass|fail>/*.jpg 를 순회하며 판정 결과를 표로 출력.
#
# 사용:
#   cd ai-service
#   bash batch_test.sh                # 전체 카테고리
#   bash batch_test.sh EXERCISE       # 특정 카테고리만
#
# 요구:
#   - ai-service가 localhost:8000 에서 실행 중이어야 함 (ANTHROPIC_API_KEY 설정된 채로)
#   - samples/{exercise,study}/{pass,fail}/ 에 이미지가 있어야 함
#
# 실제 API를 호출하는 스크립트다 — 이미지 한 장당 정확히 한 번만 curl한다
# (재시도 없음). 실패해도 같은 이미지를 다시 부르지 않는다 — 여기서 재시도
# 루프를 추가하지 마라, 비용이 나가는 호출이다.
#
# 아래 셋 중 뭐가 없어도 curl이 알 수 없는 에러를 뱉는 대신, 뭐가 없는지
# 여기서 먼저 확인하고 정확히 알려준 뒤 종료한다 — 서버 안 뜸 / 키 없음 /
# 샘플 없음은 서로 다른 문제라 원인을 헷갈리면 안 된다.

set -u

BASE_URL="${BASE_URL:-http://localhost:8000}"
CATEGORIES=("EXERCISE" "STUDY")
if [ $# -ge 1 ]; then
  CATEGORIES=("$1")
fi

# --- 사전 점검 1: 서버가 떠 있는가 -----------------------------------------
health=$(curl -s --max-time 5 "$BASE_URL/health" 2>/dev/null)
if [ -z "$health" ]; then
  echo "오류: $BASE_URL 에 연결할 수 없음 — ai-service가 안 떠 있는 것으로 보임." >&2
  echo "  먼저 다음을 실행: uvicorn main:app --reload --port 8000" >&2
  exit 1
fi

# --- 사전 점검 2: API 키가 로드됐는가 --------------------------------------
# 키 자체는 이 스크립트가 아니라 서버 프로세스가 읽으므로, 서버가 실제로
# 키를 들고 떴는지는 /health의 api_key_present로만 확인할 수 있다.
api_key_present=$(echo "$health" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_key_present', False))" 2>/dev/null)
if [ "$api_key_present" != "True" ]; then
  echo "오류: ai-service에 ANTHROPIC_API_KEY가 로드되지 않음." >&2
  echo "  ai-service/.env 에 ANTHROPIC_API_KEY=sk-ant-... 설정 후 서버 재기동." >&2
  exit 1
fi

# --- 사전 점검 3: 샘플이 있는가 --------------------------------------------
if [ ! -d samples ]; then
  echo "오류: samples/ 디렉터리가 없음." >&2
  echo "  다음 구조로 이미지를 넣어라 (gitignored, 커밋되지 않음):" >&2
  echo "    samples/exercise/pass/*.jpg   samples/exercise/fail/*.jpg" >&2
  echo "    samples/study/pass/*.jpg      samples/study/fail/*.jpg" >&2
  exit 1
fi

# 지원 형식만 실제로 호출한다. 대소문자 섞인 확장자까지 받는다.
# (macOS 사진 폴더엔 .DS_Store가 항상 낀다 — glob이 dotglob 없이는 애초에
# 숨김 파일을 안 보므로 따로 걸러낼 필요가 없다.)
_is_supported_ext() {
  local ext="${1##*.}"
  ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    jpg|jpeg|png|webp) return 0 ;;
    *) return 1 ;;
  esac
}

# 이미지 한 장을 판정 요청하고 "판정|신뢰도|이유"를 돌려준다.
# `passed`가 없는 응답(4xx/5xx의 `detail`)은 모델의 판정 불일치가 아니라
# 요청 자체가 실패한 것이므로, "이유" 칸에 조용히 빈 문자열을 남기는 대신
# `detail`을 보여준다 — 안 그러면 키 만료·타임아웃 같은 하니스 문제를
# 프롬프트 튜닝 실패로 착각한다.
_verify() {
  local cat="$1" img="$2"
  local resp
  resp=$(curl -s -X POST "$BASE_URL/verify" \
    -F "category=$cat" \
    -F "image=@$img" \
    --max-time 30)
  echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print('PARSE_ERR|-|응답을 JSON으로 못 읽음')
    sys.exit()
if 'passed' in d:
    print(f\"{d['passed']}|{d.get('confidence_score', 0):.2f}|{str(d.get('reason', ''))[:60]}\")
else:
    print(f\"ERR|-|{str(d.get('detail', ''))[:60]}\")
" 2>/dev/null || echo "PARSE_ERR|-|-"
}

# 이미지 한 장을 처리해 표에 한 줄 찍는다.
# expected가 "pass"/"fail"이면 채점 대상(총계·정확도에 반영), 그 외(빈 문자열)면
# samples/<category>/ 바로 아래에 있어 기대값이 없는 파일 — 판정은 보여주되
# 채점에서는 뺀다 (기대값 없는 파일을 조용히 무시하면 "내 사진이 테스트된 줄"
# 알게 된다 — 그래서라도 결과는 보여준다).
_process_image() {
  local cat="$1" expected="$2" img="$3"
  local parsed passed conf reason ok

  parsed=$(_verify "$cat" "$img")
  IFS='|' read -r passed conf reason <<< "$parsed"

  if [ "$expected" = "pass" ] || [ "$expected" = "fail" ]; then
    total=$((total + 1))
    if [ "$expected" = "pass" ] && [ "$passed" = "True" ]; then
      ok="✓"; correct=$((correct + 1))
    elif [ "$expected" = "fail" ] && [ "$passed" = "False" ]; then
      ok="✓"; correct=$((correct + 1))
    else
      ok="✗"
    fi
  else
    unscored=$((unscored + 1))
    expected="채점제외"
    ok="-"
  fi

  printf "%-8s %-8s %-40s %-2s %5s %8s  %s\n" \
    "$cat" "$expected" "$(basename "$img")" "$ok" "$passed" "$conf" "$reason"
}

# 헤더
printf "%-8s %-8s %-40s %8s %10s %s\n" "카테고리" "기대" "파일" "판정" "신뢰도" "이유"
printf "%s\n" "$(printf '=%.0s' {1..140})"

total=0
correct=0
skipped=0
unscored=0

for cat in "${CATEGORIES[@]}"; do
  cat_lower=$(echo "$cat" | tr '[:upper:]' '[:lower:]')
  cat_dir="samples/$cat_lower"
  [ -d "$cat_dir" ] || continue

  # pass/fail — 기대값이 있는, 채점 대상 사진
  for expected in pass fail; do
    dir="$cat_dir/$expected"
    [ -d "$dir" ] || continue
    shopt -s nullglob
    for img in "$dir"/*; do
      [ -f "$img" ] || continue
      if _is_supported_ext "$img"; then
        _process_image "$cat" "$expected" "$img"
      else
        skipped=$((skipped + 1))
      fi
    done
  done

  # pass/fail 밖, 카테고리 폴더 바로 아래 — 기대값 없이 판정만 보여줄 사진
  shopt -s nullglob
  for img in "$cat_dir"/*; do
    [ -f "$img" ] || continue
    if _is_supported_ext "$img"; then
      _process_image "$cat" "" "$img"
    else
      skipped=$((skipped + 1))
    fi
  done
done

echo ""
if [ "$total" -eq 0 ] && [ "$unscored" -eq 0 ]; then
  if [ "$skipped" -gt 0 ]; then
    echo "오류: samples/ 안에서 지원하는 이미지(JPEG/PNG/WebP)를 못 찾음 — $skipped 개 파일을 찾았지만 전부 지원하지 않는 형식임(HEIC 등)." >&2
    echo "  JPEG/PNG/WebP로 변환해서 다시 넣어라 (아이폰이 같은 이름의 .jpg를 같이 저장한 경우가 많다)." >&2
  else
    echo "오류: samples/ 아래에서 이미지를 하나도 못 찾음 (구조: samples/<category>/<pass|fail>/*.jpg)." >&2
  fi
  exit 1
fi

[ "$skipped" -gt 0 ] && echo "$skipped 개 파일 건너뜀 (지원하지 않는 형식 — HEIC 등은 JPEG/PNG/WebP로 변환 필요)"
[ "$unscored" -gt 0 ] && echo "$unscored 개 파일은 기대값 없음(pass/fail 폴더 밖) — 채점 제외, 판정 결과는 위 표 참고"
if [ "$total" -gt 0 ]; then
  echo "정확도: $correct / $total  (채점 대상만 — 위 채점 제외·건너뜀 파일은 분모에 안 들어감)"
else
  echo "채점 대상(pass/fail 폴더 안 이미지)이 없어 정확도는 계산하지 않음."
fi
