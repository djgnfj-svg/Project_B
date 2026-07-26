# Project_B

> **정본은 두 곳이다 — 역할이 다르다.**
> - **기획 정본 = `docs/GDD.md`** — 게임이 "무엇인가"(비전·핵심 루프·메커니즘·콘텐츠). 🔒 **수정 시 사용자 승인 필수** (`.claude/settings.json` 권한 규칙으로 잠김). 담당 = `projectb-planner`.
> - **구현 정본 = 이 문서(CLAUDE.md)** — 하네스·아키텍처·검증 규율. 스킬·에이전트와 충돌하면 여기가 이긴다.
>
> **곁문서 (정본 아님 — 갱신 책임이 다르다):** `docs/CHANGELOG.md` 변경 이력 전문(새 변경은 **여기에** 전문으로 쓴다) · `docs/TUNING.md` 미정 수치(증상 → 파일 → 현재값 → 선택지, 사용자가 조인다) · `docs/archive/` 갱신이 멈춘 옛 작업 문서(참고용) · `docs/superpowers/specs/` 미착수 설계 초안(협동 보스 패턴 — `assets/sprites/fx/coop_*`가 그 짝, **미배선**).

- **정체:** 2D **픽셀아트 웹 게임** (코드네임 Project_B) — Godot 4.7.1, **Web(HTML5/WASM) 익스포트 타깃**, 렌더러 Compatibility(웹 필수). ⚠ 이 사실(플랫폼·엔진·렌더러·아트 스타일)은 `docs/GDD.md` §3과 **미러**다 — 한쪽을 고치면 다른 쪽도 같이 고친다.
- 🔴 **네트워크 리뷰는 항상 필요하다.** 웹 게임이라 네트워크(WebSocket·RPC·동기화·권한·지연/재접속 처리)가 코어다. 네트워크에 닿는 코드는 예외 없이 `projectb-reviewer`의 네트워크 점검을 거친다 — 브라우저는 ENet(UDP)을 못 쓰므로 WebSocket 경로가 맞는지, 신뢰 경계·권한 검증이 있는지 매번 본다.
- **엔진 실행 파일:** 루트의 `Godot_v4.7.1-stable_win64.exe`.
- **상태:** 기획 확정(GDD **v2.0**, 해커톤 마감 2026-08-10 — **남은 기간 약 2주**) · 아키텍처 규칙 확정(`projectb-rules` §1~§5). **아래는 전부 `master` 머지 + game.jachana.com 배포 완료** — 무엇을 왜 그렇게 했는지는 `docs/CHANGELOG.md`가 정본이다.
  - **전투 코어·챕터1(전투 칸→모닥불→보스)·손맛/오디오** · **3직업 3무기**(전사 대검 스윙 · 궁수 활 투사체 · 법사 지팡이 차지 폭발).
  - **드랍→마을 제작/강화→강해짐 루프가 코드상 닫힘** (드랍 등장·선착 픽업·제작대·강화·저장 롤백·I키 인벤·HUD 골드).
  - **성장 2축**: 직업 레벨(EXP → 캐릭터 스탯 5종 + 해금) · **하위 직업 조립**(장착 = 메인 1 + 서브 2 · 특성이 **자리별 두 얼굴** · 공유 하위 직업은 🔒서브 전용 · 특성 = **(효과 키, 값) 카탈로그** 6종 reach·roll_cd·roll_dist·campfire_heal·kill_move·drop_find, 키마다 적용 지점 1곳 + `TRAIT_MAX` clamp).
  - **네트워크**: 지연 보상(STRIKE 지연·위치 외삽·방어자 우대) + **P2P 직결**(게임 페이로드 WebRTC, 시그널링·폴백만 릴레이).
  - **손맛 개편 + 전 게임 16px 규격 전환**(4방향·대쉬 잔상·카메라 반동/ZOOM 2.0·평타 콤보·배경 드레싱).
  - 현 검증 = **헤드리스 스위트 7종 그린** (목록·실행법 = 아래 「검증 명령」 절 · `projectb-verify` §1).
