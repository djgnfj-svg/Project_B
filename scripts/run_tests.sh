#!/usr/bin/env bash
# Project_B 헤드리스 검증 스위트 — 🔴 실행 정본.
#
# 왜 스크립트인가 (2026-07-28):
#   ⑴ 스위트 목록이 `CLAUDE.md`와 `projectb-verify` §1 **두 곳에 손으로 복제**돼 있었다.
#      "총 N종"이 갈라지고, 목록에서 빠진 테스트는 아무도 안 돌려 조용히 죽는다(verify §1이
#      스스로 경고하던 것). 여기서는 `tests/test_*_auto.gd`를 **자동 탐색**하므로 새 테스트가
#      **파일을 놓는 것만으로** 스위트에 들어온다 — 문서 미러가 필요 없다.
#   ⑵ 매번 긴 명령을 손으로 조립하면 `rm -f "$VAR"/*.log` 같은 위험 패턴이 반복 등장해
#      승인 프롬프트가 계속 뜬다. 여기서는 `${VAR:?}`로 빈 변수 전개를 셸이 막는다.
#
# 사용법:
#   bash scripts/run_tests.sh            # 전체 (단일 전수 + 멀티 방 왕복)
#   bash scripts/run_tests.sh --fast     # 멀티 방 왕복 생략 (3프로세스라 느리다)
#   bash scripts/run_tests.sh combat     # 이름에 그 문자열이 든 것만
#
# 판정 = `TEST_OK` 1개 이상 + exit 0 + `SCRIPT ERROR` 0 (verify §3 "침묵 통과" 방지).
# ⚠ 이 스크립트는 **실기를 대체하지 않는다** — 클릭 도달·렌더·셰이더 GLSL·소리·손맛은
#   헤드리스가 구조적으로 못 잡는다(verify §2·§6).

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

GODOT="./Godot_v4.7.1-stable_win64.exe"
[ -x "$GODOT" ] || { echo "!! Godot 실행 파일이 없다: $GODOT"; exit 1; }

RELAY_PORT="${PB_RELAY_PORT:-9081}"
FAST=0
FILTER=""
for a in "$@"; do
	case "$a" in
		--fast) FAST=1 ;;
		-*) echo "!! 모르는 옵션: $a"; exit 2 ;;
		*) FILTER="$a" ;;
	esac
done

pass=0
fail=0
failed_names=""

# 파일에서 패턴이 나온 줄 수 — 🔴 `$(grep -c ... || echo 0)`로 쓰지 마라.
#   `grep -c`는 **0 매치일 때 "0"을 출력하고 exit 1**이라, `|| echo 0`이 덧붙어 결과가 "0\n0"이 된다
#   → `[ "$n" -eq 0 ]`이 `integer expression expected`로 터진다. 즉 **정상(에러 0)일 때만 깨진다.**
#   2026-07-28 netreview가 net_room에서 이걸 잡았다(스위트가 판정을 못 내리는 상태였다).
#   대입문 **뒤에** `|| n=0`을 두면 grep의 exit 1만 삼키고 출력은 "0" 하나로 남는다.
count_in() {
	local n
	[ -f "$2" ] || { printf '0'; return; }
	n=$(grep -c "$1" "$2" 2>/dev/null) || n=0
	printf '%s' "${n:-0}"
}

# 🔴 씬 글루 파스 체크 — `-s` 스위트가 **구조적으로 못 잡는** 사각을 메운다.
#   `player.gd`·`combat_authority.gd`·`peer_sync.gd`·`boss.gd` 등은 씬 전용 글루라 `-s`가 preload를
#   하지 않는다 → **문법 오류·없는 함수 호출조차 스위트가 통과시킨다.** 2026-07-28에 실제로
#   `player.gd`가 존재하지 않는 `CombatMath` 함수를 불러 **게임이 아예 안 뜨는 상태**가 됐는데
#   스위트 판정만으로는 안 드러났다(verify §0 "초록불은 동작의 근거가 아니다").
#   변경된 `.gd`만 훑으므로 1파일 ≈ 1초다. git이 없거나 변경이 없으면 조용히 건너뛴다.
run_parse_check() {
	local files f out real n=0 bad=0 autos
	files=$(git diff --name-only HEAD -- '*.gd' 2>/dev/null)
	[ -n "$files" ] || return 0
	# 🔴 오토로드 전역 이름은 `--check-only`에서도 **정상적으로** 미해결이다 (rules §5).
	#   실게임 전용 씬 스크립트(player/stage/ui/main)는 `EventBus`·`Net`을 그대로 쓰는 것이 규약이라
	#   이걸 실패로 보면 오탐이 상시다. 이름은 `project.godot`에서 **읽어서** 만든다 — 여기 목록을
	#   복제하면 오토로드가 늘 때 갈라진다(이 프로젝트가 반복해서 값을 치른 형태).
	autos=$(awk '/^\[autoload\]/{f=1;next} /^\[/{f=0} f && /=/{sub(/=.*/,"");gsub(/[ \t]/,"");if($0!="")print}' project.godot 2>/dev/null | paste -sd'|' -)
	[ -n "$autos" ] || autos="__none__"
	for f in $files; do
		[ -f "$f" ] || continue
		n=$((n + 1))
		out=$(timeout 60 "$GODOT" --headless --path . --check-only --script "$f" 2>&1)
		# 오토로드 미해결 줄 + 그로 인한 **연쇄** 줄을 걷어내고 남은 것만 진짜 문제로 본다.
		real=$(printf '%s\n' "$out" | grep -E "SCRIPT ERROR|Parse Error|Compile Error" \
			| grep -vE "Identifier not found: ($autos)\b" \
			| grep -vE "Failed to compile depended scripts" \
			| grep -vE 'Failed to load script .* with error "Compilation failed"')
		if [ -n "$real" ]; then
			printf "  FAIL  parse: %s\n" "$f"
			printf '%s\n' "$real" | head -6 | sed 's/^/        /'
			bad=$((bad + 1))
		fi
	done
	[ "$n" -eq 0 ] && return 0
	if [ "$bad" -eq 0 ]; then
		printf "  OK    parse (변경된 .gd %s개)\n" "$n"
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		failed_names="$failed_names parse"
	fi
}

