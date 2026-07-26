extends RefCounted
# 🔴 **UI 톤의 단일 소스** — 로비·HUD·설정·제작·인벤·창고·훈련소가 전부 이 한 파일에서 색/폰트/여백을 받는다.
# (rules §0: 배경·구분선·버튼·슬롯 프레임 같은 순수 UI chrome는 스타일박스 허용 — 게임 오브젝트가 아님.)
# 언던류 슬롯 그리드 UI를 640×360 픽셀 캔버스에 각색: 다크 네이비 패널 + 시안 액센트 + 등급 테두리 슬롯.
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

static var _cached: Theme = null

# --- 폰트 크기 등급 (제목/본문/보조) ---
# ⚠ Galmuri9는 **12px에서 픽셀 격자에 딱 맞는다** — 본문 12·배너 24(2배)가 가장 또렷하다.
#   기존에 흩어져 있던 9/10/11/13/16/20/24 잡탕을 이 4단계로 접었다.
const FS_TITLE := 16   # 패널 제목 (모달 헤더·로비 타이틀)
const FS_BODY := 12    # 본문 기본값 — Label/Button/LineEdit의 테마 기본
const FS_SMALL := 10   # 보조(밀집 정보: 스탯 줄·비용·힌트)
const FS_BADGE := 9    # 슬롯 칸 위에 겹쳐 찍는 수량/이름 — 32~44px 칸을 넘치면 안 되는 자리
const FS_BANNER := 24  # 화면 중앙 상태 배너 (클리어/전멸/페이즈2)

# --- 여백·크기 등급 ---
const PAD_PANEL := 12    # 모달 다이얼로그 안쪽 패딩 (사방)
const PAD_INNER := 8     # 패널 안 섹션(인벤 바·스탯 박스) 안쪽 패딩
const GAP_SECTION := 8   # 섹션 사이 (VBox separation)
const GAP_ROW := 6       # 같은 섹션 안 행 사이
const GAP_TIGHT := 4     # 그리드 칸 사이
const BTN_MIN_W := 56    # 닫기 등 헤더 버튼 최소 폭 — 패널마다 52/56으로 갈리던 것을 통일
const BTN_PAD_H := 8     # 버튼 좌우 안쪽 여백 (스타일박스)
const BTN_PAD_V := 4     # 버튼 상하 안쪽 여백 — 실질 최소 높이를 결정

# --- HUD 바 색 (연출값이지만 팔레트라 여기 모은다 — 씬 SubResource로 흩어지면 톤이 갈라진다) ---
const HP_FILL := Color(0.85, 0.16, 0.16, 1.0)    # 체력 = 빨강
const EXP_FILL := Color(0.35, 0.72, 1.0, 1.0)    # EXP = 파랑
const ROLL_FILL := Color(0.45, 0.78, 0.95, 1.0)  # 구르기 쿨 = 하늘
const BAR_BG := Color(0.055, 0.078, 0.135, 0.75) # 바 바탕 (게임 화면이 살짝 비치게 반투명)
const OUTLINE := Color(0, 0, 0, 0.8)             # HUD 글자 외곽선 — 밝은 지형 위에서도 읽히게
const OUTLINE_SIZE := 3

# --- 팔레트 (다크 네이비 + 시안) ---
const PANEL_BG := Color(0.055, 0.078, 0.135, 0.98)   # 패널 본체 네이비
const PANEL_BG2 := Color(0.078, 0.106, 0.176, 1.0)   # 안쪽 섹션(살짝 밝은 네이비)
const PANEL_BORDER := Color(0.20, 0.30, 0.46, 1.0)   # 패널 테두리(청회색)
const ACCENT := Color(0.31, 0.72, 0.86, 1.0)         # 시안 액센트(헤더·강조)
const TEXT := Color(0.86, 0.90, 0.96, 1.0)
const TEXT_DIM := Color(0.55, 0.62, 0.74, 1.0)
const GOLD := Color(1.0, 0.82, 0.30, 1.0)

