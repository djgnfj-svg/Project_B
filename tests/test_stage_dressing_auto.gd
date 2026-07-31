extends SceneTree
# 씬 계약 — ⑴ 배경 드레싱(바닥 변주·디테일 스캐터·흔들리는 폴리지, 2026-07-26)
#           ⑵ 형제 컴포넌트 배선(`*_path` NodePath export 전수, 2026-07-27 netreview M2)
# 둘의 공통점 = **씬 파일에만 있고 코드에는 없는 계약**이라 깨져도 에러가 안 난다. 그래서 한 스위트다.
# (⑵는 `_check_scene_wiring()` — 이 파일 아래쪽. 다른 스위트가 씬을 안 읽어서 여기 얹었다.)
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
	var shadow_ok := true
	var shadow_z_ok := true
	var shadow_scaled := true
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
		# 🔴 접지 그림자 (2026-08-01) — 세 가지가 전부 조용히 깨지는 부류다.
		var sh := n2.get_node_or_null("Shadow") as Sprite2D
		if sh == null or sh.texture == null or not sh.visible:
			shadow_ok = false
		else:
			# ⑴ 폴리지 몸통(-3)보다 **아래**여야 한다. 잔몹 그림자(-2)를 그대로 베끼면
			#    그림자가 나무 위에 떠서 검은 얼룩이 된다 — 에러 없음.
			if sh.z_index >= sp.z_index:
				shadow_z_ok = false
			# ⑵ 크기를 스프라이트 폭에서 유도한다 — 안 하면 64px 나무와 32px 풀이 같은 그림자를 쓴다
			if sh.scale.x <= 0.0 or is_equal_approx(sh.scale.x, 1.0) and sp.texture.get_width() != 28:
				shadow_scaled = false
		phases[snappedf(float(n2.get("wind_phase")), 0.001)] = true
	_check(respected, "폴리지: 제외 영역(스폰 지점)에는 안 심는다")
	_check(textured, "폴리지: 전부 텍스처가 물렸다")
	_check(pivot_ok, "폴리지: 회전 피벗이 밑동(offset.y = -높이/2)")
	_check(shadow_ok, "폴리지: 접지 그림자가 물렸다")
	_check(shadow_z_ok, "★폴리지: 그림자 z가 몸통보다 아래다 (위면 나무에 검은 얼룩)")
	_check(shadow_scaled, "폴리지: 그림자 크기를 스프라이트 폭에서 유도했다")
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

	_check_scene_wiring()
	_check_village_dressing()

	if _fail == 0:
		print("TEST_OK stage_dressing")
	else:
		print("TEST_FAIL stage_dressing failures=%d" % _fail)
	quit(1 if _fail > 0 else 0)


