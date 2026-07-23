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

@onready var _slider: HSlider = %Slider
@onready var _value_label: Label = %ValueLabel
@onready var _mute_check: CheckButton = %MuteCheck
@onready var _close_btn: Button = %CloseBtn

var _dragging: bool = false  # 드래그 중엔 미리듣기를 release에서 한 번만 (연타 방지)


func _ready() -> void:
	visible = false
	_slider.value_changed.connect(_on_slider_changed)
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(_on_drag_ended)
	_mute_check.toggled.connect(_on_mute_toggled)
	_close_btn.pressed.connect(close)


# 열 때 Audio 현재 값으로 컨트롤 초기 동기화 — no_signal로 setter 재호출/미리듣기 발화를 막는다.
func open() -> void:
	var vol := Audio.master_volume()
	_slider.set_value_no_signal(vol)
	_mute_check.set_pressed_no_signal(Audio.is_muted())
	_update_value_label(vol)
	visible = true


func close() -> void:
	visible = false


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
