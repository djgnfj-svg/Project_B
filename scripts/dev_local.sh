#!/usr/bin/env bash
# Project_B 로컬 LAN 개발 서버 — 같은 공유기의 두 대가 **인터넷을 안 거치고** 붙는다.
# 실행: bash scripts/dev_local.sh          (익스포트부터 전부)
#       bash scripts/dev_local.sh --fast   (기존 build/web 재사용 — 코드 안 바꿨을 때)
#       bash scripts/dev_local.sh --stop   (Ctrl+C가 안 먹었을 때 남은 서버 정리)
#
# 왜 있나: 공용 릴레이(relay.jachana.com)는 한국에서 홍콩 엣지를 거쳐 왕복 140~215ms다
# (실측 2026-07-24). 같은 집의 두 PC가 그 경로를 쓰면 지연이 통째로 낭비다 — 로컬 릴레이는 ~15ms.
# 배포본(game.jachana.com)은 심사위원·원격 친구용 기본값으로 그대로 두고, 개발 테스트만 여기로 돌린다.
#
# 띄우는 것 2개: 중계 서버(:9080) + 웹 정적 서버(:8910). 둘 다 0.0.0.0 바인딩이라 LAN에서 접속 가능.
# 릴레이 주소는 클라가 자동 판별한다 — 페이지를 LAN IP로 받으면 같은 호스트의 :9080을 쓴다
# (src/net/net.gd default_relay_url) → 초대 링크에 ?relay=를 손으로 붙일 필요가 없다.
set -euo pipefail
cd "$(dirname "$0")/.."

RELAY_PORT=9080   # net.gd LOCAL_RELAY_PORT 미러 — 바꾸면 둘 다 고친다
WEB_PORT=8910
GODOT="${GODOT:-./Godot_v4.7.1-stable_win64.exe}"
FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1

# 그 포트를 LISTENING 중인 Windows 프로세스를 강제 종료 (//PID //F = Git Bash 경로 변환 회피 표기)
kill_port() {
	local port="$1" pids p
	pids=$(netstat -ano 2>/dev/null | grep -E "[:.]$port[[:space:]]+.*LISTENING" | awk '{print $NF}' | sort -u)
	for p in $pids; do
		[[ "$p" =~ ^[0-9]+$ ]] && taskkill //PID "$p" //F > /dev/null 2>&1 || true
	done
}

# --stop = 남은 서버 정리. Ctrl+C가 먹지 않았거나 창을 그냥 닫았을 때의 확실한 탈출구
# (Git Bash에선 SIGINT가 자식 Windows 프로세스까지 안 내려가는 경우가 있다).
if [[ "${1:-}" == "--stop" ]]; then
	kill_port "$RELAY_PORT"
	kill_port "$WEB_PORT"
	sleep 1
	if netstat -ano 2>/dev/null | grep -qE "[:.]($RELAY_PORT|$WEB_PORT)[[:space:]]+.*LISTENING"; then
		echo "⚠ 일부 포트가 아직 열려 있습니다 — 다른 프로그램이 쓰는 중일 수 있습니다." >&2
		exit 1
	fi
	echo "▶ 로컬 서버를 정리했습니다 (포트 $RELAY_PORT · $WEB_PORT)."
	exit 0
fi

if [[ ! -x "$GODOT" && ! -f "$GODOT" ]]; then
	echo "Godot 4.7.1 실행 파일이 없습니다: $GODOT" >&2
	exit 1
fi

# LAN IP 감지 — 외부로 UDP 소켓을 "연결"만 해 보고(패킷은 안 나간다) 커널이 고른 출발 IP를 읽는다.
# ipconfig 파싱보다 안정적이다(가상 어댑터·VPN·다국어 출력에 안 흔들림).
PY="${PY:-python}"
LAN_IP=$("$PY" -c "import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(('8.8.8.8',80));print(s.getsockname()[0]);s.close()" 2>/dev/null || true)
if [[ -z "$LAN_IP" ]]; then
	echo "⚠ LAN IP 자동 감지 실패 — localhost로 진행합니다(다른 PC에서는 못 붙습니다)." >&2
	LAN_IP="localhost"
fi

