extends Node
# 표시 투사체 관리 — 전투 씬(스테이지)이 자식 노드로 문다. 전 클라 공통(호스트·게스트 모두 탄을 본다).
# 발사마다(로컬 player_shoot·원격 G_SHOOT) 표시 투사체를 스폰하고, 종료(G_ARROW_HIT·호스트 arrow_gone_local)에
# 맞춰 despawn한다. 명중 판정·데미지는 여기가 아니라 CombatAuthority(호스트) — 이 노드는 표시 전용(네트워크 송신 0).
# 탄 겉모습·속도·수명·폭발 반경은 GameState.projectile_params(무기 id allowlist 리졸브) 단일 소스 —
# 호스트 판정도 같은 함수를 부르므로 "맞는 곳=보이는 곳"이 유지된다 (rules §3).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).
# ⚠ 동적 스폰 등록(rules §2 게이트 정신): _ready 그룹 스캔 없음 — 발사 시점에만 _arrows에 등록/정리.

const NetSchema := preload("res://src/core/net_schema.gd")
const ArrowScene := preload("res://src/combat/arrow.tscn")
const BlastScene := preload("res://src/combat/blast.tscn")
const CombatMathLib := preload("res://src/core/combat_math.gd")

const BLAST_SHAKE_BASE := 1.2  # 폭발 셰이크 기본 강도 (연출값 — 반경에 비례해 커진다)

var _arrows: Dictionary = {}  # aid(String) -> Arrow 노드 (조기 despawn용 — 자연 소멸은 tree_exited로 정리)
var _blasts: Dictionary = {}  # aid(String) -> {radius: float, tint: Color, sfx: String} — 폭발탄(차지 무기)만. 종료 시점에 FX 반경을 로컬로 리졸브(전송 불필요)


func _ready() -> void:
	EventBus.player_shoot.connect(_on_player_shoot)
	EventBus.arrow_gone_local.connect(_on_arrow_gone)
	EventBus.net_msg.connect(_on_net_msg)


# 로컬 발사 — 내 표시 투사체 스폰 (shooter_id == Net.my_id, player가 G_SHOOT도 별도 송신)
func _on_player_shoot(_shooter_id: int, origin: Vector2, dir: Vector2, aid: String,
		arrow_range: float, weapon_id: String, charge: int) -> void:
	_spawn(aid, origin, dir, arrow_range, weapon_id, charge)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_SHOOT:
			# 원격 피어의 발사 — 표시 투사체 스폰 (판정은 호스트 CombatAuthority가 별도).
			# r = 사거리 폴백(무기 id 리졸브 실패 시만 사용) · w = 무기 id · c = 차지 레벨
			_spawn(str(data.get("aid", "")),
				Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0))),
				Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0))),
				float(data.get("r", CombatMathLib.DEFAULT_ARROW_RANGE)),
				str(data.get("w", "")), int(data.get("c", 0)))
		NetSchema.G_ARROW_HIT:
			if from_id != NetSchema.HOST_ID:
				return  # 투사체 종료 확정은 호스트 발신만 신뢰 (rules §3)
			_despawn(str(data.get("aid", "")),
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))))


# 호스트 자신의 권한 투사체 종료 — 자기 표시 탄 despawn (릴레이가 자기 G_ARROW_HIT를 안 돌려줌, drop_pick_local 미러)
func _on_arrow_gone(aid: String, world_pos: Vector2) -> void:
	_despawn(aid, world_pos)


func _spawn(aid: String, origin: Vector2, dir: Vector2, arrow_range: float,
		weapon_id: String, charge: int) -> void:
	if aid.is_empty() or _arrows.has(aid):
		return
	# 무기 파라미터 = 로컬 데이터 리졸브(단일 소스 §3) — 호스트 판정과 같은 값(결정론)
	var p := GameState.projectile_params(weapon_id, arrow_range, charge)
	var arrow := ArrowScene.instantiate() as Node2D
	_arrows[aid] = arrow
	var blast_r := float(p["blast"])
	if blast_r > 0.0:
		# 폭발탄 — 종료(적중/만료) 시 이 반경으로 FX. 반경은 전송 안 하고 각 클라가 여기서 기억한다
		_blasts[aid] = {"radius": blast_r, "tint": p["tint"] as Color, "sfx": str(p["blast_sfx"])}
		arrow.expired.connect(func(pos: Vector2) -> void: _blast_fx(aid, pos))  # 빗나감도 그 자리에서 폭발
	arrow.tree_exited.connect(func() -> void:
		_arrows.erase(aid)
		_blasts.erase(aid))  # 자연 소멸(수명 만료)도 맵 정리 — expired가 먼저 FX를 띄운 뒤
	get_parent().add_child(arrow)  # 부모 = 스테이지 Node2D. 런타임 add_child라 안전 (rules §5 _ready 함정 무관)
	arrow.setup(origin, dir, float(p["speed"]), float(p["life"]),
		p["texture"] as Texture2D, float(p["scale"]), bool(p["spin"]))


# impact_pos = 종료 지점(호스트 권한 좌표). 폭발탄이면 그 자리에 폭발 FX(표시) — 판정은 호스트가 이미 확정.
func _despawn(aid: String, impact_pos: Vector2) -> void:
	var node_v: Variant = _arrows.get(aid)
	_arrows.erase(aid)
	_blast_fx(aid, impact_pos)
	if node_v != null and is_instance_valid(node_v):
		(node_v as Node).queue_free()


# 폭발 표시 — 반경은 스폰 때 리졸브한 로컬 값(_blasts). 폭발 없는 탄(화살)이면 아무것도 안 한다.
# 소리·셰이크는 EventBus 훅(weapon_impact)으로 — 각 클라 로컬 재생, 네트워크 0 (rules 손맛 계층 규약).
func _blast_fx(aid: String, world_pos: Vector2) -> void:
	var info_v: Variant = _blasts.get(aid)
	if info_v == null:
		return
	_blasts.erase(aid)  # 적중·만료 중 한 번만
	var info := info_v as Dictionary
	var radius := float(info["radius"])
	var blast := BlastScene.instantiate() as Node2D
	get_parent().add_child(blast)
	blast.visible = true
	blast.setup(world_pos, radius, info["tint"] as Color)
	EventBus.weapon_impact.emit(world_pos, str(info["sfx"]),
		BLAST_SHAKE_BASE * (radius / CombatMathLib.MAX_BLAST_RADIUS + 0.6))
