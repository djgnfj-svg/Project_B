extends CanvasLayer
# 개발용 **모션 튜너** (F2) — 무기 모션·궤적 룩·무게·애니 fps를 **화면을 보면서** 조인다.
#
# 🔴 **F1 디버그 패널과 성격이 정반대다: 이것은 비모달이다.**
#   F1은 Backdrop(STOP)이 뒤 클릭을 막아 "열어 둔 채 휘두르기"가 원리적으로 불가능하다 — 값을 바꾸려면
#   닫고 → 치고 → 다시 열어야 해서 손맛 조율에 못 쓴다. 여기서는 패널 **밖** 클릭이 게임으로 그대로
#   통과하므로, 슬라이더를 만진 손 그대로 바로 휘둘러 볼 수 있다. 그것이 이 파일이 따로 있는 이유다.
#   · `Anchor`/`Dock` = mouse_filter IGNORE(2) → 화면을 덮지만 클릭을 안 먹는다 (rules §5 1번 함정)
#   · `Dialog`(PanelContainer) = 기본 STOP → **패널 위**만 먹는다(슬라이더를 끌다 공격이 나가지 않게)
#   · `GameState.ui_modal_open`을 **켜지 않는다** — 켜면 player가 멎어 도구가 자기 목적을 배반한다
#   · 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지
#
# 🔴 **판정 축은 일부러 없다 — `swing_arc`·`melee_range`는 여기서 못 바꾼다** (rules §3).
#   그 둘은 표시이자 **판정**이라, 로컬 리소스만 바꾸면 호스트는 자기 `.tres`로 판정해 그 순간
#   「보이는 곳 ≠ 맞는 곳」이 된다 — 이 프로젝트가 콘 텔레그래프에서 두 번 값을 치른 실패 형태다.
#   대신 **읽기 전용으로 보여준다**(왜 없는지가 화면에 남아야 다음 사람이 추가하지 않는다).
#   조이려면 `.tres`를 고쳐라 = 밸런스 변경(`docs/TUNING.md` §12).
#
# 🔴 **값은 메모리에만 쓴다 — `.tres`는 안 건드린다.** `ResourceSaver`를 부르지 않는다.
#   `GameState.equip_def()`가 돌려주는 것은 **캐시된 공유 인스턴스**라 필드를 바꾸면 그 프로세스 전체에
#   반영된다(그게 이 도구가 성립하는 원리다). 그래서 원본을 무기 id별로 스냅샷해 두고 「되돌리기」가
#   복원한다 — 스냅샷이 없으면 게임을 껐다 켜기 전엔 원래 손맛으로 못 돌아온다.
#
# ⚠ 갱신 대상은 **로컬 아바타 하나**다. 원격 아바타는 `peer_sync`가 자기 경로로 `set_weapon_visual`을
#   부르므로 내 조작이 그쪽 캐시를 다시 태우지 않는다(상대 **화면**은 애초에 안 바뀐다 — 표시 전용).
#
# ⚠ UI 씬 스크립트라 전역(GameState·EventBus·Net·CombatMath) 직접 접근 OK (rules §5, `-s` 대상 아님).
#   class_name 선언은 하지 않는다(§0).

const UiTheme := preload("res://src/ui/ui_theme.gd")
# 게이트 판정 단일 소스 — F1 패널과 **같은 조건**으로 열려야 "F1은 뜨는데 F2는 안 뜬다"가 안 생긴다.
const DebugBridgeScript := preload("res://src/core/debug_bridge.gd")

# 레이아웃 최소폭 (위치는 전부 컨테이너가 잡는다 — position/size 매직넘버 금지, rules §5)
const TITLE_W := 52.0
const VALUE_W := 50.0

# `hit_shake / HIT_SHAKE_REF ≤ HIT_WEIGHT_MAX(3.0)` → 4.5부터 saturation(그 위로는 셰이크만 커지고
# 카메라 킥·박힘이 안 따라온다 = 무게 단일 소스가 조용히 반쪽이 된다). 상한을 그 지점에 둔다.
const HIT_SHAKE_MAX := 4.5
# 스윙창 하한 — 이보다 짧으면 선딜·스윕·후딜 셋이 한두 프레임씩이라 모션이 눈에 안 남는다.
const SWING_TIME_MIN := 0.10
# 애니 fps 범위 (표시 전용)
const FPS_MIN := 1.0
const FPS_MAX := 24.0

