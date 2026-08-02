extends CanvasLayer
# **Esc 통합 메뉴** (구 "설정 패널" — 첫 모달이자 모달 표준) — 방 정보 + 초대 코드 복사 + 성장 표기 +
# 볼륨/뮤트 + 마을 귀환/직업 변경.
#
# 🔴 **HUD에서 내려온 것들이 여기 산다** (사용자 확정 2026-08-02: *"ui 줄이기 — 너무 많음, ESC에 다
#   들어가게 하자"*). 화면에는 HP·구르기·파트너·스킬 쿨·골드·EXP 띠만 남았고, **방 코드·호스트 여부·
#   핑·경로(직결/릴레이)·fps·진행도·초대 복사·레벨/하위 직업 표기**가 이 패널로 옮겨 왔다.
# 🔴 **핑·경로·fps 세 값을 지우지 마라** — rules §5가 "렉이 있다" 신고에서 네트워크와 렌더를 가르는
#   유일한 도구로 지정한 값이다. 화면에서 뺐을 뿐이고 Esc 한 번이면 반드시 읽혀야 한다.
#   표기 문자열의 **단일 소스가 여기다**(HUD에 사본을 만들지 마라 — 두 곳이면 다음 튜닝에 갈라진다).
#
# 오디오 재생·저장 로직은 전부 Audio 오토로드(rules §1)에 있다 — 여기선 값을 읽어 표시하고,
# 바뀌면 Audio setter만 부른다(자동 저장은 Audio가 한다). 새 오디오 로직 금지.
#
# 모달 규약(rules §5·verify §2-1):
#  - 루트 = CanvasLayer, 기본 visible=false. 닫히면 완전히 숨겨 뒤 게임 클릭을 안 막는다.
#  - 열려 있는 동안만 Backdrop(ColorRect, mouse_filter=STOP)이 뒤 게임 클릭을 차단(모달).
#  - 다이얼로그 안 컨트롤(슬라이더·체크·닫기)만 클릭을 받는다.
#  - ⚠ 게임을 **멈추지 않는다**(멀티라 pause 금지 — 인벤/제작 패널과 같은 규약).
# 🔴 Esc는 **여는 쪽(HUD)과 닫는 쪽(여기)이 갈라져 있다** (rules §5 "토글 키는 한 곳에서만"의 이
#   프로젝트 관용구 — craft/inventory/subjob 패널이 전부 같은 형태다). 이 패널은 HUD의 **자식**이라
#   `_unhandled_input`을 먼저 받으므로, 열려 있으면 Esc가 HUD까지 가지 않아 "열자마자 닫힘"이 없다.
# ⚠ 이 파일은 UI 씬 스크립트라 전역 오토로드(Audio·Net·GameState) 식별자 직접 접근 OK
#   (헤드리스 -s 대상 아님, rules §5).

const UiTheme := preload("res://src/ui/ui_theme.gd")  # UI 톤 단일 소스 (rules §0: class_name 대신 preload)
const NetSchema := preload("res://src/core/net_schema.gd")  # 방 인원 상한(MAX_ROOM_PEERS) 한 곳에서 받는다

const INVITE_FX_TIME := 1.5  # 복사 피드백 표시 시간 (연출값)
const INFO_REFRESH_S := 0.5  # 핑/fps 갱신 주기(s) — Net의 측정 주기와 같게 (더 자주 그려도 값이 안 바뀐다)

@onready var _slider: HSlider = %Slider
@onready var _value_label: Label = %ValueLabel
@onready var _mute_check: CheckButton = %MuteCheck
@onready var _room_label: Label = %RoomLabel
@onready var _net_label: Label = %NetLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _growth_label: Label = %GrowthLabel
@onready var _invite_btn: Button = %InviteBtn
@onready var _village_btn: Button = %VillageBtn
@onready var _job_btn: Button = %JobBtn
@onready var _close_btn: Button = %CloseBtn

var _dragging: bool = false  # 드래그 중엔 미리듣기를 release에서 한 번만 (연타 방지)
var _overlay: Control = null  # 확인창/직업목록 서브 오버레이 (한 번에 하나)
var _invite_fx_seq: int = 0  # 복사 연타 시 이전 타이머가 새 피드백을 지우지 않게
var _info_accum: float = 0.0  # 정보 줄 갱신 누산 (열려 있는 동안만 돈다)


func _ready() -> void:
	visible = false
	set_process(false)  # 닫혀 있으면 정보 줄을 갱신할 이유가 없다(웹 WASM 단일 스레드 — 공짜가 아니다)
	$Center.theme = UiTheme.get_theme()  # 공용 테마 (로비·HUD·제작 패널과 통일)
	_slider.value_changed.connect(_on_slider_changed)
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(_on_drag_ended)
	_mute_check.toggled.connect(_on_mute_toggled)
	_invite_btn.pressed.connect(_on_invite_pressed)
	_village_btn.pressed.connect(_on_village_pressed)
	_job_btn.pressed.connect(_on_job_pressed)
	_close_btn.pressed.connect(close)


