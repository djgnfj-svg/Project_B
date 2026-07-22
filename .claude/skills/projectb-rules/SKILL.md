---
name: projectb-rules
description: Project_B(2D Godot) 프로젝트의 아키텍처 규칙·모듈 지도·하드 계약. Project_B 코드를 쓰거나·읽거나·리뷰하거나·서브에이전트에 위임하기 전에 반드시 이 스킬을 읽어라. typed GDScript 강제·class_name 금지(에이전트)·모듈 간은 EventBus+core 스키마만·수치는 데이터 리소스(.tres)·물리 레이어 배정표·씬 연결 규칙을 담는다. §1~§5는 GDD 기준으로 채워져 있다 — 구조가 바뀌면 여기를 같이 갱신한다.
---

# Project_B 아키텍처 규칙

Project_B = 2D **웹 게임**, Godot 4.7.1, **Web(HTML5/WASM) 익스포트 타깃**, 렌더러 Compatibility(웹 필수). 게임이 무엇인지는 `docs/GDD.md`가 정본 — **2인 협동 보스전 액션** (마을 제작/강화 + 챕터 사냥, WebSocket 중계 멀티, 전사부터 완성).

> 🔴 **웹 게임 = 네트워크가 코어다. 네트워크 리뷰는 항상 필요하다.** 네트워크에 닿는 코드(연결·RPC·상태 동기화·권한·재접속)는 예외 없이 `projectb-reviewer`의 네트워크 점검을 거친다. 브라우저는 ENet(UDP)을 못 쓴다 — 전송은 **WebSocket**(또는 WebRTC)이어야 한다. 서버 권한(authority) 모델·신뢰 경계·입력 검증을 매번 확인한다. 관련 스킬: `multiplayer-basics`(WebSocket 피어·RPC·권한)·`multiplayer-sync`(동기화·예측·지연 보상). ⚠ 이 이유로 멀티플레이어 스킬은 절대 "무관"으로 지우지 않는다. §0은 보편 규율, §1~§5는 Project_B 실제 값이다 — 오토로드·모듈·계약·레이어가 새로 생기면 그때그때 여기 추가한다.

**정본은 항상 `CLAUDE.md` 최상단이다.** 이 스킬과 충돌하면 CLAUDE.md가 이긴다. 새 하드 계약·모듈·단일 소스 함수가 생기면 여기 §3~§5에 기록해라 — 기록하지 않은 계약은 곧 복사되고 갈라진다.

## 0. 절대 규칙 (어기면 조용히 깨진다 — 보편 규율)

- **typed GDScript 강제.** 모든 변수·인자·반환에 타입.
- **서브에이전트 새 스크립트에 `class_name` 선언 금지** → `const X := preload(...)`. 전역 클래스 캐시는 리드의 `--import` 때만 갱신되므로, 서브에이전트가 만든 class_name은 다른 스크립트에서 "Identifier not found"로 조용히 깨진다. (리드는 core에서 class_name을 쓸 수 있다.)
- **모듈 간 통신은 EventBus 시그널 + core 스키마만.** 타 모듈을 직접 preload/get_node 하지 마라. (정당한 예외 = 조합 루트: 진입/부모 씬이 자식 씬을 무는 것.)
- **수치는 데이터 리소스(.tres/커스텀 Resource)로.** 코드에 밸런스 상수를 박지 마라. ⚠ 예외 = **연출값(손맛: 넉백·히트스톱·팝·페이드 등)은 스크립트 const**다 — 사용자가 직접 조이는 값이라 밸런스가 아니다.
- 🔴 **비주얼은 스프라이트가 기본이다 — 도형으로 때우지 마라.** 게임 오브젝트(캐릭터·적·아이템·타일·투사체 등)의 겉모습은 `Sprite2D`/`AnimatedSprite2D`에 **텍스처**를 물려 만든다. `ColorRect`·`draw_rect`·원시 도형으로 대충 그리지 마라 — 임시 플레이스홀더조차 스프라이트(단색 PNG라도)로 만들어라. 이유: 나중에 진짜 아트로 **이미지만 교체**하면 끝나기 때문. 도형으로 짜두면 아트가 나올 때 노드 구조·배선을 다 뜯어고쳐야 한다. (예외: HUD/UI의 배경·구분선 같은 순수 UI 요소, 디버그 기즈모.)
- **git 커밋은 리드(메인 세션)만.** 서브에이전트는 자기 모듈 폴더 + `tests/` 자기 접두사 파일만 수정.
- 서브에이전트는 `mcp__godot__*` 도구 사용 금지 (에디터는 리드가 관리).
- 스키마·시그널 추가가 필요하면 서브에이전트는 **보고만** 하고 리드가 core에 반영한다.

