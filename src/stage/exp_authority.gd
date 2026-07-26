extends Node
# EXP 지급 권한 컴포넌트 — 호스트가 확정하고 전원에게 지급한다 (rules §1·§3, 성장축 GDD v1.8).
# 전투 스테이지가 DropAuthority 형제로 문다. 결정만 한다 — 적립·레벨 파생은 GameState.
#
# 🔴 **왜 호스트 확정인가 (각 클라가 킬을 세면 안 되는 이유):** 레벨은 저장되고 G_STATS(스탯 공지)의
#   근거이며, 그 공지가 호스트 판정의 입력이다. 클라 간 레벨이 1 벌어지면 게스트는 자기 공속을 더 높게
#   믿고 공격하는데 호스트는 더 긴 쿨다운으로 검증해 **정당한 타격이 간헐 거부**된다 — 증상이
#   "가끔 안 맞는다"로만 나타나는 조용한 발산이다. 지급을 단일 발화로 만들면 그 클래스가 사라진다.
#
# ⚠ **stage_token("s") 가드를 의도적으로 붙이지 않는다** — G_DROP/G_SWAMP와 다르다(net_schema G_EXP 주석).
#   토큰 가드는 "다른 칸에 유령 오브젝트가 생기는 것"을 막는 장치인데 EXP는 비공간적이고, 씬 전환 창에
#   도착한 지급을 버리면 그게 곧 클라 간 레벨 발산(= 고치려는 문제 자체)이다.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.exp_granted_local.connect(_apply)  # 호스트 자기 지급 경로 (drop_spawn_local 미러)
	EventBus.net_msg.connect(_on_net_msg)


# 호스트 전용 — 킬 확정(CombatAuthority hp<=0) 시 파티 전원에게 동일 지급.
# 관전 중 사망자도 받는다 = 방 브로드캐스트라 자동 (GDD §6: "죽으면 손해"를 이중으로 만들지 않는다).
# 🔴 respawns(허수아비 dummy)는 제외 — 무한 재생성이라 반복 킬로 조용히 만레벨이 된다(rules §5 함정).
func _on_enemy_killed(_eid: String, def: EnemyDef, _world_pos: Vector2) -> void:
	if not Net.is_host() or def == null:
		return
	if def.exp <= 0 or def.respawns:
		return
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_EXP, "e": def.exp})
	EventBus.exp_granted_local.emit(def.exp)  # 호스트는 자기 브로드캐스트를 릴레이로 못 받는다


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if str(data.get(NetSchema.KEY_KIND, "")) != NetSchema.G_EXP:
		return
	if from_id != NetSchema.HOST_ID:
		return  # 신뢰 경계 — 호스트 발신만 신뢰 (ehp/php 관용구). 게스트가 EXP를 자가 지급할 수 없다
	_apply(int(data.get("e", 0)))


# 적립 — 계열 공용 풀(GameState.add_exp)로 보유 하위 직업 전부에 동일 적립.
# 레벨/해금이 변하면 GameState가 growth_changed를 emit하고 PeerSync가 스탯을 재공지한다.
func _apply(amount: int) -> void:
	if amount <= 0:
		return
	GameState.add_exp(amount)
