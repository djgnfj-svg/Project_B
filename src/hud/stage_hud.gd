extends CanvasLayer
# 인게임 공용 HUD — 화면에는 **다섯 가지만** 남긴다(사용자 확정 2026-08-02: *"ui 줄이기 … 글자를 줄이고
# 숫자 위주로"*): 내 HP 바 · 구르기 쿨 바 · 파트너 HP 바 · 스킬 쿨 슬롯 · 골드 숫자 + 화면 맨 아래 EXP 띠.
# 마을·스테이지가 인스턴스로 문다 (rules §2 src/hud). HP는 php 확정만 반영 (§3 — 로컬 선적용 금지).
#
# 🔴 **방 코드·핑·경로·fps·진행도·초대 복사·레벨 표기는 Esc 메뉴(`settings_panel`)로 옮겼다.**
#   rules §5가 "렉이 있다" 신고를 가르는 유일한 도구로 지정한 **핑·경로·fps 세 값은 없애지 않았다** —
#   화면에서만 뺐고 Esc 한 번이면 읽힌다. 표기 문자열은 이제 그 패널이 **단일 소스**로 만든다(여기에
#   사본을 두지 마라 — 두 곳이 되면 다음 튜닝에서 갈라진다).
# 🔴 Esc는 **여는 쪽만** 여기서 소비한다(rules §5 "토글 키는 한 곳에서만"). 닫는 쪽은 각 패널이
#   자기 `_unhandled_input`에서 소비하고, 패널이 트리에서 HUD보다 **뒤**에 있어(자식 또는 뒤 형제)
#   먼저 입력을 받는다 = 열려 있으면 HUD까지 안 온다.

const TOAST_QUEUE_MAX := 3  # 동시 발생분 대기 상한 (넘치면 우선순위가 가장 낮은 것부터 버린다)
# 🔴 **토스트가 두 등급이다** (사용자 신고 2026-08-02: *"너무 뜨는게 많아서 내가 좋은거 먹은지를 모르겠다"*).
#   ⑴ 획득(장비·도면·희귀+ 재료) = 아이콘 + 짧은 이름 + 등급색, 길게·크게·**대기열 앞으로**.
#   ⑵ 성장(레벨업·해금) = 아이콘 없이 작게·짧게. 킬마다 올 수 있는 소식이라 획득을 덮으면 안 된다.
#   ⚠ 등급 0(흔한 재료)은 **아예 안 띄운다** — 드랍 팝·픽업음·인벤이 이미 말해 준다.
const TOAST_TIME_ITEM := 2.6    # 획득 1건 표시 시간 (연출값)
const TOAST_TIME_GROWTH := 1.4  # 레벨업·해금 1건 표시 시간 (연출값)
const TOAST_PRIO_ITEM := 1      # 대기열 우선순위 — 높을수록 먼저 보인다
const TOAST_PRIO_GROWTH := 0
const TOAST_MIN_RARITY := 1     # 이 등급 미만 재료는 토스트를 만들지 않는다(0 = 일반)
const TOAST_ITEM_MAX_PER_EVENT := 2  # 한 번의 inventory_changed에서 만들 획득 토스트 상한(창고 인출 등 폭주 방지)
const TOAST_POP_SCALE := 1.28   # 획득 토스트 등장 팝 배율 (연출값)
const TOAST_POP_TIME := 0.22    # 팝이 1.0으로 돌아오는 시간 (연출값)
const TOAST_COLOR_UNLOCK := Color(1, 0.85, 0.3, 1)  # 도면·하위 직업 해금 = 금색
const TOAST_COLOR_LEVEL := Color(0.6, 1, 0.7, 1)  # 레벨업 = 연두
# 구르기 쿨 바 채움 — 준비됨(밝음)/쿨 중(가라앉음). 색조는 ui_theme(ROLL_FILL)에서 오고 여기선 **밝기만**
# 곱한다(팔레트를 두 곳에 적지 않는다). 연출값이라 스크립트 const (rules §0 예외).
const ROLL_COOLING_DIM := Color(0.55, 0.58, 0.62, 1)
const INV_ICON_SIZE := 16.0  # 골드 아이콘 표시 크기(px)
# --- 하위 직업 스킬 슬롯 (2026-08-02) — 화면 아래 가운데. 지금은 1칸, 앞으로 하위 직업마다 는다 ---
# 🔴 **슬롯을 하드코딩하지 않는다** — `_skill_defs()`가 돌려준 배열만큼 코드가 칸을 만든다.
#   지금 그 배열의 길이는 1(메인 자리 스킬 하나)이고, 2~4칸이 되어도 이 파일은 안 바뀐다.
const SKILL_SLOT_SIZE := 44.0     # 칸 한 변(px) — 32px 아이콘 + 프레임 여백
const SKILL_ICON_PAD := 5.0       # 9-slice 금테가 아이콘을 먹지 않게(ui_theme NS_SLOT 7과 같은 급)
const SKILL_READY_COLOR := Color(1, 1, 1, 1)          # 준비됨 = 아이콘 원색
const SKILL_COOLING_COLOR := Color(0.55, 0.55, 0.58, 1)  # 쿨 중 = 가라앉힌다(구르기 바와 같은 관용구)
# UI 오버레이 조합 — HUD가 설정/인벤 패널을 무는 것은 조합(rules §0 예외). class_name 대신 preload(§0).
const SettingsPanelScene := preload("res://src/ui/settings_panel.tscn")
const InventoryPanelScene := preload("res://src/ui/inventory_panel.tscn")
# 개발용 디버그 패널(F1) — `?debug=1`(웹) 또는 비웹(에디터·네이티브)에서만 만든다.
# 스크립트를 따로 preload하는 이유 = **게이트 판정을 인스턴스 없이** 물어보기 위해서다(panel_enabled는 static).
const DebugPanelScene := preload("res://src/ui/debug_panel.tscn")
const DebugPanel := preload("res://src/ui/debug_panel.gd")
# 개발용 모션 튜너(F2) — 같은 게이트, 다른 성격이다: F1은 모달(뒤 클릭 차단)이라 열어 둔 채 휘두를 수
# 없어 손맛 조율에 못 쓴다. 이쪽은 **비모달**이라 슬라이더를 만진 채 바로 공격할 수 있다(그 파일 상단).
const MotionTunerScene := preload("res://src/ui/motion_tuner.tscn")
const UiTheme := preload("res://src/ui/ui_theme.gd")  # UI 톤 단일 소스 (로비·패널과 같은 테마)
const GOLD_TEX := preload("res://assets/sprites/items/gold.png")  # 골드 인벤 아이콘 (DropField와 같은 소스)
const BLUEPRINT_TEX := preload("res://assets/sprites/items/blueprint.png")  # 설계도 토스트 아이콘 (DropField와 같은 소스)

