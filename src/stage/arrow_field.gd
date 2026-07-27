extends Node
# 표시 투사체 관리 — 전투 씬(스테이지)이 자식 노드로 문다. 전 클라 공통(호스트·게스트 모두 탄을 본다).
# 발사마다(로컬 player_shoot·원격 G_SHOOT) 표시 투사체를 스폰하고, 종료(G_ARROW_HIT·호스트 arrow_gone_local)에
# 맞춰 despawn한다. 명중 판정·데미지는 여기가 아니라 CombatAuthority(호스트) — 이 노드는 표시 전용(네트워크 송신 0).
# 탄 겉모습·속도·수명·폭발 반경은 GameState.projectile_params(무기 id allowlist 리졸브) 단일 소스 —
# 호스트 판정도 같은 함수를 부르므로 "맞는 곳=보이는 곳"이 유지된다 (rules §3).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).
# ⚠ 동적 스폰 등록(rules §2 게이트 정신): _ready 그룹 스캔 없음 — 발사 시점에만 _arrows에 등록/정리.

const NetSchema := preload("res://src/core/net_schema.gd")
const PeerSyncNode := preload("res://src/net/peer_sync.gd")
const ArrowScene := preload("res://src/combat/arrow.tscn")
const BlastScene := preload("res://src/combat/blast.tscn")
const CombatMathLib := preload("res://src/core/combat_math.gd")

const BLAST_SHAKE_BASE := 1.2  # 폭발 셰이크 기본 강도 (연출값 — 반경에 비례해 커진다)

@export var peer_sync_path: NodePath  # 형제 PeerSync — 발사자 아바타 조회(특성 리졸브)에 필요

var _peer_sync: PeerSyncNode = null
var _arrows: Dictionary = {}  # aid(String) -> Arrow 노드 (조기 despawn용 — 자연 소멸은 tree_exited로 정리)
var _blasts: Dictionary = {}  # aid(String) -> {radius: float, tint: Color, sfx: String} — 폭발탄(차지 무기)만. 종료 시점에 FX 반경을 로컬로 리졸브(전송 불필요)


func _ready() -> void:
	# 🔴 발사자 아바타 조회 경로를 **판정 쪽(CombatAuthority)과 같은 것**으로 맞춘다 (2026-07-27).
	#   전에는 그룹 스캔이었는데, 판정은 _peer_sync.player()를 쓰고 있었다 — 같은 노드를 가리키긴 해도
	#   경로가 둘이면 다음 사람이 한쪽만 고친다("맞는 곳 ≠ 보이는 곳"이 태어나는 자리 그 자체).
	#   덤으로 씬 스왑 프레임의 유령 노드 문제(rules §5)가 구조적으로 사라진다 — PeerSync의 _players는
	#   그 씬 것만 들고 있어서 부모 비교 같은 방어가 필요 없다.
	_peer_sync = get_node_or_null(peer_sync_path) as PeerSyncNode
	if _peer_sync == null:
		push_error("[ArrowField] peer_sync_path 미배선 — 발사자 특성 리졸브 불능(사거리가 기본값으로 떨어진다)")
	EventBus.player_shoot.connect(_on_player_shoot)
	EventBus.arrow_gone_local.connect(_on_arrow_gone)
	EventBus.net_msg.connect(_on_net_msg)


# 로컬 발사 — 내 표시 투사체 스폰 (shooter_id == Net.my_id, player가 G_SHOOT도 별도 송신)
func _on_player_shoot(shooter_id: int, origin: Vector2, dir: Vector2, aid: String,
		arrow_range: float, weapon_id: String, charge: int, combo: int) -> void:
	_spawn(aid, origin, dir, arrow_range, weapon_id, charge, shooter_id, combo)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_SHOOT:
			# 원격 피어의 발사 — 표시 투사체 스폰 (판정은 호스트 CombatAuthority가 별도).
			# r = 사거리 폴백(무기 id 리졸브 실패 시만 사용) · w = 무기 id · c = 차지 레벨 · cb = 콤보 타수
			# ⚠ cb는 **발신자 주장 그대로** 쓴다(표시 전용). 호스트 판정은 자기가 센 타수(≤ 주장)를 쓰므로
			#   사칭자는 자기 화면에만 강화살이 그려지고 판정은 안 난다 — "w"(무기 사칭)와 같은 규약이다.
			_spawn(str(data.get("aid", "")),
				Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0))),
				Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0))),
				float(data.get("r", CombatMathLib.DEFAULT_ARROW_RANGE)),
				str(data.get("w", "")), int(data.get("c", 0)), from_id, int(data.get("cb", 0)))
		NetSchema.G_ARROW_HIT:
			if from_id != NetSchema.HOST_ID:
				return  # 투사체 종료 확정은 호스트 발신만 신뢰 (rules §3)
			_despawn(str(data.get("aid", "")),
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))))


