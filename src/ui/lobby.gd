extends Control
# 로비 — 직업 선택 + 중계 서버 접속 + 방 만들기/참가. 방 성립 후 씬 전환은 조합 루트(src/main)가 한다.
# 기본 흐름 = "방 만들기" 원클릭. 코드 참가는 폴백, 서버 주소는 접힌 고급 옵션.
# 직업(GDD §5: 시작 시 선택·이후 고정)은 GameState.selected_job_id에 기록 — 스테이지가 읽는다.

const SettingsPanelScene := preload("res://src/ui/settings_panel.tscn")  # rules §0: class_name 대신 preload
const UiTheme := preload("res://src/ui/ui_theme.gd")  # UI 톤 단일 소스 (제작/인벤/HUD와 같은 테마)
# 개발 모드 게이트 단일 소스. 오토로드 인스턴스 대신 **스크립트**를 물어 static으로 부른다.
const DebugBridgeScript := preload("res://src/core/debug_bridge.gd")

@onready var _url_edit: LineEdit = %UrlEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _host_btn: Button = %HostBtn
@onready var _join_btn: Button = %JoinBtn
@onready var _adv_btn: Button = %AdvBtn
@onready var _settings_btn: Button = %SettingsBtn
@onready var _debug_btn: Button = %DebugBtn  # 개발 모드 토글 — 켜 두면 F1 패널이 URL 없이 열린다
@onready var _boss_test_btn: Button = %BossTestBtn  # 개발 전용 — 누르면 보스 테스트 랩(무적·패턴 버튼) 직행
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
	theme = UiTheme.get_theme()  # 루트 Control에 한 번 — 아래 전부 상속 (제작/인벤 패널과 같은 톤)
	_url_edit.text = Net.default_relay_url()
	if Net.state == Net.State.CONNECTED:
		_status.text = "서버 연결됨 — 방을 만들거나 참가하세요"
	# 🔴 준비중 직업이 선택된 채로 들어오면 고를 수 있는 직업으로 되돌린다 — 세이브는 직업을 담지
	#   않지만(rules §5) 로비 **재진입**에서는 이전 선택이 GameState에 그대로 남아 있어서, 잠그기 전에
	#   궁수를 골랐던 세션이 "아무 버튼도 안 눌린 채 궁수로 시작"하는 상태가 된다(에러 없음).
	if not GameState.is_job_playable(GameState.selected_job_id):
		GameState.selected_job_id = GameState.playable_job_ids()[0]
	for job_id: String in _job_btns:
		var btn := _job_btns[job_id]
		btn.button_pressed = job_id == GameState.selected_job_id  # 로비 재진입 시 이전 선택 복원
		# 아이콘 = 인게임 시트에서 유도 (아래 _job_icon) — 로비 미리보기와 인게임 그림이 갈라지지 않게
		var icon := btn.get_parent().get_node_or_null("Icon") as TextureRect
		var jd := GameState.job_def(job_id)
		var tex := _job_icon(jd)
		if icon != null and tex != null:
			icon.texture = tex
		if not GameState.is_job_playable(job_id):
			_hide_job(btn)
			continue  # 시그널을 연결하지 않는다 — 숨김에 얹어 두면 잠금을 푸는 조건이 두 개가 된다
		# button_down: 이미 눌린 토글(기본 전사)을 다시 클릭해도 반드시 발화 — pressed는 그룹 토글
		# 재클릭에서 안 올 수 있어, 자동 시작 트리거가 기본 직업 선택에서 데드락 나는 것을 막는다
		btn.button_down.connect(_on_job_pressed.bind(job_id))
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_adv_btn.pressed.connect(func() -> void: _url_edit.visible = not _url_edit.visible)
	# 개발 모드 — `?debug=1`을 URL에 매번 붙이지 않으려고 만든 토글(사용자 요청 2026-07-28).
	# ⚠ 다른 경로(URL `?debug=1` · 에디터/네이티브)로 이미 켜진 경우엔 **토글로 끌 수 없다** —
	#   게이트가 OR이라 토글을 꺼도 그쪽이 계속 연다. 눌러도 안 꺼지는 버튼은 고장으로 읽히므로
	#   비활성 + 사유를 툴팁에 적는다.
	var elsewhere := DebugBridgeScript.panel_enabled() and not DebugBridgeScript.panel_forced()
	_debug_btn.button_pressed = DebugBridgeScript.panel_forced() or elsewhere
	_debug_btn.disabled = elsewhere
	_debug_btn.tooltip_text = ("이미 켜져 있습니다 — URL의 debug=1 또는 개발 환경(에디터) 때문입니다"
		if elsewhere else "켜면 게임 중 F1로 개발 패널(직업·장비·레벨·시험장)이 열립니다. 이 선택은 기억됩니다")
	_debug_btn.toggled.connect(func(on: bool) -> void:
		DebugBridgeScript.set_panel_forced(on)
		_status.text = "개발 모드 %s — F1로 패널을 엽니다" % ("켬" if on else "끔"))
	# 개발 전용 「보스 테스트 랩」 — dev 게이트(F1 패널과 **같은 판정** = DebugBridge.panel_enabled)로만 보인다.
	#   프로덕션 웹 빌드(debug=1 없음)에서는 숨겨져 프로덕션 무접촉을 지킨다. 에디터·네이티브는 항상 dev라 보인다.
	# 🔴 스톡 엔진이 `--test`를 가로채 네이티브·에디터엔 플래그 진입로가 없어(test_mode.activate 주석), 이 버튼이 유일한 입구다.
	_boss_test_btn.visible = DebugBridgeScript.panel_enabled()
	_boss_test_btn.pressed.connect(_on_boss_test_pressed)
	var settings := SettingsPanelScene.instantiate()
	add_child(settings)  # CanvasLayer(layer 10) — 로비 위 오버레이
	_settings_btn.pressed.connect(settings.open)
	EventBus.net_connected.connect(func() -> void: _status.text = "서버 연결됨…")
	EventBus.net_connect_failed.connect(
		func(reason: String) -> void: _set_idle("연결 실패: %s" % reason))
	EventBus.room_join_failed.connect(
		func(reason: String) -> void: _set_idle("참가 실패: %s" % reason))
	EventBus.room_created.connect(
		func(code: String) -> void: _status.text = "방 생성됨 — 코드: %s" % code)
	_try_autostart()