# 단일 프로세스 테스트 하나 — 판정 3조건을 전부 본다.
run_single() {
	local path="$1" name="$2" out code ok err
	out=$(timeout 180 "$GODOT" --headless --path . -s "res://$path" 2>&1)
	code=$?
	ok=$(printf '%s' "$out" | grep -c "TEST_OK")
	err=$(printf '%s' "$out" | grep -c "SCRIPT ERROR")
	if [ "$code" -eq 0 ] && [ "$ok" -ge 1 ] && [ "$err" -eq 0 ]; then
		printf "  OK    %s\n" "$name"
		pass=$((pass + 1))
	else
		printf "  FAIL  %s   (exit=%s TEST_OK=%s SCRIPT_ERROR=%s)\n" "$name" "$code" "$ok" "$err"
		printf '%s\n' "$out" | grep -Ei "fail|script error" | head -12 | sed 's/^/        /'
		fail=$((fail + 1))
		failed_names="$failed_names $name"
	fi
}

# 멀티 방 왕복 — 릴레이 + 호스트 + 게스트 3프로세스 (verify §1).
run_net_room() {
	local sp codefile relay_pid guest_pid host_code
	sp="${TMPDIR:-/tmp}/pb_net_room.$$"
	mkdir -p "$sp" || { echo "  FAIL  net_room (임시 디렉터리 생성 실패)"; fail=$((fail + 1)); return; }
	codefile="$sp/room_code.txt"
	# ⚠ `${sp:?}` — 비었으면 셸이 여기서 멈춘다. 맨 `$sp`면 `/*.log`로 전개될 수 있다.
	rm -f "${sp:?}"/*.log "$codefile"

	"$GODOT" --headless --path . -s res://server/relay/relay_server.gd -- --port="$RELAY_PORT" > "$sp/relay.log" 2>&1 &
	relay_pid=$!
	"$GODOT" --headless --path . -s res://tests/test_net_room_auto.gd -- \
		role=guest "codefile=$codefile" "url=ws://localhost:$RELAY_PORT" > "$sp/guest.log" 2>&1 &
	guest_pid=$!
	timeout 120 "$GODOT" --headless --path . -s res://tests/test_net_room_auto.gd -- \
		role=host "codefile=$codefile" "url=ws://localhost:$RELAY_PORT" > "$sp/host.log" 2>&1
	host_code=$?
	wait "$guest_pid"
	kill "$relay_pid" 2>/dev/null

	local hok herr gok gerr
	hok=$(count_in "TEST_OK" "$sp/host.log")
	herr=$(count_in "SCRIPT ERROR" "$sp/host.log")
	gok=$(count_in "TEST_OK" "$sp/guest.log")
	gerr=$(count_in "SCRIPT ERROR" "$sp/guest.log")
	if [ "$host_code" -eq 0 ] && [ "$hok" -ge 1 ] && [ "$gok" -ge 1 ] && [ "$herr" -eq 0 ] && [ "$gerr" -eq 0 ]; then
		printf "  OK    net_room (호스트+게스트 왕복)\n"
		pass=$((pass + 1))
		rm -rf "${sp:?}"
	else
		printf "  FAIL  net_room   (host exit=%s ok=%s/%s err=%s/%s)\n" "$host_code" "$hok" "$gok" "$herr" "$gerr"
		printf "        로그: %s\n" "$sp"
		fail=$((fail + 1))
		failed_names="$failed_names net_room"
	fi
}

echo "== Project_B 헤드리스 스위트 =="

# 🔴 스위트보다 **먼저** 돈다 — 씬 글루가 파스조차 안 되는 상태에서 나머지 판정은 의미가 없다.
run_parse_check

# 🔴 자동 탐색 — 새 `tests/test_*_auto.gd`는 파일을 놓는 것만으로 여기 들어온다.
#   `test_net_room_auto.gd`만 예외다(인자·3프로세스가 필요해 아래에서 따로 돈다).
found=0
for f in tests/test_*_auto.gd; do
	[ -e "$f" ] || continue
	name=$(basename "$f" .gd)
	name=${name#test_}
	name=${name%_auto}
	[ "$name" = "net_room" ] && continue
	[ -n "$FILTER" ] && case "$name" in *"$FILTER"*) ;; *) continue ;; esac
	found=$((found + 1))
	run_single "$f" "$name"
done

if [ "$found" -eq 0 ] && [ -n "$FILTER" ]; then
	echo "  (필터 '$FILTER'에 맞는 단일 테스트 없음)"
fi

if [ "$FAST" -eq 0 ]; then
	if [ -z "$FILTER" ] || case "net_room" in *"$FILTER"*) true ;; *) false ;; esac; then
		run_net_room
	fi
else
	echo "  SKIP  net_room (--fast)"
fi

echo "-- 통과 $pass · 실패 $fail --"
if [ "$fail" -gt 0 ]; then
	echo "!! 실패:$failed_names"
	exit 1
fi
echo "ALL_TESTS_OK"
