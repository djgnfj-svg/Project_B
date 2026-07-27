extends CanvasLayer
# 개발용 디버그 패널 (F1) — 실기 확인을 위해 "정직한 클라가 시간을 들이면 도달할 수 있는 상태"로 점프한다.
# 속사수 하나 보려고 EXP 모아 Lv3 해금 → 장착 → 활 제작 → 적 찾아가는 왕복을 없애는 것이 목적이다.
#
# 🔴 **로컬 상태만 바꾼다 — 새 네트워크 메시지 0개·새 신뢰 경계 0개.**
#   바뀐 직업·장비·하위 직업·레벨은 전부 **기존 G_STATS/G_JOB 공지 경로**로 흘러가고
#   (PeerSync가 inventory_changed·growth_changed를 구독한다), 호스트가 이미 검증·clamp한다
#   (can_job_equip 대조 · max_level_stats/max_equip_stats clamp · traits_of의 계열/슬롯/중복 폐기).
#   여기서 "호스트를 우회해야 할 것 같은" 기능이 필요해지면 그건 설계가 틀린 신호다 — 멈추고 보고할 것.
#
# craft_panel 모달 패턴을 **복제**했다(새 패턴 아님 — rules §5):
#  - 루트 = CanvasLayer(layer 12 = 다른 패널 11보다 위), 기본 visible=false. 닫히면 완전히 숨어 뒤 클릭을 안 막는다.
#  - Backdrop(ColorRect) = mouse_filter 기본 STOP → 열려 있는 동안만 뒤 게임 클릭을 막는다(마우스만 모달).
#  - Center(CenterContainer) = mouse_filter IGNORE(2) → 화면을 덮지만 클릭을 안 먹는다(rules §5 1번 함정).
#  - 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지. 상대는 계속 움직인다.
#  - 🔴 **F1은 이 패널이 소비하지 않는다.** HUD(stage_hud.gd)가 소비하고 여기 toggle()을 부른다
#    (I키 인벤과 같은 관용구) — 양쪽이 다 처리하면 열자마자 닫힌다. 여기서 먹는 키는 Esc뿐이다.
#  - 스타일은 ui_theme 단일 소스(theme_override_*를 흩뿌리지 않는다) · 레이아웃은 컨테이너 주도.
#
# 🔴 **직업 전환은 기존 배선(EventBus.job_change_requested)에 얹는다** — `selected_job_id`를 직접 대입하지
#   않고, `apply_job_loadout()`의 **네 번째 호출부도 만들지 않는다**(rules §3). 설정 패널 "직업 변경"이
#   쓰는 그 입구로 보내면 PeerSync(마을 씬)가 ⑴ G_JOB 공지 먼저 ⑵ GameState.apply_job_loadout()
#   ⑶ 로컬 아바타 반영 + G_STATS 재공지를 **이미 올바른 순서로** 해준다. 순서까지 복제할 이유가 없다.
#   ⚠ 그래서 직업 전환은 **마을에서만** 유효하다(PeerSync가 SCENE_VILLAGE에서만 처리 + GameState의
#   revalidate/autofill이 in_chapter 가드로 막는다) — 판 도중엔 버튼을 비활성화하고 사유를 띄운다.
#
# ⚠ UI 씬 스크립트라 전역 오토로드(GameState·EventBus·CombatMath) 직접 접근 OK (rules §5, -s 대상 아님).
#   class_name 선언은 하지 않는다(§0).

const UiTheme := preload("res://src/ui/ui_theme.gd")
# 게이트 판정 단일 소스. 오토로드(`DebugBridge`) 인스턴스 대신 **스크립트**를 물어 static으로 부른다.
const DebugBridgeScript := preload("res://src/core/debug_bridge.gd")

# 지급량 — 디버그 편의값이라 밸런스가 아니다(스크립트 const, rules §0 예외).
const GRANT_GOLD := 99999
const GRANT_MATERIAL := 99

