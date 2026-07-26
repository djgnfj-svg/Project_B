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
| `Net` | `src/net/net.gd` | 방 코드·피어 목록·`is_host()`·연결 생명주기의 단일 소스. **전송이 둘이다(2026-07-26): WebRTC P2P 직결(웹) + WebSocket 릴레이(시그널링·폴백).** 경로 선택은 `send_game` **한 곳**에서 끝나고 수신은 경로 무관하게 `EventBus.net_msg`로 올라간다 — 그래서 P2P 도입이 게임 코드 무변경으로 떨어졌다. 공개 API에 `p2p_active()` 추가(HUD 경로 표시) |
| `GameState` | `src/core/game_state.gd` | 런타임 진행 상태 — 직업 선택·챕터 해금·현재 파티·HP 이월. **인벤(골드·재료·도면·장비) + 제작/강화 + job/chapter/material/equipment/recipe 리졸버(스캔 allowlist) + 저장 직렬화(to/from_save_dict).** 인벤은 각 클라 자기 것만(비네트워크) |
| `Db` | (미구현 — 예약) | ⚠ **아직 없다.** id→Resource 리졸버는 현재 `GameState`에 있다(전부 스캔 allowlist, `-s` 테스트 호환 위해 별도 오토로드 참조 회피). Db 통합은 후속 |
| `SaveManager` | `src/core/save_manager.gd` | 브라우저 로컬 저장(`user://save.json`). 저장 시점 = 스테이지 클리어마다 (GDD §3). `commit()`=디스크 기록·`reload()`=마지막 저장분 롤백(전멸 시 클리어분만 생존, GDD §11). 직렬화 = GameState.to/from_save_dict. ⚠ 웹 저장 실기 검증 필요(§5). EventBus·GameState는 /root로 접근(§5) |
| `Audio` | `src/core/audio.gd` | EventBus 구독 → SFX 재생(8채널) + 마스터 볼륨/뮤트(`user://settings.cfg` 저장). ⚠ 웹 autoplay 함정 → §5. BGM 붙일 때 첫 입력 이후 게이트 |
| `DamageNumbers` | `src/feel/damage_numbers.gd` | `combat_impact` 구독 → 피격 지점(월드 좌표)에 데미지 숫자 팝. Node2D 오토로드라 현재 Camera2D 캔버스 변환을 받아 전 씬 커버 (표시 전용) |

🔴 **네트워크 권한 모델 = 호스트 권한 (확정).** 중계 서버는 메시지 릴레이만 한다. 게임 로직의 단일 권한은 **방장(호스트) 클라이언트** — 적 AI·데미지 확정·드랍 생성·스테이지 전환·부활 판정은 호스트만 결정하고 결과를 브로드캐스트한다. 게스트는 자기 입력/이동을 보내고 결과를 받는다. (연출 예측은 게스트 로컬 허용, **상태 확정은 금지** — §3)

⚠ EventBus 시그널은 수신자만 있고 발신자를 나중에 붙이는 경우가 많다 — **필드를 붙이는 쪽이 emit해야** 하며 안 그러면 에러 없이 조용히 안 돈다.

## 2. 모듈 지도 — 확정 (폴더·씬이 생기는 대로 이 표와 동기화)

| 모듈 | 책임 |
|---|---|
| `src/main` | 부팅·씬 전환 조합 루트 (타이틀 → 직업 선택/로비 → 마을 → 챕터). 멀티에선 씬 전환을 호스트가 지시 |
| `src/core` | 스키마(커스텀 Resource 클래스)·단일 소스 함수(§3)·오토로드 — **리드 전용** |
| `src/net` | 전송 계층(WebRTC 직결 + WebSocket 릴레이)·로비/방 코드·동기화 헬퍼 (`Net` 오토로드 본체) |
| `src/player` | 플레이어 캐릭터 (공용 배우) — WASD 이동·마우스 조준·구르기·직업별 공격/스킬 (전사 우선) |
| `src/enemies` | 잔몹·엘리트·보스 — AI·패턴. 개체 정의는 데이터 주도 (§4) |
| `src/combat` | 히트박스/허트박스 컴포넌트·투사체·예고 장판 — 플레이어/적 공용 |
| `src/stage` | 챕터/스테이지 진행·스폰·클리어 판정·모닥불·드랍·데스/부활(관전→HP1 부활)·전멸 처리 |
| `src/village` | 마을 씬 — 제작·강화·창고 상호작용, 챕터 출발 |
| `src/hud` | 인게임 HUD — HP·파티 상태·알림 |
| `src/ui` | 메뉴·모달 — 직업 선택·로비(방 코드)·제작/강화/창고 패널·소리 설정 |
| `src/feel` | **손맛 연출 계층 (표시 전용)** — 히트스톱·히트플래시·데미지 숫자·플린치·카메라 셰이크. EventBus 훅 구독만, 판정·상태 확정 절대 없음 |

- 규칙: 한 모듈 = 한 폴더 = 한 책임. 모듈 간은 §0의 EventBus 규칙만으로 통신. 조합 루트(`src/main`, 스테이지/마을 씬)가 자식 씬을 무는 것은 예외.
- 에셋은 `assets/sprites/<모듈>/…`·`assets/audio/…`, 데이터는 `data/` (§4), 테스트는 `tests/`.

**손맛 계층 규약 (src/feel + Audio — 2026-07-23, 새 손맛/소리 연출은 이 훅에 매달아라. 복사·직접 참조 금지):**
- **모든 손맛/소리는 EventBus 훅에서 파생된다 — 판정 코드에 연출을 섞지 마라.** 훅: `combat_impact(kind, world_pos, amount)`(HP 감소 표시 경로 = `Health.hp_changed(dropped=true)`에서 피격 당사자 글루가 emit — **호스트/게스트 모두** 발화하므로 각 클라가 자기 화면 연출·소리를 재생), `screen_shake(strength)`, `player_swing`·`player_roll`·`entity_died(kind, pos)`, 드랍 손맛 `item_dropped`·`item_picked(kind, rarity, pos)`·`blueprint_unlocked(recipe_id)`(전부 호스트 확정 픽업 뒤 발화 → 각 클라 1회 재생, `DropFx` 오토로드·`drop_item`·`Audio`가 구독). 새 연출은 이 시그널을 **구독**한다.
- **표시 전용 = 네트워크 메시지 0개.** 손맛은 각 클라 로컬이라 net_schema·relay를 안 건드린다. i-frame 중엔 호스트가 데미지를 확정 안 해 hp가 안 떨어짐 → 훅이 안 와 거짓 연출 없음(자동).
- 🔴 **히트스톱에 `Engine.time_scale` 전역 정지 금지** (rules §5): 호스트가 멈추면 방 전체 정지. `hit_stop.gd`는 맞은 스프라이트의 `speed_scale`만 잠깐 0으로.
- 🔴 **히트 플래시(`hit_flash.gd`)는 번쩍이 끝나면 `sprite.material=null`로 셰이더를 뗀다** — 평상시 셰이더가 걸려 있으면 웹 Compatibility에서 amount=0이 항등이 아니라 "한 대 맞고 색이 안 돌아옴"이 된다(실기에서 발견·수정 2026-07-23).
- 연출값(셰이크 강도·히트스톱 프레임·플린치 넉백·볼륨 기본)은 **스크립트 const**(§0 예외 — 사용자가 조인다). SFX는 절차 생성 = `scripts/gen_sfx.py`(플레이스홀더, 재생성·튜닝 가능). 볼륨/뮤트는 Audio가 `user://settings.cfg`에 저장(세이브 파일과 별개).
- **`server/relay`** (src 밖) — WebSocket 중계 서버, **로컬 개발·테스트용 준거 구현**(헤드리스 GDScript). **게임 로직 금지** — 방 코드 스코프의 릴레이만. 스키마는 core `net_schema.gd`를 preload (§3). 실행: `-s res://server/relay/relay_server.gd -- --port=9080`.
- **`server/relay-worker`** — 중계 서버 **실배포본** (Cloudflare Workers + Durable Object 단일 허브, 무료 티어). relay.gd와 1:1 동작 + 배포 필수 3종(연결 64·방 24·메시지 2KB 상한, 60초 스윕·3분 무수신 좀비 정리) 구현. ⚠ **스키마 상수는 `net_schema.gd`의 JS 미러** — 스키마를 바꾸면 두 파일을 같이 고친다(§3). 배포: `cd server/relay-worker && npx wrangler deploy`. 로컬: `npx wrangler dev --port 9082` (⚠ Godot 클라는 `ws://127.0.0.1:9082` — `localhost`는 IPv6로 풀려 wrangler에 안 닿는다). 프로토콜 검증 = `tests/test_net_room_auto.gd`에 `url=` 인자로 겨눈다.
- **`server/game-worker`** — 웹 빌드 정적 서빙 Worker. ⚠ 에셋 파일당 25MiB 제한 → `index.wasm`(37MB)은 gzip 사전압축(`index.wasm.gz`)으로 올리고 Worker가 `Content-Encoding: gzip`(+`encodeBody: "manual"`)으로 서빙. **웹 배포 정본 = `bash scripts/deploy_web.sh`** (익스포트→스테이징→deploy 일괄).
- 🔴 **로컬 LAN 개발 서버 = `bash scripts/dev_local.sh`** (2026-07-24) — 릴레이(:9080) + 웹(:8910)을 한 명령으로 띄우고 LAN IP를 감지해 접속 주소를 찍는다. **같은 공간의 두 PC 테스트는 반드시 이걸 쓴다**: 공용 릴레이는 한국→홍콩→한국 왕복이라 RTT 140~215ms인데 로컬은 **13.8ms**(실측). 릴레이 주소는 클라가 자동 판별(`Net.default_relay_url` — 페이지 호스트가 localhost/사설 IP면 같은 호스트의 `LOCAL_RELAY_PORT`)이라 링크에 `?relay=`를 붙일 필요가 없다. `--fast`(익스포트 생략)·`--stop`(정리). ⚠ 호스트도 **LAN 주소**로 열어야 한다 — localhost로 열면 `invite_url()`이 페이지 origin 기반이라 초대 링크에 localhost가 박혀 상대가 못 쓴다. ⚠ Git Bash에선 Ctrl+C가 자식 Windows 프로세스까지 안 내려가는 경우가 있어 포트가 물린 채 남는다 → `--stop`이 그 탈출구(포트 기준 taskkill — `$!`는 MSYS PID라 taskkill에 못 넘긴다).
- **배포(탈PC, 2026-07-22):** 로컬 프로세스 0개. `https://game.jachana.com` = game-worker, `wss://relay.jachana.com` = relay-worker (커스텀 도메인). 페이지 호스트가 `game.*`이면 로비가 릴레이 기본값을 `wss://relay.*`로 자동 설정(`Net.default_relay_url()`). workers.dev 직접 주소는 스테이징용 — 이때 릴레이는 `?relay=` 파라미터로 지정. (구 방식: PC에서 `scripts/start_multi.bat` + cloudflared 터널 — 로컬 개발 폴백으로만 유지, quick tunnel은 기본 config.yml에 가로채이니 `--config` 지정.)

