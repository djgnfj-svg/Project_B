extends SceneTree
# SaveManager 커밋/롤백 단위 테스트 — 전멸 저장 롤백의 핵심 계약 (GDD §11).
# 계약: 스테이지 클리어=commit(디스크 영속) · 전멸=reload(마지막 저장분 롤백 → 클리어분만 생존,
#   전멸 스테이지에서 주운 것은 소실). 커밋/롤백 로직(디스크 라운드트립 + clear→load)을 검증한다.
#   (실제 시그널 배선 stage_cleared→commit·stage_wiped→reload는 SaveManager._ready 2줄로 자명 —
#    -s는 오토로드/트리가 없어 시그널 대신 commit()/reload()를 직접 호출한다, rules §5.)
# ⚠ 노드를 트리에 add하지 않는다 — -s에선 트리 안 노드의 /root 절대경로 조회가 실패한다.
#   GameState는 game_state_override로 주입, EventBus 조회는 _bus()·reload의 is_inside_tree 가드가 null 반환(트리 밖).
# ⚠ save_path를 임시 경로로 격리 — 실제 user://save.json을 절대 안 건드린다 (projectb-verify §1).
# 성공/실패 모두 한 줄씩 찍는다 — 침묵 통과 방지 (projectb-verify §3).

const GameStateScript := preload("res://src/core/game_state.gd")
const SaveManagerScript := preload("res://src/core/save_manager.gd")

const TEST_SAVE_PATH := "user://test_save_manager.json"

var _fails := 0


