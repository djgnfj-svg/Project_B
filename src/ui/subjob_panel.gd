extends CanvasLayer
# 하위 직업 훈련소 패널 (조립 축 GDD v2.0) — 마을 훈련소가 F로 여는 오버레이.
# **장착 슬롯 = 메인 1 + 서브 2**를 직접 조작한다. 하위 직업은 "보유하면 켜지는 것"이 아니라
# "3칸에 낀 것만 켜지는 것"이고(GDD §5), 특성은 **낀 자리에 따라 얼굴이 다르다**
# (메인 자리 = 메인 특성 / 서브 자리 = 서브 특성). 그래서 이 패널의 본체는 "어디에 끼울까"다.
#
# craft_panel 모달 패턴을 **복제**했다(새 패턴 아님 — rules §5·verify §2-1):
#  - 루트 = CanvasLayer(layer 11), 기본 visible=false. 닫히면 완전히 숨어 뒤 게임 클릭을 안 막는다.
#  - Backdrop(ColorRect) = mouse_filter 기본 STOP → 열려 있는 동안만 뒤 게임 클릭을 막는다(마우스만 모달).
#  - Center(CenterContainer) = mouse_filter IGNORE(2) → 화면을 덮지만 클릭을 안 먹는다(rules §5 1번 함정).
#  - Esc(ui_cancel)/F(interact)로 자체 닫기. ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로
#    반드시 visible 가드 — 없으면 닫힌 패널이 훈련소의 F를 삼킨다.
# ⚠ 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지. 다른 플레이어는 계속 움직인다.
#
# 데이터는 전부 GameState 성장 API(읽기) + `set_main_sub_job`/`set_sub_slot`(유일한 쓰기)로만 다룬다.
# **표시 전용 = 네트워크 메시지 0개** — 장착 변동의 재공지(G_STATS)는 GameState의 growth_changed를
# PeerSync가 구독해 처리한다(이 패널은 net을 모른다).
# 🔴 스탯·특성 문구는 계산·작문하지 않는다 — 단일 소스 = CombatMath(rules §3). 특히 특성 문구는
#   `CombatMath.trait_text(key, value)`가 만든다: 여기서 문장을 짜면 값과 표시가 갈라진다.
# ⚠ UI 씬 스크립트라 전역 오토로드(GameState·EventBus·CombatMath) 직접 접근 OK(rules §5).
#   class_name 선언은 하지 않는다(§0).

const UiTheme := preload("res://src/ui/ui_theme.gd")
const ItemUi := preload("res://src/ui/item_ui.gd")

# 스탯 표기 — 키는 CombatMath.LEVEL_STAT_KEYS와 미러다(순회는 항상 그 배열로 한다:
# 새 스탯이 늘면 여기 라벨만 추가하면 되고, 빠뜨려도 raw 키로 보일 뿐 깨지지 않는다).
const STAT_LABEL := {
	"crit": "치명",
	"crit_dmg": "치명피해",
	"haste": "공속",
	"move": "이속",
	"leech": "피흡",
}
# 확률·배율에 더해지는 값은 %p(퍼센트 포인트), 증가율은 %.
const STAT_UNIT := {
	"crit": "%p",
	"crit_dmg": "%p",
	"haste": "%",
	"move": "%",
	"leech": "%",
}

const ICON_SIZE := 20.0
const MAIN_SLOT := -1  # 슬롯 인덱스 규약: -1 = 메인 칸, 0.. = 서브 칸 (GameState.sub_slot_id의 인덱스)
const NO_SLOT := -99   # 어느 칸에도 안 낀 상태 (_slot_of의 반환)

signal closed

@onready var _close_btn: Button = %CloseBtn
@onready var _slot_row: HBoxContainer = %SlotRow
@onready var _stat_label: Label = %StatLabel
@onready var _notice_label: Label = %NoticeLabel
@onready var _sub_list: VBoxContainer = %SubList
@onready var _weight_label: Label = %WeightLabel

# 열린 프레임에 온 interact(F)가 곧바로 close로 튀는 걸 막는 1프레임 가드
# (훈련소가 F로 open()을 부르고, 같은 F가 아래 닫기 핸들러에 잡히는 이중 처리 방지 — craft_panel 미러)
var _ignore_toggle: bool = false


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (인벤/제작/창고와 통일)
	_close_btn.pressed.connect(close)
	_stat_label.add_theme_color_override(&"font_color", UiTheme.TEXT)
	_notice_label.add_theme_color_override(&"font_color", UiTheme.GOLD)
	_weight_label.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	# 레벨업·해금·장착 변동 → 열려 있는 동안 즉시 다시 그린다.
	EventBus.growth_changed.connect(_on_growth_changed)
	EventBus.exp_changed.connect(_on_exp_changed)


