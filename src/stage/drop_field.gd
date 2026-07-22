extends Node
# 드랍 표시/스폰 컴포넌트 — 전 클라 (rules §2 책임 분리, 결정은 DropAuthority). 스테이지가 자식으로 문다.
#
# 스폰: 호스트=drop_spawn_local(자기 롤), 게스트=G_DROP(호스트 발신·같은 stage_token만) → DropItem 인스턴스.
# 픽업 요청: DropItem이 로컬 플레이어 겹침 감지 → request_pickup → 호스트=DropAuthority.host_pickup, 게스트=G_PICK_REQ.
# 픽업 확정: G_PICK_OK(호스트 발신만 신뢰) → despawn + 주운 클라(pid==my_id)만 collect_drop(각자 로컬 저장).
#
# ⚠ 동적 스폰 등록(rules §2 게이트): _ready 그룹 스캔 금지 — 스폰 시점에 _drops에 등록한다.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")
const DropItemScene := preload("res://src/stage/drop_item.tscn")
# gold/blueprint은 고정 스프라이트(placeholder — projectb-art 교체 예정), material은 MaterialDef.icon 리졸브.
const GOLD_TEX := preload("res://assets/sprites/items/gold.png")
const BLUEPRINT_TEX := preload("res://assets/sprites/items/blueprint.png")

@export var drop_authority_path: NodePath  # 호스트 로컬 픽업 통지용 (DropAuthority)

var _drops: Dictionary = {}  # did -> DropItem 노드 (스폰 시 등록 — 그룹 스캔 아님)


func _ready() -> void:
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.drop_spawn_local.connect(_on_drop_spawn_local)
	EventBus.drop_pick_local.connect(_despawn_picked)  # 호스트 로컬 픽업 반영 (자기 G_PICK_OK 미수신 미러 — Critical 수정)


# 호스트 로컬 스폰 — DropAuthority가 롤 직후 emit (호스트는 자기 G_DROP를 릴레이로 못 받는다)
func _on_drop_spawn_local(drops: Array) -> void:
	for d: Variant in drops:
		if not (d is Dictionary):
			continue
		var e := d as Dictionary
		_spawn(str(e["did"]), str(e["kind"]), str(e["item_id"]),
			int(e["qty"]), int(e["rarity"]), e["pos"] as Vector2)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_DROP:
			if from_id != NetSchema.HOST_ID:
				return  # 드랍 생성은 호스트 발신만 신뢰 (rules §3)
			if str(data.get("s", "")) != GameState.stage_token():
				return  # 다른 칸/전환 창 유령 스폰 차단 (G_POS "s" 미러)
			for entry: Variant in (data.get("d", []) as Array):
				if not (entry is Array) or (entry as Array).size() < 7:
					continue
				var a := entry as Array
				_spawn(str(a[0]), str(a[1]), str(a[2]), int(a[3]), int(a[6]),
					Vector2(float(a[4]), float(a[5])))
		NetSchema.G_PICK_OK:
			if from_id != NetSchema.HOST_ID:
				return  # 픽업 확정은 호스트 발신만 신뢰 (rules §3)
			_despawn_picked(str(data.get("did", "")), int(data.get("pid", 0)))


func _spawn(did: String, kind: String, item_id: String, qty: int, rarity: int, pos: Vector2) -> void:
	if did.is_empty() or _drops.has(did):
		return  # 중복 스폰 가드 (재수신·경합 방지)
	var item := DropItemScene.instantiate()
	item.setup(did, kind, item_id, qty, rarity, _resolve_texture(kind, item_id), self)
	get_parent().add_child(item)  # 부모 = 스테이지 Node2D. 런타임 add_child라 안전 (rules §5 _ready 함정과 무관)
	(item as Node2D).global_position = pos
	_drops[did] = item
	EventBus.item_dropped.emit(kind, rarity, pos)  # 등장 연출(feel) — 표시 전용


func _resolve_texture(kind: String, item_id: String) -> Texture2D:
	match kind:
		"gold":
			return GOLD_TEX
		"blueprint":
			return BLUEPRINT_TEX
		"material":
			var m := GameState.material_def(item_id)
			return m.icon if m != null else null  # 아이콘 미설정이어도 죽지 말 것 — 안 보일 뿐
		_:
			return null


# DropItem이 로컬 플레이어와 겹쳐 픽업 요청 — 호스트=권한 직접, 게스트=요청 송신. DropItem은 Net을 직접 안 부른다 (rules §2)
func request_pickup(did: String) -> void:
	if Net.is_host():
		var auth := get_node_or_null(drop_authority_path)
		if auth != null:
			auth.call("host_pickup", did, Net.my_id)
	else:
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_PICK_REQ, "did": did})


# 픽업 확정 반영 — despawn + 주운 클라만 인벤 반영. 한 did당 G_PICK_OK는 1회뿐이라 전 클라가 같이 despawn.
func _despawn_picked(did: String, pid: int) -> void:
	if not _drops.has(did):
		return
	var item := _drops[did] as Node
	_drops.erase(did)
	var kind := str(item.get("kind"))
	var item_id := str(item.get("item_id"))
	var qty := int(item.get("qty"))
	var rarity := int(item.get("rarity"))
	var pos := (item as Node2D).global_position
	item.queue_free()
	if pid == Net.my_id:
		GameState.collect_drop(kind, item_id, qty)  # 주운 클라만 자기 인벤(각자 로컬 저장)
	EventBus.item_picked.emit(kind, rarity, pos)  # 픽업 연출(feel) — 표시 전용
