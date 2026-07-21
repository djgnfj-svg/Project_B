# Project_B

2D 픽셀아트 **웹 멀티플레이 게임** (Godot 4.7.1, Web/HTML5 익스포트). 2인 협동 보스전 액션.

## 바로 플레이 (설치 불필요)

- **https://game.jachana.com** 접속 → "방 만들기" → 스테이지의 **초대 링크 복사** 버튼으로 친구 초대.
- 주소 뒤에 `?host`를 붙이면 방 생성까지 자동 (`https://game.jachana.com/?host`).
- 초대 링크(`?join=코드`)를 받은 사람은 클릭만 하면 같은 방에 들어옵니다.

## 클론해서 실행 (심사위원/개발자)

1. **Godot 4.7.1**을 받아 실행 파일을 레포 루트에 둡니다 (엔진 바이너리는 용량 문제로 저장소에 없음).
   - https://godotengine.org/download/archive/4.7.1-stable/ (Windows는 `Godot_v4.7.1-stable_win64.exe`)
2. Godot으로 이 폴더(`project.godot`)를 열고 실행(F5)합니다.
3. 로비에서 "방 만들기" — 릴레이 서버는 공용 `wss://relay.jachana.com`이 기본이라 **별도 서버 실행 없이 바로 멀티가 됩니다.**
   (로컬 릴레이로 테스트하려면 로비의 "고급" 버튼으로 주소를 `ws://localhost:9080`으로 바꾸세요.)

## 배포 (친구/기여자 포함 누구나)

Claude Code에게 "배포해줘"라고 하거나 직접:

```bash
bash scripts/deploy_web.sh
```

- 필요한 것: 레포 루트의 Godot 4.7.1 + 웹 익스포트 템플릿(에디터 → 익스포트 템플릿 관리) + Node + `npx wrangler login`(무료 Cloudflare 계정).
- 스크립트가 로그인 계정을 보고 자동 분기합니다: **jachana.com 소유 계정(djgnfj)** → `game.jachana.com` 고정 주소, **그 외 계정** → 자기 `*.workers.dev` 임시 주소.
- 임시 주소로 배포했으면 출력된 workers.dev 주소 뒤에 `?host`를 붙여 공유하면 됩니다 — 릴레이는 공용 `wss://relay.jachana.com`을 그대로 씁니다.

## 문서

- **`docs/GDD.md`** — 게임 기획서(단일 진실원). 🔒 수정은 승인제.
- **`CLAUDE.md`** — 개발 규율·아키텍처·에이전트 하네스 안내(구현 정본).

## 개발 메모

- 언어: GDScript (typed). 웹 게임이라 **네트워크가 코어** — 네트워크 코드는 항상 리뷰를 거칩니다(WebSocket·호스트 권한·입력 검증).
- 테스트: `tests/*_auto.gd` 헤드리스 스위트 — 실행법은 `CLAUDE.md` 「검증 명령」.
- `.mcp.json`의 `GODOT_PATH`는 로컬 절대 경로라, 각자 환경에 맞게 바꿔야 합니다.
