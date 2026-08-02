extends SceneTree
# 보스방 진입 게이트 계약 (신설 2026-08-02 · docs/plans/active/2026-08-02-boss-gate.md).
#
# 왜 필요한가 — 아래 셋은 **전부 에러를 안 낸다**:
#   ⑴ 게이트 바위가 "boss_rock" 그룹에 들어가면 P3 돌진(`breaks_rock = false`)이 박는 순간
#      한 칸이 부서지고, 5개 중 하나가 빠지면 이웃 간격이 32 → 64px가 되어 **16px 틈**이 열린다.
#      플레이어는 빠져나가는데 보스(반경 63)는 못 따라가 싸움이 성립하지 않는다.
#   ⑵ `ttl <= 0 = 영구` 가드가 사라지면 게이트가 **한 프레임 만에 despawn**한다(0초 만료).
#      화면에는 "바위가 잠깐 떴다 사라졌다"로만 보인다.
#   ⑶ 씬의 게이트 기하가 어긋나면(손편집·생성기 미실행) 닫히는 순간 게이트 위에 선 피어가 생기거나
#      게이트가 화면 밖에서 닫힌다.
#
# ⚠ `boss_gate.gd`는 preload하지 않는다 — 씬 글루라 `-s`가 오토로드 전역 이름을 못 푼다(rules §5).
#   대신 `PackedScene.get_state()`로 **노드를 만들지 않고** 익스포트 값만 읽는다
#   (`scripts/check_boss_floor.gd`와 같은 관용구).
# ⚠ `boss_rock.gd`는 오토로드를 안 쓰므로 **실제로 인스턴스화해서** 그룹 등록을 본다 —
#   정적 함수만 부르면 "`_ready`에서 if를 지웠다"를 못 잡아 검출력이 0이 된다.

const SCENE := "res://src/stage/stage_boss.tscn"
const ROCK_SCENE := "res://src/stage/boss_rock.tscn"
const DASH_GROUP := "boss_rock"

var _fail := 0
var _checks := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s" % label)


func _init() -> void:
	_run()


# ⚠ 코루틴이다 — `root.add_child()`로는 `_ready`가 안 돌고(`-s` `_init` 시점엔 트리가 아직 안
#   돈다: 실측 `is_inside_tree() == false`), **한 프레임 흘려야** 노드가 살아난다.
func _run() -> void:
	_scene_geometry()
	await process_frame
	await _rock_contract()
	_source_defaults()
	print("검사 %d건" % _checks)
	if _fail == 0:
		print("TEST_OK boss_gate")
	else:
		print("TEST_FAIL boss_gate failures=%d" % _fail)
	quit(1 if _fail > 0 else 0)


# --- ⑴⑵ 바위 배우 계약 — 실제 인스턴스의 그룹·수명 ---
func _rock_contract() -> void:
	var ps := ResourceLoader.load(ROCK_SCENE) as PackedScene
	_check(ps != null, "%s 로드됨" % ROCK_SCENE.get_file())
	if ps == null:
		return
	var gate := ps.instantiate()
	gate.call("setup", "gate:0", Vector2.ZERO, 24.0, 0.0, null)     # ttl 0 = 영구(게이트)
	var fall := ps.instantiate()
	fall.call("setup", "boss1:rock:1", Vector2.ZERO, 24.0, 10.0, null)  # 낙석 P4 — 항등이어야 한다
	root.add_child(gate)
	root.add_child(fall)
	await process_frame

	# 🔴 게이트는 돌진 표적이 아니다(그래야 P3가 못 부순다). 낙석은 **여전히** 표적이다(항등).
	_check(not gate.is_in_group(DASH_GROUP), "★영구 바위(ttl 0)는 \"%s\" 그룹에 **없다**" % DASH_GROUP)
	_check(fall.is_in_group(DASH_GROUP), "낙석(ttl 10)은 \"%s\" 그룹에 있다 (도입 전 항등)" % DASH_GROUP)

	# 🔴 수명 — 아주 큰 delta로 `_process`를 직접 돌려 만료 분기만 겨눈다(10초를 기다리지 않는다).
	gate.call("_process", 999.0)
	fall.call("_process", 999.0)
	_check(not bool(gate.get("_gone")), "★영구 바위는 999초 뒤에도 안 사라진다")
	_check(bool(fall.get("_gone")), "낙석은 ttl 만료로 사라진다 (도입 전 항등)")

	gate.queue_free()
	fall.queue_free()


