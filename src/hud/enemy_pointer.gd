extends Control
# 화면 밖에 남은 적을 화면 가장자리 화살표로 가리킨다 (사용자 요청 2026-08-01:
# "맵에 남은 몬스터가 어디 있는지 모르니까 화살표로 표시").
#
# 🔴 **표시 전용이다** — 판정·상태 확정·네트워크 메시지가 0개다(rules §2 손맛 계층과 같은 성격).
#   각 클라가 자기 화면의 `enemy` 그룹만 훑는다. 게스트도 잔몹 좌표를 G_MOB_POS로 이미 받고
#   있으므로 호스트와 같은 곳을 가리킨다.
#
# ⚠ 스테이지가 1280×768인데 뷰포트는 640×360이라 **적 대부분이 화면 밖**이다 — 이 기능이 없으면
#   클리어 조건(전멸)을 남겨두고 빈 맵을 헤매게 된다.
#
# ⚠ 씬 스왑 프레임엔 이전 씬 적이 아직 "enemy" 그룹에 남아 있다(queue_free는 프레임 끝, rules §5).
#   한 프레임 유령 화살표가 뜰 수 있으나 표시 전용이라 무해하고 다음 프레임에 사라진다.

const POINTER_TEX := preload("res://assets/sprites/ui/enemy_pointer.png")

# 연출값 (rules §0 예외 — 사용자가 조인다)
const MARGIN_PX := 18.0        # 화면 가장자리에서 안쪽으로 이만큼 띄운다(잘리지 않게)
# 🔴 **거리는 크기가 아니라 알파로 표현한다** — 픽셀아트에서 비정수 스케일은 픽셀을 뭉갠다
#   (`ground_detail`이 "회전은 픽셀아트를 뭉갠다"고 flip만 쓰는 것과 같은 이유). 스케일은
#   손대지 않고 1.0 고정이다. ⚠ 회전은 어쩔 수 없이 쓴다 — 방향이 이 지시자의 본질이라
#   8방향 스프라이트를 따로 두지 않는 한 대안이 없다(그건 과한 아트 부채다).
const NEAR_ALPHA := 0.95       # 가까운 적 — 또렷하게
const FAR_ALPHA := 0.45        # 먼 적 — 흐리게
const FAR_DIST := 720.0        # 이 월드 거리 이상이면 FAR_ALPHA
const EDGE_SLACK := 4.0        # 화면 안 판정 여유 — 경계에 걸친 적이 깜빡이는 것을 막는다

var _pool: Array[Sprite2D] = []


func _ready() -> void:
	# 🔴 화면을 덮는 Control은 mouse_filter를 IGNORE로 — 기본값 STOP이면 그 아래 게임 클릭을
	#   통째로 먹어 공격·상호작용이 죽는다(rules §5 UI 1번 함정, 헤드리스가 절대 못 잡는다).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var xf := vp.get_canvas_transform()          # 월드 → 화면
	var size := vp.get_visible_rect().size
	var center := size * 0.5
	# 화면 중심의 월드 좌표 — 거리 기준점. 플레이어 노드를 찾지 않아도 되고(카메라가 플레이어를
	# 따라가므로 사실상 같다) 플레이어가 죽어 없는 순간에도 안전하다.
	var center_world := xf.affine_inverse() * center
	var half := center - Vector2(MARGIN_PX, MARGIN_PX)

	var used := 0
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Node2D
		if e == null or not _is_alive(e):
			continue
		var screen_pos := xf * e.global_position
		# 화면 안이면 화살표가 필요 없다(적 스프라이트가 이미 보인다)
		if absf(screen_pos.x - center.x) <= half.x - EDGE_SLACK \
				and absf(screen_pos.y - center.y) <= half.y - EDGE_SLACK:
			continue
		var dir := screen_pos - center
		if dir.length_squared() < 0.01:
			continue
		# 중심에서 dir 방향으로 화면 사각 경계까지 — 두 축 중 먼저 닿는 쪽이 교차점이다
		var t := INF
		if absf(dir.x) > 0.001:
			t = minf(t, half.x / absf(dir.x))
		if absf(dir.y) > 0.001:
			t = minf(t, half.y / absf(dir.y))
		if not is_finite(t):
			continue

		var spr := _acquire(used)
		used += 1
		spr.position = center + dir * t
		spr.rotation = dir.angle()
		var d := center_world.distance_to(e.global_position)
		var a := lerpf(NEAR_ALPHA, FAR_ALPHA, clampf(d / FAR_DIST, 0.0, 1.0))
		spr.modulate = Color(1.0, 1.0, 1.0, a)
		spr.visible = true

	# 남는 것은 숨긴다(free하지 않는다 — 매 프레임 노드를 만들고 지우면 그게 더 비싸다)
	for i in range(used, _pool.size()):
		_pool[i].visible = false


# 살아 있는가 — 권한과 무관한 표시 판단이라 각 클라가 자기 `Health`를 본다.
# ⚠ 게스트의 Health는 호스트 확정(ehp)을 받아 갱신되므로 편도 지연만큼 늦다. 죽은 적을
#   그 창 동안 가리키는 것은 무해하다(적 스프라이트도 같은 창 동안 살아 있다 — 일관된다).
func _is_alive(e: Node2D) -> bool:
	var h := e.get_node_or_null("Health")
	if h == null:
		return e.visible          # Health가 없는 개체는 표시 상태로 판단
	return not bool(h.call("is_dead"))


func _acquire(i: int) -> Sprite2D:
	while _pool.size() <= i:
		var s := Sprite2D.new()
		s.texture = POINTER_TEX
		s.visible = false
		add_child(s)
		_pool.append(s)
	return _pool[i]