# 레이아웃 최소폭 — 여러 줄의 제목/버튼을 세로로 맞추는 용도로만 쓴다(위치는 전부 컨테이너가 잡는다).
const TITLE_W := 84.0
const BTN_W := 92.0
const NAME_W := 108.0
const STEP_W := 26.0
const VALUE_W := 62.0
const ACT_W := 62.0

const IN_CHAPTER_MSG := "판 도중에는 직업·하위 직업을 바꿀 수 없습니다 — 마을에서만 가능합니다"

# 시험장 챕터 id — `data/chapters/test_arena.tres`와 **미러**다(파일명 = id 관례).
# ⚠ 정상 플레이에서는 도달 불가다: 마을 출발 게이트가 `GameState.DEFAULT_CHAPTER_ID`만 쓰므로
#   이 챕터로 가는 입구는 아래 버튼 하나뿐이고, 그 버튼은 `panel_enabled()` 뒤에 있다.
const ARENA_CHAPTER_ID := "test_arena"

signal closed

@onready var _close_btn: Button = %CloseBtn
@onready var _body: VBoxContainer = %Body
@onready var _notice: Label = %NoticeLabel
@onready var _hint: Label = %HintLabel

# 다음 그리기 1회에만 뜨는 안내(거부 사유) — subjob_panel과 같은 관용구.
var _pending_notice: String = ""
# 레벨 스테퍼의 현재 값. "지급"할 때도 이 레벨로 준다(새로 연 하위 직업이 Lv0로 남지 않게).
var _level: int = 0
var _enabled: bool = false


# 🔴 게이트 판정의 **정본은 `debug_bridge.gd`** 다 — 이 패널과 `window.pb_*` 브리지가 같은 조건으로
#   열려야 "브리지는 되는데 패널은 안 뜬다"가 안 생긴다. 판정식을 여기 복제하지 마라(2026-07-28 이관).
static func panel_enabled() -> bool:
	return DebugBridgeScript.panel_enabled()


func _ready() -> void:
	visible = false
	_enabled = panel_enabled()
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (제작/인벤/훈련소와 통일)
	_close_btn.pressed.connect(close)
	# 크기는 씬의 InfoLabel 등급, 색만 의미별로 덮는다(값은 전부 UiTheme 팔레트 — 여기서 Color 생성 금지)
	_notice.add_theme_color_override(&"font_color", UiTheme.GOLD)
	_hint.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	# 내가 바꾼 것이든 남이 바꾼 것이든(픽업·레벨업) 열려 있는 동안 즉시 반영.
	EventBus.inventory_changed.connect(_on_changed)
	EventBus.growth_changed.connect(_on_changed)


# --- 공개 API (HUD가 F1로 부른다) ---

func open() -> void:
	if not _enabled:
		return
	_pending_notice = ""
	_level = _current_level()  # 열 때 현재 메인 레벨에 맞춰 둔다(스테퍼가 엉뚱한 값에서 시작하지 않게)
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


# 🔴 F1은 HUD가 소비한다(위 주석) — 여기서 같이 먹으면 열자마자 닫힌다. 여기서 먹는 것은 둘뿐이다:
#  - Esc = 닫기.
#  - F(interact) = **삼키기만** 한다(닫지 않는다). 공격은 좌클릭이라 Backdrop(STOP)이 막지만 F는 키라
#    그냥 통과해, 제작대 앞에서 F를 누르면 제작 패널(layer 11)이 **이 패널 뒤에 가려진 채** 열린다.
#    모달인 동안은 뒤 세계 조작이 없는 것이 맞다. (craft/subjob 패널이 F로 닫히는 것은 그쪽이 F로
#    열렸기 때문이다 — 이 패널은 F1로 여니 F로 닫으면 오히려 규칙이 갈라진다.)
# ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로(rules §5) 반드시 visible 가드 —
#   없으면 닫힌 패널이 제작대/훈련소의 F를 영영 삼킨다.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()


