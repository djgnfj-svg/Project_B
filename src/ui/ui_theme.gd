extends RefCounted
# 🔴 **UI 톤의 단일 소스** — 로비·HUD·설정·제작·인벤·창고·훈련소가 전부 이 한 파일에서 색/폰트/여백을 받는다.
# (rules §0: 배경·구분선·버튼·슬롯 프레임 같은 순수 UI chrome는 스타일박스 허용 — 게임 오브젝트가 아님.)
# 판타지 나무·황동 프레임을 640×360 픽셀 캔버스에 각색: 어두운 참나무 패널 + 금 트림 + 코너 스터드.
# 코드로 Theme를 조립해 한 번 캐시 — 손으로 쓴 .tres 포맷 오류를 피하고 모든 화면이 같은 함수를 문다.
# class_name 선언 안 함(§0) — 각 UI가 const preload로 문다.
#
# 🔴 **여기가 정본이다 — .tres 테마를 따로 만들지 마라.** 두 개가 되는 순간 한쪽만 고쳐져 갈라진다
#   (rules §3 "같은 계산을 두 곳에서 하면 아무도 모르게 갈라진다"의 UI판). 새 색·크기·여백이 필요하면
#   씬에 `theme_override_*`를 박지 말고 **여기 등급 상수/타입 배리에이션을 늘려라.**
#
# 쓰는 법 두 가지:
#  ⑴ 루트에 테마 걸기 — `$Center.theme = UiTheme.get_theme()` (모달) / `theme = ...` (로비 루트 Control)
#     HUD처럼 루트가 CanvasLayer면 Control 자식마다 걸어야 한다(`apply_to_children`).
#  ⑵ 개별 위젯 등급 — `label.theme_type_variation = &"TitleLabel"` (아래 배리에이션 목록)
#     씬 파일에선 `theme_type_variation = &"TitleLabel"` 한 줄.
#
# 🎨 **프레임은 이제 픽셀 텍스처다(2026-08-01)** — 패널·버튼·슬롯이 9-slice `StyleBoxTexture`를 쓴다.
#   그전까지는 코드로 만든 둥근 `StyleBoxFlat`(다크 네이비 + 시안)이라 픽셀아트 게임 화면에서 혼자 벡터로
#   떠 보였다. 🔴 **둥근 모서리를 되살리지 마라** — 픽셀 격자에 안 맞는 안티에일리어스 곡선이 이질감의
#   실제 원인이었다(색보다 형태가 먼저 튄다). 텍스처가 없는 작은 요소(탭·툴팁·바·입력칸)는 여전히
#   StyleBoxFlat이되 **corner_radius = 0**이다.

static var _cached: Theme = null

# --- 프레임 텍스처 (9-slice) ---
# ⚠ 경로만 상수로 두고 로드는 `_tex()`가 지연 수행한다 — `-s` 헤드리스가 이 스크립트를 preload할 때
#   .import 사이드카가 없으면 preload는 통째로 컴파일 실패하지만, 지연 로드는 폴백으로 살아남는다.
const TEX_PANEL := "res://assets/sprites/ui/ui_panel.png"
const TEX_BUTTON := "res://assets/sprites/ui/ui_button.png"
const TEX_SLOT := "res://assets/sprites/ui/ui_slot.png"

# 9-slice 마진 — 각 텍스처의 **실측 테두리 두께**다(픽셀 스캔으로 잼).
# 🔴 텍스처를 다시 그리면 이 값도 같이 고쳐라. 크면 프레임이 잘리고, 작으면 코너 장식이 늘어난다.
const NS_PANEL := 14   # ui_panel.png 60×60 — 코너 스터드 장식까지 덮는 두께
const NS_BUTTON := 5   # ui_button.png 61×27 — 검정1 + 금3 + 검정1 = 정확히 5
const NS_SLOT := 7     # ui_slot.png 30×31 — 금테 + 리벳

