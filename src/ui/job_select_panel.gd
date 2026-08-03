extends CanvasLayer
# 직업 선택 카드 창 (기본·데모용) — 마을 훈련소 허수아비를 클릭하면 뜨는 오버레이.
# **하위 직업 3갈래**(검사·광전사·검성)를 큼직한 카드 3장으로 보여주고, 고른 카드를 메인 하위
# 직업으로 지정한다. 훈련소 조립 패널(`subjob_panel`)의 **간이판**이다 — 그쪽은 메인 1 + 서브 2
# 슬롯을 드래그로 조립하는 본격 UI이고, 여기는 "직업을 하나 고른다"만 하는 데모용 진입점이다.
# 🔴 **과하게 하지 않는다**(사용자 확정): 라이브 프리뷰·파티클·실시간 변신 없음. 열고닫힘 페이드 트윈만.
#
# craft_panel / subjob_panel 모달 패턴을 **복제**했다(새 패턴 아님 — rules §5 「mouse_filter」·verify §2-1):
#  - 루트 = CanvasLayer(layer 11), 기본 visible=false. 닫히면 완전히 숨어 뒤 게임 클릭을 안 막는다.
#  - Backdrop(ColorRect) = mouse_filter 기본 STOP → 열려 있는 동안만 뒤 게임 클릭을 막는다(마우스만 모달).
#  - Center(CenterContainer) = mouse_filter IGNORE(2) → 화면을 덮지만 클릭을 안 먹는다(rules §5 1번 함정).
#  - Esc(ui_cancel)/interact(F)로 자체 닫기. ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로
#    반드시 visible 가드 — 없으면 닫힌 패널이 허수아비의 F(있다면)나 다른 상호작용 입력을 삼킨다.
# ⚠ 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지. 다른 플레이어는 계속 움직인다.
#
# 데이터·거부는 전부 GameState 정본이고 이 패널은 **미러**다(rules §3):
#  - 카드 클릭 → GameState.set_main_sub_job(id). 미보유 갈래는 subjob_panel._unlock_and_equip과
#    **같은 관례**로 즉시 해금(`sub_job_exp[id] = 0`) 후 지정한다 — 데모라 세 카드가 늘 눌린다.
#  - 판 도중(in_chapter)엔 GameState가 교체를 거부하므로 UI도 흐리게 잠근다(마을 전용, GDD §5).
# 🔴 문구는 **CombatMath.trait_text가 정본**이다 — 여기서 특성 설명을 지어내지 않는다(값과 표시가
#   갈라지면 "표시는 −30%인데 실제는 −15%"가 되고 에러가 안 난다). 이름·설명은 SubJobDef 데이터.
# 🔴 **표시 전용 = 네트워크 메시지 0개** — 외형 갱신은 GameState.set_main_sub_job이 쏘는
#   growth_changed를 PeerSync가 구독해 G_STATS 재공지로 처리한다(이 패널은 net을 모른다).
# ⚠ UI 씬 스크립트라 전역 오토로드(GameState·EventBus·CombatMath) 직접 접근 OK(rules §5).
#   class_name 선언은 하지 않는다(§0). 겉모습은 스프라이트(카드 PNG)로만 — 도형 금지(§0).

const UiTheme := preload("res://src/ui/ui_theme.gd")

# 카드 = (하위 직업 id, 카드 텍스처 경로). 순서 = order(검사→광전사→검성). 매핑은 task 정본.
# ⚠ 경로만 상수로 두고 로드는 지연(_card_tex) — `-s` 헤드리스가 이 스크립트를 preload할 때
#   .import 사이드카가 없어도 컴파일이 통째로 깨지지 않게(ui_theme._tex와 같은 관례).
const CARDS := [
	{"id": "warrior_swordsman", "tex": "res://assets/sprites/ui/jobcards/job_card_swordsman.png"},
	{"id": "warrior_berserker", "tex": "res://assets/sprites/ui/jobcards/job_card_berserker.png"},
	{"id": "warrior_swordmaster", "tex": "res://assets/sprites/ui/jobcards/job_card_swordmaster.png"},
]

# 카드 규격 — 아트 실측(96×128, 세 장 동일). 하단이 텍스트 자리로 비어 있어 그 위에 이름/설명을 얹는다.
const CARD_W := 96.0
const CARD_H := 128.0
# 하단 텍스트 밴드 — 카드 아래쪽 비어 있는 자리(크레스트는 상단). 카드 위에 겹쳐 앉힌다.
const TEXT_BAND_TOP := 74.0   # 이 y부터 카드 하단까지가 텍스트 자리(실측 여백)
const TEXT_BAND_PAD := 6.0

