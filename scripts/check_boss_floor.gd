extends SceneTree
# 보스방 바닥(TileMapLayer) 검산 — `gen_stage.py boss`의 짝. **스위트가 아니다**(`tests/`가 아니라
# `scripts/`에 있고 `_auto` 접미가 없어 run_tests.sh가 자동 탐색하지 않는다).
#
# 실행:  ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://scripts/check_boss_floor.gd
#
# ⚠ **출력에 `SCRIPT ERROR: ... Identifier not found: EventBus/Net/GameState`가 잔뜩 나오는 것은
#   정상이다** — 이 씬이 무는 글루(`stage.gd`·`boss.gd`·`player.gd`…)가 오토로드 전역 이름을 쓰고
#   `-s`는 그것을 컴파일하지 못한다(rules §5). `run_tests.sh`의 파스 체크도 이 부류를 **명시적으로
#   걸러낸다**. 판정은 아래 `TEST_OK`/`FAIL` 줄과 종료 코드로 본다. 스크립트가 못 붙어도 씬 자체가
#   로드되는지·타일이 실존하는지는 그대로 검사된다(그게 이 스크립트의 요지다).
#
# 🔴 왜 필요한가 — `tests/test_scene_swap_auto.gd`는 이 씬을 **텍스트로만** 읽는다. 즉 "노드 순서"는
#   지키지만 **씬이 실제로 로드되는지·타일이 타일셋에 실존하는지는 아무도 안 본다**(rules §5:
#   "익스포트 성공"은 리소스 무결성의 근거가 아니다 — 2026-07-26 aseprite 사고가 그 형태였다).
#
# 🔴 `instantiate()`는 하지 않는다 — 이 씬은 씬 글루(`stage.gd`·`peer_sync.gd`·`boss.gd`)를 물고
#   있고 그것들은 오토로드 전역 이름을 쓴다(rules §5, `-s`에서 미해결). `SceneState`로 **노드를
#   만들지 않고** 프로퍼티만 읽으면 그 문제를 통째로 비껴간다.
#
# 🔴 판정은 생성기(파이썬)의 격자 모델을 **복제하지 않는다** — 엔진이 실제로 들고 있는 `TileData`의
#   콜리전 폴리곤 수를 본다. 같은 모델을 두 번 쓰면 검출력이 0이다(rules §3 「코드와 테스트가 같은
#   모델을 공유하면 검출력은 0」).

const SCENE := "res://src/stage/stage_boss.tscn"
const CELL := 32
const OK := "TEST_OK"

var _fail := 0
# 셀 좌표 -> 그 셀의 콜리전 폴리곤들(타일 로컬, 중심 원점). 진입 복도 도보 검산에 쓴다.
# 🔴 **셀 단위 «막힘/열림»으로 근사하지 않는다** — 이 타일셋의 콜리전은 **코너 단위**(16px 사분면)라
#   한 칸에 폴리곤이 하나만 있어도 나머지 3/4는 걸어 다닐 수 있다. 셀로 판정하면 멀쩡한 복도를
#   «막혔다»고 부르는 거짓 실패가 난다.
var _cells: Dictionary = {}


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("%s %s" % [OK, msg])
	else:
		_fail += 1
		printerr("FAIL %s" % msg)