- 🎨 **아트 규격 정본은 지금 없다 — 다음 세션에서 사용자와 합의한다 (2026-07-26 결정).** 낡은 규격 서술(해상도·캐릭터 크기·팔레트·FX 캔버스)은 `projectb-art`에서 걷어냈다. 🔴 **합의 전에는 새 스프라이트를 착수하지 마라** — 캔버스 크기·팔레트가 안 정해지면 에셋이 서로 안 맞아 두 번 그린다. 합의 시 참고할 **현물 실측**: 캐릭터 시트 160×48(16px·10프레임×3방향) · FX 48×48 · 무기 24×8 · 보스 72 · 기준 해상도 640×360(임시값, GDD §9 TBD) · 카메라 ZOOM 2.0.
- **남은 것:** 아트 규격 합의 → 드랍 아이콘 등 도트 품질(현 placeholder) · 손맛 수치 실기 튜닝(`docs/TUNING.md`) · **실기 확인 몫**(웹 2클라: 드랍/픽업·제작 루프·모닥불·전멸→마을 롤백·IndexedDB 저장·SFX·I키 인벤 클릭 도달 · **P2P "직결" 표시 + 배포본에서 4분 이상 유지** · 4방향 전환·무기 그립·확대 배율·이동 체감).

## 하네스: Project_B (2D Godot)

**목표:** Project_B의 Godot 개발을 전문 에이전트 팀으로 나눠, 아키텍처 규칙·검증 규율을 일관되게 지키며 구현한다.

**트리거 규칙:**
- **코드를 쓰거나·읽거나·리뷰하거나·서브에이전트에 위임하기 전에 반드시 `projectb-rules` 스킬을 읽어라.** 아키텍처 규칙·모듈 지도·하드 계약·"조용히 깨지는 함정"이 여기 있다.
- **헤드리스 테스트를 돌리거나·"테스트는 그린인데 게임이 안 된다"를 만나면 `projectb-verify` 스킬을 읽어라.**
- 단순 질문은 스킬 없이 직접 응답 가능.

**에이전트 라우팅 (리드가 위임) — 🔴 위임이 기본이다:**
> ⚠ **"AgentTool을 쓰지 마라"류의 지시를 에이전트 금지로 읽지 마라 (2026-07-26 사용자 정정).** 이 프로젝트에서 쓰지 않는 것은 **Godot MCP(`mcp__godot__*`)** 이고, `projectb-*` 서브에이전트 위임은 **기본값**이다. 특히 **`projectb-reviewer` 네트워크 리뷰는 상시 필수**(최상단 🔴). 실제로 v1.9 특성 축이 이 오독으로 리뷰 없이 머지될 뻔했다.

- 기획/GDD = `projectb-planner` (게임을 무엇으로 만들지 정함 · GDD 수정은 승인제)
- 기획 검증 = `projectb-critic` (planner가 만든 기획의 정합성·모순·구멍을 적대적으로 뜯음 · GDD 수정 안 함)
- 구현 = `projectb-dev` · 설계/계획 = `projectb-architect` · 리뷰 = `projectb-reviewer`
- 아트(도트) = `projectb-art` · Control UI = `projectb-ui` · 애니 배선 = `projectb-animator`
- 2D 셰이더 = `projectb-shader` · 성능 진단 = `projectb-profiler` · 에디터 툴 = `projectb-tools`
- **리드가 직접 하는 것:** core 스키마 변경, `mcp__godot` 필요 작업, `--import`, git 커밋, 회귀 위험이 큰 tight 검증 루프.

