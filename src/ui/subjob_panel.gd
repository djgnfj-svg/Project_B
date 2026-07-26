extends CanvasLayer
# 하위 직업 패널 (성장축 GDD v1.8) — 마을 훈련소가 F로 여는 오버레이.
# 메인 하위 직업 선택 + 레벨/성장 조회. "어느 것을 메인으로 둘까"가 플레이어의 선택이다(GDD §5).
#
# craft_panel 모달 패턴을 **복제**했다(새 패턴 아님 — rules §5·verify §2-1):
#  - 루트 = CanvasLayer(layer 11), 기본 visible=false. 닫히면 완전히 숨어 뒤 게임 클릭을 안 막는다.
#  - Backdrop(ColorRect) = mouse_filter 기본 STOP → 열려 있는 동안만 뒤 게임 클릭을 막는다(마우스만 모달).
#  - Center(CenterContainer) = mouse_filter IGNORE(2) → 화면을 덮지만 클릭을 안 먹는다(rules §5 1번 함정).
#  - Esc(ui_cancel)/F(interact)로 자체 닫기. ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로
#    반드시 visible 가드 — 없으면 닫힌 패널이 훈련소의 F를 삼킨다.
# ⚠ 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지. 다른 플레이어는 계속 움직인다.
#
# 데이터는 전부 GameState 성장 API(읽기) + `set_main_sub_job`(유일한 쓰기)로만 다룬다.
# **표시 전용 = 네트워크 메시지 0개** — 메인 전환의 재공지(G_STATS "lv")는 GameState의
# growth_changed를 PeerSync가 구독해 처리한다(이 패널은 net을 모른다).
# 스탯 계산은 하지 않는다 — 단일 소스 = CombatMath(rules §3). 여기선 포맷만 한다.
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

signal closed

@onready var _close_btn: Button = %CloseBtn
@onready var _main_label: Label = %MainLabel
@onready var _exp_label: Label = %ExpLabel
@onready var _exp_bar: ProgressBar = %ExpBar
@onready var _stat_label: Label = %StatLabel
@onready var _sub_list: VBoxContainer = %SubList
@onready var _weight_label: Label = %WeightLabel

# 열린 프레임에 온 interact(F)가 곧바로 close로 튀는 걸 막는 1프레임 가드
# (훈련소가 F로 open()을 부르고, 같은 F가 아래 닫기 핸들러에 잡히는 이중 처리 방지 — craft_panel 미러)
var _ignore_toggle: bool = false


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (인벤/제작/창고와 통일)
	_close_btn.pressed.connect(close)
	_exp_bar.show_percentage = false
	_stat_label.add_theme_color_override(&"font_color", UiTheme.TEXT)
	_weight_label.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	# 레벨업·해금·메인 전환 → 열려 있는 동안 즉시 다시 그린다.
	EventBus.growth_changed.connect(_on_growth_changed)
	EventBus.exp_changed.connect(_on_exp_changed)  # 가벼운 훅 — EXP 줄만 갱신


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
		_refresh_main_bar()


# --- 그리기 ---

func _refresh() -> void:
	_refresh_main_bar()
	_refresh_stats()
	_refresh_list()
	_weight_label.text = "메인은 효과 100%%, 나머지(서브)는 %d%%만 합산됩니다" % roundi(
		CombatMath.SUB_JOB_WEIGHT * 100.0)


# 메인 하위 직업 + EXP 진행 (HUD 성장 표기의 패널판 — 같은 GameState API를 읽는다)
func _refresh_main_bar() -> void:
	var d := GameState.main_sub_job()
	if d == null:
		# 성장축 데이터가 없는 계열(현재 궁수·법사) — 빈 바를 띄우면 버그처럼 보인다
		_main_label.text = "이 직업엔 아직 성장 갈래가 없습니다"
		_exp_label.text = ""
		_exp_bar.visible = false
		return
	_exp_bar.visible = true
	var p := GameState.main_exp_progress()
	var lv := int(p["level"])
	var cur := int(p["cur"])
	var need := int(p["need"])
	_main_label.text = "메인 — %s  Lv.%d / %d" % [d.display_name, lv, d.max_level]
	if need <= 0:  # 만레벨 — 바는 가득 찬 상태로 남긴다
		_exp_label.text = "MAX"
		_exp_bar.max_value = 1.0
		_exp_bar.value = 1.0
	else:
		_exp_label.text = "EXP %d / %d" % [cur, need]
		_exp_bar.max_value = float(need)
		_exp_bar.value = float(clampi(cur, 0, need))


