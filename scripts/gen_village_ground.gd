extends SceneTree
# 마을 숲 바닥 초기 레이아웃 생성기 (일회성 시드 — 이후 다듬기는 에디터 Rect Tool에서).
#
# 실행:
#   ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://scripts/gen_village_ground.gd
#   → build/village_ground_data.txt 에 `tile_map_data = PackedByteArray(...)` 한 줄을 쓴다.
#     그 줄을 village.tscn의 [node name="Ground" type="TileMapLayer"] 블록에 붙인다.
#
# 🔴 **씬을 로드해 다시 pack하지 않는다.** `PackedScene.pack()`으로 재직렬화하면 인스턴스
#   자식(HUD·CraftPanel·SubJobPanel)의 편집 상태가 헤드리스에서 보존된다는 보장이 없어,
#   인스턴스가 인라인 노드로 풀려 버릴 수 있다 — 그러면 패널을 고쳐도 마을에만 반영이 안 되는
#   조용한 갈라짐이 생긴다. 그래서 **타일 데이터만** 뽑고 씬 텍스트는 사람이 손대는 곳만 바뀐다.
#
# ⚠ 좌표는 village.tscn의 노드 위치와 미러다 — 기능 위치를 옮기면 길이 끊긴 채 남는다
#   (에러 없음, 화면에서만 드러남). 그래서 값을 베끼지 않고 씬 파일에서 직접 읽는다.

const SCENE_PATH := "res://src/village/village.tscn"
const TILESET_PATH := "res://assets/tilesets/forest_village.tres"
const OUT_PATH := "res://build/village_ground_data.txt"

const CELL := 32
const COLS := 30  # 960 / 32 — village.gd MAP_RECT와 미러
const ROWS := 18  # 576 / 32

const TERRAIN_SET := 0
const T_DIRT := 0
const T_GRASS := 1

# 흙길 반폭(셀). **0 = 1셀(32px) 폭.**
# ⚠ 1(=3셀·96px)이었을 때 실기에서 화면 절반이 흙이 되어 「숲」이 아니라 「공터」로 읽혔다
#   (2026-08-01 실기 확인). 이 값을 올리면 `village.tscn`의 스캐터 `exclude` rect도 같이 넓혀야
#   한다 — 안 그러면 넓어진 길 위에 덤불이 돋는다(에러 없음, 화면에서만 드러남).
const PATH_HALF := 0


func _init() -> void:
	var ts := load(TILESET_PATH) as TileSet
	if ts == null:
		printerr("ERROR: TileSet 로드 실패 — %s" % TILESET_PATH)
		quit(1)
		return

	var layer := TileMapLayer.new()
	layer.tile_set = ts
	root.add_child(layer)

	# --- 1) 전면 숲잔디 ---
	var all: Array[Vector2i] = []
	for y in range(ROWS):
		for x in range(COLS):
			all.append(Vector2i(x, y))
	layer.set_cells_terrain_connect(all, TERRAIN_SET, T_GRASS, false)

	# --- 2) 기능 지점을 씬 텍스트에서 읽어 셀 좌표로 ---
	var pos := _read_scene_positions()
	var spawn_cell := _cell_of(pos.get("PeerSync", Vector2(120, 285)))
	var craft_cell := _cell_of(pos.get("CraftStation", Vector2(138, 165)))
	var train_cell := _cell_of(pos.get("TrainStation", Vector2(700, 380)))
	var gate_cell := _cell_of(pos.get("Gate", Vector2(882, 270)))

	# --- 3) 흙길: 스폰에서 출발하는 메인 가로축 + 각 시설로 뻗는 가지 ---
	var road: Dictionary = {}  # Vector2i -> true (중복 제거)
	var hub_y := spawn_cell.y
	_add_line(road, Vector2i(spawn_cell.x, hub_y), Vector2i(gate_cell.x, hub_y))  # 메인 가로길
	_add_line(road, Vector2i(spawn_cell.x, hub_y), Vector2i(spawn_cell.x, craft_cell.y))
	_add_line(road, Vector2i(spawn_cell.x, craft_cell.y), Vector2i(craft_cell.x, craft_cell.y))
	_add_line(road, Vector2i(train_cell.x, hub_y), Vector2i(train_cell.x, train_cell.y))
	_add_line(road, Vector2i(gate_cell.x, hub_y), Vector2i(gate_cell.x, gate_cell.y))

	var road_cells: Array[Vector2i] = []
	for k: Vector2i in road:
		road_cells.append(k)
	layer.set_cells_terrain_connect(road_cells, TERRAIN_SET, T_DIRT, false)

	# --- 4) tile_map_data 한 줄로 출력 ---
	var data := layer.tile_map_data
	var parts := PackedStringArray()
	for b: int in data:
		parts.append(str(b))
	var line := "tile_map_data = PackedByteArray(%s)" % ", ".join(parts)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("ERROR: 출력 파일 열기 실패 — %s" % OUT_PATH)
		quit(1)
		return
	f.store_string(line)
	f.close()

	print("GROUND_OK cells=%d road=%d bytes=%d out=%s" % [all.size(), road_cells.size(), data.size(), OUT_PATH])
	print("  spawn=%s craft=%s train=%s gate=%s" % [spawn_cell, craft_cell, train_cell, gate_cell])
	quit(0)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x) / CELL, 0, COLS - 1), clampi(int(p.y) / CELL, 0, ROWS - 1))


# village.tscn을 텍스트로 훑어 노드별 position(PeerSync는 spawn_base)을 읽는다.
# 씬을 instantiate하지 않는 이유 = 위 pack 주석과 같다(부작용 0으로 유지).
func _read_scene_positions() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(SCENE_PATH):
		return out
	var f := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if f == null:
		return out
	var current := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("[node name=\""):
			var rest := line.substr(12)
			current = rest.substr(0, rest.find("\""))
		elif current != "" and (line.begins_with("position = Vector2(") or line.begins_with("spawn_base = Vector2(")):
			if not out.has(current):  # 첫 값만 (자식 Sprite의 position에 안 덮이게)
				out[current] = _parse_vec2(line)
	f.close()
	return out


func _parse_vec2(line: String) -> Vector2:
	var open := line.find("(")
	var close := line.find(")", open)
	if open < 0 or close < 0:
		return Vector2.ZERO
	var body := line.substr(open + 1, close - open - 1)
	var bits := body.split(",")
	if bits.size() < 2:
		return Vector2.ZERO
	return Vector2(bits[0].strip_edges().to_float(), bits[1].strip_edges().to_float())


# 축 정렬 선분만 받아 반폭 PATH_HALF로 두껍게 칠한다.
# 🔴 대각선을 넘기면 사각형이 통째로 칠해진다 — 에러가 안 나므로 여기서 막는다.
func _add_line(out: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if a.x != b.x and a.y != b.y:
		printerr("ERROR: _add_line은 축 정렬만 받는다 — %s → %s" % [a, b])
		return
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	for x in range(x0 - PATH_HALF, x1 + PATH_HALF + 1):
		for y in range(y0 - PATH_HALF, y1 + PATH_HALF + 1):
			if x < 0 or x >= COLS or y < 0 or y >= ROWS:
				continue
			out[Vector2i(x, y)] = true
