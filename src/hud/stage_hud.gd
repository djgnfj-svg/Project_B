extends CanvasLayer
# 인게임 공용 HUD — 방 코드·초대 복사 + HP 바 + 상태 배너(관전/클리어/전멸).
# 마을·스테이지가 인스턴스로 문다 (rules §2 src/hud). HP는 php 확정만 반영 (§3 — 로컬 선적용 금지).

const INVITE_FX_TIME := 1.5  # 복사 피드백 표시 시간 (연출값)
const TOAST_TIME := 2.5  # 토스트 1건 표시 시간 (연출값) — 도면·레벨업·해금 공용
const TOAST_QUEUE_MAX := 3  # 동시 발생분 대기 상한 (넘치면 가장 오래된 걸 버려 최신 소식이 보이게)
const TOAST_COLOR_UNLOCK := Color(1, 0.85, 0.3, 1)  # 도면·하위 직업 해금 = 금색
const TOAST_COLOR_LEVEL := Color(0.6, 1, 0.7, 1)  # 레벨업 = 연두
const PHASE_BANNER_TIME := 2.0  # 페이즈2 배너 표시 시간 (연출값)
const PING_LABEL_REFRESH_S := 0.5  # 핑 표시 갱신 주기(s) — Net의 측정 주기와 같게 (더 자주 그려도 값이 안 바뀜)
# 구르기 쿨 표시 색 — 준비됨(밝은 흰)/쿨 중(흐림). 연출값이라 스크립트 const (rules §0 예외).
const ROLL_READY_COLOR := Color(1, 1, 1, 1)
const ROLL_COOLING_COLOR := Color(0.62, 0.70, 0.82, 1)
const INV_ICON_SIZE := 16.0  # 인벤 아이콘 표시 크기(px)
# UI 오버레이 조합 — HUD가 설정/인벤 패널을 무는 것은 조합(rules §0 예외). class_name 대신 preload(§0).
const SettingsPanelScene := preload("res://src/ui/settings_panel.tscn")
const InventoryPanelScene := preload("res://src/ui/inventory_panel.tscn")
# 개발용 디버그 패널(F1) — `?debug=1`(웹) 또는 비웹(에디터·네이티브)에서만 만든다.
# 스크립트를 따로 preload하는 이유 = **게이트 판정을 인스턴스 없이** 물어보기 위해서다(panel_enabled는 static).
const DebugPanelScene := preload("res://src/ui/debug_panel.tscn")
const DebugPanel := preload("res://src/ui/debug_panel.gd")
const UiTheme := preload("res://src/ui/ui_theme.gd")  # UI 톤 단일 소스 (로비·패널과 같은 테마)
const GOLD_TEX := preload("res://assets/sprites/items/gold.png")  # 골드 인벤 아이콘 (DropField와 같은 소스)

var _invite_fx_seq: int = 0  # 복사 연타 시 이전 타이머가 새 피드백을 지우지 않게
var _toast_queue: Array[Dictionary] = []  # 대기 중 토스트 — 같은 프레임에 여러 건(레벨업+해금)이 와도 차례로 보인다
var _toast_busy: bool = false  # 현재 한 건을 표시 중인가 (타이머 만료 시 다음 것으로 넘어감)
var _phase_banner_seq: int = 0  # 페이즈 배너 자동 숨김 타이머 경합 가드 (다른 배너가 덮으면 안 지움)
var _inv_panel: CanvasLayer = null  # I키 인벤 창 — HUD가 무는 조합(어디서나 열림)
var _debug_panel: CanvasLayer = null  # F1 디버그 창 — 게이트가 닫혀 있으면 null(만들지도 않는다)
var _ping_refresh_accum: float = 0.0  # 핑 표시 갱신 누산
var _local_player: Node = null  # 구르기 쿨 표시용 로컬 아바타 캐시 (씬/스폰마다 바뀌므로 유효성 재확인)
var _roll_ready: bool = true  # 구르기 준비 상태 — 바뀔 때만 색을 덮어쓴다(매 프레임 override는 WASM에서 낭비)

