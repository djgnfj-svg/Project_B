extends Node2D

## 디버그 프로토타입 — 지면 충격파 한 줄. 스폰 시 방향·속도 고정(결정론적, 유도 없음).
## 비주얼(도트 스프라이트) + 기하만. 데미지 없음 — 느낌/설계용. 정식 통합은 보스 slam 패턴 + 네트워크로.

const FRAMES := preload("res://assets/sprites/fx/shockwave_frames.tres")

var dir: Vector2 = Vector2.RIGHT
var speed: float = 360.0
var max_range: float = 300.0
var _traveled: float = 0.0

func _ready() -> void:
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = FRAMES
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.rotation = dir.angle()   # 스프라이트는 +x(오른쪽) 기준 → 진행 방향으로 회전
	spr.scale = Vector2(1.4, 1.4)
	spr.z_index = -1              # 캐릭터 아래(바닥 위)
	spr.play(&"roll")
	add_child(spr)

func _process(delta: float) -> void:
	var step := speed * delta
	global_position += dir * step
	_traveled += step
	if _traveled >= max_range:
		queue_free()
