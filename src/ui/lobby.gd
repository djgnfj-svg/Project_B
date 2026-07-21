extends Control
# 로비 — 중계 서버 접속 + 방 만들기/참가. 방 성립 후 씬 전환은 조합 루트(src/main)가 한다.

@onready var _url_edit: LineEdit = %UrlEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _host_btn: Button = %HostBtn
@onready var _join_btn: Button = %JoinBtn
@onready var _status: Label = %Status


func _ready() -> void:
	# Node2D(main) 아래 붙는 루트 Control — 비-Control 부모에선 씬 앵커가 안 펴지는 경우가 있어 뷰포트 크기 강제
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_url_edit.text = Net.DEFAULT_RELAY_URL
	if OS.has_feature("web"):
		# 배포 관례: game.<도메인> 페이지면 릴레이 기본값 = wss://relay.<도메인> (로컬 개발은 localhost 유지)
		var page_host := str(JavaScriptBridge.eval("window.location.hostname", true))
		if page_host.begins_with("game."):
			_url_edit.text = "wss://relay." + page_host.trim_prefix("game.")
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
	_try_autostart()


# 자동 시작 — 초대 링크(?join=코드&relay=wss://…, GDD §10 스트레치 골격) + 네이티브 인자(--host/--join=)
func _try_autostart() -> void:
	var req := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host":
			req["host"] = true
		elif arg.begins_with("--join="):
			req["join"] = arg.trim_prefix("--join=")
	if OS.has_feature("web"):
		var search := str(JavaScriptBridge.eval("window.location.search", true))
		for pair: String in search.trim_prefix("?").split("&"):
			if pair == "host":
				req["host"] = true
			elif pair.begins_with("join="):
				req["join"] = pair.get_slice("=", 1)
			elif pair.begins_with("relay="):
				_url_edit.text = pair.get_slice("=", 1).uri_decode()
	if req.has("host"):
		_on_host_pressed()
	elif req.has("join"):
		_code_edit.text = str(req["join"])
		_on_join_pressed()


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
