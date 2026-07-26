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
	_check("레시피 스캔에 iron_greatsword", "iron_greatsword" in gs.recipe_ids())
	# 무기 id가 이제 G_STATS로 네트워크를 건너온다(표시용) — equip_def allowlist 경로조작 거부 미러(job_def와 동일)
	_check("장비 경로 조작 → null", gs.equip_def("../../src/core/net_schema") == null)
	_check("모르는 장비 id → null", gs.equip_def("bogus_equip") == null)
	# 모르는 id 폐기 — 조작 드랍/세이브 방어 (신뢰 경계)
	gs.add_material("bogus_mat", 5)
	_check("모르는 재료 id 폐기", gs.material_count("bogus_mat") == 0)
	# iron_greatsword 재료 확보 (goblin 7 → 제작 5 소비 후 2 남게 = 아래 창고 테스트 전제)
	gs.add_material("goblin_hide", 7)
	gs.add_material("sharp_fang", 2)
	gs.add_material("brute_core", 1)
	_check("정상 재료 추가", gs.material_count("goblin_hide") == 7)
	gs.unlock_blueprint("bogus_recipe")
	_check("모르는 도면 id 폐기", not gs.has_blueprint("bogus_recipe"))
	_check("iron_greatsword 도면 기본 잠김", not gs.has_blueprint("iron_greatsword"))
	_check("도면 없는 레시피 제작 불가", not gs.can_craft("iron_greatsword"))
	gs.unlock_blueprint("iron_greatsword")
	_check("도면 언락", gs.has_blueprint("iron_greatsword"))
	# 제작 — 골드+재료 소비 → 보유 + 빈 무기 슬롯 자동 장착
	gs.add_gold(30)
	_check("제작 가능(재료·골드 충족)", gs.can_craft("iron_greatsword"))
	_check("제작 성공", gs.craft("iron_greatsword"))
	_check("제작 후 장비 보유(lv0)", gs.equip_level("iron_greatsword") == 0)
	_check("제작 시 재료 차감(goblin 7-5)", gs.material_count("goblin_hide") == 2)
	_check("빈 무기 슬롯 자동 장착", gs.equipped_id(0) == "iron_greatsword")
	# 강화 — 골드 소비 → 레벨 +1 (upgrade_gold_base 15)
	gs.add_gold(100)
	_check("강화 가능", gs.can_upgrade("iron_greatsword"))
	_check("강화 성공", gs.upgrade_equipment("iron_greatsword"))
	_check("강화 후 레벨 = 1", gs.equip_level("iron_greatsword") == 1)
	_check("착용 장비 공격이 현재 스탯에 반영", int(gs.current_stats()["attack"]) > 0)

	# --- 직업 귀속 (전사가 활 못 듦 — can_equip_job 단일 소스, equip·can_craft 공용) ---
	# 공유 gs 오염 방지로 별도 인스턴스. worn_bow(job_id=archer)를 보유시켜도 전사면 착용 거부.
	var gsjob := GameStateScript.new() as Node
	gsjob.selected_job_id = "warrior"
	gsjob.add_equipment("worn_bow")
	gsjob.add_equipment("worn_greatsword")
	gsjob.equip("worn_bow")
	_check("전사가 활 착용 거부(슬롯 빔)", gsjob.equipped_id(0) == "")
	_check("can_equip_job: 전사+활 = false", not gsjob.can_equip_job(gsjob.equip_def("worn_bow")))
	gsjob.equip("worn_greatsword")
	_check("전사가 대검 착용 성공", gsjob.equipped_id(0) == "worn_greatsword")
	gsjob.selected_job_id = "archer"  # 직업 바꾸면 귀속 기준도 바뀜(현재 선택 직업)
	_check("can_equip_job: 궁수+활 = true", gsjob.can_equip_job(gsjob.equip_def("worn_bow")))
	gsjob.equip("worn_bow")
	_check("궁수가 활 착용 성공", gsjob.equipped_id(0) == "worn_bow")
	_check("can_equip_job: 궁수+대검 = false", not gsjob.can_equip_job(gsjob.equip_def("worn_greatsword")))
	gsjob.free()

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
	gs.deposit_equipment("iron_greatsword")
	_check("장비 예치: 가방에서 제거", gs.equip_level("iron_greatsword") == -1)
	_check("장비 예치: 창고에 레벨 보존", int(gs.storage_equipment.get("iron_greatsword", -1)) == 1)
	_check("장비 예치: 장착 자동 해제", gs.equipped_id(0) == "")
	# 창고 보유 장비를 add_equipment 해도 가방에 사본 안 생김 (id당 1개 불변식)
	gs.add_equipment("iron_greatsword")
	_check("창고 보유 장비 중복 생성 방지", gs.equip_level("iron_greatsword") == -1)
	gs.withdraw_equipment("iron_greatsword")
	_check("장비 회수: 가방 복귀(레벨 유지)", gs.equip_level("iron_greatsword") == 1)
	_check("장비 회수: 자동 장착 안 함(장착은 패널에서)", gs.equipped_id(0) == "")
	_check("장비 회수: 창고에서 제거", not gs.storage_equipment.has("iron_greatsword"))
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
	gs.equip("iron_greatsword")

	# 저장 라운드트립 — to→from 복원 (로드 시 allowlist 재검증)
	var snap: Dictionary = gs.to_save_dict()
	var gs2 := GameStateScript.new() as Node
	gs2.from_save_dict(snap)
	_check("저장 복원: 골드", gs2.gold == gs.gold)
	_check("저장 복원: 재료", gs2.material_count("goblin_hide") == 2)
	_check("저장 복원: 장비 레벨", gs2.equip_level("iron_greatsword") == 1)
	_check("저장 복원: 장착 슬롯", gs2.equipped_id(0) == "iron_greatsword")
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
	gs.add_material("sharp_fang", 2)
	gs.add_material("brute_core", 1)
	gs.deposit_equipment("iron_greatsword")  # 창고로 이동(장착 해제)
	_check("보유(창고)면 재료 충분해도 재제작 불가", not gs.can_craft("iron_greatsword"))
	gs.craft("iron_greatsword")  # 막혀서 no-op이어야 함
	_check("막힌 재제작: equipped 오염 없음(창고 아이템 안 물림)", gs.equipped_id(0) == "")
	_check("막힌 재제작: 창고분 그대로", int(gs.storage_equipment.get("iron_greatsword", -1)) == 1)

	# --- 직업 레벨 성장축 (GDD v1.8) — 리졸버 allowlist·EXP 적립·해금·메인 전환·저장 ---
	# 공유 gs 오염 방지로 별도 인스턴스 (직업 귀속 테스트와 같은 규약).
	var gg := GameStateScript.new() as Node
	gg.selected_job_id = "warrior"
	_check("하위 직업 스캔에 warrior_swordsman", "warrior_swordsman" in gg.sub_job_ids())
	_check("하위 직업 스캔에 warrior_berserker", "warrior_berserker" in gg.sub_job_ids())
	_check("하위 직업 경로 조작 → null", gg.sub_job_def("../../src/core/net_schema") == null)
	_check("모르는 하위 직업 id → null", gg.sub_job_def("bogus_sub") == null)
	var series: Array = gg.sub_jobs_of_series("warrior")  # gg는 Node 캐스트라 반환 타입 추론 불가 — 명시
	_check("계열 목록 = order 정렬(검사 → 광전사)",
		series.size() == 2 and series[0] == "warrior_swordsman" and series[1] == "warrior_berserker")
	_check("타 계열(archer) 하위 직업 없음(미작성 = 스트레치)", gg.sub_jobs_of_series("archer").is_empty())

	# 지급 — 멱등(grant_starting_loadout 미러)
	_check("지급 전 보유 0", gg.owned_sub_jobs().is_empty())
	gg.grant_starting_sub_job(gg.job_def("warrior"))
	_check("시작 하위 직업 지급", gg.has_sub_job("warrior_swordsman"))
	_check("지급 시 메인 설정", gg.main_sub_job_id == "warrior_swordsman")
	_check("지급 직후 레벨 0", gg.sub_job_level("warrior_swordsman") == 0)
	_check("레벨 0 = 스탯 전부 0(GDD §6 base 없음)",
		is_equal_approx(float(gg.current_level_stats()["crit"]), 0.0))
	gg.add_exp(50)
	gg.grant_starting_sub_job(gg.job_def("warrior"))
	_check("재지급 멱등: 진행(EXP) 보존", int(gg.sub_job_exp.get("warrior_swordsman", -1)) == 50)

	# EXP → 레벨 → 스탯 (warrior 곡선 [0,25,60,105,160,300])
	_check("50 EXP = 1레벨", gg.sub_job_level("warrior_swordsman") == 1)
	_check("레벨 오르면 스탯도 오른다", float(gg.current_level_stats()["crit"]) > 0.0)
	_check("add_exp(0/음수)는 무시", not gg.add_exp(0) and not gg.add_exp(-5))
	var changed: bool = gg.add_exp(10)  # 60 → 2레벨
	_check("레벨 변동 시 add_exp가 true 반환(재공지 트리거)", changed)
	_check("60 EXP = 2레벨", gg.sub_job_level("warrior_swordsman") == 2)
	_check("레벨 변동 없는 적립은 false 반환(킬마다 재공지 방지)", not gg.add_exp(1))

	# 해금 — 메인이 unlocks_next_at(3레벨 = 105 EXP)에 닿으면 다음 하위 직업이 열린다
	_check("해금 전 광전사 미보유", not gg.has_sub_job("warrior_berserker"))
	gg.add_exp(44)  # 61+44 = 105 → 3레벨
	_check("105 EXP = 3레벨", gg.sub_job_level("warrior_swordsman") == 3)
	_check("3레벨 도달 → 광전사 해금", gg.has_sub_job("warrior_berserker"))
	_check("해금분은 0 EXP에서 시작(해금 이후 적립분만 — GDD §6)",
		int(gg.sub_job_exp.get("warrior_berserker", -1)) == 0)
	_check("해금 후에도 메인은 그대로", gg.main_sub_job_id == "warrior_swordsman")
	# 계열 공용 풀 — 이후 적립은 보유 전부에 동일하게 들어간다
	gg.add_exp(25)
	_check("공용 풀: 메인도 적립(105+25)", int(gg.sub_job_exp.get("warrior_swordsman", -1)) == 130)
	_check("공용 풀: 해금분도 같이 적립(0+25)", int(gg.sub_job_exp.get("warrior_berserker", -1)) == 25)
	_check("해금분은 자연히 레벨이 낮다", gg.sub_job_level("warrior_berserker") < gg.sub_job_level("warrior_swordsman"))
	# 서브 합산 — 메인을 광전사로 바꾸면 공속 쪽이 커진다(둘 다 효과가 있다 = 서브도 0이 아님)
	var haste_main_sword := float(gg.current_level_stats()["haste"])
	_check("서브도 효과가 있다(합산 > 메인 단독 아님)", haste_main_sword > 0.0)

	# 메인 전환 — 마을에서만(GDD §5)
	_check("미보유 하위 직업으로 전환 거부", not gg.set_main_sub_job("bogus_sub"))
	_check("전환 성공(마을)", gg.set_main_sub_job("warrior_berserker"))
	_check("전환 반영", gg.main_sub_job_id == "warrior_berserker")
	gg.begin_stage("chapter1", 0)
	_check("판 도중 전환 거부(스탯 취사선택 차단)", not gg.set_main_sub_job("warrior_swordsman"))
	_check("거부 시 메인 불변", gg.main_sub_job_id == "warrior_berserker")
	gg.leave_chapter()
	_check("마을 복귀 후 전환 허용", gg.set_main_sub_job("warrior_swordsman"))
	# 타 계열 전환 거부 — 궁수로 바꾼 뒤 전사 하위 직업을 메인으로 요구
	gg.selected_job_id = "archer"
	_check("타 계열 하위 직업 메인 거부", not gg.set_main_sub_job("warrior_berserker"))
	_check("타 계열에선 보유 목록이 비어 EXP가 안 섞인다", gg.owned_sub_jobs().is_empty())
	# 리뷰 I3: 계열이 섞였을 때 표시가 거짓말하지 않는지 — 메인이 타 계열이면 없는 것으로 본다
	_check("타 계열 선택 시 main_sub_job() = null (HUD 거짓 표기 방지)", gg.main_sub_job() == null)
	_check("타 계열 선택 시 EXP 진행 표기 = 0", int(gg.main_exp_progress()["level"]) == 0)
	_check("타 계열 선택 시 레벨 스탯 = 전부 0", is_equal_approx(float(gg.current_level_stats()["crit"]), 0.0))
	_check("타 계열에선 add_exp가 no-op", not gg.add_exp(100))
	_check("전사 진행분은 그대로 보존(계열 무관 보관)", int(gg.sub_job_exp.get("warrior_swordsman", -1)) == 130)
	gg.selected_job_id = "warrior"

	# clamp 상한 — 데이터 유도(max_level_stats)가 하드 상한 이하이고 0이 아니다
	var caps: Dictionary = gg.max_level_stats()
	_check("max_level_stats: 치명 상한 > 0 (데이터 유도)", float(caps["crit"]) > 0.0)
	_check("max_level_stats: 하드 상한 이하",
		float(caps["crit"]) <= float(CombatMath.LEVEL_STAT_MAX["crit"]))
	_check("정직한 만성장 ≤ 데이터 유도 상한",
		float(gg.current_level_stats()["crit"]) <= float(caps["crit"]))

	# 저장 — 필드 추가(버전 불변), 구 세이브 폴백, 조작 세이브 폐기
	var gsnap: Dictionary = gg.to_save_dict()
	_check("저장에 성장 필드 포함", gsnap.has("main_sub") and gsnap.has("sub_exp"))
	_check("레벨은 저장하지 않는다(EXP에서 파생)", not gsnap.has("sub_level"))
	var gg2 := GameStateScript.new() as Node
	gg2.from_save_dict(gsnap)
	_check("저장 복원: EXP", int(gg2.sub_job_exp.get("warrior_swordsman", -1)) == 130)
	_check("저장 복원: 메인", gg2.main_sub_job_id == "warrior_swordsman")
	_check("저장 복원: 레벨 파생 일치", gg2.sub_job_level("warrior_swordsman") == gg.sub_job_level("warrior_swordsman"))
	# 구 세이브 = 성장 키가 아예 없다 → 빈 상태(레벨 0), 마을 진입의 지급이 채운다
	var gg3 := GameStateScript.new() as Node
	gg3.from_save_dict({"gold": 5, "materials": {}, "equipment": {}, "equipped": {"0": "", "1": ""}})
	_check("구 세이브: 성장 키 없음 → 보유 0", gg3.owned_sub_jobs().is_empty())
	_check("구 세이브: 레벨 0", gg3.sub_job_level("warrior_swordsman") == 0)
	_check("구 세이브: 기존 인벤은 정상 로드(회귀 방어)", gg3.gold == 5)
	gg3.grant_starting_sub_job(gg3.job_def("warrior"))
	_check("구 세이브 + 지급 = 레벨 0으로 시작", gg3.has_sub_job("warrior_swordsman") and gg3.sub_job_level("warrior_swordsman") == 0)
	# 조작 세이브 — 모르는 id 폐기, 음수 EXP 0, 메인이 비보유면 비워둔다
	gg3.from_save_dict({"sub_exp": {"hack_sub": 99999, "warrior_swordsman": -50}, "main_sub": "hack_sub"})
	_check("조작 세이브: 모르는 하위 직업 폐기", not gg3.has_sub_job("hack_sub"))
	_check("조작 세이브: 음수 EXP → 0", int(gg3.sub_job_exp.get("warrior_swordsman", -1)) == 0)
	_check("조작 세이브: 비보유 메인 → 비움(지급이 보정)", gg3.main_sub_job_id == "")
	# 과대 EXP 주입도 레벨/스탯이 만레벨을 넘지 못한다(clamp가 아니라 파생 구조로 막는다)
	gg3.from_save_dict({"sub_exp": {"warrior_swordsman": 99999999}, "main_sub": "warrior_swordsman"})
	var sdef: SubJobDef = gg3.sub_job_def("warrior_swordsman")
	_check("조작 세이브: 과대 EXP → 만레벨에서 멈춤", gg3.sub_job_level("warrior_swordsman") == sdef.max_level)
	_check("조작 세이브: 스탯도 데이터 유도 상한 이하",
		float(gg3.current_level_stats()["crit"]) <= float(gg3.max_level_stats()["crit"]))
	gg3.free()
	gg2.free()
	gg.free()

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
