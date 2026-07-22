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