## 1. 오토로드 (전역 상태) — 확정

| 오토로드 | 파일 | 역할 |
|---|---|---|
| `EventBus` | `src/core/event_bus.gd` | 시그널 허브 — 모듈 간 유일 통신로 |
| `Net` | `src/net/net.gd` | WebSocket 중계 서버 연결·방 코드·피어 목록·`is_host()`. 연결 생명주기(끊김 감지 포함)의 단일 소스 |
| `GameState` | `src/core/game_state.gd` | 런타임 진행 상태 — 직업 선택·장비/인벤토리/재료·챕터 해금·현재 파티 |
| `Db` | `src/core/db.gd` | `data/` 리소스 레지스트리, id→Resource 리졸버 |
| `SaveManager` | `src/core/save_manager.gd` | 브라우저 로컬 저장(`user://`). 저장 시점 = 스테이지 클리어마다 (GDD §3) |
| `Audio` | `src/core/audio.gd` | EventBus 구독 → SFX/BGM 재생. ⚠ 웹 autoplay 함정 → §5 |

🔴 **네트워크 권한 모델 = 호스트 권한 (확정).** 중계 서버는 메시지 릴레이만 한다. 게임 로직의 단일 권한은 **방장(호스트) 클라이언트** — 적 AI·데미지 확정·드랍 생성·스테이지 전환·부활 판정은 호스트만 결정하고 결과를 브로드캐스트한다. 게스트는 자기 입력/이동을 보내고 결과를 받는다. (연출 예측은 게스트 로컬 허용, **상태 확정은 금지** — §3)

⚠ EventBus 시그널은 수신자만 있고 발신자를 나중에 붙이는 경우가 많다 — **필드를 붙이는 쪽이 emit해야** 하며 안 그러면 에러 없이 조용히 안 돈다.

## 2. 모듈 지도 — 확정 (폴더·씬이 생기는 대로 이 표와 동기화)

| 모듈 | 책임 |
|---|---|
| `src/main` | 부팅·씬 전환 조합 루트 (타이틀 → 직업 선택/로비 → 마을 → 챕터). 멀티에선 씬 전환을 호스트가 지시 |
| `src/core` | 스키마(커스텀 Resource 클래스)·단일 소스 함수(§3)·오토로드 — **리드 전용** |
| `src/net` | WebSocket 클라이언트·로비/방 코드·동기화 헬퍼 (`Net` 오토로드 본체) |
| `src/player` | 플레이어 캐릭터 (공용 배우) — WASD 이동·마우스 조준·구르기·직업별 공격/스킬 (전사 우선) |
| `src/enemies` | 잔몹·엘리트·보스 — AI·패턴. 개체 정의는 데이터 주도 (§4) |
| `src/combat` | 히트박스/허트박스 컴포넌트·투사체·예고 장판 — 플레이어/적 공용 |
| `src/stage` | 챕터/스테이지 진행·스폰·클리어 판정·모닥불·드랍·데스/부활(관전→HP1 부활)·전멸 처리 |
| `src/village` | 마을 씬 — 제작·강화·창고 상호작용, 챕터 출발 |
| `src/hud` | 인게임 HUD — HP·파티 상태·알림 |
| `src/ui` | 메뉴·모달 — 직업 선택·로비(방 코드)·제작/강화/창고 패널 |

