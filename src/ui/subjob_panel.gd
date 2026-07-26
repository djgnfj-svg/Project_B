extends CanvasLayer
# 하위 직업 훈련소 패널 (조립 축 GDD v2.0) — 마을 훈련소가 F로 여는 오버레이.
# **장착 슬롯 = 메인 1 + 서브 2**를 직접 조작한다. 하위 직업은 "보유하면 켜지는 것"이 아니라
# "3칸에 낀 것만 켜지는 것"이고(GDD §5), 특성은 **낀 자리에 따라 얼굴이 다르다**
# (메인 자리 = 메인 특성 / 서브 자리 = 서브 특성). 그래서 이 패널의 본체는 "어디에 끼울까"다.
#
# 🖼 **아이콘 중심 재설계 (2026-07-26)** — 이전 판은 보유 행마다 텍스트 4줄을 쏟아 5종만 보유해도
#   20줄이었다. 그 내용은 **이미 `_sub_tooltip`에 통째로 있었으므로** 행 본문을 지워도 정보가
#   사라지지 않는다(hover하면 그대로 나온다). 구성 = 장착 3칸(각 칸이 드롭 대상) · 총 5스탯 한 줄 +
#   켜진 특성 · 보유 아이콘 그리드(잠긴 갈래는 흐린 고스트 셀).
# 🔁 **인프라 재사용(복사 금지)** — 인벤/창고가 쓰는 `slot_cell`(아이콘·뱃지·테두리·클릭·드래그) +
#   `slot_grid`(드롭 대상 규약 accepts/receive_drop → dropped) + `ui_theme` 그대로. ⚠ slot_cell은
#   드롭을 **부모에게 위임**하므로 장착 칸 = "slot_grid를 문 1열 컨테이너"다(셀 위·이름 라벨 위 어디든).
# 조작(사용자 확정): **드래그** = 보유 셀 → 장착 칸. **클릭 폴백** = 보유 셀이면 빈 서브 칸에 장착,
#   낀 서브 칸이면 비우기. 🔒 메인 칸은 클릭으로 못 비운다(항상 계열 갈래 하나가 메인) — 교체는 드래그로.
#   거부 조건은 UI에 미러하되 **실제 거부는 여전히 GameState가 한다**.
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
const SlotCell := preload("res://src/ui/slot_cell.gd")
const SlotGrid := preload("res://src/ui/slot_grid.gd")

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
# 증가율 계열은 부호를 붙여 "더해지는 값"임을 드러낸다(치명/피흡은 절대 확률이라 안 붙인다).
const STAT_SIGNED := ["haste", "move"]

const MAIN_SLOT := -1  # 슬롯 인덱스 규약: -1 = 메인 칸, 0.. = 서브 칸 (GameState.sub_slot_id의 인덱스)
const NO_SLOT := -99   # 어느 칸에도 안 낀 상태 (_slot_of의 반환)

const MAIN_CELL := 44.0   # 메인 칸은 더 크게 — 자리의 무게(5스탯 100% + 메인 특성)를 크기로 말한다
const SUB_CELL := 36.0
const OWNED_MIN_CELLS := 9  # 보유 그리드 최소 칸(빈 칸 패딩) — 한 줄 그리드 형태 유지 (인벤 미러)
const ZONE_OWNED := "owned"  # slot_grid.accepts가 보는 구역 이름 (.tscn의 OwnedGrid.zone과 미러)

signal closed

@onready var _close_btn: Button = %CloseBtn
@onready var _slot_row: HBoxContainer = %SlotRow
@onready var _stat_label: Label = %StatLabel
@onready var _trait_label: Label = %TraitLabel
@onready var _notice_label: Label = %NoticeLabel
@onready var _owned_grid: GridContainer = %OwnedGrid
@onready var _hint_label: Label = %HintLabel

# 열린 프레임에 온 interact(F)가 곧바로 close로 튀는 걸 막는 1프레임 가드
# (훈련소가 F로 open()을 부르고, 같은 F가 아래 닫기 핸들러에 잡히는 이중 처리 방지 — craft_panel 미러)
var _ignore_toggle: bool = false

