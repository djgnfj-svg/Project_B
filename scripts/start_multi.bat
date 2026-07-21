@echo off
rem Project_B 멀티 서버 일괄 시작 — 더블클릭 한 번으로 3종 실행:
rem   1) 중계 서버 (localhost:9080)
rem   2) 웹 빌드 서버 (localhost:8910)
rem   3) Cloudflare 터널 (game.jachana.com / relay.jachana.com -> 위 둘로 연결)
rem 접속: https://game.jachana.com  (호스트 자동 시작: https://game.jachana.com/?host)
rem 주의: 창 3개가 열리며, 닫으면 해당 서버가 꺼집니다. 웹 빌드가 없으면 먼저 익스포트하세요.
cd /d "%~dp0.."
start "PB-relay" cmd /k Godot_v4.7.1-stable_win64.exe --headless --path . -s res://server/relay/relay_server.gd -- --port=9080
start "PB-web" cmd /k "cd build\web && python -m http.server 8910"
start "PB-tunnel" cmd /k cloudflared tunnel --config "%USERPROFILE%\.cloudflared\projectb.yml" run projectb
echo Project_B 서버 3종을 시작했습니다. 이 창은 닫아도 됩니다.
pause
