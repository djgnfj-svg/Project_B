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

var _invincible: bool = true
var _npc_on: bool = true

var _cb_invin: CheckBox = null
var _cb_boss: CheckBox = null
var _cb_coop: CheckBox = null
var _cb_npc: CheckBox = null
var _hp_label: Label = null


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
	_reposition_near_boss()   # 보스+player+NPC가 한 화면에 보이게
	_build_panel()


# 랩 시작 시 플레이어·NPC를 보스 근처로 옮긴다 (그림처럼 한 화면에). 솔로 호스트라 로컬 배치로 충분.
func _reposition_near_boss() -> void:
	if _boss == null:
		return
	var bp: Vector2 = _boss.global_position
	var lp := _local_player()
	if lp != null:
		lp.global_position = bp + Vector2(-20.0, 120.0)   # 보스 아래 → 카메라가 보스를 중앙-위에 둠(우측 패널 안 가림)
	if _npc != null and is_instance_valid(_npc):
		_npc.global_position = bp + Vector2(-110.0, 100.0)


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
	add_child(layer)

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
	if _hp_label == null:
		return
	var lp := _local_player()
	if lp == null:
		return
	var h := lp.get_node_or_null("Health") as HealthComponent
	if h != null:
		_hp_label.text = "HP %d/%d %s" % [h.hp, h.max_hp, "🛡" if h.invincible else ""]
