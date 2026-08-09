#!/bin/bash
# 프롬프트 튜닝용 배치 테스트.
# ai-service/samples/<CATEGORY>/<pass|fail>/*.jpg 를 순회하며 판정 결과를 표로 출력.
#
# 사용:
#   cd ai-service
#   bash batch_test.sh                # 전체 카테고리
#   bash batch_test.sh EXERCISE       # 특정 카테고리만
#
# 요구: ai-service가 localhost:8000 에서 실행 중이어야 함.

set -u

BASE_URL="${BASE_URL:-http://localhost:8000}"
CATEGORIES=("EXERCISE" "STUDY")
if [ $# -ge 1 ]; then
  CATEGORIES=("$1")
fi

# 헤더
printf "%-8s %-6s %-40s %8s %10s %s\n" "카테고리" "기대" "파일" "판정" "신뢰도" "이유"
printf "%s\n" "$(printf '=%.0s' {1..140})"

total=0
correct=0

for cat in "${CATEGORIES[@]}"; do
  cat_lower=$(echo "$cat" | tr '[:upper:]' '[:lower:]')
  for expected in pass fail; do
    dir="samples/$cat_lower/$expected"
    [ -d "$dir" ] || continue
    shopt -s nullglob
    for img in "$dir"/*.{jpg,jpeg,png,webp,JPG,JPEG,PNG,WEBP}; do
      [ -f "$img" ] || continue
      total=$((total + 1))
      resp=$(curl -s -X POST "$BASE_URL/verify" \
        -F "category=$cat" \
        -F "image=@$img" \
        --max-time 30)
      passed=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('passed', 'ERR'))" 2>/dev/null || echo "PARSE_ERR")
      conf=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('confidence_score', 0):.2f}\")" 2>/dev/null || echo "-")
      reason=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('reason', '')[:60])" 2>/dev/null || echo "-")

      # 기대와 실제 비교
      if [ "$expected" = "pass" ] && [ "$passed" = "True" ]; then
        ok="✓"; correct=$((correct + 1))
      elif [ "$expected" = "fail" ] && [ "$passed" = "False" ]; then
        ok="✓"; correct=$((correct + 1))
      else
        ok="✗"
      fi

      printf "%-8s %-6s %-40s %-2s %5s %8s  %s\n" \
        "$cat" "$expected" "$(basename "$img")" "$ok" "$passed" "$conf" "$reason"
    done
  done
done

echo ""
echo "정확도: $correct / $total"
