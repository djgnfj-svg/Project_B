extends Node
# 늪 존 표시/스폰 컴포넌트 — 전 클라 (DropField 미러, 단 픽업 왕복 없음 = 더 단순). 스테이지가 자식으로 문다.
#
# 스폰: 호스트=swamp_spawn_local(보스 FSM이 슬램 STRIKE 시 emit) → SwampZone 로컬 스폰 + G_SWAMP 브로드캐스트.
#       게스트=G_SWAMP(호스트 발신·같은 stage_token만) → SwampZone 로컬 스폰.
# 호스트는 자기 G_SWAMP를 릴레이로 못 받으므로 swamp_spawn_local로 이미 스폰(drop_spawn_local 미러) → G_SWAMP는 게스트만 소비.
# ttl despawn·슬로우는 SwampZone 로컬(네트워크 0) — 결정만 호스트(늪 생성 = FSM), 표시/이동은 로컬 (rules §3).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")
const SwampZoneScene := preload("res://src/stage/swamp_zone.tscn")

var _swamps: Dictionary = {}  # sid -> SwampZone 노드 (중복 스폰 가드 — 재수신·경합 방지)


func _ready() -> void:
	EventBus.swamp_spawn_local.connect(_on_swamp_spawn_local)
	EventBus.net_msg.connect(_on_net_msg)


# 호스트 로컬 스폰 — 보스 FSM(_fire_strike)이 슬램 STRIKE 시 emit. 로컬 스폰 + G_SWAMP 브로드캐스트.
# (swamp_spawn_local은 호스트 보스만 emit하지만, 방어적으로 브로드캐스트는 is_host 게이트.)
func _on_swamp_spawn_local(swamps: Array) -> void:
	_spawn_all(swamps)
	if Net.is_host():
		# stage_token은 DropField/DropAuthority와 동일 소스 — 다른 칸/전환 창 유령 스폰 차단 (G_DROP "s" 미러)
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SWAMP, "s": GameState.stage_token(), "sw": swamps})


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if str(data.get(NetSchema.KEY_KIND, "")) != NetSchema.G_SWAMP:
		return
	if Net.is_host():
		return  # 호스트는 swamp_spawn_local로 이미 스폰 (자기 G_SWAMP 미수신 — drop_spawn_local 미러)
	if from_id != NetSchema.HOST_ID:
		return  # 늪 생성은 호스트 발신만 신뢰 (rules §3 — 위조 차단)
	if str(data.get("s", "")) != GameState.stage_token():
		return  # 다른 씬/칸 유령 스폰 차단 (G_DROP "s" 미러)
	_spawn_all(data.get("sw", []) as Array)


# 튜플 = [sid, x, y, r, ttl, slow] (net_schema G_SWAMP "sw" · swamp_spawn_local 공용 포맷).
func _spawn_all(swamps: Array) -> void:
	for entry: Variant in swamps:
		if not (entry is Array) or (entry as Array).size() < 6:
			continue
		var a := entry as Array
		_spawn(str(a[0]), Vector2(float(a[1]), float(a[2])), float(a[3]), float(a[4]), float(a[5]))


func _spawn(sid: String, world_pos: Vector2, radius: float, ttl: float, slow: float) -> void:
	if sid.is_empty() or _swamps.has(sid):
		return  # 중복 스폰 가드 (재수신·경합 방지)
	var zone := SwampZoneScene.instantiate()
	zone.call("setup", sid, world_pos, radius, ttl, slow, self)
	# 부모 = 스테이지 Node2D (DropField 미러) — Area2D를 plain Node(SwampField) 밑에 두면 top-level
	# 캔버스 아이템이 돼 Stage 트랜스폼이 생기면 늪만 어긋난다. 런타임 add_child라 안전(rules §5 _ready 함정 무관).
	get_parent().add_child(zone)
	_swamps[sid] = zone
	# ttl despawn 시 레지스트리 정리 — 페이즈2 자동 늪이 계속 쌓여도 딕셔너리 무한 증가 방지
	zone.tree_exited.connect(func() -> void: _swamps.erase(sid))