# 조일 수 있는 축 — 🔴 **전부 표시·손맛 전용이다.** 판정 축을 이 배열에 추가하지 마라(파일 상단).
# ⚠ `swing_time`만은 "표시 전용"이 아니다: 판정 시점(`선딜+스윕`이 끝나는 순간)과 클라 자기 스로틀을
#   같이 옮긴다(rules §3). 그래서 상한을 직업 쿨다운 미만으로 **동적으로** 덮고(§3 미러 계약),
#   게스트일 때는 힌트에 경고를 띄운다(호스트는 원본 `.tres`로 판정하므로 갈라진다).
const FIELDS: Array = [
	{"key": "swing_time", "title": "스윙창", "lo": SWING_TIME_MIN, "hi": 0.6, "step": 0.01, "fmt": "%.2f s"},
	{"key": "swing_windup_ratio", "title": "선딜", "lo": 0.05, "hi": 0.9, "step": 0.01, "fmt": "%.2f"},
	{"key": "swing_strike_ratio", "title": "스윕", "lo": 0.05, "hi": 0.9, "step": 0.01, "fmt": "%.2f"},
	{"key": "swing_pull", "title": "당김", "lo": 0.0, "hi": 40.0, "step": 0.5, "fmt": "%.1f px"},
	{"key": "swing_lunge", "title": "내지르기", "lo": 0.0, "hi": 40.0, "step": 0.5, "fmt": "%.1f px"},
	{"key": "hit_shake", "title": "무게", "lo": 0.5, "hi": HIT_SHAKE_MAX, "step": 0.1, "fmt": "%.1f"},
]

const EASES: Array = [
	{"id": "smooth", "label": "균등", "tip": "균등한 큰 호 — 대검"},
	{"id": "accel", "label": "내리꽂", "tip": "천천히 들었다 확 내리꽂는다 — 도끼"},
	{"id": "decel", "label": "쏘아짐", "tip": "튀어나가 멎는다 — 찌르기"},
]

signal closed

@onready var _title: Label = %Title
@onready var _close_btn: Button = %CloseBtn
@onready var _body: VBoxContainer = %Body
@onready var _hint: Label = %HintLabel

var _enabled: bool = false
# 지금 그려져 있는 무기 id — 바뀌었을 때만 위젯을 다시 만든다.
# 🔴 매 변경마다 재생성하면 **드래그 중인 슬라이더가 파괴되어** 값이 한 칸에서 멎는다.
#   그래서 조작 중에는 라벨 텍스트만 갱신한다(`_sync`).
var _built_id: String = ""
# 무기 id → {필드: 원본값}. 「되돌리기」의 유일한 근거 — `.tres`를 안 건드리므로 이것 말고는 원본이 없다.
var _orig: Dictionary = {}
# "<frames 경로>:<애니>" → 원본 speed. 애니도 공유 리소스라 같은 이유로 스냅샷이 필요하다.
var _anim_orig: Dictionary = {}
var _anim_sel: String = ""

var _sliders: Dictionary = {}     # 필드 키 → HSlider
var _values: Dictionary = {}      # 필드 키 → 값 Label
var _derived: Label = null
var _judge: Label = null
var _ease_btns: Dictionary = {}   # 이징 id → Button
var _anim_btns: Dictionary = {}   # 애니 이름 → Button
var _fps_slider: HSlider = null
var _fps_value: Label = null


static func panel_enabled() -> bool:
	return DebugBridgeScript.panel_enabled()


func _ready() -> void:
	visible = false
	_enabled = panel_enabled()
	# 루트가 CanvasLayer라 Control 자식마다 테마를 건다(ui_theme 관용구 — HUD와 같은 자리).
	UiTheme.apply_to_children(self)
	_close_btn.pressed.connect(close)
	_hint.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	# 무기 교체(F1·인벤·제작)를 따라간다 — 위젯 재구성은 id가 바뀔 때만 일어난다.
	EventBus.inventory_changed.connect(_on_inventory_changed)


# --- 공개 API (HUD가 F2로 부른다) ---

func open() -> void:
	if not _enabled:
		return
	_rebuild()
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


# 🔴 F2는 HUD가 소비한다(F1과 같은 관용구) — 여기서 같이 먹으면 열자마자 닫힌다(rules §5).
# ⚠ 여기서는 **어떤 키도 삼키지 않는다.** 비모달이라 Esc·F·WASD가 전부 게임으로 가야 한다
#   (Esc를 먹으면 설정 창이 안 열리고, 이 패널은 F2로 여니 F2로 닫는 것이 규칙에 맞다).
#   닫는 것은 × 버튼과 F2뿐이다.


