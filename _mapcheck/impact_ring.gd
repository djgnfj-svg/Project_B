extends Node2D

## 슬램 임팩트 지점 원형 물결(파문) — 도끼가 바닥 찍은 자리에서 퍼진다. 도트 스프라이트(Aseprite 제작).
## 애니 끝나면 자동 소멸. 탑다운 바닥 원근감 위해 세로로 납작.

const FRAMES := preload("res://assets/sprites/fx/impact_ring_frames.tres")

func _ready() -> void:
	scale = Vector2(0.85, 0.52)   # 바닥 파문 = 세로로 납작한 타원
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = FRAMES
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.z_index = -1
	spr.play(&"ripple")
	spr.animation_finished.connect(queue_free)
	add_child(spr)
