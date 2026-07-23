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

	# --- 인벤/제작/강화/저장 (드랍·제작 신뢰 경계) ---
	_check("재료 스캔에 goblin_hide", "goblin_hide" in gs.material_ids())
	_check("장비 스캔에 iron_greatsword", "iron_greatsword" in gs.equipment_ids())
	_check("레시피 스캔에 leather_armor", "leather_armor" in gs.recipe_ids())
	# 모르는 id 폐기 — 조작 드랍/세이브 방어 (신뢰 경계)
	gs.add_material("bogus_mat", 5)
	_check("모르는 재료 id 폐기", gs.material_count("bogus_mat") == 0)
	gs.add_material("goblin_hide", 5)
	_check("정상 재료 추가", gs.material_count("goblin_hide") == 5)
	gs.unlock_blueprint("bogus_recipe")
	_check("모르는 도면 id 폐기", not gs.has_blueprint("bogus_recipe"))
	_check("leather_armor 기본 언락(튜토 제작템)", gs.has_blueprint("leather_armor"))
	_check("iron_greatsword 도면 없음", not gs.has_blueprint("iron_greatsword"))
	# 제작 — 골드+재료 소비 → 보유 + 빈 슬롯 자동 장착
	gs.add_gold(50)
	_check("제작 가능(재료·골드 충족)", gs.can_craft("leather_armor"))
	_check("도면 없는 레시피 제작 불가", not gs.can_craft("iron_greatsword"))
	_check("제작 성공", gs.craft("leather_armor"))
	_check("제작 후 장비 보유(lv0)", gs.equip_level("leather_armor") == 0)
	_check("제작 시 재료 차감(5-3)", gs.material_count("goblin_hide") == 2)
	_check("빈 방어구 슬롯 자동 장착", gs.equipped_id(1) == "leather_armor")
	# 강화 — 골드 소비 → 레벨 +1
	gs.add_gold(100)
	_check("강화 가능", gs.can_upgrade("leather_armor"))
	_check("강화 성공", gs.upgrade_equipment("leather_armor"))
	_check("강화 후 레벨 = 1", gs.equip_level("leather_armor") == 1)
	_check("착용 장비 체력이 현재 스탯에 반영", int(gs.current_stats()["hp"]) > 0)

	# --- 창고 넣기/빼기 (개인·로컬 보관함, 비네트워크) ---
	# 재료: 예치→창고 증가·가방 감소, 회수→역. 0이 된 창고 키는 삭제(표시 정돈).
	gs.deposit_material("goblin_hide", 1)
	_check("재료 예치: 가방 감소(2→1)", gs.material_count("goblin_hide") == 1)
	_check("재료 예치: 창고 증가(0→1)", gs.storage_material_count("goblin_hide") == 1)
	gs.withdraw_material("goblin_hide", 1)
	_check("재료 회수: 가방 복귀(1→2)", gs.material_count("goblin_hide") == 2)
	_check("재료 회수: 창고 0 → 키 삭제",
		gs.storage_material_count("goblin_hide") == 0 and not gs.storage_materials.has("goblin_hide"))
	# 초과 이동 clamp — 보유량 넘게 못 넣음/뺌
	gs.deposit_material("goblin_hide", 999)
	_check("초과 예치 clamp: 보유 전량만 이동",
		gs.material_count("goblin_hide") == 0 and gs.storage_material_count("goblin_hide") == 2)
	gs.withdraw_material("goblin_hide", 999)
	_check("초과 회수 clamp: 전량 복귀", gs.material_count("goblin_hide") == 2)
	# 골드 예치/회수 + 초과 clamp
	var g0: int = gs.gold
	gs.deposit_gold(30)
	_check("골드 예치: 가방 감소", gs.gold == g0 - 30 and gs.storage_gold == 30)
	gs.deposit_gold(99999)
	_check("골드 초과 예치 clamp", gs.gold == 0 and gs.storage_gold == g0)
	gs.withdraw_gold(g0)
	_check("골드 회수 복귀", gs.gold == g0 and gs.storage_gold == 0)
	# 장비 예치 → 장착 해제 + 레벨 보존, 회수 → 가방 복귀(자동장착 안 함)
	gs.deposit_equipment("leather_armor")
	_check("장비 예치: 가방에서 제거", gs.equip_level("leather_armor") == -1)
	_check("장비 예치: 창고에 레벨 보존", int(gs.storage_equipment.get("leather_armor", -1)) == 1)
	_check("장비 예치: 장착 자동 해제", gs.equipped_id(1) == "")
	# 창고 보유 장비를 add_equipment 해도 가방에 사본 안 생김 (id당 1개 불변식)
	gs.add_equipment("leather_armor")
	_check("창고 보유 장비 중복 생성 방지", gs.equip_level("leather_armor") == -1)
	gs.withdraw_equipment("leather_armor")
	_check("장비 회수: 가방 복귀(레벨 유지)", gs.equip_level("leather_armor") == 1)
	_check("장비 회수: 자동 장착 안 함(장착은 패널에서)", gs.equipped_id(1) == "")
	_check("장비 회수: 창고에서 제거", not gs.storage_equipment.has("leather_armor"))
	# 창고 저장 라운드트립 — 창고에 든 채로 to→from 복원
	gs.deposit_material("goblin_hide", 1)
	gs.deposit_gold(15)
	var ssnap: Dictionary = gs.to_save_dict()
	var gs3 := GameStateScript.new() as Node
	gs3.from_save_dict(ssnap)
	_check("창고 저장 복원: 재료", gs3.storage_material_count("goblin_hide") == 1)
	_check("창고 저장 복원: 골드", gs3.storage_gold == 15)
	gs3.free()
	# 원복 — 아래 인벤 저장 라운드트립이 창고 비고 장착된 상태를 전제
	gs.withdraw_material("goblin_hide", 1)
	gs.withdraw_gold(15)
	gs.equip("leather_armor")

	# 저장 라운드트립 — to→from 복원 (로드 시 allowlist 재검증)
	var snap: Dictionary = gs.to_save_dict()
	var gs2 := GameStateScript.new() as Node
	gs2.from_save_dict(snap)
	_check("저장 복원: 골드", gs2.gold == gs.gold)
	_check("저장 복원: 재료", gs2.material_count("goblin_hide") == 2)
	_check("저장 복원: 장비 레벨", gs2.equip_level("leather_armor") == 1)
	_check("저장 복원: 장착 슬롯", gs2.equipped_id(1) == "leather_armor")
	# 조작 세이브 방어 — 모르는 id는 로드에서 폐기
	gs2.from_save_dict({"gold": 10, "materials": {"hack_mat": 99},
		"equipment": {"hack_eq": 3}, "blueprints": ["hack_bp"], "equipped": {"0": "hack_eq", "1": ""}})
	_check("조작 세이브: 모르는 재료 폐기", gs2.material_count("hack_mat") == 0)
	_check("조작 세이브: 모르는 장비 폐기", gs2.equip_level("hack_eq") == -1)
	_check("조작 세이브: 골드는 로드", gs2.gold == 10)
	gs2.free()

	# --- 리뷰 Critical 회귀: 창고 보관 중 재제작이 equipped를 창고 아이템에 물리지 않음 ---
	# 재료·골드를 충분히 줘도 이미 보유(가방/창고)한 장비면 제작이 막혀야 한다(막힌 제작 = no-op).
	# 안 막으면 자동 장착이 창고 아이템을 물어 equip_level=-1 → 음수 레벨 스탯이 전투에 반영된다.
	gs.add_gold(100)
	gs.add_material("goblin_hide", 10)
	gs.deposit_equipment("leather_armor")  # 창고로 이동(장착 해제)
	_check("보유(창고)면 재료 충분해도 재제작 불가", not gs.can_craft("leather_armor"))
	gs.craft("leather_armor")  # 막혀서 no-op이어야 함
	_check("막힌 재제작: equipped 오염 없음(창고 아이템 안 물림)", gs.equipped_id(1) == "")
	_check("막힌 재제작: 창고분 그대로", int(gs.storage_equipment.get("leather_armor", -1)) == 1)

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
