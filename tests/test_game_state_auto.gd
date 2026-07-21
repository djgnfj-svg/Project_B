extends SceneTree
# GameState 직업 리졸버 단위 테스트 — data/jobs 스캔 allowlist + 모르는 id 폴백 (신뢰 경계).
# 네트워크로 받은 직업 id가 전부 이 리졸버를 지나므로, 여기가 뚫리면 load 경로 조작이 된다.
# -s 실행에선 오토로드가 없다 — 스크립트를 직접 인스턴스한다 (projectb-rules §5).
# 성공/실패 모두 한 줄씩 찍는다 — 침묵 통과 방지 (projectb-verify §3).

const GameStateScript := preload("res://src/core/game_state.gd")

var _fails := 0


func _initialize() -> void:
	var gs := GameStateScript.new() as Node
	_check("스캔에 warrior 포함", "warrior" in gs.job_ids())
	_check("스캔에 archer 포함", "archer" in gs.job_ids())
	_check("스캔에 mage 포함", "mage" in gs.job_ids())
	_check("정상 id 리졸브", gs.job_def("mage").id == "mage")
	_check("정상 id의 sprite 연결", gs.job_def("warrior").sprite != null)
	_check("모르는 id → 기본 직업 폴백", gs.job_def("paladin").id == "warrior")
	_check("경로 조작 시도 → 기본 직업 폴백", gs.job_def("../../src/core/net_schema").id == "warrior")
	_check("빈 id → 기본 직업 폴백", gs.job_def("").id == "warrior")
	gs.free()
	if _fails == 0:
		print("TEST_OK game_state")
		quit(0)
	else:
		printerr("TEST_FAIL game_state — %d건 실패" % _fails)
		quit(1)


func _check(what: String, ok: bool) -> void:
	if ok:
		print("  ok: %s" % what)
	else:
		_fails += 1
		printerr("  FAIL: %s" % what)
