extends CanvasLayer
# 인게임 공용 HUD — 방 코드 표시 + 초대 링크 복사. 마을·스테이지가 인스턴스로 문다 (rules §2 src/hud).

const INVITE_FX_TIME := 1.5  # 복사 피드백 표시 시간 (연출값)

var _invite_fx_seq: int = 0  # 복사 연타 시 이전 타이머가 새 피드백을 지우지 않게

@onready var _room_label: Label = $RoomCode
@onready var _invite_btn: Button = $InviteBtn


func _ready() -> void:
	_room_label.text = "방 %s · %s" % [
		Net.room_code, "호스트" if Net.is_host() else "게스트"]
	_invite_btn.pressed.connect(_on_invite_pressed)


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
