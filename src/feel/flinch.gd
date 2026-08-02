extends Node
# 피격 플린치 — 맞은 스프라이트가 피격원 반대 방향으로 살짝 밀렸다 돌아온다(흠칫). 표시 전용, 멀티 안전.
# ⚠ 몸(CharacterBody2D/StaticBody2D)이 아니라 스프라이트 로컬 position만 움직인다 —
#   네트워크 위치 동기화와 무관(판정 좌표는 몸/net_anchor). 스케일=히트스톱, 위치=플린치라 충돌 없음.
# preload로만 쓴다. 연출값 (rules §0 예외).

const KNOCK := 5.0       # 세기 미상일 때의 밀리는 거리(px) — 도입 전 고정값 = 항등 폴백
# 🔴 넉백 거리(px) → 흠칫 거리(px) 배수. **여기가 층①의 유일한 표시 노브다** —
#   세기 자체는 `CombatMath.knock_show_px`가 쥔다(사본 금지, §3 무게 단일 소스).
#   1.0 = "그림이 몸과 같은 거리만큼 튄다". 현행 데이터에서 2.7~12.0px(옛 고정값 5.0을 가운데 둔다).
# ⚠ 실기에서 과하면 **여기를 내려라** — 넉백 세기(밸런스·판정 간격)를 건드리지 마라.
#   스프라이트만 움직이므로 크게 잡으면 접지 그림자(형제 노드)와 눈에 띄게 떨어진다.
const SHOW_MULT := 1.0
const TIME_OUT := 0.06   # 밀려나는 시간
const TIME_BACK := 0.14  # 돌아오는 시간


# knock_px < 0 = 세기 미상(게스트 수신 표시·구버전 경로) → KNOCK 고정값 = 도입 전과 완전 항등.
static func play(sprite: Node2D, dir: Vector2, knock_px: float = -1.0) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	# 상한은 이미 `CombatMath.MAX_KNOCK_PX`가 위에서 쥔다 — 여기서 두 번째 상한을 만들지 않는다
	# (같은 것을 뜻하는 숫자가 둘이 되면 다음 튜닝에서 한쪽만 고친다).
	var dist := KNOCK if (not is_finite(knock_px) or knock_px < 0.0) \
		else maxf(0.0, knock_px * SHOW_MULT)
	var base: Vector2 = sprite.get_meta(&"fl_base", sprite.position)
	sprite.set_meta(&"fl_base", base)
	var prev: Variant = sprite.get_meta(&"fl_tween", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	var tw := sprite.create_tween()
	sprite.set_meta(&"fl_tween", tw)
	tw.tween_property(sprite, "position", base + d * dist, TIME_OUT) \
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
