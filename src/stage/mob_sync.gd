extends Node
# 잔몹 표시 동기화 전담 컴포넌트 — 호스트: mpos(10Hz 배치)·matk 브로드캐스트, 게스트: 수신 반영.
# 권한·판정은 여기 없다(그건 CombatAuthority) — rules §2 책임 분리. 스테이지가 자식 노드로 문다.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")

const SEND_RATE := 10.0  # Hz — 배치 1건으로 묶어 릴레이 메시지 2KB 상한·빈도 부담 완화 (rules §2)

var _mobs: Dictionary = {}  # eid -> mob (그룹 "mob" 씬 배치 스캔 — 동적 스폰 없음)
var _send_accum: float = 0.0


func _ready() -> void:
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.mob_telegraph.connect(_on_mob_telegraph)
	EventBus.mob_shoot.connect(_on_mob_shoot)
	EventBus.boss_telegraph.connect(_on_boss_telegraph)
	EventBus.boss_spray.connect(_on_boss_spray)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	# 🔴 **자기 씬 하위만 등록한다** — combat_authority._ready와 같은 이유이고, 여기 피해는
	#   네트워크로 나간다: 씬 스왑 프레임의 유령이 박히면 다음 프레임부터 아래 `_physics_process`의
	#   `_mobs[eid] as Node2D`가 **캐스트에서** 터져(`Trying to cast a freed object`) 함수가 중단되고,
	#   그러면 `G_MOB_POS`가 **한 통도 안 나가** 게스트 화면의 잔몹이 통째로 얼어붙는다
	#   (초당 60회 에러 · 2026-08-01 "스테이지2에서 멈춘다" 신고의 게스트 쪽 증상).
	#   ⚠ 아래 루프의 `mob == null` 가드는 이걸 못 막는다 — **캐스트가 먼저 터진다.**
	# 🔴 **기준은 `owner`(그 .tscn의 루트)다** — combat_authority._ready와 같은 이유. `get_parent()`는
	#   컴포넌트를 한 겹만 감싸도 껍데기를 반환해 **자기 씬 잔몹이 하나도 안 통과한다**(조용한 전면
	#   무등록 = `G_MOB_POS` 0통 = 방금 고친 그 증상인데 SCRIPT ERROR조차 없다 · netreview 2026-08-01).
	var scene_root: Node = owner if owner != null else get_parent()
	var passed := 0
	for m: Node in get_tree().get_nodes_in_group("mob"):
		if scene_root == null or not scene_root.is_ancestor_of(m):
			continue
		passed += 1
		var eid_v: Variant = m.get("eid")
		if eid_v is String and not str(eid_v).is_empty():
			_mobs[str(eid_v)] = m
	# 전면 무등록 진단 — 화면에는 "게스트 잔몹이 안 움직인다"로만 나타나므로 에러를 코드로 박아 둔다.
	if scene_root != null:
		var under := _count_in_group_under(scene_root, &"mob")
		if passed < under:
			push_error("[MobSync] 씬 하위 잔몹 %d마리 중 %d마리만 등록됐다 — 씬 스캔 필터가 자기 씬을 떨어뜨린다(scene_root=%s)"
				% [under, passed, scene_root.name])


# 씬 하위의 그룹 소속 노드 수 — 위 진단 전용. `_ready` 1회라 재귀 비용은 무시할 수준.
func _count_in_group_under(n: Node, group: StringName) -> int:
	var c := 1 if n.is_in_group(group) else 0
	for ch: Node in n.get_children():
		c += _count_in_group_under(ch, group)
	return c


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_send_accum += delta
	if _send_accum < 1.0 / SEND_RATE:
		return
	_send_accum = 0.0
	var batch: Array = []
	for eid: String in _mobs:
		var mob := _mobs[eid] as Node2D
		if mob == null or not mob.visible:
			continue  # 사망(숨김) 잔몹 제외 — 사망 전파는 ehp가 담당
		batch.append(mob.call("get_sync_state"))
	if not batch.is_empty():
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_MOB_POS, "m": batch})


# 호스트 전용 수신 경로 — 잔몹 AI가 알린 텔레그래프를 전원에 중계 (게스트는 emit하지 않는다)
func _on_mob_telegraph(eid: String, center: Vector2) -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_MOB_ATK, "eid": eid, "x": center.x, "y": center.y})


