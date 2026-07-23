extends CanvasLayer
# 인게임 공용 HUD — 방 코드·초대 복사 + HP 바 + 상태 배너(관전/클리어/전멸).
# 마을·스테이지가 인스턴스로 문다 (rules §2 src/hud). HP는 php 확정만 반영 (§3 — 로컬 선적용 금지).

const INVITE_FX_TIME := 1.5  # 복사 피드백 표시 시간 (연출값)
const BLUEPRINT_TOAST_TIME := 2.5  # 도면 획득 토스트 표시 시간 (연출값)
const INV_ICON_SIZE := 16.0  # 인벤 아이콘 표시 크기(px)
# UI 오버레이 조합 — HUD가 설정/인벤 패널을 무는 것은 조합(rules §0 예외). class_name 대신 preload(§0).
const SettingsPanelScene := preload("res://src/ui/settings_panel.tscn")
const InventoryPanelScene := preload("res://src/ui/inventory_panel.tscn")
const GOLD_TEX := preload("res://assets/sprites/items/gold.png")  # 골드 인벤 아이콘 (DropField와 같은 소스)

var _invite_fx_seq: int = 0  # 복사 연타 시 이전 타이머가 새 피드백을 지우지 않게
var _toast_seq: int = 0  # 도면 연속 획득 시 이전 타이머가 새 토스트를 지우지 않게
var _inv_panel: CanvasLayer = null  # I키 인벤 창 — HUD가 무는 조합(어디서나 열림)

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


func _ready() -> void:
	_room_label.text = "방 %s · %s" % [
		Net.room_code, "호스트" if Net.is_host() else "게스트"]
	_progress.text = GameState.progress_label()  # 마을(비챕터)은 빈 문자열 = 표시 없음
	_invite_btn.pressed.connect(_on_invite_pressed)
	var settings := SettingsPanelScene.instantiate()
	add_child(settings)  # HUD(CanvasLayer) 아래 CanvasLayer(layer 10) — HUD 위 오버레이
	_settings_btn.pressed.connect(settings.open)
	# I키 인벤 창 — HUD가 물어 어디서나(스테이지·마을) I로 토글. 여는 키는 HUD가 소비(아래 _unhandled_input).
	_inv_panel = InventoryPanelScene.instantiate() as CanvasLayer
	add_child(_inv_panel)
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
	# 마지막 칸 클리어 = 챕터 완주 — 각 클라가 자기 GameState(G_SCENE 검증으로 동기)로 판별
	EventBus.stage_cleared.connect(func() -> void: _show_banner(
		"챕터 클리어! 마을로 귀환합니다" if GameState.is_last_stage() else "스테이지 클리어!"))
	EventBus.stage_wiped.connect(func() -> void: _show_banner("전멸 — 마을로 귀환합니다 (챕터 처음부터)"))


# I키로 인벤 창 토글 — HUD가 확실히 소비(패널은 I를 안 먹는다, 중복 방지). Esc 닫기는 패널 자체.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if _inv_panel != null:
			_inv_panel.call("toggle")
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
	lbl.add_theme_color_override(&"font_color", Color(1, 0.85, 0.3, 1))  # 골드 색
	lbl.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override(&"outline_size", 3)
	_gold_bar.add_child(lbl)


func _set_own_hp(hp: int) -> void:
	_hp_bar.value = float(maxi(hp, 0))
	_hp_label.text = "HP %d" % maxi(hp, 0)


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true


# 도면 획득 토스트 — 레시피명을 잠깐 띄우고 타이머로 소멸. 연속 획득 시 seq로 마지막 것만 유지.
func _on_blueprint_unlocked(recipe_id: String) -> void:
	var r := GameState.recipe_def(recipe_id)
	var disp := r.display_name if r != null else "새 설계도"  # 내부 id 노출 방지 (allowlist 통과분만 오므로 실질 폴백 안 씀)
	_toast.text = "설계도 획득! — %s" % disp
	_toast.visible = true
	_toast_seq += 1
	var seq := _toast_seq
	get_tree().create_timer(BLUEPRINT_TOAST_TIME).timeout.connect(
		func() -> void:
			if is_instance_valid(_toast) and seq == _toast_seq:
				_toast.visible = false)


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