# 손맛 연출값 — 스크립트 const(rules §0 예외: 사용자가 조이는 연출값이라 밸런스 아님).
const HOVER_SCALE := 1.06     # hover = 살짝 커진다
const HOVER_BRIGHT := 1.18    # hover = 살짝 발광(modulate 밝기)
const SEL_BRIGHT := 1.10      # 현재 선택된 카드는 은은히 밝게 유지
const HOVER_TIME := 0.10      # hover 트윈 시간
const OPEN_TIME := 0.16       # 열고닫힘 페이드 시간
const OPEN_SCALE := 0.94      # 열릴 때 살짝 작게 시작 → 1.0 (닫힐 때 역방향)

signal closed

@onready var _backdrop: ColorRect = $Backdrop
@onready var _dialog: Control = %Dialog
@onready var _card_row: HBoxContainer = %CardRow
@onready var _notice_label: Label = %NoticeLabel
@onready var _close_btn: Button = %CloseBtn

# 열린 프레임에 온 interact(F)가 곧바로 close로 튀는 걸 막는 1프레임 가드(craft_panel 미러).
var _ignore_toggle: bool = false
# 열고닫힘 페이드 트윈 핸들 — 겹쳐 돌면 서로를 덮으므로 새로 시작할 때 죽인다.
var _fade_tw: Tween = null
# 카드별 hover 트윈 — 카드 노드별로 하나만 유지(빠르게 들락날락해도 값이 안 쌓이게).
var _card_tw: Dictionary = {}


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (제작/훈련소와 통일)
	_close_btn.pressed.connect(close)
	_notice_label.add_theme_color_override(&"font_color", UiTheme.GOLD)
	# 장착 변동·해금 → 열려 있는 동안 즉시 다시 그린다(선택 강조가 실제 상태를 따라가게).
	EventBus.growth_changed.connect(_on_growth_changed)


# --- 공개 API (허수아비가 부른다) ---

func open() -> void:
	_ignore_toggle = true
	call_deferred("_clear_ignore_toggle")  # 같은 프레임 F 소진 방지 (프레임 끝에 해제)
	_refresh()
	# 미리 투명하게 해 둔다 — 아래 페이드를 한 프레임 미루므로, 안 그러면 그 한 프레임 동안 카드가
	# 불투명하게 번쩍인다(pop-in). 페이드 트윈이 이 값에서 1.0으로 올린다.
	_backdrop.modulate.a = 0.0
	_dialog.modulate.a = 0.0
	visible = true
	# 페이드는 한 프레임 미룬다 — 카드가 방금 붙어 컨테이너 size가 아직 0이라, 지금 스케일 pivot을
	# 잡으면 좌상단 기준으로 커진다(중심이 아니라). 다음 프레임엔 레이아웃이 확정돼 중심 pivot이 산다.
	call_deferred("_play_fade", true)


func close() -> void:
	if not visible:
		return
	_play_fade(false)  # 페이드아웃 끝에 실제로 숨긴다


func _clear_ignore_toggle() -> void:
	_ignore_toggle = false


# F(interact)/Esc(ui_cancel)로 닫기. ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로
# (rules §5) 반드시 visible 가드.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not _ignore_toggle:
		close()
		get_viewport().set_input_as_handled()


func _on_growth_changed() -> void:
	if visible:
		_refresh()


# --- 열고닫힘 페이드(+살짝 스케일) 트윈 ---

func _play_fade(opening: bool) -> void:
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	_dialog.pivot_offset = _dialog.size * 0.5  # 중심에서 스케일 (레이아웃 확정 뒤라 size가 유효)
	var from_a := 0.0 if opening else 1.0
	var to_a := 1.0 if opening else 0.0
	var from_s := OPEN_SCALE if opening else 1.0
	var to_s := 1.0 if opening else OPEN_SCALE
	_backdrop.modulate.a = from_a
	_dialog.modulate.a = from_a
	_dialog.scale = Vector2(from_s, from_s)
	_fade_tw = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_fade_tw.tween_property(_backdrop, "modulate:a", to_a, OPEN_TIME)
	_fade_tw.tween_property(_dialog, "modulate:a", to_a, OPEN_TIME)
	_fade_tw.tween_property(_dialog, "scale", Vector2(to_s, to_s), OPEN_TIME)
	if not opening:
		_fade_tw.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	visible = false
	_dialog.scale = Vector2.ONE
	closed.emit()