# 🔴 **코얼레스한다 — 한 클릭이 공지를 여러 통 만들기 때문이다** (2026-07-28 netreview M-1).
#   「전부 열기」 한 번에 `add_gold`·`add_material`×N·`unlock_blueprint`×N·`add_equipment`×N이 각각
#   `inventory_changed`를 쏘고, 그때마다 `_refresh()`가 패널을 통째로 재생성하면(약 40노드 파괴/생성)
#   WASM에서 **프레임 히치**가 난다. 그 히치가 곧 호스트의 "한 프레임에 패킷 몰아 드레인"을 만들어
#   발사 게이트를 깨는 원인이 된다(같은 리뷰 I-1) — 즉 디버그 도구의 렌더 비용이 측정을 오염시킨다.
#   프레임당 한 번만 다시 그린다.
var _refresh_queued: bool = false


func _on_changed() -> void:
	if not visible or _refresh_queued:
		return
	_refresh_queued = true
	_do_refresh_deferred.call_deferred()


func _do_refresh_deferred() -> void:
	_refresh_queued = false
	if visible:
		_refresh()


# --- 그리기 ---

func _refresh() -> void:
	_clear(_body)
	_level = clampi(_level, 0, _max_level())
	_body.add_child(_job_row())
	_body.add_child(_main_row())
	for i: int in range(GameState.SUB_SLOT_COUNT):
		_body.add_child(_slot_row(i))
	_body.add_child(_level_row())
	_body.add_child(_weapon_rows())
	_body.add_child(_grant_row())
	_body.add_child(_arena_row())
	_refresh_notice()
	_hint.text = "미보유 하위 직업·장비도 누르면 즉시 보유+장착된다 · 레벨은 보유분 전부에 적용 · Esc 또는 F1로 닫기"


# 안내 한 줄 — 판 도중 잠금이 최우선(다른 거부의 원인이라 그것만 말하면 된다),
# 그 외엔 직전 조작의 거부 사유를 1회 띄운다(subjob_panel 미러).
func _refresh_notice() -> void:
	var msg := _pending_notice
	_pending_notice = ""
	if GameState.in_chapter():
		msg = IN_CHAPTER_MSG
	_notice.text = msg
	_notice.visible = not msg.is_empty()


func _notify(msg: String) -> void:
	_pending_notice = msg
	_refresh()


# --- 직업 ---

func _job_row() -> Control:
	var row := _row("직업")
	var locked := GameState.in_chapter()
	for jid: String in GameState.job_ids():
		var j := GameState.job_def(jid)
		var label := j.display_name if j != null and not j.display_name.is_empty() else jid
		if jid == GameState.selected_job_id:
			label += " ✓"
		var b := _btn(label, BTN_W, locked, _on_job_pressed.bind(jid))
		b.tooltip_text = "이 직업으로 전환 — 시작 무기·시작 하위 직업까지 함께 정리된다(마을에서만)"
		row.add_child(b)
	return row


# 🔴 `selected_job_id`를 직접 대입하지 않는다 — 설정 패널과 **같은 입구**로 보낸다(파일 상단 주석).
#   PeerSync(마을)가 G_JOB 공지 → GameState.apply_job_loadout() → 로컬 반영 + G_STATS 재공지를 한다.
func _on_job_pressed(jid: String) -> void:
	if GameState.in_chapter():
		_notify(IN_CHAPTER_MSG)
		return
	if jid == GameState.selected_job_id:
		return
	EventBus.job_change_requested.emit(jid)
	if GameState.selected_job_id != jid:
		# 마을 씬이 아니면 PeerSync가 안 받는다(로비 등) — 아무 일도 안 일어난 것을 정직하게 말한다.
		_notify("직업 전환이 반영되지 않았습니다 — 마을에서만 가능합니다")
		return
	_level = _current_level()  # 계열이 바뀌면 곡선·보유가 통째로 달라진다
	_commit_save()
	_refresh()


# --- 메인 하위 직업 ---