var _toast_queue: Array[Dictionary] = []  # 대기 중 토스트 — 같은 프레임에 여러 건(획득+레벨업)이 와도 차례로 보인다
var _toast_busy: bool = false  # 현재 한 건을 표시 중인가 (타이머 만료 시 다음 것으로 넘어감)
var _toast_tween: Tween = null  # 획득 팝 — 연타 시 이전 트윈이 scale을 중간값에 두고 죽지 않게 kill 후 재생성
var _settings: CanvasLayer = null  # Esc 통합 메뉴 — 방 정보·핑/경로/fps·초대 복사·레벨·소리
var _inv_panel: CanvasLayer = null  # I키 인벤 창 — HUD가 무는 조합(어디서나 열림)
var _debug_panel: CanvasLayer = null  # F1 디버그 창 — 게이트가 닫혀 있으면 null(만들지도 않는다)
var _motion_tuner: CanvasLayer = null  # F2 모션 튜너 — 같은 게이트(비모달이라 열어 둔 채 휘두를 수 있다)
var _local_player: Node = null  # 구르기 쿨 표시용 로컬 아바타 캐시 (씬/스폰마다 바뀌므로 유효성 재확인)
var _roll_ready: bool = true  # 구르기 준비 상태 — 바뀔 때만 채움색을 덮어쓴다(매 프레임 override는 WASM에서 낭비)
var _roll_fill_ready: StyleBoxFlat = null
var _roll_fill_cool: StyleBoxFlat = null
var _partner_max: int = 0  # 파트너 HP 바 분모 — 그 아바타의 `Health.max_hp`(못 읽는 창에서만 관측 래칫 폴백).
# 전멸 롤백이 만든 인벤 변동 1회를 「획득」으로 읽지 않게 삼킨다(근거 = `_on_inventory_changed` 주석).
var _swallow_next_inv_diff: bool = false
# 획득 토스트용 인벤 스냅샷 — `inventory_changed` 때 **증가분만** 뽑는다. 각 클라 자기 인벤이라 네트워크 0.
# ⚠ 픽업 확정은 `DropField._despawn_picked`가 `pid == Net.my_id`일 때만 `collect_drop`을 부르므로,
#   이 diff에는 **내가 주운 것만** 잡힌다(파트너 픽업은 안 뜬다 = 의도).
var _mat_seen: Dictionary = {}    # mat_id -> 마지막으로 본 수량
var _equip_seen: Dictionary = {}  # equip_id -> true
# 스킬 슬롯 위젯 캐시 — [{def, icon, cool, cd_label, ready}] 순서가 곧 화면 순서다.
# ⚠ `def`는 갱신 시점의 SkillDef다(쿨다운 분모). 하위 직업이 바뀌면 `_rebuild_skill_slots`가 통째로 다시 짓는다.
var _skill_slots: Array[Dictionary] = []

@onready var _hp_bar: ProgressBar = $HpBar
@onready var _hp_num: Label = $HpBar/HpNum
@onready var _partner_bar: ProgressBar = $PartnerBar
@onready var _gold_bar: HBoxContainer = $GoldBar
@onready var _banner: Label = $Banner
@onready var _toast: Control = $Toast
@onready var _toast_row: HBoxContainer = $Toast/Row
@onready var _toast_icon: TextureRect = $Toast/Row/Icon
@onready var _toast_text: Label = $Toast/Row/Text
@onready var _exp_bar: ProgressBar = $ExpBar
@onready var _roll_bar: ProgressBar = $RollBar
@onready var _skill_bar: HBoxContainer = $SkillBar