# 슬롯 셀
const SLOT_EMPTY_BG := Color(0.043, 0.063, 0.110, 1.0)
const SLOT_FILLED_BG := Color(0.094, 0.129, 0.204, 1.0)
const SLOT_BORDER := Color(0.16, 0.23, 0.36, 1.0)     # 기본 슬롯 테두리
const SLOT_HOVER := Color(0.31, 0.72, 0.86, 1.0)      # hover/선택 시안
const EQUIP_BORDER := Color(0.85, 0.68, 0.35, 1.0)    # 장비(무기/방어구) 금빛 테두리
const EQUIPPED_GLOW := Color(0.35, 0.85, 0.55, 1.0)   # 착용 중 초록 표시

# 재료 등급 색 (MaterialDef.rarity 0/1/2)
const RARITY := {
	0: Color(0.52, 0.58, 0.66, 1.0),   # 일반(회색)
	1: Color(0.35, 0.62, 0.95, 1.0),   # 희귀(파랑)
	2: Color(0.92, 0.74, 0.32, 1.0),   # 핵심(금)
}


static func rarity_color(rarity: int) -> Color:
	return RARITY.get(rarity, RARITY[0])


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()

	# --- 기본 폰트 크기 (본문) — 이 한 줄이 씬마다 흩어진 font_size 오버라이드를 대체한다 ---
	for type_name: String in [
		"Label", "Button", "LineEdit", "CheckButton", "CheckBox", "TabContainer", "TooltipLabel",
	]:
		t.set_font_size("font_size", type_name, FS_BODY)

	# --- PanelContainer: 패널 프레임 ---
	# 🔴 안쪽 패딩을 **스타일박스가 소유한다** — 씬마다 MarginContainer로 14/12/10/16씩 따로 주던 것을 걷어냈다.
	#   패널 여백을 바꾸고 싶으면 PAD_PANEL 한 줄만 고친다(씬 5개를 찾아다니지 않는다).
	t.set_stylebox("panel", "PanelContainer", _panel_box(PANEL_BG, PANEL_BORDER, 2, 8, PAD_PANEL))

	# --- Button: 네이비 라이즈드 + 시안 hover ---
	t.set_stylebox("normal", "Button", _btn_box(Color(0.13, 0.18, 0.29, 1.0), PANEL_BORDER))
	t.set_stylebox("hover", "Button", _btn_box(Color(0.18, 0.26, 0.40, 1.0), ACCENT))
	t.set_stylebox("pressed", "Button", _btn_box(Color(0.10, 0.14, 0.22, 1.0), ACCENT))
	t.set_stylebox("disabled", "Button", _btn_box(Color(0.09, 0.11, 0.16, 0.7), Color(0.16, 0.20, 0.28, 1.0)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1, 1))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)

	# --- Label ---
	t.set_color("font_color", "Label", TEXT)

	# --- 구분선 ---
	var sep := StyleBoxFlat.new()
	sep.bg_color = PANEL_BORDER
	sep.content_margin_top = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)

	# --- ScrollContainer 스크롤바(슬림 네이비) ---
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.24, 0.34, 0.50, 1.0)
	grabber.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0.04, 0.06, 0.10, 0.6)
	scroll_bg.set_corner_radius_all(3)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)

	# --- TabContainer (제작/강화 탭) ---
	t.set_stylebox("panel", "TabContainer", _panel_box(PANEL_BG2, PANEL_BORDER, 1, 6, PAD_INNER))
	t.set_stylebox("tab_selected", "TabContainer", _tab_box(Color(0.16, 0.24, 0.38, 1.0), ACCENT, true))
	t.set_stylebox("tab_unselected", "TabContainer", _tab_box(Color(0.08, 0.11, 0.17, 1.0), PANEL_BORDER, false))
	t.set_stylebox("tab_hovered", "TabContainer", _tab_box(Color(0.13, 0.19, 0.30, 1.0), ACCENT, false))
	t.set_color("font_selected_color", "TabContainer", Color(1, 1, 1, 1))
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	# --- 툴팁 (아이템 상세) ---
	t.set_stylebox("panel", "TooltipPanel", _panel_box(Color(0.03, 0.05, 0.09, 0.98), ACCENT, 1, 6, 5))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# --- LineEdit (로비 방 코드·서버 주소) — 기본 밝은 테마가 로비만 튀던 것 ---
	var edit_bg := _panel_box(SLOT_EMPTY_BG, SLOT_BORDER, 1, 4, 6)
	t.set_stylebox("normal", "LineEdit", edit_bg)
	t.set_stylebox("focus", "LineEdit", _panel_box(SLOT_EMPTY_BG, ACCENT, 1, 4, 6))
	t.set_stylebox("read_only", "LineEdit", _panel_box(SLOT_EMPTY_BG, SLOT_BORDER, 1, 4, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(0.31, 0.72, 0.86, 0.35))

	# --- HSlider (설정 볼륨) ---
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = SLOT_EMPTY_BG
	slider_bg.set_corner_radius_all(2)
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = ACCENT
	slider_fill.set_corner_radius_all(2)
	slider_fill.content_margin_top = 3
	slider_fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	# --- CheckButton (음소거) ---
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color(1, 1, 1, 1))
	t.set_color("font_pressed_color", "CheckButton", ACCENT)
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	# --- ProgressBar (HP·EXP·구르기 쿨) — 바탕만 공용, 채움색은 bar_fill()로 바마다 ---
	t.set_stylebox("background", "ProgressBar", bar_bg())
	t.set_stylebox("fill", "ProgressBar", bar_fill(ACCENT))

	# --- 타입 배리에이션(등급) — 씬에서 theme_type_variation 한 줄로 고른다 ---
	_label_variation(t, "TitleLabel", FS_TITLE, ACCENT, false)     # 패널 제목
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
	# 패널 안 섹션 박스 — 본체보다 한 단계 밝은 네이비
	t.set_type_variation("InnerPanel", "PanelContainer")
	t.set_stylebox("panel", "InnerPanel", _panel_box(PANEL_BG2, PANEL_BORDER, 1, 4, PAD_INNER))

	_cached = t
	return t