- 규칙: 한 모듈 = 한 폴더 = 한 책임. 모듈 간은 §0의 EventBus 규칙만으로 통신. 조합 루트(`src/main`, 스테이지/마을 씬)가 자식 씬을 무는 것은 예외.
- 에셋은 `assets/sprites/<모듈>/…`·`assets/audio/…`, 데이터는 `data/` (§4), 테스트는 `tests/`.
- **`server/relay`** (src 밖) — WebSocket 중계 서버, **로컬 개발·테스트용 준거 구현**(헤드리스 GDScript). **게임 로직 금지** — 방 코드 스코프의 릴레이만. 스키마는 core `net_schema.gd`를 preload (§3). 실행: `-s res://server/relay/relay_server.gd -- --port=9080`.
- **`server/relay-worker`** — 중계 서버 **실배포본** (Cloudflare Workers + Durable Object 단일 허브, 무료 티어). relay.gd와 1:1 동작 + 배포 필수 3종(연결 64·방 24·메시지 2KB 상한, 60초 스윕·3분 무수신 좀비 정리) 구현. ⚠ **스키마 상수는 `net_schema.gd`의 JS 미러** — 스키마를 바꾸면 두 파일을 같이 고친다(§3). 배포: `cd server/relay-worker && npx wrangler deploy`. 로컬: `npx wrangler dev --port 9082` (⚠ Godot 클라는 `ws://127.0.0.1:9082` — `localhost`는 IPv6로 풀려 wrangler에 안 닿는다). 프로토콜 검증 = `tests/test_net_room_auto.gd`에 `url=` 인자로 겨눈다.
- **`server/game-worker`** — 웹 빌드 정적 서빙 Worker. ⚠ 에셋 파일당 25MiB 제한 → `index.wasm`(37MB)은 gzip 사전압축(`index.wasm.gz`)으로 올리고 Worker가 `Content-Encoding: gzip`(+`encodeBody: "manual"`)으로 서빙. **웹 배포 정본 = `bash scripts/deploy_web.sh`** (익스포트→스테이징→deploy 일괄).
- **배포(탈PC, 2026-07-22):** 로컬 프로세스 0개. `https://game.jachana.com` = game-worker, `wss://relay.jachana.com` = relay-worker (커스텀 도메인). 페이지 호스트가 `game.*`이면 로비가 릴레이 기본값을 `wss://relay.*`로 자동 설정(`Net.default_relay_url()`). workers.dev 직접 주소는 스테이징용 — 이때 릴레이는 `?relay=` 파라미터로 지정. (구 방식: PC에서 `scripts/start_multi.bat` + cloudflared 터널 — 로컬 개발 폴백으로만 유지, quick tunnel은 기본 config.yml에 가로채이니 `--config` 지정.)