# 다음 그리기 1회에만 뜨는 안내(거부 사유). 버튼을 지운 대신 "왜 안 됐는지"를 여기로 말한다.
var _pending_notice: String = ""


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (인벤/제작/창고와 통일)
	_close_btn.pressed.connect(close)
	_stat_label.add_theme_color_override(&"font_color", UiTheme.TEXT)
	_trait_label.add_theme_color_override(&"font_color", UiTheme.ACCENT)
	_notice_label.add_theme_color_override(&"font_color", UiTheme.GOLD)
	_hint_label.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	# 보유 그리드에 놓기 = 장착 해제(칸에서 빼내기). slot_grid가 zone 비교로 자기 구역 드롭만 거른다.
	_owned_grid.dropped.connect(_on_dropped_to_owned)
	# 레벨업·해금·장착 변동 → 열려 있는 동안 즉시 다시 그린다.
	EventBus.growth_changed.connect(_on_growth_changed)
	EventBus.exp_changed.connect(_on_exp_changed)


# --- 공개 API (훈련소가 부른다) ---

func open() -> void:
	_ignore_toggle = true
	call_deferred("_clear_ignore_toggle")  # 같은 프레임 F 소진 방지 (프레임 끝에 해제)
	_pending_notice = ""
	_refresh()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


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
	_refresh_owned()
	_hint_label.text = "끌어다 칸에 놓기 · 아이콘 클릭 = 빈 서브 칸 장착 · 낀 서브 칸 클릭 = 비우기   |   메인 100%%, 서브 각 %d%%" % roundi(
		CombatMath.SUB_JOB_WEIGHT * 100.0)


# 안내 한 줄 — 판 도중 잠금이 최우선(다른 모든 거부의 원인이라 그것만 말하면 된다),
# 그 외엔 직전 조작의 거부 사유를 1회 띄운다. 판 도중엔 GameState가 교체를 거부하는데(GDD §5 마을 전용)
# 아무 일도 안 일어나면 "왜 안 되지"가 안 읽히므로 사유를 정직하게 비춘다.
func _refresh_notice() -> void:
	var msg := _pending_notice
	_pending_notice = ""
	if GameState.in_chapter():
		msg = "판 도중에는 장착을 바꿀 수 없습니다 — 마을에서만 교체할 수 있습니다"
	_notice_label.text = msg
	_notice_label.visible = not msg.is_empty()


func _notify(msg: String) -> void:
	_pending_notice = msg
	_refresh()


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


# slot_grid가 보는 구역 이름. 칸 컨테이너 자신의 zone은 비워 둔다(빈 zone ≠ 어떤 payload zone이라
# 보유·다른 칸에서 온 것을 전부 받는다) — 셀 payload에만 이 값을 실어 "어디서 왔나"를 남긴다.
func _slot_zone(index: int) -> String:
	return "slot:%d" % index


