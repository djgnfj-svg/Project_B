extends SceneTree
# PixelLab Wang 타일셋(16타일) → Godot TileSet 리소스 변환기 (재실행 가능한 생성 도구).
# 관행 = scripts/gen_sfx.py·gen_bgm.js와 같은 자리 — 원본을 다시 뽑으면 이걸 다시 돌린다.
#
# 실행:
#   ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://scripts/gen_tileset.gd -- \
#       --meta=res://assets/sprites/village/ground/forest_tiles_meta.json \
#       --tex=res://assets/sprites/village/ground/forest_tiles.png \
#       --out=res://assets/tilesets/forest_village.tres \
#       --lower=흙길 --upper=숲 잔디
#
# 🔴 **mode = TERRAIN_MODE_MATCH_CORNERS(1)이다 — PixelLab 공식 문서의 컨버터는 0을 쓴다.**
#   0 = MATCH_CORNERS_AND_SIDES라 side peering bit까지 요구하는데, Wang 16타일 셋에는
#   코너 정보밖에 없다. 그대로 두면 에디터 Terrains 탭에서 오토타일이 **에러 없이 안 붙는다**.
#
# 🔴 **시트 위치는 메타데이터 bounding_box에서만 유도한다.** 타일 이름 `wang_N`의 N은 시트
#   인덱스가 아니라 코너 비트값이고, `original_position`은 생성 격자(4×8 등) 좌표다 —
#   둘 중 아무거나 시트 좌표로 쓰면 타일이 뒤섞여 가로 줄무늬가 생긴다(PixelLab 문서 경고).
#
# ⚠ PNG는 ext_resource 참조로 남는다(인라인 PackedByteArray 금지) — 공식 컨버터는 이미지
#   바이트를 .tres에 통째로 박아 400KB짜리 텍스트를 만든다. 그러면 git diff가 죽고
#   rules §4 「게임은 .png/.tres만 본다」의 에셋 경계도 흐려진다.

# 코너 이름 → Godot CellNeighbor 상수 (MATCH_CORNERS가 쓰는 네 비트)
const CORNER_BITS := {
	"NW": TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	"NE": TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	"SW": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	"SE": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
}

const TERRAIN_LOWER := 0
const TERRAIN_UPPER := 1


func _init() -> void:
	var args := _parse_args()
	var meta_path: String = args.get("meta", "")
	var tex_path: String = args.get("tex", "")
	var out_path: String = args.get("out", "")
	if meta_path.is_empty() or tex_path.is_empty() or out_path.is_empty():
		printerr("ERROR: --meta=, --tex=, --out= 셋 다 필요하다")
		quit(1)
		return

	var meta := _read_json(meta_path)
	if meta.is_empty():
		quit(1)
		return

	var tex := load(tex_path) as Texture2D
	if tex == null:
		printerr("ERROR: 텍스처 로드 실패 — %s (--import를 먼저 돌렸나?)" % tex_path)
		quit(1)
		return

	var data: Dictionary = meta.get("tileset_data", {})
	var tiles: Array = data.get("tiles", [])
	var size_d: Dictionary = data.get("tile_size", {})
	var tw := int(size_d.get("width", 32))
	var th := int(size_d.get("height", 32))
	if tiles.is_empty() or tw <= 0 or th <= 0:
		printerr("ERROR: 메타데이터에 tiles/tile_size가 없다")
		quit(1)
		return

	# terrain 이름 — 인자 우선, 없으면 메타데이터 설명에서 가져온다(길어서 잘라 쓴다)
	var lower_name: String = args.get("lower", str(meta.get("lower_description", "lower")))
	var upper_name: String = args.get("upper", str(meta.get("upper_description", "upper")))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tw, th)
	# 🔴 terrain_set·terrain을 먼저 만든다 — peering bit는 존재하는 terrain id만 받는다
	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	ts.add_terrain(0)
	ts.add_terrain(0)
	ts.set_terrain_name(0, TERRAIN_LOWER, lower_name)
	ts.set_terrain_name(0, TERRAIN_UPPER, upper_name)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tw, th)
	ts.add_source(src, 0)

	# terrain 팔레트 색을 베이스 타일(코너 4개가 전부 같은 terrain)의 중심 픽셀에서 뽑는다.
	# 안 하면 Godot이 자동 배정한 비슷한 갈색 두 개가 나와 에디터에서 흙/잔디 구분이 안 된다.
	var img := tex.get_image()
	var base_color := {}

	var made := 0
	for t: Variant in tiles:
		var tile: Dictionary = t
		var bb: Dictionary = tile.get("bounding_box", {})
		var corners: Dictionary = tile.get("corners", {})
		if bb.is_empty() or corners.size() != 4:
			printerr("WARN: 타일 %s 건너뜀 (bbox/corners 없음)" % tile.get("name", "?"))
			continue
		# bbox 픽셀 → 아틀라스 셀 좌표
		var px := int(bb.get("x", 0))
		var py := int(bb.get("y", 0))
		var coords := Vector2i(px / tw, py / th)
		if not src.has_tile(coords):
			src.create_tile(coords)
		var td := src.get_tile_data(coords, 0)
		td.terrain_set = 0
		var upper_count := 0
		for key: String in CORNER_BITS:
			var is_upper := str(corners.get(key, "lower")) == "upper"
			if is_upper:
				upper_count += 1
			td.set_terrain_peering_bit(CORNER_BITS[key], TERRAIN_UPPER if is_upper else TERRAIN_LOWER)
		# center terrain — MATCH_CORNERS는 판정에 안 쓰지만, 비워 두면 에디터 팔레트에서
		# 그 타일이 "terrain 미지정"으로 흐리게 나온다. 다수결 코너로 채운다(무해).
		var center_terrain := TERRAIN_UPPER if upper_count >= 2 else TERRAIN_LOWER
		td.terrain = center_terrain
		if (upper_count == 0 or upper_count == 4) and img != null and not base_color.has(center_terrain):
			base_color[center_terrain] = img.get_pixel(px + tw / 2, py + th / 2)
		made += 1

	for tid: int in [TERRAIN_LOWER, TERRAIN_UPPER]:
		if base_color.has(tid):
			ts.set_terrain_color(0, tid, base_color[tid])

	var err := ResourceSaver.save(ts, out_path)
	if err != OK:
		printerr("ERROR: 저장 실패 (%d) — %s" % [err, out_path])
		quit(1)
		return
	print("TILESET_OK tiles=%d size=%dx%d out=%s" % [made, tw, th, out_path])
	print("  terrain 0 = %s / terrain 1 = %s (mode = MATCH_CORNERS)" % [lower_name, upper_name])
	quit(0)


# `-- --key=value` 형태 인자 파싱 (run_tests.sh 관행과 같은 모양)
func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var eq := body.find("=")
		if eq > 0:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		printerr("ERROR: 메타데이터 없음 — %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("ERROR: 열기 실패 — %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	printerr("ERROR: JSON 파싱 실패 — %s" % path)
	return {}
