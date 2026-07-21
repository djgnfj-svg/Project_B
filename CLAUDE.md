# Project_B

> **정본은 두 곳이다 — 역할이 다르다.**
> - **기획 정본 = `docs/GDD.md`** — 게임이 "무엇인가"(비전·핵심 루프·메커니즘·콘텐츠). 🔒 **수정 시 사용자 승인 필수** (`.claude/settings.json` 권한 규칙으로 잠김). 담당 = `projectb-planner`.
> - **구현 정본 = 이 문서(CLAUDE.md)** — 하네스·아키텍처·검증 규율. 스킬·에이전트와 충돌하면 여기가 이긴다.

- **정체:** 2D **픽셀아트 웹 게임** (코드네임 Project_B) — Godot 4.7.1, **Web(HTML5/WASM) 익스포트 타깃**, 렌더러 Compatibility(웹 필수). ⚠ 이 사실(플랫폼·엔진·렌더러·아트 스타일)은 `docs/GDD.md` §3과 **미러**다 — 한쪽을 고치면 다른 쪽도 같이 고친다.
- 🔴 **네트워크 리뷰는 항상 필요하다.** 웹 게임이라 네트워크(WebSocket·RPC·동기화·권한·지연/재접속 처리)가 코어다. 네트워크에 닿는 코드는 예외 없이 `projectb-reviewer`의 네트워크 점검을 거친다 — 브라우저는 ENet(UDP)을 못 쓰므로 WebSocket 경로가 맞는지, 신뢰 경계·권한 검증이 있는지 매번 본다.
- **엔진 실행 파일:** 루트의 `Godot_v4.7.1-stable_win64.exe`.
- **상태:** 기획 확정(GDD v1.4, 해커톤 마감 2026-08-10) · 아키텍처 규칙 확정(`projectb-rules` §1~§5) · **프로젝트 뼈대 생성 + 웹 익스포트 파이프라인 검증 완료.** 기준 해상도 640×360은 임시값(GDD §9 TBD). 다음 단계 = 멀티 골격 스파이크 또는 전사 수직 슬라이스.

## 하네스: Project_B (2D Godot)

**목표:** Project_B의 Godot 개발을 전문 에이전트 팀으로 나눠, 아키텍처 규칙·검증 규율을 일관되게 지키며 구현한다.

**트리거 규칙:**
- **코드를 쓰거나·읽거나·리뷰하거나·서브에이전트에 위임하기 전에 반드시 `projectb-rules` 스킬을 읽어라.** 아키텍처 규칙·모듈 지도·하드 계약·"조용히 깨지는 함정"이 여기 있다.
- **헤드리스 테스트를 돌리거나·"테스트는 그린인데 게임이 안 된다"를 만나면 `projectb-verify` 스킬을 읽어라.**
- 단순 질문은 스킬 없이 직접 응답 가능.

**에이전트 라우팅 (리드가 위임):**
- 기획/GDD = `projectb-planner` (게임을 무엇으로 만들지 정함 · GDD 수정은 승인제)
- 기획 검증 = `projectb-critic` (planner가 만든 기획의 정합성·모순·구멍을 적대적으로 뜯음 · GDD 수정 안 함)
- 구현 = `projectb-dev` · 설계/계획 = `projectb-architect` · 리뷰 = `projectb-reviewer`
- 아트(도트) = `projectb-art` · Control UI = `projectb-ui` · 애니 배선 = `projectb-animator`
- 2D 셰이더 = `projectb-shader` · 성능 진단 = `projectb-profiler` · 에디터 툴 = `projectb-tools`
- **리드가 직접 하는 것:** core 스키마 변경, `mcp__godot` 필요 작업, `--import`, git 커밋, 회귀 위험이 큰 tight 검증 루프.

