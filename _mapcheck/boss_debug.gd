extends Node2D

## 보스 패턴 테스트 하네스 (오픈소스 프로토타입) — 릴레이/로비 없이 보스 패턴을 발동·조정·검증한다.
##   [P] 다음 패턴 / [Space] 선택 패턴 발동 / [R] 재시작 / [H] 패널 숨김
## 좌하 패널에서 선택 패턴 수치(예고·사거리·반각·데미지·쿨) 실시간 조정. debug_hold로 보스 자동공격 정지.
## 게임 배선과 무관(_mapcheck/ 삭제 가능). Net.my_id를 호스트로 강제해 보스 AI 경로가 돈다.

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerScene := preload("res://src/player/player.tscn")

const ARENA_CENTER := Vector2(576, 324)
const ARENA_HALF := Vector2(348, 188)
const CAM_ZOOM := 0.9

var _stage: Node = null
var _boss: Node = null
var _sprite: AnimatedSprite2D = null
var _cam: Camera2D = null
var _coop: Node = null            # C1(영혼 비석) 테스트용 CoopAuthority
var _npc: Node = null             # 코옵 가짜 파트너(NPC 777)

var _pat_ids: Array[String] = []
var _pat_defs: Array = []
var _sel: int = 0

var _hud: CanvasLayer = null
var _pat_label: Label = null
var _sliders: Dictionary = {}   # field -> {slider, value_label}

# 조정 가능한 필드 (선택 패턴에 적용) — 이름, 최소, 최대, step
const FIELDS := [
	["telegraph_s", 0.2, 3.0, 0.1],
	["range", 30.0, 320.0, 5.0],
	["half_angle", 0.1, 1.5, 0.05],
	["damage", 1.0, 100.0, 1.0],
	["cooldown_s", 0.3, 6.0, 0.1],
	["recover_s", 0.1, 2.0, 0.1],
]


func _ready() -> void:
	Net.my_id = NetSchema.HOST_ID
	var ps := load("res://src/stage/stage_boss.tscn") as PackedScene
	if ps == null:
		push_error("stage_boss.tscn 로드 실패")
		return
	_stage = ps.instantiate()
	add_child(_stage)
	# 망령 전용 늪 제거 (미노는 자체 패턴만). CoopAuthority는 C1(영혼 비석) 테스트용으로 남긴다.
	var sf := _stage.get_node_or_null("SwampField")
	if sf != null:
		sf.queue_free()
	_coop = _stage.get_node_or_null("CoopAuthority")
	if _coop != null:
		_coop.set("debug_hold", true)   # 자동 순환 정지 — 버튼/캡처로만 발동

	_boss = _stage.get_node_or_null("Boss")
	if _boss != null:
		_sprite = _boss.get_node_or_null("Sprite") as AnimatedSprite2D
		_boss.set("debug_hold", true)   # 자동공격/자동선택 정지 — 버튼으로만 발동
		var def: Variant = _boss.get("def")
		if def != null:
			for p: Variant in def.patterns:
				if p != null:
					_pat_ids.append(str(p.id))
					_pat_defs.append(p)

	_build_bounds(_stage)
	_build_debug_rock()
	_build_camera()
	_build_hud()

	if OS.get_cmdline_user_args().has("swcap"):
		_capture_test()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		var k := ke.keycode
		var pk := ke.physical_keycode
		if k == KEY_P or pk == KEY_P:
			_cycle_pattern()
		elif k == KEY_SPACE or pk == KEY_SPACE:
			_fire_pattern()
		elif k == KEY_R or pk == KEY_R:
			get_tree().reload_current_scene()
		elif k == KEY_H or pk == KEY_H:
			if _hud != null:
				_hud.visible = not _hud.visible
		elif k == KEY_C or pk == KEY_C:
			_fire_stele(true)    # C = 영혼 비석: 인간이 B(비석 파괴), NPC가 A(자동 버티기)
		elif k == KEY_V or pk == KEY_V:
			_fire_stele(false)   # V = 영혼 비석: 인간이 A(연타 버티기), NPC가 B(자동 파괴)