# --- ⑶ 씬에 찍힌 게이트 기하 (생성기가 소유하지만, 손편집·미실행을 여기서 잡는다) ---
#
# 🔴 **씬을 `load()` 하지 않고 텍스트로 읽는다** — `stage_boss.tscn`은 씬 글루(`stage.gd`·`boss.gd`·
#   `peer_sync.gd`…)를 물고 있고 그것들은 오토로드 전역 이름을 쓴다. `-s`에서 로드하면
#   `SCRIPT ERROR: Identifier not found` 가 **42줄** 쏟아져 스위트 판정 3조건(SCRIPT ERROR 0)이
#   무너진다. `scripts/check_boss_floor.gd`가 그 소음을 감수하는 것은 **스위트가 아니기 때문**이다
#   — 그 관용구를 여기로 베끼면 하네스가 통째로 빨개진다. 관용구는 `test_scene_swap_auto._src()`다.
func _scene_geometry() -> void:
	var f := FileAccess.open(SCENE, FileAccess.READ)
	var src := "" if f == null else f.get_as_text()
	_check(not src.is_empty(), "%s 읽힘" % SCENE.get_file())
	if src.is_empty():
		return
	var g := _node_props(src, "BossGate")
	_check(not g.is_empty(), "BossGate 노드 생존")
	if g.is_empty():
		return
	var gx := float(g.get("gate_x", "0"))
	var tx := float(g.get("trigger_x", "0"))
	var gr := float(g.get("gate_radius", "0"))
	var y0 := float(g.get("gate_y0", "0"))
	var y1 := float(g.get("gate_y1", "0"))
	var n := int(g.get("gate_count", "0"))
	# 🔴 배선도 함께 본다 — NodePath가 비면 게이트가 보스를 못 재우고 **조용히 아무 일도 안 한다**.
	#    (`test_stage_dressing_auto`의 «*_path 전수»는 이름이 `_path`로 끝나야 걸린다 = 여기도 걸린다.
	#     그래도 «비었는가»는 씬마다 확인하는 편이 싸다.)
	_check(str(g.get("boss_path", "")).contains("Boss")
			and str(g.get("coop_path", "")).contains("CoopAuthority"),
		"BossGate 배선: boss_path=%s coop_path=%s" % [g.get("boss_path", "(없음)"), g.get("coop_path", "(없음)")])
	var spawn_x := _vec2_x(str(_node_props(src, "PeerSync").get("spawn_base", "")))

	_check(n >= 2 and gr > 0.0 and y1 > y0, "게이트 기하 설정됨 (바위 %d개·반경 %.0f·y %.0f~%.0f)" % [n, gr, y0, y1])
	_check(spawn_x < gx and gx < tx, "배치 순서: 스폰 %.0f < 게이트 %.0f < 트리거 %.0f" % [spawn_x, gx, tx])

	# 🔴 트리거 여유 ≥ 외삽 상한. 호스트는 낡은 좌표(`net_anchor`)로 판정하므로 앵커가 트리거선에
	#    닿은 순간의 실제 위치는 최악 이만큼 서쪽일 수 있다 — 모자라면 **게이트 위에서 닫힌다**.
	#    ⚠ 값을 여기 복제하지 않는다(CombatMath가 정본 — 그쪽을 재유도하면 이 단정이 같이 움직인다).
	var slack := tx - (gx + gr)
	_check(slack >= CombatMath.LAG_MAX_LEAD_DIST,
		"★트리거 여유 %.0fpx ≥ LAG_MAX_LEAD_DIST %.0f" % [slack, CombatMath.LAG_MAX_LEAD_DIST])

	# 🔴 틈 없이 막는가 — 인접 두 원(중심거리 s, 반경 r)의 최소 띠 두께 2√(r² − (s/2)²) > 0.
	#    `gen_stage.py`는 «플레이어 폭 + 프레임 변위»까지 요구하지만, 여기서는 **씬에 실제로 찍힌
	#    값**만으로 성립하는 하한(겹침)을 본다 — 생성기를 안 돌린 손편집을 잡는 것이 목적이다.
	var step := (y1 - y0) / float(maxi(1, n - 1))
	_check(step < 2.0 * gr, "★게이트 간격 %.1f < 지름 %.0f (인접 바위가 겹친다 = 틈 0)" % [step, 2.0 * gr])


# `.tscn` 텍스트에서 노드 한 블록의 `key = value` 를 뽑는다(값은 문자열 그대로).
func _node_props(src: String, node_name: String) -> Dictionary:
	var out: Dictionary = {}
	var inside := false
	for line: String in src.split("\n"):
		if line.begins_with("["):
			if inside:
				break
			inside = line.begins_with("[node ") and line.contains("name=\"%s\"" % node_name)
			continue
		if not inside or not line.contains(" = "):
			continue
		out[line.get_slice(" = ", 0).strip_edges()] = line.substr(line.find(" = ") + 3).strip_edges()
	return out


# "Vector2(-256, 340)" → -256.0. 못 읽으면 0.0(그러면 배치 순서 단정이 FAIL한다 = 침묵 통과 없음).
func _vec2_x(text: String) -> float:
	if not text.begins_with("Vector2("):
		return 0.0
	return float(text.substr(8).get_slice(",", 0).strip_edges())


# --- 플래그 기본값 = 도입 전 항등 (소스 텍스트 트립와이어) ---
#
# 🔴 왜 텍스트인가: `boss.gd`·`coop_authority.gd`는 씬 글루라 `-s`가 preload를 못 한다(rules §5).
#   그런데 이 두 기본값이 뒤집히면 **BossGate가 없는 씬 전부**가 조용히 망가진다 —
#   `gate_dormant = true`면 시험장·테스트 랩의 보스가 영영 안 움직이고, `armed = false`면
#   코옵 파훼가 영영 안 나온다. 둘 다 에러가 없다.
func _source_defaults() -> void:
	for entry: Array in [
			["res://src/enemies/boss.gd", "var gate_dormant: bool = false"],
			["res://src/stage/coop_authority.gd", "var armed: bool = true"]]:
		var f := FileAccess.open(str(entry[0]), FileAccess.READ)
		var src := "" if f == null else f.get_as_text()
		_check(src.contains(str(entry[1])),
			"%s: `%s` (기본값 = 도입 전 항등)" % [str(entry[0]).get_file(), str(entry[1])])
