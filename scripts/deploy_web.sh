#!/usr/bin/env bash
# Project_B 웹 배포 정본 — 익스포트 → 스테이징(wasm gzip) → Cloudflare Workers 정적 에셋 배포.
# 실행: bash scripts/deploy_web.sh  (Bash 툴/Git Bash 기준)
set -euo pipefail
cd "$(dirname "$0")/.."

# Godot 헤드리스 익스포트는 실패해도 exit 0인 사례가 있어 산출물 신선도로 판정한다
STAMP=$(mktemp)
./Godot_v4.7.1-stable_win64.exe --headless --path . --export-release "Web" build/web/index.html
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

(cd server/game-worker && npx --yes wrangler deploy)
