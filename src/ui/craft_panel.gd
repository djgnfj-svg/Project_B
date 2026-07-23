extends CanvasLayer
# 제작/강화 패널 (슬라이스 2 모달) — 마을 제작대가 F로 여는 오버레이.
# settings_panel 모달 패턴을 복제·확장했다(rules §5·verify §2-1):
#  - 루트 = CanvasLayer, 기본 visible=false. 닫히면 완전히 숨겨 뒤 게임 클릭을 안 막는다.
#  - Backdrop(ColorRect, mouse_filter=STOP)이 열려 있는 동안만 뒤 게임 클릭을 막는다(마우스만 모달).
#  - Center(CenterContainer)는 mouse_filter=IGNORE — 화면을 덮지만 클릭을 안 먹는다(rules §5 1번 함정).
#
# ⚠ 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지. 다른 플레이어는 계속 움직인다.
#   마우스만 모달(Backdrop STOP)이고, F/Esc 키만 이 패널이 소비해 닫는다.
# 모든 데이터/조작은 GameState API(로컬·네트워크 0개) + CombatMath 단일 소스(rules §3)로만 한다.
# ⚠ UI 씬 스크립트라 전역 오토로드(GameState·EventBus·CombatMath·Audio) 직접 접근 OK
#   (헤드리스 -s 대상 아님, rules §5). class_name 선언은 하지 않는다(서브에이전트 규칙 §0).

const UiTheme := preload("res://src/ui/ui_theme.gd")
const ItemUi := preload("res://src/ui/item_ui.gd")

@onready var _close_btn: Button = %CloseBtn
@onready var _inv_row: HBoxContainer = %InvRow
@onready var _tabs: TabContainer = %Tabs
@onready var _craft_list: VBoxContainer = %CraftList
@onready var _upgrade_list: VBoxContainer = %UpgradeList

signal closed

# 열린 프레임에 온 interact(F)가 곧바로 close로 튀는 걸 막는 1프레임 가드.
# (제작대가 F로 open()을 부르고, 같은 F가 _unhandled_input의 닫기 핸들러에 잡히는 이중 처리 방지)
var _ignore_toggle: bool = false


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (인벤/창고와 통일)
	_close_btn.pressed.connect(close)
	_tabs.set_tab_title(0, "제작")
	_tabs.set_tab_title(1, "강화")
	# 픽업으로 재료가 늘면(inventory_changed) 열려 있는 동안 즉시 반영.
	EventBus.inventory_changed.connect(_on_inventory_changed)


# --- 공개 API (제작대가 부른다) ---

func open() -> void:
	_ignore_toggle = true
	call_deferred("_clear_ignore_toggle")  # 같은 프레임 F 소진 방지 (프레임 끝에 해제)
	_refresh()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _clear_ignore_toggle() -> void:
	_ignore_toggle = false


# F(interact)/Esc(ui_cancel)로 닫기. ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로
# (rules §5) 반드시 visible 가드 — 안 그러면 닫힌 패널이 제작대의 F를 삼킨다.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not _ignore_toggle:
		close()
		get_viewport().set_input_as_handled()


func _on_inventory_changed() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	_refresh_inv_bar()
	_refresh_craft()
	_refresh_upgrade()


# --- 인벤 바 (공통): 골드 + 보유 재료 ---

func _refresh_inv_bar() -> void:
	_clear(_inv_row)
	var gold := Label.new()
	gold.text = "골드 %d" % GameState.gold
	_inv_row.add_child(gold)
	for mid: String in GameState.materials:
		var qty := int(GameState.materials[mid])
		if qty <= 0:
			continue
		var mdef := GameState.material_def(mid)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.tooltip_text = ItemUi.material_tooltip(mdef, qty) if mdef != null else mid  # 아이템 상세 hover
		cell.add_child(_make_icon(mdef.icon if mdef != null else null))
		var lbl := Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_txt := mdef.display_name if mdef != null else mid
		lbl.text = "%s %d" % [name_txt, qty]
		cell.add_child(lbl)
		_inv_row.add_child(cell)


# --- 제작 탭: 언락된 레시피 나열 ---

func _refresh_craft() -> void:
	_clear(_craft_list)
	var shown := 0
	for rid: String in GameState.recipe_ids():
		if not GameState.has_blueprint(rid):
			continue
		var recipe := GameState.recipe_def(rid)
		if recipe == null:
			continue
		_craft_list.add_child(_make_craft_row(rid, recipe))
		shown += 1
	if shown == 0:
		_craft_list.add_child(_make_empty_label("보유한 설계도가 없습니다"))