func _on_inventory_changed() -> void:
	if visible:
		_rebuild()


# --- 대상 리졸브 ---

# 로컬 아바타 — 씬 전환·재스폰마다 노드가 바뀌므로 매번 스캔한다(stage_hud와 같은 관용구).
# ⚠ 캐시하지 않는 것은 이 패널이 프레임마다 도는 경로가 아니기 때문이다(조작할 때만 부른다).
func _player() -> Node:
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n.get("is_local") == true and n.has_method("set_weapon_visual"):
			return n
	return null


func _equip() -> EquipDef:
	return GameState.equip_def(GameState.equipped_id(EquipDef.SLOT_WEAPON))


# 스윙창 상한 = 직업 쿨다운 미만 — 🔴 **§3 미러 계약**(`swing_time < attack_cooldown`)이 깨지면
#   원격 스윙 창-잠금 가드(`player.play_attack_fx`)가 정당한 연속 공격의 연출을 삼켜 상대 화면에서만
#   스윙이 사라진다(데미지는 정상이라 원인이 화면에 안 드러난다). haste는 양변에 같은 배율이 곱해져
#   부등식이 보존되므로 base끼리 비교하면 된다.
func _swing_time_max() -> float:
	var j := GameState.selected_job()
	if j == null:
		return 0.6
	return maxf(j.attack_cooldown - 0.01, SWING_TIME_MIN)


# --- 위젯 구성 (무기가 바뀔 때만) ---

func _rebuild() -> void:
	var e := _equip()
	var id := e.id if e != null else ""
	if id == _built_id and not _body.get_children().is_empty():
		_sync()
		return
	_built_id = id
	_clear(_body)
	_sliders.clear()
	_values.clear()
	_ease_btns.clear()
	_anim_btns.clear()
	_derived = null
	_judge = null
	_fps_slider = null
	_fps_value = null
	if e == null:
		_title.text = "모션 (F2)"
		_body.add_child(_note("무기를 착용해야 조일 수 있습니다 — F1에서 장착하세요"))
		_hint.text = "F2로 닫기"
		return
	_snapshot(e)
	_title.text = "모션 · %s" % (e.display_name if not e.display_name.is_empty() else e.id)
	# 🔴 판정 축은 **읽기 전용**으로만 보인다(파일 상단) — 왜 슬라이더가 없는지가 화면에 남아야 한다.
	_judge = _note("")
	_body.add_child(_judge)
	for f: Dictionary in FIELDS:
		_body.add_child(_slider_row(e, f))
	_body.add_child(_ease_row(e))
	_derived = _note("")
	_body.add_child(_derived)
	_body.add_child(_anim_row())
	_body.add_child(_fps_row())
	_body.add_child(_action_row())
	_sync()