**예정된 리팩터 게이트 (착수 전 선행 조건 — 어기면 호스트 권한 경로가 복붙으로 갈라진다):**
- 원칙: **권한·동기화 로직은 복사 금지 — 두 번째 사용처가 생기기 전에 공용화한다.** 게이트를 통과(분리 완료)하면 해당 줄을 지운다. 새 이음새가 리뷰에서 발견되면 여기 추가한다.
- **훈련용 허수아비(`respawns=true`)를 씬에 배치하기 전 (2026-07-26 리뷰 M4):** 「광란」(`kill_move`)은 `EventBus.entity_died("enemy", pos)`에 매달려 있는데 그 시그널엔 **`EnemyDef`가 안 실려** 부활하는 적을 걸러낼 수단이 없다. 허수아비를 마을에 놓는 순간 광란이 **상시 유지**된다(에러 없음). `exp_authority`가 무한 EXP 파밍을 코드로 막은 것과 같은 문제이므로, 배치 전에 `entity_died`에 `respawns`(또는 def)를 실어 넓히고 `player._on_entity_died`가 그걸 보게 고친다. ⚠ 지금은 `training_dummy`가 어느 씬에도 없어 도달 불가라 미조치.
- **적 동적 스폰(웨이브 등) 착수 전:** CombatAuthority·MobSync의 적 등록이 `_ready` 일회 스캔이라 씬 배치 전제다 — 런타임 스폰 적은 미등록으로 게스트 hit_req가 **에러 없이** 무시된다. 등록 시그널 또는 지연 재스캔 구조로 바꾼 뒤 착수한다 (2026-07-22 리뷰).
- **스테이지 중 재합류(현재 GDD 비범위) 도입 전:** 합류 피어용 상태 스냅샷(ehp·php 일괄 재송신)을 먼저 만든다 — 없으면 놓친 사망 브로드캐스트가 게스트 화면에 멈춘 좀비 잔몹으로 영구 잔류한다 (2026-07-22 리뷰). ⚠ **드랍·장비 스탯도 스냅샷 대상** — 재합류 피어는 기존 바닥 드랍(DropAuthority `_drops`) + 각 피어의 `G_STATS`(장비 스탯)를 받아야 한다. ⚠ **비행 중 투사체(CombatAuthority `_arrows`·ArrowField `_arrows`/`_blasts`)도 검토** — 재합류 피어는 이미 날아가는 탄의 G_SHOOT를 놓쳐 표시가 없고(표시 전용이라 무해하나 일관성), **차지 중인 피어의 G_POS "c"는 다음 패킷에서 바로 따라잡히므로 스냅샷 대상이 아니다** (2026-07-24 리뷰).
- **4인 파티 도입 전 (P2P 전송분, 2026-07-26):** 현 전송 계층은 **2인 전제**(`MAX_ROOM_PEERS=2`)에 기대어 단순화돼 있다. 셋 이상이 되면 세 곳이 동시에 깨진다 — ⑴ `send_game`이 "한 명이라도 직결이 아니면 릴레이 브로드캐스트"라 **직결 피어가 같은 메시지를 두 번 받는다**(릴레이 페이로드에 수신자 지정 `to`가 필요) ⑵ 시그널링(SDP/ICE)도 방 전체 브로드캐스트라 A↔B의 ICE 후보가 C에게 흘러가 C가 엉뚱한 후보를 물고 **연결률만 조용히 떨어진다** ⑶ 메시 연결 수가 늘어 협상 상태기계가 지금 구조로는 감당이 안 된다. 릴레이 자체에 수신자 라우팅을 넣는 것이 선행 조건이다.
- **웨이브 스폰(동적 스폰) 도입 시 딸리는 것 — 메시지 크기 상한이 경로마다 다르다** (2026-07-26): 릴레이는 2048 UTF-16 유닛 초과 시 `close(1009)`로 **연결을 끊지만** 직결엔 상한이 없다. `G_MOB_POS` 배치나 `G_SWAMP` 묶음이 커지면 "직결일 땐 잘 되는데 폴백하는 순간 튕긴다"가 된다(현 몹 수에선 도달 불가). 배치 크기를 늘리는 변경은 릴레이 상한 기준으로 쪼개라.
- **4인 파티 / PvP성 요소 도입 전 (지연 보상분, 2026-07-24):** 지연 보상의 "방어자 우대"는 **의심스러우면 안 맞은 것으로** 판정한다 — 협동에선 무해하지만 PvP에선 회피가 과하게 관대해진다. 또 조작 클라가 pong을 늦게 보내 RTT를 부풀리면 자기 외삽 lead가 커져 **자기만 덜 맞을** 수 있다(상한 = 편도 200ms·거리 56px). PvP를 넣을 땐 ⑴ 판정을 한쪽 좌표 기준으로 좁히고 ⑵ RTT를 서버(릴레이)가 관측한 값으로 대체하는 것을 검토한다.
- **4인 파티 / PvP성 요소 도입 전:** ⑴ 픽업 근접 검증을 `DropAuthority._confirm_pickup`에 추가 — 요청자 `net_anchor()`와 `_drops[did].pos` 거리를 픽업 반경으로(hit_req `is_hit_in_reach` 패턴). ⑵ `G_STATS`(장비 스탯 공지)는 현재 **발신자 트러스트 + 데이터 유도 clamp**(`GameState.max_equip_stats`)만 — 본격 검증(장착 장비 실제 소유 확인 등)은 여기서. 둘 다 현재 **공유+선착+2인+아이템 이전 자유**라 생략(복제·귀속 스푸핑 없음, clamp로 무한 hp 차단 — reviewer 2026-07-23). DropAuthority에 peer_sync 참조가 필요해진다.
- (통과: 두 번째 씬 게이트 2026-07-22 — 피어/직업 동기화 = `src/net/peer_sync.gd`, 전투 확정 = `src/stage/combat_authority.gd`, 공용 HUD = `src/hud/stage_hud.tscn`. 마을·스테이지는 이 컴포넌트를 자식 노드로 문다 — 새 씬도 같은 방식, 복사 금지.)
- (통과: 잔몹 게이트 2026-07-22 — HP·피격·부활 = `src/combat/health_component.gd`(바디 타입 무관 자식 노드 `Health`, 권한 경로 `apply_damage/confirm_hp`와 표시 경로 `set_hp_display` 분리). 허수아비·잔몹·플레이어가 같은 컴포넌트를 문다. 씬 전환 송수신 = `src/net/scene_flow.gd`(G_SCENE 검증 공용 — village 용접분 추출), 잔몹 표시 동기화 = `src/stage/mob_sync.gd`(mpos 10Hz 배치·matk 중계 — 판정 없음). 새 적/새 씬도 같은 컴포넌트를 문다, 복사 금지.)
- (통과: 두 번째 무기 모션 게이트 2026-07-24 — 공격 **모션 타입**을 `EquipDef.motion_type`(swing/shoot/charge/thrust)로 빼고 `player.gd _local_combat`이 타입 분기(`_swing_attack`/`_fire_projectile`/`_tick_charge`). **shoot = 궁수 활 = 실제 이동 투사체**: 표시 화살 = `src/combat/arrow.gd`(순수 연출, 충돌 없음)·전 클라 관리 = `src/stage/arrow_field.gd`·호스트 권한 판정 = `combat_authority.gd`(매 프레임 전진·`is_arrow_hit` 거리 질의·G_ARROW_HIT). 새 발사형 무기 = `motion_type="shoot"` + `arrow_range` .tres 한 장. thrust는 아직 미구현 — 추가 시 분기 하나 더. 네트워크 리뷰 2회 Critical 0.)
- (통과: 세 번째 무기 모션 = **charge 게이트 2026-07-24** — 법사 지팡이. shoot 경로를 **재사용**하고 갈래를 안 만들었다: 표시 탄·호스트 전진·G_SHOOT·G_ARROW_HIT가 전부 같은 코드다. 차이는 데이터(`blast_radius`·`charge_step_time`·`projectile_*`)와 3곳뿐 — 발사 입력(`_tick_charge`)·종료 시 폭발 판정(`_confirm_blast`)·폭발 FX(`arrow_field._blast_fx`). **신규 네트워크 메시지 0개**(G_SHOOT에 `w`/`c` 필드 추가, G_POS에 표시용 `c`). 새 차지 무기 = .tres 한 장. ⚠ 다음 발사형(관통·유도·다중탄)을 만들 때도 **새 메시지·새 필드를 만들기 전에** 이 경로에 데이터로 얹을 수 있는지 먼저 본다.)
- **새 특성(효과 키)을 추가하기 전 (조립 축 v2.0 2026-07-26 — v1.9 게이트를 통과하며 갱신):** 특성은 이제 **(효과 키, 값) 카탈로그**다 — `CombatMath.TRAIT_KEYS`/`TRAIT_MAX`/`TRAIT_LABEL` + `SubJobDef.main/sub_trait_*`. 기존 키를 재사용하는 하위 직업은 **순수 데이터 한 장**이고, **키를 늘릴 때만** 코드가 는다. 새 키를 넣을 땐 ⑴ `TRAIT_KEYS`·`TRAIT_MAX`·`TRAIT_LABEL` 세 곳을 함께(빠뜨리면 `clamp_trait`가 상한 0으로 **조용히 폐기**한다 — 이게 안전한 방향이라 에러가 안 난다) ⑵ 적용 지점을 **1곳**으로 유지하고 그 값을 **대상 아바타**(`player.trait_value`)에서 읽는다 ⑶ 🔒 특성 경계를 다시 읽는다 — **무기·모션·조작을 바꾸는 특성은 거부**(2차 전직 = 비범위), **공격력·체력**(장비 축)·**공속·치명**(5스탯 축 = 예산 안)도 거부. ⚠ 특성이 곱셈으로 데미지에 걸리면 화력 예산 밖에 둘 수 없다 — 그때는 GDD §6 예산표부터 고친다(planner 승인). ⚠ 이동/구르기 축 키는 **지연 보상 상한(`LAG_MAX_LEAD_DIST`)을 같이 재유도**해야 한다(`roll_dist`가 그 예 — 안 하면 "피했는데 맞았다"가 부분 재발하고 `test_combat_math_auto`의 외삽 불변식이 빨개진다).
- 🔴 **G_STATS 공지의 "보유 검증"이 없다 — 조립 축이 표면을 3배로 넓히고 성격까지 바꿨다** (2026-07-26 리뷰 I4): `"ms"`(메인 하위 직업 id) + `"ss"`(서브 칸 id 2개)는 **발신자 트러스트**다. 계열 불일치·모르는 id·경로 조작·슬롯 초과·중복 id·모르는 효과 키·상한 초과는 전부 막지만 **소유는 안 본다** — 전사면 검성·곡예사를 보유하지 않아도 주장할 수 있다.
  - ⚠ **이번에 전제 하나가 깨졌다.** 지금까지의 공지 스푸핑(atk/hp/lv/ms)은 전부 **사칭자 자신에게만** 걸렸는데, `drop_find`(도굴꾼)는 `DropAuthority`가 **파티 최대값**을 쓰므로 조작 클라 한 명이 **호스트의 드랍 롤 자체**를 바꾼다 — 정직한 플레이어의 세이브(경제)로 들어간다. "협동 2인이라 남에게 피해가 없다"는 더 이상 전부 참이 아니다.
  - ⚠ **공유 하위 직업은 콘텐츠 게이트(보스 클리어)로 열리는데 공지에는 그 게이트가 없다** — 챕터1을 깨기 전에도 곡예사·도굴꾼을 주장할 수 있다(레벨 게이트 사칭과 성격이 다르다).
  - 그래도 **지금은 수용한다**(협동 2인·아이템 이전 자유·각 키가 `TRAIT_MAX`로 묶임). 4인/PvP 게이트에서 `G_STATS` 본격 검증을 할 때 **보유·장착 하위 직업 확인**을 같이 넣고, `drop_find`는 그때 "요청자 본인 것만" 또는 호스트 관측값으로 좁힌다.
  - 🔴 **`"weapon"` 필드만은 예외로 지금 검증한다 — 게이트로 미루지 않았다** (2026-07-26 신고·리뷰 I-4). 다른 공지 필드의 스푸핑은 전부 **변조 클라가 필요**한데, "전사 + 지팡이"는 **정직한 클라가 상태 버그만으로** 도달했다(직업을 바꿔도 착용이 안 풀렸다 — §5 함정). 즉 이 조합은 치팅 표면이기 이전에 **재발 가능한 버그 클래스**이고, 그때 화력이 예산 밖으로 뛴다(전사 공격력 + 법사 차지 광역). 그래서 `combat_authority`가 공지 무기를 그 피어의 **공지 직업**과 대조하고(`GameState.can_job_equip` — 클라의 착용 규칙과 **같은 함수**), 불일치면 `""`(기본 화살 = 차지 배율·폭발 없음)로 떨어뜨린다. 폐기 방향이 관대한 쪽이 아님을 확인하고 넣은 것이다.