func _init() -> void:
	var ps := ResourceLoader.load(SCENE) as PackedScene
	_check(ps != null, "%s 로드됨" % SCENE.get_file())
	if ps == null:
		quit(1)
		return
	var st := ps.get_state()

	# --- 씬 구조: Ground만 바뀌고 보스전 노드가 전부 살아 있는가 ---
	var types := {}
	var props := {}          # 노드 이름 -> {프로퍼티: 값}
	for i in st.get_node_count():
		var n := String(st.get_node_name(i))
		types[n] = String(st.get_node_type(i))
		var p := {}
		for j in st.get_node_property_count(i):
			p[String(st.get_node_property_name(i, j))] = st.get_node_property_value(i, j)
		props[n] = p

	# 🔴 보스방에만 있는 노드 — 전투 칸 템플릿을 찍으면 통째로 사라지는 것들이다.
	for req: String in ["Ground", "BossArena", "Boss", "RockField", "CoopAuthority",
			"PeerSync", "CombatAuthority", "MobSync", "SceneFlow", "ChapterFlow"]:
		_check(types.has(req), "노드 생존: %s" % req)
	_check(String(types.get("Ground", "")) == "TileMapLayer", "Ground = TileMapLayer")
	_check(String(props.get("CoopAuthority", {}).get("boss_eid", "")) == "boss1",
		"CoopAuthority.boss_eid 보존")
	_check(bool(props.get("CoopAuthority", {}).get("stele_only", false)),
		"CoopAuthority.stele_only 보존")

	# 🔴 z 배치 (rules §5 표) — BossArena가 바닥 **위**·늪(-9) **아래**에 남아야 한다.
	#    페이즈2 늪이 아레나 표지에 가리면 안 되고, 바닥이 아레나를 덮어도 안 된다.
	var gz := int(props.get("Ground", {}).get("z_index", 0))
	var az := int(props.get("BossArena", {}).get("z_index", 0))
	_check(gz < az, "z: Ground(%d) < BossArena(%d)" % [gz, az])
	_check(az < -9 + 1 and az <= -10, "z: BossArena(%d) ≤ -10 (늪 -9 아래)" % az)

	# --- 타일 데이터: 타일셋에 실존하는가 + 아레나가 정말 열려 있는가 ---
	var ts := props.get("Ground", {}).get("tile_set") as TileSet
	_check(ts != null, "Ground.tile_set 로드됨")
	if ts == null:
		quit(1)
		return
	var src := ts.get_source(0) as TileSetAtlasSource
	_check(src != null, "타일셋 source 0 = 아틀라스")
	if src == null:
		quit(1)
		return

	var data := props.get("Ground", {}).get("tile_map_data") as PackedByteArray
	_check(data != null and data.size() > 2 and (data.size() - 2) % 12 == 0,
		"tile_map_data 크기 정합 (%d바이트)" % (0 if data == null else data.size()))
	if data == null:
		quit(1)
		return

	# 아레나 표지 = 보스가 서서 싸우는 바닥. 그 위 + 보스 반경만큼은 콜리전이 **한 조각도** 없어야
	# 한다 — 돌진(CHARGE_DASH)이 이동 거리로 끝나는데 중간에 끼면 헛돌고 화면엔 이유가 안 드러난다.
	var arena_pos := props.get("BossArena", {}).get("position", Vector2.ZERO) as Vector2
	var arena_tex := props.get("BossArena", {}).get("texture") as Texture2D
	_check(arena_tex != null, "BossArena.texture 로드됨")
	var asz := Vector2(768, 416) if arena_tex == null else Vector2(arena_tex.get_size())
	# 🔴 **`body_radius`를 여기 숫자로 적지 마라 — 데이터에서 읽는다** (2026-08-02에 한 번 갈라졌다).
	#   보스 덩치를 줄였을 때(1.5 → 1.2 · 반경 63 → 50) 이 상수만 63으로 남아, 검사가 **실제보다 넓은**
	#   아레나를 요구했다. 이번엔 보수적인 방향이라 무해했지만 반대로 키우면 검사가 조용히 느슨해진다.
	var boss_def := load("res://data/enemies/wraith_boss.tres") as EnemyDef
	var boss_r: float = 63.0 if boss_def == null else boss_def.body_radius
	_check(boss_def != null, "wraith_boss.tres 로드됨 (실패 시 폴백 63 — 검사가 낡은 값으로 돈다)")
	var arena := Rect2(arena_pos - asz * 0.5, asz).grow(boss_r)

	var cells := 0
	var missing := 0
	var open_in_arena := 0
	var blocked_in_arena := 0
	var solid_cells := 0
	var minc := Vector2i(99999, 99999)
	var maxc := Vector2i(-99999, -99999)
	var i := 2
	while i + 12 <= data.size():
		var cx := data.decode_s16(i)
		var cy := data.decode_s16(i + 2)
		var ax := data.decode_s16(i + 6)
		var ay := data.decode_s16(i + 8)
		i += 12
		cells += 1
		minc = Vector2i(mini(minc.x, cx), mini(minc.y, cy))
		maxc = Vector2i(maxi(maxc.x, cx), maxi(maxc.y, cy))
		var coord := Vector2i(ax, ay)
		if not src.has_tile(coord):
			missing += 1
			continue
		var td := src.get_tile_data(coord, 0)
		var polys := 0 if td == null else td.get_collision_polygons_count(0)
		if polys > 0:
			solid_cells += 1
		var cp: Array[PackedVector2Array] = []
		for pi: int in polys:
			cp.append(td.get_collision_polygon_points(0, pi))
		_cells[Vector2i(cx, cy)] = cp
		# 이 셀이 아레나(+보스 반경)와 겹치는가
		if arena.intersects(Rect2(cx * CELL, cy * CELL, CELL, CELL)):
			if polys > 0:
				blocked_in_arena += 1
			else:
				open_in_arena += 1

	_check(missing == 0, "모든 타일이 타일셋에 실존 (누락 %d/%d)" % [missing, cells])
	_check(blocked_in_arena == 0,
		"🔴 아레나 안 통행 불가 0칸 (막힌 칸 %d · 열린 칸 %d)" % [blocked_in_arena, open_in_arena])
	_check(open_in_arena > 0, "아레나가 타일로 덮여 있다 (%d칸)" % open_in_arena)
	_check(solid_cells > 0, "가장자리가 닫혀 있다 (콜리전 있는 칸 %d)" % solid_cells)

	# 물리 레이어 = 1(world). 플레이어·보스가 mask 1이라 여기가 어긋나면 **에러 없이 안 막힌다**.
	_check(ts.get_physics_layer_collision_layer(0) == 1,
		"타일셋 물리 레이어 = 1 (실제 %d)" % ts.get_physics_layer_collision_layer(0))

	# 바닥이 덮는 범위 — 보스방엔 카메라 제한이 없다(stage.gd). 앵커가 전부 안에 있는가.
	var world := Rect2(Vector2(minc) * CELL, Vector2(maxc - minc + Vector2i.ONE) * CELL)
	var boss_pos := props.get("Boss", {}).get("position", Vector2.ZERO) as Vector2
	var spawn := props.get("PeerSync", {}).get("spawn_base", Vector2.ZERO) as Vector2
	_check(world.encloses(arena), "바닥 %s ⊇ 아레나+보스반경 %s" % [world, arena])
	_check(world.has_point(boss_pos), "보스 %s 가 바닥 위" % boss_pos)
	_check(world.has_point(spawn), "스폰 %s 이 바닥 위" % spawn)
	print("[bossfloor] 셀 %d · 바닥 %s · 콜리전 칸 %d" % [cells, world, solid_cells])

	_gate_and_corridor(props, world, spawn, boss_pos)
	quit(1 if _fail > 0 else 0)


