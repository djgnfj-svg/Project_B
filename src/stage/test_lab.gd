extends Node
# 테스트 랩 컨트롤러 — ?test=1일 때 main이 보스 아레나에 붙인다 (TestMode 게이트, 프로덕션 무접촉·rules §5 씬 글루).
# 그림 구조: 아레나[보스 + player1(무적) + NPC 더미(무적, 코옵 2인 채움)] + 우측 패턴/상태 패널.
#  · 보스 자동공격·코옵 자동순환을 끄고(debug_hold) → 버튼으로 특정 패턴만 즉시 발동해 관찰·튜닝.
#  · 체크박스로 현재 상태(무적/보스정지/코옵정지/NPC) 확인·토글. HP 회복 버튼.
#  · 2인 실기: NPC 체크 해제하면 더미 제거 → 실제 2명으로 테스트.

const PlayerScene := preload("res://src/player/player.tscn")
const PlayerActor := preload("res://src/player/player.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")

# 보스 공격 패턴 버튼 (id = wraith_boss.tres 패턴 id)
const BOSS_BTNS: Array = [["검기", "swing"], ["슬램", "slam"], ["물뿌리기", "spray"]]
# 코옵 파훼 버튼 (인덱스 = coop_authority MECHS 순서)
const COOP_BTNS: Array = [["케이지", 0], ["별낙하", 1], ["봉인진", 2], ["분산", 3], ["뭉치기", 4], ["직면", 5]]

var _boss: Node = null
var _coop: Node = null
var _npc: PlayerActor = null
var _boss_rim: AnimatedSprite2D = null   # 보스 뒤 밝은 실루엣(림) — 청록 배경에서 보스를 또렷하게

var _invincible: bool = true
var _npc_on: bool = true

var _cb_invin: CheckBox = null
var _cb_boss: CheckBox = null
var _cb_coop: CheckBox = null
var _cb_npc: CheckBox = null
var _hp_label: Label = null

# 2방(젤다식 화면 전환) — 왼쪽 진입 방 + 오른쪽 보스 방. 카메라를 현재 방에 클램프, 경계 넘으면 스냅.
const ROOM_SPLIT_X := 192.0
const ROOM1 := Rect2(-576.0, 100.0, 768.0, 448.0)   # 진입 방(왼쪽)
const ROOM2 := Rect2(192.0, 100.0, 768.0, 448.0)    # 보스 방(오른쪽 = 현 성역)
var _cur_room: int = 0
var _sealed: bool = false
var _panel_layer: CanvasLayer = null   # 패턴 패널(토글) — 기본 숨김이라 맵이 깨끗하게 보임. P로 토글.


func _ready() -> void:
	if not TestMode.is_active():
		queue_free()
		return
	# peer_sync가 플레이어를 call_deferred로 스폰하므로 한 프레임 뒤 셋업
	_setup.call_deferred()


func _setup() -> void:
	_boss = get_parent().get_node_or_null("Boss")
	_coop = get_parent().get_node_or_null("CoopAuthority")
	if _boss != null:
		_boss.debug_hold = true       # 보스 자동공격 정지 (버튼으로만)
	if _coop != null:
		_coop.debug_hold = true       # 코옵 자동순환 정지 (버튼으로만)
	_apply_invincible()
	_spawn_npc()
	_reposition()             # 보스·NPC=보스 방, 플레이어=진입 방
	_build_bounds()           # 2방 벽 + 진입 방 바닥 + 바깥 void
	_setup_camera()           # 방 카메라 (클램프+스냅)
	_setup_lighting()         # 2D 라이팅 — 어두운 성역 + 발광 지점(맵 퀄업)
	_apply_boss_rim()         # 보스 밝은 림(뒤 실루엣) — 청록 배경에서 또렷하게
	_setup_particles()        # 떠다니는 데이터 모트 (공간감)
	_setup_floor_detail()     # 바닥 데이터 글리프 디테일 (가장자리 위주)
	_build_panel()