# --- 씬 형제 배선 계약 (2026-07-27 netreview M2) ---
#
# 🔴 왜 여기 있나: 형제 컴포넌트 배선(`*_path` NodePath export)이 **빠져도 에러가 안 난다.** 새 씬은
#   기존 씬을 복제해 만드는 것이 관례(rules §2)라 다음 씬에서 한 줄이 빠지는 경로가 상시 열려 있다.
#   `ArrowField.peer_sync_path`가 특히 위험한데, 빠지면 **표시만 특성을 잃고 판정은 그대로**라
#   "판정 > 표시"(화면에 없는데 맞는다)가 된다 — `authoritative_combo` 규약이 금지한 방향이다.
#   런타임 `push_error`는 그 씬을 실제로 띄워야 보이므로 너무 늦다.
#
# ⚠ **인스턴스하지 않고 `SceneState`만 읽는다** — 씬을 띄우면 오토로드가 없는 `-s`에서 깨진다(rules §5).
#   그래서 이 검사는 스크립트를 실행하지 않고 저장된 노드/프로퍼티 표만 본다.
# ⚠ 전 `src/**/*.tscn` × 모든 `*_path` 프로퍼티가 대상이다 — `peer_sync_path`만 겨누면 다음에 생길
#   형제 배선(현재도 `drop_authority_path`·`scene_flow_path`가 있다)이 같은 방식으로 조용히 빠진다.
func _check_scene_wiring() -> void:
	var scenes: Array[String] = []
	_collect_scenes("res://src", scenes)
	_check(scenes.size() >= 4, "씬 배선: 스캔된 씬 %d개 (0건이면 침묵 통과)" % scenes.size())
	var bad := ""
	var checked := 0
	var arrow_fields := 0
	for path: String in scenes:
		var ps := load(path) as PackedScene
		if ps == null:
			bad += "%s(로드 실패) " % path.get_file()
			continue
		var st := ps.get_state()
		var known: Dictionary = {}
		for i: int in range(st.get_node_count()):
			known[str(st.get_node_path(i))] = true
		for i: int in range(st.get_node_count()):
			var here := str(st.get_node_path(i))
			var has_peer_sync := false
			var is_arrow_field := false
			for j: int in range(st.get_node_property_count(i)):
				var pn := st.get_node_property_name(i, j)
				var pv: Variant = st.get_node_property_value(i, j)
				if pn == "script" and pv is Script \
						and (pv as Script).resource_path == "res://src/stage/arrow_field.gd":
					is_arrow_field = true
				if not pn.ends_with("_path") or not (pv is NodePath):
					continue
				if pn == "peer_sync_path":
					has_peer_sync = true
				checked += 1
				var rel := str(pv as NodePath)
				if rel.is_empty():
					bad += "%s:%s.%s(빈 값) " % [path.get_file(), here, pn]
				elif not known.has(_resolve_node_path(here, rel)):
					bad += "%s:%s.%s→%s(대상 없음) " % [path.get_file(), here, pn, rel]
			if is_arrow_field:
				arrow_fields += 1
				# 🔴 **프로퍼티가 아예 없는 경우**도 잡아야 한다 — 미설정 export는 SceneState에 안 나타나므로
				#   위 루프가 그냥 건너뛴다(= 배선을 지우면 검사가 조용히 통과한다).
				if not has_peer_sync:
					bad += "%s:%s(peer_sync_path 미배선) " % [path.get_file(), here]
	_check(arrow_fields >= 4, "씬 배선: ArrowField를 문 씬 %d개 (전투/모닥불 4개 이상)" % arrow_fields)
	_check(checked >= 8, "씬 배선: 검사한 *_path 배선 %d개" % checked)
	_check(bad.is_empty(), "★씬 배선 전수: 모든 *_path가 같은 씬의 실제 노드를 가리킨다 (위반: %s)"
		% ("없음" if bad.is_empty() else bad))


# --- 마을 숲 드레싱 계약 (2026-08-01) ---
#
# 🔴 왜: 스캐터 세 노드는 `textures`가 비거나 `foliage_scene`이 안 물리면 `_ready`가 **early return**한다
#   — 장식이 0개인데 **에러도 경고도 없다.** 위 ⑴~⑶ 검사는 스캐터 *로직*을 스테이지 에셋으로 보지,
#   마을 씬이 그 노드를 실제로 물었는지는 아무도 안 본다. 아트를 갈아엎을 때 정확히 이 줄이 빠진다.
# 🔴 그리고 **제외 영역**: 기능 3곳 + 스폰이 exclude 안에 없으면 상호작용 영역(60×60)에 덤불이 돋아
#   "그림 위에 섰는데 F가 안 뜬다"가 된다. 좌표는 **씬에서 읽는다** — 여기 숫자를 적으면 기능을 옮겼을 때
#   테스트만 초록인 채 갈라진다(rules 「미러를 만들지 마라」).
const VILLAGE := "res://src/village/village.tscn"