# --- 공개 API (훈련소가 부른다) ---

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


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _clear_ignore_toggle() -> void:
	_ignore_toggle = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return  # 🔴 닫힌 패널은 아무 입력도 소비하지 않는다 (훈련소의 F를 삼키지 않게)
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not _ignore_toggle:
		close()
		get_viewport().set_input_as_handled()


func _on_growth_changed() -> void:
	if visible:
		_refresh()


func _on_exp_changed(_cur: int, _need: int) -> void:
	if visible:
		_refresh()


# --- 그리기 ---

func _refresh() -> void:
	_refresh_slots()
	_refresh_stats()
	_refresh_notice()
	_refresh_list()
	_weight_label.text = "낀 3칸만 효과를 냅니다 — 메인 100%%, 서브 각 %d%% 합산. 특성은 낀 자리(메인/서브)의 것 하나만 켜집니다" % roundi(
		CombatMath.SUB_JOB_WEIGHT * 100.0)


# 판 도중엔 GameState가 교체를 거부한다(GDD §5 마을 전용) — 버튼 disabled만으로는 "왜 안 되지"가
# 안 읽히므로 사유를 한 줄로 띄운다. 훈련소는 마을에만 있어 평소엔 안 뜨지만 정직하게 비춘다.
func _refresh_notice() -> void:
	_notice_label.visible = GameState.in_chapter()
	if _notice_label.visible:
		_notice_label.text = "판 도중에는 장착을 바꿀 수 없습니다 — 마을에서만 교체할 수 있습니다"


# --- 장착 슬롯 3칸 ---

func _refresh_slots() -> void:
	_clear(_slot_row)
	_slot_row.add_child(_make_slot_card(MAIN_SLOT))
	for i: int in range(GameState.SUB_SLOT_COUNT):
		_slot_row.add_child(_make_slot_card(i))


# 칸에 낀 하위 직업 def — 없거나 무효(미보유·타 계열·메인과 중복)면 null = 빈 칸으로 본다.
# 🔴 유효성 판정은 GameState.equipped_sub_jobs의 필터와 **같은 조건**이다 — 여기만 관대하면
#   화면엔 껴 있는데 실제로는 안 세는 칸이 생긴다(에러 없이 거짓말하는 UI).
func _slot_def(index: int) -> SubJobDef:
	if index == MAIN_SLOT:
		return GameState.main_sub_job()  # 타 계열 진행분은 null (계열 검사 포함)
	var sid := GameState.sub_slot_id(index)
	if sid.is_empty() or sid == GameState.main_sub_job_id or not GameState.can_equip_sub(sid):
		return null
	return GameState.sub_job_def(sid)


func _slot_title(index: int) -> String:
	return "메인" if index == MAIN_SLOT else "서브 %d" % (index + 1)


func _make_slot_card(index: int) -> Control:
	var is_main := index == MAIN_SLOT
	var d := _slot_def(index)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 6)
	margin.add_theme_constant_override(&"margin_right", 6)
	margin.add_theme_constant_override(&"margin_top", 3)
	margin.add_theme_constant_override(&"margin_bottom", 3)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	margin.add_child(box)

	var head := _make_line(_slot_title(index), 9)
	head.add_theme_color_override(&"font_color", UiTheme.ACCENT if is_main else UiTheme.TEXT_DIM)
	box.add_child(head)

	if d == null:
		var empty := _make_wrap_label("비어 있음", UiTheme.TEXT_DIM)
		box.add_child(empty)
		card.tooltip_text = "%s 칸 — 아래 목록에서 골라 끼웁니다" % _slot_title(index)
		return card

	var sid := GameState.main_sub_job_id if is_main else GameState.sub_slot_id(index)
	var name_lbl := _make_line("%s Lv.%d" % [d.display_name, GameState.sub_job_level(sid)], 0)
	name_lbl.add_theme_color_override(&"font_color", UiTheme.TEXT)
	box.add_child(name_lbl)

	# 🔴 이 칸에서 **실제로 켜지는** 특성만 보여준다 — trait_at(자리)가 그 자리의 얼굴을 준다.
	var trait_line := _trait_line(d, is_main)
	box.add_child(_make_wrap_label(
		trait_line if not trait_line.is_empty() else "특성 없음",
		UiTheme.ACCENT if not trait_line.is_empty() else UiTheme.TEXT_DIM))

	if is_main:
		box.add_child(_make_exp_line())
	else:
		box.add_child(_make_clear_button(index))
	card.tooltip_text = _sub_tooltip(sid, d)
	return card


