extends CanvasLayer
# 설정 패널 (첫 모달 — 표준 수립) — 전체 볼륨/뮤트 조절 UI.
# 오디오 재생·저장 로직은 전부 Audio 오토로드(rules §1)에 있다 — 여기선 값을 읽어 표시하고,
# 바뀌면 Audio setter만 부른다(자동 저장은 Audio가 한다). 새 오디오 로직 금지.
#
# 모달 규약(rules §5·verify §2-1):
#  - 루트 = CanvasLayer, 기본 visible=false. 닫히면 완전히 숨겨 뒤 게임 클릭을 안 막는다.
#  - 열려 있는 동안만 Backdrop(ColorRect, mouse_filter=STOP)이 뒤 게임 클릭을 차단(모달).
#  - 다이얼로그 안 컨트롤(슬라이더·체크·닫기)만 클릭을 받는다.
# ⚠ 이 파일은 UI 씬 스크립트라 전역 오토로드(Audio) 식별자 직접 접근 OK (헤드리스 -s 대상 아님, rules §5).

const UiTheme := preload("res://src/ui/ui_theme.gd")  # UI 톤 단일 소스 (rules §0: class_name 대신 preload)

@onready var _slider: HSlider = %Slider
@onready var _value_label: Label = %ValueLabel
@onready var _mute_check: CheckButton = %MuteCheck
@onready var _village_btn: Button = %VillageBtn
@onready var _job_btn: Button = %JobBtn
@onready var _close_btn: Button = %CloseBtn

var _dragging: bool = false  # 드래그 중엔 미리듣기를 release에서 한 번만 (연타 방지)
var _overlay: Control = null  # 확인창/직업목록 서브 오버레이 (한 번에 하나)


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 테마 (로비·HUD·제작 패널과 통일)
	_slider.value_changed.connect(_on_slider_changed)
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(_on_drag_ended)
	_mute_check.toggled.connect(_on_mute_toggled)
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
	visible = true


func close() -> void:
	_dismiss_overlay()
	visible = false


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
