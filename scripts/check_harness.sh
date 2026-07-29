#!/usr/bin/env bash
# 하네스 문서 규율 검사.
#
# 왜 필요한가: "CLAUDE.md에는 한 줄 요약만" 규칙은 2026-07-21부터 docs/CHANGELOG.md에
# 적혀 있었지만 지켜지지 않았다 — 최근 4건이 578~842자까지 부풀어 CLAUDE.md가 43.7KB가 됐다.
# 손으로 지키는 규율은 갈라진다. run_tests.sh가 "총 N종" 미러를 자동 탐색으로 없앤 것과 같은 처방이다.
#
# 사용: bash scripts/check_harness.sh
# 종료 코드: 위반이 하나라도 있으면 1

set -uo pipefail
cd "$(dirname "$0")/.."

MAX_LEN=200        # 변경 이력 한 건의 최대 글자수
MAX_ROWS=5         # 변경 이력 최대 건수
MAX_CLAUDE=16000   # CLAUDE.md 최대 글자수 (매 세션 로드되므로 크기가 곧 비용)

fail=0
warn=0
note() { printf '  %s\n' "$1"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
soft() { printf '\033[33m!\033[0m %s\n' "$1"; warn=$((warn+1)); }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }

# 글자수(바이트 아님). 한글이 3바이트라 바이트로 세면 규칙이 3배 느슨해진다.
charlen() { printf '%s' "$1" | wc -m | tr -d ' '; }

echo "=== 하네스 문서 규율 검사 ==="
echo

# ── A. CLAUDE.md 변경 이력: 건당 길이 ──────────────────────────────
rows=$(grep -c '^| 2026-' CLAUDE.md || true)
over=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  n=$(charlen "$line")
  if [ "$n" -gt "$MAX_LEN" ]; then
    bad "변경 이력 ${n}자 (상한 ${MAX_LEN}) — $(printf '%s' "$line" | cut -c1-56)…"
    note "전문은 docs/CHANGELOG.md, 판단 근거는 docs/DECISIONS.md로 옮겨라."
    over=$((over+1))
  fi
done < <(grep '^| 2026-' CLAUDE.md || true)
[ "$over" -eq 0 ] && ok "변경 이력 ${rows}건 전부 ${MAX_LEN}자 이내"

# ── B. CLAUDE.md 변경 이력: 건수 ───────────────────────────────────
if [ "$rows" -gt "$MAX_ROWS" ]; then
  bad "변경 이력 ${rows}건 (상한 ${MAX_ROWS}) — 오래된 건은 docs/CHANGELOG.md에만 남긴다"
else
  ok "변경 이력 ${rows}건 (상한 ${MAX_ROWS})"
fi

# ── C. CLAUDE.md 총량 ──────────────────────────────────────────────
size=$(wc -m < CLAUDE.md | tr -d ' ')
if [ "$size" -gt "$MAX_CLAUDE" ]; then
  bad "CLAUDE.md ${size}자 (상한 ${MAX_CLAUDE}) — 매 세션 로드되므로 크기가 곧 비용이다"
  note "옮길 곳: 판단 근거→docs/DECISIONS.md · 변경 전문→docs/CHANGELOG.md · 다음 할 일→docs/TUNING.md"
else
  ok "CLAUDE.md ${size}자 (상한 ${MAX_CLAUDE})"
fi

# ── D. 소유권 표가 가리키는 문서가 실재하는가 ──────────────────────
missing=0
for f in docs/GDD.md docs/CHANGELOG.md docs/DECISIONS.md docs/TUNING.md \
         .claude/skills/projectb-rules/SKILL.md .claude/skills/projectb-verify/SKILL.md \
         .claude/skills/projectb-gdd/SKILL.md .claude/agents/projectb-art.md; do
  [ -f "$f" ] || { bad "소유권 표가 가리키는 파일 없음: $f"; missing=$((missing+1)); }
done
[ "$missing" -eq 0 ] && ok "소유권 표의 정본 문서 8종 전부 실재"

# ── E. 에이전트·스킬 개수 미러 ─────────────────────────────────────
# CLAUDE.md에 개수를 적어 둔 이상 그것은 미러다. 미러는 갈라진다 — 그래서 검사한다.
a_real=$(find .claude/agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
s_real=$(find .claude/skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
a_doc=$(grep -oE '에이전트 [0-9]+종' CLAUDE.md | head -1 | grep -oE '[0-9]+' || echo "")
s_doc=$(grep -oE '스킬 [0-9]+종' CLAUDE.md | head -1 | grep -oE '[0-9]+' || echo "")
if [ -n "$a_doc" ] && [ "$a_doc" != "$a_real" ]; then
  bad "에이전트 개수 미러 갈라짐 — CLAUDE.md '${a_doc}종' vs 실제 ${a_real}개"
elif [ -n "$a_doc" ]; then ok "에이전트 ${a_real}개 — 문서와 일치"; fi
if [ -n "$s_doc" ] && [ "$s_doc" != "$s_real" ]; then
  bad "스킬 개수 미러 갈라짐 — CLAUDE.md '${s_doc}종' vs 실제 ${s_real}개"
elif [ -n "$s_doc" ]; then ok "스킬 ${s_real}개 — 문서와 일치"; fi

# ── F. 삭제된 에이전트 이름을 아직 부르는 곳 ───────────────────────
# "구 projectb-ui" / "흡수" / "삭제된 에이전트"는 이관 이력을 설명하는 정상 문장이다 — 제외한다.
# 오탐이 남으면 스크립트를 신뢰하지 않게 되고, 신뢰받지 못하는 검사는 없는 것과 같다.
ghosts=""
for g in projectb-planner projectb-architect projectb-ui projectb-animator \
         projectb-shader projectb-profiler projectb-tools; do
  hits=$(grep -rnF "$g" CLAUDE.md .claude/agents .claude/skills 2>/dev/null \
         | grep -vE '구 '"$g"'|흡수|삭제된 에이전트|없어진 이름' || true)
  # 파일:줄번호만 보여준다 — 본문을 자르면 UTF-8 중간에서 끊겨 "Binary file matches"가 된다.
  [ -n "$hits" ] && ghosts="${ghosts}${g}\n$(printf '%s' "$hits" | cut -d: -f1,2 | sed 's/^/      /')\n"
done
if [ -n "$ghosts" ]; then
  soft "삭제된 에이전트 이름이 아직 살아 있다 (라우팅이 빈 곳을 가리킨다)"
  printf "$ghosts" | sed 's/^/    /'
else
  ok "삭제된 에이전트 이름 참조 없음"
fi

# ── G. CHANGELOG 새 항목이 섹션 형식인가 ───────────────────────────
if grep -q '^# 기록' docs/CHANGELOG.md; then
  ok "CHANGELOG 섹션 형식 도입됨 (표는 아카이브로 보존)"
else
  bad "docs/CHANGELOG.md에 '# 기록' 절이 없다 — 새 항목을 쌓을 자리가 없다"
fi

echo
if [ "$fail" -gt 0 ]; then
  printf '\033[31m실패 %d건\033[0m' "$fail"
  [ "$warn" -gt 0 ] && printf ' · 경고 %d건' "$warn"
  echo; exit 1
fi
printf '\033[32m통과\033[0m'
[ "$warn" -gt 0 ] && printf ' · 경고 %d건' "$warn"
echo