# C1 솔로 테스트 — 인간이 A/B 역할을 골라 발동. NPC(777)가 반대 역할을 자동으로 한다(설계 "둘다 테스트").
func _fire_stele(human_is_b: bool) -> void:
	if _coop == null:
		return
	if not TestMode.is_active():
		TestMode.activate()
	if _npc == null or not is_instance_valid(_npc):
		_spawn_npc()
	var victim := TestMode.NPC_PEER_ID    # 인간=B → NPC가 피해자(A)
	if not human_is_b:
		var lp := _local_player_node()    # 인간=A → 인간(로컬)이 피해자
		if lp != null:
			victim = int(lp.get("peer_id"))
	_coop.call("debug_force_stele", victim)


func _process(_d: float) -> void:
	if _cam != null and not _cam.is_current():
		_cam.make_current()
	# 플레이어 무적 — 보스는 공격하되 데미지 0
	for p: Node in get_tree().get_nodes_in_group("player"):
		var h := p.get_node_or_null("Health")
		if h != null:
			h.set("invincible", true)


func _cycle_pattern() -> void:
	if _pat_ids.is_empty():
		return
	_sel = (_sel + 1) % _pat_ids.size()
	_refresh_hud()


func _fire_pattern() -> void:
	if _pat_ids.is_empty() or _boss == null or not is_instance_valid(_boss):
		return
	if _boss.has_method("debug_force_pattern"):
		_boss.debug_force_pattern(_pat_ids[_sel])


