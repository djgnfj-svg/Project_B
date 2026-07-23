extends RefCounted
# 인벤/제작/창고 패널 공용 아이템 표현 헬퍼 — 아이콘·툴팁 텍스트·드래그 프리뷰를 한 곳에서 만든다.
# 세 패널이 같은 함수를 물어 표시가 통일된다(이름·부위·등급·스탯·설명 포맷 단일 소스).
# ⚠ 스탯 계산은 여기서 하지 않는다(단일 소스 = CombatMath, rules §3) — 부르는 쪽이 계산해 넘긴다.
# class_name 선언 안 함(§0) — 패널이 const preload로 문다. 타입 EquipDef/MaterialDef는 core class_name(인게임/임포트 해석 OK).

const RARITY_NAMES := {0: "일반", 1: "희귀", 2: "핵심"}
const RARITY_COLORS := {
	0: Color(0.85, 0.85, 0.85, 1.0),   # 흰
	1: Color(0.45, 0.65, 1.0, 1.0),    # 파랑
	2: Color(1.0, 0.82, 0.28, 1.0),    # 금
}
const GOLD_COLOR := Color(1.0, 0.85, 0.3, 1.0)


# 아이콘 TextureRect — 도형 금지(§0)라 스프라이트만. tex가 null이면 빈 칸 유지(안전).
static func make_icon(tex: Texture2D, size: float = 16.0) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 픽셀아트 크리스프
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 — 클릭 안 먹음
	if tex != null:
		t.texture = tex
	return t


static func rarity_name(rarity: int) -> String:
	return str(RARITY_NAMES.get(rarity, "일반"))


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS[0])


# 장비 툴팁 — 이름·부위·강화단계·현재 스탯·설명. atk/hp는 부르는 쪽이 CombatMath로 계산해 넘긴다(§3).
static func equip_tooltip(equip: EquipDef, level: int, atk: int, hp: int) -> String:
	var slot_txt := "방어구" if equip.slot() == EquipDef.SLOT_ARMOR else "무기"
	var lines: Array[String] = []
	lines.append("%s  [%s]" % [equip.display_name, slot_txt])
	lines.append("강화 Lv.%d / %d" % [level, equip.max_level])
	lines.append("공격 %d · HP %d" % [atk, hp])
	if not equip.description.is_empty():
		lines.append("")
		lines.append(equip.description)
	return "\n".join(lines)


# 재료 툴팁 — 이름·등급·보유수·설명.
static func material_tooltip(mdef: MaterialDef, qty: int) -> String:
	var lines: Array[String] = []
	lines.append("%s  (%s)" % [mdef.display_name, rarity_name(mdef.rarity)])
	lines.append("보유 %d개" % qty)
	if not mdef.description.is_empty():
		lines.append("")
		lines.append(mdef.description)
	return "\n".join(lines)


# 드래그 프리뷰 — 커서를 따라다니는 반투명 아이콘. set_drag_preview(control)에 넘긴다.
# 커서 중앙에 오도록 음수 오프셋 Control로 감싼다.
static func make_drag_preview(tex: Texture2D, size: float = 20.0) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := make_icon(tex, size)
	icon.position = Vector2(-size * 0.5, -size * 0.5)
	icon.modulate = Color(1, 1, 1, 0.85)
	root.add_child(icon)
	return root