func _ready() -> void:
	# 루트가 CanvasLayer라 theme 프로퍼티가 없다 → Control 자식마다 건다(손자는 상속).
	# ⚠ 자식 CanvasLayer(설정·인벤 패널)는 건너뛴다 — 그쪽은 자기 루트에서 직접 건다.
	UiTheme.apply_to_children(self)
	# 바 채움색만 바마다 다르다(바탕·모서리는 테마 공용) — 색은 ui_theme 팔레트에서 온다.
	_hp_bar.add_theme_stylebox_override(&"fill", UiTheme.bar_fill(UiTheme.HP_FILL))
	_partner_bar.add_theme_stylebox_override(&"fill", UiTheme.bar_fill(UiTheme.HP_FILL))
	_exp_bar.add_theme_stylebox_override(&"fill", UiTheme.bar_fill(UiTheme.EXP_FILL))
	_roll_fill_ready = UiTheme.bar_fill(UiTheme.ROLL_FILL)
	_roll_fill_cool = UiTheme.bar_fill(UiTheme.ROLL_FILL * ROLL_COOLING_DIM)
	_roll_bar.add_theme_stylebox_override(&"fill", _roll_fill_ready)
	_gold_bar.add_theme_constant_override(&"separation", UiTheme.GAP_TIGHT)
	_toast_row.add_theme_constant_override(&"separation", UiTheme.GAP_ROW)
	# Esc 통합 메뉴 — 방 코드·핑/경로/fps·진행도·초대 복사·레벨·소리가 전부 여기 들어간다.
	# 여는 키(Esc)는 **HUD가** 소비하고(아래 _unhandled_input), 닫는 Esc는 패널 자신이 소비한다.
	_settings = SettingsPanelScene.instantiate() as CanvasLayer
	add_child(_settings)  # HUD(CanvasLayer) 아래 CanvasLayer(layer 10) — HUD 위 오버레이
	# I키 인벤 창 — HUD가 물어 어디서나(스테이지·마을) I로 토글. 여는 키는 HUD가 소비(아래 _unhandled_input).
	_inv_panel = InventoryPanelScene.instantiate() as CanvasLayer
	add_child(_inv_panel)
	# F1 디버그 창 — 인벤과 같은 조합(HUD가 물고, 여는 키는 HUD가 소비). 게이트가 닫히면 아예 안 만든다.
	if DebugPanel.panel_enabled():
		_debug_panel = DebugPanelScene.instantiate() as CanvasLayer
		add_child(_debug_panel)
		# F2 모션 튜너 — 같은 게이트 뒤에 함께 만든다(둘 다 `DebugBridge.panel_enabled()` 단일 소스).
		_motion_tuner = MotionTunerScene.instantiate() as CanvasLayer
		add_child(_motion_tuner)
	_refresh_hp_max()
	_set_own_hp(int(_hp_bar.max_value))
	_partner_bar.visible = false
	_banner.visible = false
	_toast.visible = false
	# 인벤 카운트 (드랍 픽업 반영) — 각 클라 자기 인벤. 골드만 화면에 남기고 나머지는 I키 인벤 창.
	_snapshot_inventory()  # ⚠ 첫 스냅샷은 **토스트 없이** — 세이브 로드분이 시작하자마자 쏟아지면 안 된다
	EventBus.inventory_changed.connect(_on_inventory_changed)
	_refresh_gold()
	# 도면 획득 토스트 — blueprint_unlocked(도면 픽업 확정)마다 잠깐 표시 후 자동 소멸.
	# 상태 배너(관전/클리어/전멸)와 독립 노드라 서로 안 덮는다. 각 클라 자기 인벤 기준.
	EventBus.blueprint_unlocked.connect(_on_blueprint_unlocked)
	EventBus.player_hp_confirmed.connect(_on_player_hp)
	EventBus.peer_left.connect(_on_peer_left)  # 파트너 바는 상대가 나가면 지운다(멈춘 바가 남으면 거짓말이 된다)
	# 직업 레벨·EXP 표기 (GDD v1.8 성장축) — 전부 각 클라 자기 GameState 읽기 전용, 네트워크 0.
	# growth_changed = 레벨/메인 변동(바+슬롯 갱신) · exp_changed = 매 적립(바만, 가벼운 훅).
	EventBus.growth_changed.connect(_refresh_growth)
	EventBus.exp_changed.connect(_on_exp_changed)
	EventBus.sub_job_level_up.connect(_on_sub_job_level_up)
	EventBus.sub_job_unlocked.connect(_on_sub_job_unlocked)
	# ⚠ 스킬 슬롯은 `_refresh_growth()` 안에서 함께 지어진다(메인 하위 직업이 그 둘의 공통 근거다).
	_refresh_growth()
	# ⚠ `boss_phase_changed`·`boss_wide_view` **구독은 2026-08-03에 끊었다** — 보스 안내 배너 삭제
	#   (근거는 아래 `_show_banner` 위 주석). 시그널 자체는 카메라·중계가 계속 쓴다.
	# 마지막 칸 클리어 = 챕터 완주 — 각 클라가 자기 GameState(G_SCENE 검증으로 동기)로 판별
	EventBus.stage_cleared.connect(func() -> void: _show_banner(
		"챕터 클리어! 마을로 귀환합니다" if GameState.is_last_stage() else "스테이지 클리어!"))
	# ⚠ 배너와 함께 **다음 인벤 변동 1회를 삼킨다** — 롤백이 되돌려 놓는 재료가 「획득」으로 뜨는 것을
	#   막는다(`_on_inventory_changed` 주석이 근거). 롤백은 `SaveManager.reload()`가 곧이어 낸다.
	EventBus.stage_wiped.connect(func() -> void:
		_swallow_next_inv_diff = true
		_show_banner("전멸 — 마을로 귀환합니다 (챕터 처음부터)"))


func _process(_delta: float) -> void:
	_refresh_roll_bar()  # 매 프레임 — 쿨은 0.8s 미만이라 주기 갱신으로 그리면 눈금이 뛴다
	_refresh_skill_slots()  # 같은 이유(쿨 게이지는 프레임마다 움직여야 눈금이 안 뛴다)


# 구르기 쿨 표시 — **표시 전용·네트워크 0.** 로컬 아바타의 읽기 접근자(roll_cooldown_ratio)만 본다.
# 바는 "차오르면 준비됨"(value = 1 − 남은비율) — 비어 가는 바보다 "지금 구를 수 있나"가 한눈에 읽힌다.
# 로컬 플레이어가 아직 없으면(스폰 전·로비) 숨긴다 — 빈 바가 떠 있으면 버그처럼 보인다.
# ⚠ 글자("구르기")는 뺐다 — 자리가 HP 바 바로 아래로 고정돼 무엇인지 위치가 말한다(사용자 확정 2026-08-02).
func _refresh_roll_bar() -> void:
	var p := _local_player_node()
	if p == null:
		_roll_bar.visible = false
		return
	_roll_bar.visible = true
	var ratio := float(p.call("roll_cooldown_ratio"))
	_roll_bar.value = 1.0 - ratio
	var ready := ratio <= 0.0
	if ready != _roll_ready:
		_roll_ready = ready
		_roll_bar.add_theme_stylebox_override(&"fill", _roll_fill_ready if ready else _roll_fill_cool)


