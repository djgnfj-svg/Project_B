extends Control
# 로비 — 직업 선택 + 중계 서버 접속 + 방 만들기/참가. 방 성립 후 씬 전환은 조합 루트(src/main)가 한다.
# 기본 흐름 = "방 만들기" 원클릭. 코드 참가는 폴백, 서버 주소는 접힌 고급 옵션.
# 직업(GDD §5: 시작 시 선택·이후 고정)은 GameState.selected_job_id에 기록 — 스테이지가 읽는다.

@onready var _url_edit: LineEdit = %UrlEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _host_btn: Button = %HostBtn
@onready var _join_btn: Button = %JoinBtn
@onready var _adv_btn: Button = %AdvBtn
@onready var _status: Label = %Status
@onready var _job_btns: Dictionary[String, Button] = {  # job id -> 토글 버튼 (ButtonGroup로 라디오)
	"warrior": %WarriorBtn as Button,
	"archer": %ArcherBtn as Button,
	"mage": %MageBtn as Button,
}

var _pending_autostart: Dictionary = {}  # 초대 링크 자동 시작 — 직업을 고른 뒤에 실행


func _ready() -> void:
	# Node2D(main) 아래 붙는 루트 Control — 비-Control 부모에선 씬 앵커가 안 펴지는 경우가 있어 뷰포트 크기 강제
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_url_edit.text = Net.default_relay_url()
	if Net.state == Net.State.CONNECTED:
		_status.text = "서버 연결됨 — 방을 만들거나 참가하세요"
	for job_id: String in _job_btns:
		var btn := _job_btns[job_id]
		btn.button_pressed = job_id == GameState.selected_job_id  # 로비 재진입 시 이전 선택 복원
		# button_down: 이미 눌린 토글(기본 전사)을 다시 클릭해도 반드시 발화 — pressed는 그룹 토글
		# 재클릭에서 안 올 수 있어, 자동 시작 트리거가 기본 직업 선택에서 데드락 나는 것을 막는다
		btn.button_down.connect(_on_job_pressed.bind(job_id))
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_adv_btn.pressed.connect(func() -> void: _url_edit.visible = not _url_edit.visible)
	EventBus.net_connected.connect(func() -> void: _status.text = "서버 연결됨…")
	EventBus.net_connect_failed.connect(
		func(reason: String) -> void: _set_idle("연결 실패: %s" % reason))
	EventBus.room_join_failed.connect(
		func(reason: String) -> void: _set_idle("참가 실패: %s" % reason))
	EventBus.room_created.connect(
		func(code: String) -> void: _status.text = "방 생성됨 — 코드: %s" % code)
	_try_autostart()


func _on_job_pressed(job_id: String) -> void:
	GameState.selected_job_id = job_id
	if not _pending_autostart.is_empty():
		var req := _pending_autostart
		_pending_autostart = {}
		_run_autostart(req)


# 자동 시작 — 초대 링크(?join=코드&relay=wss://…, GDD §10 스트레치 골격) + 네이티브 인자(--host/--join=/--relay=)
# 직업 선택이 먼저다: 요청을 보관해 두고, 직업 버튼을 누르는 순간 실행한다.
func _try_autostart() -> void:
	var req := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host":
			req["host"] = true
		elif arg.begins_with("--join="):
			req["join"] = arg.trim_prefix("--join=")
		elif arg.begins_with("--relay="):
			# 네이티브 기본값이 공용 릴레이라, 로컬 릴레이 개발 테스트는 이 인자로 겨눈다 (웹 ?relay=와 대칭)
			_url_edit.text = arg.trim_prefix("--relay=")
	if OS.has_feature("web"):
		var search := str(JavaScriptBridge.eval("window.location.search", true))
		for pair: String in search.trim_prefix("?").split("&"):
			if pair == "host":
				req["host"] = true
			elif pair.begins_with("join="):
				req["join"] = pair.get_slice("=", 1)
			elif pair.begins_with("relay="):
				_url_edit.text = pair.get_slice("=", 1).uri_decode()
	if req.has("host") or req.has("join"):
		_pending_autostart = req
		_status.text = "직업을 선택하면 바로 시작합니다"


func _run_autostart(req: Dictionary) -> void:
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
