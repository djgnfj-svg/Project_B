extends Area2D
# 마을 훈련소 허수아비 (직업 선택 진입점) — **클릭 전용**. 좌클릭하면 직업 선택 카드 창을 연다.
# 🔴 전투 판정 무접촉이다 — 이건 전투용 `training_dummy`(StaticBody2D + Health)가 아니라,
#   마을에 세워 둔 **클릭 상호작용용** 허수아비다. Health·데미지·부활 컴포넌트가 없다(클릭만).
#   물리 레이어는 상호작용(interact = 7)이라 플레이어 몸/공격과 겹쳐도 아무 판정이 안 생긴다.
#
# 겉모습은 스프라이트(dummy.png)로만 — 도형 금지(§0). Area2D의 input_event로 마우스 좌클릭을 받는다.
# 패널 오픈은 시그널(opened)로 마을에 알린다 — 이 노드는 UI 씬을 직접 물지 않는다(모듈 경계, §0).
# ⚠ UI가 열려 있는 동안엔 그 위 클릭이 Area2D까지 안 내려온다(모달 Backdrop가 STOP으로 먹는다) —
#   그래서 "패널 열려 있는데 또 열림" 같은 이중 오픈이 구조적으로 안 생긴다.

const DUMMY_TEX_PATH := "res://assets/sprites/enemies/dummy.png"

signal clicked  # 좌클릭됨 — 마을이 받아 직업 선택 패널을 연다

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	input_event.connect(_on_input_event)
	_apply_texture()


# 허수아비 텍스처 — 발밑(하단 중앙)이 노드 좌표에 오게 offset을 유도한다(발밑 원점 규약, village 미러).
func _apply_texture() -> void:
	if ResourceLoader.exists(DUMMY_TEX_PATH):
		var tex := load(DUMMY_TEX_PATH) as Texture2D
		if tex != null:
			_sprite.texture = tex
	var t := _sprite.texture
	if t != null:
		_sprite.offset = Vector2(-t.get_width() * 0.5, -float(t.get_height()))


# Area2D 마우스 이벤트 — 좌클릭(pressed)만 소비. viewport가 이 콜백을 주는 것 자체가
# "이 도형 위 클릭"이라 별도 히트테스트가 필요 없다.
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