# 현재 총 5스탯 (메인 온전 + 서브 가중 합산 — 계산은 CombatMath, 여기선 포맷만)
func _refresh_stats() -> void:
	var s := GameState.current_level_stats()
	var crit := float(s.get("crit", 0.0)) * 100.0
	var crit_mult := CombatMath.crit_mult(float(s.get("crit_dmg", 0.0))) * 100.0
	var haste := float(s.get("haste", 0.0)) * 100.0
	var move := float(s.get("move", 0.0)) * 100.0
	var leech := float(s.get("leech", 0.0)) * 100.0
	_stat_label.text = "치명타 %.1f%%  ·  치명 피해 %.0f%%  ·  공격 속도 +%.1f%%\n이동 속도 +%.1f%%  ·  피 흡수 %.1f%%" % [
		crit, crit_mult, haste, move, leech]


func _refresh_list() -> void:
	for c: Node in _sub_list.get_children():
		c.queue_free()
	# 계열 = 선택한 직업 id. 전체 목록을 돌며 보유/미보유를 나눈다(미보유 = 아직 안 열린 것).
	var all := GameState.sub_jobs_of_series(GameState.selected_job_id)
	if all.is_empty():
		_sub_list.add_child(_make_empty_label("이 직업엔 아직 하위 직업이 없습니다"))
		return
	for sid: String in all:
		var d := GameState.sub_job_def(sid)
		if d == null:
			continue
		if GameState.has_sub_job(sid):
			_sub_list.add_child(_make_owned_row(sid, d))
		else:
			_sub_list.add_child(_make_locked_row(sid, d))


# --- 행 ---

func _make_owned_row(sid: String, d: SubJobDef) -> Control:
	var is_main := GameState.main_sub_job_id == sid
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.tooltip_text = _sub_tooltip(sid, d, true)
	# 아이콘 슬롯 — SubJobDef.icon은 아직 비어 있다(아트 미작성). 데이터가 채워지면 코드 변경 없이 뜬다.
	if d.icon != null:
		row.add_child(ItemUi.make_icon(d.icon, ICON_SIZE))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 행 툴팁이 이 영역 hover에서도 뜨게 이벤트 통과
	info.add_theme_constant_override(&"separation", 1)

	var level := GameState.sub_job_level(sid)
	var name_lbl := _make_line("%s  Lv.%d / %d%s" % [
		d.display_name, level, d.max_level, "   [메인]" if is_main else ""], 0)
	name_lbl.add_theme_color_override(&"font_color", UiTheme.ACCENT if is_main else UiTheme.TEXT)
	info.add_child(name_lbl)

	# 행에는 **수치만** 둔다 — flavor 설명(d.description)은 hover 툴팁에만(_sub_tooltip).
	# 목록에서 고를 때 필요한 건 "이 갈래가 뭘 올려주나"지 분위기 문장이 아니다(사용자 확정 2026-07-26).
	info.add_child(_make_wrap_label(_growth_text(d), UiTheme.TEXT))
	# 메인 전용 특성 — 켜짐(메인)이면 액센트, 꺼짐이면 흐리게. 이 대비가 "메인으로 둬야 켜진다"를
	# 목록에서 바로 읽히게 한다(GDD v1.9 §5 — 메인 선택을 스탯 비교에서 플레이 감각 선택으로).
	var trait_line := _trait_text(d, is_main)
	if not trait_line.is_empty():
		info.add_child(_make_wrap_label(trait_line, UiTheme.ACCENT if is_main else UiTheme.TEXT_DIM))
	row.add_child(info)

	row.add_child(_make_main_button(sid, is_main))
	return row


# 메인 지정 버튼 — 현재 메인은 눌러도 무의미하니 상태 표시(disabled "메인").
# 🔴 쓰기는 GameState.set_main_sub_job 하나뿐이고, 판 도중(챕터 안)에는 거부된다(GDD §5 마을 전용) —
#   훈련소는 마을에만 있어 평소엔 안 걸리지만, 거부 상태를 버튼에 정직하게 비춘다.
func _make_main_button(sid: String, is_main: bool) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72, 0)
	if is_main:
		btn.text = "메인"
		btn.disabled = true
		btn.tooltip_text = "이미 메인입니다 — 효과가 온전히 적용됩니다"
		return btn
	btn.text = "메인 지정"
	if GameState.in_chapter():
		btn.disabled = true
		btn.tooltip_text = "판 도중에는 메인을 바꿀 수 없습니다 (마을에서만)"
		return btn
	btn.pressed.connect(_on_main_pressed.bind(sid))
	return btn


