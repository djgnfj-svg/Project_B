extends CanvasLayer
# 인게임 공용 HUD — 방 코드·초대 복사 + HP 바 + 상태 배너(관전/클리어/전멸).
# 마을·스테이지가 인스턴스로 문다 (rules §2 src/hud). HP는 php 확정만 반영 (§3 — 로컬 선적용 금지).

const INVITE_FX_TIME := 1.5  # 복사 피드백 표시 시간 (연출값)
const BLUEPRINT_TOAST_TIME := 2.5  # 도면 획득 토스트 표시 시간 (연출값)
const INV_ICON_SIZE := 16.0  # 인벤 아이콘 표시 크기(px)
# UI 오버레이 조합 — HUD가 설정 패널을 무는 것은 조합(rules §0 예외). class_name 대신 preload(§0).
const SettingsPanelScene := preload("res://src/ui/settings_panel.tscn")
const GOLD_TEX := preload("res://assets/sprites/items/gold.png")  # 골드 인벤 아이콘 (DropField와 같은 소스)

var _invite_fx_seq: int = 0  # 복사 연타 시 이전 타이머가 새 피드백을 지우지 않게
var _toast_seq: int = 0  # 도면 연속 획득 시 이전 타이머가 새 토스트를 지우지 않게

@onready var _room_label: Label = $RoomCode
@onready var _progress: Label = $Progress
@onready var _invite_btn: Button = $InviteBtn
@onready var _settings_btn: Button = $SettingsBtn
@onready var _hp_bar: ProgressBar = $HpBar
@onready var _hp_label: Label = $HpBar/HpLabel
@onready var _partner_label: Label = $PartnerHp
@onready var _inv_bar: HBoxContainer = $InvBar
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


func _on_player_hp(peer_id: int, hp: int) -> void:
	if peer_id == Net.my_id:
		_set_own_hp(hp)
		if hp <= 0:
			_show_banner("관전 중 — 스테이지 클리어 시 부활")
		elif _banner.visible and _banner.text.begins_with("관전"):
			_banner.visible = false
	else:
		_partner_label.text = "파트너 HP %d" % maxi(hp, 0) if hp > 0 else "파트너 사망"


# 인벤 아이콘+숫자 좌하단 표시 (inventory_changed 훅) — 골드 먼저, 이후 보유 재료를 종류별로.
# 재구성 = 옛 항목 즉시 remove_child(중복 프레임 방지) 후 재생성. 픽업 빈도가 낮아 비용 무해.
func _refresh_inv() -> void:
	for c: Node in _inv_bar.get_children():
		_inv_bar.remove_child(c)
		c.queue_free()
	_add_inv_entry(GOLD_TEX, GameState.gold)
	for id: String in GameState.materials:
		var q := int(GameState.materials[id])
		if q <= 0:
			continue
		var m := GameState.material_def(id)
		_add_inv_entry(m.icon if m != null else null, q)


# 인벤 한 항목 = [아이콘][숫자] — 클릭 안 먹게 전부 mouse_filter IGNORE (rules §5 오버레이 함정 예방).
func _add_inv_entry(tex: Texture2D, count: int) -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	var tr := TextureRect.new()
	tr.texture = tex  # null이어도 안전 — 안 보일 뿐
	tr.custom_minimum_size = Vector2(INV_ICON_SIZE, INV_ICON_SIZE)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var lbl := Label.new()
	lbl.text = str(count)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override(&"outline_size", 3)
	box.add_child(lbl)
	_inv_bar.add_child(box)


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
