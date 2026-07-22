extends Node
# 피격 플린치 — 맞은 스프라이트가 피격원 반대 방향으로 살짝 밀렸다 돌아온다(흠칫). 표시 전용, 멀티 안전.
# ⚠ 몸(CharacterBody2D/StaticBody2D)이 아니라 스프라이트 로컬 position만 움직인다 —
#   네트워크 위치 동기화와 무관(판정 좌표는 몸/net_anchor). 스케일=히트스톱, 위치=플린치라 충돌 없음.
# preload로만 쓴다. 연출값 (rules §0 예외).

const KNOCK := 5.0       # 밀리는 거리(px)
const TIME_OUT := 0.06   # 밀려나는 시간
const TIME_BACK := 0.14  # 돌아오는 시간


static func play(sprite: Node2D, dir: Vector2) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	var base: Vector2 = sprite.get_meta(&"fl_base", sprite.position)
	sprite.set_meta(&"fl_base", base)
	var prev: Variant = sprite.get_meta(&"fl_tween", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	var tw := sprite.create_tween()
	sprite.set_meta(&"fl_tween", tw)
	tw.tween_property(sprite, "position", base + d * KNOCK, TIME_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position", base, TIME_BACK) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 그룹 노드들 중 origin에 가장 가까운 것의 위치 (없으면 origin → dir 0 → 위로 흠칫)
static func nearest_pos(origin: Vector2, nodes: Array) -> Vector2:
	var best := origin
	var bd := INF
	for node: Node in nodes:
		var n2 := node as Node2D
		if n2 == null:
			continue
		var dd := origin.distance_squared_to(n2.global_position)
		if dd < bd:
			bd = dd
			best = n2.global_position
	return best