func _main_row() -> Control:
	var row := _row("메인")
	var locked := GameState.in_chapter()
	for sid: String in GameState.sub_jobs_of_series(GameState.selected_job_id):
		row.add_child(_sub_btn(sid, sid == GameState.main_sub_job_id, locked, _on_main_pressed.bind(sid)))
	return row


func _on_main_pressed(sid: String) -> void:
	if GameState.in_chapter():
		_notify(IN_CHAPTER_MSG)
		return
	if not _ensure_sub_job(sid):
		_notify("모르는 하위 직업입니다 — data/subjobs 확인")
		return
	if not GameState.set_main_sub_job(sid):
		_notify("메인으로 지정할 수 없습니다 — 이 계열의 갈래만 가능합니다(공유는 서브 전용)")
		return
	_commit_save()
	_refresh()


# --- 서브 칸 (계열 잔여 + 공유) ---

func _slot_row(index: int) -> Control:
	var row := _row("서브 %d" % (index + 1))
	var locked := GameState.in_chapter()
	var cur := GameState.sub_slot_id(index)
	row.add_child(_btn("비움" + (" ✓" if cur.is_empty() else ""), 52.0, locked,
		_on_slot_pressed.bind(index, "")))
	for sid: String in _slot_candidates():
		row.add_child(_sub_btn(sid, sid == cur, locked, _on_slot_pressed.bind(index, sid)))
	return row


# 서브 칸에 낄 수 있는 후보 = 이 계열 갈래 전부 + 공유 갈래 전부(곡예사·도굴꾼).
# 메인과 겹치는 것은 GameState.set_sub_slot이 거부하므로 목록에서 지우지 않고 사유로 말한다.
func _slot_candidates() -> Array[String]:
	var out := GameState.sub_jobs_of_series(GameState.selected_job_id)
	out.append_array(GameState.shared_sub_jobs())
	return out


func _on_slot_pressed(index: int, sid: String) -> void:
	if GameState.in_chapter():
		_notify(IN_CHAPTER_MSG)
		return
	if not sid.is_empty() and not _ensure_sub_job(sid):
		_notify("모르는 하위 직업입니다 — data/subjobs 확인")
		return
	if not GameState.set_sub_slot(index, sid):
		_notify("이 칸에 넣을 수 없습니다 — 메인과 같은 갈래이거나 다른 계열입니다")
		return
	_commit_save()
	_refresh()


# --- 직업 레벨 (EXP를 그 레벨의 누적 요구치로 세팅) ---

