class_name EventBusHub
extends Node
# 모듈 간 유일 통신로 (projectb-rules §0·§1). 시그널 추가는 리드가 한다.
# class_name(core·리드 전용)을 두는 이유: -s 헤드리스 테스트에선 오토로드 전역 식별자가
# 컴파일되지 않으므로, 테스트 대상 스크립트는 /root 경로 + 이 타입으로 접근한다 (rules §5).
# 필드를 붙이는 쪽이 emit해야 한다 — 발신자 없는 시그널은 에러 없이 조용히 안 돈다.

# --- net (src/net/net.gd가 emit) ---
signal net_connected
signal net_connect_failed(reason: String)
signal net_disconnected
signal room_created(code: String)
signal room_joined(code: String, peer_ids: Array[int])
signal room_join_failed(reason: String)
signal room_closed
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal net_msg(from_id: int, data: Dictionary)
signal player_spawned(peer_id: int, player: Node)  # PeerSync가 스폰 완료(잡 반영 포함) 시 emit — 호스트의 이월 HP 확정(CombatAuthority) 등 스폰 후속 처리용

# --- flow (마을/스테이지가 emit, src/main이 씬 스왑) ---
signal scene_change(scene_id: String)  # 호스트 로컬 결정 또는 게스트의 G_SCENE 수신 후 emit — 스왑은 main만 한다

# --- combat (플레이어/적이 emit, 스테이지가 권한 처리) ---
signal attack_hit(enemy: Node, job: JobDef)     # 로컬 공격 판정이 적에 닿음(공격자 job 동봉) — 확정은 호스트 경로(stage)
signal enemy_hp_confirmed(eid: String, hp: int)  # 호스트 전용 emit(enemy 권한 경로/부활) — stage가 ehp 브로드캐스트
signal player_hp_confirmed(peer_id: int, hp: int)  # 확정 HP 통지 — 호스트=Health 권한 경로, 게스트=php 수신 경로. 호스트일 때만 stage가 php 브로드캐스트
signal mob_telegraph(eid: String, center: Vector2)  # 호스트 전용 emit(잔몹 AI WINDUP) — MobSync가 matk 브로드캐스트
signal mob_strike(eid: String, center: Vector2)     # 호스트 전용 emit(잔몹 AI STRIKE) — CombatAuthority가 데미지 확정

# --- stage flow (호스트=판정 시, 게스트=clear/wipe 수신 시 emit) ---
signal stage_cleared
signal stage_wiped

# --- feel (표시 전용 손맛 — 각 클라 로컬에서 emit·소비, 네트워크 아님) ---
# HP 감소 표시 경로(Health.hp_changed dropped=true)에서 피격 당사자 글루가 emit — 호스트/게스트
# 무관하게 각 클라가 자기 화면 연출(플래시·데미지 숫자·셰이크·SFX·히트스톱)을 재생한다.
# kind = "enemy"|"player" (누가 맞았나), world_pos = 피격 지점, amount = 감소량.
signal combat_impact(kind: String, world_pos: Vector2, amount: int)
signal screen_shake(strength: float)  # 명시적 셰이크 트리거 (사망·보스 슬램 등) — 카메라가 소비
# 소리/연출 트리거 (표시·소리 전용, 각 클라 로컬) — Audio가 SFX로, 필요시 연출이 구독.
signal player_swing(world_pos: Vector2)   # 플레이어 공격 스윙(로컬·원격 연출 시점)
signal player_roll(world_pos: Vector2)    # 플레이어 구르기 시작
signal entity_died(kind: String, world_pos: Vector2)  # kind = "enemy"|"player" — 사망 확정 표시

# --- 드랍/인벤 (드랍·제작 2026-07-23) ---
signal enemy_killed(eid: String, def: EnemyDef, world_pos: Vector2)  # 호스트 전용 emit(CombatAuthority, hp<=0 확정) — DropAuthority가 드랍 롤 트리거
signal drop_spawn_local(drops: Array)  # DropAuthority(호스트) → DropField 로컬 스폰 (호스트는 자기 G_DROP를 못 받으므로)
signal inventory_changed  # 골드/재료/장비/도면 변동 (각 클라 로컬) — HUD·제작/강화 패널 갱신
signal blueprint_unlocked(recipe_id: String)  # 도면 획득 확정 — "설계도 획득!" 배너 연출·제작 가용 갱신
# feel (표시 전용 — 네트워크 아님, rules §2)
signal item_dropped(kind: String, rarity: int, world_pos: Vector2)  # 드랍 등장 연출(착지 팝·등급 반짝임)
signal item_picked(kind: String, rarity: int, world_pos: Vector2)   # 픽업 연출(흡수 팝)