# ============================================================================
# 하위 직업 스킬 슬롯 (2026-08-02) — 화면 아래 가운데. 🔴 **표시 전용·네트워크 0.**
# ============================================================================
# 🔴 **읽는 곳이 둘 다 단일 소스다** — 스킬 정의는 `GameState.active_skill()`(= `main_slot_def`
#   게이트), 남은 쿨은 로컬 아바타의 `skill_cooldown_left()`(= `is_skill_ready`와 같은 문턱).
#   여기서 쿨다운을 자체 계산하면 "바는 찼는데 안 나간다"가 되고 이유가 화면에 안 드러난다(§3).
# 🔴 `mouse_filter = 2`(IGNORE)를 **만드는 모든 Control에** 건다 — 화면 아래 가운데는 평타 클릭이
#   가장 자주 지나가는 자리라, 하나라도 STOP이면 그 위에서 공격이 통째로 죽는다(rules §5 UI 1번 함정,
#   헤드리스가 절대 못 잡는다).
# 🔴 색·여백·프레임은 전부 `ui_theme`에서 받는다 — 씬에 `theme_override_*`를 박지 마라(23개 파일
#   193곳이 그 단일 소스를 쓴다. 박으면 다음 톤 조정이 전수 수정이 된다).


# 지금 화면에 걸 스킬 목록 — **지금은 1칸**(메인 자리)이지만 자리는 배열이다.
# 앞으로 칸이 늘면 여기만 늘리면 되고 위젯 코드는 그대로다(사용자 확정: "앞으로 하위 직업마다 하나씩").
func _skill_defs() -> Array[SkillDef]:
	var out: Array[SkillDef] = []
	var s := GameState.active_skill()
	if s != null:
		out.append(s)
	return out


# 슬롯 재구성 — 하위 직업 변동(growth_changed)·씬 진입 시. 옛 위젯은 즉시 remove_child(중복 프레임 방지).
# 🔴 스킬이 없으면(검사·미장착) **바 전체를 숨긴다** — 빈 칸이 떠 있으면 "뭔가 고장 났다"로 읽힌다.
# 🔴 **정의가 그대로면 아무것도 안 한다** — 이 함수는 `growth_changed`를 타는데 그 훅은 **킬마다**
#   오는 `exp_changed`와 같은 갱신 함수를 지난다(`_refresh_growth`). 가드가 없으면 노드 5개를
#   매 킬 만들고 버려 웹(WASM 단일 스레드)에서 값을 치른다 — 화면은 멀쩡해서 이유가 안 드러난다.
func _rebuild_skill_slots() -> void:
	var want := _skill_defs()
	if want.size() == _skill_slots.size():
		var same := true
		for i: int in range(want.size()):
			if _skill_slots[i].get("def") != want[i]:
				same = false
				break
		if same:
			return
	for c: Node in _skill_bar.get_children():
		_skill_bar.remove_child(c)
		c.queue_free()
	_skill_slots.clear()
	_skill_bar.visible = not want.is_empty()
	if want.is_empty():
		return
	_skill_bar.add_theme_constant_override(&"separation", UiTheme.GAP_TIGHT)
	var hint := _skill_key_hint()
	for d: SkillDef in want:
		_skill_slots.append(_make_skill_slot(d, hint))


# 칸 하나 = 프레임(9-slice 금테) + 아이콘 + 쿨 커튼 + 남은 초 + 키 힌트.
# 🔴 아이콘은 **텍스처**다(`SkillDef.icon`) — 도형으로 때우지 않는다(rules §0). 아이콘이 없는
#   데이터면 칸만 비어 보이지만 배선은 그대로라, 나중에 PNG만 물리면 끝난다.
func _make_skill_slot(d: SkillDef, key_hint: String) -> Dictionary:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SKILL_SLOT_SIZE, SKILL_SLOT_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skill_bar.add_child(slot)

	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 장비 슬롯과 같은 금테 소켓 — 등급 틴트 대신 장비 테두리색을 쓴다(ui_theme 단일 소스).
	frame.add_theme_stylebox_override(&"panel", UiTheme.slot_box(UiTheme.EQUIP_BORDER, true, false))
	slot.add_child(frame)

	var icon := TextureRect.new()
	icon.texture = d.icon
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = SKILL_ICON_PAD
	icon.offset_top = SKILL_ICON_PAD
	icon.offset_right = -SKILL_ICON_PAD
	icon.offset_bottom = -SKILL_ICON_PAD
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 픽셀아트 크리스프
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)

	# 쿨 커튼 — 위→아래로 채워지는 어두운 막이 **아래로 물러나며** 아이콘을 드러낸다(= 아래→위 채움).
	# 🔴 준비되면 `value = 0`이라 **아무것도 안 그려진다** = 도입 전 아이콘과 완전 항등(항상 덮는
	#   반투명 판을 얹으면 준비 상태에서도 색이 탁해진다).
	var cool := ProgressBar.new()
	cool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cool.offset_left = SKILL_ICON_PAD
	cool.offset_top = SKILL_ICON_PAD
	cool.offset_right = -SKILL_ICON_PAD
	cool.offset_bottom = -SKILL_ICON_PAD
	cool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cool.show_percentage = false
	cool.fill_mode = ProgressBar.FILL_TOP_TO_BOTTOM
	cool.max_value = 1.0
	cool.step = 0.001
	cool.value = 0.0
	cool.add_theme_stylebox_override(&"background", StyleBoxEmpty.new())  # 바탕이 있으면 아이콘을 덮는다
	cool.add_theme_stylebox_override(&"fill", UiTheme.bar_fill(UiTheme.BAR_BG))  # 색은 ui_theme 팔레트
	slot.add_child(cool)

	# 남은 초 — 커튼만으로는 "몇 초 남았나"가 안 읽힌다(사용자 요구: 남은 시간이 눈에 보여야 한다).
	var cd_label := Label.new()
	cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_label.theme_type_variation = &"HudLabel"  # 외곽선 있음 — 아이콘 위에서도 읽힌다
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.visible = false
	slot.add_child(cd_label)

	# 키 힌트 — 🔴 **InputMap에서 유도한다.** "Q"를 박으면 `project.godot`(리드 몫)과 미러가 되어
	#   리바인드하는 순간 화면이 거짓말을 한다(rules §3 "사람이 지키는 미러는 조용히 갈라진다").
	var key := Label.new()
	key.text = key_hint
	key.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key.offset_right = -3.0
	key.offset_bottom = -1.0
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.theme_type_variation = &"HudLabel"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	slot.add_child(key)

	return {"def": d, "icon": icon, "cool": cool, "cd": cd_label, "ready": true}


