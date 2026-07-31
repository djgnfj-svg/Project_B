extends Node2D

## 임시 디버그 미리보기 — 완성맵+보스 PNG를 화면에 맞춰 띄운다. (게임 배선과 무관, _mapcheck/ 통째로 삭제 가능)

func _ready() -> void:
	var tex := load("res://_mapcheck/map_boss.png") as Texture2D
	if tex == null:
		push_error("map_boss.png 로드 실패 — --import 먼저 필요")
		return
	var vp := get_viewport_rect().size
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sc: float = minf(vp.x / float(tex.get_width()), vp.y / float(tex.get_height()))
	s.scale = Vector2(sc, sc)
	s.position = vp / 2.0
	add_child(s)

	var lbl := Label.new()
	lbl.text = "DEBUG PREVIEW  —  _mapcheck/preview.tscn  (게임 배선 아님)"
	lbl.position = Vector2(8, 8)
	add_child(lbl)
