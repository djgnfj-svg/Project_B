extends SceneTree
# 씬 전환 — 「새 씬의 `_ready` 일회 스캔이 이전 씬 노드를 잡지 않는가」.
#
# 왜 테스트가 있나 (2026-08-01 실기 신고 "잡몹 스테이지2 갈 때 멈춘다"의 원인):
#   `main._swap`이 `queue_free()`(실행은 **프레임 끝**) 뒤 곧바로 `add_child(next)`를 하는데,
#   `add_child`는 새 씬의 `_ready`를 **그 자리에서 동기 실행**한다. 그 순간 이전 씬 노드가 아직
#   그룹에 살아 있어, `_ready`에서 그룹을 **일회 스캔**하는 컴포넌트(combat_authority·mob_sync)가
#   유령을 딕셔너리에 **영구히** 박았다. 다음 프레임에 그것이 해제되면 소비부의
#   `entry["health"] as HealthComponent`가 **캐스트 단계에서** 터진다:
#       SCRIPT ERROR: Trying to cast a freed object.
#   → 그 함수가 통째로 중단된다. 실제 피해 둘 다 **에러가 화면에 안 드러났다**:
#     ⑴ `_check_clear`가 첫 반복에서 죽어 **스테이지2가 영영 클리어되지 않았다**
#        (Dictionary는 삽입 순서라 유령이 늘 첫 항목 = 100% 재현).
#     ⑵ `mob_sync._physics_process`도 같은 자리에서 죽어 `G_MOB_POS`가 한 통도 안 나가
#        **게스트 화면의 잔몹이 얼어붙었다**(초당 60회).
#   ⚠ `x == null` 가드로는 못 막는다 — **캐스트가 먼저 터진다.** 그게 이 결함이 오래(2026-07-22 이후)
#     살아남은 이유다: 두 소비부 모두 null 가드를 갖고 있었고 그래서 "방어됐다"로 읽혔다.
#
# ⚠ 이 파일은 **오토로드를 안 쓴다** — 그래서 `-s`로 돈다(rules §5 전역 식별자 함정).
#   `main.gd`·`combat_authority.gd`·`mob_sync.gd`는 씬 글루라 preload할 수 없으므로, 행동 계약은
#   **같은 관용구를 순수 노드로 재현**해 겨누고 실제 호출부는 **소스 트립와이어**로 잠근다.
#   🔴 의도적으로 freed 캐스트를 일으키지 않는다 — 그건 스위트를 SCRIPT ERROR로 빨갛게 만든다.

const GROUP := "swaptest_mob"

var _fail := 0


func _init() -> void:
	_run()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s" % label)


# `_ready`에서 그룹을 일회 스캔하는 컴포넌트 — combat_authority._ready / mob_sync._ready 재현.
class Scanner extends Node:
	var scan_all: Array[String] = []      # 필터 없는 스캔(옛 코드)
	var scan_filtered: Array[String] = []  # 자기 씬 하위만(처방)

	func _ready() -> void:
		var scene_root := get_parent()
		for n: Node in get_tree().get_nodes_in_group("swaptest_mob"):
			scan_all.append(n.name)
			if scene_root != null and scene_root.is_ancestor_of(n):
				scan_filtered.append(n.name)


func _make_stage(mob_name: String) -> Node:
	var stage := Node.new()
	var mob := Node2D.new()
	mob.name = mob_name
	stage.add_child(mob)
	mob.add_to_group(GROUP)
	stage.add_child(Scanner.new())   # 스테이지 루트의 자식 = 실제 배선과 같다
	return stage


func _scanner_of(stage: Node) -> Scanner:
	for c: Node in stage.get_children():
		var s := c as Scanner
		if s != null:
			return s
	return null


# --- ⑴ 엔진 전제: queue_free 만으로는 그룹에 남고, remove_child 는 즉시 빠진다 ---
# 이 두 성질이 처방의 근거 전체다. Godot이 바뀌어 전제가 깨지면 여기서 먼저 알아야 한다.
func _engine_premise() -> void:
	var host := Node.new()
	root.add_child(host)
	var a := Node2D.new()
	host.add_child(a)
	a.add_to_group(GROUP)
	await process_frame
	_check(get_nodes_in_group(GROUP).size() == 1, "전제: 살아 있는 노드는 그룹에 잡힌다")

	a.queue_free()
	_check(get_nodes_in_group(GROUP).size() == 1,
		"전제: queue_free 직후에도 그룹에 남는다(프레임 끝에야 해제) — 유령의 출처")

	var b := Node2D.new()
	host.add_child(b)
	b.add_to_group(GROUP)
	host.remove_child(b)
	_check(get_nodes_in_group(GROUP).size() == 1,
		"전제: remove_child 는 그룹 조회에서 **즉시** 빠진다 — 처방의 근거")
	b.queue_free()
	await process_frame
	host.queue_free()
	await process_frame