func _initialize() -> void:
	_purge()  # 이전 실행 잔여 격리 파일 정리 (깨끗한 시작)

	var gs := GameStateScript.new() as Node  # 트리 밖 — /root 조회 회피 (rules §5)
	var sm := SaveManagerScript.new() as Node
	sm.save_path = TEST_SAVE_PATH
	sm.game_state_override = gs

	# --- 클리어분 적립 후 커밋 (스테이지 클리어 시점) ---
	gs.add_gold(100)
	gs.add_material("goblin_hide", 3)
	sm.commit()  # 디스크 기록 (stage_cleared→commit 경로가 실전에서 부르는 것)
	_check("커밋 후 저장 파일 존재", FileAccess.file_exists(TEST_SAVE_PATH))

	# --- 전멸 스테이지에서 더 주움 (아직 미커밋) ---
	gs.add_gold(50)                    # 클리어분 100 + 전멸분 50 = 150 (인메모리)
	gs.add_material("goblin_hide", 5)  # 3 + 5 = 8 (인메모리)
	gs.add_material("brute_core", 1)   # 전멸 스테이지에서 새로 주운 핵심재료
	_check("전멸 전 인메모리 골드 = 150", gs.gold == 150)
	_check("전멸 전 인메모리 재료 = 8", gs.material_count("goblin_hide") == 8)

	# --- 전멸 → 롤백 (stage_wiped→reload 경로) ---
	sm.reload()
	_check("전멸 롤백: 골드 = 클리어분 100 (전멸분 50 소실)", gs.gold == 100)
	_check("전멸 롤백: 재료 = 클리어분 3 (전멸분 5 소실)", gs.material_count("goblin_hide") == 3)
	_check("전멸 롤백: 전멸분 핵심재료 소실", gs.material_count("brute_core") == 0)

	# --- 도면도 커밋분만 생존 (핵심 게이트 재료·도면 롤백 정합) ---
	gs.unlock_blueprint("iron_greatsword")  # 커밋 전 상태에 없던 도면
	sm.commit()                             # 이제 도면 포함해 커밋
	gs.add_material("sharp_fang", 2)        # 커밋 후 주운 것
	sm.reload()
	_check("전멸 롤백: 커밋된 도면은 생존", gs.has_blueprint("iron_greatsword"))
	_check("전멸 롤백: 커밋 후 주운 재료 소실", gs.material_count("sharp_fang") == 0)

	# --- EXP·직업 레벨도 재료와 **같은 롤백 규칙** (성장축 GDD v1.8 §6) ---
	# 성장 자원마다 롤백 규칙이 다르면 플레이어가 "내가 무엇을 잃었는지"를 읽을 수 없다.
	# 이 계약은 SaveManager 코드 0줄로 성립한다(to/from_save_dict에 필드로 실리기 때문) — 그래서
	# 저장 필드가 빠지면 여기서만 드러난다.
	gs.grant_starting_sub_job(gs.job_def("warrior"))
	gs.add_exp(60)                       # 클리어분 EXP (curve [0,25,60,…] → 2레벨)
	_check("클리어 전 EXP 적립 = 60", int(gs.sub_job_exp.get("warrior_swordsman", -1)) == 60)
	_check("클리어 전 레벨 = 2", gs.sub_job_level("warrior_swordsman") == 2)
	sm.commit()                          # 스테이지 클리어 = 커밋
	gs.add_exp(45)                       # 전멸 스테이지에서 더 벌어 3레벨(105)까지 감
	_check("전멸 전 인메모리 EXP = 105", int(gs.sub_job_exp.get("warrior_swordsman", -1)) == 105)
	_check("전멸 전 레벨 = 3", gs.sub_job_level("warrior_swordsman") == 3)
	_check("전멸 전 해금 발생(3레벨)", gs.has_sub_job("warrior_berserker"))
	sm.reload()                          # 전멸 = 마지막 커밋으로 롤백
	_check("전멸 롤백: EXP = 클리어분 60 (전멸분 45 소실)", int(gs.sub_job_exp.get("warrior_swordsman", -1)) == 60)
	_check("전멸 롤백: 레벨도 클리어분(2)으로 되돌아감", gs.sub_job_level("warrior_swordsman") == 2)
	_check("전멸 롤백: 전멸 스테이지에서 딴 해금도 소실", not gs.has_sub_job("warrior_berserker"))
	_check("전멸 롤백: 메인 하위 직업은 커밋분 그대로", gs.main_sub_job_id == "warrior_swordsman")

	# 🔴 SAVE_VERSION 트립와이어 — 올리면 여기가 빨개지고 이유를 읽게 된다.
	# save_manager.gd가 버전을 **정확일치**로 검사하므로, 버전을 올리면 이미 배포된
	# game.jachana.com 플레이어들의 세이브가 조건에서 탈락해 조용히 전부 무시된다.
	# 성장축 같은 필드 추가는 버전을 올리지 않고 "키 없음 = 기본값" 폴백으로 처리한다(GDD §6).
	_check("SAVE_VERSION == 1 고정 (올리면 배포본 세이브가 조용히 전멸 — GDD §6·rules §5)",
		int(SaveManagerScript.SAVE_VERSION) == 1)

	# 🔴 **오토로드 순서 트립와이어** (조립 축 v2.0, 리뷰 M6) — 공유 하위 직업 해금은 GameState가
	# `stage_cleared`에 물려 있고, SaveManager도 같은 시그널에 `commit`을 문다. Godot은 **연결 순서**대로
	# 호출하고 그 순서는 곧 오토로드 등록 순서다 → GameState가 SaveManager보다 **앞**에 있어야
	# 해금이 그 판 저장에 포함된다. 뒤집히면 에러 없이 "보스를 깼는데 다음 판에 곡예사가 없다"가 된다.
	var proj := FileAccess.get_file_as_string("res://project.godot")
	var i_gs := proj.find("GameState=")
	var i_sm := proj.find("SaveManager=")
	_check("오토로드 순서: GameState가 SaveManager보다 앞 (해금이 그 판 commit에 포함되는 전제)",
		i_gs >= 0 and i_sm >= 0 and i_gs < i_sm)

	# 공유 하위 직업 해금이 저장을 타고 살아남나 — 위 순서 가정의 결과물 검증(보스 클리어 시나리오).
	gs.unlock_shared_sub_jobs()
	_check("보스 클리어: 공유 하위 직업 해금(곡예사)", gs.has_sub_job("shared_acrobat"))
	sm.commit()
	gs.sub_job_exp.erase("shared_acrobat")  # 메모리만 날려 로드 경로를 강제
	sm.reload()
	_check("공유 해금이 저장 라운드트립을 통과한다", gs.has_sub_job("shared_acrobat"))

	sm.free()
	gs.free()

	# --- 첫 판 전멸 (저장 파일 없음) → 빈 인벤 (크래시 없이) ---
	_purge()
	var gs2 := GameStateScript.new() as Node
	var sm2 := SaveManagerScript.new() as Node
	sm2.save_path = TEST_SAVE_PATH
	sm2.game_state_override = gs2
	gs2.add_gold(77)  # 커밋 없이 주운 것
	sm2.reload()      # 첫 판 전멸 — 저장 파일 없음
	_check("첫 판 전멸: 저장 없어 빈 인벤으로 롤백", gs2.gold == 0)
	sm2.free()
	gs2.free()

	_purge()  # 격리 파일 정리

	if _fails == 0:
		print("TEST_OK save_manager")
		quit(0)
	else:
		printerr("TEST_FAIL save_manager — %d건 실패" % _fails)
		quit(1)


func _purge() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _check(what: String, ok: bool) -> void:
	if ok:
		print("  ok: %s" % what)
	else:
		_fails += 1
		printerr("  FAIL: %s" % what)