# ① 떠다니는 데이터 모트 — 어두운 성역에 청록 입자가 느리게 부유. 방 두 개를 아우르는 넓은 방출.
func _setup_particles() -> void:
	var p := GPUParticles2D.new()
	p.amount = 90
	p.lifetime = 7.0
	p.preprocess = 4.0
	p.texture = _light_tex()
	p.z_index = 6
	p.modulate = Color(0.45, 0.62, 0.8, 0.38)   # 청록 완화 → 배경 부유 입자가 보스와 안 겹침
	p.visibility_rect = Rect2(-620.0, 60.0, 1640.0, 520.0)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(768.0, 224.0, 1.0)
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 50.0
	m.gravity = Vector3(0.0, -5.0, 0.0)
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 9.0
	m.scale_min = 0.015
	m.scale_max = 0.05
	p.process_material = m
	get_parent().add_child(p)
	p.global_position = Vector2(192.0, 324.0)


# ③ 바닥 데이터 글리프 — 작은 룬/코드 조각을 방 가장자리·중간 링에 산재(중앙 전장은 비움 = FX 안 묻힘).
# 데칼 시트 8칸(24×24 그리드) — floor_decals.png
const DECAL_REGIONS := [
	Rect2(0, 0, 24, 24), Rect2(24, 0, 24, 24), Rect2(48, 0, 24, 24), Rect2(72, 0, 24, 24),
	Rect2(0, 24, 24, 24), Rect2(24, 24, 24, 24), Rect2(48, 24, 24, 24), Rect2(72, 24, 24, 24),
]

# 선택된 4종만 어울리게 배치 (1 코드룬A · 2 코드룬B · 5 균열 · 10 큰룬사인). 중앙 전장은 비움.
func _setup_floor_detail() -> void:
	var decals: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/stage/floor_decals.png"):
		decals = load("res://assets/sprites/stage/floor_decals.png")
	var objects: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/stage/floor_objects.png"):
		objects = load("res://assets/sprites/stage/floor_objects.png")
	# 10 큰룬사인 (feature) — 각 방 바닥에 크게, 중앙 피함
	if objects != null:
		for p: Vector2 in [Vector2(-390, 320), Vector2(120, 205), Vector2(430, 445), Vector2(770, 300)]:
			_scatter(objects, Rect2(48, 0, 48, 48), p, 1.5, false)
	if decals != null:
		# 1 코드룬A
		for p: Vector2 in [Vector2(-500, 180), Vector2(-250, 460), Vector2(40, 190), Vector2(330, 175), Vector2(650, 465), Vector2(900, 200)]:
			_scatter(decals, Rect2(0, 0, 24, 24), p, 2.0, true)
		# 2 코드룬B
		for p: Vector2 in [Vector2(-420, 455), Vector2(-120, 165), Vector2(-540, 320), Vector2(470, 480), Vector2(560, 155), Vector2(940, 440)]:
			_scatter(decals, Rect2(24, 0, 24, 24), p, 2.0, true)
		# 5 균열
		for p: Vector2 in [Vector2(-330, 485), Vector2(-90, 470), Vector2(230, 450), Vector2(700, 165), Vector2(820, 480), Vector2(280, 160)]:
			_scatter(decals, Rect2(0, 24, 24, 24), p, 2.3, true)


func _scatter(sheet: Texture2D, region: Rect2, pos: Vector2, sc: float, rot: bool) -> void:
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = region
	var sp := Sprite2D.new()
	sp.texture = at
	if rot:
		sp.rotation = randf() * TAU
	sp.scale = Vector2.ONE * (sc * (0.85 + randf() * 0.35))
	# 어둡고 남색기 도는 저채도 → 청록 보스와 경쟁하지 않음
	sp.modulate = Color(0.55, 0.68, 0.78, 0.4 + randf() * 0.2)
	sp.z_index = -8
	get_parent().add_child(sp)
	sp.global_position = pos


# 2D 라이팅 — CanvasModulate로 씬을 어둡게 하고, 룬·제단·대문·균열이 빛나게(PointLight2D 가산).
# 배경(아레나 Sprite2D)이 조명을 받는다(2d-essentials §4·§10). Compatibility에서 작동.
func _light_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


func _add_light(pos: Vector2, col: Color, energy: float, scale: float, parent: Node = null) -> void:
	var l := PointLight2D.new()
	l.texture = _light_tex()
	l.color = col
	l.energy = energy
	l.texture_scale = scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	if parent != null:
		parent.add_child(l)
		l.position = pos
	else:
		get_parent().add_child(l)
		l.global_position = pos