@onready var _room_label: Label = $RoomCode
@onready var _progress: Label = $Progress
@onready var _invite_btn: Button = $InviteBtn
@onready var _settings_btn: Button = $SettingsBtn
@onready var _hp_bar: ProgressBar = $HpBar
@onready var _hp_label: Label = $HpBar/HpLabel
@onready var _partner_label: Label = $PartnerHp
@onready var _gold_bar: HBoxContainer = $GoldBar
@onready var _banner: Label = $Banner
@onready var _toast: Label = $Toast
@onready var _growth: Control = $Growth
@onready var _level_label: Label = $Growth/LevelLabel
@onready var _exp_bar: ProgressBar = $Growth/ExpBar
@onready var _roll_bar: ProgressBar = $RollBar
@onready var _roll_label: Label = $RollBar/RollLabel


func _ready() -> void:
	# 루트가 CanvasLayer라 theme 프로퍼티가 없다 → Control 자식마다 건다(손자는 상속).
	# ⚠ 자식 CanvasLayer(설정·인벤 패널)는 건너뛴다 — 그쪽은 자기 루트에서 직접 건다.
	UiTheme.apply_to_children(self)
	# 바 채움색만 바마다 다르다(바탕·모서리는 테마 공용) — 색은 ui_theme 팔레트에서 온다.
	_hp_bar.add_theme_stylebox_override(&"fill", UiTheme.bar_fill(UiTheme.HP_FILL))
	_exp_bar.add_theme_stylebox_override(&"fill", UiTheme.bar_fill(UiTheme.EXP_FILL))
	_roll_bar.add_theme_stylebox_override(&"fill", UiTheme.bar_fill(UiTheme.ROLL_FILL))
	_update_room_label()
	_progress.text = GameState.progress_label()  # 마을(비챕터)은 빈 문자열 = 표시 없음
	_invite_btn.pressed.connect(_on_invite_pressed)
	var settings := SettingsPanelScene.instantiate()
	add_child(settings)  # HUD(CanvasLayer) 아래 CanvasLayer(layer 10) — HUD 위 오버레이
	_settings_btn.pressed.connect(settings.open)
	# I키 인벤 창 — HUD가 물어 어디서나(스테이지·마을) I로 토글. 여는 키는 HUD가 소비(아래 _unhandled_input).
	_inv_panel = InventoryPanelScene.instantiate() as CanvasLayer
	add_child(_inv_panel)
	# F1 디버그 창 — 인벤과 같은 조합(HUD가 물고, 여는 키는 HUD가 소비). 게이트가 닫히면 아예 안 만든다.
	if DebugPanel.panel_enabled():
		_debug_panel = DebugPanelScene.instantiate() as CanvasLayer
		add_child(_debug_panel)
	var max_hp := GameState.selected_job().max_hp
	_hp_bar.max_value = float(max_hp)
	_set_own_hp(max_hp)
	_partner_label.text = ""
	_banner.visible = false
	_toast.visible = false
	# 인벤 카운트 (드랍 픽업 반영) — 각 클라 자기 인벤. 본격 인벤 UI는 슬라이스 2, 여기선 최소 표시.
	EventBus.inventory_changed.connect(_refresh_inv)
	_refresh_inv()
	# 도면 획득 토스트 — blueprint_unlocked(도면 픽업 확정)마다 잠깐 표시 후 자동 소멸.
	# 상태 배너(관전/클리어/전멸)와 독립 노드라 서로 안 덮는다. 각 클라 자기 인벤 기준.
	EventBus.blueprint_unlocked.connect(_on_blueprint_unlocked)
	EventBus.player_hp_confirmed.connect(_on_player_hp)
	# 직업 레벨·EXP 표기 (GDD v1.8 성장축) — 전부 각 클라 자기 GameState 읽기 전용, 네트워크 0.
	# growth_changed = 레벨/메인 변동(라벨+바 전체 갱신) · exp_changed = 매 적립(바만, 가벼운 훅).
	EventBus.growth_changed.connect(_refresh_growth)
	EventBus.exp_changed.connect(_on_exp_changed)
	EventBus.sub_job_level_up.connect(_on_sub_job_level_up)
	EventBus.sub_job_unlocked.connect(_on_sub_job_unlocked)
	_refresh_growth()
	# 페이즈2 돌입 배너 — 호스트 확정, MobSync가 게스트에 G_BOSS_PHASE 중계. 잠깐 표시 후 자동 숨김.
	EventBus.boss_phase_changed.connect(_on_boss_phase)
	# 마지막 칸 클리어 = 챕터 완주 — 각 클라가 자기 GameState(G_SCENE 검증으로 동기)로 판별
	EventBus.stage_cleared.connect(func() -> void: _show_banner(
		"챕터 클리어! 마을로 귀환합니다" if GameState.is_last_stage() else "스테이지 클리어!"))
	EventBus.stage_wiped.connect(func() -> void: _show_banner("전멸 — 마을로 귀환합니다 (챕터 처음부터)"))


