extends RefCounted
# 잔몹 길찾기 격자 — 지형(물리 레이어 1 = world)을 한 번 구워 두고 A*(JPS)로 우회 경로를 낸다.
#
# 🔴 **호스트 로컬 계산이다 — 네트워크 메시지가 0개다** (rules §1: AI는 호스트에서만 돈다).
#   경로를 전송하지 않는다. 게스트는 지금처럼 `G_MOB_POS` 좌표를 lerp할 뿐이라 이 파일이
#   존재하는 줄도 모른다 — 그래서 새 kind도, 채널 분류도, 신뢰 경계도 늘지 않는다.
#   ⚠ 길찾기는 **방향만** 바꾼다. 이속(`def.move_speed`)을 건드리면 `CombatMath.MOB_LAG_SLACK_SPEED`
#     (90)에서 유도한 각 슬랙이 과소평가되어 창의 팁 타격이 조용히 거부된다(rules §3).
#
# ⚠ **오토로드(Net·EventBus)를 안 쓴다** — 그래야 `-s` 헤드리스가 preload할 수 있고
#   `tests/test_mob_nav_auto.gd`가 격자·경로를 전수로 겨눌 수 있다(rules §5 전역 식별자 함정,
#   §3 J-1 "데이터가 만족해야 하는 상수는 preload 가능한 곳에 둔다"). 씬 글루(부모 탐색·물리
#   세계 접근·상태 기계)는 부르는 쪽(`mob_melee.gd`)이 진다.
#
# --- 왜 이 방식인가 (선택지 셋 중) ---
#   ⑴ NavigationRegion2D + NavigationAgent2D(정석) — 우리 지형은 TileSet의 **물리 폴리곤**이지
#      내비메시가 아니다. 쓰려면 `gen_tileset.gd`(리드 관리)가 navigation polygon을 **물리 폴리곤의
#      여집합**으로 새로 굽고 두 타일셋을 재생성해야 한다. 즉 "실제로 막는 것"과 "길찾기가 아는 것"이
#      **두 개의 진실원**이 되고, 한쪽만 고치면 조용히 갈라진다(이 프로젝트가 반복해 값을 치른 형태).
#   ⑵ 격자 A*(선택) — **판정과 같은 물리 세계**를 질의해 굽는다. 진실원이 하나뿐이고,
#      TileMapLayer든 StaticBody2D든 무엇이 막든 자동으로 따라온다.
#   ⑶ 조향만 — 가장 싸지만 오목 지형에서 갇힌다. 지금 맵이 볼록한 것은 **맵 설계로 문제를 가린 것**이라
#      이 축을 고르면 다음 맵에서 같은 신고가 돌아온다.
#
# --- 실측 (데스크톱 헤드리스, 80×48 = 3840칸) ---
#   굽기(물리 사각 질의 3840회) 0.97ms · 경로 1회 **8.3µs**(JPS) / 21.6µs(비JPS) ·
#   도달 불가(격자 전량 탐색) 최악 497µs · 격자 solid 채우기 0.26ms.
#   ⚠ 웹(WASM 단일 스레드)은 통상 2~4배이므로 **굽기 ≈ 3~4ms(칸당 1회)** · 경로 ≈ 25µs로 본다.
#     매 프레임 굽지 않는다 — 반경 버킷당 1회 굽고, 경로는 `mob_melee`가 초 단위로 스로틀한다.

