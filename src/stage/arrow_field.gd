extends Node
# 표시 화살 관리 — 전투 씬(스테이지)이 자식 노드로 문다. 전 클라 공통(호스트·게스트 모두 화살을 본다).
# 발사마다(로컬 player_shoot·원격 G_SHOOT) 표시 화살을 스폰하고, 종료(G_ARROW_HIT·호스트 arrow_gone_local)에
# 맞춰 despawn한다. 명중 판정·데미지는 여기가 아니라 CombatAuthority(호스트) — 이 노드는 표시 전용(네트워크 송신 0).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).
# ⚠ 동적 스폰 등록(rules §2 게이트 정신): _ready 그룹 스캔 없음 — 발사 시점에만 _arrows에 등록/정리.

const NetSchema := preload("res://src/core/net_schema.gd")
const ArrowScene := preload("res://src/combat/arrow.tscn")
const CombatMathLib := preload("res://src/core/combat_math.gd")

var _arrows: Dictionary = {}  # aid(String) -> Arrow 노드 (조기 despawn용 — 자연 소멸은 tree_exited로 정리)


func _ready() -> void:
	EventBus.player_shoot.connect(_on_player_shoot)
	EventBus.arrow_gone_local.connect(_on_arrow_gone)
	EventBus.net_msg.connect(_on_net_msg)


# 로컬 발사 — 내 표시 화살 스폰 (shooter_id == Net.my_id, player가 G_SHOOT도 별도 송신)
func _on_player_shoot(_shooter_id: int, origin: Vector2, dir: Vector2, aid: String, arrow_range: float) -> void:
	_spawn(aid, origin, dir, arrow_range)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_SHOOT:
			# 원격 피어의 발사 — 표시 화살 스폰 (판정은 호스트 CombatAuthority가 별도). r = 사거리(수명 리졸브)
			_spawn(str(data.get("aid", "")),
				Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0))),
				Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0))),
				float(data.get("r", CombatMathLib.DEFAULT_ARROW_RANGE)))
		NetSchema.G_ARROW_HIT:
			if from_id != NetSchema.HOST_ID:
				return  # 화살 종료 확정은 호스트 발신만 신뢰 (rules §3)
			_despawn(str(data.get("aid", "")),
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))))


# 호스트 자신의 권한 화살 종료 — 자기 표시 화살 despawn (릴레이가 자기 G_ARROW_HIT를 안 돌려줌, drop_pick_local 미러)
func _on_arrow_gone(aid: String, world_pos: Vector2) -> void:
	_despawn(aid, world_pos)


func _spawn(aid: String, origin: Vector2, dir: Vector2, arrow_range: float) -> void:
	if aid.is_empty() or _arrows.has(aid):
		return
	var arrow := ArrowScene.instantiate() as Node2D
	_arrows[aid] = arrow
	arrow.tree_exited.connect(func() -> void: _arrows.erase(aid))  # 자연 소멸(수명 만료)도 맵 정리
	get_parent().add_child(arrow)  # 부모 = 스테이지 Node2D. 런타임 add_child라 안전 (rules §5 _ready 함정 무관)
	# 수명 = clamp(사거리)/속도 — 표시·호스트가 같은 값을 받아 결정론. (표시 화살은 clamp만, 검증은 호스트)
	arrow.setup(origin, dir, CombatMathLib.ARROW_SPEED, CombatMathLib.arrow_lifetime_s(arrow_range))


# impact_pos = 적중 지점(호스트 권한 좌표) — 슬라이스 3에서 임팩트 연출을 여기에 얹는다(현재 despawn만)
func _despawn(aid: String, _impact_pos: Vector2) -> void:
	var node_v: Variant = _arrows.get(aid)
	_arrows.erase(aid)
	if node_v != null and is_instance_valid(node_v):
		(node_v as Node).queue_free()