**예정된 리팩터 게이트 (착수 전 선행 조건 — 어기면 호스트 권한 경로가 복붙으로 갈라진다):**
- 원칙: **권한·동기화 로직은 복사 금지 — 두 번째 사용처가 생기기 전에 공용화한다.** 게이트를 통과(분리 완료)하면 해당 줄을 지운다. 새 이음새가 리뷰에서 발견되면 여기 추가한다.
- **적 동적 스폰(웨이브 등) 착수 전:** CombatAuthority·MobSync의 적 등록이 `_ready` 일회 스캔이라 씬 배치 전제다 — 런타임 스폰 적은 미등록으로 게스트 hit_req가 **에러 없이** 무시된다. 등록 시그널 또는 지연 재스캔 구조로 바꾼 뒤 착수한다 (2026-07-22 리뷰).
- **두 번째 무기 모션(찌르기·발사 등 비-스윙) 착수 전:** 공격 모션(3박자 호 스윙)과 궤적 FX(swoosh_arc)가 `player.gd`에 대검 전용으로 하드코딩돼 있다 — 모션 타입(swing/thrust/shoot)·FX 텍스처를 무기 데이터로 빼고 나서 착수한다. 스윙형 무기 추가는 게이트 없이 가능(텍스처+그립+range면 끝, §4) (2026-07-22 무기 분리 작업에서 등록).
- **스테이지 중 재합류(현재 GDD 비범위) 도입 전:** 합류 피어용 상태 스냅샷(ehp·php 일괄 재송신)을 먼저 만든다 — 없으면 놓친 사망 브로드캐스트가 게스트 화면에 멈춘 좀비 잔몹으로 영구 잔류한다 (2026-07-22 리뷰).
- (통과: 두 번째 씬 게이트 2026-07-22 — 피어/직업 동기화 = `src/net/peer_sync.gd`, 전투 확정 = `src/stage/combat_authority.gd`, 공용 HUD = `src/hud/stage_hud.tscn`. 마을·스테이지는 이 컴포넌트를 자식 노드로 문다 — 새 씬도 같은 방식, 복사 금지.)
- (통과: 잔몹 게이트 2026-07-22 — HP·피격·부활 = `src/combat/health_component.gd`(바디 타입 무관 자식 노드 `Health`, 권한 경로 `apply_damage/confirm_hp`와 표시 경로 `set_hp_display` 분리). 허수아비·잔몹·플레이어가 같은 컴포넌트를 문다. 씬 전환 송수신 = `src/net/scene_flow.gd`(G_SCENE 검증 공용 — village 용접분 추출), 잔몹 표시 동기화 = `src/stage/mob_sync.gd`(mpos 10Hz 배치·matk 중계 — 판정 없음). 새 적/새 씬도 같은 컴포넌트를 문다, 복사 금지.)

**챕터1 진행 골격 (2026-07-22) — 새 스테이지/챕터는 이 조합을 문다, 복사 금지:**
- 칸 목록 = `data/chapters/*.tres`(ChapterDef — 씬 경로 순서, 모닥불 칸 포함, 마지막 = 보스). 진행 결정 = `src/stage/chapter_flow.gd`(호스트 전용: stage_cleared→다음 칸, 마지막 클리어/전멸→마을). 전투 스테이지 루트 = `src/stage/stage.gd`(PeerSync 토큰만 갱신) + PeerSync·CombatAuthority·MobSync·SceneFlow·ChapterFlow·HUD 조합. 모닥불 = `src/stage/campfire.tscn`(앉기 회복 = 호스트 confirm_hp, G_SIT은 힌트 — 거리 재검증).
- **칸 토큰 = `GameState.stage_token()`("stage:챕터:인덱스")** — 같은 tscn(모닥불)이 여러 칸에 재사용돼도 칸마다 토큰이 달라 G_POS 유령 스폰이 안 생긴다. 새 씬은 루트 _ready에서 PeerSync.scene_id에 이 토큰을 넣는다.
- **HP는 챕터 내 스테이지 간 이월된다** — 기록 = `GameState.record_party_hp`(player.gd 확정 경로 2곳만), 스폰 재확정 = 호스트(CombatAuthority의 player_spawned 핸들러), 리셋 = `GameState.leave_chapter()`(마을/로비 진입, main). 직업 재공지는 `Health.set_max_hp`(setup 아님)라 이월 HP를 안 지운다.

## 3. 하드 계약 (단일 소스 — 복사하면 갈라진다)

같은 계산을 두 곳에서 하면(예: UI 표시와 실제 게임플레이가 위력을 각자 계산) 한쪽만 고쳤을 때 아무도 모르게 갈라진다. 아직 코드가 없으므로 아래는 **예약된 계약**이다 — 해당 로직을 처음 구현할 때 반드시 이 위치에 만들고, 다른 곳은 전부 이 함수를 부른다.