# --- ⑵ 행동 계약: main._swap 관용구를 그대로 재현 ---
func _swap_contract() -> void:
	# 현행(옛) 방식 — queue_free 만. 새 씬의 스캔이 유령을 본다.
	var old1 := _make_stage("ghost_mob")
	root.add_child(old1)
	await process_frame
	old1.queue_free()
	var new1 := _make_stage("live_mob")
	root.add_child(new1)          # 여기서 new1 의 Scanner._ready 가 동기 실행된다
	var s1 := _scanner_of(new1)
	_check(s1 != null and s1.scan_all.has("ghost_mob"),
		"재현: queue_free 만이면 새 씬의 _ready 스캔이 **이전 씬 노드까지** 잡는다")
	# 🔴 같은 프레임·같은 스캔인데 필터가 있으면 유령이 안 들어온다 = 입구 방어의 검출력
	_check(s1 != null and not s1.scan_filtered.has("ghost_mob") and s1.scan_filtered.has("live_mob"),
		"입구 방어: is_ancestor_of 필터가 유령만 걸러내고 자기 씬 적은 남긴다")
	new1.queue_free()
	await process_frame

	# 처방 방식 — remove_child 를 먼저. 필터가 없어도 스캔이 깨끗하다.
	var old2 := _make_stage("ghost_mob2")
	root.add_child(old2)
	await process_frame
	root.remove_child(old2)
	old2.queue_free()
	var new2 := _make_stage("live_mob2")
	root.add_child(new2)
	var s2 := _scanner_of(new2)
	_check(s2 != null and not s2.scan_all.has("ghost_mob2"),
		"처방: remove_child 를 먼저 하면 새 씬의 스캔에 유령이 아예 안 들어온다")
	new2.queue_free()
	await process_frame


# --- ⑶ 소스 트립와이어 — 실제 호출부(씬 글루라 preload 불가)를 잠근다 ---
func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _source_tripwires() -> void:
	var main_src := _src("res://src/main/main.gd")
	var rm := main_src.find("remove_child(_current)")
	var qf := main_src.find("_current.queue_free()")
	# 🔴 순서가 계약이다 — queue_free 뒤에 remove_child 를 두면 이미 늦다(그 프레임 스캔이 유령을 본다).
	_check(rm >= 0 and qf >= 0 and rm < qf,
		"main._swap: remove_child(_current) 가 queue_free() **앞에** 있다")

	# 두 일회 스캔은 자기 씬 하위만 받아야 한다. 근본 처방이 되돌려져도 이쪽이 남는다(2층 방어).
	for path: String in ["res://src/stage/combat_authority.gd", "res://src/stage/mob_sync.gd"]:
		var src := _src(path)
		var scan := src.find("get_nodes_in_group(")
		_check(scan >= 0 and src.find("is_ancestor_of") >= 0,
			"%s: _ready 그룹 스캔에 is_ancestor_of 필터가 있다" % path.get_file())
		# 🔴 기준은 `owner`여야 한다 — `get_parent()`만 쓰면 컴포넌트를 한 겹 감싸는 순간
		#   자기 씬 적이 **하나도** 안 통과한다(조용한 전면 무등록).
		_check(src.find("owner if owner != null else get_parent()") >= 0,
			"%s: 씬 기준이 owner다(get_parent()는 폴백)" % path.get_file())

	# 🔴 G_MOB_POS 순서 가드 (2026-08-02) — 씬 글루라 preload가 안 돼 소스 문자열로 겨눈다.
	#   이 셋 중 하나만 지워도 증상이 **"적 HP만 안 깎인다"** 라서 §3 「각 축 지연 보상」 결함과
	#   구분되지 않는다(서로를 가린다). 그래서 세 조각을 각각 단정한다.
	var ms := _src("res://src/stage/mob_sync.gd")
	_check(ms.find("\"n\": _mpos_seq") >= 0,
		"mob_sync: G_MOB_POS 배치에 시퀀스 n을 싣는다 (없으면 수신 가드가 항등 폴백으로 무력화)")
	_check(ms.find("is_pos_seq_fresh") >= 0,
		"mob_sync: 수신부가 CombatMath.is_pos_seq_fresh로 순서를 본다 (사본 금지 — G_POS와 공유)")
	# 🔴 에폭 리셋이 짝이다 — 이것만 빠지면 순서 가드가 오히려 피해를 **키운다**(netreview I-1:
	#   직전 씬의 큰 번호가 새 씬 `_last`에 박혀 이후 전량 폐기 = 수백 초 정지).
	# ⚠ `find("EPOCH_GAP")`으로는 부족하다 — 상수 선언만 남기고 **사용처를 지우는** 뮤테이션이
	#   그대로 통과한다(실측). 리셋이 실제로 일어나는 표현식을 겨눈다.
	_check(ms.find("_last_mpos_seq - EPOCH_GAP") >= 0 and ms.find("_last_mpos_seq = 0") >= 0,
		"mob_sync: 씬 에폭 리셋이 동작한다 — 순서 가드 단독은 씬 전환에서 오히려 더 나쁘다(netreview I-1)")

	# 🔴 마무리 타 사거리(v2.3)의 **표시 배선** — `combat_math` 전수 트립와이어가 원리적으로 못 닿는
	#   자리다(`player.gd`는 씬 글루라 `-s` preload 불가). 이 한 줄이 사라지면 판정만 늘고 궤적은
	#   그대로여서 **「안 보이는데 맞는다」**(§3 금지 방향)가 되는데, 대검 여유가 +2px뿐이라
	#   42 → 63에서 **−19px**가 즉시 생긴다. 전수 쪽 ⑻ⓓ는 `CombatMath` 함수만 보므로 여기가 짝이다.
	var pl := _src("res://src/player/player.gd")
	_check(pl.find("combo_finish_show_mult") >= 0,
		"player: 리본 배율이 마무리 사거리를 따라간다(combo_finish_show_mult) — 없으면 판정만 늘어 §3 위반")
	_check(pl.find("_weapon_override, _swing_is_finish") >= 0,
		"player: 로컬 근접 질의가 마무리 타 사거리를 쓴다(_swing_is_finish 전달)")