func _check_village_dressing() -> void:
	var ps := load(VILLAGE) as PackedScene
	if ps == null:
		_check(false, "마을: 씬 로드 실패")
		return
	var st := ps.get_state()
	var props: Dictionary = {}     # 노드명 -> {프로퍼티: 값}
	var spots: Array[Vector2] = []  # 기능 3곳 + 스폰 (씬에서 읽는다 — 미러 금지)
	for i: int in range(st.get_node_count()):
		var name := str(st.get_node_name(i))
		var d: Dictionary = {}
		for j: int in range(st.get_node_property_count(i)):
			d[st.get_node_property_name(i, j)] = st.get_node_property_value(i, j)
		props[name] = d
		if name in ["CraftStation", "TrainStation", "Gate"] and d.has("position"):
			spots.append(d["position"] as Vector2)
		elif name == "PeerSync" and d.has("spawn_base"):
			spots.append(d["spawn_base"] as Vector2)

	for n: String in ["GroundDetail", "TreeRing", "Bushes"]:
		var d: Dictionary = props.get(n, {})
		if d.is_empty():
			_check(false, "마을: %s 노드가 없다" % n)
			continue
		var texs: Variant = d.get("textures", [])
		var n_tex := (texs as Array).size() if texs is Array else 0
		# 🔴 비면 `_ready`가 조용히 return — 장식 0개인데 에러 없음
		_check(n_tex > 0, "마을 %s: textures가 비어있지 않다 (%d장)" % [n, n_tex])
		_check(int(d.get("count", 0)) > 0, "마을 %s: count > 0 (%d)" % [n, int(d.get("count", 0))])
		if n != "GroundDetail":
			_check(d.get("foliage_scene", null) != null, "마을 %s: foliage_scene이 물렸다" % n)

	_check(spots.size() == 4, "마을: 기능 3곳+스폰 좌표를 씬에서 읽었다 (%d/4)" % spots.size())
	var ex: Variant = (props.get("Bushes", {}) as Dictionary).get("exclude", [])
	var rects: Array = ex if ex is Array else []
	var uncovered := ""
	for p: Vector2 in spots:
		var covered := false
		for r: Variant in rects:
			if (r as Rect2).has_point(p):
				covered = true
				break
		if not covered:
			uncovered += "%s " % p
	_check(uncovered.is_empty(),
		"★마을: 덤불 제외 영역이 기능 3곳+스폰을 전부 덮는다 (안 덮임: %s)"
		% ("없음" if uncovered.is_empty() else uncovered))


func _collect_scenes(dir: String, out: Array[String]) -> void:
	for f: String in DirAccess.get_files_at(dir):
		var base := f.trim_suffix(".remap")
		if base.get_extension() == "tscn":
			out.append("%s/%s" % [dir, base])
	for d: String in DirAccess.get_directories_at(dir):
		_collect_scenes("%s/%s" % [dir, d], out)


# SceneState 표기(루트 = ".", 자식 = "./A/B") 기준으로 상대 NodePath를 절대화한다.
# 못 풀면 "" — 호출부가 "대상 없음"으로 처리한다(절대 경로 `/root/…`도 여기서 걸린다).
func _resolve_node_path(base: String, rel: String) -> String:
	if rel.begins_with("/"):
		return ""  # 씬 밖 절대 경로 = 배선 계약 위반(복제한 씬에서 그대로 깨진다)
	# ⚠ 상대 NodePath는 **그 노드 자신** 기준이다 — 여기서 미리 자기 이름을 떼면 안 된다("../X"의 ".."이
	#   그 일을 한다). 처음에 떼도록 짰다가 이 테스트 자신에게 걸렸다(전 씬이 "대상 없음"으로 빨개졌다).
	var parts: Array[String] = []
	for seg: String in base.split("/", false):
		if seg != ".":
			parts.append(seg)
	for seg: String in rel.split("/", false):
		if seg == "..":
			if parts.is_empty():
				return ""  # 씬 루트 위로 나감
			parts.remove_at(parts.size() - 1)
		elif seg != ".":
			parts.append(seg)
	return "." if parts.is_empty() else "./" + "/".join(parts)
