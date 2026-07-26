extends SceneTree
# 배경 드레싱(바닥 변주·디테일 스캐터·흔들리는 폴리지) 계약 — 2026-07-26.
#
# 왜 표시 전용인데 테스트가 있나: 이 셋의 결함은 **에러를 안 낸다.**
#   ⑴ 폴리지 회전 피벗이 밑동이 아니면 풀이 공중에서 빙빙 돈다(아트가 텍스처를 다시 그릴 때마다 재발 가능).
#   ⑵ 배치가 비결정적이면 호스트·게스트가 다른 지면을 본다 — 무해해 보이지만 "같은 방을 보고 있다"가 깨진다.
#   ⑶ 제외 영역이 안 먹으면 스폰 지점에 덤불이 돋아 시야를 가린다.
# 전부 화면을 봐야만 아는 것들이라 헤드리스로 잡을 수 있는 계약만 여기서 고정한다.
#
# ⚠ 이 스크립트들은 **오토로드를 안 쓴다** — 그래서 `-s`로 돌아간다(rules §5 전역 식별자 함정 회피).
#   씬 스크립트(player/stage 등)를 여기 끌어들이면 통째로 컴파일이 깨진다.
# ⚠ `_ready`는 **다음 프레임에 돈다** — add_child 직후에 자식을 세면 항상 0이다(작성 중 실제로 겪음).

const GroundVariant := preload("res://src/stage/ground_variant.gd")
const GroundDetail := preload("res://src/stage/ground_detail.gd")
const FoliageField := preload("res://src/stage/foliage_field.gd")
const FOLIAGE_SCENE := "res://src/stage/foliage.tscn"
const EXCLUDE := Rect2(0.0, 0.0, 80.0, 80.0)

var _fail := 0


func _init() -> void:
	_run()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s" % label)


func _make_field(count: int, seed_value: int) -> Node2D:
	var fs: Array[Texture2D] = [load("res://assets/sprites/stage/foliage_grass.png"),
		load("res://assets/sprites/stage/foliage_bush.png"),
		load("res://assets/sprites/stage/foliage_tree_s.png")]
	var ex: Array[Rect2] = [EXCLUDE]
	var ff := Node2D.new()
	ff.set_script(FoliageField)
	ff.set("foliage_scene", load(FOLIAGE_SCENE))
	ff.set("area", Rect2(0.0, 0.0, 320.0, 180.0))
	ff.set("textures", fs)
	ff.set("count", count)
	ff.set("rng_seed", seed_value)
	ff.set("exclude", ex)
	root.add_child(ff)
	return ff


