extends SceneTree
# 잔몹 길찾기 — 격자·경로 계약 + **배포되는 스테이지가 실제로 통과 가능한가**.
#
# 왜 테스트가 있나: 이 결함들은 전부 **에러를 안 낸다.**
#   ⑴ A*가 벽을 뚫는 경로를 내면 몹이 벽에 붙어 비비기만 한다(화면엔 걷는 애니만 돈다).
#   ⑵ 반경을 안 넣고 구우면 "경로는 났는데 몸이 안 들어가는 틈"이 생겨 같은 증상이 된다.
#   ⑶ 새 맵 배치가 몹을 가두면 그 칸이 **영영 클리어가 안 된다** — 실기에서 몇 분을 기다려야 안다.
#   ⑷ 격자 칸이 지형 콜리전 격자와 어긋나면 통행 가능한 칸이 통째로 막힌 것으로 구워진다.
#
# ⚠ 이 파일은 **오토로드를 안 쓴다** — 그래서 `-s`로 돈다(rules §5 전역 식별자 함정).
#   `mob_melee.gd`(씬 글루)는 preload할 수 없으므로 **상태 기계 배선은 여기서 못 겨눈다** —
#   그 몫은 `build/nav_shot` 실기 리그와 리드의 실게임 확인이 진다.

const NavGrid := preload("res://src/enemies/nav_grid.gd")
const STAGES := ["res://src/stage/stage_1.tscn", "res://src/stage/stage_2.tscn"]
const WORLD_MASK := 1 << 0

var _fail := 0


func _init() -> void:
	_run()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s" % label)


# --- 합성 지형: 가운데 세로벽 + 아래쪽 틈 ---
# area 640×480 · cell 16 → 40×30칸. 벽 = x ∈ [312, 328), y < 400.
func _wall_solid_fn(gap_y: float, radius: float) -> Callable:
	return func(c: Vector2) -> bool:
		# 반경만큼 부풀린 사각이 벽과 겹치는가 — 물리 굽기(space_solid_fn)와 같은 의미.
		var half := 8.0 + radius
		var wall := Rect2(312.0, -1000.0, 16.0, 1000.0 + gap_y)
		return wall.intersects(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0))


# 경로가 실제로 통행 가능한 곳만 지나는가 — 웨이포인트 사이를 촘촘히 훑는다.
# 🔴 JPS는 꺾이는 지점만 내놓으므로 "점만 통행 가능"으로는 아무것도 보장되지 않는다.
func _path_walkable(nav: NavGrid, from: Vector2, path: PackedVector2Array, radius: float) -> bool:
	var prev := from
	for wp: Vector2 in path:
		var d := wp - prev
		var steps := maxi(1, int(ceil(d.length() / (nav.cell * 0.25))))
		for i: int in range(steps + 1):
			if nav.solid_at(prev + d * (float(i) / float(steps)), radius):
				return false
		prev = wp
	return true