# --- 폰트 크기 등급 (제목/본문/보조) ---
# ⚠ Galmuri9는 **12px에서 픽셀 격자에 딱 맞는다** — 본문 12·배너 24(2배)가 가장 또렷하다.
#   기존에 흩어져 있던 9/10/11/13/16/20/24 잡탕을 이 4단계로 접었다.
const FS_TITLE := 16   # 패널 제목 (모달 헤더·로비 타이틀)
const FS_BODY := 12    # 본문 기본값 — Label/Button/LineEdit의 테마 기본
const FS_SMALL := 10   # 보조(밀집 정보: 스탯 줄·비용·힌트)
const FS_BADGE := 9    # 슬롯 칸 위에 겹쳐 찍는 수량/이름 — 32~44px 칸을 넘치면 안 되는 자리
const FS_BANNER := 24  # 화면 중앙 상태 배너 (클리어/전멸/페이즈2)

# --- 여백·크기 등급 ---
const PAD_PANEL := 12    # 모달 다이얼로그 안쪽 패딩 (사방) — 프레임 두께는 PAD_FRAME이 따로 더한다
const PAD_FRAME := 4     # 나무 프레임이 먹는 몫 — 내용이 금 트림 위로 올라타지 않게
const PAD_INNER := 8     # 패널 안 섹션(인벤 바·스탯 박스) 안쪽 패딩
const GAP_SECTION := 8   # 섹션 사이 (VBox separation)
const GAP_ROW := 6       # 같은 섹션 안 행 사이
const GAP_TIGHT := 4     # 그리드 칸 사이
const BTN_MIN_W := 56    # 닫기 등 헤더 버튼 최소 폭 — 패널마다 52/56으로 갈리던 것을 통일
const BTN_PAD_H := 8     # 버튼 좌우 안쪽 여백 (스타일박스)
const BTN_PAD_V := 5     # 버튼 상하 안쪽 여백
# 🔴 **BTN_PAD_V < NS_BUTTON이면 글자가 프레임 밑으로 들어가 사라진다.** 9-slice 마진은 테두리를
#   고정할 뿐 텍스트 자리를 비켜주지 않으므로, 안쪽 여백이 테두리보다 작으면 글씨가 금테 위에 겹쳐
#   찍힌다 — 큰 버튼("방 만들기")은 멀쩡하고 **작은 버튼에서만** 드러나서 놓치기 쉽다(실제로 밟았다).
#   이 부등식을 깨는 방향으로 조이지 마라: BTN_PAD_V >= NS_BUTTON.

# --- HUD 바 색 (연출값이지만 팔레트라 여기 모은다 — 씬 SubResource로 흩어지면 톤이 갈라진다) ---
# 🎨 전부 게임 35색 팔레트에서 골랐다(마을 아트 실측) — UI만 다른 색계를 쓰면 톤이 갈라진다.
const HP_FILL := Color(0.749, 0.247, 0.180, 1.0)   # 체력 = 붉은 #BF3F2E
const EXP_FILL := Color(0.969, 0.776, 0.294, 1.0)  # EXP = 금 #F7C64B (파랑은 이 팔레트에 없다)
const ROLL_FILL := Color(0.549, 0.580, 0.565, 1.0) # 구르기 쿨 = 회청 #8C9490
const BAR_BG := Color(0.102, 0.063, 0.031, 0.80)   # 바 바탕 (게임 화면이 살짝 비치게 반투명)
const OUTLINE := Color(0.043, 0.024, 0.008, 0.9)   # HUD 글자 외곽선 — 밝은 지형 위에서도 읽히게
const OUTLINE_SIZE := 3

# --- 팔레트 (어두운 참나무 + 황동) ---
# 텍스처에서 실측한 색이라 프레임과 색면이 이어진다. 폴백 StyleBoxFlat도 같은 값을 쓴다.
const PANEL_BG := Color(0.188, 0.153, 0.141, 0.98)   # 패널 본체 #302724 (ui_panel 내부색)
const PANEL_BG2 := Color(0.145, 0.094, 0.086, 1.0)   # 안쪽 섹션 #251816 (ui_slot 내부색)
const PANEL_BORDER := Color(0.337, 0.263, 0.184, 1.0)  # 나무 테두리 #56432F
const ACCENT := Color(0.906, 0.757, 0.494, 1.0)      # 금 트림 #E7C17E (패널 라인과 같은 색)
const TEXT := Color(0.941, 0.878, 0.753, 1.0)        # 밝은 양피지 #F0E0C0
const TEXT_DIM := Color(0.690, 0.553, 0.388, 1.0)    # 흐린 갈금 #B08D63
const GOLD := Color(0.969, 0.776, 0.294, 1.0)        # #F7C64B (게임 팔레트)