# 방 코드 줄에 왕복 지연(핑)·프레임레이트를 같이 띄운다 — 별도 노드를 안 만들어 레이아웃/클릭 리스크가 없다.
# 핑은 게스트가 겪는 회피 창 손실의 크기와 직결된다(지연 보상 §3) — 렉이 체감될 때 원인을 눈으로 확인하는 창구.
# 🔴 FPS를 핑과 **같은 줄에** 두는 이유: "렉이 심하다"는 신고에서 네트워크(핑)와 렌더(FPS)는 원인도
#   처방도 완전히 다른데 체감이 똑같다. 둘을 나란히 보면 어느 쪽인지 한눈에 갈린다 — 조작이 굼뜬데
#   핑이 낮으면 웹 빌드 프레임 문제이고, 핑만 높으면 릴레이 경로 문제다(2026-07-26 진단).
# 아직 왕복 측정 전이거나 솔로면 핑은 생략(0 = 표시 안 함). FPS는 솔로에서도 항상 띄운다.
func _update_room_label() -> void:
	var text := "방 %s · %s" % [Net.room_code, "호스트" if Net.is_host() else "게스트"]
	var rtt := Net.display_rtt_ms()
	if rtt > 0.0:
		# 경로를 핑 옆에 같이 박는다 — P2P 직결이 실제로 뚫렸는지는 **핑 숫자만으론 못 읽는다**
		# (릴레이 폴백도 조용히 잘 돈다). 실기에서 "직결"이 떠야 릴레이를 걷어낸 게 확인된 것.
		text += " · 핑 %dms(%s)" % [int(roundf(rtt)), "직결" if Net.p2p_active() else "릴레이"]
	text += " · %dfps" % Engine.get_frames_per_second()
	_room_label.text = text


func _process(delta: float) -> void:
	_refresh_roll_bar()  # 매 프레임 — 쿨은 0.8s 미만이라 0.5s 주기로 그리면 눈금이 뛴다
	_ping_refresh_accum += delta
	if _ping_refresh_accum < PING_LABEL_REFRESH_S:
		return
	_ping_refresh_accum = 0.0
	_update_room_label()


# 구르기 쿨 표시 — **표시 전용·네트워크 0.** 로컬 아바타의 읽기 접근자(roll_cooldown_ratio)만 본다.
# 바는 "차오르면 준비됨"(value = 1 − 남은비율) — 비어 가는 바보다 "지금 구를 수 있나"가 한눈에 읽힌다.
# 로컬 플레이어가 아직 없으면(스폰 전·로비) 숨긴다 — 빈 바가 떠 있으면 버그처럼 보인다.
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
		_roll_label.add_theme_color_override(
			&"font_color", ROLL_READY_COLOR if ready else ROLL_COOLING_COLOR)


# 로컬 아바타 찾기 — 씬 전환·재스폰마다 노드가 바뀌므로 캐시를 유효성으로 검증하고 필요할 때만 다시 스캔한다.
# ⚠ 씬 스왑 프레임엔 이전 씬 노드가 그룹에 남는다(rules §5) — 캐시가 무효해지면 그 프레임에 옛 노드를
#   잡을 수 있지만, 표시 전용이고 다음 프레임에 새 노드로 교체되므로 무해하다.
func _local_player_node() -> Node:
	if is_instance_valid(_local_player) and _local_player.is_inside_tree():
		return _local_player
	_local_player = null
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n.get("is_local") == true and n.has_method("roll_cooldown_ratio"):
			_local_player = n
			break
	return _local_player