# 🔴 기본 칸 크기 = 지형 콜리전 격자와 **미러**다. 스테이지 바닥은 Wang 코너 타일이라 32px 타일의
#   **사분면(16px)** 단위로 막힌다(`scripts/gen_stage.py`의 `CELL // 2`). 이보다 크게 잡으면
#   한 칸이 "일부만 막힌" 상태가 되어 굽기가 통째로 보수적이 되고, 작게 잡으면 칸 수만 는다.
#   `tests/test_mob_nav_auto.gd`가 gen_stage.py의 CELL과 대조한다(값을 손으로 맞추지 않게).
const DEFAULT_CELL := 16.0
# 에이전트 반경 양자화(px) — 같은 굵기의 적이 격자를 공유한다. 적 종류가 3~4종이라 실제 격자는 2~3개.
const RADIUS_QUANT := 2.0
# 캐시 상한. 넘치면 **가장 보수적인(가장 큰)** 격자를 재사용한다 — 좁은 틈으로 경로를 내는 것보다
# 멀리 돌아가는 편이 안전하다(에러 없이 나빠지는 방향을 고른다).
const MAX_GRIDS := 6
# 질의 사각을 살짝 줄인다 — 정확히 맞닿은 이웃 칸이 "접촉"으로 잡혀 통행 가능한 칸이 통째로
# 막히는 것을 피한다(경계 여유). 0.98 = 16px 칸에서 0.32px.
const CELL_QUERY_SHRINK := 0.98
# 시작·목표 칸이 막혀 있을 때(벽에 붙어 선 몹/플레이어) 밖으로 훑는 최대 링(칸).
const SNAP_RING_MAX := 6
# 격자 상한 — 터무니없는 area가 들어와도 메모리·시간이 폭주하지 않게.
const MAX_COLS := 512
const MAX_ROWS := 512

var cell: float = DEFAULT_CELL
var origin: Vector2 = Vector2.ZERO
var cols: int = 0
var rows: int = 0

var _grids: Dictionary = {}   # int(반경 버킷) -> AStarGrid2D


# --- 격자 정의 ---

func setup(area: Rect2, cell_size: float = DEFAULT_CELL) -> void:
	cell = maxf(cell_size, 1.0)
	origin = area.position
	cols = clampi(int(ceil(area.size.x / cell)), 0, MAX_COLS)
	rows = clampi(int(ceil(area.size.y / cell)), 0, MAX_ROWS)
	_grids.clear()


func is_ready() -> bool:
	return cols > 0 and rows > 0


func cell_center(cx: int, cy: int) -> Vector2:
	return origin + Vector2((float(cx) + 0.5) * cell, (float(cy) + 0.5) * cell)


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / cell)), int(floor((p.y - origin.y) / cell)))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


# 반경 버킷 — 같은 굵기끼리 격자를 공유한다. 올림이라 **실효 반경 ≥ 실제 반경**(보수적).
func bucket_of(radius: float) -> int:
	return clampi(int(ceil(maxf(radius, 0.0) / RADIUS_QUANT)), 0, 64)


func bucket_radius(bucket: int) -> float:
	return float(bucket) * RADIUS_QUANT


# --- 굽기 ---

# 🔴 굽기는 **에이전트 반경을 포함한 사각**으로 질의한다 — "그 칸 중심에 몸이 서도 벽에 안 겹치는가".
#   별도 팽창(dilation) 패스를 두지 않는 이유: 팽창은 칸 단위라 항상 한 칸(16px) 뭉텅이로
#   보수적이 되는데, 여기서는 반경이 그대로 들어가 **정확**하다. 그리고 이 방식이면
#   「경로는 났는데 몸이 안 들어가는 틈」이 원리적으로 생길 수 없다.
func space_solid_fn(space: PhysicsDirectSpaceState2D, mask: int, radius: float) -> Callable:
	var shape := RectangleShape2D.new()
	shape.size = (Vector2(cell, cell) + Vector2(radius, radius) * 2.0) * CELL_QUERY_SHRINK
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = mask
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return func(c: Vector2) -> bool:
		q.transform = Transform2D(0.0, c)
		return not space.intersect_shape(q, 1).is_empty()


# 합성 지형 주입(테스트·비물리 용도). 게임 경로는 `find_path`가 알아서 굽는다.
func bake_with(radius: float, is_solid: Callable) -> void:
	if is_ready():
		_build(bucket_of(radius), is_solid)


func has_grid(radius: float) -> bool:
	return _grids.has(bucket_of(radius))


# 그 반경의 몸이 이 지점에 설 수 있는가(= 격자상 통행 불가인가). 굽지 않았으면 항상 false.
func solid_at(p: Vector2, radius: float) -> bool:
	var g := _grids.get(bucket_of(radius)) as AStarGrid2D
	if g == null:
		return false
	var c := world_to_cell(p)
	return not in_bounds(c) or g.is_point_solid(c)