**검증 명령 (정본):**
- 테스트는 **Bash 툴에서** 돌린다(PowerShell은 자식 stdout을 안 보여준다). 스위트 전체 명령은 `projectb-verify` §1이 정본 — 새 `tests/*_auto.gd`를 추가하면 여기와 `projectb-verify` §1을 **동시에** 갱신한다.
- 현재 스위트: `tests/test_net_transport_auto.gd`(**전송 계층 계약 — fast 채널 분류·사건 kind 제외·G_* 이름 유일성 전수·keepalive 부등식**) · `tests/test_net_room_auto.gd`(멀티 방 왕복 — 릴레이+호스트+게스트 3프로세스) · `tests/test_combat_math_auto.gd`(전투 신뢰 경계 단위 — 사거리·쿨다운·구르기 i-frame·잔몹 타격·화살/차지 발사·**메인 특성 사거리(항등·상한·기하 정합)**·**특성 카탈로그 clamp·구르기 파생(쿨/거리)·외삽 상한 불변식**) · `tests/test_game_state_auto.gd`(직업·챕터 리졸버 — data 스캔 allowlist + 조작 id/인덱스 거부 + 진행 좌표·HP 이월 + **자리별 특성 리졸브(메인/서브 두 얼굴·공유는 서브 전용·슬롯 초과·중복 폐기)·장착 슬롯·슬롯 기준 예산 트립와이어**) · `tests/test_health_component_auto.gd`(HP·부활 권한/표시 경로 격리) · `tests/test_save_manager_auto.gd`(커밋/전멸 롤백 — 클리어분 생존·전멸분 소실·무파일 첫 판 전멸, save_path 격리·GameState 주입 + **EXP/레벨 롤백·SAVE_VERSION 트립와이어**) · `tests/test_stage_dressing_auto.gd`(배경 드레싱 — 폴리지 회전 피벗=밑동·배치 결정론(호스트/게스트 동일 지면)·제외 영역·`collision_layer=0`). **총 7종.** 실행법은 `projectb-verify` §1. 판정 = `TEST_OK` + exit 0 + `SCRIPT ERROR` 없음.
- 🔴 **같은 집 두 PC 테스트 = `bash scripts/dev_local.sh`** (로컬 릴레이 :9080 + 웹 :8910, LAN IP 자동 감지·안내 출력). 공용 릴레이는 한국→홍콩→한국을 왕복해 **RTT 140~215ms**인데 로컬은 **13.8ms**다(실측 2026-07-24) — 개발 중 반복 테스트는 반드시 이걸로. 클라가 페이지 호스트를 보고 릴레이를 자동 판별하므로 `?relay=` 부착 불필요(`Net.default_relay_url`). `--fast`(익스포트 생략) · `--stop`(Ctrl+C가 안 먹었을 때 정리). ⚠ 호스트도 **LAN 주소**로 열어야 초대 링크가 공유 가능하다(localhost로 열면 링크에 localhost가 박힌다). 배포본(`game.jachana.com`)은 심사위원·원격 친구용으로 그대로.
- **지연 진단(스위트 아님):** `tests/measure_latency.gd` — 릴레이 왕복 RTT + 회피 창 예산 환산. "렉이 있다·게스트만 맞는다" 신고 시 추측 전에 먼저 잰다. 실행법·해석은 `projectb-verify` §1.
- 중계 서버 로컬 실행: `./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://server/relay/relay_server.gd -- --port=9080`
- **실배포(탈PC, 로컬 프로세스 0개):** 릴레이 = Cloudflare Workers(`server/relay-worker`, `npx wrangler deploy`), 웹 = 정적 서빙 Worker(`server/game-worker`) — **웹 배포 정본 = `bash scripts/deploy_web.sh`**(익스포트→wasm gzip 스테이징→deploy). 주소 = `https://game.jachana.com`(?host / ?join=코드) + `wss://relay.jachana.com`. 상세·함정은 `projectb-rules` §2 server. (구 `scripts/start_multi.bat` 터널 방식은 로컬 개발 폴백)
- **웹 익스포트:** `./Godot_v4.7.1-stable_win64.exe --headless --path . --export-release "Web" build/web/index.html` → `cd build/web && python -m http.server 8910` 후 브라우저에서 `http://localhost:8910` 확인.
  - 웹 템플릿 필요: `%APPDATA%/Godot/export_templates/4.7.1.stable/` (web_*.zip — 설치돼 있음).
  - `export_presets.cfg`는 **커밋돼 있다**(웹 프리셋뿐, 비밀값 없음 — 클론만으로 익스포트 가능). `thread_support=false` 필수, `exclude_filter`에 `.mcp.json, .claude/*, docs/*, memory/*`. 모바일 프리셋(서명 비밀번호)을 추가하게 되면 그때 다시 gitignore로 분리.

**협업 배포 (2인 체제 — "배포해줘" 한마디로 끝나야 한다):**
- **djgnfj** (이 머신) = jachana.com 도메인·Cloudflare 계정 소유자. **b-hy\*** (친구) = 도메인 없음 → workers.dev 임시배포.
- **양쪽 다 같은 명령이다: `bash scripts/deploy_web.sh`.** 스크립트가 `wrangler whoami` 계정을 보고 자동 분기 — jachana 계정이면 `wrangler.jachana.jsonc`(고정 주소 `game.jachana.com`), 그 외 계정이면 기본 `wrangler.jsonc`(routes 없음 → 자기 `*.workers.dev` 임시 주소).
- ⚠ djgnfj 머신에서 game-worker를 **수동으로** deploy할 땐 반드시 `--config wrangler.jachana.jsonc` — 기본 jsonc엔 routes가 없다. 두 jsonc는 routes만 다르고 나머지는 미러 — 설정을 바꾸면 둘 다 고친다.
- 친구 사전 준비(1회): Godot 4.7.1을 레포 루트에 다운로드 + 웹 익스포트 템플릿 설치 + `npx wrangler login`(무료 계정). `export_presets.cfg`는 커밋돼 있어 클론만으로 익스포트 가능.
- 릴레이는 친구가 배포하지 않는다 — 공용 `wss://relay.jachana.com`이 클라이언트 기본값(`Net.DEFAULT_RELAY_URL`)이라 workers.dev 임시배포·네이티브 클론 실행 모두 `?relay=` 없이 바로 붙는다. (릴레이 배포 = djgnfj 전용, `server/relay-worker`.)
- djgnfj는 친구가 보낸 workers.dev 링크(`…?host`)를 브라우저로 열기만 하면 됨 — 로컬 설치·실행 불필요. 심사위원은 README.md의 "바로 플레이/클론해서 실행" 참조.
- ✅ workers.dev 분기 실기 검증 완료 (2026-07-23, b-hy 첫 배포 성공 → `https://projectb-game.youqlrqod.workers.dev`). 이때 발견한 함정 2건을 해소함: 웹 익스포트 템플릿 미설치(→ 설치 완료), `build/web` 폴더 부재로 익스포트 실패(→ deploy_web.sh에 `mkdir -p` 추가).