# 🔴 **판 도중 잠금이 직업·하위 직업과 같은 이유로 여기에도 필요하다** (2026-07-28 netreview I-2).
#   레벨을 바꾸면 `growth_changed` → 로컬 아바타에 **즉시** 반영 + G_STATS 재공지인데, 호스트의 원격
#   아바타는 **편도 지연(배포 릴레이 70~200ms) 뒤에야** 바뀐다. 그 창에서 로컬 쿨다운은 새 haste로
#   짧아졌는데 호스트 임계는 옛 haste라 `is_hit_cooldown_ok`가 **거부**한다 → 스윙은 나가고 데미지만 0.
#   `move`가 오르면 원격 변위 clamp가 정당한 이동을 깎아 "피했는데 맞았다"도 부분 재발한다(rules §3).
# 🔴 **이 창이 위험한 진짜 이유는 크기가 아니라 증상이다** — "게스트만·배포본에서만·데미지만 0"이라
#   홀드 연사(`auto_fire_gap_s`)를 검증하러 온 사람이 F1로 레벨을 올린 직후 쏘면 **그 수정이 실패한
#   것처럼 보인다.** 도구가 자기 측정을 오염시킨다. 판 도중 레벨업(+1)도 같은 창을 만들지만 MAX는
#   델타가 몇 배라 창 안에서 깨지는 타수가 다르다.
func _level_row() -> Control:
	var row := _row("직업 레벨")
	var top := _max_level()
	var locked := GameState.in_chapter()
	if locked:
		# subjob_panel과 같은 관용구 — 판 도중 잠금이 다른 모든 거부의 원인이라 그것만 말한다.
		row.add_child(_btn("Lv %d (판 도중 잠금)" % _level, 180.0, true, Callable()))
		return row
	row.add_child(_btn("◀", STEP_W, _level <= 0, _apply_level.bind(_level - 1)))
	var v := Label.new()
	v.text = "Lv %d / %d" % [_level, top]
	v.custom_minimum_size = Vector2(VALUE_W, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.theme_type_variation = &"InfoLabel"
	row.add_child(v)
	row.add_child(_btn("▶", STEP_W, _level >= top, _apply_level.bind(_level + 1)))
	row.add_child(_btn("0", 34.0, false, _apply_level.bind(0)))
	var maxb := _btn("MAX", 44.0, false, _apply_level.bind(top))
	maxb.tooltip_text = "보유한 하위 직업 전부(계열 + 공유)의 EXP를 그 레벨의 누적 요구치로 세팅한다"
	row.add_child(maxb)
	return row


# 🔴 레벨은 저장하지 않고 EXP에서 파생된다(GameState 주석) — 그래서 레벨을 "세팅"하는 유일한 방법은
#   그 레벨의 **누적 요구치**를 EXP에 넣는 것이다. 레벨 필드를 따로 만들면 두 진실원이 생긴다.
func _apply_level(level: int) -> void:
	_level = clampi(level, 0, _max_level())
	var changed := false
	for sid: String in GameState.all_owned_sub_jobs():
		var e := _exp_for(sid, _level)
		if int(GameState.sub_job_exp.get(sid, -1)) != e:
			GameState.sub_job_exp[sid] = e
			changed = true
	if changed:
		_growth_dirty()
	_commit_save()
	_refresh()


# --- 무기 (그 직업이 들 수 있는 장비 + 강화 레벨) ---

func _weapon_rows() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	var first := true
	for eid: String in _weapon_ids():
		var e := GameState.equip_def(eid)
		if e == null:
			continue
		var row := _row("무기" if first else "")
		first = false
		var lv := maxi(GameState.equip_level(eid), 0)  # -1(미보유)은 0으로 보여준다 — 누르면 그 레벨로 지급된다
		var nm := Label.new()
		nm.text = e.display_name if not e.display_name.is_empty() else eid
		nm.custom_minimum_size = Vector2(NAME_W, 0)
		nm.clip_text = true
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.theme_type_variation = &"InfoLabel"
		row.add_child(nm)
		row.add_child(_btn("◀", STEP_W, lv <= 0, _set_equip_level.bind(eid, lv - 1)))
		var v := Label.new()
		v.text = "+%d / %d" % [lv, e.max_level]
		v.custom_minimum_size = Vector2(VALUE_W, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.theme_type_variation = &"InfoLabel"
		row.add_child(v)
		row.add_child(_btn("▶", STEP_W, lv >= e.max_level, _set_equip_level.bind(eid, lv + 1)))
		var equipped := GameState.equipped_id(e.slot()) == eid
		var eq := _btn("장착됨" if equipped else "장착", ACT_W, equipped, _equip_now.bind(eid))
		eq.tooltip_text = "미보유면 즉시 지급 후 착용한다 (강화 레벨은 위 ◀▶ 값)"
		row.add_child(eq)
		box.add_child(row)
	return box


# 현재 직업이 들 수 있는 장비 — 규칙은 GameState.can_job_equip 단일 소스(rules §3)를 그대로 쓴다.
func _weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for eid: String in GameState.equipment_ids():
		var e := GameState.equip_def(eid)
		if e != null and GameState.can_job_equip(GameState.selected_job_id, e):
			out.append(eid)
	return out


func _set_equip_level(eid: String, level: int) -> void:
	if not _own_equip(eid, level):
		return
	_inventory_dirty()
	_commit_save()
	_refresh()


func _equip_now(eid: String) -> void:
	var e := GameState.equip_def(eid)
	if e == null:
		_notify("모르는 장비입니다 — data/equipment 확인")
		return
	var lv := maxi(GameState.equip_level(eid), 0)
	if not _own_equip(eid, lv):
		return
	GameState.equip(eid)  # 착용 규칙(직업 귀속)은 GameState가 판정한다 + inventory_changed까지 emit
	if GameState.equipped_id(e.slot()) != eid:
		_notify("착용에 실패했습니다 — 이 직업이 들 수 없는 장비입니다")
		return
	_commit_save()
	_refresh()


# 보유 + 강화 레벨 세팅. 🔴 임의 레벨을 넣는 공개 API가 없어(upgrade_equipment는 골드 차감 +1단계)
#   `owned_equipment`를 직접 쓴다 — **디버그 전용**이고, 레벨은 `EquipDef.max_level`로 clamp한다
#   (그러지 않으면 내 표시가 호스트의 `max_equip_stats` clamp보다 커져 "보이는 스탯 ≠ 판정 스탯"이 된다).
func _own_equip(eid: String, level: int) -> bool:
	var e := GameState.equip_def(eid)
	if e == null:
		_notify("모르는 장비입니다 — data/equipment 확인")
		return false
	# 창고에 있으면 먼저 가방으로 — add_equipment는 창고 보유분을 새로 만들지 않는다(id당 1개 규약).
	if GameState.storage_equipment.has(eid):
		GameState.withdraw_equipment(eid)
	GameState.add_equipment(eid)  # allowlist 통과 + 미보유일 때만 생성(멱등)
	GameState.owned_equipment[eid] = clampi(level, 0, e.max_level)
	return true


# --- 골드·재료·도면 지급 ---

func _grant_row() -> Control:
	var row := _row("지급")
	var all := _btn("전부 열기", 96.0, false, _grant_all)
	all.tooltip_text = "골드·재료·도면 + 모든 장비 만강화 + 모든 하위 직업 + 만렙 — 한 번에"
	row.add_child(all)
	var b := _btn("골드·재료·도면", 132.0, false, _grant_resources)
	b.tooltip_text = "골드 %d · 재료 각 %d · 도면 전부 — 제작대에서 바로 만들 수 있게" % [GRANT_GOLD, GRANT_MATERIAL]
	row.add_child(b)
	var gold := Label.new()
	gold.text = "현재 %d G" % GameState.gold
	gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold.theme_type_variation = &"GoldLabel"
	row.add_child(gold)
	return row


func _grant_resources() -> void:
	GameState.add_gold(GRANT_GOLD)
	for mid: String in GameState.material_ids():
		GameState.add_material(mid, GRANT_MATERIAL)
	for rid: String in GameState.recipe_ids():
		GameState.unlock_blueprint(rid)
	_commit_save()
	_refresh()


# 🔴 **아무것도 제한하지 않는다 — 이 도구는 "다 열려 있어야" 도구다** (사용자 확정 2026-07-28).
#   여기서 만드는 상태는 새 능력이 아니라 **정직하게 도달 가능한 최대치로 점프**하는 것이고, 전부
#   호스트의 기존 clamp·대조(`can_job_equip`·`max_equip_stats`·`max_level_stats`·`traits_of`) 안에
#   떨어진다(netreview 확인 — "보이는 스탯 ≠ 판정 스탯"은 안 생긴다).
# ⚠ **공유 하위 직업(도굴꾼)도 준다.** rules §2가 기록해 둔 수용 표면(G_STATS `"ss"` 보유 미검증)이
#   이 패널로 **미변조 클라에서도 도달 가능**해진다는 뜻이다 — 조작 클라 한 명이 파티 드랍(최대값)을
#   올릴 수 있고 그건 상대 세이브로 들어간다. 2인 협동·심사 기간이라 **수용한 판단**이고, 4인/PvP
#   게이트에서 보유 검증을 넣을 때 이 줄을 함께 본다.
# ⚠ 장비는 **직업 귀속과 무관하게 전부** 보유시킨다 — 보유는 자유이고 착용만 `can_job_equip`이 막는다
#   (rules §3 "해제는 파기가 아니다: 착용만 풀고 소유는 건드리지 않는다"와 같은 자리).
func _grant_all() -> void:
	GameState.add_gold(GRANT_GOLD)
	for mid: String in GameState.material_ids():
		GameState.add_material(mid, GRANT_MATERIAL)
	for rid: String in GameState.recipe_ids():
		GameState.unlock_blueprint(rid)
	for eid: String in GameState.equipment_ids():
		var e := GameState.equip_def(eid)
		if e != null:
			_own_equip(eid, e.max_level)
	for sid: String in GameState.sub_job_ids():
		_ensure_sub_job(sid)
	# 만렙은 마지막에 — `_apply_level`이 **방금 부여한 하위 직업 전부**의 EXP를 한 번에 맞춘다
	# (`all_owned_sub_jobs`를 도므로 순서가 뒤집히면 새로 연 갈래가 Lv0로 남는다).
	# ⚠ 판 도중이면 `_apply_level`이 레벨 행과 같은 이유로 위험하지만(편도 전이 구간), 이 버튼은
	#   레벨 행과 달리 마을 전용이 아니다 — 대신 `_level_row`가 잠겨 있어 판 안에서는 눌러도
	#   `_max_level()`이 현재값과 같아 변화가 없는 것이 보통이다. 실기 절차는 "마을에서 세팅"이다.
	_apply_level(_max_level())
	# ⚠ 안내는 **맨 마지막**이다 — `_notify`가 곧바로 `_refresh()`를 부르고 그 안에서 `_pending_notice`가
	#   소비되므로, 앞에 두면 뒤따르는 `_apply_level`의 갱신이 문구를 지운다.
	_notify("전부 열었습니다 — 장비 만강화 · 하위 직업 전부 · 만렙")


# --- 시험장 (자리만) ---

func _arena_row() -> Control:
	var row := _row("시험장")
	# 🔴 씬을 직접 바꾸지 않는다 — EventBus로 **요청만** 하고 그 씬의 SceneFlow(호스트 권한 경로)가
	#   `Net.is_host()` + `GameState.is_valid_stage` 가드를 지나 결정한다(rules §1: 게스트는 상태를
	#   확정하지 않는다). 그래서 게스트가 눌러도 조용히 아무 일도 안 일어난다.
	# ⚠ **마을에서만** 가능하다 — 판 도중엔 `_departed`가 이미 true라 요청이 무시된다. 눌러도 안 되는
	#   버튼을 살려 두면 "고장난 것"으로 읽히므로 비활성 + 사유를 툴팁에 적는다.
	var in_chapter := GameState.in_chapter()
	var b := _btn("시험장으로", 180.0, in_chapter, func() -> void:
		EventBus.debug_stage_requested.emit(ARENA_CHAPTER_ID, 0)
		close())
	b.tooltip_text = ("판 도중에는 이동할 수 없습니다 — 마을에서 누르세요"
		if in_chapter else "허수아비 4마리 + 거리 눈금(50·150·300·480px). 방장만 이동할 수 있습니다")
	row.add_child(b)
	return row


# --- 하위 직업 보유/EXP 헬퍼 ---

# 이 하위 직업을 **즉시 보유**시킨다(이 도구의 목적). 이미 보유면 그대로 둔다(EXP를 지우지 않게).
# 🔴 보유를 부여하는 공개 API가 없어 `sub_job_exp`를 직접 쓴다 — **디버그 전용**이고,
#   넣는 값은 `add_exp`가 만들었을 값과 정확히 같다(그 레벨의 누적 요구치 = 곡선 그대로).
#   ⚠ 리드에게 core API(`GameState.debug_grant_sub_job(id, level)`)를 제안했다 — 생기면 이걸 갈아끼운다.
func _ensure_sub_job(sid: String) -> bool:
	var d := GameState.sub_job_def(sid)
	if d == null:
		return false
	if GameState.has_sub_job(sid):
		return true
	GameState.sub_job_exp[sid] = _exp_for(sid, _level)
	_growth_dirty()
	return true


# 그 하위 직업의 레벨 n 누적 요구치. 곡선은 **그 갈래의 계열** 기준(GameState.sub_job_level과 같은 소스)
# — 선택 직업 기준으로 구하면 공유 갈래의 레벨 표시가 갈라진다.
func _exp_for(sid: String, level: int) -> int:
	var d := GameState.sub_job_def(sid)
	if d == null:
		return 0
	var curve := GameState.exp_curve(d.series_id)
	var top := mini(d.max_level, curve.size() - 1)
	return int(curve[clampi(level, 0, maxi(top, 0))])


# 스테퍼 상한 = 이 계열 + 공유 갈래가 도달할 수 있는 최대 레벨(곡선 길이와 max_level 중 작은 쪽).
func _max_level() -> int:
	var top := 0
	for sid: String in _slot_candidates():
		var d := GameState.sub_job_def(sid)
		if d == null:
			continue
		top = maxi(top, mini(d.max_level, GameState.exp_curve(d.series_id).size() - 1))
	return maxi(top, 0)


func _current_level() -> int:
	if GameState.main_sub_job() != null:
		return GameState.sub_job_level(GameState.main_sub_job_id)
	return 0


# --- 갱신 훅 ---
# 🔴 GameState의 필드를 직접 쓴 뒤에는 **바꾼 쪽이 알린다**(rules §1 "필드를 붙이는 쪽이 emit").
#   growth_changed → PeerSync 재공지(G_STATS)·HUD·훈련소 패널 / inventory_changed → 같은 경로 + 인벤 UI.
#   공개 API를 지나는 조작(add_gold·equip·set_sub_slot 등)은 GameState가 이미 쏘므로 여기서 또 쏘지 않는다.

func _growth_dirty() -> void:
	EventBus.growth_changed.emit()


func _inventory_dirty() -> void:
	EventBus.inventory_changed.emit()


# --- 위젯 헬퍼 (레이아웃은 컨테이너 주도 — position/size 매직넘버 없음) ---

func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var lbl := Label.new()
	lbl.text = title
	lbl.custom_minimum_size = Vector2(TITLE_W, 0)  # 줄마다 제목 폭을 맞춰 세로 정렬만 시킨다
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.theme_type_variation = &"SectionLabel"
	row.add_child(lbl)
	return row


func _btn(text: String, min_w: float, disabled: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 0)
	b.theme_type_variation = &"SmallButton"
	b.disabled = disabled
	b.clip_text = true
	if not disabled and on_press.is_valid():
		b.pressed.connect(on_press)
	return b


# 하위 직업 버튼 — 이름 + 보유/레벨. 미보유는 "+"로 "누르면 지급된다"를 말한다.
func _sub_btn(sid: String, is_current: bool, disabled: bool, on_press: Callable) -> Button:
	var d := GameState.sub_job_def(sid)
	var nm := d.display_name if d != null and not d.display_name.is_empty() else sid
	var owned := GameState.has_sub_job(sid)
	var label := nm
	if owned:
		label += " %d" % GameState.sub_job_level(sid)
	else:
		label += " +"
	if is_current:
		label += " ✓"
	var b := _btn(label, BTN_W, disabled, on_press)
	var lines: Array[String] = []
	var kind := "공유 갈래 — 서브 전용" if d != null and d.is_shared() else "계열 갈래"
	lines.append("%s (%s)" % [nm, kind])
	if owned:
		lines.append("보유함 · Lv %d" % GameState.sub_job_level(sid))
	else:
		lines.append("미보유 — 누르면 Lv %d로 즉시 지급" % _level)
	if d != null and not d.description.is_empty():
		lines.append(d.description)
	b.tooltip_text = "\n".join(lines)
	return b


func _clear(container: Node) -> void:
	for c: Node in container.get_children():
		container.remove_child(c)  # 즉시 떼어낸다 — queue_free만 하면 같은 프레임 재생성분과 겹쳐 보인다
		c.queue_free()


func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근(craft_panel 미러).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