# --- 그리기 ---

func _refresh() -> void:
	_refresh_notice()
	_refresh_cards()


# 안내 한 줄 — 판 도중 잠금이 최우선(그것만 말하면 왜 안 되는지가 읽힌다). 그 외엔 숨긴다.
func _refresh_notice() -> void:
	var locked := GameState.in_chapter()
	_notice_label.visible = locked
	if locked:
		_notice_label.text = "판 도중에는 직업을 바꿀 수 없습니다 — 마을에서만 선택할 수 있습니다"


func _refresh_cards() -> void:
	_clear(_card_row)
	_card_tw.clear()
	for entry: Dictionary in CARDS:
		_card_row.add_child(_make_card(str(entry["id"]), str(entry["tex"])))


# 카드 하나 = [카드 PNG 배경] + [하단 텍스트 밴드(이름 굵게 + 설명 첫 줄)] + [선택 테두리].
# TextureButton으로 클릭·hover를 받고, 그 위에 이름/설명 라벨을 겹쳐 얹는다(카드 하단이 비어 있다).
func _make_card(sid: String, tex_path: String) -> Control:
	var d: SubJobDef = GameState.sub_job_def(sid)
	var selected := (sid == GameState.main_sub_job_id) and GameState.main_sub_job() != null
	var locked := GameState.in_chapter()

	var btn := TextureButton.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 픽셀아트 크리스프
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var tex := _card_tex(tex_path)
	if tex != null:
		btn.texture_normal = tex
	btn.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5  # hover 스케일이 중심 기준
	btn.modulate = Color(SEL_BRIGHT, SEL_BRIGHT, SEL_BRIGHT, 1.0) if selected else Color(1, 1, 1, 1)
	btn.disabled = locked
	if not locked:
		btn.pressed.connect(_on_card_pressed.bind(sid))
		btn.mouse_entered.connect(_on_card_hover.bind(btn, true, selected))
		btn.mouse_exited.connect(_on_card_hover.bind(btn, false, selected))
	btn.tooltip_text = _card_tooltip(sid, d)

	# 선택 테두리 — 현재 메인이면 카드 위에 금 테두리를 얹는다(픽셀 UI chrome이라 스타일박스 허용 §0).
	if selected:
		var border := Panel.new()
		border.set_anchors_preset(Control.PRESET_FULL_RECT)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(2)
		sb.border_color = UiTheme.GOLD
		border.add_theme_stylebox_override(&"panel", sb)
		btn.add_child(border)

	# 하단 텍스트 밴드 — 카드 위에 겹쳐 앉힌다(카드 하단이 비어 있는 자리).
	btn.add_child(_make_card_text(d, sid))
	return btn


# 카드 하단 이름 + 설명 첫 줄. 마우스 IGNORE = 카드 버튼의 클릭·hover를 그대로 통과.
func _make_card_text(d: SubJobDef, sid: String) -> Control:
	var band := VBoxContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.offset_top = TEXT_BAND_TOP
	band.offset_left = TEXT_BAND_PAD
	band.offset_right = -TEXT_BAND_PAD
	band.offset_bottom = -TEXT_BAND_PAD
	band.add_theme_constant_override(&"separation", 1)
	band.alignment = BoxContainer.ALIGNMENT_CENTER

	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = d.display_name if d != null else sid
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override(&"font_size", UiTheme.FS_BODY)
	name_lbl.add_theme_color_override(&"font_color", UiTheme.GOLD)  # 이름 = 강조(굵게 대신 금색)
	name_lbl.add_theme_color_override(&"font_outline_color", UiTheme.OUTLINE)
	name_lbl.add_theme_constant_override(&"outline_size", UiTheme.OUTLINE_SIZE)
	band.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.text = _first_sentence(d.description) if d != null else ""
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override(&"font_size", UiTheme.FS_BADGE)
	desc_lbl.add_theme_color_override(&"font_color", UiTheme.TEXT)
	desc_lbl.add_theme_color_override(&"font_outline_color", UiTheme.OUTLINE)
	desc_lbl.add_theme_constant_override(&"outline_size", UiTheme.OUTLINE_SIZE_SMALL)
	band.add_child(desc_lbl)
	return band