# 발동 키 표기 — InputMap의 실제 배선에서 유도한다(위 주석이 근거). 액션이 없으면 빈 문자열(칸만 남는다).
func _skill_key_hint() -> String:
	if not InputMap.has_action(&"skill"):
		return ""
	for ev: InputEvent in InputMap.action_get_events(&"skill"):
		var k := ev as InputEventKey
		if k == null:
			continue
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		if code != 0:
			return OS.get_keycode_string(code)
	return ""


# 매 프레임 쿨 갱신 — 🔴 **로컬 아바타의 읽기 접근자만 본다**(상태를 바꾸지 않는다, `_refresh_roll_bar` 미러).
# 아바타가 아직 없으면(스폰 전·로비) 커튼을 가득 채우지 말고 **그대로 둔다** — 스폰 프레임에
# 값이 튀는 것보다 낫고, 어차피 다음 프레임에 실제 값이 들어온다.
func _refresh_skill_slots() -> void:
	if _skill_slots.is_empty():
		return
	var p := _local_player_node()
	if p == null or not p.has_method("skill_cooldown_left"):
		return
	for s: Dictionary in _skill_slots:
		var d := s.get("def") as SkillDef
		var cool := s.get("cool") as ProgressBar
		var cd_label := s.get("cd") as Label
		var icon := s.get("icon") as TextureRect
		if d == null or cool == null or cd_label == null or icon == null:
			continue
		# ⚠ 지금은 칸이 하나라 아바타 접근자가 그 칸의 값이다. 칸이 늘면 접근자에 **스킬 id 인자**가
		#   필요해진다(그때 player 쪽 API를 넓히고 여기 루프만 고친다 — 위젯 구조는 그대로다).
		var left := float(p.call("skill_cooldown_left"))
		var ratio := float(p.call("skill_cooldown_ratio"))
		cool.value = clampf(ratio, 0.0, 1.0)
		var ready := left <= 0.0
		cd_label.visible = not ready
		if not ready:
			# 올림 — "1초 남음"이 0으로 표시된 채 한 프레임 더 기다리는 것보다 낫다.
			cd_label.text = "%d" % maxi(1, int(ceilf(left)))
		if ready != bool(s.get("ready", true)):
			s["ready"] = ready
			icon.modulate = SKILL_READY_COLOR if ready else SKILL_COOLING_COLOR


# 로컬 아바타 찾기 — 씬 전환·재스폰마다 노드가 바뀌므로 캐시를 유효성으로 검증하고 필요할 때만 다시 스캔한다.
# ⚠ 씬 스왑 프레임엔 이전 씬 노드가 그룹에 남는다(rules §5) — 캐시가 무효해지면 그 프레임에 옛 노드를
# 잡을 수 있지만, 표시 전용이고 다음 프레임에 새 노드로 교체되므로 무해하다.
func _local_player_node() -> Node:
	if is_instance_valid(_local_player) and _local_player.is_inside_tree():
		return _local_player
	_local_player = null
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n.get("is_local") == true and n.has_method("roll_cooldown_ratio"):
			_local_player = n
			break
	return _local_player


# Esc = 통합 메뉴 열기 · I키 = 인벤 창 토글 — 둘 다 **여기 한 곳에서만** 소비한다(rules §5).
# 🔴 Esc의 "닫기"는 여기가 아니라 각 패널이 자기 `_unhandled_input`에서 소비한다. 패널들이 트리에서
#   HUD보다 뒤에 있어(설정·인벤은 HUD의 자식, 제작·훈련소는 마을 씬의 뒤 형제) 입력을 **먼저** 받으므로,
#   무언가 열려 있으면 이 함수까지 오지 않는다 = "열려 있으면 닫기, 아무것도 없으면 메뉴"가 성립한다.
#   ⚠ 이 성질은 **씬 트리 순서에 기댄다** — 새 패널을 마을/스테이지 씬에 놓을 땐 HUD **뒤에** 놓아라.
# 🔴 F1(디버그 패널)·F2(모션 튜너)도 여기 한 곳에서만 소비한다 — 패널이 같이 먹으면 열자마자 닫힌다.
#   InputMap 액션이 아니라 raw 키로 본다: project.godot(입력 맵)은 리드 몫이고, F1/F2는 리바인드 대상이
#   아닌 개발용 키라 액션을 늘릴 이유가 없다. 게이트가 닫혀 패널이 없으면 키를 **소비하지 않는다**.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _settings != null:
			_settings.call("open")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		if _inv_panel != null:
			_inv_panel.call("toggle")
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F1 and _debug_panel != null:
		_debug_panel.call("toggle")
		get_viewport().set_input_as_handled()
	# ⚠ 모션 튜너는 비모달이라 그 패널은 어떤 키도 삼키지 않는다: Esc·F·WASD가 전부 게임으로 가야
	#   열어 둔 채로 움직이며 휘두를 수 있다. 그래서 닫는 키가 여기 있는 F2뿐이다.
	elif key.keycode == KEY_F2 and _motion_tuner != null:
		_motion_tuner.call("toggle")
		get_viewport().set_input_as_handled()


func _on_player_hp(peer_id: int, hp: int) -> void:
	if peer_id == Net.my_id:
		_set_own_hp(hp)
		if hp <= 0:
			_show_banner("관전 중 — 스테이지 클리어 시 부활")
		elif _banner.visible and _banner.text.begins_with("관전"):
			_banner.visible = false
	else:
		_set_partner_hp(peer_id, hp)


