extends CanvasLayer
# 인게임 공용 HUD — 방 코드·초대 복사 + HP 바 + 상태 배너(관전/클리어/전멸).
# 마을·스테이지가 인스턴스로 문다 (rules §2 src/hud). HP는 php 확정만 반영 (§3 — 로컬 선적용 금지).

const INVITE_FX_TIME := 1.5  # 복사 피드백 표시 시간 (연출값)

var _invite_fx_seq: int = 0  # 복사 연타 시 이전 타이머가 새 피드백을 지우지 않게

@onready var _room_label: Label = $RoomCode
@onready var _invite_btn: Button = $InviteBtn
@onready var _hp_bar: ProgressBar = $HpBar
@onready var _hp_label: Label = $HpBar/HpLabel
@onready var _partner_label: Label = $PartnerHp
@onready var _banner: Label = $Banner


func _ready() -> void:
	_room_label.text = "방 %s · %s" % [
		Net.room_code, "호스트" if Net.is_host() else "게스트"]
	_invite_btn.pressed.connect(_on_invite_pressed)
	var max_hp := GameState.selected_job().max_hp
	_hp_bar.max_value = float(max_hp)
	_set_own_hp(max_hp)
	_partner_label.text = ""
	_banner.visible = false
	EventBus.player_hp_confirmed.connect(_on_player_hp)
	EventBus.stage_cleared.connect(func() -> void: _show_banner("스테이지 클리어!"))
	EventBus.stage_wiped.connect(func() -> void: _show_banner("전멸 — 마을로 귀환합니다"))


func _on_player_hp(peer_id: int, hp: int) -> void:
	if peer_id == Net.my_id:
		_set_own_hp(hp)
		if hp <= 0:
			_show_banner("관전 중 — 스테이지 클리어 시 부활")
		elif _banner.visible and _banner.text.begins_with("관전"):
			_banner.visible = false
	else:
		_partner_label.text = "파트너 HP %d" % maxi(hp, 0) if hp > 0 else "파트너 사망"


func _set_own_hp(hp: int) -> void:
	_hp_bar.value = float(maxi(hp, 0))
	_hp_label.text = "HP %d" % maxi(hp, 0)


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true


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
