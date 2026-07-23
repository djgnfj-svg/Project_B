#!/usr/bin/env bash
# Project_B 웹 배포 정본 — 익스포트 → 스테이징(wasm gzip) → Cloudflare Workers 정적 에셋 배포.
# 실행: bash scripts/deploy_web.sh  (Bash 툴/Git Bash 기준)
# 누가 돌려도 된다: wrangler 로그인 계정이 jachana 소유(djgnfj)면 game.jachana.com,
# 그 외 계정이면 자기 workers.dev 임시 주소로 배포된다 (config 자동 선택).
set -euo pipefail
cd "$(dirname "$0")/.."

# jachana.com 커스텀 도메인을 소유한 Cloudflare 계정 (djgnfj) — whoami가 이 ID면 고정 주소 배포
JACHANA_ACCOUNT_ID="bc1854af49d65d6e7bcf4a79809c4f2f"

GODOT="${GODOT:-./Godot_v4.7.1-stable_win64.exe}"
if [[ ! -x "$GODOT" && ! -f "$GODOT" ]]; then
	echo "Godot 4.7.1 실행 파일이 없습니다: $GODOT" >&2
	echo "→ https://godotengine.org/download/archive/4.7.1-stable/ 에서 받아 레포 루트에 두거나, GODOT=<경로> 로 지정하세요." >&2
	exit 1
fi
if [[ -n "${APPDATA:-}" && ! -d "$APPDATA/Godot/export_templates/4.7.1.stable" ]]; then
	echo "⚠ 웹 익스포트 템플릿(4.7.1.stable)이 없어 보입니다 — Godot 에디터: 에디터 → 익스포트 템플릿 관리에서 설치하세요." >&2
fi

# Godot 헤드리스 익스포트는 실패해도 exit 0인 사례가 있어 산출물 신선도로 판정한다
STAMP=$(mktemp)
mkdir -p build/web  # 클론 직후엔 없다(gitignore) — 없으면 익스포트가 "대상 폴더 없음"으로 죽는다 (b-hy 첫 배포에서 발견)
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
for f in build/web/index.wasm build/web/index.pck; do
	if [[ ! -s "$f" || ! "$f" -nt "$STAMP" ]]; then
		echo "익스포트 실패 의심: $f 이 새로 생성되지 않음 — 배포 중단" >&2
		rm -f "$STAMP"
		exit 1
	fi
done
rm -f "$STAMP"

PUB=server/game-worker/public
rm -rf "$PUB"
mkdir -p "$PUB"
for f in build/web/*; do
	case "$f" in
	*.import) continue ;; # Godot 익스포트 사이드카 — 서빙 불필요
	*/index.wasm) gzip -9 -c "$f" > "$PUB/index.wasm.gz" ;; # 에셋 25MiB 제한 우회 — game-worker가 gzip 서빙
	*) cp "$f" "$PUB/" ;;
	esac
done

cd server/game-worker
if ! npx --yes wrangler whoami > /tmp/pb_whoami.txt 2>&1; then
	echo "Cloudflare 로그인이 안 돼 있습니다 — 먼저 실행: npx wrangler login" >&2
	exit 1
fi
if grep -q "$JACHANA_ACCOUNT_ID" /tmp/pb_whoami.txt; then
	echo "→ jachana 계정 감지: game.jachana.com 고정 주소로 배포"
	npx --yes wrangler deploy --config wrangler.jachana.jsonc
else
	echo "→ 외부 계정: workers.dev 임시 주소로 배포 (아래 출력의 주소를 공유 — 호스트 시작은 주소 뒤에 ?host)"
	npx --yes wrangler deploy
fi
