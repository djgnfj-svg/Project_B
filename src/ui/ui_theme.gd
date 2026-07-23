extends RefCounted
# 공용 프리미엄 UI 테마 (다크 네이비) — 인벤/제작/창고 패널이 루트 Control에 걸어 비주얼을 통일한다.
# (rules §0: 배경·구분선·버튼·슬롯 프레임 같은 순수 UI chrome는 스타일박스 허용 — 게임 오브젝트가 아님.)
# 언던류 슬롯 그리드 UI를 640×360 픽셀 캔버스에 각색: 다크 네이비 패널 + 시안 액센트 + 등급 테두리 슬롯.
# 코드로 Theme를 조립해 한 번 캐시 — 손으로 쓴 .tres 포맷 오류를 피하고 세 패널이 같은 함수를 문다.
# ⚠ 폰트/크기는 프로젝트 기본 픽셀 폰트(Galmuri9) 상속 유지 — 640×360 레이아웃 안정.
# class_name 선언 안 함(§0) — 패널이 const preload로 문다.

static var _cached: Theme = null

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

	# --- PanelContainer: 패널 프레임 ---
	t.set_stylebox("panel", "PanelContainer", _panel_box(PANEL_BG, PANEL_BORDER, 2, 8, 6))

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
	t.set_stylebox("panel", "TabContainer", _panel_box(PANEL_BG2, PANEL_BORDER, 1, 6, 6))
	t.set_stylebox("tab_selected", "TabContainer", _tab_box(Color(0.16, 0.24, 0.38, 1.0), ACCENT, true))
	t.set_stylebox("tab_unselected", "TabContainer", _tab_box(Color(0.08, 0.11, 0.17, 1.0), PANEL_BORDER, false))
	t.set_stylebox("tab_hovered", "TabContainer", _tab_box(Color(0.13, 0.19, 0.30, 1.0), ACCENT, false))
	t.set_color("font_selected_color", "TabContainer", Color(1, 1, 1, 1))
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	# --- 툴팁 (아이템 상세) ---
	t.set_stylebox("panel", "TooltipPanel", _panel_box(Color(0.03, 0.05, 0.09, 0.98), ACCENT, 1, 6, 5))
	t.set_color("font_color", "TooltipLabel", TEXT)

	_cached = t
	return t


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
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


static func _tab_box(bg: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_top = 2 if selected else 1
	s.border_color = border
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