# 그 peer의 아바타 노드 — 🔴 **`as` 캐스트로 찾지 마라.** 씬 스왑 프레임엔 해제된 이전 씬 노드가
#   그룹에 남고, 캐스트는 그 자리에서 터져 함수를 통째로 중단시킨다(docs/DECISIONS.md 2026-08-01 —
#   이 프로젝트가 가장 비싸게 값을 치른 결함 모양). `is_instance_valid` → `get()` 순서가 계약이다.
func _peer_player_node(peer_id: int) -> Node:
	for n: Node in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n.get("peer_id") == peer_id:
			return n
	return null


# 파트너 HP — 글자 없이 내 바 아래 얇은 한 줄(사용자 확정 2026-08-02: 2인 협동이라 동료 체력은 필요하다).
# 🔴🔴 **분모는 그 피어 아바타의 `Health.max_hp`다 — 「관측 최대치」로 근사하지 마라** (netreview M-1).
#   처음엔 *"남의 max_hp는 표시 경로로 오지 않는다"* 는 이유로 관측 래칫(`maxi`)을 썼는데, **그 전제가
#   거짓이었다**: 원격 아바타의 최대 HP는 이미 모든 클라가 로컬로 리졸브한다 —
#     G_JOB(직업 id) + G_STATS `"hp"` → `peer_sync.set_equip_stats` → `player._apply_max_hp()`
#       → `Health.set_max_hp(job.max_hp + equip_hp_bonus)`
#   즉 **신규 네트워크 필드 0개**로 정확한 분모가 나오고, 게다가 그것이 호스트가 판정에 쓰는 값과
#   **같은 소스**라 갈라질 수 없다(rules §3 「대상 아바타에서 읽는다」의 표시판).
# 🔴 관측 래칫이 왜 위험했나: HUD는 **씬마다 새로 태어나** `_partner_max`가 매 칸 0에서 시작하는데,
#   새 칸의 첫 php는 **호스트가 재확정한 이월 HP**다. 이월 45 / 실제 최대 120이면 분모가 45로 굳어
#   **바가 가득 찬다** — 동료가 세 대면 죽는 상태에서 「여유 있다」로 읽힌다. 부활은 HP 1이고 모닥불도
#   없어 래칫이 **판 내내 회복되지 않는다.**
# ⚠ 아바타가 아직 없거나(스폰 전) 최대 HP가 0인 창에서만 옛 래칫을 **폴백**으로 남긴다.
func _set_partner_hp(peer_id: int, hp: int) -> void:
	var v := maxi(hp, 0)
	var node := _peer_player_node(peer_id)
	var real_max := 0
	if node != null:
		var h: Node = node.get_node_or_null(^"Health")
		if h != null:
			real_max = maxi(int(h.get("max_hp")), 0)
	if real_max > 0:
		_partner_max = real_max
	else:
		_partner_max = maxi(_partner_max, v)  # 폴백: G_STATS 도착 전 창
	if _partner_max <= 0:
		_partner_bar.visible = false
		return
	_partner_bar.visible = true
	_partner_bar.max_value = float(_partner_max)
	_partner_bar.value = float(v)


func _on_peer_left(peer_id: int) -> void:
	if peer_id == Net.my_id:
		return
	_partner_bar.visible = false
	_partner_max = 0


# 골드만 우하단 아이콘+숫자 표시 (inventory_changed 훅). 재료·장비는 I키 인벤 창(inventory_panel).
# 재구성 = 옛 항목 즉시 remove_child(중복 프레임 방지) 후 재생성.
func _refresh_gold() -> void:
	for c: Node in _gold_bar.get_children():
		_gold_bar.remove_child(c)
		c.queue_free()
	# 아이콘 → 숫자 순(우측정렬 컨테이너라 왼쪽에 아이콘, 오른쪽에 숫자)
	var tr := TextureRect.new()
	tr.texture = GOLD_TEX
	tr.custom_minimum_size = Vector2(INV_ICON_SIZE, INV_ICON_SIZE)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 픽셀아트 크리스프
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_bar.add_child(tr)
	var lbl := Label.new()
	lbl.text = str(GameState.gold)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.theme_type_variation = &"HudGoldLabel"  # 금색 + 외곽선 = ui_theme 등급 (여기서 Color를 박지 않는다)
	_gold_bar.add_child(lbl)


func _on_inventory_changed() -> void:
	_refresh_gold()
	_refresh_hp_max()  # 장비를 바꾸면 최대 HP가 바뀐다 — 바 분모가 안 따라오면 "가득인데 가득이 아님"이 된다
	# 🔴 **전멸 롤백이 만든 변동은 「획득」이 아니다** (netreview m-1). `SaveManager.reload()`가
	#   마지막 줄에서 `inventory_changed`를 emit하는데, 롤백이 판 도중 **소모한** 재료를 되돌려 놓으면
	#   그게 증가분으로 잡혀 **전멸 배너와 나란히 "희귀 재료 x3" 획득 토스트**가 뜬다 — 잃은 순간에
	#   얻었다고 말하는 방향이다. 그래서 전멸 직후 한 번은 **토스트 없이 스냅샷만** 갱신한다.
	# ⚠ 이 경로는 2026-08-02 전멸 판정 수정으로 **처음 실제로 돌기 시작했다**(그전엔 전멸 자체가 안 났다).
	if _swallow_next_inv_diff:
		_swallow_next_inv_diff = false
		_snapshot_inventory()
		return
	_diff_inventory_toasts()


