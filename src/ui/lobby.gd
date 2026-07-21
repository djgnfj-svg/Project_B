extends Control
# 로비 — 중계 서버 접속 + 방 만들기/참가. 방 성립 후 씬 전환은 조합 루트(src/main)가 한다.

@onready var _url_edit: LineEdit = %UrlEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _host_btn: Button = %HostBtn
@onready var _join_btn: Button = %JoinBtn
@onready var _status: Label = %Status


func _ready() -> void:
	_url_edit.text = Net.DEFAULT_RELAY_URL
	if Net.state == Net.State.CONNECTED:
		_status.text = "서버 연결됨 — 방을 만들거나 참가하세요"
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	EventBus.net_connected.connect(func() -> void: _status.text = "서버 연결됨…")
	EventBus.net_connect_failed.connect(
		func(reason: String) -> void: _set_idle("연결 실패: %s" % reason))
	EventBus.room_join_failed.connect(
		func(reason: String) -> void: _set_idle("참가 실패: %s" % reason))
	EventBus.room_created.connect(
		func(code: String) -> void: _status.text = "방 생성됨 — 코드: %s" % code)


func _on_host_pressed() -> void:
	_set_busy("방 만드는 중…")
	Net.host_room(_url_edit.text.strip_edges())


func _on_join_pressed() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		_status.text = "방 코드를 입력하세요"
		return
	_set_busy("방 참가 중…")
	Net.join_room(_url_edit.text.strip_edges(), code)


func _set_busy(msg: String) -> void:
	_status.text = msg
	_host_btn.disabled = true
	_join_btn.disabled = true


func _set_idle(msg: String) -> void:
	_status.text = msg
	_host_btn.disabled = false
	_join_btn.disabled = false