func _synthetic() -> void:
	print("-- 합성 지형(세로벽 + 아래 틈) --")
	var nav := NavGrid.new()
	nav.setup(Rect2(0.0, 0.0, 640.0, 480.0), NavGrid.DEFAULT_CELL)
	_check(nav.is_ready() and nav.cols == 40 and nav.rows == 30, "setup: 640x480 / cell 16 → 40x30칸")

	# 반경 0 — 틈(y ≥ 400)이 넉넉히 열려 있다
	nav.bake_with(0.0, _wall_solid_fn(400.0, 0.0))
	var from := Vector2(120.0, 200.0)
	var to := Vector2(520.0, 200.0)
	var p := nav.find_path(from, to, 0.0)
	_check(not p.is_empty(), "벽 너머 목표 — 경로가 난다")
	_check(_path_walkable(nav, from, p, 0.0), "★ 경로가 통행 불가 칸을 지나지 않는다(JPS 유효성)")
	var deep := 0.0
	for wp: Vector2 in p:
		deep = maxf(deep, wp.y)
	_check(deep >= 396.0, "경로가 아래 틈(y≥400)으로 우회한다 (최대 y=%.0f)" % deep)
	_check(p[p.size() - 1].distance_to(to) <= NavGrid.DEFAULT_CELL, "마지막 웨이포인트가 목표 칸이다")

	# 첫 점이 "지금 서 있는 칸"이면 몹이 뒤로 당겨진 뒤 출발한다 — 빼고 준다.
	_check(p[0].distance_to(from) > 1.0, "첫 웨이포인트가 현재 칸 중심이 아니다")

	# 완전히 막힌 벽 — 경로 없음(= 부르는 쪽이 직진으로 폴백)
	var nav2 := NavGrid.new()
	nav2.setup(Rect2(0.0, 0.0, 640.0, 480.0), NavGrid.DEFAULT_CELL)
	nav2.bake_with(0.0, _wall_solid_fn(9999.0, 0.0))
	_check(nav2.find_path(from, to, 0.0).is_empty(), "도달 불가 — 빈 경로(직진 폴백)")

	# 같은 칸 = 우회할 것이 없다
	_check(nav.find_path(from, from + Vector2(2.0, 2.0), 0.0).is_empty(), "같은 칸 — 빈 경로")

	# 🔴 반경이 굽기에 실제로 들어가는가 — 좁은 틈은 굵은 몸에게 닫혀야 한다.
	#   안 들어가면 "경로는 났는데 몸이 안 들어가는 틈"이 되어 몹이 벽에 붙어 비빈다.
	var narrow := NavGrid.new()
	narrow.setup(Rect2(0.0, 0.0, 640.0, 480.0), NavGrid.DEFAULT_CELL)
	narrow.bake_with(0.0, _wall_solid_fn(460.0, 0.0))     # 틈 = y ∈ [460, 480) = 20px
	narrow.bake_with(14.0, _wall_solid_fn(460.0, 14.0))
	_check(not narrow.find_path(from, to, 0.0).is_empty(), "20px 틈 — 반경 0은 통과")
	_check(narrow.find_path(from, to, 14.0).is_empty(), "★ 20px 틈 — 반경 14는 막힌다(굽기에 반경 반영)")

	# 벽에 붙어 선 몹/플레이어 — 자기 칸이 막혀 있어도 가장 가까운 통행 칸으로 옮겨 경로를 낸다.
	var stuck_from := Vector2(318.0, 460.0)   # 벽 x 범위 안이지만 틈(y≥400) 아래라 통행 가능
	var inside := Vector2(320.0, 100.0)       # 벽 한가운데
	var p3 := nav.find_path(inside, to, 0.0)
	_check(not p3.is_empty(), "시작이 통행 불가 칸이어도 스냅해서 경로가 난다")
	_check(not nav.find_path(from, inside, 0.0).is_empty(), "목표가 통행 불가 칸이어도 스냅한다")
	_check(nav.solid_at(inside, 0.0) and not nav.solid_at(stuck_from, 0.0), "solid_at 판정")


# --- 물리 세계에서 굽기 (게임이 실제로 쓰는 경로) ---
func _decode_tile_data(bytes: PackedByteArray, tml: TileMapLayer) -> int:
	# 헤더 u16 + 셀당 int16 × 6 (x, y, source_id, atlas_x, atlas_y, alternative) — gen_stage.py와 미러.
	var n := 0
	var i := 2
	while i + 12 <= bytes.size():
		tml.set_cell(Vector2i(bytes.decode_s16(i), bytes.decode_s16(i + 2)),
			bytes.decode_s16(i + 4),
			Vector2i(bytes.decode_s16(i + 6), bytes.decode_s16(i + 8)),
			bytes.decode_s16(i + 10))
		i += 12
		n += 1
	return n


func _scene_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _ext_paths(txt: String) -> Dictionary:
	var out := {}
	for line: String in txt.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var pth := line.get_slice('path="', 1).get_slice('"', 0)
		var rid := line.get_slice('id="', 1).get_slice('"', 0)
		out[rid] = pth
	return out


func _vec_of(line: String) -> Vector2:
	var inner := line.get_slice("Vector2(", 1).get_slice(")", 0)
	var parts := inner.split(",")
	return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))


func _bytes_of(line: String) -> PackedByteArray:
	var out := PackedByteArray()
	for tok: String in line.get_slice("PackedByteArray(", 1).get_slice(")", 0).split(","):
		out.append(int(tok.strip_edges()))
	return out