- **6번째 캐릭터 스탯을 추가하기 전 (성장축 2026-07-25):** `CombatMath.LEVEL_STAT_KEYS` 루프에 얹을 수 있는지 먼저 본다 — 얹히면 **키 한 줄 + SubJobDef 필드/step() + 적용 1곳**이고, 안 얹히면(비-곱셈·비-% 스탯) **왜 안 얹히는지를 §3에 적고** 별도 경로를 판다. 얹을 때도 `LEVEL_STAT_MAX`(하드 상한)·`GameState.max_level_stats`(데이터 유도 상한) 두 곳을 같이 늘린다 — 상한이 없는 스탯은 G_STATS 공지로 임의 수가 들어온다.
- 🔴 **장비에 5스탯을 붙이려는 변경은 거부한다** (GDD §6 🔒 축 경계). `EquipDef`에 crit/haste를 넣는 것, 반대로 `SubJobDef`에 attack/hp를 넣는 것 **둘 다** 기획 변경(planner 승인)이 선행 조건이다. 축이 겹치면 ⑴ 강화할 이유가 옅어지고 ⑵ "정직한 최강 장비"를 기준으로 잡아 둔 스탯 상한 검증의 기준선이 흐려진다. 이 경계는 **스키마에 필드가 아예 없는 것**으로 강제돼 있다(코드 구조 = 규율보다 싸다).
- 🔴 **클리어 후에도 킬이 생기는 구조(웨이브 스폰·소환·클리어 후 비행 투사체)를 넣기 전: `G_EXP` dedup을 먼저 만든다** (2026-07-25 리뷰 I4). `ExpAuthority`는 씬 컴포넌트라 ⑴ 마을·모닥불에 도착한 G_EXP는 **구독자가 없어 사라지고**(토큰 가드를 뺀 이유가 바로 그 유실인데 배치가 같은 창을 만든다) ⑵ `main._swap`이 `queue_free`(프레임 끝) 후 즉시 `add_child`라 **한 프레임 동안 두 씬의 ExpAuthority가 같이 `net_msg`에 붙어** 있어 그 프레임에 도착한 지급이 **2배 적립**된다(= 영구 레벨 발산). 현 흐름에선 마지막 킬과 전환 사이에 `ChapterFlow.NEXT_DELAY_S`(3초)가 있어 **도달 불가**지만, 클리어 후 킬이 생기는 순간 살아난다. 해법 후보: G_EXP에 단조 증가 시퀀스(`n`)를 실어 수신 측이 `n <= last_n`이면 폐기(유실 방지 성질은 유지하고 중복만 죽인다 — ⚠ 방 재입장 시 시퀀스 리셋을 함께 다뤄야 한다), 또는 적립 구독을 항상 살아 있는 곳(오토로드)으로 옮기고 ExpAuthority는 호스트 발화만 담당.
- **적 동적 스폰(웨이브) 게이트에 EXP도 포함된다:** EXP 지급이 `enemy_killed`(CombatAuthority 확정 경로)를 타므로, 미등록 적은 드랍뿐 아니라 **EXP도 안 준다** — 에러 없이 조용히.

**챕터1 진행 골격 (2026-07-22) — 새 스테이지/챕터는 이 조합을 문다, 복사 금지:**
- 칸 목록 = `data/chapters/*.tres`(ChapterDef — 씬 경로 순서, 모닥불 칸 포함, 마지막 = 보스). 진행 결정 = `src/stage/chapter_flow.gd`(호스트 전용: stage_cleared→다음 칸, 마지막 클리어/전멸→마을). 전투 스테이지 루트 = `src/stage/stage.gd`(PeerSync 토큰만 갱신) + PeerSync·CombatAuthority·MobSync·SceneFlow·ChapterFlow·HUD 조합. 모닥불 = `src/stage/campfire.tscn`(앉기 회복 = 호스트 confirm_hp, G_SIT은 힌트 — 거리 재검증).
- **칸 토큰 = `GameState.stage_token()`("stage:챕터:인덱스")** — 같은 tscn(모닥불)이 여러 칸에 재사용돼도 칸마다 토큰이 달라 G_POS 유령 스폰이 안 생긴다. 새 씬은 루트 _ready에서 PeerSync.scene_id에 이 토큰을 넣는다.
- **HP는 챕터 내 스테이지 간 이월된다** — 기록 = `GameState.record_party_hp`(player.gd 확정 경로 2곳만), 스폰 재확정 = 호스트(CombatAuthority의 player_spawned 핸들러), 리셋 = `GameState.leave_chapter()`(마을/로비 진입, main). 직업 재공지는 `Health.set_max_hp`(setup 아님)라 이월 HP를 안 지운다.

## 3. 하드 계약 (단일 소스 — 복사하면 갈라진다)

같은 계산을 두 곳에서 하면(예: UI 표시와 실제 게임플레이가 위력을 각자 계산) 한쪽만 고쳤을 때 아무도 모르게 갈라진다. 일부는 이미 구현됨(장비 스탯·데미지·드랍 스키마 — 2026-07-23), 나머지는 **예약된 계약**이다 — 해당 로직을 처음 구현할 때 반드시 이 위치에 만들고, 다른 곳은 전부 이 함수를 부른다.

- 🔴 **최종 데미지 = `src/core/combat_math.gd`의 `calc_damage(job, bonus_attack)`.** (2026-07-23 구현) bonus_attack = 착용 장비 공격 합(total_stats.attack). 미착용=0 → 기존 동작과 동일(항등 폴백). 실제 전투 판정(호스트)과 UI 표시가 같은 함수.
- 🔴 **장비 스탯 합산 = `src/core/combat_math.gd`의 `total_stats(equip_levels)` + `equip_stat_at_level(equip, level)`.** (2026-07-23 구현) 착용 장비 → 총 {attack, hp}. HUD·전투·제작/강화 패널 공용. ⚠ CombatMath는 오토로드를 참조하지 않는다(-s 테스트 호환) — 착용 id→EquipDef 리졸브는 부르는 쪽(`GameState.equipped_defs`)이 한다.
- 🔴 **강화 결과·비용 = `src/core/combat_math.gd`의 `upgraded_stats(equip, from, to)`·`upgrade_cost(equip, level)`.** (2026-07-23 구현) 강화 UI "다음 단계 미리보기"와 실제 적용/차감이 같은 함수.
- 🔴 **직업 귀속 = `GameState.can_job_equip(job_id, equip)`(규칙) + `revalidate_equipped()`(직업 변경 시점) + `apply_job_loadout()`(뒤처리 3종 세트).** (2026-07-26 실기 신고 "전사로 들어왔는데 마법 지팡이를 쓴다") `can_equip_job`은 **착용 시점에만** 걸리므로 직업이 **나중에** 바뀌는 경로(로비 재선택·마을 직업 변경·세이브 로드)에서 남의 직업 무기가 착용된 채 남았다. 겉모습 문제가 아니다 — 그 id가 `G_STATS "weapon"`으로 공지되고 호스트가 `peer_weapon_id`로 판정을 리졸브하므로 **전사가 실제로 차지 폭발을 쐈다**(화력 예산 밖).
  - 🔴 **직업이 확정되는 자리는 `apply_job_loadout()` 한 줄만 부른다** — 재검증 → 시작 무기 지급/착용 → 시작 하위 직업 지급이 **늘 같이** 가야 한다. 하나라도 빠지면 조용히 깨진다(해제만 = 맨손 / 지급만 = 이번 신고 / 하위 직업 누락 = 메인이 옛 계열에 남아 메인 특성·5스탯이 통째로 꺼짐). 호출부는 `main._to_village`·`main._on_scene_change(VILLAGE)`·`peer_sync._on_job_change_requested` 셋 — **세 줄을 손으로 맞춰 들고 있으면 네 번째 자리에서 반드시 빠진다**(§2 "권한·동기화 로직 복사 금지"와 같은 이유).
  - 🔴 **호스트 판정도 같은 함수를 지난다** — `combat_authority`가 공지 무기를 그 피어의 공지 직업(`peer_sync.peer_job_id`)과 대조할 때 `can_job_equip`을 부른다. 사본 조건문을 두면 다음 튜닝에서 클라 착용 규칙과 갈라진다(§2 G_STATS 항목).
  - 🔴 **재검증은 판 도중(`in_chapter`)엔 돌지 않는다** — `autofill_sub_slots`의 가드와 같은 이유이고 더 세다: 해제는 내 판정 무기·atk를 즉시 바꾸는데 상대 호스트의 원격 아바타는 G_STATS 도달 뒤에야 바뀌어, 그 창의 타격이 **무음 거부**된다. 가드는 호출부가 아니라 **피호출 함수**에 있다(호출부에 흩어 두면 다음 사람이 스테이지에서 직업을 대입하는 순간 전투 중 무기가 사라진다).
  - **해제는 파기가 아니다** — 착용(`equipped`)만 풀고 소유(`owned_equipment`)는 건드리지 않는다. 그 직업으로 돌아오면 가방에 남은 무기를 되찾는다.
- 🔴 **인원 스케일링(솔로 시 보스 약화) = `src/core/combat_math.gd`의 `party_scale()`.** 수치·범위는 GDD §11 TBD — 함수 위치만 먼저 고정.
- 🔴 **히트 기하(공격 중심·반경) = `src/core/combat_math.gd`의 `attack_center_offset()`·`attack_radius()`.** 실제 판정(원형 질의)과 공격 궤적 FX 크기(스워시 스케일 = 판정 도달/텍스처 반경)가 같은 함수에서 파생된다 — 한쪽만 조이면 "맞는 곳"과 "보이는 곳"이 어긋난다. 손맛 튜닝은 반드시 이 상수(ATTACK_CENTER_SCALE·ATTACK_RADIUS_SCALE)와 `data/jobs/*.tres`의 attack_range로.
- 🔴 **하위 직업 특성 = `combat_math.gd`의 `TRAIT_KEYS`/`TRAIT_MAX`/`clamp_trait(s)`/`empty_traits`/`trait_text` + `GameState.traits_of(main_id, sub_ids, series)` + `player.trait_value(key)`.** (조립 축 GDD v2.0, 2026-07-26) 특성은 **(효과 키, 값)** 이고 키마다 적용 지점이 1곳이다. 자리별로 얼굴이 다르다 — 메인 id는 `SubJobDef.trait_at(true)`, 서브 id는 `trait_at(false)`.
  - **신뢰 경계:** 네트워크로 오는 것은 **id뿐**(G_STATS `"ms"`/`"ss"`)이고 값은 각자 로컬 `data/subjobs`에서 리졸브한다(`peer_weapon_id`·`projectile_params`와 같은 철학). `traits_of`가 ⑴ 계열 불일치(공유 `"*"`는 통과) ⑵ 모르는 id·경로 조작 ⑶ **서브 슬롯 수 초과분**(`SUB_SLOT_COUNT`에서 자름 — 서브를 10개 실어 특성을 쌓는 것 차단) ⑷ 메인·서브 중복 id ⑸ 모르는 효과 키를 전부 폐기하고, 마지막에 `clamp_traits`가 `TRAIT_MAX`로 자른다. 남은 표면 = 보유 검증 없음(§2 게이트).
  - 🔴 **호스트는 특성을 항상 "대상 아바타"(`player.trait_value`)에서 읽는다** — 사거리(공격자)·구르기 쿨(구른 피어)·모닥불 회복(앉은 피어)·드랍량(파티 최대) 전부. `peer_sync._peer_stats`엔 **로컬(호스트 자신) 항목이 영원히 없어서**(Net 루프백 없음) 그쪽을 읽으면 "내 것만 안 먹힌다"가 된다 — 2026-07-25 공속 Critical과 같은 함정이고, 이번에도 같은 규약으로 선제 차단했다.
  - 🔴 **UI 문구는 `trait_text`에서 파생한다** — 훈련소 패널이 설명을 하드코딩하면 값과 표시가 갈라진다(v1.9 게이트가 요구한 것). 이름만 데이터(`SubJobDef.*_trait_name`).