# --- 획득 토스트 (사용자 신고 2026-08-02: "내가 좋은거 먹은지를 모르겠다") ---
# 🔴 **새 시그널을 만들지 않았다** — `item_picked`는 등급만 싣고 **어느 아이템인지·누가 주웠는지를
#   안 싣는다**(파트너 픽업에도 발화한다). 그래서 이미 있는 `inventory_changed` 위에 **내 인벤의
#   증가분**을 얹었다: 아이콘·이름·수량이 전부 로컬 `.tres`에서 나오고 네트워크 필드가 0개다.
#   (제작/강화로 얻은 장비도 같은 경로로 뜬다 — "얻었다"는 사실은 같으므로 의도된 부작용이다.)
func _snapshot_inventory() -> void:
	_mat_seen.clear()
	for mid: String in GameState.materials:
		_mat_seen[mid] = int(GameState.materials[mid])
	_equip_seen.clear()
	for eid: String in GameState.owned_equipment:
		_equip_seen[eid] = true


func _diff_inventory_toasts() -> void:
	var shown := 0
	# 장비는 등급 필터 없이 전부 띄운다 — 드물고, 곧 착용 판단이 필요한 소식이다.
	for eid: String in GameState.owned_equipment:
		if _equip_seen.has(eid):
			continue
		if shown >= TOAST_ITEM_MAX_PER_EVENT:
			break
		var e := GameState.equip_def(eid)
		if e == null:
			continue
		_push_item_toast(_disp(e.display_name, "새 장비"), e.icon, UiTheme.EQUIP_BORDER)
		shown += 1
	# 재료는 **희귀 이상만** — 흔한 재료가 매번 큰 토스트를 띄우면 그게 곧 신고받은 소음이다.
	for mid: String in GameState.materials:
		if shown >= TOAST_ITEM_MAX_PER_EVENT:
			break
		var qty := int(GameState.materials[mid])
		var gained := qty - int(_mat_seen.get(mid, 0))
		if gained <= 0:
			continue
		var m := GameState.material_def(mid)
		if m == null or m.rarity < TOAST_MIN_RARITY:
			continue
		_push_item_toast(
			"%s x%d" % [_disp(m.display_name, "재료"), gained],
			m.icon, UiTheme.rarity_color(m.rarity))
		shown += 1
	_snapshot_inventory()  # 상한에 걸려 못 띄운 것도 스냅샷은 갱신한다(다음 획득에 소급 발화 금지)


# 내부 id 노출 방지 — 표시명이 비면 종류 이름으로 떨어진다(패널들과 같은 관용구).
func _disp(name: String, fallback: String) -> String:
	return name if not name.is_empty() else fallback


# 🔴 **보스 전투 안내 배너는 2026-08-03에 삭제했다 — 되살리지 마라**(사용자 지시:
#   *"텍스트 뜨는 것도 다 지워줘, 알아서 보고 피하게"*). 지운 것 둘:
#     ⑴ 「돌진 주의 — 붉은 띠를 피해라!」 (`boss_wide_view` 구독)
#     ⑵ 「페이즈 2!」 (`boss_phase_changed` 구독)
#   위협은 **화면이 말한다** — 붉은 띠 예고 도형·차오름·광역 줌아웃이 그 역할이고, 글자는 그것을
#   읽는 습관을 오히려 늦춘다(GDD §5 기믹 원칙 = 예고를 **보고** 피한다).
# 🔴 **시그널 자체는 살아 있다 — HUD 구독만 끊었다.** `EventBus.boss_wide_view`는 카메라 줌아웃
#   (`camera_rig`)과 `mob_sync`의 `G_BOSS_VIEW` 중계가 쓰고, `EventBus.boss_phase_changed`는
#   `mob_sync`의 `G_BOSS_PHASE` 중계와 시험장 램프가 쓴다. 지우면 광역 시야가 죽는다.
# ⚠ `$Banner` 노드와 `_show_banner`는 **유지**다 — 클리어/전멸/관전은 게임 진행 상태라 대체 신호가
#   없다(그 셋은 패턴 안내가 아니다).


# 내 HP 바 분모 — 🔴 `player._apply_max_hp()`와 **같은 유도**(직업 기본 + 착용 장비 체력)를 쓴다.
# ⚠ 이건 미러다(§3 후보) — 갈라지면 "체력이 가득인데 바가 안 참"이 되고 에러가 안 난다. 그래서
#   `_set_own_hp`가 확정 HP로 분모를 한 번 더 밀어 올려, **틀리는 방향을 항상 "바가 덜 찬 쪽"이 아니라
#   "바가 가득인 쪽"으로** 고정한다(관측값보다 작은 분모는 존재할 수 없다).
func _refresh_hp_max() -> void:
	var job := GameState.selected_job()
	var bonus := int(GameState.current_stats().get("hp", 0))
	var m := maxi(1, (job.max_hp if job != null else 1) + bonus)
	_hp_bar.max_value = float(maxi(m, int(_hp_bar.value)))


func _set_own_hp(hp: int) -> void:
	var v := maxi(hp, 0)
	if float(v) > _hp_bar.max_value:
		_hp_bar.max_value = float(v)  # 위 주석 — 분모가 관측값보다 작아지는 일은 없게
	_hp_bar.value = float(v)
	_hp_num.text = str(v)  # 숫자만 (사용자 확정: 글자를 줄이고 숫자 위주로)


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true


# 도면 획득 토스트 — 레시피명을 잠깐 띄운다. **획득 등급**이라 아이콘 + 우선순위를 함께 받는다.
func _on_blueprint_unlocked(recipe_id: String) -> void:
	var r := GameState.recipe_def(recipe_id)
	var disp := _disp(r.display_name if r != null else "", "새 설계도")  # 내부 id 노출 방지
	_push_item_toast(disp, BLUEPRINT_TEX, TOAST_COLOR_UNLOCK)


# 하위 직업 레벨업 — 계열 보유분에 EXP가 동시 적립되므로 한 킬에 여러 건이 올 수 있다(큐가 차례로 보여준다).
# ⚠ 잦은 소식이라 **성장 등급**(작게·짧게·뒤로) — 획득 토스트를 덮으면 신고받은 그 증상이 된다.
func _on_sub_job_level_up(sub_id: String, level: int) -> void:
	_push_growth_toast("Lv.%d %s" % [level, _sub_job_name(sub_id)], TOAST_COLOR_LEVEL)