- 🔴 **최종 데미지 = `src/core/combat_math.gd`의 `calc_damage()`.** 실제 전투 판정(호스트)과 UI 표시(장비 스펙·강화 미리보기)가 같은 함수를 부른다.
- 🔴 **장비 스탯 합산 = `src/core/combat_math.gd`의 `total_stats()`.** 착용 장비 → 총 스탯. HUD·전투·제작/강화 패널 공용.
- 🔴 **강화 결과 수치 = `src/core/combat_math.gd`의 `upgraded_stats()`.** 강화 UI의 "다음 단계 미리보기"와 실제 적용이 같은 함수.
- 🔴 **인원 스케일링(솔로 시 보스 약화) = `src/core/combat_math.gd`의 `party_scale()`.** 수치·범위는 GDD §11 TBD — 함수 위치만 먼저 고정.
- 🔴 **히트 기하(공격 중심·반경) = `src/core/combat_math.gd`의 `attack_center_offset()`·`attack_radius()`.** 실제 판정(원형 질의)과 공격 궤적 FX 크기(스워시 스케일 = 판정 도달/텍스처 반경)가 같은 함수에서 파생된다 — 한쪽만 조이면 "맞는 곳"과 "보이는 곳"이 어긋난다. 손맛 튜닝은 반드시 이 상수(ATTACK_CENTER_SCALE·ATTACK_RADIUS_SCALE)와 `data/jobs/*.tres`의 attack_range로.
- 🔴 **구르기 타이밍 = `src/core/combat_math.gd`의 `ROLL_TIME_S`·`ROLL_COOLDOWN_S`·`is_roll_grant_ok()`·`is_iframe_active()`.** 로컬 구르기 이동(player)과 호스트 i-frame 검증(G_ROLL 그랜트)이 같은 상수를 읽는다 — player.gd에 사본을 만들면 첫 손맛 튜닝에서 무적 창과 이동이 갈라진다. (i-frame 있음 = 사용자 확정 2026-07-22) ⚠ **애니 미러**: `assets/sprites/player/*_frames.tres`의 roll 애니(4프레임/speed 16 = 0.25s)가 이 값과 암묵으로 맞물린다 — ROLL_TIME_S를 바꾸면 3개 .tres의 roll speed도 같이 조정 (loop=false라 애니가 창보다 짧으면 마지막 프레임에 얼어붙는다).
- 🔴 **공격 스윙 창 미러 = `src/player/player.gd`의 `ATTACK_ANIM_TIME`(0.25) < 모든 `data/jobs/*.tres`의 `attack_cooldown`.** (2026-07-22 리뷰 등록) 어떤 직업이든 attack_cooldown이 0.25 밑으로 내려가면 원격 스윙 창-잠금 가드(`play_attack_fx`)가 정당한 연속 공격의 스윙 연출을 무시해 로컬-원격 화면이 갈라진다. attack_cooldown을 조일 땐 이 상수와 같이 본다. ⚠ 무기는 몸에 굽지 않는다 — **몸(AnimatedSprite2D)과 분리된 독립 Sprite2D**(`WeaponPivot/Weapon`, 텍스처 = `JobDef.weapon_texture`)가 조준각으로 회전 + 스윙 창 동안 호를 그린다(전부 표시 전용). 장비 교체 = 텍스처 교체가 되도록 유지하고, 장비 시스템 도입 시 weapon_texture/weapon_grip은 EquipDef로 이관한다. 원격 조준각 = G_POS "a"(표시 전용, 판정은 여전히 net_anchor+호스트 검증).
- 🔴 **잔몹 타격 기하 = `EnemyDef.strike_radius` + `combat_math.gd`의 `is_strike_hit()`.** 호스트 판정과 텔레그래프 표시(스프라이트 스케일)가 같은 반경을 읽는다 — "맞는 곳=보이는 곳". 판정 좌표는 net_anchor(§3 위치 원칙).
- 🔴 **네트워크 메시지 스키마 = `src/core/net_schema.gd`.** 메시지 타입 상수·페이로드 구조는 여기 한 곳. 호스트/게스트가 각자 문자열 리터럴로 메시지를 만들면 갈라진다.
- 🔴 **씬 전환 좌표 검증 = `GameState.is_valid_stage()`.** 호스트 송신 전(scene_flow.request_stage)과 게스트 G_SCENE 수신이 같은 함수를 지난다 — 챕터 id는 data/chapters 스캔 allowlist, 인덱스는 ChapterDef 범위. **스테이지 씬 경로는 절대 네트워크로 받지 않는다** — 로컬 .tres에서만 리졸브 (임의 load 경로 조작 차단).
- 🔴 **상태 확정 권한 = 호스트 (§1).** 데미지 적용·드랍 생성·클리어/전멸 판정·스테이지 전환·부활은 호스트 코드 경로에서만 확정한다. 게스트 로컬에서 상태를 "일단 적용"하는 코드 금지 (히트 이펙트 등 연출 예측은 허용). ⚠ 위치는 각자 소유(스파이크 확정)지만, **데미지/판정을 도입하는 시점부터 호스트는 게스트가 보낸 입력의 범위(이동 거리·공격 사거리·쿨다운)를 검증해야 한다** — 무검증 신뢰는 스파이크까지만.