# 버튼 글자 — 🔴 버튼 면이 **밝은 나무**(#C58E50)라 글자가 어두워야 읽힌다.
# 옛 네이비 버튼의 밝은 글자를 그대로 두면 대비가 무너져 글씨가 사라진다.
const BTN_TEXT := Color(0.165, 0.102, 0.055, 1.0)       # #2A1A0E
const BTN_TEXT_HOVER := Color(0.082, 0.047, 0.016, 1.0) # #150C04
const BTN_TEXT_DISABLED := Color(0.416, 0.333, 0.251, 1.0)

# 버튼 상태 틴트 — 텍스처 한 장을 modulate로 3상태로 쓴다(프레임 두께가 상태마다 달라지지 않는다).
# ⚠ pressed를 더 어둡게 하면 BTN_TEXT(어두운 글자)와 대비가 무너진다 — 0.76이 하한이다.
const BTN_TINT_NORMAL := Color(0.92, 0.90, 0.86, 1.0)
const BTN_TINT_HOVER := Color(1.12, 1.10, 1.02, 1.0)
const BTN_TINT_PRESSED := Color(0.76, 0.72, 0.66, 1.0)
const BTN_TINT_DISABLED := Color(0.50, 0.47, 0.44, 0.85)

# 슬롯 셀
const SLOT_EMPTY_BG := Color(0.145, 0.094, 0.086, 1.0)
const SLOT_FILLED_BG := Color(0.227, 0.165, 0.118, 1.0)
const SLOT_BORDER := Color(0.678, 0.467, 0.216, 1.0)   # 기본 슬롯 테두리 #AD7737
const SLOT_HOVER := Color(0.969, 0.776, 0.294, 1.0)    # hover/선택 금
const EQUIP_BORDER := Color(0.949, 0.584, 0.227, 1.0)  # 장비(무기/방어구) 주황금 #F2953A
const EQUIPPED_GLOW := Color(0.455, 0.800, 0.184, 1.0) # 착용 중 초록 #74CC2F

# 재료 등급 색 (MaterialDef.rarity 0/1/2)
const RARITY := {
	0: Color(0.549, 0.580, 0.565, 1.0),   # 일반 #8C9490
	1: Color(0.376, 0.424, 0.569, 1.0),   # 희귀 #606C91
	2: Color(0.969, 0.776, 0.294, 1.0),   # 핵심 #F7C64B
}


static func rarity_color(rarity: int) -> Color:
	return RARITY.get(rarity, RARITY[0])


# 프레임 텍스처 지연 로드 + 캐시. 없으면 null → 부르는 쪽이 StyleBoxFlat으로 폴백한다.
# 🔴 `--import` 전이거나 웹 익스포트에서 빠지면 여기가 null이 된다 — 그때도 UI가 통째로 사라지지
#   않고 색면 프레임으로 떨어질 뿐이다(rules §5 "조용히 깨지는" 것을 피한다).
static var _tex_cache: Dictionary = {}