# 월드 한 점이 실제로 막혀 있는가 — 엔진이 들고 있는 **콜리전 폴리곤**으로 직접 묻는다.
# 🔴 생성기(파이썬)의 정점 격자 모델을 복제하지 않는 것이 이 스크립트의 존재 이유다
#    (rules §3 「코드와 테스트가 같은 모델을 공유하면 검출력은 0」).
func _blocked(w: Vector2) -> bool:
	var c := Vector2i(floori(w.x / float(CELL)), floori(w.y / float(CELL)))
	if not _cells.has(c):
		return true   # 타일 자체가 없다 = 바닥 밖 = 못 간다
	var local := w - (Vector2(c) * float(CELL) + Vector2(CELL, CELL) * 0.5)
	for poly: PackedVector2Array in (_cells[c] as Array[PackedVector2Array]):
		if Geometry2D.is_point_in_polygon(local, poly):
			return true
	return false


# --- 진입 복도·게이트 (2026-08-02 · docs/plans/active/2026-08-02-boss-gate.md) ---
#
# 🔴 헤드리스가 잡을 수 있는 유일한 축이다 — 복도가 안 뚫려 있으면 파티가 **스폰 자리에서 한 걸음도
#    못 나가고**, 게이트 라인 단면이 씬 값과 다르면 낙석이 벽 안에 박히거나 틈이 남는다.
#    둘 다 에러가 없고 스위트도 못 본다(스위트는 씬을 텍스트로만 읽는다).
func _gate_and_corridor(props: Dictionary, world: Rect2, spawn: Vector2, boss_pos: Vector2) -> void:
	# 🔴 먼저 **판정 기계 자체**를 증명한다 — 좌표 변환이 틀리면 아래 단정이 전부 거짓 통과한다.
	_check(not _blocked(boss_pos), "질의 검산: 보스 자리 %s 는 통행 가능" % boss_pos)
	_check(_blocked(world.position + Vector2(4, 4)), "질의 검산: 맵 좌상단 모서리는 통행 불가")

	var g := props.get("BossGate", {}) as Dictionary
	_check(not g.is_empty(), "노드 생존: BossGate")
	if g.is_empty():
		return
	var gx := float(g.get("gate_x", 0.0))
	var tx := float(g.get("trigger_x", 0.0))
	var y0 := float(g.get("gate_y0", 0.0))
	var y1 := float(g.get("gate_y1", 0.0))
	# 플레이어 몸 반폭 — 씬에서 읽는다(여기 숫자를 적으면 몸이 커졌을 때 조용히 갈라진다).
	# ⚠ `load()`가 아니라 **텍스트**로 읽는다 — `player.tscn`을 로드하면 씬 글루가 딸려 와
	#   `SCRIPT ERROR` 소음만 늘고, 필요한 것은 숫자 하나뿐이다(`gen_stage.py`와 같은 관용구).
	var half := 6.0
	var pf := FileAccess.open("res://src/player/player.tscn", FileAccess.READ)
	if pf != null:
		for line: String in pf.get_as_text().split("\n"):
			if line.begins_with("size = Vector2("):
				half = float(line.substr(15).get_slice(",", 0)) * 0.5
				break

	# ⑴ 스폰 → 트리거선까지 **실제로 걸어갈 수 있는가** (몸 폭까지 훑는다)
	var hit := Vector2.INF
	var x := spawn.x
	while x <= tx and hit == Vector2.INF:
		for dy: float in [-half, 0.0, half]:
			if _blocked(Vector2(x, spawn.y + dy)):
				hit = Vector2(x, spawn.y + dy)
				break
		x += 8.0
	_check(hit == Vector2.INF, "★진입 복도 도보: 스폰 x=%.0f → 트리거 x=%.0f 막힘 없음%s"
		% [spawn.x, tx, "" if hit == Vector2.INF else (" (막힌 곳 %s)" % hit)])

	# ⑵ 게이트 라인의 통행 단면이 씬에 찍힌 값과 일치하는가 (16px = 코너 콜리전 격자 해상도)
	# 🔴 **사분면 «중심»을 찍는다(+8), 경계선을 찍지 마라** — 경계 위의 점은 이웃 사분면의 콜리전
	#    폴리곤 **테두리**에도 걸려 `is_point_in_polygon`이 true를 준다. 실제로 이 스크립트가
	#    「272 vs 288」로 파이썬 모델과 어긋났고, 원인은 지형이 아니라 표본 위치였다.
	var step := float(CELL) * 0.5
	var top := -1.0
	var bot := -1.0
	var yy := world.position.y
	while yy < world.end.y:
		if not _blocked(Vector2(gx, yy + step * 0.5)):
			if top < 0.0:
				top = yy
			bot = yy + step
		elif top >= 0.0:
			break
		yy += step
	_check(is_equal_approx(top, y0) and is_equal_approx(bot, y1),
		"★게이트 라인(x=%.0f) 복도 단면 %.0f~%.0f = 씬 값 %.0f~%.0f" % [gx, top, bot, y0, y1])

	# ⑶ 트리거선 자리는 통행 가능해야 한다 (거기 못 서면 게이트가 영원히 안 닫힌다)
	_check(not _blocked(Vector2(tx, spawn.y)), "트리거선 (%.0f,%.0f) 통행 가능" % [tx, spawn.y])
