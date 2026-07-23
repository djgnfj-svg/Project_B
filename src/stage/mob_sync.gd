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
	EventBus.boss_telegraph.connect(_on_boss_telegraph)
	for m: Node in get_tree().get_nodes_in_group("mob"):
		var eid_v: Variant = m.get("eid")
		if eid_v is String and not str(eid_v).is_empty():
			_mobs[str(eid_v)] = m


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


# 호스트 전용 수신 경로 — 보스 AI가 알린 패턴 텔레그래프를 전원에 중계 (matk 규약 확장, 표시 전용)
func _on_boss_telegraph(eid: String, pattern_id: String, center: Vector2, angle: float) -> void:
	if not Net.is_host():
		return  # 방어적 — 보스 AI는 호스트만 emit하지만, 게스트 발신 시 릴레이 낭비 차단 (게스트 위조는 수신부 HOST_ID 검증이 이미 거부)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_ATK,
		"eid": eid, "p": pattern_id, "x": center.x, "y": center.y, "a": angle})


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
				mob.call("show_telegraph",
					Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))))
		NetSchema.G_BOSS_ATK:
			var boss: Node = _mobs.get(str(data.get("eid", "")))
			if boss != null:
				boss.call("show_boss_telegraph", str(data.get("p", "")),
					Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
					float(data.get("a", 0.0)))