- 🔴 **구르기 파생 = `effective_roll_cooldown(roll_cd)` / `effective_roll_speed(base, roll_dist)` / `ROLL_SPEED_MULT`(v2.0에 player.gd에서 이사).** 로컬 쿨과 호스트 그랜트 검증(`is_roll_grant_ok`)이 **같은 쿨 함수**를 지나고, 로컬 이동·원격 속도 clamp·원격 변위 clamp **세 곳이 같은 속도 함수**를 지난다(§3 이동속도 계약과 같은 이유). 한쪽만 고치면 ⑴ "굴러지는데 무적이 안 걸린다"(쿨) ⑵ 정당하게 길어진 구르기가 깎여 외삽 과소평가 → "피했는데 맞았다" 부분 재발(속도)이 된다 — 둘 다 화면에 이유가 안 드러난다. ⚠ clamp에 쓰는 상한은 `player._max_move_speed`/`_max_roll_speed`(kill_move를 **타이머와 무관하게 항상 포함**) — 버프 창이 클라마다 몇십 ms 어긋나도 정당 이동이 안 깎이게, 상한은 관대한 쪽으로 틀리는 것이 안전하다.
- 🔴 **평타 사거리 = `combat_math.gd`의 `effective_attack_range(job, reach)` — 사거리 3함수(`is_hit_in_reach`·`attack_center_offset`·`attack_radius`)가 전부 이 함수를 지난다.** (하위 직업 특성 = 검성 검기 파형, GDD v1.9→v2.0, 2026-07-26) `reach` = 활성 특성의 `reach` 키(`GameState.active_traits()` / `peer_sync.peer_traits()` → `player.trait_value("reach")`). **`haste_scale`과 같은 이유로 배율 함수를 공유하는 것 자체가 계약의 증명이다** — 한 곳이라도 `job.attack_range`를 직접 읽으면 판정과 표시(스워시 스케일·파형 도달점)가 갈라져 "맞는 곳 ≠ 보이는 곳"이 되고, 그건 에러 없이 손맛으로만 드러난다. 기본값 0 = 특성 도입 전과 **완전 항등**.
  - **신뢰 경계:** `clamp_reach`(하드 상한 `MAX_REACH_BONUS` +50% · 음수 0 · INF 0) + **수치를 네트워크로 받지 않는다** — G_STATS `"ms"`로 오는 것은 하위 직업 **id뿐**이고 값은 각자 로컬 `data/subjobs`에서 리졸브한다(`GameState.reach_bonus_of` — 계열 불일치·모르는 id·경로 조작은 0으로 폐기). `peer_weapon_id`·`projectile_params`와 같은 철학. 남은 표면 = 보유 검증 없음(위 §2 게이트).
  - 🔴 **호스트는 사거리 보너스도 "공격자 아바타"(`attacker.reach_bonus`)에서 읽는다 — 공속·치명·피흡과 같은 소스다.** `peer_sync`의 수신 기록류(`_peer_stats`)에는 **로컬(호스트 자신) 항목이 영원히 없다**(Net 루프백 없음). 그걸 쓰면 검성 호스트가 자기 파형 사거리를 못 받아 "내 파형은 헛치는데 게스트는 맞는다"가 된다 — 2026-07-25 공속 Critical과 **같은 함정**이다. 로컬 값은 `peer_sync._apply_local_stats`가 `GameState.main_reach_bonus()`로 넣는다.
  - **파형은 표시 전용이고 판정을 만들지 않는다** (GDD §6: 자체 데미지 없음). `player.gd`의 `_start_wave`/`_tick_wave`는 그 프레임 스워시와 **같은 기하 계산 결과**를 도달점으로 받는다 — 연출값(`WAVE_FX_TIME`·`WAVE_START_RATIO`)으로 도달 거리를 늘리지 마라. `WAVE_TEX_HALF_H`(12)는 `sword_wave.png` 세로 반높이와 **미러**(텍스처를 다시 그리면 같이 고친다 — blast.png `TEX_RADIUS`와 같은 함정).
- 🔴 **구르기 타이밍 = `src/core/combat_math.gd`의 `ROLL_TIME_S`·`ROLL_COOLDOWN_S`·`is_roll_grant_ok()`·`is_iframe_active()`.** 로컬 구르기 이동(player)과 호스트 i-frame 검증(G_ROLL 그랜트)이 같은 상수를 읽는다 — player.gd에 사본을 만들면 첫 손맛 튜닝에서 무적 창과 이동이 갈라진다. (i-frame 있음 = 사용자 확정 2026-07-22) ⚠ **애니 미러**: `assets/sprites/player/*_frames.tres`의 roll 애니(4프레임/speed 16 = 0.25s)가 이 값과 암묵으로 맞물린다 — ROLL_TIME_S를 바꾸면 3개 .tres의 roll speed도 같이 조정 (loop=false라 애니가 창보다 짧으면 마지막 프레임에 얼어붙는다).
- 🔴 **공격 스윙 창 미러 = 스윙 창 < 모든 `data/jobs/*.tres`의 `attack_cooldown`.** (2026-07-22 등록, 2026-07-24 무기별화) 스윙 창은 이제 **무기별 = `EquipDef.swing_time`**(폴백 = `player.gd`의 `ATTACK_ANIM_TIME`=0.25). 어떤 무기의 swing_time이든, 어떤 직업의 attack_cooldown이든 **swing_time ≥ attack_cooldown이 되면** 원격 스윙 창-잠금 가드(`play_attack_fx`)가 정당한 연속 공격의 스윙 연출을 무시해 로컬-원격 화면이 갈라진다. swing_time을 늘리거나 attack_cooldown을 줄일 땐 이 부등식을 같이 본다(현: 대검 swing_time ≤0.34 < 전사 0.4). ⚠ **스윙 모션(호 반각·창·내지르기)은 무기별 = `EquipDef.swing_arc/swing_time/swing_lunge`** — `player.gd`의 `_swing_*` 멤버가 `set_weapon_visual`에서 세팅돼 로컬·원격 모두 그 피어의 무기 동작으로 그린다(§ 손맛). ⚠ 무기는 몸에 굽지 않는다 — **몸(AnimatedSprite2D)과 분리된 독립 Sprite2D**(`WeaponPivot/Weapon`, 텍스처 = `EquipDef.weapon_texture`, 미착용 시 무장 해제)가 조준각으로 회전 + 스윙 창 동안 호를 그린다(전부 표시 전용). 원격 조준각 = G_POS "a"(표시 전용, 판정은 여전히 net_anchor+호스트 검증).
- 🔴 **잔몹 타격 기하 = `EnemyDef.strike_radius` + `combat_math.gd`의 `is_strike_hit()`.** 호스트 판정과 텔레그래프 표시(스프라이트 스케일)가 같은 반경을 읽는다 — "맞는 곳=보이는 곳". 판정 좌표는 net_anchor(§3 위치 원칙).
- 🔴 **보스 패턴 판정 기하 = `combat_math.gd`의 `is_strike_hit()`(원) + `is_hit_in_cone()`(부채꼴).** (보스전 슬라이스 0, 2026-07-23) `BossPatternDef.shape`("circle"/"cone")가 어느 함수를 부를지 정하고, 판정 반경/각(`range`·`half_angle`) = 텔레그래프 표시 스케일/회전 — "맞는 곳=보이는 곳". 물 뿌리기(여러 원 착탄)는 `is_strike_hit`를 착탄점마다 N회(`burst_count`). 새 판정 형태(사각 등)가 필요하면 여기 단일 소스로 추가하고 shape 값을 늘린다.
  - 🔴 **부채꼴 텔레그래프 각은 코드가 강제 못 하는 art/data 계약이고, 지금 실제로 어긋나 있다** (2026-07-23 리뷰 등록 → 2026-07-26 실측으로 위반 확인): `boss_croc.gd`의 균일 스케일은 텍스처 **길이=range**만 판정과 맞춘다. **각도는 `telegraph_cone.png`에 그려진 부채꼴 각이 그대로 결정**되므로 텍스처를 **전체각 = 2×half_angle**로 그려야 "보이는 각=맞는 각"이다.
    - **실측 위반:** `telegraph_cone.png`(80×96)에 그려진 각은 **half 0.599rad(전체 68.6°)** 로 **악어 기준**(`croc_boss.tres` swing 0.60)인데, 실제 배선된 보스는 **망령**(`wraith_boss.tres` swing **0.75rad = 전체 85.9°**)이다. → 보이는 예고보다 판정이 **좌우 각 8.6° 넓다**(range 130px에서 약 19px 폭 = 캐릭터 16px보다 넓은 무예고 피격 영역). 해소 = ⑴ 망령 `half_angle`을 0.6으로 내리거나 ⑵ 86° 콘 텍스처를 새로 그려 `BossPatternDef.telegraph_tex`로 그 패턴에만 지정한다(패턴별 텍스처 필드가 이미 있다).
    - **교훈:** 보스/패턴을 교체할 때 `half_angle`이 달라지면 텍스처 계약이 함께 깨진다 — 데이터만 바꿔도 아트 부채가 생기는 유일한 필드다. 원 텔레그래프는 균일 스케일=반경이라 이 함정이 없다.
  - ⚠ **공격 애니↔telegraph_s 미러**: 보스 공격 애니(`swing`/`slam`/`spray`, loop=false)는 WINDUP 시작 시 1회 재생되고 STRIKE는 `pattern.telegraph_s` 뒤 — **애니 총 길이 ≈ telegraph_s**여야 타격 프레임이 STRIKE 순간에 보인다. telegraph_s를 조이면 SpriteFrames speed도 같이 본다(mob_melee의 ATTACK_ANIM_LEAD_S 미러).
  - 🔵 **현행 배선은 망령이다** (2026-07-26 확인): `stage_boss.tscn`의 `BossCroc` 노드가 `data/enemies/wraith_boss.tres`(64px, `boss_wraith_frames.tres`)를 def로 문다 — 씬·스크립트 이름의 `croc`은 과거 이름이 남은 것이다. **`croc_boss.tres`(72px, 31프레임 6애니)는 아트·데이터가 완성돼 있으나 어느 씬도 참조하지 않는다.** 그리고 망령 시트엔 **`walk`가 없어**(idle/swing/slam/spray/death) `_has_anim()` 가드가 건너뛰므로 **보스가 이동할 때 idle 자세로 미끄러진다**(에러 없음). 보스 관련 값을 인용할 때 어느 def를 보는지 먼저 확인해라.
