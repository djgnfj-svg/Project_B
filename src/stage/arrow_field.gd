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
	EventBus.mob_shoot.connect(_on_mob_shoot)
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
	# 무기 파라미터 = 로컬 데이터 리졸브(단일 소스 §3) — 호스트 판정과 같은 값(결정론).
	# 사거리 특성(proj_range)도 호스트 판정과 **같은 소스**(발사자 아바타)에서 읽는다 — 아래 헬퍼.
	# 콤보 타수는 표시 쪽만 주장값을 쓴다(위 _on_net_msg 주석 — 갈라짐은 안전한 방향으로만).
	var p := GameState.projectile_params(weapon_id, arrow_range, charge,
		_shooter_proj_range(shooter_id), combo)
	_instantiate(aid, origin, dir, float(p["speed"]), float(p["life"]),
		p["texture"] as Texture2D, float(p["scale"]), bool(p["spin"]),
		float(p["blast"]), p["tint"] as Color, str(p["blast_sfx"]))


# 🔴 원거리 잔몹의 발사 — 호스트는 자기 AI가 emit, 게스트는 G_MOB_SHOOT 수신 → 배우 → 같은 시그널.
#   **양쪽이 같은 함수로 수렴하므로 표시 경로가 하나뿐이다**(플레이어의 player_shoot와 같은 구조).
# 🔴 **호스트는 자기 화살을 이 로컬 emit으로 만든다 — 브로드캐스트 수신에 기대지 않는다**
#   (netreview ① 2026-08-01). Net에는 **루프백이 없어서** 호스트는 자기 G_MOB_SHOOT를 되받지
#   못한다 — 수신부에서만 스폰하면 **호스트 화면에만 화살이 안 뜬다**(에러 0·로그 0).
#   `swamp_spawn_local`·`rock_spawn_local`·`arrow_gone_local`이 전부 이 이유로 존재하는 로컬
#   미러이고, 2026-07-25 공속 Critical과 같은 부류다.
# 🔴 파라미터는 **전송값이 아니라 def(로컬 .tres)** 에서 온다 — 네트워크로는 eid만 왔다.
#   호스트 판정(CombatAuthority)도 같은 def를 읽으므로 속도·수명이 정확히 일치한다("맞는 곳=보이는 곳").
# 🔴 **표시 탄만 자기 편도 지연만큼 앞당겨 스폰한다** (설계 ⑸ 축②). 안 하면 게스트 화면의 화살이
#   권한 화살보다 영구히 `편도 × 속도` px 뒤처져(200ms·200px/s = 40px) **화면상 아직 멀리 있는
#   화살에 맞는다** = §3이 금지하는 "안 보이는데 맞는다". 기존 「방어자 우대」(is_strike_hit_lagged)는
#   플레이어의 *이동*을 용서하는 규약이라 **가만히 선 게스트에겐 아무 효과가 없다** — 다른 축이다.
#
# 🔴🔴 **유도 — 두 구간이 각각 다른 값에 앵커된다. 하나로 합치려 하지 마라** (netreview ② 2026-08-01:
#   폐기 구현이 정합했던 유일한 이유가 이 불변식이었는데 코드 어디에도 안 적혀 있었다).
#   `T` = 호스트가 화살을 놓는 벽시계 시각 · `d` = 이 클라와 호스트 사이 편도 지연.
#     ⑴ **조준 구간** — 호스트 WINDUP은 `telegraph_s + strike_delay_s(max_remote_one_way)`,
#        게스트는 G_MOB_ATK를 `d` 늦게 받아 자기 `telegraph_s`만 돈다. 두 창의 **끝이 T에서 만난다**
#        (근접 예고와 같은 규약 — `mob_melee._host_ai`). 즉 게스트도 온전한 조준 시간을 본다.
#     ⑵ **비행 구간** — G_MOB_SHOOT은 `T + d`에 도착한다. 그때 원점을 `속도 × d`만큼 앞으로
#        밀면 게스트 표시 위치 = `O + dir·s·t`이고 호스트 권한 위치도 `O + dir·s·t`라
#        **모든 벽시계 시각에 정확히 일치**한다.
#   ⚠ ⑴은 `max_remote_one_way`(가장 느린 피어), ⑵는 `이 클라의 d`를 쓴다 — **다른 값이 맞다.**
#     2인에선 같지만 4인에선 갈린다: 조준은 모두가 온전한 창을 가져야 하므로 최댓값, 비행은
#     각자 자기 화면을 맞추는 것이라 자기 값이다. 하나로 통일하면 둘 중 하나가 반드시 깨진다.
#   🔴 **경과 시간·고정 상수로 바꾸지 마라** — 호스트 시계를 실어 보내면 시계 동기화가 필요해지고
#     (이 프로젝트는 의도적으로 안 한다, `G_PING` 주석), 고정 상수는 RTT 가변성을 못 따라간다.
#   ⚠ **`dev_local.sh`(13.8ms)에선 이 갈래가 한 줄도 안 돈다** — 배포 릴레이(편도 70~108ms)에서만
#     드러난다. 헤드리스도 못 잡는다. 고칠 때 실기 확인 없이 "돌아간다"고 결론 내지 마라.
#   ⚠ **수명은 앞당기지 않는다(원본 그대로).** 그러면 게스트 화살이 호스트 만료보다 편도만큼 더
#     오래·더 멀리 남아 오차가 **"보이는데 안 맞는다"**(안전한 쪽)로만 떨어진다. 수명까지 깎으면
#     RTT 지터 한 번에 꼬리 구간이 "안 보이는데 맞는다"로 뒤집힌다 — **이 한 줄이 부호를 정한다.**
#   ⚠ 신뢰 대가 0: 이 값은 전송되지 않고 각 클라가 재는 자기 RTT다. 부풀리면 화살이 자기 화면에서
#     더 앞서 그려져 **자기 경고 시간만 줄어든다**(자해). 호스트는 자기 id의 RTT가 없어 0 = 항등.
func _on_mob_shoot(_eid: String, origin: Vector2, dir: Vector2, aid: String, def: EnemyDef) -> void:
	if def == null:
		return
	var speed := CombatMathLib.clamp_projectile_speed(def.proj_speed)
	var lead_s := CombatMathLib.clamp_one_way_ms(Net.one_way_ms(NetSchema.HOST_ID)) / 1000.0
	_instantiate(aid, origin + dir * (speed * lead_s), dir, speed,
		CombatMathLib.projectile_lifetime_s(def.proj_range, speed),
		def.proj_texture, 1.0, false, 0.0, Color(1, 1, 1, 1), "")