## 4. "새 X = 파일 한 장" (데이터 주도)

새 콘텐츠가 "코드 수정 없이 .tres 한 장"으로 떨어지도록 설계한다. 스키마(각 .tres의 커스텀 Resource 클래스)는 `src/core/`에 두고 리드가 관리한다.

- 새 적/엘리트/보스 = `data/enemies/*.tres` (스탯·스프라이트·드랍 테이블·패턴 파라미터)
- 새 장비 = `data/equipment/*.tres` (부위·기본 수치·강화 곡선) — 장비는 수치만 (GDD §6 확정)
- 새 무기 비주얼 = `assets/sprites/weapons/<id>.png`(+aseprite 소스) + 값 2개(`weapon_texture`·`weapon_grip` — 현 JobDef, 장비 도입 시 EquipDef 이관) + `attack_range` 시각 정합(§3). 텍스처 규격 = 우향(+x) 수평·그립 픽셀 명시(projectb-art 참조). 조준 회전·플립·상하 가림·구르기/사망 숨김·원격 조준각·스팸 가드는 **player.gd 공용 경로가 자동 처리** — 무기별로 다시 만들지 마라
- 새 재료 = `data/materials/*.tres`
- 새 제작 레시피 = `data/recipes/*.tres` (재료 목록 → 결과 장비)
- 새 직업 = `data/jobs/*.tres` (기본 스탯·스킬 구성) — 궁수/법사 스트레치가 파일 추가로 떨어지게
- 새 챕터 = `data/chapters/*.tres` (ChapterDef — 칸 목록 = 스테이지 씬 경로 순서, 모닥불 칸은 `campfire.tscn`을 끼워 넣기, **파일명이 campfire로 시작하면 휴식 칸**(is_rest 관례), 마지막 칸 = 보스) — 챕터2 스트레치가 파일 한 장이 되게
- 모닥불 수치 = `data/campfire/*.tres` (CampfireDef — 회복량·간격·앉기 반경. 값은 GDD §11 TBD, 사용자가 조인다)
- 새 소리 = `assets/audio/sfx/<id>.wav` (파일명 = id 관례)

## 5. 조용히 깨지는 함정 (에러 없이) — 보편 + 프로젝트 고유

아래는 2D Godot에서 에러 없이 조용히 깨지는 보편 함정이다. Project_B 고유 함정이 발견되면 여기 추가해라.

- 🔴 **물리 레이어/마스크 불일치**: 발사체·피격 판정은 레이어/마스크가 정확히 맞아야 `take_hit`/충돌 콜백이 불린다. 틀리면 에러 없이 아무 일도 안 일어난다. **배정표(아래)가 단일 소스다** — 코드·씬의 값이 표와 다르면 그게 버그다.

  | # | 이름 | 쓰임 | mask |
  |---|---|---|---|
  | 1 | `world` | 벽·지형 (StaticBody2D/TileMap) | — |
  | 2 | `player_body` | 플레이어 몸 (CharacterBody2D) | 1 |
  | 3 | `enemy_body` | 적 몸 | 1 |
  | 4 | `player_attack` | 플레이어 공격/투사체 히트박스 (Area2D) | 3 |
  | 5 | `enemy_attack` | 적 공격/예고 장판 히트박스 (Area2D) | 2 |
  | 6 | `pickup` | 드랍 아이템 (Area2D) | 2 |
  | 7 | `interact` | 상호작용 영역 — 모닥불·제작대·출구 (Area2D) | 2 |

  원칙: 공격 판정 = Area2D 히트박스가 **상대 몸 레이어를 mask**. 몸끼리(2↔3)는 충돌하지 않는다(탑다운 겹침 허용 — 밀림이 필요해지면 그때 추가하고 표를 갱신).