# I키로 인벤 창 토글 — HUD가 확실히 소비(패널은 I를 안 먹는다, 중복 방지). Esc 닫기는 패널 자체.
# 🔴 F1(디버그 패널)도 **여기 한 곳에서만** 소비한다 — 패널이 같이 먹으면 열자마자 닫힌다(rules §5).
#   InputMap 액션이 아니라 raw 키로 본다: project.godot(입력 맵)은 리드 몫이고, F1은 리바인드 대상이
#   아닌 개발용 키라 액션을 늘릴 이유가 없다. 게이트가 닫혀 패널이 없으면 키를 **소비하지 않는다**.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if _inv_panel != null:
			_inv_panel.call("toggle")
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1 and _debug_panel != null:
		_debug_panel.call("toggle")
		get_viewport().set_input_as_handled()


func _on_player_hp(peer_id: int, hp: int) -> void:
	if peer_id == Net.my_id:
		_set_own_hp(hp)
		if hp <= 0:
			_show_banner("관전 중 — 스테이지 클리어 시 부활")
		elif _banner.visible and _banner.text.begins_with("관전"):
			_banner.visible = false
	else:
		_partner_label.text = "파트너 HP %d" % maxi(hp, 0) if hp > 0 else "파트너 사망"


# 골드만 우하단 아이콘+숫자 표시 (inventory_changed 훅). 재료·장비는 I키 인벤 창(inventory_panel).
# 재구성 = 옛 항목 즉시 remove_child(중복 프레임 방지) 후 재생성.
func _refresh_inv() -> void:
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


# 페이즈2 돌입 배너 — 상태 배너(관전/클리어/전멸)와 같은 _banner 노드 재사용, 잠시 후 자동 숨김.
# 자동 숨김은 그 사이 다른 배너가 텍스트를 덮지 않았을 때만(seq + 텍스트 확인) — 클리어/관전 배너 보존.
func _on_boss_phase(phase: int) -> void:
	if phase < 2:
		return
	_show_banner("페이즈 2!")
	_phase_banner_seq += 1
	var seq := _phase_banner_seq
	get_tree().create_timer(PHASE_BANNER_TIME).timeout.connect(
		func() -> void:
			if is_instance_valid(_banner) and seq == _phase_banner_seq and _banner.text == "페이즈 2!":
				_banner.visible = false)


func _set_own_hp(hp: int) -> void:
	_hp_bar.value = float(maxi(hp, 0))
	_hp_label.text = "HP %d" % maxi(hp, 0)


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true


# 도면 획득 토스트 — 레시피명을 잠깐 띄운다. 표시는 공용 토스트 큐가 맡는다.
func _on_blueprint_unlocked(recipe_id: String) -> void:
	var r := GameState.recipe_def(recipe_id)
	var disp := r.display_name if r != null else "새 설계도"  # 내부 id 노출 방지 (allowlist 통과분만 오므로 실질 폴백 안 씀)
	_push_toast("설계도 획득! — %s" % disp, TOAST_COLOR_UNLOCK)


# 하위 직업 레벨업 — 계열 보유분에 EXP가 동시 적립되므로 한 킬에 여러 건이 올 수 있다(큐가 차례로 보여준다).
func _on_sub_job_level_up(sub_id: String, level: int) -> void:
	_push_toast("레벨 업! — %s Lv%d" % [_sub_job_name(sub_id), level], TOAST_COLOR_LEVEL)


# 다음 하위 직업 해금 — 레벨업과 같은 프레임에 오는 게 정상(레벨업이 해금을 트리거)이라 큐로 둘 다 보인다.
func _on_sub_job_unlocked(sub_id: String) -> void:
	_push_toast("새 하위 직업 해금! — %s" % _sub_job_name(sub_id), TOAST_COLOR_UNLOCK)