func _make_craft_row(rid: String, recipe: RecipeDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var result := GameState.equip_def(recipe.result_equip_id)
	if result != null:
		var base := CombatMath.equip_stat_at_level(result, 0)  # 제작 결과는 Lv.0
		row.tooltip_text = ItemUi.equip_tooltip(result, 0, int(base["attack"]), int(base["hp"]))
	row.add_child(_make_icon(result.icon if result != null else null))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 행 툴팁이 이 영역 hover에서도 뜨게 이벤트 통과
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = result.display_name if result != null else recipe.result_equip_id
	info.add_child(name_lbl)
	var cost_lbl := Label.new()
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_lbl.text = _craft_cost_text(recipe)
	cost_lbl.add_theme_font_size_override("font_size", 10)
	info.add_child(cost_lbl)
	row.add_child(info)

	var btn := Button.new()
	btn.text = "제작"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(64, 0)
	btn.disabled = not GameState.can_craft(rid)
	btn.pressed.connect(_on_craft_pressed.bind(rid))
	row.add_child(btn)
	return row


func _craft_cost_text(recipe: RecipeDef) -> String:
	var parts: Array[String] = []
	parts.append("골드 %d/%d" % [GameState.gold, recipe.gold_cost])
	for mid: String in recipe.material_costs:
		var need := int(recipe.material_costs[mid])
		var have := GameState.material_count(mid)
		var mdef := GameState.material_def(mid)
		var name_txt := mdef.display_name if mdef != null else mid
		parts.append("%s %d/%d" % [name_txt, have, need])
	return " · ".join(parts)


func _on_craft_pressed(rid: String) -> void:
	if GameState.craft(rid):  # 성공 시 GameState가 inventory_changed emit → _refresh 자동
		_commit_save()


# --- 강화 탭: 보유 장비 나열 (강화 + 장착) ---

func _refresh_upgrade() -> void:
	_clear(_upgrade_list)
	if GameState.owned_equipment.is_empty():
		_upgrade_list.add_child(_make_empty_label("보유한 장비가 없습니다"))
		return
	for eid: String in GameState.owned_equipment:
		var equip := GameState.equip_def(eid)
		if equip == null:
			continue
		_upgrade_list.add_child(_make_upgrade_row(eid, equip))


func _make_upgrade_row(eid: String, equip: EquipDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_icon(equip.icon))

	var level := GameState.equip_level(eid)
	var maxed := level >= equip.max_level
	var cur0 := CombatMath.equip_stat_at_level(equip, level)
	row.tooltip_text = ItemUi.equip_tooltip(equip, level, int(cur0["attack"]), int(cur0["hp"]))  # 아이템 상세 hover

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 행 툴팁이 이 영역 hover에서도 뜨게 이벤트 통과
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = "%s  Lv.%d/%d" % [equip.display_name, level, equip.max_level]
	info.add_child(name_lbl)

	var stat_lbl := Label.new()
	stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_lbl.text = "공격 %d · HP %d" % [int(cur0["attack"]), int(cur0["hp"])]
	stat_lbl.add_theme_font_size_override("font_size", 10)
	info.add_child(stat_lbl)

	var prev_lbl := Label.new()
	prev_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prev_lbl.add_theme_font_size_override("font_size", 10)
	if maxed:
		prev_lbl.text = "MAX"
	else:
		var delta := CombatMath.upgraded_stats(equip, level, level + 1)
		var cost := CombatMath.upgrade_cost(equip, level)
		prev_lbl.text = "→ 공격 +%d · HP +%d  (골드 %d)" % [
			int(delta["attack"]), int(delta["hp"]), cost]
	info.add_child(prev_lbl)
	row.add_child(info)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 3)

	var up_btn := Button.new()
	up_btn.focus_mode = Control.FOCUS_NONE
	up_btn.custom_minimum_size = Vector2(64, 0)
	if maxed:
		up_btn.text = "MAX"
		up_btn.disabled = true
	else:
		up_btn.text = "강화"
		up_btn.disabled = not GameState.can_upgrade(eid)
		up_btn.pressed.connect(_on_upgrade_pressed.bind(eid))
	btn_col.add_child(up_btn)

	var eq_btn := Button.new()
	eq_btn.focus_mode = Control.FOCUS_NONE
	eq_btn.custom_minimum_size = Vector2(64, 0)
	var equipped := GameState.equipped_id(equip.slot()) == eid
	if equipped:
		eq_btn.text = "장착됨"
		eq_btn.disabled = true
	else:
		eq_btn.text = "장착"
		eq_btn.pressed.connect(_on_equip_pressed.bind(eid))
	btn_col.add_child(eq_btn)
	row.add_child(btn_col)
	return row


func _on_upgrade_pressed(eid: String) -> void:
	if GameState.upgrade_equipment(eid):
		_commit_save()


func _on_equip_pressed(eid: String) -> void:
	GameState.equip(eid)  # equip은 항상 성공(보유 장비) — inventory_changed로 _refresh
	_commit_save()


# --- 헬퍼 ---

func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근.
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()


func _clear(container: Node) -> void:
	for c: Node in container.get_children():
		c.queue_free()


# 아이콘 TextureRect — 도형 금지(§0)라 스프라이트만. icon이 null일 수 있어 안전 처리(빈 칸 유지).
func _make_icon(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(16, 16)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 픽셀아트 크리스프
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 — 클릭 안 먹음
	if tex != null:
		t.texture = tex
	return t


func _make_empty_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return l