static func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = ResourceLoader.load(path) as Texture2D
	_tex_cache[path] = t
	return t


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()

	# --- 기본 폰트 크기 (본문) — 이 한 줄이 씬마다 흩어진 font_size 오버라이드를 대체한다 ---
	for type_name: String in [
		"Label", "Button", "LineEdit", "CheckButton", "CheckBox", "TabContainer", "TooltipLabel",
	]:
		t.set_font_size("font_size", type_name, FS_BODY)

	# --- PanelContainer: 나무 프레임 (9-slice 텍스처) ---
	# 🔴 안쪽 패딩을 **스타일박스가 소유한다** — 씬마다 MarginContainer로 14/12/10/16씩 따로 주던 것을 걷어냈다.
	#   패널 여백을 바꾸고 싶으면 PAD_PANEL 한 줄만 고친다(씬 5개를 찾아다니지 않는다).
	t.set_stylebox("panel", "PanelContainer", panel_box())

	# --- Button: 나무 + 금테 텍스처, 상태는 틴트로 ---
	t.set_stylebox("normal", "Button", _btn_box(BTN_TINT_NORMAL))
	t.set_stylebox("hover", "Button", _btn_box(BTN_TINT_HOVER))
	t.set_stylebox("pressed", "Button", _btn_box(BTN_TINT_PRESSED))
	t.set_stylebox("disabled", "Button", _btn_box(BTN_TINT_DISABLED))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", BTN_TEXT)
	t.set_color("font_hover_color", "Button", BTN_TEXT_HOVER)
	t.set_color("font_pressed_color", "Button", BTN_TEXT)
	t.set_color("font_disabled_color", "Button", BTN_TEXT_DISABLED)

	# --- Label ---
	t.set_color("font_color", "Label", TEXT)

	# --- 구분선 ---
	var sep := StyleBoxFlat.new()
	sep.bg_color = PANEL_BORDER
	sep.content_margin_top = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)

	# --- ScrollContainer 스크롤바(슬림 나무) ---
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.502, 0.353, 0.176, 1.0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0.086, 0.055, 0.031, 0.6)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)

	# --- TabContainer (제작/강화 탭) ---
	# 탭은 아래가 열려 있어야 본문과 이어져 보인다 → 텍스처(사방 프레임)를 안 쓰고 색면으로 남긴다.
	t.set_stylebox("panel", "TabContainer", _flat_box(PANEL_BG2, PANEL_BORDER, 1, PAD_INNER))
	t.set_stylebox("tab_selected", "TabContainer", _tab_box(Color(0.290, 0.196, 0.114, 1.0), ACCENT, true))
	t.set_stylebox("tab_unselected", "TabContainer", _tab_box(Color(0.129, 0.086, 0.055, 1.0), PANEL_BORDER, false))
	t.set_stylebox("tab_hovered", "TabContainer", _tab_box(Color(0.227, 0.153, 0.090, 1.0), ACCENT, false))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	# --- 툴팁 (아이템 상세) ---
	# 작고 자주 뜨는 것이라 큰 나무 프레임은 시끄럽다 — 금 실선 색면으로.
	t.set_stylebox("panel", "TooltipPanel", _flat_box(Color(0.078, 0.047, 0.027, 0.98), ACCENT, 1, 5))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# --- LineEdit (로비 방 코드·서버 주소) — 파인 나무 홈처럼 ---
	var edit_bg := _flat_box(SLOT_EMPTY_BG, SLOT_BORDER, 1, 6)
	t.set_stylebox("normal", "LineEdit", edit_bg)
	t.set_stylebox("focus", "LineEdit", _flat_box(SLOT_EMPTY_BG, GOLD, 1, 6))
	t.set_stylebox("read_only", "LineEdit", _flat_box(SLOT_EMPTY_BG, PANEL_BORDER, 1, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(0.906, 0.757, 0.494, 0.35))

	# --- HSlider (설정 볼륨) ---
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = SLOT_EMPTY_BG
	slider_bg.set_border_width_all(1)
	slider_bg.border_color = PANEL_BORDER
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = GOLD
	slider_fill.content_margin_top = 3
	slider_fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	# --- CheckButton (음소거) ---
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color(1, 1, 1, 1))
	t.set_color("font_pressed_color", "CheckButton", GOLD)
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	# --- ProgressBar (HP·EXP·구르기 쿨) — 바탕만 공용, 채움색은 bar_fill()로 바마다 ---
	t.set_stylebox("background", "ProgressBar", bar_bg())
	t.set_stylebox("fill", "ProgressBar", bar_fill(ACCENT))

	# --- 타입 배리에이션(등급) — 씬에서 theme_type_variation 한 줄로 고른다 ---
	_label_variation(t, "TitleLabel", FS_TITLE, GOLD, false)       # 패널 제목
	_label_variation(t, "SectionLabel", FS_BODY, ACCENT, false)    # 섹션 머리말("내 가방")
	_label_variation(t, "SmallLabel", FS_SMALL, TEXT_DIM, false)   # 흐린 보조(힌트·빈 목록 안내)
	_label_variation(t, "InfoLabel", FS_SMALL, TEXT, false)        # 작지만 본문급(스탯 readout)
	_label_variation(t, "GoldLabel", FS_BODY, GOLD, false)         # 골드 수치(패널 안)
	_label_variation(t, "HudLabel", FS_BODY, Color(1, 1, 1, 1), true)  # HUD — 지형 위라 외곽선
	_label_variation(t, "HudGoldLabel", FS_BODY, GOLD, true)
	_label_variation(t, "BannerLabel", FS_BANNER, Color(1, 1, 1, 1), true)
	_label_variation(t, "ToastLabel", FS_TITLE, GOLD, true)  # 색은 종류별로 코드가 덮는다(해금 금색/레벨 연두)
	# 작은 버튼(보관/꺼내기 같은 인라인 액션)
	t.set_type_variation("SmallButton", "Button")
	t.set_font_size("font_size", "SmallButton", FS_SMALL)
	# 패널 안 섹션 박스 — 본체보다 어두운 홈(사방 프레임을 겹치면 시끄럽다)
	t.set_type_variation("InnerPanel", "PanelContainer")
	t.set_stylebox("panel", "InnerPanel", _flat_box(PANEL_BG2, PANEL_BORDER, 1, PAD_INNER))

	_cached = t
	return t