- 🔴 **화면 덮는 Control의 `mouse_filter`**: 기본값 STOP이 그 아래 클릭을 다 먹는다 → 배경/장식 오버레이는 `mouse_filter = 2`(IGNORE). **헤드리스가 절대 못 잡는다** → `projectb-verify` 참조.
- 🔴 **씬끼리 PackedScene 순환 preload 금지**: A⇄B 순환 preload는 껍데기 노드를 만들어 전환이 깨진다. `@export_file` 경로 + `change_scene_to_file`을 써라. 헤드리스는 못 잡고 실게임 부팅에서만 드러난다.
- 🔴 **저장 초기화 착각**: 세이브 파일만 지우고 오토로드(GameState 등) 메모리를 안 지우면, 옛 상태가 메모리에 남아 다음 저장에 도로 써진다. "새로하기"는 파일 삭제가 아니라 오토로드 상태 리셋까지 해야 한다.
- 🔴 **씬 스왑 프레임엔 이전 씬 노드가 그룹에 남아 있다**: main의 `queue_free`는 프레임 끝에 실행되므로, 새 씬의 첫 프레임 그룹 스캔("player" 등)에 이전 씬 노드(게이트 앞 좌표)가 걸린다. 잔몹 AI가 이 유령에 어그로를 물고 영구 추격했다(챕터1 실기에서 발견 — 간헐 레이스, CHASE 리시 `LEASH_MULT`로 수정). 그룹 스캔 기반 AI/시스템은 첫 프레임 결과를 못 믿는다 — 리시·거리 재확인·지연 스캔 중 하나를 넣어라.
- 🔴 **배경 타일 스프라이트는 `z_index = -10`**: 잔몹 텔레그래프가 z=-1이라 바닥을 z 0으로 깔면 텔레그래프가 **조용히** 가려진다 (test_stage엔 바닥이 없어서 안 드러났던 함정 — 챕터1 스테이지에서 발견). 무기(z 0 이상 유지)와 함께 z 배치: 바닥 -10 < 텔레그래프 -1 < 몸/무기 0+.
- 🔴 **자식 컴포넌트의 `_ready`에서 `get_parent().add_child()` 금지**: 그 시점 부모는 아직 자식 셋업 중이라 "Parent node is busy setting up children"으로 실패한다 — 웹 실기에선 에러가 콘솔에 묻혀 "노드가 조용히 없음"으로만 보인다(마을 스폰에서 실제 발생). 스폰류 초기화는 `call_deferred`로 한 프레임 미뤄라 (`peer_sync.gd _initial_spawn` 패턴). 씬 루트 스크립트의 `_ready`에서 자기 자신에게 add_child는 안전하다.

**Project_B 고유 (웹·멀티):**

- 🔴 **`-s` 헤드리스에선 오토로드 전역 식별자가 컴파일되지 않는다**: `-s` 테스트가 (직간접) preload하는 스크립트가 `EventBus`/`Net` 같은 전역 이름을 쓰면 "Identifier not found"로 통째로 컴파일 실패한다. **헤드리스로 테스트할 로직(core·net)은 `/root` 경로 + class_name 타입으로 접근해라** (예: net.gd의 `_bus()` 헬퍼 → `EventBusHub`). 실게임 전용 씬 스크립트(player/stage/ui/main)는 전역 이름을 그대로 써도 된다.

