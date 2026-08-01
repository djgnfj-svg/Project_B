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


func _run() -> void:
	await process_frame
	print("== 씬 전환(유령 노드) ==")
	await _engine_premise()
	await _swap_contract()
	_source_tripwires()
	if _fail == 0:
		print("TEST_OK scene_swap")
	else:
		print("TEST_FAILED scene_swap (%d)" % _fail)
	quit(1 if _fail > 0 else 0)