# 호스트 전용 수신 경로 — 원거리 잔몹의 발사를 전원에 중계 (matk 규약 확장, 2026-08-01).
# 🔴 **게스트도 같은 시그널을 로컬 emit한다**(아래 G_MOB_SHOOT 수신 → mob.play_shoot → mob_shoot).
#   그 재emit이 여기로 되돌아와 무한 중계가 되지 않도록 호스트 가드가 **필수**다 — `_on_boss_telegraph`가
#   방어적으로 달아 둔 같은 가드가 여기서는 실제로 동작에 필요하다.
# 🔴 **수치는 하나도 싣지 않는다** — eid만 보내면 각 클라가 자기 씬의 EnemyDef에서 속도·사거리·
#   판정 반경·텍스처를 리졸브한다(`peer_weapon_id`·`projectile_params` 철학, rules §3).
#   그래서 스푸핑 표면이 0이고 "맞는 곳 = 보이는 곳"이 구조로 유지된다.
# ⚠ 채널: 이 kind는 **사건**이라 유실 허용(fast)에 넣으면 안 된다 — 한 통이 사라지면 게스트 화면에
#   화살 없이 데미지만 들어온다. `RTC_FAST_KINDS`는 allowlist라 기본이 safe다(rules §3 채널 분류).
func _on_mob_shoot(eid: String, origin: Vector2, dir: Vector2, aid: String, _def: EnemyDef) -> void:
	if not Net.is_host():
		return
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_MOB_SHOOT, "eid": eid,
		"ox": origin.x, "oy": origin.y, "dx": dir.x, "dy": dir.y, "aid": aid})


# 호스트 전용 수신 경로 — 보스 AI가 알린 패턴 텔레그래프를 전원에 중계 (matk 규약 확장, 표시 전용)
func _on_boss_telegraph(eid: String, pattern_id: String, center: Vector2, angle: float) -> void:
	if not Net.is_host():
		return  # 방어적 — 보스 AI는 호스트만 emit하지만, 게스트 발신 시 릴레이 낭비 차단 (게스트 위조는 수신부 HOST_ID 검증이 이미 거부)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_ATK,
		"eid": eid, "p": pattern_id, "x": center.x, "y": center.y, "a": angle})


# 호스트 전용 — 보스 물뿌리기 착탄점들을 전원에 중계(표시 전용). 게스트가 N개 원 텔레그래프 렌더.
# Vector2는 JSON 왕복이 안 되므로 [[x,y], …] 평면 배열로 직렬화 (G_SWAMP/G_DROP 규약 미러).
func _on_boss_spray(eid: String, pattern_id: String, centers: Array, _angle: float) -> void:
	if not Net.is_host():
		return
	var arr: Array = []
	for c: Variant in centers:
		var v := c as Vector2
		arr.append([v.x, v.y])
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_SPRAY, "eid": eid, "p": pattern_id, "c": arr})


# 호스트 전용 — 보스 페이즈 전이를 전원에 중계(표시 큐). 정본 판정은 호스트 hp — 이건 배너 동기화일 뿐.
func _on_boss_phase_changed(phase: int) -> void:
	if not Net.is_host():
		return
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_PHASE, "ph": phase})


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if Net.is_host() or from_id != NetSchema.HOST_ID:
		return  # 잔몹 상태는 호스트 발신만 신뢰 (rules §3). 미등록 eid = 자연 드랍
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_MOB_POS:
			for entry: Variant in (data.get("m", []) as Array):
				if not (entry is Array) or (entry as Array).size() < 4:
					continue
				var arr := entry as Array
				var mob: Node = _mobs.get(str(arr[0]))
				if mob != null:
					mob.call("apply_remote_pos",
						Vector2(float(arr[1]), float(arr[2])), bool(arr[3]))
		NetSchema.G_MOB_ATK:
			var mob: Node = _mobs.get(str(data.get("eid", "")))
			if mob != null:
				# ⚠ 원거리 개체는 같은 호출을 **활 당김 모션**으로 해석한다(그 배우가 자기 def를 본다)
				#   — 신규 kind 0개. 여기서 분기하지 마라: 갈래가 둘이 되는 순간 "메시지는 왔는데
				#   한쪽만 해석한다"가 태어난다.
				mob.call("show_telegraph",
					Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))))
		NetSchema.G_MOB_SHOOT:
			# 원거리 잔몹 발사 — 배우가 놓는 프레임으로 넘어가고 로컬 mob_shoot을 emit해
			# ArrowField가 표시 탄을 띄운다. 판정용 화살은 호스트가 이미 등록해 뒀다(CombatAuthority).
			# ⚠ 방향은 여기 실린 dx/dy가 정본이다 — G_MOB_ATK에서 유도한 자세각은 근사일 뿐이다.
			var shooter: Node = _mobs.get(str(data.get("eid", "")))
			if shooter != null:
				shooter.call("play_shoot",
					Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0))),
					Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0))),
					str(data.get("aid", "")))
		NetSchema.G_BOSS_ATK:
			var boss: Node = _mobs.get(str(data.get("eid", "")))
			if boss != null:
				boss.call("show_boss_telegraph", str(data.get("p", "")),
					Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
					float(data.get("a", 0.0)))
		NetSchema.G_BOSS_SPRAY:
			# 착탄점 [[x,y], …] → Vector2 배열 복원 후 boss_spray 로컬 emit(보스 렌더러가 N개 원 그림)
			var centers: Array = []
			for e: Variant in (data.get("c", []) as Array):
				if e is Array and (e as Array).size() >= 2:
					var a := e as Array
					centers.append(Vector2(float(a[0]), float(a[1])))
			EventBus.boss_spray.emit(str(data.get("eid", "")), str(data.get("p", "")), centers, 0.0)
		NetSchema.G_BOSS_PHASE:
			EventBus.boss_phase_changed.emit(int(data.get("ph", 1)))  # HUD 배너(표시 큐)