**검증 명령 (정본):**
- 테스트는 **Bash 툴에서** 돌린다(PowerShell은 자식 stdout을 안 보여준다). 스위트 전체 명령은 `projectb-verify` §1이 정본 — 새 `tests/*_auto.gd`를 추가하면 여기와 `projectb-verify` §1을 **동시에** 갱신한다.
- 현재 스위트: `tests/test_net_room_auto.gd`(멀티 방 왕복 — 릴레이+호스트+게스트 3프로세스) · `tests/test_combat_math_auto.gd`(전투 신뢰 경계 단위) · `tests/test_game_state_auto.gd`(직업 리졸버 — data/jobs 스캔 allowlist + 조작 id 폴백). 실행법은 `projectb-verify` §1. 판정 = `TEST_OK` + exit 0 + `SCRIPT ERROR` 없음.
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
- ⚠ **미검증 1건:** 외부 계정 → workers.dev 분기는 아직 실기로 안 돌았다(djgnfj 계정뿐이라 검증 불가). **친구(b-hy\*)의 첫 배포가 이 분기의 실기 검증이다** — 성공하면 이 줄을 지운다. 친구가 Cloudflare 계정이 없으면 그때 무료 가입(이메일만, 카드 불필요) 후 `npx wrangler login`.

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

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-07-21 | 탁본 하네스를 Project_B용으로 이식 (에이전트 9종 `takbon-*`→`projectb-*`, 스킬 `takbon-rules/verify`→`projectb-rules/verify` 재작성, Godot 4.6.1→4.7.1) | 전체 | 탁본 `.claude` 복사본을 신규 2D 프로젝트에 맞춰 일반화. 게임 고유 사실은 걷어내고 보편 규율만 유지 |
| 2026-07-21 | 기획 담당 `projectb-planner` + 진실원 문서 `docs/GDD.md` 신설, GDD 수정 승인 게이트(settings.json `permissions.ask`) 추가 | agents/projectb-planner.md · docs/GDD.md · .claude/settings.json | 하나의 진실원 기획 문서로 개발하고, 그 문서 수정은 사용자 승인을 받도록 |
| 2026-07-21 | 프로젝트 정체를 웹 게임(Web/HTML5 익스포트)으로 확정, 네트워크 리뷰 상시 필수 규칙 추가 | CLAUDE.md · projectb-rules · projectb-reviewer | 웹 게임이라 네트워크가 코어 — 리뷰에서 WebSocket·권한·검증을 매번 확인 |
| 2026-07-21 | "비주얼은 스프라이트 기본, 도형으로 때우지 마라" 규약 추가 | projectb-rules §0 · projectb-dev · projectb-reviewer | 임시라도 스프라이트(텍스처)로 만들어야 나중에 이미지 교체가 쉬움 |
| 2026-07-21 | 기획 검증 에이전트 `projectb-critic` + `projectb-plancheck` 스킬(7 정합성 렌즈) 신설 | agents/projectb-critic.md · skills/projectb-plancheck | planner가 만든 기획을 적대적으로 검증(생성-검증 짝). 모순·안 닫히는 루프·비현실적 범위를 잡되 GDD는 안 고침 — 수정은 planner 승인제로 |
| 2026-07-21 | 커밋 규약 신설 — 한국어 메시지, 요약 줄 `동사: 내용` 형식(추가/변경/수정/삭제/문서/정리), 한 커밋=한 논리 변경(섞이면 먼저 질문) | CLAUDE.md 커밋 규약 절 | 커밋 언어·형식·단위를 고정해 이력을 읽기 쉽게, 뒤섞인 커밋 방지 |
| 2026-07-21 | `projectb-rules` §1~§5를 GDD 기준 실제 값으로 채움 — 오토로드 6종(EventBus·Net·GameState·Db·SaveManager·Audio)+호스트 권한 모델, 모듈 지도 10종, 예약 하드 계약(combat_math·net_schema·호스트 확정), 데이터 주도 매핑, 물리 레이어 배정표(7층)+웹·멀티 고유 함정 | projectb-rules · CLAUDE.md 상태 줄 | GDD v1.4 확정에 따라 구현 착수 전 아키텍처 지도를 고정 — 이후 모든 위임이 같은 지도를 봄 |
| 2026-07-21 | Godot 프로젝트 뼈대 생성(project.godot — Compatibility·Nearest·640×360 임시+정수배, 부팅 씬 src/main) + 4.7.1 웹 템플릿 설치 + 웹 익스포트 파이프라인 검증(빌드 산출·로컬 서버 200 확인). 웹 익스포트 정본 명령을 검증 명령 절에 추가 | project.godot · src/main · CLAUDE.md | 웹 빌드가 제출물의 전부 — 익스포트 리스크를 Day 1에 제거 |
| 2026-07-21 | 멀티 골격 스파이크 — 자체 JSON/WebSocket 프로토콜(net_schema 단일 소스) + 중계 서버(server/relay, 방 코드 스코프 릴레이) + Net 오토로드 + 로비/테스트 스테이지(피어당 스폰·위치 동기화). 첫 자동 테스트(tests/test_net_room_auto.gd — 방 왕복 + 방 종료 후 재생성, 뮤테이션 2종으로 검출력 증명), reviewer 네트워크 리뷰 Critical(방 종료 후 상태기계 데드락) 수정. 함정 추가: `-s`에선 오토로드 전역 식별자 컴파일 불가 → core/net은 /root+class_name 접근 | src/core·src/net·server/relay·src/player·src/stage·src/ui·tests · projectb-rules §2·§3·§5 · projectb-verify §1 | 네트워크가 코어(웹 게임) — 멀티 구조를 먼저 뚫고 그 위에 게임플레이를 쌓기 위해 |
| 2026-07-21 | 전사 슬라이스 1단계 — 마우스 조준(2방향 플립)·좌클릭 공격(_unhandled_input, 원형 질의)·Shift 구르기 + 허수아비 적(EnemyDef·dummy.tres). 전투 동기화 = 호스트 권한: hit_req 사거리+쿨다운 검증(CombatMath, 같은 스윙 다중 타격 허용), 부활 확정 호스트 전용(enemy_hp_confirmed→ehp 브로드캐스트), ehp 송신자 검증, 원격 변위 클램프(순간이동 스푸핑 완화), 공격자 job 기반 판정. 테스트 추가: test_combat_math_auto(경계값, 뮤테이션 검출 확인) | src/core(combat_math·enemy_def·event_bus·net_schema)·src/enemies·src/player·src/stage·data·tests·project.godot | GDD v1.5 조작 확정 → 전투 코어 착수. reviewer Critical 3·Important 2 반영 |
| 2026-07-21 | 브라우저 실기 검증 정비 — 한글 픽셀 폰트(Galmuri9, OFL) 임베드(한글 전부 tofu였음), 로비 중앙 레이아웃 수정(비-Control 부모에서 앵커 미적용 → 뷰포트 크기 강제), 방 코드 HUD(스테이지 좌상단), 자동 시작(`?host`/`?join=코드` — 초대 링크 스트레치의 골격, 네이티브 `--host/--join=`), 웹 디버그 입력 브리지(`?debug=1`에서만 `window.pb_press/pb_release`). 크롬 2탭 실기 검증 통과: 참가·위치/공격 연출 동기화·게스트 공격→호스트 확정→사망→부활 브로드캐스트 수렴. 함정 등록: 크롬 백그라운드 탭 프리즈 = 호스트 정지 | assets/fonts·src/ui/lobby·src/stage·src/core/debug_bridge·project.godot · projectb-rules §5 | 웹 실기에서만 드러나는 결함(폰트·레이아웃·검증 불가능성)을 Day 1에 제거 |
| 2026-07-22 | 서버 탈PC 배포 — 릴레이를 Cloudflare Workers+Durable Object로 포팅(`server/relay-worker`, relay.gd와 1:1 + 배포 필수 3종: 연결 64·방 24·메시지 2KB 상한, 60초 스윕·3분 좀비 정리), 웹 빌드 정적 서빙 Worker(`server/game-worker` — wasm 25MiB 제한을 gzip 사전압축으로 우회), 배포 정본 `scripts/deploy_web.sh`. 프로토콜 동일성은 기존 `test_net_room_auto`를 `url=`로 겨눠 검증(로컬 wrangler dev·실배포 wss 둘 다 TEST_OK). net_schema에 FAIL_SERVER_FULL 추가. 함정: wrangler dev는 127.0.0.1만(localhost는 IPv6), R2는 대시보드 활성화 필요라 미사용, Pages는 파일 25MiB 제한으로 포기 | server/relay-worker·server/game-worker·scripts·src/core/net_schema.gd · projectb-rules §2 · CLAUDE.md | "프로세스가 왜 이렇게 많냐" — 로컬 프로세스 0개 목표(메모리 과제 ②), 링크 공유만으로 상시 접속 |
| 2026-07-22 | 초대 원클릭 UX — 스테이지 HUD "초대 링크 복사" 버튼(`?join=코드` 전체 URL 클립보드, 비-기본 릴레이만 `&relay=` 부착), 초대 URL·릴레이 기본값을 `Net`(`invite_url()`·`default_relay_url()`) 단일 소스로 통합, 로비 단순화(방 만들기 큰 버튼 + 코드 참가 폴백, 서버 주소는 접힌 고급 옵션). 실기 검증: 도메인 멀티 정상. 리뷰 Critical 0·Minor 반영(focus_mode 0·피드백 타이머 중첩·네이티브 relay 중복) | src/net·src/ui/lobby·src/stage | 심사위원/친구가 링크 클릭만으로 판까지 도달해야 함(메모리 과제 ①, GDD §10) — 주소·코드 수동 복사 불만 제거 |
| 2026-07-22 | 협업 배포 절(2인 체제) 신설 — djgnfj = jachana.com 소유·고정 주소 배포 담당, 친구(b-hy\*) = 도메인 없음 → workers.dev 임시배포(routes 삭제 + 공용 relay.jachana.com 재사용 + `?relay=` 링크 부착) | CLAUDE.md 협업 배포 절 | 친구가 코드를 고쳐 임시배포하면 djgnfj가 링크만 열어 확인하는 협업 흐름을 문서화 |
| 2026-07-22 | 클론-앤-배포 원커맨드화 — `export_presets.cfg` 커밋(비밀값 없음), game-worker wrangler를 기본(routes 없음, workers.dev)/`wrangler.jachana.jsonc`(고정 주소)로 분리, `deploy_web.sh`가 `wrangler whoami` 계정 보고 자동 분기 + Godot 실행 파일·템플릿·로그인 사전 점검, 릴레이 기본값을 공용 `wss://relay.jachana.com`으로(웹 localhost 페이지만 로컬 릴레이), README를 심사위원용 "바로 플레이/클론 실행/배포" 안내로 재작성 | .gitignore·export_presets.cfg·server/game-worker·scripts/deploy_web.sh·src/net/net.gd·README.md·CLAUDE.md | 친구(b-hy\*)·심사위원이 클론 후 "배포해줘" 한마디로 임시배포·플레이까지 되게 — 수동 단계(프리셋 전달·routes 삭제·`?relay=` 부착) 제거 |
| 2026-07-22 | 전체 구조 리뷰 반영을 하네스에 고정 — projectb-rules §3에 히트 기하 하드 계약(attack_center_offset·attack_radius — 판정과 FX가 같은 함수) 추가, §2에 "예정된 리팩터 게이트" 신설(잔몹 착수 전 enemy HP·피격 컴포넌트 분리 · 두 번째 씬 착수 전 스테이지 동기화/전투 확정 공용화 · 권한·동기화 로직 복사 금지 원칙). 코드 반영은 e2825e4(재접속 스폰 화면 밖 이탈 수정 + 기하 단일 소스화 + 비트마스크 상수화) | projectb-rules §2·§3 · CLAUDE.md | 리뷰가 찾은 "다음 작업에서 갈라질 이음새"를 일회성 지적으로 흘리지 않고 규칙으로 고정 — 이후 모든 위임·리뷰가 착수 전 게이트로 보게 (사용자 요청: 하네스에서 항상 신경) |
| 2026-07-22 | 직업 선택 + 캐릭터 스프라이트 3종 — 로비 직업 선택 UI(3버튼·기본 전사, 초대 링크 자동 시작은 직업 클릭 후로 연기), 사용자 제공 aseprite 3종(warrior/archer/mage_16, 버전 접미사 제거) 임베드, GameState 오토로드 신설(선택 보관 + data/jobs 스캔 allowlist 리졸버 — 모르는/조작 id는 기본 직업 폴백), JobDef에 id·sprite, G_JOB 직업 공지(스테이지 입장 + 피어 합류 + 상대 첫 G_POS 시 재공지). 리뷰 Important 3 반영: 공지 유실 경합(첫 G_POS 재공지)·판 도중 직업 변경 차단(피어별 첫 공지 잠금)·직업 목록 하드코딩 제거(폴더 스캔). 테스트 추가: test_game_state_auto(리졸버 신뢰 경계, 뮤테이션 검출 확인) | src/core(game_state·job_def·net_schema)·src/player·src/stage·src/ui/lobby·data/jobs·assets(sprites/player·aseprite)·tests·project.godot · projectb-verify §1 · CLAUDE.md | 직업 선택→그 캐릭터로 플레이 (온보딩 첫 단계, GDD §7). 직업이 호스트 검증(사거리·쿨다운) 기준이라 네트워크 공지·잠금·allowlist 필수 |
| 2026-07-22 | 마을 씬 + 씬 전환 골격 — 리팩터 게이트(두 번째 씬) 통과: 피어/직업 동기화를 `src/net/peer_sync.gd`, 전투 확정을 `src/stage/combat_authority.gd`, 방코드/초대 HUD를 `src/hud/stage_hud`로 추출(마을·스테이지가 자식 노드로 공유). G_POS에 씬 id 부착 + 원격 스폰을 "첫 G_POS(같은 씬 증명)"로 일원화(다른 씬 피어 유령 스폰 방지), G_SCENE(호스트 → 전원 씬 전환 지시, HOST_ID 발신만 신뢰 + 씬 id allowlist) 신설. 흐름 = 로비 → 마을(잔디 타일·돌 아치 게이트, interact 레이어 7) → 호스트가 게이트 앞에서 **F(`interact` 액션, 키 변경 용이)** 로 출발 확인 시 전원 스테이지 돌입(게이트 안 안내: 호스트 "F — 출발"·게스트 "방장이 출발"). HUD 초대 버튼은 URL이 아니라 **방 코드 복사**(사용자 확정 — 환경 따라 URL이 안 통해 코드 입력 흐름이 확실). 함정 등록: 자식 컴포넌트 `_ready`에서 부모 add_child는 busy로 조용히 실패 → `call_deferred`(웹 실기에서 발견·수정). 검증: 헤드리스 3종 TEST_OK + 마을 실기(사용자, 밟으면-출발 판) — F 상호작용판 실기는 인계 | src/net/peer_sync.gd·src/stage(combat_authority·test_stage)·src/hud·src/village·src/main·src/core(net_schema·event_bus)·src/player·project.godot(interact)·assets/sprites/village·tests 무변경 · projectb-rules §2·§5 | GDD §3 마을 거점 착수 — 두 번째 씬이 생기기 전에 권한·동기화 공용화(게이트), 이후 챕터 스테이지도 같은 컴포넌트를 문다 |
| 2026-07-22 | jachana.com 고정 배포 + 실기 진단 계측 + 사거리 검증 좌표 수정 — Cloudflare named tunnel `projectb`(기존 ideaforge와 별개, quick tunnel이 기본 config에 가로채이는 함정 해결)로 `game/relay.jachana.com` 고정 주소, 로비가 `game.*` 호스트에서 릴레이 기본값 자동 설정, `?relay=` 초대 링크 파라미터, `scripts/start_multi.bat` 일괄 시작. 계측: 릴레이 비-pos 이벤트 로그, 브리지 pb_dump + InputEventAction 주입. **수정: 호스트 사거리 검증이 보간 표시 좌표를 써서 랙 시 정당한 적중을 거부 → net_anchor()(클램프된 최신 수신 좌표)로 변경.** 도메인 경유 전 구간 실기 검증: 참가→이동 동기화→게스트 공격→호스트 검증·확정(30→20)→게스트 반영 | server/relay·src/core/debug_bridge·src/player·src/stage·src/ui/lobby·scripts · projectb-rules §2·§5 · CLAUDE.md | 원격 친구와 바로 플레이 가능한 고정 주소 확보 + 랙 환경 오탐 제거 |