# 배포되는 스테이지 한 칸을 그대로 세우고(바닥 타일 + 물리) 잔몹이 스폰까지 갈 수 있는지 본다.
func _stage(path: String) -> void:
	print("-- %s --" % path.get_file())
	var txt := _scene_text(path)
	if txt.is_empty():
		_check(false, "씬을 읽을 수 없다")
		return
	var ext := _ext_paths(txt)
	var lines := txt.split("\n")

	var ts_path := ""
	var data := PackedByteArray()
	var spawn := Vector2.ZERO
	var mobs: Array = []          # [pos, enemy_def_path]
	var cur_is_mob := false
	var cur_pos := Vector2.ZERO
	for line: String in lines:
		if line.begins_with("[node "):
			cur_is_mob = line.contains('name="Mob')
			cur_pos = Vector2.ZERO
		elif line.begins_with("tile_set = ExtResource"):
			ts_path = String(ext.get(line.get_slice('ExtResource("', 1).get_slice('"', 0), ""))
		elif line.begins_with("tile_map_data = PackedByteArray"):
			data = _bytes_of(line)
		elif line.begins_with("spawn_base = Vector2"):
			spawn = _vec_of(line)
		elif cur_is_mob and line.begins_with("position = Vector2"):
			cur_pos = _vec_of(line)
		elif cur_is_mob and line.begins_with("def = ExtResource"):
			mobs.append([cur_pos, String(ext.get(line.get_slice('ExtResource("', 1).get_slice('"', 0), ""))])

	_check(not ts_path.is_empty() and data.size() > 12 and spawn != Vector2.ZERO and not mobs.is_empty(),
		"씬 파싱 (타일셋·타일데이터·스폰·잔몹 %d)" % mobs.size())
	if ts_path.is_empty() or data.is_empty():
		return

	var tml := TileMapLayer.new()
	tml.tile_set = load(ts_path)
	var cells := _decode_tile_data(data, tml)
	root.add_child(tml)
	await physics_frame
	await physics_frame

	var nav := NavGrid.new()
	var used := tml.get_used_rect()
	var tsz: Vector2i = tml.tile_set.tile_size
	nav.setup(Rect2(Vector2(used.position * tsz), Vector2(used.size * tsz)), NavGrid.DEFAULT_CELL)
	var space := root.get_world_2d().direct_space_state
	_check(cells == used.size.x * used.size.y, "타일 %d칸 디코드" % cells)

	for m: Array in mobs:
		var pos: Vector2 = m[0]
		var edef: EnemyDef = load(String(m[1])) as EnemyDef
		if edef == null:
			_check(false, "적 def 로드 실패: %s" % m[1])
			continue
		var t0 := Time.get_ticks_usec()
		var p := nav.find_path(pos, spawn, edef.body_radius, space, WORLD_MASK)
		var us := Time.get_ticks_usec() - t0
		var name := String(m[1]).get_file()
		# 🔴 이것이 이 스위트의 핵심 트립와이어다 — 배치가 몹을 가두면 그 칸은 영영 클리어가 안 된다.
		_check(not p.is_empty(), "★ %s (%.0f,%.0f) → 스폰 도달 가능 [%d점 %dus]"
			% [name, pos.x, pos.y, p.size(), us])
		_check(_path_walkable(nav, pos, p, edef.body_radius),
			"★ %s 경로가 몸(반경 %.0f)이 지날 수 있는 칸만 지난다" % [name, edef.body_radius])
		_check(not nav.solid_at(pos, edef.body_radius), "%s 스폰 위치가 통행 가능" % name)

	tml.queue_free()


func _mirror() -> void:
	print("-- 미러 --")
	# 🔴 격자 칸 = 지형 콜리전 격자(32px 타일의 사분면)와 미러. 어긋나면 통행 가능한 칸이
	#   "일부만 막힘" 때문에 통째로 막힌 것으로 구워진다 — 에러 없이 몹이 멀리 돌아간다.
	var f := FileAccess.open("res://scripts/gen_stage.py", FileAccess.READ)
	var cell_py := 0.0
	if f != null:
		for line: String in f.get_as_text().split("\n"):
			if line.begins_with("CELL = "):
				cell_py = float(line.get_slice("=", 1).strip_edges())
				break
	_check(cell_py > 0.0 and is_equal_approx(NavGrid.DEFAULT_CELL * 2.0, cell_py),
		"NavGrid.DEFAULT_CELL(%.0f) × 2 == gen_stage.py CELL(%.0f)" % [NavGrid.DEFAULT_CELL, cell_py])


func _run() -> void:
	await process_frame
	print("== 잔몹 길찾기 ==")
	_synthetic()
	_mirror()
	for s: String in STAGES:
		await _stage(s)
	if _fail == 0:
		print("TEST_OK mob_nav")
	else:
		print("TEST_FAILED mob_nav (%d)" % _fail)
	quit(1 if _fail > 0 else 0)
