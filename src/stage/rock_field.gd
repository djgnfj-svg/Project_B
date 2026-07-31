extends Node
# 낙석(P4) 바위 지형 스폰/동기화 컴포넌트 — 전 클라 (SwampField 미러). 스테이지가 자식으로 문다.
#
# 스폰: 호스트=rock_spawn_local(보스 낙석 STRIKE 시 emit) → BossRock 로컬 스폰 + G_ROCK 브로드캐스트.
#       게스트=G_ROCK(호스트 발신·같은 stage_token만) → BossRock 로컬 스폰.
# 호스트는 자기 G_ROCK을 릴레이로 못 받으므로 rock_spawn_local로 이미 스폰(SwampField 미러) → G_ROCK은 게스트만 소비.
# 돌진 충돌·ttl despawn은 로컬(네트워크 0) — 결정만 호스트(낙석 = FSM), 표시/충돌은 로컬 (rules §3).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")
const BossRockScene := preload("res://src/stage/boss_rock.tscn")

var _rocks: Dictionary = {}  # rid -> BossRock 노드 (중복 스폰 가드 — 재수신·경합 방지)


func _ready() -> void:
	EventBus.rock_spawn_local.connect(_on_rock_spawn_local)
	EventBus.net_msg.connect(_on_net_msg)


# 호스트 로컬 스폰 — 보스 FSM(_fire_strike)이 낙석 STRIKE 시 emit. 로컬 스폰 + G_ROCK 브로드캐스트.
func _on_rock_spawn_local(rocks: Array) -> void:
	_spawn_all(rocks)
	if Net.is_host():
		# stage_token은 G_SWAMP/G_DROP와 동일 소스 — 다른 칸/전환 창 유령 스폰 차단
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ROCK, "s": GameState.stage_token(), "rk": rocks})


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if str(data.get(NetSchema.KEY_KIND, "")) != NetSchema.G_ROCK:
		return
	if Net.is_host():
		return  # 호스트는 rock_spawn_local로 이미 스폰 (자기 G_ROCK 미수신 — SwampField 미러)
	if from_id != NetSchema.HOST_ID:
		return  # 바위 생성은 호스트 발신만 신뢰 (rules §3 — 위조 차단)
	if str(data.get("s", "")) != GameState.stage_token():
		return  # 다른 씬/칸 유령 스폰 차단 (G_SWAMP "s" 미러)
	_spawn_all(data.get("rk", []) as Array)


# 튜플 = [rid, x, y, r, ttl] (net_schema G_ROCK "rk" · rock_spawn_local 공용 포맷).
func _spawn_all(rocks: Array) -> void:
	for entry: Variant in rocks:
		if not (entry is Array) or (entry as Array).size() < 5:
			continue
		var a := entry as Array
		_spawn(str(a[0]), Vector2(float(a[1]), float(a[2])), float(a[3]), float(a[4]))


func _spawn(p_rid: String, world_pos: Vector2, radius: float, ttl: float) -> void:
	if p_rid.is_empty() or _rocks.has(p_rid):
		return  # 중복 스폰 가드 (재수신·경합 방지)
	var rock := BossRockScene.instantiate()
	rock.call("setup", p_rid, world_pos, radius, ttl, self)
	# 부모 = 스테이지 Node2D (SwampField 미러) — StaticBody2D를 plain Node 밑에 두면 트랜스폼 어긋남.
	get_parent().add_child(rock)
	_rocks[p_rid] = rock
	# despawn 시 레지스트리 정리 — 낙석이 계속 쌓여도 딕셔너리 무한 증가 방지
	rock.tree_exited.connect(func() -> void: _rocks.erase(p_rid))