func _slider_row(e: EquipDef, f: Dictionary) -> Control:
	var key: String = f["key"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var t := Label.new()
	t.text = f["title"]
	t.custom_minimum_size = Vector2(TITLE_W, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.theme_type_variation = &"InfoLabel"
	row.add_child(t)
	var s := HSlider.new()
	s.min_value = f["lo"]
	# 스윙창만 상한이 동적이다(직업 쿨다운 미만) — 그 위로는 슬라이더만 움직이고 결과가 안 따라온다.
	s.max_value = _swing_time_max() if key == "swing_time" else f["hi"]
	s.step = f["step"]
	s.value = clampf(float(e.get(key)), s.min_value, s.max_value)
	s.focus_mode = Control.FOCUS_NONE  # WASD·Esc가 슬라이더로 새지 않게(비모달이라 게임이 살아 있다)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(60, 0)
	s.value_changed.connect(_on_field_changed.bind(key))
	row.add_child(s)
	_sliders[key] = s
	var v := Label.new()
	v.custom_minimum_size = Vector2(VALUE_W, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.theme_type_variation = &"InfoLabel"
	row.add_child(v)
	_values[key] = v
	return row


func _ease_row(e: EquipDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 3)
	var t := Label.new()
	t.text = "이징"
	t.custom_minimum_size = Vector2(TITLE_W, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.theme_type_variation = &"InfoLabel"
	row.add_child(t)
	for opt: Dictionary in EASES:
		var b := _btn(opt["label"], 44.0, _on_ease_pressed.bind(String(opt["id"])))
		b.tooltip_text = opt["tip"]
		row.add_child(b)
		_ease_btns[String(opt["id"])] = b
	return row


func _anim_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 3)
	var t := Label.new()
	t.text = "애니"
	t.custom_minimum_size = Vector2(TITLE_W, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.theme_type_variation = &"InfoLabel"
	row.add_child(t)
	var names := _anim_names()
	if names.is_empty():
		var n := Label.new()
		n.text = "(스프라이트 없음)"
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.theme_type_variation = &"SmallLabel"
		row.add_child(n)
		return row
	if not names.has(_anim_sel):
		_anim_sel = names[0]
	for a: String in names:
		var b := _btn(a, 40.0, _on_anim_pressed.bind(a))
		b.tooltip_text = "이 애니의 재생 속도(fps)를 아래 슬라이더로 조인다"
		row.add_child(b)
		_anim_btns[a] = b
	return row


func _fps_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var t := Label.new()
	t.text = "fps"
	t.custom_minimum_size = Vector2(TITLE_W, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.theme_type_variation = &"InfoLabel"
	row.add_child(t)
	var s := HSlider.new()
	s.min_value = FPS_MIN
	s.max_value = FPS_MAX
	s.step = 0.5
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(60, 0)
	s.value_changed.connect(_on_fps_changed)
	row.add_child(s)
	_fps_slider = s
	var v := Label.new()
	v.custom_minimum_size = Vector2(VALUE_W, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.theme_type_variation = &"InfoLabel"
	row.add_child(v)
	_fps_value = v
	return row


func _action_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var r := _btn("되돌리기", 62.0, _on_revert)
	r.tooltip_text = "이 무기의 값을 .tres 원본으로 되돌린다 (애니 fps 포함)"
	row.add_child(r)
	var c := _btn(".tres 출력", 74.0, _on_dump)
	c.tooltip_text = "바뀐 줄만 콘솔에 찍고 클립보드에 넣는다 — 그 파일에 붙여넣으면 끝"
	row.add_child(c)
	return row


# --- 값 반영 ---

# 🔴 위젯을 다시 만들지 않는다 — 드래그 중이면 슬라이더가 파괴되어 값이 멎는다(위 `_built_id` 주석).
func _on_field_changed(v: float, key: String) -> void:
	var e := _equip()
	if e == null:
		return
	e.set(key, v)
	_push(e)
	_sync()


func _on_ease_pressed(id: String) -> void:
	var e := _equip()
	if e == null:
		return
	e.swing_ease = id
	_push(e)
	_sync()


# 🔴 로컬 아바타에 다시 태운다 — `set_weapon_visual` → `_apply_weapon_feel`이 EquipDef의 모션 필드를
#   **전부 멤버로 캐시**하므로, 리소스만 바꾸고 이걸 안 부르면 화면이 안 변한다(에러도 없다).
# ⚠ 진행 중인 스윙은 안 흔들린다 — `player`가 스윙 시작 시 구간 비율·창 길이를 **굳혀** 두기 때문이다
#   (rules §3 「굳힌 시간 축」). 바뀐 값은 다음 스윙부터 보인다.
func _push(e: EquipDef) -> void:
	var p := _player()
	if p != null:
		p.call("set_weapon_visual", e)


func _on_anim_pressed(a: String) -> void:
	_anim_sel = a
	_sync()


func _on_fps_changed(v: float) -> void:
	var f := _frames()
	if f == null or _anim_sel.is_empty() or not f.has_animation(_anim_sel):
		return
	_snapshot_anim(f, _anim_sel)
	f.set_animation_speed(_anim_sel, v)
	_sync()


# --- 표시 갱신 (위젯 재생성 없이 텍스트만) ---

func _sync() -> void:
	var e := _equip()
	if e == null:
		return
	for key: String in _values.keys():
		var lbl: Label = _values[key]
		var f := _field(key)
		lbl.text = String(f.get("fmt", "%.2f")) % float(e.get(key))
	for id: String in _ease_btns.keys():
		var b: Button = _ease_btns[id]
		b.disabled = (e.swing_ease == id)
	for a: String in _anim_btns.keys():
		var b2: Button = _anim_btns[a]
		b2.disabled = (a == _anim_sel)
	_sync_fps()
	_sync_judge(e)
	_sync_derived(e)
	_sync_hint()


func _sync_fps() -> void:
	if _fps_slider == null:
		return
	var f := _frames()
	if f == null or _anim_sel.is_empty() or not f.has_animation(_anim_sel):
		_fps_slider.editable = false
		_fps_value.text = "—"
		return
	_fps_slider.editable = true
	var cur := f.get_animation_speed(_anim_sel)
	if not is_equal_approx(_fps_slider.value, cur):
		_fps_slider.set_value_no_signal(clampf(cur, FPS_MIN, FPS_MAX))
	var n := f.get_frame_count(_anim_sel)
	_fps_value.text = "%.1f (%d장)" % [cur, n]


# 판정 축 읽기 전용 표시 — 🔴 여기에 슬라이더를 붙이지 마라(파일 상단).
func _sync_judge(e: EquipDef) -> void:
	if _judge == null:
		return
	var j := GameState.selected_job()
	var reach := e.melee_range if e.melee_range > 0.0 else (j.attack_range if j != null else 0.0)
	var half := CombatMath.melee_half_angle(e)
	var arc_txt := "전방위" if half >= CombatMath.MELEE_FULL_ARC - CombatMath.MELEE_FULL_ARC_EPS \
		else "±%.0f°" % rad_to_deg(half)
	_judge.text = "판정(잠김) 사거리 %.0f · 반각 %s · 타입 %s" % [reach, arc_txt, e.motion_type]


# 파생값 — 🔴 **`CombatMath`가 실제로 적용하는 값**을 되읽어 보여준다. 데이터가 상한을 넘으면 코드가
#   조용히 clamp하는데(rules §3 J-1), 그 "조용함"이 여기서는 `⚠ clamp`로 눈에 보인다.
func _sync_derived(e: EquipDef) -> void:
	if _derived == null:
		return
	var ph := CombatMath.motion_phases(e)
	var recover := 1.0 - ph.x - ph.y
	var hit_ms := e.swing_time * (ph.x + ph.y) * 1000.0
	var clamped := not (is_equal_approx(ph.x, e.swing_windup_ratio)
		and is_equal_approx(ph.y, e.swing_strike_ratio))
	var txt := "후딜 %.2f · 판정까지 %.0f ms · 무게 ×%.2f" % [
		recover, hit_ms, CombatMath.weapon_weight(e)]
	if clamped:
		txt += "  ⚠ clamp → 선딜 %.2f / 스윕 %.2f" % [ph.x, ph.y]
	if e.hit_shake > CombatMath.HIT_SHAKE_REF * CombatMath.HIT_WEIGHT_MAX:
		txt += "  ⚠ 무게 상한(킥·박힘 안 따라옴)"
	_derived.text = txt


# 🔴 게스트일 때 `swing_time`은 안전하지 않다 — 호스트는 **원본 `.tres`** 로 판정하므로 내가 로컬에서
#   창을 옮기면 판정 시점·클라 스로틀이 호스트 기대와 갈라져 「스윙은 보이는데 HP만 안 깎임」이 된다
#   (docs/TUNING.md §13 B-1·B-5와 증상이 같아 서로를 가린다). 혼자·호스트면 자기 판정이라 무관하다.
func _sync_hint() -> void:
	var solo_ok := Net.is_host()
	var base := "패널 밖을 클릭하면 그대로 휘둘러진다 · 값은 메모리만(.tres 안 바뀜) · F2 닫기"
	if solo_ok:
		_hint.text = base
	else:
		_hint.text = base + "\n🔴 게스트다 — 「스윙창」을 바꾸면 호스트는 원본으로 판정해 데미지가 어긋난다"


# --- 원본 스냅샷 / 되돌리기 ---

func _snapshot(e: EquipDef) -> void:
	if _orig.has(e.id):
		return
	var d := {}
	for f: Dictionary in FIELDS:
		d[f["key"]] = e.get(f["key"])
	d["swing_ease"] = e.swing_ease
	_orig[e.id] = d


func _snapshot_anim(f: SpriteFrames, anim: String) -> void:
	var k := _anim_key(f, anim)
	if not _anim_orig.has(k):
		_anim_orig[k] = f.get_animation_speed(anim)


func _on_revert() -> void:
	var e := _equip()
	if e == null or not _orig.has(e.id):
		return
	var d: Dictionary = _orig[e.id]
	for key: String in d.keys():
		e.set(key, d[key])
	for key: String in _sliders.keys():
		var s: HSlider = _sliders[key]
		s.set_value_no_signal(clampf(float(e.get(key)), s.min_value, s.max_value))
	var f := _frames()
	if f != null:
		for k: String in _anim_orig.keys():
			var parts := k.rsplit(":", true, 1)
			if parts.size() == 2 and parts[0] == _frames_key(f) and f.has_animation(parts[1]):
				f.set_animation_speed(parts[1], float(_anim_orig[k]))
	_push(e)
	_sync()


# --- .tres 출력 (바뀐 줄만) ---

# 🔴 **바뀐 줄만 찍는다** — `.tres`는 안 쓴 필드를 그냥 비워 두는 포맷이라, 전부 찍으면 원래 없던
#   줄까지 파일에 박혀 "기본값과 같은데 명시된" 항목이 늘어난다. 붙여넣을 것만 준다.
func _on_dump() -> void:
	var e := _equip()
	if e == null:
		return
	var lines: Array[String] = []
	var d: Dictionary = _orig.get(e.id, {})
	for f: Dictionary in FIELDS:
		var key: String = f["key"]
		var now := float(e.get(key))
		if not is_equal_approx(now, float(d.get(key, now))):
			lines.append("%s = %s" % [key, _num(now)])
	if e.swing_ease != String(d.get("swing_ease", e.swing_ease)):
		lines.append("swing_ease = \"%s\"" % e.swing_ease)
	var anim_lines := _anim_dump_lines()
	var head := "# data/equipment/%s.tres" % e.id
	var out := ""
	if lines.is_empty():
		out = head + "\n# (모션 변경 없음)"
	else:
		out = head + "\n" + "\n".join(lines)
	if not anim_lines.is_empty():
		out += "\n\n# 애니 speed — 그 직업의 *_frames.tres\n" + "\n".join(anim_lines)
	print("[MOTION]\n", out)
	DisplayServer.clipboard_set(out)
	_hint.text = "클립보드에 복사했다 — 콘솔에도 찍혔다\n" + out.replace("\n", " / ")


func _anim_dump_lines() -> Array[String]:
	var out: Array[String] = []
	var f := _frames()
	if f == null:
		return out
	for k: String in _anim_orig.keys():
		var parts := k.rsplit(":", true, 1)
		if parts.size() != 2 or parts[0] != _frames_key(f) or not f.has_animation(parts[1]):
			continue
		var now := f.get_animation_speed(parts[1])
		if not is_equal_approx(now, float(_anim_orig[k])):
			out.append("# %s: speed %s" % [parts[1], _num(now)])
	return out


# .tres는 float을 소수점 있는 형태로 쓴다(`38.0`) — 정수로 찍으면 붙여넣었을 때 타입이 흔들린다.
func _num(v: float) -> String:
	var s := "%.4f" % v
	while s.ends_with("0") and not s.ends_with(".0"):
		s = s.substr(0, s.length() - 1)
	return s


# --- 스프라이트 애니 ---

func _frames() -> SpriteFrames:
	var p := _player()
	if p == null:
		return null
	var spr := p.get_node_or_null("Sprite") as AnimatedSprite2D
	return spr.sprite_frames if spr != null else null


func _frames_key(f: SpriteFrames) -> String:
	return f.resource_path if not f.resource_path.is_empty() else str(f.get_instance_id())


func _anim_key(f: SpriteFrames, anim: String) -> String:
	return "%s:%s" % [_frames_key(f), anim]


# 🔴 **`roll`은 목록에서 뺀다 — `CombatMath.ROLL_TIME_S`와 암묵 미러다**(rules §3): 4프레임/speed 16 =
#   0.25s가 구르기 창과 맞물려 있어, 여기서 fps를 낮추면 애니가 창보다 길어져 `loop=false`인 클립이
#   마지막 프레임에서 얼어붙는다. 손맛이 아니라 계약이라 도구가 열어 두면 안 된다.
#   ⚠ 방향 변형(`roll_e`/`roll_s`/`roll_n`)도 같은 클립이라 접두사로 거른다.
func _anim_names() -> Array[String]:
	var out: Array[String] = []
	var f := _frames()
	if f == null:
		return out
	for n: StringName in f.get_animation_names():
		var s := String(n)
		if s.begins_with("roll"):
			continue
		out.append(s)
	return out


# --- 위젯 헬퍼 (레이아웃은 컨테이너 주도 — position/size 매직넘버 없음) ---

func _btn(text: String, min_w: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 0)
	b.theme_type_variation = &"SmallButton"
	b.clip_text = true
	b.pressed.connect(on_press)
	return b


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"SmallLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _field(key: String) -> Dictionary:
	for f: Dictionary in FIELDS:
		if String(f["key"]) == key:
			return f
	return {}


func _clear(container: Node) -> void:
	for c: Node in container.get_children():
		container.remove_child(c)  # 즉시 떼어낸다 — queue_free만 하면 같은 프레임 재생성분과 겹쳐 보인다
		c.queue_free()