# ---------------- HUD ----------------
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 50
	add_child(_hud)

	var top := Label.new()
	top.text = "패턴 [P]다음 [Space]발동  ·  영혼비석 [C]나=B(부수기) [V]나=A(버티기)  ·  [R]재시작 [H]숨김  ·  WASD·좌클릭(무적)"
	top.position = Vector2(8, 6)
	_hud.add_child(top)

	# 좌하 패턴 패널
	var pc := PanelContainer.new()
	pc.position = Vector2(8, 210)
	pc.custom_minimum_size = Vector2(280, 0)
	_hud.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)

	_pat_label = Label.new()
	vb.add_child(_pat_label)

	for f: Array in FIELDS:
		var field: String = f[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vb.add_child(row)
		var nl := Label.new()
		nl.text = field
		nl.custom_minimum_size = Vector2(78, 0)
		row.add_child(nl)
		var sld := HSlider.new()
		sld.min_value = f[1]
		sld.max_value = f[2]
		sld.step = f[3]
		sld.custom_minimum_size = Vector2(130, 0)
		sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sld)
		var vl := Label.new()
		vl.custom_minimum_size = Vector2(44, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		sld.value_changed.connect(func(v: float) -> void:
			vl.text = "%.2f" % v
			if _sel < _pat_defs.size() and _pat_defs[_sel] != null:
				_pat_defs[_sel].set(field, v))
		_sliders[field] = {"slider": sld, "vl": vl}

	_refresh_hud()


func _refresh_hud() -> void:
	if _pat_ids.is_empty():
		_pat_label.text = "패턴 없음"
		return
	var d: Variant = _pat_defs[_sel]
	_pat_label.text = "패턴 %d/%d:  %s  (%s)" % [_sel + 1, _pat_ids.size(), _pat_ids[_sel], str(d.get("shape"))]
	for f: Array in FIELDS:
		var field: String = f[0]
		var entry: Dictionary = _sliders[field]
		var sld := entry["slider"] as HSlider
		var v: float = float(d.get(field))
		sld.set_value_no_signal(v)
		(entry["vl"] as Label).text = "%.2f" % v


# ---------------- 카메라 / 바운드 ----------------
func _build_camera() -> void:
	_cam = Camera2D.new()
	_cam.position = ARENA_CENTER
	_cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	_cam.position_smoothing_enabled = false
	add_child(_cam)
	_cam.make_current()


func _build_bounds(stage: Node) -> void:
	var body := StaticBody2D.new()
	body.name = "ArenaBounds"
	body.collision_layer = 1
	body.collision_mask = 0
	var t := 24.0
	var hw := ARENA_HALF.x
	var hh := ARENA_HALF.y
	var walls: Array = [
		[Vector2(ARENA_CENTER.x, ARENA_CENTER.y - hh - t * 0.5), Vector2(hw * 2 + t * 2, t)],
		[Vector2(ARENA_CENTER.x, ARENA_CENTER.y + hh + t * 0.5), Vector2(hw * 2 + t * 2, t)],
		[Vector2(ARENA_CENTER.x - hw - t * 0.5, ARENA_CENTER.y), Vector2(t, hh * 2 + t * 2)],
		[Vector2(ARENA_CENTER.x + hw + t * 0.5, ARENA_CENTER.y), Vector2(t, hh * 2 + t * 2)],
	]
	for w: Array in walls:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = w[1]
		cs.shape = shape
		cs.position = w[0]
		body.add_child(cs)
	stage.add_child(body)


# 돌진(P3) HIT→그로기 분기 테스트용 디버그 바위 — "boss_rock" 그룹 + layer 1(보스가 물리로 박음).
# 실제 P4 낙석 바위가 같은 그룹·레이어를 재사용한다. 보스↔플레이어 경로(y~320) 사이에 둔다.
func _build_debug_rock() -> void:
	var rock := StaticBody2D.new()
	rock.name = "DebugRock"
	rock.add_to_group("boss_rock")
	rock.collision_layer = 1
	rock.collision_mask = 0
	rock.position = Vector2(500, 320)
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	cs.shape = shape
	rock.add_child(cs)
	var poly := Polygon2D.new()   # 회색 바위 마커(디버그 표시) — P4 스프라이트로 대체 예정
	poly.color = Color(0.44, 0.42, 0.40)
	poly.polygon = PackedVector2Array([
		Vector2(-24, -8), Vector2(-11, -24), Vector2(15, -22),
		Vector2(24, -2), Vector2(17, 22), Vector2(-13, 24), Vector2(-26, 7)])
	rock.add_child(poly)
	_stage.add_child(rock)


# ---------------- 자가 캡처 테스트 (`-- swcap`) ----------------
func _capture_test() -> void:
	await get_tree().create_timer(1.2).timeout
	if _hud != null:
		_hud.visible = false
	var args := OS.get_cmdline_user_args()
	if args.has("slam"):
		_sel = 1   # P2 원형 테스트
	elif args.has("charge"):
		_sel = 2   # P3 돌진 테스트
	elif args.has("rock"):
		_sel = 3   # P4 낙석 테스트
	elif args.has("spin"):
		_sel = 4   # P5 도끼 회전 테스트
	if args.has("stele"):
		await _capture_stele()
		return
	if args.has("charge"):
		await _capture_charge()
		return
	if args.has("rock"):
		var names := ["IDLE", "CHASE", "WINDUP", "RECOVER", "CHARGE_DASH", "CHARGE_HIT"]
		print("[ROCK] pat=", _pat_ids[_sel], " burst=", _pat_defs[_sel].get("burst_count"), " leaves_rock=", _pat_defs[_sel].get("leaves_rock"))
		_fire_pattern()
		for i in 14:   # ~2.8s
			await get_tree().create_timer(0.2).timeout
			var st := int(_boss.get("_state"))
			var rc := get_tree().get_nodes_in_group("boss_rock").size()
			print("[ROCK] t=%.1f state=%s rocks=%d" % [i * 0.2, names[st] if st < names.size() else str(st), rc])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/ACE/Desktop/bobs_project/aseprite-mcp/sw_capture.png")
		get_tree().quit()
		return
	_fire_pattern()
	await get_tree().create_timer(0.4).timeout   # 예고 중
	await RenderingServer.frame_post_draw
	if _boss != null and _sprite != null:
		print("[CAP] pat=", _pat_ids[_sel] if not _pat_ids.is_empty() else "-", " anim=", _sprite.animation, " face=", _boss.get("_face_dir"))
	get_viewport().get_texture().get_image().save_png("C:/Users/ACE/Desktop/bobs_project/aseprite-mcp/sw_capture.png")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()


# ---------------- C1 영혼 비석 결박 자가 테스트 (`-- swcap stele`) ----------------
# TestMode 활성 + 가짜 파트너(NPC 777=A) 스폰 → STELE 발동 → B 타격 시뮬레이션으로 내구도 0 → 보스 그로기 확인.
func _capture_stele() -> void:
	if _coop == null:
		print("[STELE] CoopAuthority 없음 — stage_boss 배선 확인")
		get_tree().quit()
		return
	TestMode.activate()
	_spawn_npc()
	await get_tree().create_timer(0.4).timeout
	var args := OS.get_cmdline_user_args()
	var human_a := args.has("va")   # va = 인간이 A(연타 버티기), NPC가 B(자동 파괴). 기본 = 인간 B
	var fail_mode := args.has("fail")
	var victim := TestMode.NPC_PEER_ID
	if human_a:
		var lp := _local_player_node()
		if lp != null:
			victim = int(lp.get("peer_id"))
	_coop.call("debug_force_stele", victim)
	if fail_mode:
		_coop.set("_resist", 9.0)   # 빠른 실패 유도
	print("[STELE] fired human=%s victim=%d NPC=%d fail=%s" % [
		("A" if human_a else "B"), int(_coop.get("_victim")), TestMode.NPC_PEER_ID, str(fail_mode)])
	var saved := false
	for i in 70:   # ~10.5s (A역할은 NPC-B 2/s라 더 걸린다)
		await get_tree().create_timer(0.15).timeout
		if bool(_coop.get("_active")) and not fail_mode:
			if human_a:
				_coop.call("_stele_a_mash")   # 인간 A 버티기 시뮬 → NPC-B가 자동으로 비석 깬다
			else:
				_coop.call("_stele_b_hit")    # 인간 B 타격 시뮬 → NPC-A가 자동 버틴다
		var dura := float(_coop.get("_stele_dura"))
		var resist := float(_coop.get("_resist"))
		var groggy: float = float(_boss.get("groggy_left")) if _boss != null else 0.0
		if i % 3 == 0 or groggy > 0.0:
			print("[STELE] t=%.1f dura=%.0f resist=%.0f active=%s groggy=%.2f" % [
				i * 0.15, dura, resist, str(_coop.get("_active")), groggy])
		if i == 18:   # 중간(가시 링 방출 구간 ~2.7s) — 비석·결박선·가시 링 렌더 확인용
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("C:/Users/ACE/Desktop/bobs_project/aseprite-mcp/sw_stele_mid.png")
		if groggy > 0.0 and not saved:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("C:/Users/ACE/Desktop/bobs_project/aseprite-mcp/sw_capture.png")
			saved = true
			break
	if not saved:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/ACE/Desktop/bobs_project/aseprite-mcp/sw_capture.png")
	get_tree().quit()


func _spawn_npc() -> void:
	var lp := _local_player_node()
	var base: Vector2 = (lp as Node2D).global_position if lp != null else Vector2(320, 340)
	var scene_id: String = str(lp.get("scene_id")) if lp != null else ""
	var p := PlayerScene.instantiate()
	_stage.add_child(p)
	p.call("setup", TestMode.NPC_PEER_ID, false, base + Vector2(48, 0), scene_id)
	if GameState.job_def("warrior") != null:
		p.call("set_job", GameState.job_def("warrior"))
	var h := p.get_node_or_null("Health")
	if h != null:
		h.set("invincible", true)
	_npc = p


func _local_player_node() -> Node:
	for pl: Node in get_tree().get_nodes_in_group("player"):
		if pl.get("is_local") == true:
			return pl
	return null


# 돌진(P3)은 모션이라 단일 PNG로 못 본다 — 상태 궤적을 표본해 WINDUP→CHARGE_DASH→CHARGE_HIT→그로기와
# 위치가 바위 쪽으로 이동 후 멈추는지 찍는다. 마지막에 그로기 순간을 캡처한다.
func _capture_charge() -> void:
	var names := ["IDLE", "CHASE", "WINDUP", "RECOVER", "CHARGE_DASH", "CHARGE_HIT"]
	var b := _boss as Node2D
	var start_x: float = b.global_position.x
	_fire_pattern()
	var saved := false
	for i in 30:   # ~3.0s
		await get_tree().create_timer(0.1).timeout
		if _boss == null or not is_instance_valid(_boss):
			break
		var st := int(_boss.get("_state"))
		var groggy := float(_boss.get("groggy_left"))
		print("[CHG] t=%.1f state=%s x=%.0f dx=%.0f groggy=%.2f" % [
			i * 0.1, names[st] if st < names.size() else str(st),
			b.global_position.x, b.global_position.x - start_x, groggy])
		if groggy > 0.0 and not saved:   # 그로기(박은 뒤 처벌창) 순간 캡처
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("C:/Users/ACE/Desktop/bobs_project/aseprite-mcp/sw_capture.png")
			saved = true
	if not saved:   # 헛참(바위 안 박음) — 마지막 프레임이라도 남긴다
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/ACE/Desktop/bobs_project/aseprite-mcp/sw_capture.png")
	get_tree().quit()