# 장착 칸 하나 = [슬롯 셀] + [이름 한 줄]. 컨테이너에 slot_grid를 물려 **드롭 대상**으로 만든다.
func _make_slot_card(index: int) -> Control:
	var is_main := index == MAIN_SLOT
	var d := _slot_def(index)
	var cell_px := MAIN_CELL if is_main else SUB_CELL

	var card: GridContainer = SlotGrid.new()  # zone은 비워 둔다 → 어디서 온 payload든 받는다
	card.columns = 1
	card.mouse_filter = Control.MOUSE_FILTER_PASS  # 셀 밖 여백에 놔도 드롭이 성립하게
	card.add_theme_constant_override(&"v_separation", 1)
	card.dropped.connect(_on_dropped_to_slot.bind(index))

	var cell: PanelContainer = SlotCell.new()
	cell.custom_minimum_size = Vector2(cell_px, cell_px)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.set_icon_stretch(TextureRect.STRETCH_KEEP_CENTERED)  # 🔴 정수배(1배)만 — 픽셀아트 뭉개짐 방지
	cell.activated.connect(_on_slot_activated)
	card.add_child(cell)

	# 셀 아래 이름 한 줄. 크기 9 = Galmuri9 설계 크기(픽셀 퍼펙트), 마우스 IGNORE = 셀 툴팁·카드 드롭 통과.
	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override(&"font_size", 9)
	caption.add_theme_constant_override(&"line_spacing", 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.clip_text = true  # 🔴 긴 이름이 카드를 밀어 Dialog가 640 뷰포트를 넘는 것을 막는다
	caption.custom_minimum_size = Vector2(cell_px + 12.0, 0)
	card.add_child(caption)

	if d == null:
		cell.set_empty("")
		cell.tooltip_text = _empty_slot_tooltip(index)
		caption.text = _slot_title(index)
		caption.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
		return card

	var sid := GameState.main_sub_job_id if is_main else GameState.sub_slot_id(index)
	cell.fill(
		_payload(sid, d, _slot_zone(index), index),
		d.icon, 1, _badge(d, GameState.sub_job_level(sid)),
		UiTheme.ACCENT if is_main else UiTheme.EQUIPPED_GLOW,
		not GameState.in_chapter(), false, _sub_tooltip(sid, d))
	caption.text = d.display_name
	caption.add_theme_color_override(&"font_color", UiTheme.ACCENT if is_main else UiTheme.TEXT)
	return card


# --- 총 스탯 + 켜진 특성 ---

# 현재 총 5스탯 한 줄 (낀 3칸: 메인 온전 + 서브 가중 — 계산은 CombatMath, 여기선 포맷만)
# 🔴 순회는 CombatMath.LEVEL_STAT_KEYS로 한다(사본 배열 금지 — 스탯이 늘면 라벨만 추가하면 된다).
func _refresh_stats() -> void:
	var s := GameState.current_level_stats()
	var parts: Array[String] = []
	for key: String in CombatMath.LEVEL_STAT_KEYS:
		var v := float(s.get(key, 0.0))
		if key == "crit_dmg":
			# 치명피해만 "총 배율"로 보여준다(기본 150% 포함) — 합산은 CombatMath.crit_mult 단일 소스.
			parts.append("%s %d%%" % [_stat_name(key), roundi(CombatMath.crit_mult(v) * 100.0)])
			continue
		var sign_s := "+" if key in STAT_SIGNED else ""
		parts.append("%s %s%.1f%s" % [_stat_name(key), sign_s, v * 100.0, _stat_unit(key)])
	_stat_label.text = " · ".join(parts)

	var traits := _active_trait_parts()
	_trait_label.visible = not traits.is_empty()
	if _trait_label.visible:
		_trait_label.text = "특성 · " + "  ·  ".join(traits)


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


# --- 보유 아이콘 그리드 ---

func _refresh_owned() -> void:
	_clear(_owned_grid)
	var count := 0
	for sid: String in GameState.all_owned_sub_jobs():  # 계열 보유 + 공유 보유
		var d := GameState.sub_job_def(sid)
		if d == null:
			continue
		_owned_grid.add_child(_make_owned_cell(sid, d))
		count += 1
	# 아직 안 열린 계열 갈래 — "저걸 열면 뭐가 생기나"가 해금 동기다(GDD §6 레벨업 = 콘텐츠 해금).
	# ⚠ 공유 하위 직업의 미보유분은 안 띄운다 — 해금 조건이 계열 체인 밖(콘텐츠 보상)이라
	#   이 패널이 조건을 정확히 말할 수 없다. 틀린 안내를 적느니 안 적는다.
	for sid: String in GameState.sub_jobs_of_series(GameState.selected_job_id):
		if GameState.has_sub_job(sid):
			continue
		var d := GameState.sub_job_def(sid)
		if d == null:
			continue
		_owned_grid.add_child(_make_locked_cell(d))
		count += 1
	# 빈 칸 패딩 — 그리드 형태 유지 (인벤/창고와 같은 관례)
	var target := maxi(OWNED_MIN_CELLS, ceili(float(count) / float(_owned_grid.columns)) * _owned_grid.columns)
	for _i in range(target - count):
		var empty: PanelContainer = SlotCell.new()
		empty.set_empty("")
		_owned_grid.add_child(empty)


func _make_owned_cell(sid: String, d: SubJobDef) -> Control:
	var cell: PanelContainer = SlotCell.new()
	cell.set_icon_stretch(TextureRect.STRETCH_KEEP_CENTERED)  # 정수배(1배)만
	cell.activated.connect(_on_owned_activated)
	var slot := _slot_of(sid)
	cell.fill(
		_payload(sid, d, ZONE_OWNED, slot),
		d.icon, 1, _badge(d, GameState.sub_job_level(sid)),
		UiTheme.GOLD if d.is_shared() else UiTheme.ACCENT,  # 공유 갈래(서브 전용)는 금빛으로 구분
		not GameState.in_chapter(), slot != NO_SLOT, _sub_tooltip(sid, d))
	return cell


# 잠긴 갈래 — 같은 그리드에 흐린 고스트 셀로 둔다(드래그·클릭 불가: payload가 비어 있으면
# slot_cell이 activated도 _get_drag_data도 내지 않는다). 아이콘이 아직 없으면 "잠김" 글자로 폴백.
func _make_locked_cell(d: SubJobDef) -> Control:
	var cell: PanelContainer = SlotCell.new()
	cell.set_icon_stretch(TextureRect.STRETCH_KEEP_CENTERED)
	cell.set_empty("잠김", d.icon)
	cell.tooltip_text = _locked_tooltip(d)
	return cell


# 셀 payload — 드래그 데이터이자 클릭 페이로드. "zone"은 slot_grid.accepts가, "slot"은
# 어느 칸에서 나왔는지(보유 셀은 지금 낀 칸)를 말한다. 형식은 인벤/창고 payload와 통일.
func _payload(sid: String, d: SubJobDef, zone: String, slot: int) -> Dictionary:
	return {"kind": "subjob", "id": sid, "tex": d.icon, "zone": zone, "slot": slot}


# 셀 뱃지 — 레벨. ⚠ 아이콘 미배선 방어: `SubJobDef.icon`이 비면 이름 두 글자로 대신해 셀을
#   식별할 수 있게 한다(레벨은 툴팁에 그대로 있다). 현재 5종은 전부 배선돼 있어 평소엔 안 탄다 —
#   새 하위 직업 .tres가 아이콘 없이 추가돼도 빈 칸으로 보이지 않게 하는 폴백이다.
func _badge(d: SubJobDef, level: int) -> String:
	if d.icon == null:
		return d.display_name.substr(0, 2)
	return "Lv%d" % level


# 이 하위 직업이 지금 낀 칸 — MAIN_SLOT(-1) / 서브 인덱스(0..) / 미장착(-99).
func _slot_of(sid: String) -> int:
	if sid == GameState.main_sub_job_id and GameState.main_sub_job() != null:
		return MAIN_SLOT
	for i: int in range(GameState.SUB_SLOT_COUNT):
		if _slot_def(i) != null and GameState.sub_slot_id(i) == sid:
			return i
	return NO_SLOT


# --- 조작 (드래그 + 클릭 폴백) ---

# 장착 칸에 드롭 — 보유 그리드에서든 다른 칸에서든 같은 경로.
func _on_dropped_to_slot(_zone: String, payload: Dictionary, index: int) -> void:
	if str(payload.get("kind", "")) != "subjob":
		return
	_apply_slot(index, str(payload.get("id", "")))


# 보유 그리드에 드롭 = 그 칸을 비운다(끌어내기). 메인은 비울 수 없다.
func _on_dropped_to_owned(_zone: String, payload: Dictionary) -> void:
	if str(payload.get("kind", "")) != "subjob":
		return
	var from := int(payload.get("slot", NO_SLOT))
	if from == MAIN_SLOT:
		_notify("메인 칸은 비울 수 없습니다 — 다른 갈래를 끌어다 놓으면 교체됩니다")
	elif from >= 0:
		_apply_slot(from, "")


# 보유 셀 클릭 = 빈 서브 칸에 장착(클릭 폴백). 빈 칸이 없으면 **상태를 바꾸지 않고** 안내만 한다 —
# 임의의 칸을 밀어내면 사용자가 의도하지 않은 조립이 조용히 바뀐다.
func _on_owned_activated(payload: Dictionary) -> void:
	if str(payload.get("kind", "")) != "subjob":
		return
	if int(payload.get("slot", NO_SLOT)) != NO_SLOT:
		_notify("이미 장착 중입니다 — 낀 칸을 클릭하면 비웁니다")
		return
	for i: int in range(GameState.SUB_SLOT_COUNT):
		if _slot_def(i) == null:
			_apply_slot(i, str(payload.get("id", "")))
			return
	_notify("빈 칸이 없습니다 — 칸을 비우거나 끌어다 놓으세요")


# 장착 칸 클릭 = 비우기(서브만). 🔒 메인은 항상 계열 갈래 하나가 차 있어야 하므로 사유만 말한다.
func _on_slot_activated(payload: Dictionary) -> void:
	var index := int(payload.get("slot", NO_SLOT))
	if index == MAIN_SLOT:
		_notify("메인 칸은 비울 수 없습니다 — 다른 갈래를 끌어다 놓으면 교체됩니다")
		return
	if index < 0:
		return
	_apply_slot(index, "")


# 🔴 쓰기는 GameState 두 함수뿐 — 실패(판 도중·미보유·타 계열·공유의 메인)는 거기서 거부된다.
#   여기서 상태를 직접 바꾸지 않는다. 성공하면 growth_changed로 자동 갱신(+ PeerSync 재공지).
#   거부 조건은 UI에 **미러**할 뿐이다(눌렀는데 아무 일도 없는 것이 제일 나쁘다).
func _apply_slot(index: int, sid: String) -> void:
	if GameState.in_chapter():
		_refresh()  # 안내는 _refresh_notice의 판 도중 문구가 대신 말한다
		return
	if index == MAIN_SLOT:
		var d := GameState.sub_job_def(sid)
		if d != null and d.is_shared():
			_notify("공유 갈래는 서브 칸 전용입니다 — 메인은 이 직업 계열의 갈래만 낄 수 있습니다")
			return
		if not GameState.set_main_sub_job(sid):
			_notify("메인으로 지정할 수 없습니다 — 이 계열의 보유 갈래만 가능합니다")
			return
	else:
		if not sid.is_empty() and sid == GameState.main_sub_job_id:
			_notify("메인으로 낀 것은 서브 칸에 함께 넣을 수 없습니다")
			return
		if not GameState.set_sub_slot(index, sid):
			_notify("이 칸에 넣을 수 없습니다 — 보유한 갈래만 장착됩니다")
			return
	_commit_save()
	_refresh()  # 변화 없는 성공(같은 칸에 같은 것)은 growth_changed가 안 오므로 여기서 한 번


# --- 텍스트 (본문에서 걷어낸 설명은 전부 hover 툴팁으로) ---

# 5스탯 딕셔너리 → "치명 +4.0%p · 공속 +5.0%" 조각들(0은 생략) — 레벨당 성장·현재 기여 공용 포맷.
# 🔴 순회는 CombatMath.LEVEL_STAT_KEYS로 한다(스탯이 늘면 여기 라벨만 추가 — 사본 배열을 만들면 갈라진다).
func _stat_parts(stats: Dictionary) -> Array[String]:
	var parts: Array[String] = []
	for key: String in CombatMath.LEVEL_STAT_KEYS:
		var v := float(stats.get(key, 0.0))
		if is_zero_approx(v):
			continue
		parts.append("%s +%.1f%s" % [_stat_name(key), v * 100.0, _stat_unit(key)])
	return parts


# 레벨당 성장 요약 — 0인 스탯은 빠져서 그 하위 직업의 성격이 한눈에 보인다.
func _growth_parts(d: SubJobDef) -> Array[String]:
	var steps := {}
	for key: String in CombatMath.LEVEL_STAT_KEYS:
		steps[key] = d.step(key)
	return _stat_parts(steps)


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


# "이 자리에 끼우면 이렇게 된다" 한 조각. 공유 하위 직업의 메인 자리는 **낄 수 없음**을
# 그대로 말한다(GDD §5 — 메인은 항상 계열 갈래).
func _face_text(d: SubJobDef, as_main: bool) -> String:
	if as_main and d.is_shared():
		return "메인 불가 (공유 갈래는 서브 전용)"
	var line := _trait_line(d, as_main)
	return line if not line.is_empty() else "특성 없음"


func _prev_in_series(d: SubJobDef) -> SubJobDef:
	for sid: String in GameState.sub_jobs_of_series(d.series_id):
		var other := GameState.sub_job_def(sid)
		if other != null and other.order == d.order - 1:
			return other
	return null


# 셀 hover 툴팁 — 이름·레벨·현재 자리·현재 기여·레벨당 성장·두 얼굴·설명·조작 안내.
# 🔴 본문에서 걷어낸 텍스트가 전부 여기로 모인다(같은 내용이 원래부터 여기 있었다).
# 🔴 기여도는 직접 곱하지 않는다: CombatMath.level_stats에 **그 하위 직업 하나만** 넘겨
#   메인 가중(1.0)/서브 가중(SUB_JOB_WEIGHT)을 단일 소스가 적용하게 한다(§3 — 여기서 곱하면 갈라진다).
func _sub_tooltip(sid: String, d: SubJobDef) -> String:
	var lines: Array[String] = []
	var level := GameState.sub_job_level(sid)
	var slot := _slot_of(sid)
	lines.append("%s  Lv.%d / %d" % [d.display_name, level, d.max_level])
	if slot == MAIN_SLOT:
		lines.append("메인 — 5스탯 100%% 적용 · %s" % _exp_text())
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
		var parts := _stat_parts(CombatMath.level_stats(GameState.main_sub_job_id, one_level, one_def))
		lines.append("현재 기여 — " + (" · ".join(parts) if not parts.is_empty() else "없음"))
	var growth := _growth_parts(d)
	if not growth.is_empty():
		lines.append("레벨마다  " + " · ".join(growth))
	lines.append("메인 자리 — " + _face_text(d, true))
	lines.append("서브 자리 — " + _face_text(d, false))
	if not d.description.is_empty():
		lines.append("")
		lines.append(d.description)
	lines.append("")
	lines.append("(끌어다 칸에 놓기 · 클릭: 빈 서브 칸 장착)" if slot == NO_SLOT else "(끌어다 칸을 바꾸기)")
	return "\n".join(lines)


# 빈 칸 툴팁 — 이 칸이 무엇을 받는지. 메인 칸은 계열 제한을 여기서만 말한다(본문에서 걷어낸 문장).
func _empty_slot_tooltip(index: int) -> String:
	if index == MAIN_SLOT:
		# ⚠ 여기엔 % 포맷을 적용하지 않으므로 백분율 기호는 한 개다(%%로 적으면 그대로 두 개가 보인다).
		return "메인 칸 — 5스탯 100% 적용 + 메인 특성\n이 직업 계열의 갈래만 낄 수 있습니다(공유 갈래는 서브 전용)\n\n아래 아이콘을 끌어다 놓으세요"
	return "%s 칸 — 5스탯 %d%% 합산 + 서브 특성\n\n아래 아이콘을 끌어다 놓거나, 아이콘을 클릭하면 빈 칸에 들어갑니다" % [
		_slot_title(index), roundi(CombatMath.SUB_JOB_WEIGHT * 100.0)]


# 잠김 툴팁 — 해금 조건 = 직전(order-1) 하위 직업이 **메인일 때** unlocks_next_at 도달 (GameState 미러)
func _locked_tooltip(d: SubJobDef) -> String:
	var lines: Array[String] = []
	lines.append("%s  (잠김)" % d.display_name)
	var prev := _prev_in_series(d)
	if prev != null:
		lines.append("%s를 메인으로 Lv.%d 달성 시 해금" % [prev.display_name, prev.unlocks_next_at])
	lines.append("메인 자리 — " + _face_text(d, true))
	lines.append("서브 자리 — " + _face_text(d, false))
	if not d.description.is_empty():
		lines.append("")
		lines.append(d.description)
	return "\n".join(lines)


# 메인 하위 직업의 EXP 진행 — 메인만 성장 페이싱의 기준점이다(HUD 표기의 패널판).
func _exp_text() -> String:
	var p := GameState.main_exp_progress()
	var need := int(p.get("need", 0))
	if need <= 0:
		return "EXP MAX"
	return "EXP %d / %d" % [int(p.get("cur", 0)), need]


func _stat_name(key: String) -> String:
	return str(STAT_LABEL.get(key, key))


func _stat_unit(key: String) -> String:
	return str(STAT_UNIT.get(key, "%"))


# --- 헬퍼 ---

func _clear(container: Node) -> void:
	for c: Node in container.get_children():
		container.remove_child(c)  # 즉시 떼어낸다 — queue_free만 하면 같은 프레임 재생성분과 겹쳐 보인다
		c.queue_free()


func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근(craft_panel 미러).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
