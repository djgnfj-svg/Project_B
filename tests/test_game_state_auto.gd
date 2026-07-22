extends SceneTree
# GameState 리졸버 단위 테스트 — 직업 + 챕터. data/ 스캔 allowlist + 모르는 id 폴백 (신뢰 경계).
# 네트워크로 받은 직업/챕터 id·스테이지 인덱스가 전부 이 리졸버를 지나므로, 여기가 뚫리면
# load 경로 조작·범위 밖 인덱싱이 된다. 챕터 진행 좌표·HP 이월 헬퍼도 여기서 검증.
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

	# --- 챕터 리졸버 (G_SCENE c/i 신뢰 경계) ---
	_check("챕터 스캔에 chapter1 포함", "chapter1" in gs.chapter_ids())
	var ch1: ChapterDef = gs.chapter_def("chapter1")
	_check("챕터1 칸 수 = 4 (전투3+보스 직전 모닥불1)", ch1.stage_count() == 4)
	_check("모르는 챕터 → 기본 챕터 폴백", gs.chapter_def("chapter99").display_name == ch1.display_name)
	_check("챕터 경로 조작 → 기본 챕터 폴백",
		gs.chapter_def("../../src/core/net_schema").display_name == ch1.display_name)
	_check("무효 인덱스(-1) 거부", not gs.is_valid_stage("chapter1", -1))
	_check("무효 인덱스(범위 밖) 거부", not gs.is_valid_stage("chapter1", ch1.stage_count()))
	_check("모르는 챕터 좌표 거부", not gs.is_valid_stage("bogus", 0))
	_check("정상 좌표 허용", gs.is_valid_stage("chapter1", 0))

	# --- 칸 성격 판별 (모닥불 관례) + HUD 순번 ---
	_check("0번 칸 = 전투", not ch1.is_rest(0))
	_check("2번 칸 = 모닥불 (보스 직전)", ch1.is_rest(2))
	_check("전투 스테이지 총수 = 3", ch1.combat_total() == 3)
	_check("1번 칸 = 2번째 전투", ch1.combat_ordinal(1) == 2)
	_check("마지막 칸 = 3번째 전투(보스)", ch1.combat_ordinal(3) == 3)

	# --- 진행 좌표·토큰·이월 HP ---
	gs.begin_stage("chapter1", 1)
	_check("진행 중 in_chapter", gs.in_chapter())
	_check("씬 토큰 = 칸 좌표", gs.stage_token() == "stage:chapter1:1")
	_check("1번 칸은 마지막 아님", not gs.is_last_stage())
	_check("씬 경로 = stage_2", gs.stage_scene_path().get_file() == "stage_2.tscn")
	_check("진행 표기 = 스테이지 2/3", gs.progress_label().ends_with("스테이지 2/3"))
	gs.begin_stage("chapter1", 3)
	_check("마지막 칸 판별", gs.is_last_stage())
	gs.begin_stage("chapter1", 2)
	_check("모닥불 진행 표기", gs.progress_label().ends_with("모닥불"))
	_check("이월 기록 없음 = -1", gs.carried_hp(7) == -1)
	gs.record_party_hp(7, 12)
	_check("이월 기록 조회", gs.carried_hp(7) == 12)
	gs.leave_chapter()
	_check("챕터 이탈 시 좌표 리셋", not gs.in_chapter())
	_check("챕터 이탈 시 이월 HP 리셋", gs.carried_hp(7) == -1)
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