func _make_locked_row(sid: String, d: SubJobDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	# 행 자체는 최소 정보(이름·해금 조건)만, 성장 성격·설명은 hover 툴팁으로 — 목록이 길어지지 않게
	row.tooltip_text = _sub_tooltip(sid, d, false)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override(&"separation", 1)

	var name_lbl := _make_line(d.display_name, 0)
	name_lbl.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	info.add_child(name_lbl)

	info.add_child(_make_wrap_label(_lock_text(d), UiTheme.TEXT_DIM))
	# 잠긴 갈래도 특성은 예고한다 — "저걸 열면 뭐가 생기나"가 해금 동기다(GDD §6 레벨업 = 콘텐츠 해금).
	var locked_trait := _trait_text(d, false)
	if not locked_trait.is_empty():
		info.add_child(_make_wrap_label(locked_trait, UiTheme.TEXT_DIM))
	row.add_child(info)

	# 버튼 자리에 상태 라벨 — 보유 행과 폭을 맞춰 목록이 흔들리지 않게
	var state := Label.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.custom_minimum_size = Vector2(72, 0)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.text = "잠김"
	state.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	row.add_child(state)
	return row


func _on_main_pressed(sid: String) -> void:
	# 실패(판 도중·미보유·타 계열)는 GameState가 거부한다 — 여기서 상태를 직접 바꾸지 않는다.
	if not GameState.set_main_sub_job(sid):
		_refresh()  # 거부 사유가 바뀌었을 수 있으니 버튼 상태만 다시 그린다
		return
	# 성공 시 GameState가 growth_changed emit → _on_growth_changed로 자동 갱신(+ PeerSync 재공지)
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


# 메인 전용 특성 한 줄 (GDD v1.9 §5). 특성 없는 갈래는 빈 문자열 → 호출부가 줄 자체를 안 만든다.
# ⚠ 특성 이름·문구는 아직 코드에 있다 — 현재 특성이 사거리 하나뿐이라서다(SubJobDef 필드도 하나).
#   두 번째 특성이 생기면 이름/문구를 SubJobDef로 옮긴다(하위 직업당 최대 1개 규약은 그대로).
# 값은 CombatMath.clamp_reach를 지나 표시한다 — 데이터에 상한 초과값이 적혀 있어도 **실제 걸리는 값**만
#   보여주기 위해서다(UI가 게임보다 후한 수치를 약속하면 그게 곧 거짓말이다).
func _trait_text(d: SubJobDef, is_main: bool) -> String:
	if is_zero_approx(d.main_reach_bonus):
		return ""
	var pct := roundi(CombatMath.clamp_reach(d.main_reach_bonus) * 100.0)
	var head := "특성 발동" if is_main else "메인 지정 시"
	return "%s — 검기 파형: 평타 사거리 +%d%%" % [head, pct]


func _growth_text(d: SubJobDef) -> String:
	var parts := _growth_parts(d)
	if parts.is_empty():
		return "레벨당 성장 없음"
	return "레벨당  " + " · ".join(parts)


# 잠김 안내 — 해금 조건 = 직전(order-1) 하위 직업이 **메인일 때** unlocks_next_at 도달 (GameState._try_unlock_next 미러)
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


# 행 hover 툴팁 — 이름·레벨·역할(메인/서브)·현재 기여·설명.
# 🔴 기여도는 직접 곱하지 않는다: CombatMath.level_stats에 **그 하위 직업 하나만** 넘겨
#   메인 가중(1.0)/서브 가중(SUB_JOB_WEIGHT)을 단일 소스가 적용하게 한다(§3 — 여기서 곱하면 갈라진다).
func _sub_tooltip(sid: String, d: SubJobDef, owned: bool) -> String:
	var lines: Array[String] = []
	var level := GameState.sub_job_level(sid)
	var is_main := GameState.main_sub_job_id == sid
	lines.append("%s  Lv.%d / %d" % [d.display_name, level, d.max_level])
	if not owned:
		lines.append(_lock_text(d))
	elif is_main:
		lines.append("메인 — 효과 100% 적용")
	else:
		lines.append("서브 — 효과 %d%% 합산" % roundi(CombatMath.SUB_JOB_WEIGHT * 100.0))
	if owned:
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
	var trait_line := _trait_text(d, is_main)
	if not trait_line.is_empty():
		lines.append(trait_line)
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
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 — 행 툴팁이 계속 뜨게
	if font_size > 0:
		l.add_theme_font_size_override(&"font_size", font_size)
	return l


# 보조 줄(성장 요약·설명·잠김 안내) — 🔴 autowrap 필수: 안 감으면 긴 줄의 최소 폭이
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


func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근(craft_panel 미러).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