# 열 때 Audio 현재 값으로 컨트롤 초기 동기화 — no_signal로 setter 재호출/미리듣기 발화를 막는다.
func open() -> void:
	var vol := Audio.master_volume()
	_slider.set_value_no_signal(vol)
	_mute_check.set_pressed_no_signal(Audio.is_muted())
	_update_value_label(vol)
	_refresh_actions()
	_refresh_info()
	_info_accum = 0.0
	visible = true
	set_process(true)


func close() -> void:
	_dismiss_overlay()
	visible = false
	set_process(false)


# Esc = 닫기. 서브 오버레이(마을 확인창·직업 목록)가 열려 있으면 **그것부터** 접는다 —
# 한 번에 창 두 개가 닫히면 "취소하려던 것"과 "메뉴를 닫는 것"이 구분되지 않는다.
# ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받는다(rules §5) → visible 가드가 필수다.
#   가드가 없으면 이 패널이 Esc를 늘 삼켜 **HUD가 메뉴를 영영 못 연다**(에러 없음).
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _overlay != null:
			_dismiss_overlay()
		else:
			close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_info_accum += delta
	if _info_accum < INFO_REFRESH_S:
		return
	_info_accum = 0.0
	_refresh_info()


# --- 방 정보 / 네트워크 진단 / 진행도 / 성장 (구 HUD 좌상단 + 좌하단) ---
# 🔴 **핑·경로·fps를 한 줄에 나란히 둔다** — "렉이 심하다"는 신고에서 네트워크(핑)와 렌더(FPS)는 원인도
#   처방도 완전히 다른데 체감이 똑같다. 둘을 나란히 보면 한눈에 갈린다(rules §5). 경로("직결"/"릴레이")도
#   같은 줄이다 — P2P가 실제로 뚫렸는지는 **핑 숫자만으로는 못 읽는다**(릴레이 폴백도 조용히 잘 돈다).
# 아직 왕복 측정 전이거나 솔로면 핑·경로는 생략(0 = 표시 안 함). FPS는 솔로에서도 항상 띄운다.
func _refresh_info() -> void:
	var in_room := not Net.room_code.is_empty()
	_invite_btn.visible = in_room  # 로비(방 없음)에서도 이 패널이 열린다 — 복사할 코드가 없으면 버튼도 없다
	# 🔴 **인원수도 여기 붙인다** (2026-08-02) — 마을 우상단 배지에서 옮겨 온 것이다. 그 배지는
	#   빌드 버전과 인원을 화면에 상시 띄우고 있었는데, "화면 글자를 줄이고 ESC에 다 넣자"는
	#   사용자 요구와 정면으로 어긋났다. 인원은 방 정보의 일부라 방 줄에 붙는 것이 자연스럽다.
	# ⚠ 상한은 `NetSchema.MAX_ROOM_PEERS`(현재 2인 전제)에서 온다 — 4인 파티를 열 때 자동 추종한다.
	if in_room:
		_room_label.text = "방 %s · %s · %d/%d명" % [Net.room_code,
			"호스트" if Net.is_host() else "게스트",
			Net.peer_ids.size() + 1, NetSchema.MAX_ROOM_PEERS]
	else:
		_room_label.text = "방에 들어가지 않음"
	var net_text := ""
	var rtt := Net.display_rtt_ms()
	if rtt > 0.0:
		net_text = "핑 %dms · %s · " % [int(roundf(rtt)), "직결" if Net.p2p_active() else "릴레이"]
	net_text += "%dfps" % Engine.get_frames_per_second()
	# 빌드 버전을 같은 줄 끝에 붙인다 — 마을 우상단 배지에서 옮겨 온 것이다(2026-08-02).
	# 🔴 이 값이 있어야 "웹에서 옛 캐시를 물고 있다"를 판별할 수 있다. 핑·fps와 같은 진단 줄이 제자리다.
	net_text += " · %s" % GameState.BUILD_VERSION
	_net_label.text = net_text
	# 진행도 — 마을(비챕터)은 빈 문자열이라 줄 자체를 숨긴다
	var prog := GameState.progress_label()
	_progress_label.visible = not prog.is_empty()
	_progress_label.text = prog
	_refresh_growth_line()


# 하위 직업 이름 + 레벨 + EXP — HUD에서는 바만 남기고 **숫자는 여기로** 옮겼다.
# 성장축이 없는 계열(main_sub_job() == null)은 줄을 숨긴다(빈 줄이 떠 있으면 버그처럼 보인다).
func _refresh_growth_line() -> void:
	var d := GameState.main_sub_job()
	if d == null:
		_growth_label.visible = false
		return
	_growth_label.visible = true
	var p := GameState.main_exp_progress()
	var lv := int(p["level"])
	var need := int(p["need"])
	if need <= 0:
		_growth_label.text = "%s Lv%d · MAX" % [d.display_name, lv]
	else:
		_growth_label.text = "%s Lv%d · %d/%d" % [d.display_name, lv, int(p["cur"]), need]


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