# --- 조작 ---

# 카드 클릭 → 메인 하위 직업 지정 → 페이드아웃 닫힘.
# 🔴 쓰기는 GameState.set_main_sub_job 하나뿐. 미보유 갈래는 subjob_panel._unlock_and_equip과 같은
#   관례로 즉시 해금(데모라 세 카드가 늘 눌린다) — 그래도 판 도중·타 계열은 GameState가 거부한다.
func _on_card_pressed(sid: String) -> void:
	if GameState.in_chapter():
		_refresh()  # 안내는 _refresh_notice가 대신 말한다
		return
	var d: SubJobDef = GameState.sub_job_def(sid)
	if d == null or d.series_id != GameState.selected_job_id:
		return  # 현재 직업 계열이 아닌 카드 — 데모 3장은 전부 warrior라 평소엔 안 탄다
	if not GameState.sub_job_exp.has(sid):
		GameState.sub_job_exp[sid] = 0  # 해금(키의 존재 = 보유) — 지정 전에 소유부터
	if not GameState.set_main_sub_job(sid):
		return  # GameState가 거부(항등) — 조용히 실패, 상태 안 바꿈
	_commit_save()
	close()  # 외형 갱신은 growth_changed → PeerSync가 처리(신규 네트워크 0)


# hover = 살짝 커지고 발광. 트윈은 카드별로 하나만(빠른 들락날락에 값이 안 쌓이게).
func _on_card_hover(btn: TextureButton, entering: bool, selected: bool) -> void:
	if not is_instance_valid(btn):
		return
	var prev := _card_tw.get(btn) as Tween
	if prev != null and prev.is_valid():
		prev.kill()
	var target_scale := HOVER_SCALE if entering else 1.0
	var base_bright := SEL_BRIGHT if selected else 1.0
	var bright := HOVER_BRIGHT if entering else base_bright
	var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(btn, "scale", Vector2(target_scale, target_scale), HOVER_TIME)
	tw.tween_property(btn, "modulate", Color(bright, bright, bright, 1.0), HOVER_TIME)
	_card_tw[btn] = tw


# --- 텍스트 ---

# 카드 hover 툴팁 — 이름·설명 전문 + 메인/서브 자리 특성(문구는 CombatMath.trait_text 정본).
func _card_tooltip(sid: String, d: SubJobDef) -> String:
	if d == null:
		return sid
	var lines: Array[String] = [d.display_name]
	var main_line := _trait_line(d, true)
	if not main_line.is_empty():
		lines.append("메인 특성 — " + main_line)
	var sub_line := _trait_line(d, false)
	if not sub_line.is_empty():
		lines.append("서브 특성 — " + sub_line)
	if not d.description.is_empty():
		lines.append("")
		lines.append(d.description)
	return "\n".join(lines)


# 자리별 특성 한 줄 — 이름(데이터) + 효과 문구(CombatMath). 🔴 효과 문구를 여기서 짜지 마라
# (rules §3 특성 계약): 값과 표시가 갈라지면 아무 에러도 안 난다.
func _trait_line(d: SubJobDef, as_main: bool) -> String:
	var t := d.trait_at(as_main)
	if t.is_empty():
		return ""
	var txt := CombatMath.trait_text(str(t.get("key", "")), float(t.get("value", 0.0)))
	if txt.is_empty():
		return ""  # 모르는 키(데이터 오타) — 리졸버도 폐기하므로 UI도 약속하지 않는다
	var nm := str(t.get("name", ""))
	return "%s: %s" % [nm, txt] if not nm.is_empty() else txt


# 설명 첫 문장(카드 밴드가 좁아 한 줄만 얹는다). "—"·"." 앞까지, 없으면 통째로.
func _first_sentence(text: String) -> String:
	for sep: String in [" — ", ". ", "—"]:
		var i := text.find(sep)
		if i > 0:
			return text.substr(0, i).strip_edges()
	return text.strip_edges()


# --- 헬퍼 ---

# 카드 텍스처 지연 로드(_ready 시점의 preload 컴파일 실패 회피, ui_theme._tex 관례).
func _card_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path) as Texture2D
	return null


func _clear(container: Node) -> void:
	for c: Node in container.get_children():
		container.remove_child(c)  # 즉시 떼어낸다 — queue_free만 하면 같은 프레임 재생성분과 겹쳐 보인다
		c.queue_free()


func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근(craft_panel 미러).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