func _build(bucket: int, is_solid: Callable) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, cols, rows)
	g.cell_size = Vector2(cell, cell)
	# 🔴 AStarGrid2D의 월드 좌표 = 칸 인덱스 × cell_size + offset. 칸 **중심**을 내놓게 하려면
	#   offset에 격자 원점과 반 칸을 함께 담는다(실측 확인: 칸 (5,24)·cell 16·offset 8 → (88,392)).
	g.offset = origin + Vector2(cell, cell) * 0.5
	# 대각 이동은 양옆이 뚫려 있을 때만 — 벽 모서리를 사선으로 통과하는 경로를 막는다.
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	# 🔴 JPS — 경로가 **꺾이는 지점만** 나온다(실측 54점 → 5점). 웨이포인트를 하나하나 밟는
	#   계단 걸음이 사라지고 A* 비용도 2.6배 싸진다. 별도 스트링풀(퍼널) 패스가 필요 없어지는 것이
	#   이 옵션의 값이다 — 퍼널은 GDScript 루프라 웹에서 ms 단위가 된다.
	g.jumping_enabled = true
	g.update()
	for cy: int in rows:
		for cx: int in cols:
			if bool(is_solid.call(cell_center(cx, cy))):
				g.set_point_solid(Vector2i(cx, cy), true)
	_grids[bucket] = g
	return g


func _ensure(bucket: int, space: PhysicsDirectSpaceState2D, mask: int) -> AStarGrid2D:
	if _grids.has(bucket):
		return _grids[bucket] as AStarGrid2D
	if _grids.size() >= MAX_GRIDS:
		var mx := -1
		for k: int in _grids:
			mx = maxi(mx, k)
		return _grids[mx] as AStarGrid2D
	if space == null:
		return null
	return _build(bucket, space_solid_fn(space, mask, bucket_radius(bucket)))


# --- 경로 ---

# 반환 = 밟아야 할 월드 웨이포인트(**지금 서 있는 칸은 빼고**). 비면 "경로 없음" = 부르는 쪽이
# 기존 직진으로 폴백한다(도입 전과 항등).
# ⚠ `space`는 굽기가 필요할 때만 쓴다 — `_physics_process` 안에서만 유효하므로 **보관하지 않는다**.
func find_path(from: Vector2, to: Vector2, radius: float,
		space: PhysicsDirectSpaceState2D = null, mask: int = 1) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not is_ready():
		return out
	var g := _ensure(bucket_of(radius), space, mask)
	if g == null:
		return out
	var s := _snap(world_to_cell(from), g)
	var e := _snap(world_to_cell(to), g)
	if s.x < 0 or e.x < 0 or s == e:
		return out   # 같은 칸 = 우회할 것이 없다 → 직진 폴백
	var pts := g.get_point_path(s, e)
	if pts.size() < 2:
		return out
	# 첫 점 = 지금 서 있는 칸 중심. 그대로 두면 몹이 살짝 뒤로 당겨진 뒤 출발한다.
	for i: int in range(1, pts.size()):
		out.append(pts[i])
	return out


func _free(c: Vector2i, g: AStarGrid2D) -> bool:
	return in_bounds(c) and not g.is_point_solid(c)


# 벽에 붙어 선 몹·플레이어는 자기 칸이 통행 불가로 잡힌다(반경을 포함해 구웠으니 정상이다).
# 그때 A*를 그냥 포기하면 "벽에 닿는 순간 길찾기가 꺼진다"가 되므로 가장 가까운 통행 가능 칸으로 옮긴다.
func _snap(c: Vector2i, g: AStarGrid2D) -> Vector2i:
	if _free(c, g):
		return c
	for r: int in range(1, SNAP_RING_MAX + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue   # 링 테두리만
				var n := c + Vector2i(dx, dy)
				if not _free(n, g):
					continue
				var d := Vector2(float(dx), float(dy)).length_squared()
				if d < best_d:
					best_d = d
					best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)