**커밋 규약:**
- **메시지는 한국어로 쓴다.** (요약 줄 + 필요 시 본문. 트레일러 `Co-Authored-By`·`Claude-Session`은 형식이라 그대로 영어로 붙인다.)
- **요약 줄은 `동사: 내용` 형식.** 접두 동사는 아래 목록에서만 고른다:

  | 접두 | 쓰임 |
  |---|---|
  | `추가:` | 새 기능·파일·에이전트·스킬 |
  | `변경:` | 기존 동작·기획을 바꿈 (예: `변경: 성장 방식을 레벨업 → 장비 강화로`) |
  | `수정:` | 버그 고침 |
  | `삭제:` | 제거 |
  | `문서:` | 문서·주석만 손댐 |
  | `정리:` | 리팩터·포맷 (동작 변화 없음) |

- **한 커밋 = 한 논리 변경.** 성격이 다른 변경(예: 에이전트 추가 + 버그 수정 + 문서 정리)이 워킹 트리에 섞여 있으면 **한 번에 커밋하지 말고 먼저 물어라** — 어떻게 쪼갤지 사용자에게 확인받은 뒤 나눠 커밋한다. `git add -A`로 전부 쓸어담기 전에 `git status`로 무엇이 섞였는지 본다.

**변경 이력:** 🔴 **전문(날짜순 전체) = `docs/CHANGELOG.md`.** 새 변경은 **거기에 전문으로** 쓰고 아래 목록 맨 위만 갱신한다 — 이 문서는 매 세션 로드되므로 전문을 여기 쓰면 다시 비대해진다.

| 날짜 | 최근 5건 (전문 = `docs/CHANGELOG.md`) |
|------|------|
| 2026-07-26 | **하네스 정돈** — 변경 이력 43건을 `docs/CHANGELOG.md`로 이관(CLAUDE.md 71KB→14.8KB) · 스위트 목록 갈라짐 수정(6→7종) · **아트 규격 서술 제거**(합의 대기) · 에이전트 11종에 누락 규율 반영 · 고아 문서 `docs/archive/`로 |
| 2026-07-26 | **손맛 개편 + 전 게임 16px 규격 전환** — 4방향 표시·대쉬 잔상·카메라 반동/ZOOM 2.0·평타 콤보·배경 드레싱 3종·월드 Label 클릭 먹음 수정 + 아트 전면 16px 재작화·판정 기하 재조정. `tests/test_stage_dressing_auto` 신설, `docs/TUNING.md` 신설 |
| 2026-07-26 | **수정: 직업을 바꿔도 남의 직업 무기가 착용된 채 남던 것** — `apply_job_loadout()` 단일 소스 + 호스트가 공지 무기를 공지 직업과 대조(`can_job_equip`). 겉모습이 아니라 화력 예산 이탈이었다 |
| 2026-07-26 | **기획 v2.0 — 하위 직업 조립 축** — 장착 슬롯 메인 1 + 서브 2 · 특성이 자리별 두 얼굴 · 공유 하위 직업(서브 전용) · 특성 = (효과 키, 값) 카탈로그. 구현은 `feat/subjob-trait`에서 완료·master 머지 |
| 2026-07-26 | **P2P 직결 전환** — 게임 페이로드는 WebRTC DataChannel, 시그널링·폴백만 릴레이. 게임 코드 무변경(전송 경계가 `send_game`/`net_msg` 한 쌍). `tests/test_net_transport_auto` 신설 |