- 🔴 **웹 오디오 autoplay**: 첫 사용자 입력 전에는 소리가 안 난다(브라우저 정책) — 에러 없이 무음. 온보딩 첫 입력 이후에 BGM 시작.
- 🔴 **웹에서 스레드 금지**: `Thread`/`WorkerThreadPool`은 기본 웹 익스포트에서 안 돈다(COOP/COEP 헤더 필요). 에디터·데스크톱에선 돌아서 **웹 빌드에서만** 깨진다 — 애초에 쓰지 마라.
- 🔴 **저장 검증은 브라우저에서**: `user://`는 웹에서 IndexedDB다. 에디터에서 저장이 돌아도 웹 빌드에서 새로고침 후 남는지 따로 확인해야 한다.
- 🔴 **호스트/게스트 씬 트리 불일치**: RPC·동기화는 양쪽에 같은 경로의 노드가 있어야 도착한다. 스폰 순서가 어긋나면 조용히 유실 — **스폰은 호스트가 지시하고 게스트가 따라 만든다** (게스트 단독 스폰 금지).
- 🔴 **크롬은 백그라운드/가려진 탭을 프리즈한다**: 호스트 탭이 백그라운드로 가면 게임 루프·소켓 플러시까지 통째로 멈춰 **방 전체가 정지**하고, 깨어날 때 큐가 한꺼번에 처리된다(브라우저 실기 검증에서 확인). 실플레이(각자 기기·포커스 탭)에선 안 드러나지만, 한 PC 두 탭 테스트·호스트의 잠깐 탭 전환에서 드러난다. 대응 후보(미결): 호스트 이탈 감지 안내, 오디오 keepalive. 같은 PC 테스트 시엔 탭을 번갈아 활성화해 큐를 밀어줘야 한다. ⚠ 원격 릴레이(Workers)는 **3분 무수신 시 좀비로 간주해 연결을 끊는다** — 프리즈된 호스트 탭은 3분 뒤 방 종료로 정리된다 (실기 디버깅 때 "3분 뒤 로비로 튕김"은 이 정상 동작).
- **웹 실기 자동 검증 = 디버그 브리지**: 브라우저 자동화는 합성 키를 Godot에 못 꽂는다(신뢰 이벤트만 수신, 홀드 불가). `?debug=1`일 때만 열린다(`src/core/debug_bridge.gd`): `window.pb_press/pb_release(액션)`(InputEventAction — _unhandled_input·폴링 둘 다 구동) · `window.pb_dump()`(방·플레이어 좌표·적 HP를 console에 `[PB]` JSON으로). 로컬 입력 시뮬레이션/관측일 뿐 신뢰 경계(§3)는 그대로. ⚠ 같은 프레임에 press+release가 붙으면 액션이 소실될 수 있다 — 자동화에선 press만 보내고 다음 프레임 이후 release. ⚠ 가려진(occluded) 창은 활성 탭도 rAF가 멈춘다 — 캡처(스크린샷/줌)가 프레임을 1개씩 강제로 굴리므로, 프리즈 상태에선 "입력 → 캡처(프레임) → 검증" 순으로 진행.

## 6. 위임 라우팅 (리드용)

- **기획 정본 = `docs/GDD.md`** (게임이 무엇인가). 기획 = `projectb-planner`, 🔒 GDD 수정은 사용자 승인제. 새 시스템은 GDD에서 정해진 뒤 architect로 내려간다.
- 구현 위임 = `projectb-dev` · 설계/계획 = `projectb-architect` · 리뷰 = `projectb-reviewer`.
- 아트 = `projectb-art` · UI = `projectb-ui` · 애니 = `projectb-animator` · 셰이더 = `projectb-shader` · 성능 = `projectb-profiler` · 에디터 툴 = `projectb-tools`.
- **언제 직접 하나**: 회귀 위험이 크고 tight한 검증 루프가 필요한 작업, core 스키마 변경, `mcp__godot` 필요 작업, 커밋.
- 위임해도 검증·`--import`·커밋은 리드가 직접(→ `projectb-verify`).
