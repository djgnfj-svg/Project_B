extends Node2D
# 데미지 숫자 팝 (src/feel) — combat_impact 구독, 피격 지점(월드 좌표)에 뜨는 라벨.
# 오토로드 Node2D: /root 아래라 현재 Camera2D의 캔버스 변환을 그대로 받아 월드 좌표에 그려진다
# (스테이지 3종을 안 건드리고 전 씬 커버). 표시 전용·각 클라 로컬 — 전투 없는 씬(로비·마을)에선
# combat_impact가 안 와 아무것도 안 한다. 라벨 폰트는 전역 테마(Galmuri9)가 자동 적용.
# 연출값 (rules §0 예외).

const RISE := 20.0        # 떠오르는 높이(px)
const LIFE := 0.55        # 수명(초)
const SPREAD := 9.0       # 겹친 타격이 안 포개지게 좌우 랜덤(px)
const BOX_W := 48.0       # 라벨 폭(중앙 정렬 기준)
const POP_SCALE := 1.45   # 등장 스케일 팝
const COLORS := {"enemy": Color(1.0, 1.0, 1.0), "player": Color(1.0, 0.42, 0.36)}


func _ready() -> void:
	EventBus.combat_impact.connect(_on_impact)


func _on_impact(kind: String, world_pos: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.z_index = 100
	lbl.size = Vector2(BOX_W, 16.0)
	lbl.pivot_offset = Vector2(BOX_W * 0.5, 8.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate = COLORS.get(kind, Color.WHITE)
	lbl.add_theme_constant_override(&"outline_size", 4)
	lbl.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	add_child(lbl)
	var start := world_pos + Vector2(randf_range(-SPREAD, SPREAD) - BOX_W * 0.5, -10.0)
	lbl.position = start
	lbl.scale = Vector2.ONE * POP_SCALE
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", start.y - RISE, LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, LIFE).set_ease(Tween.EASE_IN)
	tw.tween_callback(lbl.queue_free)