# 로비 아이콘 = 그 직업의 **인게임 idle 첫 프레임**에서 유도한다 (2026-07-29).
# 🔴 `JobDef.sprite`(별도 단일 컷 PNG)를 직접 쓰면 시트를 다시 그렸을 때 **조용히 갈라진다** —
#   실제로 `warrior_anim.png`를 새로 그린 뒤 로비만 7월 22일자 옛 캐릭터를 계속 보여줬다(에러 없음,
#   화면만 어긋나는 부류). 두 파일이 같은 캐릭터를 뜻하는데 갱신 책임이 사람에게 있으면 반드시 어긋난다.
#   frames에서 유도하면 아트가 시트를 갈아도 로비가 자동으로 따라온다.
# ⚠ `sprite`는 폴백으로만 남긴다 — 시트가 없거나 idle이 빠진 직업(`_frames.tres` 작업 전)에서 빈 칸이
#   되는 것보다 옛 그림이라도 뜨는 편이 낫다. 필드 자체를 지우려면 참조처를 전수로 봐야 한다.
const ICON_ANIM := &"idle"


func _job_icon(jd: JobDef) -> Texture2D:
	if jd == null:
		return null
	var f := jd.frames
	if f != null and f.has_animation(ICON_ANIM) and f.get_frame_count(ICON_ANIM) > 0:
		return f.get_frame_texture(ICON_ANIM, 0)
	return jd.sprite


# 준비중 직업을 로비에서 **통째로 숨긴다** (사용자 결정 2026-07-29: "캐릭터 하나만 보이게").
# 숨기는 것은 버튼이 아니라 **열(아이콘 + 버튼을 담은 VBox)** 이다 — 버튼만 숨기면 아이콘이 남아
# 이름 없는 그림 두 개가 떠 있게 된다.
# 🔴 `disabled`도 같이 건다 — `visible = false`만으로는 **ButtonGroup이 그 버튼을 계속 들고 있어서**
#   나중에 코드가 그룹을 순회하면 안 보이는 버튼이 후보로 잡힌다. 잠금은 보이는 것과 무관해야 한다.
func _hide_job(btn: Button) -> void:
	btn.disabled = true
	btn.button_pressed = false
	var col := btn.get_parent() as Control
	if col != null:
		col.visible = false


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
	# 테스트 모드(?test=1 / --test) = 솔로 자동 호스트 (직업 선택 후 보스 아레나 랩 직행은 main이 처리)
	if TestMode.is_active():
		req["host"] = true
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


# 개발 전용 — TestMode를 켜고 현재 선택 직업(기본 전사)으로 즉시 호스트한다.
# 방 성립(room_created) → main._enter_after_room()이 TestMode.is_active()를 보고 _to_boss_test()로
# 챕터1 보스 칸 + 랩(무적 플레이어·NPC 더미·패턴 버튼·「새 보스」)에 직행한다.
# ⚠ 호스트는 릴레이(기본 wss://relay.jachana.com)를 지난다 — 기존 ?test=1 경로와 동일한 전제다(솔로도 방을 만든다).
func _on_boss_test_pressed() -> void:
	TestMode.activate()
	_status.text = "보스 테스트 랩으로 시작합니다…"
	_on_host_pressed()


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