# 표시 탄 생성·등록 — 플레이어/잔몹 공용 꼬리. 종료(_despawn·G_ARROW_HIT)도 완전 공용이라
# 이 노드에서 발사 주체가 갈리는 곳은 **파라미터를 어디서 리졸브하느냐** 한 군데뿐이다.
func _instantiate(aid: String, origin: Vector2, dir: Vector2, speed: float, life: float,
		tex: Texture2D, orb_scale: float, spin: bool,
		blast_r: float, tint: Color, blast_sfx: String) -> void:
	if aid.is_empty() or _arrows.has(aid):
		return
	var arrow := ArrowScene.instantiate() as Node2D
	_arrows[aid] = arrow
	if blast_r > 0.0:
		# 폭발탄 — 종료(적중/만료) 시 이 반경으로 FX. 반경은 전송 안 하고 각 클라가 여기서 기억한다
		_blasts[aid] = {"radius": blast_r, "tint": tint, "sfx": blast_sfx}
		arrow.expired.connect(func(pos: Vector2) -> void: _blast_fx(aid, pos))  # 빗나감도 그 자리에서 폭발
	arrow.tree_exited.connect(func() -> void:
		_arrows.erase(aid)
		_blasts.erase(aid))  # 자연 소멸(수명 만료)도 맵 정리 — expired가 먼저 FX를 띄운 뒤
	get_parent().add_child(arrow)  # 부모 = 스테이지 Node2D. 런타임 add_child라 안전 (rules §5 _ready 함정 무관)
	arrow.setup(origin, dir, speed, life, tex, orb_scale, spin)


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