func _run() -> void:
	await process_frame

	# --- 바닥 변주: fill_ratio가 0/1일 때의 경계 + 그리드 정렬 ---
	var vs: Array[Texture2D] = [load("res://assets/sprites/stage/ground_32_a.png"),
		load("res://assets/sprites/stage/ground_32_b.png")]
	var gv := Node2D.new()
	gv.set_script(GroundVariant)
	gv.set("area", Rect2(0.0, 0.0, 320.0, 160.0))  # 10×5 = 50칸
	gv.set("variants", vs)
	gv.set("fill_ratio", 1.0)
	root.add_child(gv)
	var empty := Node2D.new()
	empty.set_script(GroundVariant)
	empty.set("area", Rect2(0.0, 0.0, 320.0, 160.0))
	empty.set("variants", vs)
	empty.set("fill_ratio", 0.0)
	root.add_child(empty)
	await process_frame
	_check(gv.get_child_count() == 50, "변주: fill_ratio=1이면 모든 칸을 덮는다 (%d/50)" % gv.get_child_count())
	_check(empty.get_child_count() == 0, "변주: fill_ratio=0이면 한 칸도 안 덮는다")
	# 그리드 정렬 — 반 픽셀이 끼면 이음새에 틈이 보인다
	var aligned := true
	for c in gv.get_children():
		var s := c as Sprite2D
		if s == null or s.centered \
				or not is_equal_approx(fmod(s.position.x, 32.0), 0.0) \
				or not is_equal_approx(fmod(s.position.y, 32.0), 0.0):
			aligned = false
			break
	_check(aligned, "변주: 타일이 32px 그리드에 정렬되고 centered=false다")

	# --- 디테일 스캐터: 개수·범위·결정론 ---
	var ds: Array[Texture2D] = [load("res://assets/sprites/stage/detail_grass.png"),
		load("res://assets/sprites/stage/detail_pebble.png"),
		load("res://assets/sprites/stage/detail_crack.png"),
		load("res://assets/sprites/stage/detail_flower.png")]
	var area := Rect2(0.0, 0.0, 320.0, 180.0)
	var made: Array[Node2D] = []
	for i in 2:
		var gd := Node2D.new()
		gd.set_script(GroundDetail)
		gd.set("area", area)
		gd.set("textures", ds)
		gd.set("count", 40)
		gd.set("rng_seed", 4242)  # 같은 시드 → 같은 배치여야 한다
		root.add_child(gd)
		made.append(gd)
	await process_frame
	_check(made[0].get_child_count() == 40, "디테일: count만큼 생성 (%d/40)" % made[0].get_child_count())
	var in_area := true
	for c in made[0].get_children():
		var n2 := c as Node2D
		# grow(1) = 부동소수 경계 여유. 범위 밖으로 새면 맵 밖 공허에 무늬가 뜬다
		if n2 == null or not area.grow(1.0).has_point(n2.position):
			in_area = false
			break
	_check(in_area, "디테일: 전부 지정 범위 안")
	var same := made[0].get_child_count() == made[1].get_child_count()
	if same:
		for i in made[0].get_child_count():
			var a := made[0].get_child(i) as Node2D
			var b := made[1].get_child(i) as Node2D
			if a == null or b == null or not a.position.is_equal_approx(b.position):
				same = false
				break
	# 🔴 결정론이 깨지면 호스트·게스트 지면이 갈린다 — randi() 전역을 쓰면 여기가 빨개진다
	_check(same, "디테일: 같은 시드 → 같은 배치 (결정론)")

	# --- 폴리지: 개수·제외 영역·🔴 밑동 피벗 ---
	var ff := _make_field(24, 917)
	await process_frame
	_check(ff.get_child_count() == 24, "폴리지: count만큼 심는다 (%d/24)" % ff.get_child_count())
	var respected := true
	var pivot_ok := true
	var textured := true
	var phases := {}
	for c in ff.get_children():
		var n2 := c as Node2D
		if n2 == null:
			continue
		if EXCLUDE.has_point(n2.position):
			respected = false
		var sp := n2.get_node_or_null("Sprite") as Sprite2D
		if sp == null or sp.texture == null:
			textured = false
			continue
		# 🔴 밑동 = 회전축. offset.y가 -높이/2여야 노드 원점이 텍스처 하단에 앉는다
		#   (아트 보고: foliage_* 3종 모두 밑동이 캔버스 하단 중앙).
		if not is_equal_approx(sp.offset.y, -float(sp.texture.get_height()) * 0.5):
			pivot_ok = false
		phases[snappedf(float(n2.get("wind_phase")), 0.001)] = true
	_check(respected, "폴리지: 제외 영역(스폰 지점)에는 안 심는다")
	_check(textured, "폴리지: 전부 텍스처가 물렸다")
	_check(pivot_ok, "폴리지: 회전 피벗이 밑동(offset.y = -높이/2)")
	# 위상이 전부 같으면 숲이 한 몸처럼 흔들려 인형처럼 보인다
	_check(phases.size() > 1, "폴리지: 바람 위상이 개체마다 흩어진다 (%d종)" % phases.size())

	# --- 충돌 경계: 감지만 하고 아무에게도 안 잡힌다 ---
	var one := (ff.get_child(0) as Area2D) if ff.get_child_count() > 0 else null
	if one != null:
		# layer=0이 아니면 남의 질의(공격 판정 등)에 지형이 걸린다 — 판정에 개입하면 안 된다
		_check(one.collision_layer == 0, "폴리지: collision_layer=0 (아무 판정에도 안 잡힌다)")
		_check(one.collision_mask == 6, "폴리지: mask = player_body|enemy_body (6)")
		_check(not one.monitorable, "폴리지: monitorable=false")
	else:
		_check(false, "폴리지: 인스턴스가 없다")

	if _fail == 0:
		print("TEST_OK stage_dressing")
	else:
		print("TEST_FAIL stage_dressing failures=%d" % _fail)
	quit(1 if _fail > 0 else 0)
