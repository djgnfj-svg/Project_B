extends SceneTree
# 마을 숲 아트 반영 검증 — rules §5 「'익스포트 성공'을 리소스 무결성의 근거로 쓰지 마라」.
# `ResourceLoader.load`가 null이 아닌지 **직접** 보고, 타일셋의 terrain 구성까지 확인한다.
#
# 실행:
#   ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://scripts/check_village_assets.gd
#
# 🔴 **씬을 `ResourceLoader.load` 하지 않는다 — 텍스트로 파싱해 ext_resource 경로만 훑는다.**
#   `load`를 걸면 자식 스크립트(craft_panel·subjob_panel)가 오토로드 전역(EventBus)을 못 찾아
#   `-s`에서 **반드시** SCRIPT ERROR를 낸다(rules §5). 그러면 판정 3조건의 「SCRIPT ERROR 0」이
#   상시 오염돼 이 검사가 **거짓 실패**를 뿜고, 진짜 고장과 구분이 안 된다.
#   잡으려는 것은 2026-07-26 사고(`ext_resource referenced non-existent resource`)이고,
#   그건 **경로 존재**로 잡힌다 — 스크립트 컴파일은 스위트와 씬 글루 파스 체크의 몫이다.

const TILESET := "res://assets/tilesets/forest_village.tres"
const SCENE := "res://src/village/village.tscn"

const DECOR := [
	"tree_a", "tree_b", "bush_a", "bush_b",
	"grass_a", "grass_b", "grass_c", "grass_d",
	"flower_a", "flower_b", "rock_a", "rock_b",
]
const STATIONS := [
	"res://assets/sprites/village/props/anvil.png",
	"res://assets/sprites/village/train_station.png",
	"res://assets/sprites/village/buildings/gate_48.png",
]


func _init() -> void:
	var bad := 0
	for id: String in DECOR:
		bad += _need("res://assets/sprites/village/decor/%s.png" % id)
	for p: String in STATIONS:
		bad += _need(p)
	bad += _need("res://assets/sprites/village/ground/forest_tiles.png")
	bad += _scene_refs(SCENE)

	var ts := ResourceLoader.load(TILESET) as TileSet
	if ts == null:
		printerr("NULL  %s" % TILESET)
		bad += 1
	else:
		var src := ts.get_source(0) as TileSetAtlasSource
		var tiles := src.get_tiles_count() if src != null else 0
		var mode := ts.get_terrain_set_mode(0)
		print("OK    %s  tiles=%d  mode=%d  terrain=[%s, %s]" % [
			TILESET, tiles, mode, ts.get_terrain_name(0, 0), ts.get_terrain_name(0, 1)])
		# 🔴 코너 모드가 아니면 오토타일이 **에러 없이** 안 붙는다 (gen_tileset.gd 주석)
		if mode != TileSet.TERRAIN_MODE_MATCH_CORNERS:
			printerr("BAD   terrain mode != MATCH_CORNERS(1) — 오토타일이 조용히 안 붙는다")
			bad += 1
		if tiles != 16:
			printerr("BAD   Wang 16타일이 아니다 — tiles=%d" % tiles)
			bad += 1

	# 죽은 참조 회귀 방지 — 지운 텍스처를 씬이 다시 물면 로드가 통째로 깨진다
	if FileAccess.file_exists("res://assets/sprites/village/craft_station.png"):
		printerr("BAD   지운 craft_station.png가 되살아났다")
		bad += 1

	if bad > 0:
		printerr("ASSET_FAIL count=%d" % bad)
		quit(1)
		return
	print("TEST_OK village assets intact")
	quit(0)


func _need(path: String) -> int:
	var r := ResourceLoader.load(path)
	if r == null:
		printerr("NULL  %s" % path)
		return 1
	print("OK    %s" % path)
	return 0


# 씬 텍스트에서 ext_resource 경로를 뽑아 **존재만** 확인한다 (위 주석의 이유로 load하지 않는다).
func _scene_refs(scene_path: String) -> int:
	if not FileAccess.file_exists(scene_path):
		printerr("NULL  %s" % scene_path)
		return 1
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if f == null:
		printerr("OPEN  %s" % scene_path)
		return 1
	var bad := 0
	var seen := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if not line.begins_with("[ext_resource"):
			continue
		var key := "path=\""
		var i := line.find(key)
		if i < 0:
			continue
		var rest := line.substr(i + key.length())
		var p := rest.substr(0, rest.find("\""))
		seen += 1
		if not FileAccess.file_exists(p):
			printerr("MISSING ext_resource — %s (%s)" % [p, scene_path])
			bad += 1
	f.close()
	if bad == 0:
		print("OK    %s  ext_resource=%d 전부 존재" % [scene_path, seen])
	return bad