- 🔴 **인원 스케일링(솔로 시 보스 약화) = `combat_math.gd`의 `party_scale(base, party_size, solo_factor)`.** (보스전 슬라이스 0 — 예약→구현) 솔로(1) → `base*solo_factor`, 2인+ → 항등. 보스 max_hp·물 착탄 수·페이즈2 늪 생성 빈도에 호스트가 곱한다(게스트도 같은 피어 수로 동일 계산 → 표시 일치). solo_factor·적용 대상은 GDD §11 TBD·사용자 실기 튜닝.
- 🔴 **거대 적 사거리 = `is_hit_in_reach(..., enemy_radius)`에 `EnemyDef.body_radius` 반영.** (보스전 슬라이스 0) 중심거리 − body_radius로 판정한다 — 거대 보스(radius ~48)는 중심이 멀어 "붙어도 사거리 밖"이 되므로 몸통 표면까지. 기본 0 = 기존 잔몹 동작 불변. 호출부(`combat_authority._on_net_msg` G_HIT_REQ)는 `entry["def"].body_radius`를 넘긴다.
- 🔴 **투사체(궁수 화살) = `combat_math.gd`의 `ARROW_SPEED`·`is_arrow_hit()`·`arrow_lifetime_s(range)`·`clamp_arrow_range()` + 발사 검증 `is_fire_rate_ok()`·`is_shot_origin_ok()`.** (궁수 활, 2026-07-24) 화살 = 결정론 직선 등속: 발사자 `G_SHOOT`(원점·방향·aid·**r=사거리**) 1회 → 각 클라 로컬 표시 화살 시뮬(위치 스트림 없음). **명중은 호스트만**: `combat_authority._physics_process`가 권한 화살을 전진시키며 `is_arrow_hit`(거리 질의 — 물리 레이어 대신, §5 함정 회피)로 판정 → `calc_damage` 확정 → `G_ARROW_HIT`(표시 despawn). 신뢰 경계(§1): 사망자 발사 거부·`is_fire_rate_ok`(발사율)·`is_shot_origin_ok`(원점 근접, `SHOT_ORIGIN_TOL`)·게스트 `r`은 `arrow_lifetime_s`가 `MAX_ARROW_RANGE`로 clamp(G_STATS clamp 미러). 속도는 공용 상수(결정론), **사거리는 무기별 `EquipDef.arrow_range`**(G_SHOOT로 전송 → 표시·판정 동일값). 화살 굵기 = `ARROW_HIT_RADIUS`+적 body_radius. ⚠ 터널링 불변식: 프레임당 전진(SPEED/60) < 최소 명중 지름 — `ARROW_SPEED`↑나 body_radius 0 적 도입 시 세그먼트 질의 필요(combat_math 주석). 무기 표시 거리 = `EquipDef.weapon_hold_dist`(활은 몸과 안 겹치게 20, 순수 표시).
- 🔴 **차지 발사(법사 지팡이) = `combat_math.gd`의 `MAX_CHARGE_LEVEL`·`CHARGE_DAMAGE_MULT`/`CHARGE_RADIUS_MULT`/`CHARGE_ORB_SCALE`·`clamp_charge_level()`·`charge_level_for()`·`charge_damage()`·`charge_blast_radius()`·`is_blast_hit()`·`is_charge_time_ok()`.** (2026-07-24) 마우스 홀드로 3단계를 모아 쏘고 착탄(명중/사거리 소진) 지점에서 **범위 폭발**. **네트워크로 오가는 건 레벨(정수)뿐** — 위력·반경 배율은 이 공용 표에서 각자 리졸브한다(배율을 전송하면 그게 곧 스푸핑 표면). 신뢰 경계: `clamp_charge_level`(배열 인덱스·위력 상한) + `is_charge_time_ok`(마지막 발사 이후 경과 ≥ 레벨×단계시간×0.9 — 연사하며 MAX를 주장하는 스팸 차단, `is_fire_rate_ok` 미러) + `charge_blast_radius`의 `MAX_BLAST_RADIUS` clamp. 🔴 **폭발 판정 반경 = 표시 FX 반경**(`blast.gd`의 `scale = radius / TEX_RADIUS`) — blast.png의 원 반지름이 바뀌면 `TEX_RADIUS`도 같이 고친다(텍스처 미러, 콘 텔레그래프와 같은 함정).
- 🔴 **투사체 파라미터 리졸브 = `GameState.projectile_params(weapon_id, fallback_range, charge)`.** (2026-07-24) 표시(`arrow_field`: 탄 텍스처·속도·수명·폭발 FX 반경)와 판정(`combat_authority`: 전진 속도·수명·폭발 반경)이 **반드시 같은 함수**를 지난다 — 한쪽에서 직접 계산하면 "맞는 곳"과 "보이는 곳"이 갈라진다. 무기 id(G_SHOOT `w`)는 **allowlist 리졸브 전용**(모르는 id → 기본 화살 폴백, 경로는 절대 네트워크로 안 받는다 §3). 리졸브되면 사거리·속도·폭발 반경은 전송값이 아니라 **각자의 로컬 무기 데이터**에서 나온다. 🔴 **호스트는 발사 메시지의 `w`를 안 믿는다** — `peer_sync.peer_weapon_id()`(그 피어가 G_STATS로 공지한 착용 무기)로 리졸브한다. 안 그러면 전사/궁수가 `w="worn_staff"`를 실어 차지 배율(×3.4)과 광역 폭발을 얻는다(2026-07-24 리뷰). 표시(ArrowField)는 메시지 `w`를 그대로 쓰므로 **사칭자 화면에만 폭발이 그려지고 판정은 안 난다**(안전한 방향의 갈라짐). 남은 표면은 G_STATS 공지 자체의 발신자 트러스트뿐 = atk/hp와 같은 한 장(4인/PvP 게이트 §2 대상).
- 🔴 **지연 보상 = `combat_math.gd`의 `clamp_one_way_ms`·`strike_delay_s`·`lag_lead_s`·`extrapolate`·`is_strike_hit_lagged`·`is_hit_in_cone_lagged` + `Net.one_way_ms`/`max_remote_one_way_ms` + `player.net_anchor_lead()`.** (2026-07-24) 호스트 권한 모델에서 **게스트만 구조적으로 손해보는** 문제("피했는데 맞았다")의 단일 소스. 실측 근거: 배포 릴레이 RTT 140~215ms에서 게스트의 실효 회피 창이 고블린 0.60s → 0.38s(36% 손실), 호스트는 0% — 예고가 늦게 도착(편도)하고 판정에 쓰이는 좌표가 낡았기(편도+송신주기) 때문.
  - **두 축 (둘 다 호스트 계산 — 게스트는 상태를 확정하지 않는다 §1):** ⑴ **STRIKE 지연**(`strike_delay_s(Net.max_remote_one_way_ms())`) = 예고 타격 시각을 가장 느린 피어의 편도 지연만큼 늦춘다 → 게스트도 자기 화면 기준 온전한 `telegraph_s`를 갖는다. 호스트 화면은 예고가 그만큼 길어져 **공평해진다**(표시 지속도 같이 늘려야 "보이는 예고 = 맞는 타이밍"이 유지된다 — `mob_melee.show_telegraph(center, duration)`·`boss_croc._telegraph_hold_s`). ⑵ **위치 외삽 + 방어자 우대** = 판정 시 게스트의 "지금" 위치를 마지막 관측 속도(G_POS `vx/vy`)로 추정하고, **낡은 좌표와 추정 좌표가 둘 다 맞아야** 확정.
  - 🔴 **왜 "둘 다"인가 — 이 규약을 `and`에서 한쪽으로 바꾸면 안 된다.** 외삽은 방향 전환 순간에 틀리므로 추정 좌표만 믿으면 새 오탐이 생긴다. 둘 다 요구하면 오차가 **항상 방어자에게 유리한 쪽**으로만 떨어진다(빠져나가는 중 → 안 맞음 = 고치려던 그 버그 / 들어오는 중 → 안 맞음 = 관대 / 계속 안 → 맞음). 두 좌표가 같으면(호스트 자신·정지) 기존 `is_strike_hit`과 **항등**이라 솔로·호스트 동작은 변하지 않는다.
  - **신뢰 경계:** 편도 지연 `LAG_MAX_ONE_WAY_MS`(200ms) clamp — 큰 RTT를 주장해 보스 예고를 무한 지연시키는 것 차단. 외삽 거리 `LAG_MAX_LEAD_DIST`(56px) clamp + 속도는 수신부에서 `job.move_speed × ROLL_SPEED_MULT`로 `limit_length`. 남은 표면 = 조작 게스트가 RTT를 부풀려 **자기만 덜 맞는** 것(최대 56px 유리) — 협동 전용이라 자해에 가까워 수용, §2 4인/PvP 게이트 대상.
  - **RTT 계측 = `Net`이 자체 처리**(G_PING/G_PONG, 0.5s 주기, EMA). ⚠ 이 두 메시지는 `net_msg`로 **안 올라온다** — Net이 소비하고 끝낸다. 시계 동기화 불필요(자기가 찍은 타임스탬프를 그대로 돌려받아 자기 시계로만 잰다).
  - 🔴 **RTT 계측 채널 = 예고 전달 채널** (P2P 도입 2026-07-26). ping/pong을 유실 허용(fast) 채널로 내리면 **실패한 왕복이 아예 샘플에 안 잡혀** RTT가 낙관적으로 보고되고, 그만큼 `strike_delay_s`가 과소 보상해 그 회차만 회피 창이 짧아진다("가끔 예고가 늦다"로만 보인다). 예고(G_MOB_ATK·G_BOSS_ATK)가 reliable인 한 측정도 reliable이어야 한다 — `test_net_transport_auto`가 지킨다.
  - 🔴 **전송 경로가 바뀌면 `_rtt_ms`를 버린다.** 직결(20ms)에서 릴레이(~200ms)로 폴백할 때 EMA를 들고 가면 ~2.5초 동안 `strike_delay_s`가 거의 0이고 `net_anchor_lead`가 `net_anchor`와 같아져 **"둘 다 맞아야" 규약이 한쪽 판정으로 퇴화**한다(= 이 계약이 고친 버그의 재발). `_p2p_drop`이 `S_PEER_LEFT`와 같은 이유로 erase한다.