# HUD 바 바탕/채움 — ProgressBar 스타일을 씬 SubResource로 흩지 않고 여기서 만든다.
static func bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_BG
	s.set_corner_radius_all(2)
	s.set_border_width_all(1)
	s.border_color = Color(0.16, 0.23, 0.36, 0.9)
	return s


static func bar_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(2)
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
# border_color = 등급/장비 색, hover/선택 시 시안. filled면 밝은 바탕.
static func slot_box(border_color: Color, filled: bool, highlight: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SLOT_FILLED_BG if filled else SLOT_EMPTY_BG
	s.set_corner_radius_all(4)
	var bw := 2 if (filled or highlight) else 1
	s.set_border_width_all(bw)
	s.border_color = SLOT_HOVER if highlight else (border_color if filled else SLOT_BORDER)
	return s


# 착용 중 슬롯 — 초록 글로우 테두리(장비 doll에서 현재 착용 표시)
static func equipped_slot_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.11, 0.18, 0.15, 1.0)
	s.set_corner_radius_all(4)
	s.set_border_width_all(2)
	s.border_color = EQUIPPED_GLOW
	return s


static func _panel_box(bg: Color, border: Color, border_w: int, radius: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border_w)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


static func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(4)
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
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.content_margin_left = PAD_PANEL
	s.content_margin_right = PAD_PANEL
	s.content_margin_top = BTN_PAD_V   # 탭 높이 = 버튼 높이와 같은 등급으로 (헤더 줄이 들쭉날쭉하지 않게)
	s.content_margin_bottom = BTN_PAD_V
	return s