# 메인 칸의 EXP 진행 — 메인 하위 직업만 성장 페이싱의 기준점이라 이 칸에 붙인다(HUD 표기의 패널판).
func _make_exp_line() -> Control:
	var p := GameState.main_exp_progress()
	var cur := int(p.get("cur", 0))
	var need := int(p.get("need", 0))
	var lbl := _make_line("MAX" if need <= 0 else "EXP %d / %d" % [cur, need], 9)
	lbl.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	return lbl


func _make_clear_button(index: int) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "비우기"
	btn.add_theme_font_size_override(&"font_size", 9)
	if GameState.in_chapter():
		btn.disabled = true
		btn.tooltip_text = "판 도중에는 바꿀 수 없습니다 (마을에서만)"
		return btn
	btn.pressed.connect(_on_slot_set.bind(index, ""))
	return btn


# --- 총 스탯 ---

# 현재 총 5스탯 (낀 3칸: 메인 온전 + 서브 가중 — 계산은 CombatMath, 여기선 포맷만)
func _refresh_stats() -> void:
	var s := GameState.current_level_stats()
	var crit := float(s.get("crit", 0.0)) * 100.0
	var crit_mult := CombatMath.crit_mult(float(s.get("crit_dmg", 0.0))) * 100.0
	var haste := float(s.get("haste", 0.0)) * 100.0
	var move := float(s.get("move", 0.0)) * 100.0
	var leech := float(s.get("leech", 0.0)) * 100.0
	var text := "치명타 %.1f%%  ·  치명 피해 %.0f%%  ·  공격 속도 +%.1f%%\n이동 속도 +%.1f%%  ·  피 흡수 %.1f%%" % [
		crit, crit_mult, haste, move, leech]
	var traits := _active_trait_parts()
	if not traits.is_empty():
		text += "\n특성 — " + "  ·  ".join(traits)
	_stat_label.text = text


# 지금 켜진 특성 목록 — 🔴 문구도 합산·clamp도 전부 단일 소스에서 온다
# (GameState.active_traits = 자리별 리졸브 + CombatMath.clamp_traits, 문구 = CombatMath.trait_text).
# 같은 키를 메인·서브가 같이 밀면 합산 뒤 상한에서 잘린 **실제 걸리는 값**이 여기 뜬다.
func _active_trait_parts() -> Array[String]:
	var active := GameState.active_traits()
	var parts: Array[String] = []
	for key: String in CombatMath.TRAIT_KEYS:
		var v := float(active.get(key, 0.0))
		if is_zero_approx(v):
			continue
		var txt := CombatMath.trait_text(key, v)
		if not txt.is_empty():
			parts.append(txt)
	return parts


# --- 보유 목록 ---

func _refresh_list() -> void:
	_clear(_sub_list)
	var owned := GameState.all_owned_sub_jobs()  # 계열 보유 + 공유 보유 (서브 칸에 낄 수 있는 전부)
	for sid: String in owned:
		var d := GameState.sub_job_def(sid)
		if d != null:
			_sub_list.add_child(_make_owned_row(sid, d))
	# 아직 안 열린 계열 갈래 — "저걸 열면 뭐가 생기나"가 해금 동기다(GDD §6 레벨업 = 콘텐츠 해금).
	# ⚠ 공유 하위 직업의 미보유분은 안 띄운다 — 해금 조건이 계열 체인 밖(콘텐츠 보상)이라
	#   이 패널이 조건을 정확히 말할 수 없다. 틀린 안내를 적느니 안 적는다.
	var locked := 0
	for sid: String in GameState.sub_jobs_of_series(GameState.selected_job_id):
		if GameState.has_sub_job(sid):
			continue
		var d := GameState.sub_job_def(sid)
		if d == null:
			continue
		_sub_list.add_child(_make_locked_row(d))
		locked += 1
	if owned.is_empty() and locked == 0:
		_sub_list.add_child(_make_empty_label("이 직업엔 아직 하위 직업이 없습니다"))


