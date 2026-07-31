extends Node2D

## 임시 디버그 — 보스방 바닥(sanctum) 위에서 교체된 보스(미노타우로스)를 애니 재생.
## 게임 배선과 무관(_mapcheck/ 삭제 가능). 네트워크 스택 없이 스프라이트/애니만 확인용.

var _boss: AnimatedSprite2D

func _ready() -> void:
	var vp := get_viewport_rect().size

	var arena := load("res://assets/sprites/stage/sanctum_arena.png") as Texture2D
	var gsc: float = minf(vp.x / float(arena.get_width()), vp.y / float(arena.get_height()))

	var ground := Sprite2D.new()
	ground.texture = arena
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground.scale = Vector2(gsc, gsc)
	ground.position = vp / 2.0
	add_child(ground)

	_boss = AnimatedSprite2D.new()
	_boss.sprite_frames = load("res://assets/sprites/enemies/mino_boss_frames.tres") as SpriteFrames
	_boss.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_boss.scale = Vector2(1.5 * gsc, 1.5 * gsc)   # boss.tscn Sprite scale(1.5) × 아레나 맞춤
	_boss.position = vp / 2.0
	add_child(_boss)
	_boss.animation_finished.connect(_on_finished)
	_boss.play(&"idle")

	var lbl := Label.new()
	lbl.text = "BOSS SWAP PREVIEW — 미노타우로스  (2.5초마다 swing, 게임 배선 아님)"
	lbl.position = Vector2(8, 8)
	add_child(lbl)

	var t := Timer.new()
	t.wait_time = 2.5
	t.autostart = true
	add_child(t)
	t.timeout.connect(_on_tick)

func _on_finished() -> void:
	_boss.play(&"idle")

func _on_tick() -> void:
	if _boss.animation == &"idle":
		_boss.play(&"swing")