# 씬/권한에 따라 두 액션 버튼 상태 갱신
func _refresh_actions() -> void:
	var in_village := get_tree().get_first_node_in_group("village") != null
	# 마을로 가기 — 마을에선 숨김, 스테이지에선 호스트만 (씬 전환 = 호스트 권한, rules §3)
	# ⚠ 라벨에 이모지를 쓰지 않는다 — 픽셀 폰트(Galmuri9)에 없어 시스템 폰트로 폴백되고, 그 한 글자 때문에
	#   이 화면만 톤이 튄다(웹에선 OS마다 모양도 다르다). 상태는 괄호 문구로 말한다.
	_village_btn.visible = not in_village
	_village_btn.disabled = not Net.is_host()
	_village_btn.text = "마을로 가기" if Net.is_host() else "마을로 가기 (방장만)"
	# 직업 변경 — 마을에서만 (전투 스테이지에선 스탯 취사선택 악용 방지로 잠금)
	_job_btn.disabled = not in_village
	_job_btn.text = "직업 변경" if in_village else "직업 변경 (마을에서만)"


func _on_village_pressed() -> void:
	var vb := _make_overlay("마을로 돌아갈까요?\n현재 스테이지 진행은 사라집니다.")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiTheme.GAP_SECTION)
	var yes := _mk_btn("예", 72)
	yes.pressed.connect(func() -> void:
		_dismiss_overlay()
		EventBus.leave_to_village_requested.emit()  # SceneFlow(호스트)가 전원 귀환
		close())
	var no := _mk_btn("아니오", 72)
	no.pressed.connect(_dismiss_overlay)
	row.add_child(yes)
	row.add_child(no)
	vb.add_child(row)


func _on_job_pressed() -> void:
	var vb := _make_overlay("직업 변경")
	for id: String in GameState.job_ids():
		var jd := GameState.job_def(id)
		var label := jd.display_name if jd != null and not jd.display_name.is_empty() else id
		if id == GameState.selected_job_id:
			label += "  ✓"
		# 🔴 준비중 직업은 여기서도 막는다 (데모용 2026-07-29) — 로비와 **같은 판정 함수**를 쓴다.
		#   UI마다 규칙을 복사하면 한쪽만 풀렸을 때 "로비에선 못 고르는데 마을에서 바꿔진다"가 된다.
		#   여긴 버튼 폭이 160px라 로비와 달리 라벨에 그대로 넣어도 열이 안 어긋난다.
		var playable := GameState.is_job_playable(id)
		if not playable:
			label += "  (준비중)"
		var b := _mk_btn(label, 160)
		b.disabled = not playable
		var jid := id
		if playable:
			b.pressed.connect(func() -> void:
				_dismiss_overlay()
				EventBus.job_change_requested.emit(jid)  # PeerSync(마을)가 반영+재공지
				close())
		vb.add_child(b)
	var cancel := _mk_btn("취소", 160)
	cancel.pressed.connect(_dismiss_overlay)
	vb.add_child(cancel)


# 서브 오버레이 생성 (딤 배경 + 중앙 패널). title 라벨을 얹은 VBox를 돌려준다 — 호출자가 내용 추가.
func _make_overlay(title: String) -> VBoxContainer:
	_dismiss_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.theme = UiTheme.get_theme()  # CanvasLayer 자식이라 상속이 안 온다 — 여기서 직접 건다
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # 열려 있는 동안 뒤 설정 클릭 차단(모달)
	_overlay.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()  # 안쪽 패딩은 PanelContainer 스타일박스가 소유한다(ui_theme PAD_PANEL)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UiTheme.GAP_SECTION)
	margin.add_child(vb)
	var t := Label.new()
	t.text = title  # 확인 문구는 두 줄짜리 본문이라 제목 등급을 씌우지 않는다(본문 12px 그대로)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	add_child(_overlay)  # CanvasLayer 자식 — Center보다 뒤에 추가돼 위에 그려진다
	return vb


func _dismiss_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


func _mk_btn(text: String, min_w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 28)  # 씬의 액션 버튼 높이와 같은 등급
	return b


func _on_slider_changed(v: float) -> void:
	Audio.set_master_volume(v)  # 자동 저장은 Audio가 한다
	_update_value_label(v)
	if not _dragging:
		Audio.play("hit")  # 클릭/키보드 단발 조작 미리듣기 (드래그 중엔 release에서)


func _on_drag_ended(value_changed: bool) -> void:
	_dragging = false
	if value_changed:
		Audio.play("hit")  # 드래그 끝에 한 번 (드래그 중 매 프레임 발화 안 함)


func _on_mute_toggled(pressed: bool) -> void:
	Audio.set_muted(pressed)


func _update_value_label(v: float) -> void:
	_value_label.text = "%d%%" % roundi(v * 100.0)