# 다음 하위 직업 해금 — 레벨업과 같은 프레임에 오는 게 정상(레벨업이 해금을 트리거)이라 큐로 둘 다 보인다.
func _on_sub_job_unlocked(sub_id: String) -> void:
	_push_growth_toast("해금 %s" % _sub_job_name(sub_id), TOAST_COLOR_UNLOCK)


func _sub_job_name(sub_id: String) -> String:
	var d := GameState.sub_job_def(sub_id)
	return _disp(d.display_name if d != null else "", "새 하위 직업")  # 내부 id 노출 방지


# --- 공용 토스트 큐 (획득 · 성장이 같은 노드를 차례로 쓴다 — 노드를 늘리지 않아 레이아웃/클릭 리스크 0) ---

func _push_item_toast(text: String, icon: Texture2D, color: Color) -> void:
	_push_toast({
		"text": text, "color": color, "icon": icon,
		"time": TOAST_TIME_ITEM, "prio": TOAST_PRIO_ITEM,
	})


func _push_growth_toast(text: String, color: Color) -> void:
	_push_toast({
		"text": text, "color": color, "icon": null,
		"time": TOAST_TIME_GROWTH, "prio": TOAST_PRIO_GROWTH,
	})


# 🔴 우선순위 삽입 — 획득은 **대기 중인 성장 소식보다 앞으로** 끼운다. 레벨업/해금은 킬마다 올 수 있어서,
#   FIFO로 두면 드문 획득이 잦은 성장 뒤에 줄을 서다 상한에 밀려 사라진다(= 신고받은 증상).
#   넘칠 때 버리는 것도 **가장 낮은 우선순위의 가장 오래된 것**이라 획득은 마지막까지 살아남는다.
func _push_toast(entry: Dictionary) -> void:
	var prio := int(entry.get("prio", 0))
	var i := _toast_queue.size()
	while i > 0 and int(_toast_queue[i - 1].get("prio", 0)) < prio:
		i -= 1
	_toast_queue.insert(i, entry)
	while _toast_queue.size() > TOAST_QUEUE_MAX:
		var drop := 0
		for j: int in range(_toast_queue.size()):
			if int(_toast_queue[j].get("prio", 0)) < int(_toast_queue[drop].get("prio", 0)):
				drop = j
		_toast_queue.remove_at(drop)
	if not _toast_busy:
		_advance_toast()


func _advance_toast() -> void:
	if _toast_queue.is_empty():
		_toast_busy = false
		_toast.visible = false
		return
	_toast_busy = true
	var m: Dictionary = _toast_queue.pop_front()
	var is_item := int(m.get("prio", 0)) >= TOAST_PRIO_ITEM
	var icon := m.get("icon") as Texture2D
	_toast_icon.texture = icon
	_toast_icon.visible = icon != null
	_toast_text.theme_type_variation = &"ToastLabel" if is_item else &"ToastSmallLabel"
	_toast_text.text = str(m.get("text", ""))
	var col: Color = m.get("color", Color(1, 1, 1, 1))
	_toast_text.add_theme_color_override(&"font_color", col)
	_toast.visible = true
	if is_item:
		_pop_toast()
	# 타이머 만료 → 다음 대기분(없으면 숨김). HUD가 씬 전환으로 사라지면 연결이 자동 해제된다.
	get_tree().create_timer(float(m.get("time", TOAST_TIME_GROWTH))).timeout.connect(_advance_toast)


# 획득만 살짝 튀어나온다 — 등급색·아이콘·크기에 더해 **움직임**이 "새 소식"을 가장 빨리 알린다.
# ⚠ 스케일은 `Row`에 건다(부모 `Toast`는 클릭 통과용 껍데기라 크기가 화면 폭 고정이다).
#   레이아웃 전(첫 프레임)엔 size가 0일 수 있으니 그때는 팝을 건너뛴다 — 표시 자체는 정상이다.
func _pop_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	if _toast_row.size.x <= 0.0:
		_toast_row.scale = Vector2.ONE
		return
	_toast_row.pivot_offset = _toast_row.size * 0.5
	_toast_row.scale = Vector2(TOAST_POP_SCALE, TOAST_POP_SCALE)
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_row, "scale", Vector2.ONE, TOAST_POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# EXP 진행 — 🔴 화면에는 **바만** 남는다(맨 아래 가로 띠). 하위 직업 이름·레벨 숫자는 Esc 메뉴로 옮겼다.
# 성장축이 없는 계열(main_sub_job() == null)은 바를 통째로 숨긴다 — 빈 바가 떠 있으면 버그처럼 보인다.
func _refresh_growth() -> void:
	# 🔴 스킬 슬롯도 **같은 훅에서** 다시 짓는다 — 메인 하위 직업이 바뀌면 스킬이 통째로 바뀐다.
	#   따로 훅을 파면 "특성·색은 바뀌었는데 슬롯만 옛 스킬"이 되고, 그건 클릭하기 전엔 안 드러난다.
	_rebuild_skill_slots()
	if GameState.main_sub_job() == null:
		_exp_bar.visible = false
		return
	_exp_bar.visible = true
	var p := GameState.main_exp_progress()
	_set_exp_bar(int(p["cur"]), int(p["need"]))


# 매 적립 훅 — 인자(cur/need)는 GameState.main_exp_progress()와 같은 값이라 _refresh_growth로 일원화한다
# (표기를 두 곳에서 만들면 갈라진다). 비용 = 킬당 Dictionary 하나 + 짧은 곡선 루프.
func _on_exp_changed(_cur: int, _need: int) -> void:
	_refresh_growth()


func _set_exp_bar(cur: int, need: int) -> void:
	if need <= 0:  # 만레벨 — 바는 가득 찬 상태로 남긴다(사라지면 "뭔가 없어졌다"로 읽힌다)
		_exp_bar.max_value = 1.0
		_exp_bar.value = 1.0
		return
	_exp_bar.max_value = float(need)
	_exp_bar.value = float(clampi(cur, 0, need))