# 포트 선점 확인 — 익스포트에 시간을 다 쓰고 나서 "릴레이가 안 뜬다"로 죽는 걸 막는다.
# (이 스크립트를 두 번 띄웠거나, 앞서 수동으로 켠 릴레이가 남아 있는 경우)
for port_pair in "$RELAY_PORT 중계 서버" "$WEB_PORT 웹 서버"; do
	port="${port_pair%% *}"
	what="${port_pair#* }"
	if netstat -ano 2>/dev/null | grep -qE "[:.]$port[[:space:]]+.*LISTEN"; then
		echo "포트 $port 이(가) 이미 사용 중입니다 ($what)." >&2
		echo "→ 이미 실행 중인 창이 있으면 그걸 쓰세요. 남은 서버를 정리하려면:" >&2
		echo "   bash scripts/dev_local.sh --stop" >&2
		exit 1
	fi
done

if [[ $FAST -eq 0 ]]; then
	echo "▶ 웹 익스포트 중… (--fast 로 건너뛸 수 있습니다)"
	mkdir -p build/web
	"$GODOT" --headless --path . --export-release "Web" build/web/index.html > /dev/null 2>&1 || true
fi
if [[ ! -f build/web/index.html ]]; then
	echo "build/web/index.html 이 없습니다 — --fast 없이 다시 실행해 익스포트하세요." >&2
	exit 1
fi

# 종료 시 자식 프로세스 정리 — Ctrl+C 한 번으로 릴레이·웹 서버가 같이 죽게
RELAY_PID=""
WEB_PID=""
cleanup() {
	echo
	echo "▶ 정리 중…"
	# ⚠ Git Bash의 kill은 네이티브 Windows 프로세스(Godot·python)를 못 죽이는 경우가 있다 —
	#   그대로 두면 포트가 물린 채 남아 다음 실행이 "포트 사용 중"으로 막힌다(실제로 겪음).
	#   먼저 얌전히 요청하고, 남아 있으면 taskkill로 확실히 끝낸다.
	for pid in "$RELAY_PID" "$WEB_PID"; do
		[[ -z "$pid" ]] && continue
		kill "$pid" 2>/dev/null || true
	done
	sleep 1
	# ⚠ Git Bash의 $! 는 MSYS PID라 taskkill(Windows PID)에 그대로 못 넘긴다 —
	#   그래서 **포트를 물고 있는 쪽**을 찾아 끝낸다. 시작할 때 포트 선점을 이미 거부했으므로
	#   이 포트의 리스너는 우리가 띄운 것뿐이다.
	kill_port "$RELAY_PORT"
	kill_port "$WEB_PORT"
	wait 2>/dev/null || true
	echo "▶ 종료됐습니다."
}
trap cleanup EXIT INT TERM

"$GODOT" --headless --path . -s res://server/relay/relay_server.gd -- --port=$RELAY_PORT > /tmp/pb_relay.log 2>&1 &
RELAY_PID=$!
("$PY" -m http.server "$WEB_PORT" --bind 0.0.0.0 --directory build/web > /tmp/pb_web.log 2>&1) &
WEB_PID=$!

sleep 2
if ! kill -0 "$RELAY_PID" 2>/dev/null; then
	echo "중계 서버가 뜨지 않았습니다 — /tmp/pb_relay.log 확인 (포트 $RELAY_PORT 사용 중일 수 있음)" >&2
	exit 1
fi

cat <<EOF

════════════════════════════════════════════════════════════
  Project_B 로컬 서버 실행 중 (Ctrl+C 로 종료)

  이 PC (호스트)   http://$LAN_IP:$WEB_PORT/?host
  다른 PC (참가)   http://$LAN_IP:$WEB_PORT/

  → 호스트 화면의 "방 코드 복사"로 코드를 넘기고, 참가 PC에서 위 주소를 열어 입력하면 됩니다.

  ⚠ 호스트도 localhost가 아니라 **위 LAN 주소**로 여세요 — localhost로 열면
    게임이 만드는 초대 링크에 localhost가 박혀 다른 PC에서 못 씁니다.

  릴레이: ws://$LAN_IP:$RELAY_PORT  (클라가 자동으로 이 주소를 씁니다)
  로그:   /tmp/pb_relay.log · /tmp/pb_web.log

  ⚠ 다른 PC가 못 붙으면 Windows 방화벽입니다 —
    "Python"과 "Godot"의 **개인/사설 네트워크** 인바운드를 허용하세요.
  ⚠ 두 PC가 같은 공유기(같은 Wi-Fi)에 있어야 합니다.
════════════════════════════════════════════════════════════

EOF

wait