func _setup_lighting() -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.10, 0.10, 0.15)   # 씬 더 어둡게 → 집중광이 튄다
	get_parent().add_child(cm)
	# 성역 발광 지점 — 청록이 아니라 차분한 남색으로(에너지↓) → 보스의 청록만 유일하게 밝은 청록이 됨
	_add_light(Vector2(852.0, 324.0), Color(0.28, 0.46, 0.62), 1.1, 2.1)   # 제단/룬
	_add_light(Vector2(150.0, 324.0), Color(0.3, 0.48, 0.66), 1.0, 1.7)    # 대문 빛
	_add_light(Vector2(-500.0, 300.0), Color(0.32, 0.48, 0.6), 1.0, 1.3)   # 진입 균열
	# 플레이어 따라다니는 빛 (시야 확보 — 은은하게, 캐릭터가 하얗게 뜨지 않게)
	var lp := _local_player()
	if lp != null:
		_add_light(Vector2.ZERO, Color(0.8, 0.84, 0.95), 1.0, 1.3, lp)
	# 보스 으스스한 빛 — 배경 청록을 죽였으니 여기가 가장 밝은 청록이 되어 보스가 튄다 (은은하게)
	if _boss != null:
		_add_light(Vector2.ZERO, Color(0.5, 0.9, 0.78), 1.2, 1.15, _boss)