# --- ⑷ 노드 순서 계약 — 그룹 등록이 `.tscn`이 아니라 코드 `_ready`에서 일어난다 ---
#
# 🔴 `mob_melee.gd`·`boss.gd`·`enemy.gd`가 `_ready`에서 `add_to_group`한다(씬 파일엔 groups 선언이
#   없다). Godot의 형제 `_ready` 순서는 **트리 순서**이므로, 몹이 `CombatAuthority`/`MobSync`보다
#   씬에서 **위에** 있어야 스캔 시점에 이미 그룹에 들어 있다. 아래로 옮기면 스캔이 **빈 그룹**을 보고
#   전면 무등록이 된다 — 클리어 영영 안 됨 + `G_MOB_POS` 0통.
# ⚠ **런타임 진단(`passed < under`)은 이 경우를 못 잡는다** — `add_to_group`이 아직 안 됐으면
#   `under`도 0이라 `0 < 0`이 거짓이다. 그래서 이 단정이 유일한 방어다.
# ⚠ `.tscn`의 노드 선언 순서 = 트리 순서라 텍스트 위치 비교로 충분하다.
# 그 씬이 무는 스크립트 중 하나라도 `add_to_group("enemy"/"mob")`을 하는가.
func _scene_joins_group(scene_path: String) -> bool:
	var src := _src(scene_path)
	for line: String in src.split("\n"):
		if not line.begins_with("[ext_resource") or not line.contains(".gd"):
			continue
		var gd := _src(line.get_slice("path=\"", 1).get_slice("\"", 0))
		if gd.contains("add_to_group(\"enemy\")") or gd.contains("add_to_group(\"mob\")"):
			return true
	return false


func _node_order() -> void:
	for path: String in ["res://src/stage/stage_1.tscn", "res://src/stage/stage_2.tscn",
			"res://src/stage/stage_boss.tscn", "res://src/stage/stage_test.tscn"]:
		var src := _src(path)
		if src.is_empty():
			_check(false, "%s: 읽을 수 없다" % path.get_file())
			continue
		# 🔴 배우 씬 목록을 **하드코딩하지 않는다** — `.tscn`이 참조하는 PackedScene을 열어
		#   그 안의 스크립트가 실제로 `add_to_group("enemy"/"mob")`을 하는지 본다. 새 적 씬
		#   (training_dummy 같은 것)이 늘어도 이 단정이 자동으로 따라온다.
		var actor_ids: Array[String] = []
		for line: String in src.split("\n"):
			if not line.begins_with("[ext_resource") or not line.contains(".tscn"):
				continue
			var sub := line.get_slice("path=\"", 1).get_slice("\"", 0)
			if sub.is_empty() or not _scene_joins_group(sub):
				continue
			actor_ids.append(line.get_slice("id=\"", 1).get_slice("\"", 0))
		var first_actor := -1
		var first_comp := -1
		var pos := 0
		for line: String in src.split("\n"):
			if line.begins_with("[node "):
				for aid: String in actor_ids:
					if line.contains("instance=ExtResource(\"%s\")" % aid) and first_actor < 0:
						first_actor = pos
			elif line.begins_with("script = ExtResource(") and first_comp < 0:
				# 직전 노드가 CombatAuthority/MobSync인지는 스크립트 경로로 판별한다
				var sid := line.get_slice("(\"", 1).get_slice("\"", 0)
				for l2: String in src.split("\n"):
					if l2.begins_with("[ext_resource") and l2.contains("id=\"%s\"" % sid) \
							and (l2.contains("combat_authority.gd") or l2.contains("mob_sync.gd")):
						first_comp = pos
						break
			pos += 1
		_check(first_actor >= 0 and first_comp >= 0 and first_actor < first_comp,
			"%s: 몹/보스가 CombatAuthority·MobSync보다 **위**에 있다 (배우 %d행 < 컴포넌트 %d행)"
				% [path.get_file(), first_actor, first_comp])


func _run() -> void:
	await process_frame
	print("== 씬 전환(유령 노드) ==")
	await _engine_premise()
	await _swap_contract()
	_source_tripwires()
	_node_order()
	if _fail == 0:
		print("TEST_OK scene_swap")
	else:
		print("TEST_FAILED scene_swap (%d)" % _fail)
	quit(1 if _fail > 0 else 0)