# 모달 패널 프레임 — 나무 텍스처 9-slice. 텍스처가 없으면 색면으로 폴백한다.
static func panel_box() -> StyleBox:
	var tex := _tex(TEX_PANEL)
	if tex == null:
		return _flat_box(PANEL_BG, ACCENT, 2, PAD_PANEL + PAD_FRAME)
	return _tex_box(tex, NS_PANEL, PAD_PANEL + PAD_FRAME, Color(1, 1, 1, 1))


# HUD 바 바탕/채움 — ProgressBar 스타일을 씬 SubResource로 흩지 않고 여기서 만든다.
# ⚠ 반환 타입이 StyleBoxFlat 그대로다 — 바는 텍스처를 안 쓴다(6~18px라 9-slice가 안 들어간다).
static func bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_BG
	s.set_border_width_all(1)
	s.border_color = Color(0.337, 0.263, 0.184, 0.9)
	return s


static func bar_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s


# 루트가 CanvasLayer라 theme 프로퍼티가 없는 경우(HUD)에 쓴다 — Control 자식마다 테마를 건다.
# 손자는 Control 상속으로 자동 전파되므로 한 겹만 돌면 된다.
# ⚠ 자식 CanvasLayer(설정·인벤 패널)는 건너뛴다 — 그쪽은 자기 루트에 직접 건다.
static func apply_to_children(root: Node) -> void:
	var t := get_theme()
	for c: Node in root.get_children():
		if c is Control:
			(c as Control).theme = t


static func _label_variation(
	t: Theme, name: String, size: int, color: Color, outline: bool
) -> void:
	t.set_type_variation(name, "Label")
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)
	if outline:
		t.set_color("font_outline_color", name, OUTLINE)
		t.set_constant("outline_size", name, OUTLINE_SIZE)


# --- 슬롯 셀 스타일박스 (slot_cell이 상태별로 부른다) ---
# 금테 소켓 텍스처 한 장을 **틴트**로 등급/상태에 맞춘다 — 등급마다 PNG를 그리지 않는다.
# 🔴 반환 타입이 StyleBox(부모 타입)다 — 텍스처가 없으면 StyleBoxFlat이 나온다. 호출부는 전부
#   `add_theme_stylebox_override`로 넘기므로 좁은 타입을 요구하지 않는다.
static func slot_box(border_color: Color, filled: bool, highlight: bool) -> StyleBox:
	var tex := _tex(TEX_SLOT)
	if tex == null:
		return _flat_slot(border_color, filled, highlight)
	var tint := Color(0.72, 0.68, 0.64, 1.0)  # 빈 칸은 가라앉힌다
	if filled:
		tint = _tint_of(border_color)
	if highlight:
		tint = tint * 1.22
		tint.a = 1.0
	return _tex_box(tex, NS_SLOT, 0, tint)


# 착용 중 슬롯 — 초록 틴트(장비 doll에서 현재 착용 표시)
static func equipped_slot_box() -> StyleBox:
	var tex := _tex(TEX_SLOT)
	if tex == null:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.11, 0.18, 0.15, 1.0)
		s.set_border_width_all(2)
		s.border_color = EQUIPPED_GLOW
		return s
	return _tex_box(tex, NS_SLOT, 0, Color(0.62, 1.15, 0.66, 1.0))