# A. 보스 밝은 림 — 같은 SpriteFrames를 공유하는 뒤쪽 실루엣을 살짝 키워 발광시킨다.
#    아틀라스 시트라 아웃라인 셰이더는 이웃 프레임을 샘플해 번지므로, 복제 실루엣 + _process 프레임 동기화로.
func _apply_boss_rim() -> void:
	if _boss == null:
		return
	var spr := _boss.get_node_or_null("Sprite") as AnimatedSprite2D
	if spr == null or spr.sprite_frames == null:
		return
	spr.z_index = 2                     # 실제 스프라이트를 림 위로
	var rim := AnimatedSprite2D.new()
	rim.sprite_frames = spr.sprite_frames
	rim.scale = spr.scale * 1.08        # 살짝 크게 → 테두리만 삐져나옴 (은은하게)
	rim.z_index = 1                     # 실루엣은 보스 바로 뒤 (그림자 -2 · 텔레그래프 -1 위)
	rim.modulate = Color(0.4, 0.8, 0.66, 0.5)   # 은은한 청록 발광 (반투명)
	rim.material = CanvasItemMaterial.new()
	(rim.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.add_sibling(rim)
	rim.position = spr.position
	_boss_rim = rim


# 방 카메라 = 플레이어 카메라를 현재 방 경계에 클램프(따라가되 방 안에만). 경계 넘으면 리밋 스왑 = 스냅.
func _setup_camera() -> void:
	_apply_room_camera(1)   # 진입 방부터


func _player_cam() -> Camera2D:
	var lp := _local_player()
	if lp == null:
		return null
	for c: Node in lp.get_children():
		if c is Camera2D:
			return c as Camera2D
	return null


func _apply_room_camera(room: int) -> void:
	var cam := _player_cam()
	if cam == null:
		return
	var rc: Rect2 = ROOM2 if room == 2 else ROOM1
	cam.limit_left = int(rc.position.x)
	cam.limit_top = int(rc.position.y)
	cam.limit_right = int(rc.position.x + rc.size.x)
	cam.limit_bottom = int(rc.position.y + rc.size.y)
	cam.reset_smoothing()   # 방 전환 스냅


# 보스 방 진입 시 뒤 통로 봉쇄 — 못 돌아감(물리 벽).
func _seal_threshold() -> void:
	if _sealed:
		return
	_sealed = true
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	get_parent().add_child(wall)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(40.0, 460.0)
	cs.shape = r
	cs.position = Vector2(ROOM_SPLIT_X, 324.0)
	wall.add_child(cs)


# 좌→우 배치: 보스는 오른쪽 제단, 플레이어·NPC는 왼쪽 진입 지점. (아레나 필드 월드 좌표 기준)
func _reposition() -> void:
	# 보스·NPC = 오른쪽 보스 방, 플레이어 = 왼쪽 진입 방에서 시작
	if _boss != null:
		_boss.global_position = Vector2(852.0, 324.0)    # 보스 방 제단
	if _npc != null and is_instance_valid(_npc):
		_npc.global_position = Vector2(700.0, 372.0)     # 보스 방 (코옵 파트너 대기)
	var lp := _local_player()
	if lp != null:
		lp.global_position = Vector2(-300.0, 324.0)      # 진입 방 왼쪽 시작


# 아레나 필드 경계 = 충돌 벽으로 플레이어를 가둔다 + 바깥 바닥을 어둡게 해 "맵 밖"을 확실히 구분.
# 아레나 스프라이트 = 768×448 중심 (576,324) → 월드 필드 대략 x[192,960] y[100,548], 안쪽 벽 면.
func _build_bounds() -> void:
	# 바깥(주변 타일)을 거의 검정 void로 → 방 밖이 확실히 구분
	var ground := get_parent().get_node_or_null("Ground") as CanvasItem
	if ground != null:
		ground.modulate = Color(0.07, 0.07, 0.1)
	# 진입 방 바닥 스프라이트 (보스 방 왼쪽에). 아트 없으면 스킵.
	if ResourceLoader.exists("res://assets/sprites/stage/approach_room.png"):
		var s := Sprite2D.new()
		s.texture = load("res://assets/sprites/stage/approach_room.png")
		s.position = Vector2(-192.0, 324.0)   # 보스 방(576) 왼쪽으로 768
		s.z_index = -10
		get_parent().add_child(s)
	# 충돌 벽 — 두 방을 아우르는 바깥 경계 (world x[-576,960]). 방 사이 통로는 열림.
	var walls := StaticBody2D.new()
	walls.collision_layer = 1   # world (플레이어 mask=1)
	walls.collision_mask = 0
	get_parent().add_child(walls)
	var segs := [
		[Vector2(-606.0, 324.0), Vector2(60.0, 500.0)],   # 진입 방 왼쪽 끝
		[Vector2(946.0, 324.0), Vector2(60.0, 500.0)],    # 보스 방 오른쪽 끝
		[Vector2(192.0, 130.0), Vector2(1600.0, 60.0)],   # 위 (두 방 가로지름)
		[Vector2(192.0, 518.0), Vector2(1600.0, 60.0)],   # 아래
	]
	for s2: Array in segs:
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = s2[1]
		cs.shape = r
		cs.position = s2[0]
		walls.add_child(cs)


# ── 참가자 ──
func _local_player() -> PlayerActor:
	for n: Node in get_tree().get_nodes_in_group("player"):
		var p := n as PlayerActor
		if p != null and p.is_local:
			return p
	return null


func _real_player_count() -> int:
	var c := 0
	for n: Node in get_tree().get_nodes_in_group("player"):
		var p := n as PlayerActor
		if p != null and p.peer_id != TestMode.NPC_PEER_ID:
			c += 1
	return c


func _apply_invincible() -> void:
	var lp := _local_player()
	if lp == null:
		return
	var h := lp.get_node_or_null("Health") as HealthComponent
	if h != null:
		h.invincible = _invincible


func _heal_full() -> void:
	var lp := _local_player()
	if lp == null:
		return
	var h := lp.get_node_or_null("Health") as HealthComponent
	if h != null:
		h.confirm_hp(h.max_hp)     # 권한 경로 회복 (솔로 = 나는 호스트)


func _spawn_npc() -> void:
	if _npc != null and is_instance_valid(_npc):
		return
	if _real_player_count() >= 2:
		return   # 2인 실기 — 더미 불필요
	var lp := _local_player()
	var base: Vector2 = lp.global_position if lp != null else Vector2(320.0, 200.0)
	var scene_id: String = lp.scene_id if lp != null else ""
	var p := PlayerScene.instantiate() as PlayerActor
	get_parent().add_child(p)
	p.setup(TestMode.NPC_PEER_ID, false, base + Vector2(-90.0, 0.0), scene_id)
	p.set_job(GameState.job_def("warrior"))
	var h := p.get_node_or_null("Health") as HealthComponent
	if h != null:
		h.invincible = true          # NPC 더미도 무적 (코옵 판정에서 자동 통과 = coop_authority 처리)
	_npc = p


func _despawn_npc() -> void:
	if _npc != null and is_instance_valid(_npc):
		_npc.queue_free()
	_npc = null


# ── 패널 UI (우측 세로 바 — 아레나는 왼쪽, 클릭 안 막음) ──
func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.visible = false          # 기본 숨김 → 맵이 깨끗하게 풀로 보임. P로 토글.
	add_child(layer)
	_panel_layer = layer
	# 항상 보이는 작은 힌트 (우상단)
	var hint_layer := CanvasLayer.new()
	hint_layer.layer = 19
	add_child(hint_layer)
	var hint := Label.new()
	hint.text = "[P] 패턴 랩"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.9, 0.7))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.add_theme_constant_override("outline_size", 3)
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -84.0
	hint.offset_top = 2.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_layer.add_child(hint)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -156.0
	panel.offset_top = 4.0
	panel.offset_right = -4.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	_add_title(vb, "◆ 패턴 랩")
	_add_title(vb, "· 보스")
	var g_boss := _grid(vb, 3)
	for e: Array in BOSS_BTNS:
		_add_btn(g_boss, str(e[0]), _on_boss.bind(str(e[1])))
	_add_title(vb, "· 코옵")
	var g_coop := _grid(vb, 2)
	for e: Array in COOP_BTNS:
		_add_btn(g_coop, str(e[0]), _on_coop.bind(int(e[1])))

	vb.add_child(HSeparator.new())
	var g_chk := _grid(vb, 2)
	_cb_invin = _add_check(g_chk, "무적", _invincible, _on_invin)
	_cb_boss = _add_check(g_chk, "보스정지", true, _on_boss_hold)
	_cb_coop = _add_check(g_chk, "코옵정지", true, _on_coop_hold)
	_cb_npc = _add_check(g_chk, "NPC", _npc_on, _on_npc_toggle)
	_add_btn(vb, "HP 회복", _heal_full)
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 11)
	vb.add_child(_hp_label)