# 호스트 자신의 권한 투사체 종료 — 자기 표시 탄 despawn (릴레이가 자기 G_ARROW_HIT를 안 돌려줌, drop_pick_local 미러)
func _on_arrow_gone(aid: String, world_pos: Vector2) -> void:
	_despawn(aid, world_pos)


func _spawn(aid: String, origin: Vector2, dir: Vector2, arrow_range: float,
		weapon_id: String, charge: int, shooter_id: int, combo: int) -> void:
	if aid.is_empty() or _arrows.has(aid):
		return
	# 무기 파라미터 = 로컬 데이터 리졸브(단일 소스 §3) — 호스트 판정과 같은 값(결정론).
	# 사거리 특성(proj_range)도 호스트 판정과 **같은 소스**(발사자 아바타)에서 읽는다 — 아래 헬퍼.
	# 콤보 타수는 표시 쪽만 주장값을 쓴다(위 _on_net_msg 주석 — 갈라짐은 안전한 방향으로만).
	var p := GameState.projectile_params(weapon_id, arrow_range, charge,
		_shooter_proj_range(shooter_id), combo)
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


# 발사자 아바타의 「투사체 사거리」(proj_range) 특성 — 미스폰/미상이면 0(항등 = 보너스 없음).
# 🔴 **항상 발사자 아바타에서 읽는다**(rules §3): peer_sync._peer_stats에는 로컬(내) 항목이 영원히
#   없어서(Net 루프백 없음) 그쪽을 읽으면 "내 화살만 안 늘어난다"가 된다 — 2026-07-25 공속 Critical과
#   같은 함정이다. 아바타 값은 로컬=GameState.active_traits() · 원격=그 피어 공지 id 리졸브(peer_sync가
#   set_traits로 심는다)라, 호스트 판정(CombatAuthority)이 보는 값과 **같은 소스**다("맞는 곳=보이는 곳").
# 🔴 조회 경로도 판정 쪽과 **같은 것**(_peer_sync.player)이다 — 옛 그룹 스캔은 같은 노드를 가리키긴 했지만
#   경로가 둘이라 다음 사람이 한쪽만 고칠 수 있었다(2026-07-27 통일).
# ⚠ 미스폰(첫 G_POS 전에 도착한 G_SHOOT)이면 0 — **게스트 발사에 한해** 안전하다. 호스트가 그 창에서
#   발사 자체를 거부(`shooter == null`)하므로 표시만 짧아지고 판정은 아예 안 생긴다.
# 🔴 **호스트 자기 발사에는 그 보호가 없다** (2026-07-27 netreview m2): 호스트는 자기 발사를 거부하지
#   않으므로, 게스트가 아직 호스트의 아바타·특성(G_STATS)을 반영하지 못한 창에서 호스트가 쏘면
#   **게스트 화면 150px / 호스트 판정 최대 210px**로 갈라진다 — 방향이 "화면에 없는데 맞는다"는 금지 쪽이다.
#   창이 스폰 직후 한 번뿐이고(그 뒤 아바타가 계속 산다) 특성 보유자에게만 생겨 지금은 수용한다.
#   ⚠ 넓히려면(재합류·4인) 여기가 아니라 **스냅샷**에서 고쳐라 — rules §2 재합류 게이트의 대상이다.
func _shooter_proj_range(shooter_id: int) -> float:
	if _peer_sync == null:
		return 0.0
	var p := _peer_sync.player(shooter_id)
	return p.trait_value("proj_range") if p != null else 0.0


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