# 보유 행 — 이름/레벨 + 레벨당 성장 + **메인일 때 / 서브일 때 특성 두 줄**(나란히 놓아야
# "어디에 끼울까"가 비교된다, GDD v2.0 §5) + 칸 버튼 3개.
func _make_owned_row(sid: String, d: SubJobDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.tooltip_text = _sub_tooltip(sid, d)
	# 아이콘 슬롯 — SubJobDef.icon은 아직 비어 있다(아트 미작성). 데이터가 채워지면 코드 변경 없이 뜬다.
	if d.icon != null:
		row.add_child(ItemUi.make_icon(d.icon, ICON_SIZE))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 행 툴팁이 이 영역 hover에서도 뜨게 이벤트 통과
	info.add_theme_constant_override(&"separation", 1)

	var slot := _slot_of(sid)
	var equipped := slot != NO_SLOT
	var mark := "   [%s]" % _slot_title(slot) if equipped else ""
	var name_lbl := _make_line("%s  Lv.%d / %d%s" % [
		d.display_name, GameState.sub_job_level(sid), d.max_level, mark], 0)
	name_lbl.add_theme_color_override(&"font_color", UiTheme.ACCENT if equipped else UiTheme.TEXT)
	info.add_child(name_lbl)

	# 행에는 **수치만** 둔다 — flavor 설명(d.description)은 hover 툴팁에만(_sub_tooltip).
	info.add_child(_make_wrap_label(_growth_text(d), UiTheme.TEXT))
	# 두 얼굴 — 지금 켜져 있는 자리는 액센트, 나머지는 흐리게. 이 대비가 "어느 칸에 끼면 무엇이 켜지나"를
	# 목록에서 바로 읽히게 한다.
	info.add_child(_make_wrap_label(
		"메인 자리 — " + _face_text(d, true), UiTheme.ACCENT if slot == MAIN_SLOT else UiTheme.TEXT_DIM))
	info.add_child(_make_wrap_label(
		"서브 자리 — " + _face_text(d, false),
		UiTheme.ACCENT if slot >= 0 else UiTheme.TEXT_DIM))
	row.add_child(info)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override(&"separation", 3)
	btns.add_child(_make_slot_button(sid, d, MAIN_SLOT))
	for i: int in range(GameState.SUB_SLOT_COUNT):
		btns.add_child(_make_slot_button(sid, d, i))
	row.add_child(btns)
	return row


# 이 하위 직업이 지금 낀 칸 — MAIN_SLOT(-1) / 서브 인덱스(0..) / 미장착(-99).
func _slot_of(sid: String) -> int:
	if sid == GameState.main_sub_job_id and GameState.main_sub_job() != null:
		return MAIN_SLOT
	for i: int in range(GameState.SUB_SLOT_COUNT):
		if _slot_def(i) != null and GameState.sub_slot_id(i) == sid:
			return i
	return NO_SLOT


# 칸 버튼 — 클릭 한 번에 그 칸으로 끼운다(칸을 먼저 고르는 모드 상태 없이 직접 조작).
# 🔴 GameState의 거부 조건을 UI에 **미러**한다(공유는 메인 불가·판 도중 잠금·이미 낀 칸) —
#   눌렀는데 아무 일도 안 일어나는 버튼이 제일 나쁘다. 실제 거부는 여전히 GameState가 한다.
func _make_slot_button(sid: String, d: SubJobDef, index: int) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = _slot_title(index)
	btn.add_theme_font_size_override(&"font_size", 9)
	btn.custom_minimum_size = Vector2(46, 0)

	if index == MAIN_SLOT and d.is_shared():
		btn.disabled = true
		btn.tooltip_text = "공유 하위 직업은 서브 칸 전용입니다 — 메인은 항상 이 직업 계열의 갈래입니다"
		return btn
	if _slot_of(sid) == index:
		btn.disabled = true
		btn.tooltip_text = "이미 이 칸에 장착돼 있습니다"
		return btn
	if index >= 0 and sid == GameState.main_sub_job_id:
		btn.disabled = true
		btn.tooltip_text = "메인으로 낀 것은 서브 칸에 함께 넣을 수 없습니다"
		return btn
	if GameState.in_chapter():
		btn.disabled = true
		btn.tooltip_text = "판 도중에는 바꿀 수 없습니다 (마을에서만)"
		return btn
	btn.tooltip_text = "%s 칸에 장착 — %s" % [_slot_title(index), _face_text(d, index == MAIN_SLOT)]
	btn.pressed.connect(_on_slot_set.bind(index, sid))
	return btn


func _make_locked_row(d: SubJobDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override(&"separation", 1)

	var name_lbl := _make_line(d.display_name, 0)
	name_lbl.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	info.add_child(name_lbl)
	info.add_child(_make_wrap_label(_lock_text(d), UiTheme.TEXT_DIM))
	info.add_child(_make_wrap_label("메인 자리 — " + _face_text(d, true), UiTheme.TEXT_DIM))
	info.add_child(_make_wrap_label("서브 자리 — " + _face_text(d, false), UiTheme.TEXT_DIM))
	row.add_child(info)

	# 버튼 자리에 상태 라벨 — 보유 행과 폭을 맞춰 목록이 흔들리지 않게
	var state := Label.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.custom_minimum_size = Vector2(150, 0)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.text = "잠김"
	state.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	row.add_child(state)
	return row


# 🔴 쓰기는 GameState 두 함수뿐 — 실패(판 도중·미보유·타 계열·공유의 메인)는 거기서 거부된다.
#   여기서 상태를 직접 바꾸지 않는다. 성공하면 growth_changed로 자동 갱신(+ PeerSync 재공지).
func _on_slot_set(index: int, sid: String) -> void:
	var ok: bool = false
	if index == MAIN_SLOT:
		ok = GameState.set_main_sub_job(sid)
	else:
		ok = GameState.set_sub_slot(index, sid)
	if not ok:
		_refresh()  # 거부 사유가 바뀌었을 수 있으니 버튼 상태만 다시 그린다
		return
	_commit_save()


# --- 텍스트 ---

# 레벨당 성장 요약 — 0인 스탯은 빼서 그 하위 직업의 성격이 한눈에 보이게.
# 🔴 순회는 CombatMath.LEVEL_STAT_KEYS로 한다(스탯이 늘면 여기 라벨만 추가 — 목록을 사본으로 만들면 갈라진다).
func _growth_parts(d: SubJobDef) -> Array[String]:
	var parts: Array[String] = []
	for key: String in CombatMath.LEVEL_STAT_KEYS:
		var step := d.step(key)
		if is_zero_approx(step):
			continue
		parts.append("%s +%.1f%s" % [_stat_name(key), step * 100.0, _stat_unit(key)])
	return parts


func _growth_text(d: SubJobDef) -> String:
	var parts := _growth_parts(d)
	if parts.is_empty():
		return "레벨당 성장 없음"
	return "레벨당  " + " · ".join(parts)


# 자리별 특성 한 줄 — 이름(데이터) + 효과 문구(CombatMath). 특성 없으면 빈 문자열.
# 🔴 효과 문구를 여기서 짜지 마라(rules §2 게이트): 값과 표시가 갈라지면
#   "표시는 −30%인데 실제는 −15%"가 되고 아무 에러도 안 난다.
func _trait_line(d: SubJobDef, as_main: bool) -> String:
	var t := d.trait_at(as_main)
	if t.is_empty():
		return ""
	var txt := CombatMath.trait_text(str(t.get("key", "")), float(t.get("value", 0.0)))
	if txt.is_empty():
		return ""  # 모르는 키(데이터 오타) — 리졸버도 폐기하므로 UI도 약속하지 않는다
	var nm := str(t.get("name", ""))
	return "%s: %s" % [nm, txt] if not nm.is_empty() else txt


# 목록 행의 "이 자리에 끼우면 이렇게 된다" 한 조각. 공유 하위 직업의 메인 자리는 **낄 수 없음**을
# 그대로 말한다(GDD §5 — 메인은 항상 계열 갈래).
func _face_text(d: SubJobDef, as_main: bool) -> String:
	if as_main and d.is_shared():
		return "메인 불가 (공유 갈래는 서브 전용)"
	var line := _trait_line(d, as_main)
	return line if not line.is_empty() else "특성 없음"


# 잠김 안내 — 해금 조건 = 직전(order-1) 하위 직업이 **메인일 때** unlocks_next_at 도달 (GameState 미러)
func _lock_text(d: SubJobDef) -> String:
	var prev := _prev_in_series(d)
	if prev == null:
		return "잠김"
	return "잠김 — %s를 메인으로 Lv.%d 달성 시 해금" % [prev.display_name, prev.unlocks_next_at]


func _prev_in_series(d: SubJobDef) -> SubJobDef:
	for sid: String in GameState.sub_jobs_of_series(d.series_id):
		var other := GameState.sub_job_def(sid)
		if other != null and other.order == d.order - 1:
			return other
	return null


# 행/칸 hover 툴팁 — 이름·레벨·현재 자리·현재 기여·두 얼굴·설명.
# 🔴 기여도는 직접 곱하지 않는다: CombatMath.level_stats에 **그 하위 직업 하나만** 넘겨
#   메인 가중(1.0)/서브 가중(SUB_JOB_WEIGHT)을 단일 소스가 적용하게 한다(§3 — 여기서 곱하면 갈라진다).
func _sub_tooltip(sid: String, d: SubJobDef) -> String:
	var lines: Array[String] = []
	var level := GameState.sub_job_level(sid)
	var slot := _slot_of(sid)
	lines.append("%s  Lv.%d / %d" % [d.display_name, level, d.max_level])
	if slot == MAIN_SLOT:
		lines.append("메인 — 5스탯 100% 적용")
	elif slot >= 0:
		lines.append("서브 %d — 5스탯 %d%% 합산" % [slot + 1, roundi(CombatMath.SUB_JOB_WEIGHT * 100.0)])
	else:
		lines.append("미장착 — 효과가 꺼져 있습니다")
	if slot != NO_SLOT:
		# 단일 항목만 넘겨 메인/서브 가중을 CombatMath가 적용하게 한다(딕셔너리 리터럴 대신
		# 명시 대입 — 키가 변수임을 문법적으로 못 헷갈리게).
		var one_level := {}
		one_level[sid] = level
		var one_def := {}
		one_def[sid] = d
		var contrib := CombatMath.level_stats(GameState.main_sub_job_id, one_level, one_def)
		var parts: Array[String] = []
		for key: String in CombatMath.LEVEL_STAT_KEYS:
			var v := float(contrib.get(key, 0.0))
			if is_zero_approx(v):
				continue
			parts.append("%s +%.1f%s" % [_stat_name(key), v * 100.0, _stat_unit(key)])
		lines.append("현재 기여 — " + (" · ".join(parts) if not parts.is_empty() else "없음"))
	var growth := _growth_parts(d)
	if not growth.is_empty():
		lines.append("레벨마다  " + " · ".join(growth))
	lines.append("메인 자리 — " + _face_text(d, true))
	lines.append("서브 자리 — " + _face_text(d, false))
	if not d.description.is_empty():
		lines.append("")
		lines.append(d.description)
	return "\n".join(lines)


func _stat_name(key: String) -> String:
	return str(STAT_LABEL.get(key, key))


func _stat_unit(key: String) -> String:
	return str(STAT_UNIT.get(key, "%"))


# --- 헬퍼 ---

# font_size 0 = 프로젝트 기본 픽셀 폰트 크기 상속(craft_panel의 이름 줄과 통일)
func _make_line(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 — 행/칸 툴팁이 계속 뜨게
	if font_size > 0:
		l.add_theme_font_size_override(&"font_size", font_size)
	return l


# 보조 줄(성장 요약·특성 줄·잠김 안내) — 🔴 autowrap 필수: 안 감으면 긴 줄의 최소 폭이
# 컨테이너를 밀어 Dialog가 640 뷰포트를 넘어간다(잘려 보이는데 에러는 없다).
# 크기 9 = Galmuri9의 설계 크기(픽셀 퍼펙트) + line_spacing 0 → 이름 줄보다 확실히 얇게 깔린다.
func _make_wrap_label(text: String, color: Color) -> Label:
	var l := _make_line(text, 9)
	l.add_theme_constant_override(&"line_spacing", 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(80, 0)  # wrap 하한 — 0이면 한 글자 폭까지 줄어든다
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override(&"font_color", color)
	return l


func _make_empty_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	return l


func _clear(container: Node) -> void:
	for c: Node in container.get_children():
		container.remove_child(c)  # 즉시 떼어낸다 — queue_free만 하면 같은 프레임 재생성분과 겹쳐 보인다
		c.queue_free()


func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근(craft_panel 미러).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