func _grid(parent: Node, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	parent.add_child(g)
	return g


func _add_title(vb: VBoxContainer, txt: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	vb.add_child(l)


func _add_btn(parent: Node, txt: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE   # 버튼 포커스가 이후 게임 입력을 먹지 않게
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(48.0, 22.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _add_check(parent: Node, txt: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = txt
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 11)
	c.toggled.connect(cb)
	parent.add_child(c)
	return c


# ── 버튼 핸들러 ──
func _on_boss(pid: String) -> void:
	if _boss != null and _boss.has_method("debug_force_pattern"):
		_boss.debug_force_pattern(pid)


func _on_coop(idx: int) -> void:
	if _coop != null and _coop.has_method("debug_force_mech"):
		_coop.debug_force_mech(idx)


func _on_invin(on: bool) -> void:
	_invincible = on
	_apply_invincible()


func _on_boss_hold(on: bool) -> void:
	if _boss != null:
		_boss.debug_hold = on


func _on_coop_hold(on: bool) -> void:
	if _coop != null:
		_coop.debug_hold = on


func _on_npc_toggle(on: bool) -> void:
	_npc_on = on
	if on:
		_spawn_npc()
	else:
		_despawn_npc()


func _process(_delta: float) -> void:
	# 보스 림 실루엣을 실제 스프라이트와 프레임/방향 동기화
	if _boss_rim != null and is_instance_valid(_boss_rim) and _boss != null:
		var bspr := _boss.get_node_or_null("Sprite") as AnimatedSprite2D
		if bspr != null and bspr.sprite_frames != null:
			if bspr.animation != _boss_rim.animation and bspr.sprite_frames.has_animation(bspr.animation):
				_boss_rim.animation = bspr.animation
			_boss_rim.frame = bspr.frame
			_boss_rim.flip_h = bspr.flip_h
	var lp := _local_player()
	if lp == null:
		return
	# 방 전환(젤다식): 경계 넘으면 카메라 스냅 + 보스 방 진입 시 뒤 통로 봉쇄
	var room := 2 if lp.global_position.x >= ROOM_SPLIT_X else 1
	if room != _cur_room:
		_cur_room = room
		_apply_room_camera(room)
		if room == 2:
			_seal_threshold()
	if _hp_label != null:
		var h := lp.get_node_or_null("Health") as HealthComponent
		if h != null:
			_hp_label.text = "HP %d/%d %s" % [h.hp, h.max_hp, "🛡" if h.invincible else ""]


# P = 패턴 패널 토글 (기본 숨김 → 맵 깨끗). 게임 입력과 안 겹치는 키.
func _unhandled_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke != null and ke.pressed and not ke.echo and ke.physical_keycode == KEY_P:
		if _panel_layer != null:
			_panel_layer.visible = not _panel_layer.visible
		get_viewport().set_input_as_handled()