func _sub_job_name(sub_id: String) -> String:
	var d := GameState.sub_job_def(sub_id)
	return d.display_name if d != null and not d.display_name.is_empty() else "새 하위 직업"  # 내부 id 노출 방지


# 공용 토스트 큐 — 도면·레벨업·해금이 같은 Toast 노드를 차례로 쓴다(노드를 늘리지 않아 레이아웃/클릭 리스크 0).
# 같은 프레임에 여러 건이 오면 앞의 것이 즉시 덮여 안 보이던 문제를 큐로 해결. 상태 배너(_banner)와는 여전히 독립.
func _push_toast(text: String, color: Color) -> void:
	if _toast_queue.size() >= TOAST_QUEUE_MAX:
		_toast_queue.pop_front()
	_toast_queue.append({"text": text, "color": color})
	if not _toast_busy:
		_advance_toast()


func _advance_toast() -> void:
	if _toast_queue.is_empty():
		_toast_busy = false
		_toast.visible = false
		return
	_toast_busy = true
	var m: Dictionary = _toast_queue.pop_front()
	var col: Color = m["color"]
	_toast.text = str(m["text"])
	_toast.add_theme_color_override(&"font_color", col)
	_toast.visible = true
	# 타이머 만료 → 다음 대기분(없으면 숨김). HUD가 씬 전환으로 사라지면 연결이 자동 해제된다.
	get_tree().create_timer(TOAST_TIME).timeout.connect(_advance_toast)


# 하위 직업 이름 + 레벨 + EXP 진행 — 성장축이 없는 계열(main_sub_job() == null: 데이터 미작성 궁수·법사)은
# 표기 전체를 숨긴다(빈 라벨이 떠 있으면 버그처럼 보인다). 만레벨(need == 0)은 바를 가득 채우고 "MAX".
func _refresh_growth() -> void:
	var d := GameState.main_sub_job()
	if d == null:
		_growth.visible = false
		return
	_growth.visible = true
	var p := GameState.main_exp_progress()
	var lv := int(p["level"])
	var need := int(p["need"])
	var cur := int(p["cur"])
	if need <= 0:
		_level_label.text = "%s Lv%d · MAX" % [d.display_name, lv]
	else:
		_level_label.text = "%s Lv%d · %d/%d" % [d.display_name, lv, cur, need]
	_set_exp_bar(cur, need)


# 매 적립 훅 — 인자(cur/need)는 GameState.main_exp_progress()와 같은 값이라 _refresh_growth로 일원화한다
# (표기 문구를 두 곳에서 만들면 갈라진다). 비용 = 킬당 Dictionary 하나 + 짧은 곡선 루프.
func _on_exp_changed(_cur: int, _need: int) -> void:
	_refresh_growth()


func _set_exp_bar(cur: int, need: int) -> void:
	if need <= 0:  # 만레벨 — 바는 가득 찬 상태로 남긴다(사라지면 "뭔가 없어졌다"로 읽힌다)
		_exp_bar.max_value = 1.0
		_exp_bar.value = 1.0
		return
	_exp_bar.max_value = float(need)
	_exp_bar.value = float(clampi(cur, 0, need))


# 초대 코드(방 코드) 클립보드 복사 — URL이 아니라 코드만 준다 (사용자 확정 2026-07-22:
# 로컬/브라우저 환경마다 URL 링크가 안 통하는 경우가 있어, 받는 쪽이 로비에 코드를 치는 흐름이 확실)
func _on_invite_pressed() -> void:
	DisplayServer.clipboard_set(Net.room_code)
	print("[PB] invite code copied: %s" % Net.room_code)
	_invite_btn.text = "복사됨! (%s)" % Net.room_code
	_invite_fx_seq += 1
	var seq := _invite_fx_seq
	get_tree().create_timer(INVITE_FX_TIME).timeout.connect(
		func() -> void:
			if is_instance_valid(_invite_btn) and seq == _invite_fx_seq:
				_invite_btn.text = "초대 코드 복사")