- 🔴 **전송 계층(P2P 직결) = `src/net/net.gd`의 `RTC_FAST_KINDS`·`_p2p_send`/`_p2p_ready`·`send_game` + `CombatMath.is_pos_seq_fresh` + `NetSchema.G_RTC_SDP`/`G_RTC_ICE`/`G_KEEP`.** (2026-07-26) 게임 페이로드는 WebRTC DataChannel 직결로, 시그널링·폴백만 릴레이로 간다. 릴레이 왕복 실측 207ms(§5 무료 CF가 서울 엣지를 안 태운다) → 직결 10~40ms.
  - 🔴 **fast(유실 허용) 채널에는 "다음 패킷이 곧 덮어쓰는 것"만 넣는다** — 현재 `G_POS`·`G_MOB_POS`뿐. **사건 kind(shoot·arrowhit·drop·ehp·php·scene…)를 넣으면 한 통 유실이 곧 영구 상태 갈라짐**이다(화살이 안 생기거나 안 사라지고, HP가 클라마다 달라진다 — 에러 없이 화면만 어긋난다). `test_net_transport_auto`가 집합을 단정하고, 사건 kind를 끼워 넣으면 빨개진다.
  - 🔴 **unordered 채널은 순서 뒤바뀜을 만든다 — 릴레이(TCP)에선 없던 결함이다.** 옛 G_POS를 적용하면 `_remote_target`과 `_remote_vel`이 **함께** 과거로 돌아가고, 그러면 `net_anchor`와 `net_anchor_lead`가 **같은 방향**으로 틀려 방어자 우대 규약이 무력화된다(규약은 두 좌표가 서로 다른 방향으로 틀릴 때만 방어자를 보호한다). → G_POS `"n"`(단조 증가 시퀀스) + `is_pos_seq_fresh` 폐기. ⚠ 변위 clamp는 이걸 못 막는다 — 되돌아가는 거리가 한 송신 간격분(~4px)이라 상한(~13px) 안이다.
  - **두 채널이 다 열려야 직결로 본다**(`_p2p_ready`). 하나만 태우면 같은 피어에게 가는 메시지가 두 경로로 갈라져 사건이 그것이 서술하는 위치보다 먼저 도착한다.
  - **폴백은 지우지 마라.** 대칭형 NAT 등에서 P2P는 통상 10~20% 실패하고, 그때 릴레이가 없으면 게임이 아예 성립하지 않는다. 직결이 죽으면(`FAILED`/`CLOSED`/**`DISCONNECTED`** + 무수신 워치독 3s) 자동으로 릴레이로 돌아온다. ⚠ `DISCONNECTED`를 빼면 브라우저 consent 만료(~30초)까지 채널이 `STATE_OPEN`인 채 **메시지가 블랙홀로 간다**(put_packet도 OK를 돌려준다).
- 🔴 **최종 데미지 = `combat_math.gd`의 `confirm_damage(job, bonus, lv_stats, charge_lv, roll)` — 근접·투사체·폭발 3경로 전부 이 함수만 부른다.** (성장축 2026-07-25) 곱 순서 **(직업 기본 + 장비) × 차지 배율 × 치명 배율, 반올림 1회**. `charge_damage`가 이미 round를 하므로 치명을 그 밖에서 곱하면 **이중 반올림**이 된다 — 경로마다 곱 순서/반올림이 갈라지면 같은 상황에서 데미지가 달라진다. 전투 확정 경로에서 `calc_damage`/`charge_damage` 직접 호출 금지(UI 미리보기 전용). 굴림(`roll`)은 **호출부(호스트 RNG)** 가 만든다 — CombatMath는 RNG·오토로드를 쥐지 않는다(테스트 결정론). 굴림 단위 = **데미지 인스턴스 1회**(폭발이 3마리를 때리면 3번, 사용자 확정). 호스트 구현 = `combat_authority._apply_confirmed`.
- 🔴 **레벨 스탯(캐릭터 스탯 5종) = `LEVEL_STAT_KEYS` + `level_stats(main, levels, defs, sub_weight)` + `clamp_level_stats(stats, caps)`.** (성장축) 와이어 키 = 이 상수 문자열 그대로(G_STATS `lv`·`SubJobDef.step()`·clamp 키) — **별도 매핑 표를 만들지 마라**(두 번째 진실원이 되어 갈라진다). 🔴 수신부는 **payload가 아니라 키 목록을 순회**한다(모르는 키 자동 폐기·빠진 키 0으로 항등 폴백). 상한 = `LEVEL_STAT_MAX`(하드) ∩ `GameState.max_level_stats()`(데이터 유도) 이중. 효과 = **메인 온전 + 서브 × `SUB_JOB_WEIGHT`**(GDD §5).
- 🔴 **유효 쿨다운 = `effective_cooldown(job, haste)` / 배율 = `haste_scale(haste)` 단 하나.** (성장축) 스윙 창(`EquipDef.swing_time`)·차지 스텝(`charge_step_time`)에도 **같은 `haste_scale`을 곱한다** — 그러면 스윙 창 계약(`swing_time < attack_cooldown`)이 모든 haste에서 `swing_time·k < cooldown·k`로 **자동 보존**된다. **배율 함수를 공유하는 것 자체가 계약의 증명**이고, 각자 `1/(1+h)`를 다시 쓰면 그 증명이 깨진다. 로컬·원격 파생 = `player._refresh_growth_derived()`(입력이 둘 — 레벨 스탯 변동·무기 교체 — 이라 반드시 한 함수로 모은다). 호스트 검증 3함수(`is_hit_cooldown_ok`·`is_fire_rate_ok`·`is_charge_time_ok`)는 **발신자 주장이 아니라 자기가 clamp한 `peer_sync.peer_level_stats()`** 를 게이트에 넣는다(`peer_weapon_id` 철학). ⚠ `effective_cooldown×0.9`가 `SAME_SWING_MS`(50ms)보다 작아지면 근접 쿨다운 게이트가 퇴화한다 — 테스트 트립와이어 유지.
- 🔴 **이동속도 = `effective_move_speed(base, move)` — 로컬 이동과 원격 위치 clamp 2곳이 같은 유도식(`player._move_speed()`)을 쓴다.** (성장축) 🔴 원격 clamp만 기본 이속으로 남기면 빨라진 **정당한** 이동이 깎여 `net_anchor_lead` 외삽이 과소평가되고, 2026-07-24에 고친 "피했는데 맞았다"가 빠른 피어에게 **부분 재발**한다(설계 중 발견). 속도 상한(`ROLL_SPEED_MULT`)과 변위 상한(`×REMOTE_MAX_SPEED_MULT`)을 함께 유도한다 — 갈라지면 다음 튜닝에서 한쪽만 고친다.
- 🔴 **피흡 = 호스트 전용 소수 누적(`combat_authority._leech_frac`) + 회복 확정은 `Health.confirm_hp`.** (성장축) 누적 기준은 🔴 **실제로 깎인 HP**(`before - health.hp`) — 오버킬 기준이면 1HP 잔몹을 치명타로 때려 회복을 부풀린다. 데미지가 4~34 정수라 매 타격 절삭하면 6% 흡혈이 0이 되므로 소수를 쌓아 1 이상일 때 회복한다(GDD §6). 상한 max_hp·사망 공격자 제외·`peer_left` 정리. 잔량을 게스트가 들면 회복 확정이 두 곳이 되어 §1 위반 — **새 메시지 0개**(php 재사용).
- 🔴 **EXP 확정 = 호스트 + `G_EXP`, 적립은 `GameState.add_exp`(계열 필터).** (성장축) 발화 조건 = `def.exp > 0 and not def.respawns`. 신뢰 경계는 `from_id == HOST_ID`. **레벨은 저장하지 않고 EXP에서 파생**(`level_for_exp`) — 둘을 다 저장하면 어긋남이 곧 클라 간 스탯 발산이다. ⚠ **stage_token 가드를 붙이지 않는다** — G_DROP과 의도적으로 다르다(EXP는 비공간적이고, 씬 전환 창에 도착한 지급을 버리는 것이 곧 레벨 발산 = 고치려는 문제 자체). 치명 표시는 `Health.last_crit`(emit 직전 반드시 덮어쓴다) → 피격 글루 → `combat_impact(..., crit)`이고, 게스트는 `G_ENEMY_HP "cr"`로만 안다 — **표시 쪽에서 치명을 다시 굴리는 코드 금지**.
- 🔴 **네트워크 메시지 스키마 = `src/core/net_schema.gd`.** 메시지 타입 상수·페이로드 구조는 여기 한 곳. 호스트/게스트가 각자 문자열 리터럴로 메시지를 만들면 갈라진다.
- 🔴 **씬 전환 좌표 검증 = `GameState.is_valid_stage()`.** 호스트 송신 전(scene_flow.request_stage)과 게스트 G_SCENE 수신이 같은 함수를 지난다 — 챕터 id는 data/chapters 스캔 allowlist, 인덱스는 ChapterDef 범위. **스테이지 씬 경로는 절대 네트워크로 받지 않는다** — 로컬 .tres에서만 리졸브 (임의 load 경로 조작 차단).
- 🔴 **상태 확정 권한 = 호스트 (§1).** 데미지 적용·드랍 생성·클리어/전멸 판정·스테이지 전환·부활은 호스트 코드 경로에서만 확정한다. 게스트 로컬에서 상태를 "일단 적용"하는 코드 금지 (히트 이펙트 등 연출 예측은 허용). ⚠ 위치는 각자 소유(스파이크 확정)지만, **데미지/판정을 도입하는 시점부터 호스트는 게스트가 보낸 입력의 범위(이동 거리·공격 사거리·쿨다운)를 검증해야 한다** — 무검증 신뢰는 스파이크까지만.

## 4. "새 X = 파일 한 장" (데이터 주도)

새 콘텐츠가 "코드 수정 없이 .tres 한 장"으로 떨어지도록 설계한다. 스키마(각 .tres의 커스텀 Resource 클래스)는 `src/core/`에 두고 리드가 관리한다.

- 새 적/엘리트 = `data/enemies/*.tres` (`EnemyDef` — 스탯·스프라이트·드랍 테이블·단일 패턴 파라미터)
- 새 보스 = `data/enemies/*.tres` (`BossDef extends EnemyDef` — EnemyDef 상속으로 max_hp·drop_table·body_radius·sprite·frames 그대로 물려받아 CombatAuthority/DropAuthority가 캐스트 없이 동작 + 고유 `patterns: Array[BossPatternDef]`·페이즈·늪 파라미터. 각 패턴 = 인라인 `BossPatternDef` sub_resource: `shape`(circle/cone)·`telegraph_s`·`damage`·`range`·`half_angle`·`cooldown_s`(재선택 게이트)·`recover_s`(STRIKE 후 짧은 경직 — 쿨다운과 분리해야 공격 사이 "빈틈" 안 생김)·`priority`(선택 우선순위 — 거리별 역할 분리, 높은 게 우선)·거리/페이즈 게이트(`use_min/max_dist`·`min_phase`)·`creates_swamp`·`burst_count`). 스키마 = `src/core/boss_def.gd`·`boss_pattern_def.gd`(리드 전용, class_name). "새 보스 = 파일 한 장"
- 새 장비 = `data/equipment/*.tres` (부위·기본 수치·강화 곡선) — 장비는 수치만 (GDD §6 확정). ⚠ **`job_id`가 빈(범용) 장비를 처음 추가할 때**(방어구가 그 첫 사례가 된다) `test_game_state_auto`의 "직업 전환: 범용 장비는 유지" 케이스를 확인해라 — 현재 `data/equipment` 4장이 전부 귀속 장비라, 재검증을 "전부 해제"로 망가뜨려도 합성 `EquipDef`를 겨눈 그 케이스가 없으면 스위트가 그린이다(= 마을 갈 때마다 방어구가 벗겨지는데 초록불)
- 새 무기 비주얼 = `assets/sprites/weapons/<id>.png`(+aseprite 소스) + `EquipDef`(`weapon_texture`·`weapon_grip`·`weapon_hold_dist` — 큰 무기는 크게 잡아 몸과 안 겹치게) + `attack_range` 시각 정합(§3). 텍스처 규격 = 우향(+x) 수평·그립 픽셀 명시(projectb-art 참조). 조준 회전·플립·상하 가림·구르기/사망 숨김·원격 조준각·스팸 가드는 **player.gd 공용 경로가 자동 처리** — 무기별로 다시 만들지 마라
- 새 발사형(원거리) 무기 = `EquipDef.motion_type="shoot"` + `arrow_range`(사거리) 한 장. 탄 스폰·호스트 판정·G_SHOOT·표시 탄은 **shoot 공용 경로(player `_fire_projectile`·arrow_field·combat_authority)가 자동 처리** (§3 투사체 계약) — 새 활/석궁은 .tres만. 탄 겉모습·속도를 바꾸려면 `projectile_texture`/`projectile_speed`/`projectile_spin`(전부 무기 id로 각 클라가 리졸브). ⚠ 스윙형 손맛 필드(swing_*)는 shoot에서 무시됨, `swing_sfx`만 발사음으로 재활용
- 🎨 **폭발 텍스처는 중립(그레이스케일)로 그리고 원소색은 `EquipDef.swing_color`로 입힌다** (2026-07-24). `assets/sprites/fx/blast.png`는 흰~회색 그라데(중심 255 → 바깥 150)이고, 무속성 지팡이는 `swing_color = (0.88, 0.93, 1)`로 은백이 된다 — 이후 불/얼음 지팡이는 **텍스처 재사용 + 색 한 줄**(불 `(1, 0.55, 0.22)` 등). ⚠ 반대로 **투사체 텍스처(`projectile_texture`)는 제 색으로 그린다**: 탄에는 틴트를 안 곱한다(곱하면 탁해짐). 차지 오브도 탄 텍스처를 그대로 쓴다. ⚠ **초보 장비에 속성·화려함을 얹지 마라**(사용자 확정 2026-07-24) — 첫 지팡이는 무속성·무색 수정이다. 속성(불·얼음)은 상위 무기의 차별점으로 남긴다.
- 새 차지형(기 모아 범위 폭발) 무기 = `motion_type="charge"` + `charge_step_time`(단계 시간)·`blast_radius`(0단계 폭발 반경)·`projectile_*` 한 장. 차지 입력·단계 오브·감속·폭발 판정·폭발 FX/소리는 **charge 공용 경로가 자동 처리** (§3 차지 계약) — 단계 수와 위력/반경 배율은 무기가 아니라 CombatMath 공용 표다(무기별로 배율을 갈라야 하면 그때 EquipDef로 이관하고 §3을 갱신). `charge_sfx`(단계 상승음)·`blast_sfx`(폭발음)도 데이터
- 새 재료 = `data/materials/*.tres`
- 새 제작 레시피 = `data/recipes/*.tres` (재료 목록 → 결과 장비)
- 새 직업 = `data/jobs/*.tres` (기본 스탯·스킬 구성) — 궁수/법사 스트레치가 파일 추가로 떨어지게
- 새 챕터 = `data/chapters/*.tres` (ChapterDef — 칸 목록 = 스테이지 씬 경로 순서, 모닥불 칸은 `campfire.tscn`을 끼워 넣기, **파일명이 campfire로 시작하면 휴식 칸**(is_rest 관례), 마지막 칸 = 보스) — 챕터2 스트레치가 파일 한 장이 되게
- 모닥불 수치 = `data/campfire/*.tres` (CampfireDef — 회복량·간격·앉기 반경. 값은 GDD §11 TBD, 사용자가 조인다)
- 새 소리 = `assets/audio/sfx/<id>.wav` (파일명 = id 관례)
- 🔴 **에셋 참조 경계 = 게임은 `.png`/`.wav`/`.tres`만 본다. 원본 편집 파일(`.aseprite`·`.psd`·`.blend`)은 소스일 뿐 참조 대상이 아니다.** (2026-07-26) `.aseprite`를 SpriteFrames로 바로 읽어주는 임포터 애드온이 있지만 **쓰지 마라** — 그 임포터는 Aseprite 프로그램을 외부 실행하고, 실행 경로가 **EditorSettings(각 PC 로컬, 커밋 불가)** 라서 **만든 사람 PC에서만 동작한다.** 애니 정의는 `assets/sprites/<모듈>/<id>_frames.tres`로 커밋한다(기준 = `croc_boss_frames.tres`). 이 경계는 "클론만으로 익스포트 가능"(CLAUDE.md)을 지키는 조건이다 — 심사위원이 Aseprite를 설치·설정할 일은 없다.
- 새 하위 직업 = `data/subjobs/*.tres` 한 장 (`SubJobDef` — 계열(`series_id`, `"*"` = 공유)·순서(`order`)·해금 레벨·5스탯 레벨당 스텝·**자리별 특성 2개**(`main_trait_*`/`sub_trait_*`)). 스프라이트·무기·모션 불필요(GDD §5). ⚠ **총 화력 예산은 "상위 3개"가 정한다** — v2.0에서 장착 슬롯(메인 1 + 서브 2)이 고정되면서 개수에 비례한 전면 재역산은 사라졌지만, 새 하위 직업이 어떤 키에서 **기존 상위 3위 안에 들면 그 키를 다시 본다**. 상한 공식 = `GameState.max_level_stats()`(계열 최강 1개 + 계열 잔여·공유를 합친 풀의 상위 `SUB_SLOT_COUNT`개 × `SUB_JOB_WEIGHT`)가 GDD §6 목표(치명 20%·치명피해 50%·공속 25%·이속 15%·피흡 6%) 이하. **`test_game_state_auto`의 예산 트립와이어가 이걸 지킨다**(현 5개 체제 실측: 0.195/0.470/0.225/0.140/0.059). 🔒 **공유 하위 직업은 서브 전용** — `SubJobDef.trait_at(true)`가 구조로 막는다(데이터에 메인 특성을 적어도 안 켜진다).
- ⚠ **새 효과 키가 필요한 하위 직업은 "파일 한 장"이 아니다** (GDD v2.0). 키는 판정·표시·공지 경로를 함께 건드린다 — 검기 파형(사거리)·곡예(구르기 쿨)가 그 예다(§3 특성 계약). **기존 키 재사용은 순수 데이터**다. 새 키를 만들 땐 §2 게이트를 먼저 본다.
- 새 적의 EXP = `EnemyDef.exp` 한 칸 (`BossDef`가 상속). 0 = EXP 없음. ⚠ `respawns=true`는 값과 무관하게 코드가 제외한다(§5 무한 파밍 함정).
- 계열 EXP 페이싱 = `JobDef.exp_curve` (레벨 n 도달 **누적** 요구치 배열, 비면 `CombatMath.default_exp_curve()` 폴백)

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
- 🔴 **화면 덮는 Control의 `mouse_filter` — UI 1번 함정**: 기본값 STOP이 그 아래 클릭을 다 먹어 발사·상호작용이 통째로 죽는다 → 배경/장식 오버레이는 `mouse_filter = 2`(IGNORE), 모달 뒷판(뒤 게임 클릭을 **막아야** 하는 것)은 STOP이 맞다. **헤드리스가 절대 못 잡는다**(에러도 경고도 없고 스위트는 그린) → `projectb-verify` 참조.
  - 🔴 **Control만의 문제가 아니다 — 월드 씬의 `Label`도 그 아래 게임 클릭을 먹는다** (2026-07-26 실제 버그: 보스전 480px 밴드·마을 3개·모닥불 2개의 안내 Label이 클릭을 삼켰다). 월드에 안내문·표지를 놓을 때도 `mouse_filter = 2`를 적어라.
  - **모달 규약**: 열리면 `GameState.ui_modal_open = true`(또는 EventBus 시그널) → player·caster가 폴링/구독해 멎는다. ⚠ **닫힌 invisible Control도 `_unhandled_input`을 받는다**(자기토글 숨은 패널이 그 원리) — 대신 닫히면 `visible=false`라 클릭이 그 아래로 샌다.
  - **토글 키는 한 곳에서만 소비한다** — I키 인벤은 **HUD가 키를 먹고** 패널은 안 먹는다(양쪽이 다 처리하면 열자마자 닫힌다). 새 토글 키를 붙일 땐 소비 주체를 하나로 정하고 보고한다.
  - **새 패널은 가장 가까운 기존 패널을 복제·확장한다 — 표준은 이미 있다.** 모달 규약 준거 = `src/ui/craft_panel`(마을 제작대), 그것을 복제해 만든 것이 `src/ui/inventory_panel`(I키)·`src/ui/subjob_panel`(훈련소). 스타일은 `ui_theme` 단일 소스(2026-07-26 도입) — 패널마다 `theme_override_*`를 흩뿌리면 다음 톤 조정이 전수 수정이 된다. 레이아웃은 컨테이너 주도(VBox·HBox·Grid·Margin), 코드에 `position`/`size` 매직넘버 금지(게임 내 오버레이 = 피해 숫자·조준선은 예외).
  - **확인법**: 에디터로 실게임을 띄워 `viewport.push_input(InputEventMouseButton)`으로 0회→1회. 액션 주입·헤드리스 push_input은 이 버그를 못 잡는다.
- 🔴 **4방향 애니 명명이 틀리면 코드가 2방향으로 조용히 폴백한다**: 명명 = `<base>_e` / `<base>_s` / `<base>_n`(서쪽은 `_e`를 flip). 시트나 태그가 없으면 **에러가 아니라 폴백**이라 "왜 4방향이 아니지"만 남는다(`.tscn`의 `autoplay="idle"` 같은 옛 이름이 새 명명과 어긋나 실제로 폴백됐다).
  - **애니 클립을 손대면 `play("...")`·`autoplay`를 grep해 이름 집합을 대조해라** — 프레임 구성을 바꿔 이름이 사라지면 그 애니는 **조용히 안 나온다**(보스 리드로우 때 `walk`/`slam`/`spray`가 빠져 있었다).
  - **노드 선택**: `AnimatedSprite2D` = 시트 프레임 애니(기본) · `AnimationPlayer` = 고정 시퀀스 원샷(피격 흠칫) · `Tween` = 코드 프로퍼티 모션(손맛 juice) · `AnimationTree`는 **블렌딩·전이가 정말 필요할 때만**(2D 스프라이트 게임은 대개 불필요, IK·리타깃팅은 3D용이라 안 쓴다).
  - 🔴 **애니 FSM ≠ 게임플레이 FSM**: 클립→클립 전이만 애니 쪽이고, Idle→Combat→Dead 같은 게임 상태는 `state-machine`으로 짜서 애니를 **구동**한다 — 애니 노드 안에 게임 로직을 넣지 마라.
- 🔴 **씬끼리 PackedScene 순환 preload 금지**: A⇄B 순환 preload는 껍데기 노드를 만들어 전환이 깨진다. `@export_file` 경로 + `change_scene_to_file`을 써라. 헤드리스는 못 잡고 실게임 부팅에서만 드러난다.
- 🔴 **저장 초기화 착각**: 세이브 파일만 지우고 오토로드(GameState 등) 메모리를 안 지우면, 옛 상태가 메모리에 남아 다음 저장에 도로 써진다. "새로하기"는 파일 삭제가 아니라 오토로드 상태 리셋까지 해야 한다.
- 🔴 **씬 스왑 프레임엔 이전 씬 노드가 그룹에 남아 있다**: main의 `queue_free`는 프레임 끝에 실행되므로, 새 씬의 첫 프레임 그룹 스캔("player" 등)에 이전 씬 노드(게이트 앞 좌표)가 걸린다. 잔몹 AI가 이 유령에 어그로를 물고 영구 추격했다(챕터1 실기에서 발견 — 간헐 레이스, CHASE 리시 `LEASH_MULT`로 수정). 그룹 스캔 기반 AI/시스템은 첫 프레임 결과를 못 믿는다 — 리시·거리 재확인·지연 스캔 중 하나를 넣어라.
- 🔴 **배경 타일 스프라이트는 `z_index = -10`**: 잔몹 텔레그래프가 z=-1이라 바닥을 z 0으로 깔면 텔레그래프가 **조용히** 가려진다 (test_stage엔 바닥이 없어서 안 드러났던 함정 — 챕터1 스테이지에서 발견). 무기(z 0 이상 유지)와 함께 z 배치:

  | z | 층 | 비고 |
  |---|---|---|
  | -10 | 바닥 타일 · **바닥 변주 타일**(`ground_variant`) | 변주는 바닥과 같은 층이라 **씬 트리에서 Ground 다음 형제**여야 위로 그려진다 |
  | -9 | **바닥 디테일 스캐터**(`ground_detail`) · 늪(`swamp_zone`) | ⚠ 둘이 같은 층이다 — **늪이 있는 씬(보스방)에는 스캐터를 뿌리지 마라**(흙 무늬가 늪 위에 뜬 것처럼 보인다) |
  | -3 | **흔들리는 폴리지**(`foliage`) | 캐릭터가 항상 풀 위로 그려진다(뒤에 숨는 연출은 포기 — y_sort를 안 쓰고 층을 고정한 것은 텔레그래프 가림을 확실히 피하려는 선택) |
  | -2 | **접지 그림자**(플레이어·잔몹·보스) | 2026-07-26에 -1에서 내렸다 — 텔레그래프와 같은 층이면 **다른 부모 간 순서가 불확정**이라 그림자가 예고를 가릴 수 있었다 |
  | -1 | 잔몹/보스 텔레그래프 | |
  | 0+ | 몸 · 무기 · FX | 무기는 음수로 내리지 마라(배경 밑으로 꺼져 통째로 사라진다) |
- 🔴 **자식 컴포넌트의 `_ready`에서 `get_parent().add_child()` 금지**: 그 시점 부모는 아직 자식 셋업 중이라 "Parent node is busy setting up children"으로 실패한다 — 웹 실기에선 에러가 콘솔에 묻혀 "노드가 조용히 없음"으로만 보인다(마을 스폰에서 실제 발생). 스폰류 초기화는 `call_deferred`로 한 프레임 미뤄라 (`peer_sync.gd _initial_spawn` 패턴). 씬 루트 스크립트의 `_ready`에서 자기 자신에게 add_child는 안전하다.

- 🔴 **"내 PC에서만 되는 것"은 만든 사람이 절대 못 본다 — 원본 편집 파일을 게임 리소스로 참조** (2026-07-26 실제 사고): `data/enemies/wraith_boss.tres`가 `boss_wraith.aseprite`를 SpriteFrames로 직접 참조했다. 그걸 읽는 임포터는 **Aseprite를 외부 실행**하고 그 경로는 **EditorSettings(각 PC 로컬)** 라 커밋되지 않는다 → 작성자 PC에선 완벽히 동작하고, 다른 PC에선 `Parse Error: [ext_resource] referenced non-existent resource` → **그 def를 쓰는 씬이 통째로 로드 실패**(챕터1 보스전이 안 떴다).
  - ⚠ **웹 익스포트가 `exit 0`으로 통과한다** — 실패는 로그의 ERROR 줄에만 남는다. **"익스포트 성공"을 리소스 무결성의 근거로 쓰지 마라.** 확인법 = `ResourceLoader.load("res://data/…")`가 null이 아닌지 직접 보기.
  - ⚠ **대체 리소스가 있어도 낡았을 수 있다** — 이 사고에서 PNG 기반 `boss_wraith_frames.tres`가 남아 있었지만 애니가 4종뿐이고 엔진이 부르는 `walk`/`slam`/`spray`가 빠져 있었다(리드로우 때 원본으로만 추가됨). 스왑 전에 **애니 이름 집합을 엔진 호출부와 대조**해라.
  - 같은 부류: 절대 경로(`C:\…`), 커밋 안 된 `.import` 사이드카, 로컬에만 설치된 애드온·도구. 예방 = §4 에셋 참조 경계 + `projectb-reviewer` 2.7단계 이식성 점검.

**Project_B 고유 (웹·멀티):**

- 🔴 **`-s` 헤드리스에선 오토로드 전역 식별자가 컴파일되지 않는다**: `-s` 테스트가 (직간접) preload하는 스크립트가 `EventBus`/`Net` 같은 전역 이름을 쓰면 "Identifier not found"로 통째로 컴파일 실패한다. **헤드리스로 테스트할 로직(core·net)은 `/root` 경로 + class_name 타입으로 접근해라** (예: net.gd의 `_bus()` 헬퍼 → `EventBusHub`). 실게임 전용 씬 스크립트(player/stage/ui/main)는 전역 이름을 그대로 써도 된다.

- 🔴 **웹 오디오 autoplay**: 첫 사용자 입력 전에는 소리가 안 난다(브라우저 정책) — 에러 없이 무음. 온보딩 첫 입력 이후에 BGM 시작.
- 🔴 **웹에서 스레드 금지**: `Thread`/`WorkerThreadPool`은 기본 웹 익스포트에서 안 돈다(COOP/COEP 헤더 필요). 에디터·데스크톱에선 돌아서 **웹 빌드에서만** 깨진다 — 애초에 쓰지 마라. 성능 처방으로도 쓰지 마라(`thread_support=false`).
- 🔴 **에디터·데스크톱 프로파일은 웹과 다르다**: WASM 단일 스레드에서만 드러나는 히치가 있다 — 실제로 발사마다 `.tres`를 재파싱해 **웹에서만** 끊겼고 캐시로 해소했다. **에디터 수치로 "괜찮다"고 결론 내지 마라.**
- 🔴 **"렉이 있다" 신고를 렌더 문제로 가정하지 마라 — HUD 세 값으로 먼저 가른다**: 방 코드 줄에 **핑 · 경로(직결/릴레이) · FPS**가 이미 표시된다. FPS가 멀쩡한데 굼뜨면 **네트워크**, 핑이 낮은데 굼뜨면 **렌더/스크립트**, 경로가 "릴레이"면 **P2P 협상 실패**(핑 숫자만으로는 못 읽는다). 지연은 추측 말고 `tests/measure_latency.gd`로 재고(실행법 = `projectb-verify` §1), ⚠ 릴레이 왕복은 시점에 따라 140~215ms를 오가니 **한 번 재고 결론 내지 마라** — 같은 시간대 A/B로 재라. 프로파일러 없이 최적화하지 마라(리드에게 캡처 요청 — `mcp__godot`는 리드 담당). C#을 안 쓰니 **GC 압박 경로는 해당 없음** — 끊김이면 물리(적 수)·스크립트 핫루프·드로우콜을 먼저 본다.
  - 🔵 **미해결 단서:** 실기 핑 282ms vs 헤드리스 계측 207ms의 차 **~75ms가 설명되지 않았다.** 가설 = 소켓 poll이 렌더 프레임에 묶인 **클라이언트 프레임 지연**(P2P로도 안 없어졌다). FPS 실측 + 프레임 타임 분포가 첫 단서다.
- 🔴 **셰이더는 Compatibility 렌더러 기준이다**: 데스크톱 Forward+에서만 되는 기능(일부 스크린 텍스처·고급 블렌드)은 **웹에서만 조용히 다르게 나온다** — 에디터에서 예쁘다고 끝이 아니다. 🔴 **효과가 끝나면 머티리얼을 떼라(`sprite.material = null`)** — 웹 Compatibility에서 평상시 셰이더가 걸려 있으면 `amount = 0`이 **항등이 아니어서** "한 대 맞고 색이 안 돌아옴"이 된다(`src/feel/hit_flash.gd`가 준거, §2). 상시 부착 셰이더를 제안하려면 이 항등성부터 확인한다. 셰이더 외형은 헤드리스가 못 잡으니 실게임 스샷이 필요하다.
- 🔴 **저장 검증은 브라우저에서**: `user://`는 웹에서 IndexedDB다. 에디터에서 저장이 돌아도 웹 빌드에서 새로고침 후 남는지 따로 확인해야 한다.
- 🔴 **호스트/게스트 씬 트리 불일치**: RPC·동기화는 양쪽에 같은 경로의 노드가 있어야 도착한다. 스폰 순서가 어긋나면 조용히 유실 — **스폰은 호스트가 지시하고 게스트가 따라 만든다** (게스트 단독 스폰 금지).
- 🔴 **Net이 소비하는 메시지 이름은 기존 kind와 겹치면 안 된다**: `net_msg`로 안 올리고 Net이 가로채는 메시지(G_PING/G_PONG)에 흔한 이름을 쓰면 그 이름을 쓰던 곳이 **조용히 죽는다.** 실제로 `"ping"`/`"pong"`은 `tests/test_net_room_auto.gd`가 임의의 게임 메시지로 이미 쓰고 있어서 왕복 테스트가 통째로 깨졌다 → `"nping"`/`"npong"`으로 분리. **새 kind를 만들기 전에 `grep -rn '"이름"' src tests server`로 먼저 확인해라.**
- 🔴 **릴레이 지연은 DO 배치로 못 줄인다 — 이미 시도했다**(2026-07-24 실측): `locationHint: "apac"` + 새 DO 이름으로 아시아 배치를 시도했으나, 같은 시간대 교차 측정에서 구 DO 207/145/207ms · apac DO 214/–/152ms로 **차이 없음**. 릴레이 왕복은 시점에 따라 140~215ms를 오가며 그 변동이 위치 효과보다 크다(재배치 직후 83ms가 한 번 나왔지만 재현 안 됨 — 경로 운). 지연은 **게임 코드의 지연 보상**(§3)으로 다룬다. ⚠ DO 이름을 바꾸면 살아있던 방이 전부 사라지고, 최초 생성 중엔 create/join이 서로 다른 인스턴스에 붙어 `no_room`으로 실패한다.
- 🔴 **크롬은 백그라운드/가려진 탭을 프리즈한다**: 호스트 탭이 백그라운드로 가면 게임 루프·소켓 플러시까지 통째로 멈춰 **방 전체가 정지**하고, 깨어날 때 큐가 한꺼번에 처리된다(브라우저 실기 검증에서 확인). 실플레이(각자 기기·포커스 탭)에선 안 드러나지만, 한 PC 두 탭 테스트·호스트의 잠깐 탭 전환에서 드러난다. 대응 후보(미결): 호스트 이탈 감지 안내, 오디오 keepalive. 같은 PC 테스트 시엔 탭을 번갈아 활성화해 큐를 밀어줘야 한다. ⚠ 원격 릴레이(Workers)는 **3분 무수신 시 좀비로 간주해 연결을 끊는다** — 프리즈된 호스트 탭은 3분 뒤 방 종료로 정리된다 (실기 디버깅 때 "3분 뒤 로비로 튕김"은 이 정상 동작).
- 🔴 **"3분 뒤 튕김"이 이제는 정상 동작이 아닐 수도 있다 — 릴레이 유휴 스윕 × 직결 무트래픽** (P2P 도입 2026-07-26, 리뷰 C1): 릴레이 Worker의 좀비 판정은 `seen`(**그 클라가 릴레이로 보낸** 마지막 시각) 기준인데, P2P가 열리면 게임 트래픽이 전부 직결로 빠져 **릴레이로 나가는 프레임이 0이 된다** → 멀쩡히 플레이 중인 방이 3분마다 끊기고 로비로 튕기며 챕터 좌표·이월 HP까지 날아간다. 대응 = `Net._tick_relay_keepalive`(45초 주기 `G_KEEP`, **반드시 `_send`로 — `send_game`을 쓰면 직결로 나가 목적을 정확히 배반한다**). ⚠ **로컬 릴레이(`server/relay/relay.gd`)엔 유휴 스윕이 자체가 없어 `dev_local.sh`로는 영원히 재현되지 않는다 — 배포본에서만 터진다.** 위 줄의 "정상 동작"과 헷갈리면 상시 버그를 방치하게 된다. 주기를 바꿀 땐 `index.js`의 `IDLE_LIMIT_MS`/`SEEN_WRITE_MS`와 미러이며 `test_net_transport_auto`가 부등식을 지킨다.
- 🔴 **세이브는 직업을 담지 않는다 — `from_save_dict` 시점의 `selected_job_id`는 항상 기본 직업(warrior)이다** (2026-07-26 리뷰 I-1). `SaveManager._ready`가 로비보다 **먼저** 돌기 때문이다. 그래서 로드 시점에 직업 기준 필터를 **파괴적으로** 걸면 정당한 장비가 조용히 벗겨진다 — 법사가 제작한 상위 지팡이가 부팅 때마다 해제되고, 마을 진입의 `grant_starting_loadout`은 **시작 무기만** 채우므로 그대로 다운그레이드된 채 판에 들어간다(에러 없음). 로드는 **비파괴 + 사용/확정 시점 필터**가 규약이다 — 하위 직업 슬롯 로드가 이미 같은 결정을 주석으로 남겨 뒀는데 장비 쪽이 한 번 반대로 밟았다. 직업 기준 필터는 `apply_job_loadout()`(직업 확정 경계)만 건다(§3).
- 🔴 **`SAVE_VERSION`을 올리면 배포본 세이브가 전부 조용히 무시된다** (`save_manager.gd`가 **정확일치** 검사). 성장축처럼 필드를 추가할 때는 **버전 유지 + "키 없음 = 기본값" 폴백**으로만 한다(구 세이브는 레벨 0으로 읽힌다). `test_save_manager_auto`에 `SAVE_VERSION == 1` 트립와이어가 있다 — 올리면 빨개지고 이유를 읽게 된다.
- 🔴 **허수아비(`respawns=true`)는 무한 EXP 파밍 구멍이다** — `_check_clear`가 클리어 조건에서 제외하듯 **EXP도 코드로 제외**해야 한다(`exp_authority`). 데이터 값을 0으로 두는 것에 의존하지 마라(다음 사람이 값을 넣는다). 안 막으면 에러 없이 만레벨.
- 🔴 **원격 스윙 창을 그 피어의 공속으로 스케일하지 않으면** 창-잠금 가드(`player.play_attack_fx`)가 정당한 연속 공격을 삼켜 **"원격에서 스윙이 안 보인다"만** 나타난다 — 데미지는 정상이라 원인이 화면에 안 드러난다. `_refresh_growth_derived()`가 base(무기)×haste로 파생하는 이유다.
- 🔴 **이속 보너스를 원격 위치 clamp에 반영하지 않으면 지연 보상이 부분 퇴행한다** — 정당한 속도가 깎여 외삽이 과소평가되고 "피했는데 맞았다"가 빠른 피어에게 재발한다(2026-07-24에 고친 그 버그). §3 이동속도 계약 참조.
- 🔴 **`Health.last_crit`은 사이드채널이다** — `apply_damage`/`set_hp_display`는 **emit 직전에 반드시** 값을 덮어써야 하고, 회복·부활 경로(`confirm_hp`)는 false로 지운다. 안 덮으면 다음 평타가 이전 치명 강조를 물려받는다(에러 없음, 화면만 거짓).
- 🔴 **딕셔너리 직접 인덱싱은 뮤테이션 검출력을 0으로 만든다** (2026-07-25 실제로 겪음): 테스트가 `dict["key"]`로 읽으면, 그 키를 만드는 코드를 지우는 뮤테이션에서 **SCRIPT ERROR로 테스트가 통째로 죽어** `FAIL` 0건 = 통과처럼 보인다(verify §3 침묵 통과). 테스트에서는 `dict.get("key", 폴백)`으로 읽어 **명확히 FAIL**하게 해라.
- **웹 실기 자동 검증 = 디버그 브리지**: 브라우저 자동화는 합성 키를 Godot에 못 꽂는다(신뢰 이벤트만 수신, 홀드 불가). `?debug=1`일 때만 열린다(`src/core/debug_bridge.gd`): `window.pb_press/pb_release(액션)`(InputEventAction — _unhandled_input·폴링 둘 다 구동) · `window.pb_dump()`(방·플레이어 좌표·적 HP를 console에 `[PB]` JSON으로). 로컬 입력 시뮬레이션/관측일 뿐 신뢰 경계(§3)는 그대로. ⚠ 같은 프레임에 press+release가 붙으면 액션이 소실될 수 있다 — 자동화에선 press만 보내고 다음 프레임 이후 release. ⚠ 가려진(occluded) 창은 활성 탭도 rAF가 멈춘다 — 캡처(스크린샷/줌)가 프레임을 1개씩 강제로 굴리므로, 프리즈 상태에선 "입력 → 캡처(프레임) → 검증" 순으로 진행.

## 6. 위임 라우팅 (리드용) — 에이전트 5종 (2026-07-26 재편)

- **기획은 에이전트가 아니라 파이프라인이다** — ① 브레인스토밍 = **메인 세션에서 리드+사용자 대화**(위임하면 대화가 한 겹 끊긴다) → ② 점검 = **`projectb-critic`**(방법론 = `projectb-plancheck`) → ③ 문서화 = 리드가 **`projectb-gdd` 스킬**로, 🔒 사용자 승인 후 → ④ 구현 = `projectb-dev`. 정본 = `docs/GDD.md`.
- **구현 = `projectb-dev`** — GDScript 구현 + **설계·UI·애니 배선·셰이더·성능 진단까지 이 한 곳**(2026-07-26에 5종을 흡수했다). 큰 기능은 코드 전에 설계 스케치를 먼저 낸다.
- **코드 리뷰 = `projectb-reviewer`** — 품질·하드 계약·이식성 게이트.
- 🔴 **네트워크 리뷰 = `projectb-netreview`** — 전송 경계·호스트 권한·신뢰 경계·채널 분류. **네트워크에 닿는 코드는 예외 없이 이 리뷰를 거친다**(웹 게임이라 상시 필수).
- **에셋(도트) = `projectb-art`** — ⚠ 규격 정본이 미정이라 **합의 전 신규 스프라이트 착수 금지**.
- **언제 직접 하나**: core 스키마 변경, `mcp__godot` 필요 작업, `--import`, git 커밋, 회귀 위험이 큰 tight 검증 루프.
- 위임해도 검증·`--import`·커밋은 리드가 직접(→ `projectb-verify`).
**에이전트는 이 5종뿐이다: `critic` · `dev` · `reviewer` · `netreview` · `art`.**

- ⚠ **삭제된 에이전트 (2026-07-26): planner · architect · ui · animator · shader · profiler · tools.** 없어진 이름을 부르지 말고 위 5종으로 보내라. 고유 지식은 잃지 않았다 — GDD 작성 규율은 **`projectb-gdd` 스킬**로(기획은 사용자와의 대화가 본질이라 에이전트가 아니라 스킬이 맞다), 설계 규율은 `projectb-dev`로, UI 모달·4방향 애니·셰이더·웹 프로파일 함정은 **§5**로 이관했다. 필요가 다시 커지면 그때 되살린다(에디터 툴은 `@tool`·`EditorPlugin`이 0개라 도메인 자체가 없다).