# 등급색을 modulate 틴트로 바꾼다 — 색조는 남기고 밝기를 1 근처로 올려
# 금테가 곱셈으로 탁해지는 것을 막는다(어두운 등급색을 그대로 곱하면 프레임이 죽는다).
# 🔴 **흰색 쪽으로 섞어야 한다(TINT_MIX)** — 정규화한 등급색을 그대로 곱하면 색조 힌트가 아니라
#   **전체 도색**이 된다. 실기에서 장비 슬롯(주황금)이 금테를 통째로 주황 단색으로 덮어, 칸 안의
#   아이콘보다 테두리가 더 눈에 띄었다. 섞고 나면 금테 소켓이 살아 있고 등급은 색조로만 읽힌다.
const TINT_MIX := 0.45  # 0 = 등급 무시(원본 금테) · 1 = 등급색 도색(실기에서 기각된 값)


static func _tint_of(c: Color) -> Color:
	var m := maxf(c.r, maxf(c.g, c.b))
	if m <= 0.001:
		return Color(1, 1, 1, 1)
	var norm := Color(c.r / m, c.g / m, c.b / m, 1.0)
	var mixed := Color(1, 1, 1, 1).lerp(norm, TINT_MIX)
	return Color(mixed.r * 1.08, mixed.g * 1.08, mixed.b * 1.08, 1.0)


# 9-slice 텍스처 스타일박스. margin = 테두리 두께(늘어나지 않는 가장자리), pad = 안쪽 내용 여백.
# 🔴 축 stretch는 **STRETCH여야 한다 — TILE로 바꾸지 마라.** 픽셀아트의 일반 통념은 TILE이지만
#   이 텍스처들은 중앙이 균일색이 아니라 **나무결**이라, 타일링하면 중앙폭(버튼 51px)마다 결이
#   끊긴 **세로 이음매 줄**이 생긴다(실기에서 버튼마다 금줄 3개로 나타났다). STRETCH는 nearest
#   필터라 픽셀이 계단식으로 늘어날 뿐이고, 결 자체가 가로 방향이라 늘어나도 읽히지 않는다.
static func _tex_box(tex: Texture2D, margin: int, pad: int, tint: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.set_texture_margin_all(margin)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.modulate_color = tint
	if pad > 0:
		s.set_content_margin_all(pad)
	return s


# 🔴 corner_radius를 되살리지 마라 — 픽셀 격자에 안 맞는 곡선이 이질감의 실제 원인이었다.
static func _flat_box(bg: Color, border: Color, border_w: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


# 슬롯 텍스처가 없을 때의 폴백 — 옛 색면 슬롯과 같은 모양(모서리만 각졌다).
static func _flat_slot(border_color: Color, filled: bool, highlight: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SLOT_FILLED_BG if filled else SLOT_EMPTY_BG
	var bw := 2 if (filled or highlight) else 1
	s.set_border_width_all(bw)
	s.border_color = SLOT_HOVER if highlight else (border_color if filled else SLOT_BORDER)
	return s


static func _btn_box(tint: Color) -> StyleBox:
	var tex := _tex(TEX_BUTTON)
	if tex == null:
		var f := _flat_box(Color(0.773, 0.557, 0.314, 1.0) * tint, PANEL_BORDER, 1, 0)
		f.content_margin_left = BTN_PAD_H
		f.content_margin_right = BTN_PAD_H
		f.content_margin_top = BTN_PAD_V
		f.content_margin_bottom = BTN_PAD_V
		return f
	var s := _tex_box(tex, NS_BUTTON, 0, tint)
	s.content_margin_left = BTN_PAD_H
	s.content_margin_right = BTN_PAD_H
	s.content_margin_top = BTN_PAD_V
	s.content_margin_bottom = BTN_PAD_V
	return s


static func _tab_box(bg: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_top = 2 if selected else 1
	s.border_color = border
	s.content_margin_left = PAD_PANEL
	s.content_margin_right = PAD_PANEL
	s.content_margin_top = BTN_PAD_V   # 탭 높이 = 버튼 높이와 같은 등급으로 (헤더 줄이 들쭉날쭉하지 않게)
	s.content_margin_bottom = BTN_PAD_V
	return s
