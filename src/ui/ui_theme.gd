extends RefCounted
# 공용 픽셀 UI 테마 — 인벤/제작/창고 패널이 루트 Control에 걸어 비주얼을 통일한다.
# (rules §0: 배경·구분선·버튼 같은 순수 UI chrome는 도형/스타일박스 허용 — 게임 오브젝트가 아님.)
# 코드로 Theme를 조립해 한 번 캐시한다 — 손으로 쓴 .tres 포맷 오류 위험을 피하고, 세 패널이 같은 함수를 문다.
# 툴팁(TooltipPanel/TooltipLabel)도 함께 테마 → 아이템 상세 툴팁이 통일된 룩으로 뜬다.
# ⚠ 폰트/폰트 크기는 건드리지 않는다(프로젝트 기본 픽셀 폰트 Galmuri9 상속 유지) — 640×360 레이아웃 안정.
# class_name 선언 안 함(§0) — 패널이 const preload로 문다.

static var _cached: Theme = null

const PANEL_BG := Color(0.10, 0.10, 0.13, 0.97)
const PANEL_BORDER := Color(0.42, 0.36, 0.28, 1.0)  # 따뜻한 갈색 테두리 (픽셀 목재 느낌)
const BTN_NORMAL := Color(0.20, 0.19, 0.24, 1.0)
const BTN_HOVER := Color(0.28, 0.26, 0.32, 1.0)
const BTN_PRESSED := Color(0.15, 0.14, 0.18, 1.0)
const BTN_DISABLED := Color(0.14, 0.14, 0.16, 0.7)
const BTN_BORDER := Color(0.36, 0.32, 0.26, 1.0)
const TOOLTIP_BG := Color(0.06, 0.06, 0.08, 0.98)
const TEXT := Color(0.92, 0.90, 0.85, 1.0)
const TEXT_DIM := Color(0.68, 0.66, 0.62, 1.0)


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()

	# --- PanelContainer 배경 (패널 다이얼로그 프레임) ---
	t.set_stylebox("panel", "PanelContainer", _panel_box(PANEL_BG, PANEL_BORDER, 2, 10))

	# --- Button (제작/강화/장착/보관/꺼내기 버튼 통일) ---
	t.set_stylebox("normal", "Button", _btn_box(BTN_NORMAL))
	t.set_stylebox("hover", "Button", _btn_box(BTN_HOVER))
	t.set_stylebox("pressed", "Button", _btn_box(BTN_PRESSED))
	t.set_stylebox("disabled", "Button", _btn_box(BTN_DISABLED))
	t.set_stylebox("focus", "Button", _empty_box())  # 포커스 외곽선 제거 (마우스 UI)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1, 1))
	t.set_color("font_disabled_color", "Button", TEXT_DIM)

	# --- Label 기본 글자색 ---
	t.set_color("font_color", "Label", TEXT)

	# --- 툴팁 (아이템 상세) — 기본 hover 툴팁을 같은 룩으로 ---
	t.set_stylebox("panel", "TooltipPanel", _panel_box(TOOLTIP_BG, PANEL_BORDER, 1, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	_cached = t
	return t


static func _panel_box(bg: Color, border: Color, border_w: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border_w)
	s.border_color = border
	s.set_corner_radius_all(4)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


static func _btn_box(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = BTN_BORDER
	s.set_corner_radius_all(3)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


static func _empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()
