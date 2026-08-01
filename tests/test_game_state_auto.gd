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
	# ⚠ 궁수·법사는 2026-08-01에 삭제됐다(기획상 폐기 — 전사 계열만 산다). 직업이 하나뿐이라
	#   "다른 직업"을 **실제 데이터로는 만들 수 없다** — 아래 귀속 테스트가 합성 EquipDef를 쓰는 이유다.
	_check("정상 id 리졸브", gs.job_def("warrior").id == "warrior")
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
	# 「도굴」 소수 잔량도 판 단위 런타임 상태다(저장 대상 아님) — 이월 HP와 같은 자리에서 리셋한다.
	gs.begin_stage("chapter1", 0)
	gs.drop_find_frac["material"] = 0.9
	gs.leave_chapter()
	_check("챕터 이탈 시 도굴 잔량 리셋", gs.drop_find_frac.is_empty())

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

	# --- 직업 귀속 (남의 직업 무기는 못 듦 — can_equip_job 단일 소스, equip·can_craft 공용) ---
	# 🔴 **소재가 합성이다** — 궁수·법사 삭제(2026-08-01) 후 `data/equipment`가 전부 전사 귀속이라
	#   실제 데이터로는 "남의 직업 무기"를 만들 수 없다. 규칙은 `job_id` **문자열 비교**라 그 직업이
	#   실재하지 않아도 검증에 충분하다. 이렇게 안 하면 이 규칙 전체가 검출력 0으로 침묵 통과한다
	#   (2026-07-26 실기 신고 "전사로 들어왔는데 마법 지팡이를 쓴다"가 이 규칙이 막는 것이다).
	var gsjob := GameStateScript.new() as Node
	gsjob.selected_job_id = "warrior"
	var foreign := EquipDef.new()
	foreign.id = "test_foreign_weapon"
	foreign.slot_name = "weapon"
	foreign.job_id = "test_other_job"       # 전사가 아닌 무언가 — 실재하지 않아도 된다
	gsjob._equip_cache["test_foreign_weapon"] = foreign   # 리졸버 주입(allowlist 밖 합성 def)
	gsjob.owned_equipment["test_foreign_weapon"] = 0
	gsjob.add_equipment("worn_greatsword")
	gsjob.equip("test_foreign_weapon")
	_check("전사가 남의 직업 무기 착용 거부(슬롯 빔)", gsjob.equipped_id(0) == "")
	_check("can_equip_job: 전사+남의 무기 = false", not gsjob.can_equip_job(foreign))
	gsjob.equip("worn_greatsword")
	_check("전사가 대검 착용 성공", gsjob.equipped_id(0) == "worn_greatsword")
	# 직업이 하나뿐이라 "그 직업이면 착용 성공"은 규칙 함수로만 겨눈다(equip 경로는 재현 불가)
	gsjob.selected_job_id = "test_other_job"
	_check("can_equip_job: 그 직업이면 true", gsjob.can_equip_job(foreign))
	_check("can_equip_job: 그 직업+대검 = false", not gsjob.can_equip_job(gsjob.equip_def("worn_greatsword")))
	gsjob.selected_job_id = "warrior"
	gsjob.equip("worn_greatsword")
	# 🔴 직업 전환 뒤처리 (2026-07-26 실기 신고 "전사로 들어왔는데 마법 지팡이를 쓴다").
	# can_equip_job은 equip() **시점**에만 걸린다 — 직업이 나중에 바뀌면 남의 무기가 착용된 채 남고,
	# 그 id가 G_STATS로 공지돼 호스트 판정(peer_weapon_id)까지 그 무기가 된다(전사가 차지 폭발).
	gsjob.equipped[0] = "test_foreign_weapon"  # 남의 무기를 낀 상태를 직접 만든다(직업 전환 경로 재현)
	_check("직업 전환: 남의 직업 무기 자동 해제",
		gsjob.revalidate_equipped() and gsjob.equipped_id(0) == "")
	_check("직업 전환: 해제해도 장비는 가방에 남는다",
		gsjob.owned_equipment.has("test_foreign_weapon"))
	# 빈 슬롯은 **보유분으로도** 채운다 — 안 그러면 위 해제 뒤 맨손으로 남는다(그 직업을 전에 해봤으면
	# 가방에 무기가 있는데도). 재지급은 여전히 안 한다(멱등).
	gsjob.grant_starting_loadout(gsjob.job_def("warrior"))
	_check("빈 슬롯: 보유 중인 시작 무기를 착용(맨손 방지)", gsjob.equipped_id(0) == "worn_greatsword")
	gsjob.grant_starting_loadout(gsjob.job_def("warrior"))
	_check("멱등: 재호출해도 착용·레벨 그대로",
		gsjob.equipped_id(0) == "worn_greatsword" and gsjob.equip_level("worn_greatsword") == 0)
	# 🔴 **해제하면 안 되는 것**도 고정한다 (리뷰 I-5). 현재 data/equipment 4장은 전부 job_id가
	#   채워져 있어, 재검증을 "전부 해제"로 망가뜨려도 위 케이스들이 전부 통과한다(검출력 0의 침묵 통과 —
	#   합성 SubJobDef로 공유 가드를 겨눈 것과 같은 상황). 범용 장비(job_id="")를 합성해 직접 겨눈다:
	#   방어구가 들어오는 순간 "마을 갈 때마다 방어구가 벗겨지는데 스위트는 그린"이 되는 것을 막는다.
	var generic := EquipDef.new()
	generic.id = "test_generic_armor"
	generic.slot_name = "armor"
	generic.job_id = ""  # 범용 — 어느 직업이든 착용 가능
	gsjob._equip_cache["test_generic_armor"] = generic  # 리졸버 주입(allowlist 밖 합성 def)
	gsjob.owned_equipment["test_generic_armor"] = 0
	gsjob.equip("test_generic_armor")
	_check("범용 장비(job_id 빈 값) 착용 성공", gsjob.equipped_id(1) == "test_generic_armor")
	gsjob.equipped[0] = "test_foreign_weapon"
	_check("직업 전환: 범용 장비는 **유지**(해제 대상은 귀속 위반분만)",
		gsjob.equipped_id(1) == "test_generic_armor")
	gsjob.revalidate_equipped()
	_check("직업 전환: 같은 순간 귀속 위반 무기는 해제", gsjob.equipped_id(0) == "")
	gsjob.free()
	# 🔴 세이브 로드 **비파괴** 케이스는 지금 재현할 수 없다 — 직업이 전사 하나뿐이라(궁수·법사
	#   2026-08-01 폐기) "남의 직업 무기"를 **실제 장비 id로** 만들 수 없고, `from_save_dict`는
	#   `if eid in equipment_ids()`로 allowlist를 거르므로 합성 id는 왕복에서 폐기된다.
	#   🔴 **규칙은 살아 있다**(`revalidate_equipped`·`apply_job_loadout`) — 검증만 공백이다.
	#   두 번째 직업이 생기면 이 블록을 되살려라(git: 2026-08-01 이전 판에 전문이 있다).
	#   그 규칙이 막는 것: 세이브가 직업을 안 담고 SaveManager가 로비보다 먼저 도는 탓에, 로드
	#   시점에 직업 필터를 걸면 상위 무기가 부팅마다 벗겨지고 시작 무기로 다운그레이드된다.

	# --- 투사체 파라미터 리졸브 (§3 단일 소스 — 표시 ArrowField = 판정 CombatAuthority) ---
	# 🔴 **적용 지점 자체**를 겨눈다. CombatMath.effective_projectile_range만 검사하면 "함수는 맞는데
	#   projectile_params가 그 함수를 안 부른다"가 통과한다 — 그 결함의 증상이 정확히
	#   "맞는 곳 ≠ 보이는 곳"이고, 화면엔 이유가 안 드러난다(호스트만 짧은 화살로 판정).
	# 무기 = **합성 shoot 무기** — 실제 발사형 장비(활·지팡이)는 궁수·법사 폐기와 함께 2026-08-01에
	# 삭제됐다. `projectile_params`는 id → `equip_def` 리졸브를 지나므로 `_equip_cache` 주입으로
	# 적용 지점을 그대로 겨눌 수 있다. 수명 = 사거리/속도라 수명 비교가 곧 거리 비교다.
	var gproj := GameStateScript.new() as Node
	var shooter := EquipDef.new()
	shooter.id = "test_shooter"
	shooter.motion_type = "shoot"
	shooter.arrow_range = 150.0
	# 콤보 필드 — 실제 활이 갖던 값과 같은 역할(3타에서 사거리 2배·데미지 2.5배).
	# 🔴 이걸 안 채우면 「적용 지점 검출」 케이스들이 통째로 침묵 통과한다.
	# 🔴 타별 **배열**이다(길이 = 콤보 타수). [1, 1, 2] = 3타만 사거리 2배 — 실제 활이 쓰던 형태.
	shooter.combo_range_mult = PackedFloat32Array([1.0, 1.0, 2.0])
	shooter.combo_damage_mult = PackedFloat32Array([1.0, 1.0, 2.5])
	gproj._equip_cache["test_shooter"] = shooter
	# 합성 charge 무기 — 차지 반경이 자라는 갈래(과잉 수정 방어)를 겨눈다
	var charger2 := EquipDef.new()
	charger2.id = "test_charger"
	charger2.motion_type = "charge"
	charger2.arrow_range = 150.0
	charger2.blast_radius = 40.0
	gproj._equip_cache["test_charger"] = charger2
	var bow_range: float = shooter.arrow_range
	var pp_base: Dictionary = gproj.projectile_params("test_shooter", 0.0, 0)
	var pp_zero: Dictionary = gproj.projectile_params("test_shooter", 0.0, 0, 0.0)
	var pp_bonus: Dictionary = gproj.projectile_params("test_shooter", 0.0, 0, 0.25)
	_check("projectile_params: 특성 인자 생략 = 0 = 도입 전과 항등",
		is_equal_approx(float(pp_base.get("life", -1.0)), float(pp_zero.get("life", -2.0))))
	_check("projectile_params: 특성 0의 수명 = arrow_range/속도 (항등 폴백)",
		is_equal_approx(float(pp_zero.get("life", -1.0)),
			CombatMath.projectile_lifetime_s(bow_range, float(pp_zero.get("speed", 0.0)))))
	_check("projectile_params: proj_range +25% → 수명(=사거리)이 실제로 1.25배 ★적용 지점 검출",
		is_equal_approx(float(pp_bonus.get("life", -1.0)), float(pp_zero.get("life", -2.0)) * 1.25))
	# 상한 초과 주장은 TRAIT_MAX에서, 그 뒤 사거리는 MAX_ARROW_RANGE에서 잘린다(이중 방어)
	var pp_over: Dictionary = gproj.projectile_params("test_shooter", 0.0, 0, 9.0)
	_check("projectile_params: 과대 특성 주장 → TRAIT_MAX(+50%)까지만",
		is_equal_approx(float(pp_over.get("life", -1.0)), float(pp_zero.get("life", -2.0)) * 1.5))
	# 무기 리졸브 실패(모르는 id) 경로에도 같이 걸린다 — fallback_range 쪽만 특성이 빠지면 갈라진다
	var pp_fb: Dictionary = gproj.projectile_params("bogus_weapon", 200.0, 0, 0.5)
	_check("projectile_params: 폴백 사거리(모르는 무기)에도 특성이 걸린다",
		is_equal_approx(float(pp_fb.get("life", -1.0)),
			CombatMath.projectile_lifetime_s(300.0, float(pp_fb.get("speed", 0.0)))))

	# --- 평타 콤보 (궁수 "평·평·쭉") 적용 지점 (§3 — 표시 ArrowField = 판정 CombatAuthority) ---
	# 🔴 CombatMath.combo_*만 검사하면 "함수는 맞는데 projectile_params가 안 부른다"가 통과한다.
	#   그 결함의 증상이 정확히 "3타가 화면에선 멀리 나가는데 판정은 평타"이고 화면엔 이유가 안 드러난다.
	# worn_bow = 사거리 150 · 콤보 [1, 1, 2] · 데미지 [1, 1, 2.5]. 수명 = 사거리/속도라 수명 비교가 곧 거리 비교다.
	var pp_c0: Dictionary = gproj.projectile_params("test_shooter", 0.0, 0, 0.0, 0)
	var pp_c1: Dictionary = gproj.projectile_params("test_shooter", 0.0, 0, 0.0, 1)
	var pp_c2: Dictionary = gproj.projectile_params("test_shooter", 0.0, 0, 0.0, 2)
	_check("projectile_params: 콤보 인자 생략 = 0타 = 도입 전과 항등",
		is_equal_approx(float(pp_zero.get("life", -1.0)), float(pp_c0.get("life", -2.0))))
	_check("projectile_params: 1타·2타는 같은 사거리(평·평)",
		is_equal_approx(float(pp_c0.get("life", -1.0)), float(pp_c1.get("life", -2.0))))
	_check("projectile_params: 3타 사거리 = 2배(쭉) ★적용 지점 검출 — 안 걸리면 여기가 빨개진다",
		is_equal_approx(float(pp_c2.get("life", -1.0)), float(pp_c0.get("life", -2.0)) * 2.0))
	_check("projectile_params: 3타 데미지 배율 = 2.5 (사거리와 **같은 리졸브**에서 함께 온다)",
		is_equal_approx(float(pp_c2.get("combo_dmg", -1.0)), 2.5))
	_check("projectile_params: 1타 데미지 배율 = 1.0 (항등)",
		is_equal_approx(float(pp_c0.get("combo_dmg", -1.0)), 1.0))
	# 범위 밖 타수 주장은 항등으로 떨어진다(표시 경로는 발신자 주장을 그대로 넘기므로 여기가 마지막 방어)
	_check("projectile_params: 범위 밖 타수 주장(99) → 항등 사거리",
		is_equal_approx(float(gproj.projectile_params("test_shooter", 0.0, 0, 0.0, 99).get("life", -1.0)),
			float(pp_c0.get("life", -2.0))))
	# 콤보 없는 무기(법사 지팡이)는 어떤 타수를 실어도 그대로 — 사용자 확정 "법사는 그대로 둔다"
	var pp_staff0: Dictionary = gproj.projectile_params("worn_staff", 0.0, 0, 0.0, 0)
	var pp_staff2: Dictionary = gproj.projectile_params("worn_staff", 0.0, 0, 0.0, 2)
	_check("projectile_params: 지팡이는 타수를 실어도 사거리 불변 ★법사 무변경 회귀 방어",
		is_equal_approx(float(pp_staff0.get("life", -1.0)), float(pp_staff2.get("life", -2.0))))
	_check("projectile_params: 지팡이 데미지 배율도 항등",
		is_equal_approx(float(pp_staff2.get("combo_dmg", -1.0)), 1.0))
	# 🔴 **비차지 무기(마법볼)에 실린 차지 레벨은 폭발 반경에서도 떨어진다** (2026-07-27 netreview I1).
	#   `level`·`scale`·`step_time`은 처음부터 게이트를 지났는데 `blast`만 `lv`를 날것으로 썼었다.
	#   판정은 `is_charge_time_ok`가 막지만 **표시**(`arrow_field`)는 이 함수를 직접 불러 반경을 기억하므로,
	#   조작 클라 한 통이 **정직한 파트너 화면에도** 48px 폭발 FX·소리·셰이크를 띄웠다.
	# 🔴 이 단정이 그 결함 클래스의 **유일한 자동 방어**다 — 나머지 층(`combat_authority`의 발사형 가드)은
	#   씬 글루라 `-s`가 preload할 수 없어 지워도 스위트가 초록이다(그 파일 주석 참조).
	var staff_r0 := float(gproj.projectile_params("worn_staff", 0.0, 0).get("blast", -1.0))
	var staff_r3 := float(gproj.projectile_params("worn_staff", 0.0, 3).get("blast", -1.0))
	_check("projectile_params: 마법볼(shoot)에 c=3을 실어도 폭발 반경 불변 ★표시 스푸핑 방어",
		is_equal_approx(staff_r0, staff_r3))
	_check("projectile_params: 마법볼 c=3 반경 = 0단계 반경(게이트를 되돌리면 ×2.4로 빨개진다)",
		is_equal_approx(staff_r3, CombatMath.charge_blast_radius(staff_r0, 0)))
	# ⚠ 반대 방향 회귀 방어 — **차지 무기는 여전히 자란다.** 위 게이트를 `is_charge` 없이 0으로
	#   못 박으면(과잉 수정) 여기가 빨개진다. 기대값은 .tres가 아니라 CombatMath에서 유도한다.
	var iron_r0 := float(gproj.projectile_params("test_charger", 0.0, 0).get("blast", -1.0))
	var iron_r3 := float(gproj.projectile_params("test_charger", 0.0, 3).get("blast", -1.0))
	_check("projectile_params: 차지 무기(합성)는 c=3에서 반경이 자란다 ★과잉 수정 방어",
		iron_r3 > iron_r0 and is_equal_approx(iron_r3, CombatMath.charge_blast_radius(iron_r0, 3)))
	# 특성(proj_range)과 콤보가 **함께** 곱해지되 MAX_ARROW_RANGE clamp를 우회하지 않는가(심층 방어).
	# ⚠ 기대값도 .tres에서 유도한다 — 사거리를 조일 때마다 여기가 거짓으로 빨개지지 않게.
	_check("projectile_params: 3타 × proj_range 상한이 함께 곱해진다(clamp 우회 없음)",
		is_equal_approx(float(gproj.projectile_params("test_shooter", 0.0, 0, 0.5, 2).get("life", -1.0)),
			CombatMath.projectile_lifetime_s(bow_range * 2.0 * 1.5,
				float(pp_c0.get("speed", 0.0)))))
	gproj.free()

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
	_check("하위 직업 스캔에 warrior_swordmaster(검성)", "warrior_swordmaster" in gg.sub_job_ids())
	_check("하위 직업 경로 조작 → null", gg.sub_job_def("../../src/core/net_schema") == null)
	_check("모르는 하위 직업 id → null", gg.sub_job_def("bogus_sub") == null)
	var series: Array = gg.sub_jobs_of_series("warrior")  # gg는 Node 캐스트라 반환 타입 추론 불가 — 명시
	# order 정렬 = 해금 체인의 순서 그대로. 계열에 하위 직업을 더하면 이 줄도 같이 늘린다
	# (부등호로 느슨하게 두면 순서가 뒤집혀도 통과해 해금 체인이 조용히 어긋난다).
	_check("계열 목록 = order 정렬(검사 → 광전사 → 검성)",
		series.size() == 3 and series[0] == "warrior_swordsman" and series[1] == "warrior_berserker" \
		and series[2] == "warrior_swordmaster")
	# ⚠ 궁수·법사 계열은 2026-08-01에 삭제됐다(기획상 폐기 — 전사 계열만 산다). 아래 「계열 목록을
	#   data/jobs 스캔에서 파생해 전수로 돈다」가 그 자리를 대신한다 — 직업이 늘면 자동으로 커버된다.
	# 🔴 3계열이 전부 채워졌다(2026-07-27) — 이제 "미작성 계열" 단정은 없다. 대신 **계열 목록 자체**를
	#   `data/jobs` 스캔에서 파생해 전수로 돈다: 직업이 늘었는데 하위 직업을 안 만들면 여기가 빨개진다
	#   (`add_exp`가 보유 0이면 즉시 return 해서 **성장 축이 통째로 안 도는데 에러가 안 난다** — 궁수·법사가
	#   실제로 그 상태였다). 계열별 개수는 위 세 블록이 이름까지 못박으므로 여기선 "비어 있지 않음"만 본다.
	for jid: String in gg.job_ids():
		_check("계열 '%s'에 하위 직업이 있다(없으면 EXP가 안 쌓인다)" % jid,
			not gg.sub_jobs_of_series(jid).is_empty())

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
	# 🔴 공지도 같은 판정을 써야 한다 — 나는 0으로 계산하는데 남에게는 id를 보내면 "같은 것을 두
	#   근거로 계산"하는 구조가 남는다(수신 측 계열 필터가 지금은 같은 결과를 내서 안 드러날 뿐).
	_check("타 계열 선택 시 공지 메인 id도 비어야 한다(계산 근거 통일)", gg.announced_main_id().is_empty())
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

	# 🔴 GDD §6 총 화력 예산 트립와이어 — max_level_stats()가 곧 "메인 만레벨 + 나머지 전부 서브 만레벨"의
	#   정직한 최대치라 예산과 직접 비교된다. **하위 직업을 추가하고 스텝 재역산을 잊으면 여기서 빨개진다**
	#   ("데이터 한 장"이 아니라 "재역산이 딸린 한 장" — GDD §6·§7). 하드 상한(LEVEL_STAT_MAX)은 스푸핑
	#   방어선이라 예산보다 넉넉하다 — 그래서 그 검사만으로는 예산 초과를 못 잡는다.
	var budget := {"crit": 0.20, "crit_dmg": 0.50, "haste": 0.25, "move": 0.15, "leech": 0.06}
	for key: String in budget:
		var got := float(caps.get(key, -1.0))
		_check("예산 %s: 만성장 %.3f ≤ GDD %.2f" % [key, got, float(budget[key])],
			got >= 0.0 and got <= float(budget[key]) + 0.0005)

	# 🔴 이동 축 합산 트립와이어 (리뷰 I1) — 「광란」(kill_move)은 5스탯 move와 **같은 축이라 더해진 뒤**
	#   LEVEL_STAT_MAX["move"]에서 잘린다. 데이터 최대 move + TRAIT_MAX["kill_move"]가 그 상한을 넘으면
	#   표시는 "+15%"인데 실제로는 조용히 깎인다(이속을 키울수록 광란이 사라진다). 둘 중 하나를 올릴 때
	#   여기가 빨개진다 — 그때는 값을 낮추거나, 축을 분리하고 LAG_MAX_LEAD_DIST를 재유도해라.
	#   ⚠ **현재 여유는 0.01뿐이다**(실측 move 0.14 + kill_move 0.15 = 0.29 ≤ 0.30). 이동 성장이 있는
	#   하위 직업을 하나만 더 넣거나 SUB_SLOT_COUNT를 3으로 올리면 즉시 빨개진다 — 빡빡한 게 정상이다.
	_check("이동 축 합산: 데이터 최대 move + kill_move ≤ LEVEL_STAT_MAX['move'] (표시=실제)",
		float(caps.get("move", 9.0)) + float(CombatMath.TRAIT_MAX.get("kill_move", 9.0))
			<= float(CombatMath.LEVEL_STAT_MAX.get("move", 0.0)) + 0.0005)

	# --- 하위 직업 특성 리졸브 (자리별 두 얼굴) — GDD v2.0 §5 ---
	# 🔴 네트워크로 오가는 것은 **하위 직업 id뿐**이고 값은 로컬 .tres에서 나온다(peer_weapon_id 철학).
	#   그래서 여기 검사는 곧 호스트가 원격 주장을 어떻게 거르는지의 검사다.
	#   ⚠ 딕셔너리는 반드시 `.get(키, 폴백)`으로 읽는다 — 직접 인덱싱하면 그 키를 지우는 뮤테이션에서
	#   SCRIPT ERROR로 테스트가 통째로 죽어 "검출력 0"이 통과로 위장된다 (verify §3, 2026-07-25).
	var t_main: Dictionary = gg.traits_of("warrior_swordmaster", [], "warrior")
	_check("특성: 검성을 **메인**에 = 평타 사거리 +30%",
		is_equal_approx(float(t_main.get("reach", -1.0)), 0.3))
	var t_sub: Dictionary = gg.traits_of("warrior_swordsman", ["warrior_swordmaster"], "warrior")
	# 🔴 자리별 두 얼굴의 핵심 계약 — 같은 검성이라도 서브면 **다른(약한) 특성**이 켜진다.
	_check("특성: 검성을 **서브**에 = 간격 감각 +10%(메인 특성 아님)",
		is_equal_approx(float(t_sub.get("reach", -1.0)), 0.1))
	_check("특성: 검사를 메인에 = 굳건한 자세(구르기 쿨 −20%)",
		is_equal_approx(float(t_sub.get("roll_cd", -1.0)), 0.2))
	# 같은 축은 합산되고 상한에서 잘린다(GDD §6 "보상은 있되 끝이 있다")
	var t_stack: Dictionary = gg.traits_of("warrior_swordsman", ["shared_acrobat"], "warrior")
	_check("특성: 같은 축 합산 = 검사 0.2 + 곡예사 0.15 → 상한 0.30",
		is_equal_approx(float(t_stack.get("roll_cd", -1.0)), CombatMath.TRAIT_MAX.get("roll_cd", 0.0)))
	# 🔒 공유 하위 직업은 **서브 전용** — 메인 자리에 넣어도 특성이 안 켜진다(SubJobDef.trait_at 구조 방어).
	# 🔴 현재 data/subjobs의 공유 2종은 main_trait_key가 비어 있어 **데이터만으로는 이 가드를 못 겨눈다**
	#   (가드를 지워도 빈 키에서 걸러져 테스트가 통과 = 검출력 0의 침묵 통과, verify §3에서 실제로 겪음).
	#   그래서 가드를 직접 겨누는 합성 def를 만든다 — 나중에 공유 .tres에 메인 특성을 적어 넣어도 안 켜진다.
	var fake_shared := SubJobDef.new()
	fake_shared.series_id = SubJobDef.SERIES_SHARED
	fake_shared.main_trait_key = "reach"
	fake_shared.main_trait_value = 0.5
	fake_shared.sub_trait_key = "roll_cd"
	fake_shared.sub_trait_value = 0.1
	_check("특성: 공유는 메인 자리 특성이 구조적으로 꺼진다(데이터에 적어도)",
		fake_shared.trait_at(true).is_empty())
	_check("특성: 공유의 서브 자리 특성은 정상 동작",
		is_equal_approx(float(fake_shared.trait_at(false).get("value", -1.0)), 0.1))
	var t_shared_main: Dictionary = gg.traits_of("shared_acrobat", [], "warrior")
	_check("특성: 공유를 메인 자리에 넣어도 꺼짐(서브 전용)",
		is_equal_approx(float(t_shared_main.get("roll_cd", -1.0)), 0.0))
	_check("특성: 공유는 서브 자리에서 켜짐(+15%)",
		is_equal_approx(float(gg.traits_of("", ["shared_acrobat"], "warrior").get("roll_cd", -1.0)), 0.15))
	_check("특성: 공유는 **다른 계열**에서도 켜진다(계열 무관)",
		is_equal_approx(float(gg.traits_of("", ["shared_acrobat"], "archer").get("roll_cd", -1.0)), 0.15))
	_check("특성: 타 계열 주장(archer가 검성) 폐기",
		is_equal_approx(float(gg.traits_of("warrior_swordmaster", [], "archer").get("reach", -1.0)), 0.0))
	_check("특성: 모르는 id 폐기",
		is_equal_approx(float(gg.traits_of("bogus_sub", [], "warrior").get("reach", -1.0)), 0.0))
	_check("특성: 경로 조작 폐기",
		is_equal_approx(float(gg.traits_of("../../src/core/net_schema", [], "warrior").get("reach", -1.0)), 0.0))
	# 🔴 슬롯 수 초과 공지 차단 — 서브를 10개 실어 특성을 쌓는 것을 SUB_SLOT_COUNT에서 잘라낸다
	var t_flood: Dictionary = gg.traits_of("", ["shared_acrobat", "warrior_swordmaster", "warrior_swordsman"], "warrior")
	_check("특성: 서브 초과분 폐기(3개 공지 → 앞 2개만)",
		is_equal_approx(float(t_flood.get("campfire_heal", -1.0)), 0.0))
	# 🔴 같은 id를 메인·서브에 동시에 실어 두 자리를 먹는 것 차단(5스탯 이중 계상의 특성판)
	_check("특성: 메인과 같은 id를 서브에 실어도 한 번만",
		is_equal_approx(float(gg.traits_of("warrior_swordmaster",
			["warrior_swordmaster"], "warrior").get("reach", -1.0)), 0.3))

	# --- 장착 슬롯 (메인 1 + 서브 2) — GDD v2.0 §5 ---
	gg.sub_job_exp["warrior_swordmaster"] = 0  # 해금 체인 대신 직접 보유시켜 슬롯만 검사
	gg.sub_job_exp["shared_acrobat"] = 0
	_check("슬롯: 검사를 메인으로", gg.set_main_sub_job("warrior_swordsman"))
	_check("슬롯: 서브 0번에 검성", gg.set_sub_slot(0, "warrior_swordmaster"))
	_check("슬롯: 메인과 같은 것을 서브에 = 거부", not gg.set_sub_slot(1, "warrior_swordsman"))
	# 미보유 = sub_job_exp에 키가 없는 것. 도굴꾼은 이 시점에 보유시키지 않았다(곡예사만 지급).
	_check("슬롯: 미보유 서브 거부", not gg.set_sub_slot(1, "shared_treasure_hunter"))
	_check("슬롯: 모르는 id 거부", not gg.set_sub_slot(1, "bogus_sub"))
	_check("슬롯: 공유는 서브에 가능", gg.set_sub_slot(1, "shared_acrobat"))
	_check("슬롯: 장착 3개", gg.equipped_sub_jobs().size() == 3)
	# 🔴 공지 페이로드는 **메인을 빼고** 서브만 실어야 한다 — 메인이 "ss"에 섞이면 수신 측
	#   traits_of가 SUB_SLOT_COUNT에서 앞 2개만 취하므로 **진짜 서브 하나가 밀려 사라진다**
	#   (dedup이 로컬에선 흡수해서 로컬 특성으론 안 드러난다 — 상대 화면에서만 갈라진다).
	var ann: Array = gg.announced_sub_ids()
	_check("공지: 서브 목록이 정확히 SUB_SLOT_COUNT개", ann.size() == 2)
	_check("공지: 서브 목록에 메인이 섞이지 않는다", gg.main_sub_job_id not in ann)
	_check("공지: 메인 id는 유효할 때만 실린다", gg.announced_main_id() == gg.main_sub_job_id)
	# 🔴 메인 전환 시 그 자리를 서브에서 빼 준다 — 안 그러면 한 하위 직업이 두 자리를 먹는다
	_check("슬롯: 서브에 낀 검성으로 메인 전환", gg.set_main_sub_job("warrior_swordmaster"))
	_check("슬롯: 전환 후에도 장착은 3개(중복 없음)", gg.equipped_sub_jobs().size() == 3)
	_check("슬롯: 전환 후 서브에 검성이 남지 않음",
		"warrior_swordmaster" not in [gg.sub_slot_id(0), gg.sub_slot_id(1)])
	# 🔴 예산이 슬롯에 묶이는 자리 — 낀 것만 5스탯에 들어간다(보유 전부가 아니라)
	gg.set_sub_slot(0, "")
	gg.set_sub_slot(1, "")
	var only_main: Dictionary = gg.current_level_stats()
	gg.set_sub_slot(0, "warrior_swordsman")
	var with_sub: Dictionary = gg.current_level_stats()
	_check("슬롯: 서브를 빼면 5스탯이 줄어든다(보유가 아니라 장착이 기준)",
		float(with_sub.get("leech", 0.0)) > float(only_main.get("leech", -1.0)))
	# 🔴 판 도중엔 슬롯이 안 바뀐다 (리뷰 I3) — 전투 중 해금이 빈 칸을 채우면 특성이 판 도중 켜지고,
	#   내 로컬 판정 기하는 즉시 넓어지는데 호스트의 원격 아바타는 공지 도달(편도) 뒤에야 바뀐다
	#   → 그 창에서 타격이 무음 거부되거나(사거리) 정당 변위가 clamp된다(구르기).
	gg.set_main_sub_job("warrior_swordsman")
	gg.set_sub_slot(0, "")
	gg.set_sub_slot(1, "")
	gg.begin_stage("chapter1", 0)
	gg.autofill_sub_slots()
	_check("슬롯: 판 도중 autofill이 슬롯을 안 건드린다(마을 전용 불변식)",
		gg.sub_slot_id(0).is_empty() and gg.sub_slot_id(1).is_empty())
	gg.leave_chapter()
	gg.autofill_sub_slots()
	_check("슬롯: 마을로 나오면 autofill이 빈 칸을 채운다", not gg.sub_slot_id(0).is_empty())
	# 🔴 배선 계약 (리뷰 I-1) — 판 중 해금분이 슬롯에 껴지는 유일한 자리가 마을 진입의
	#   grant_starting_sub_job이다. **이 함수를 부르면 빈 칸이 채워진다**를 여기서 고정한다.
	#   ⚠ 이 테스트는 "main.gd가 그 함수를 부르는가"(호출자 배선)는 못 본다 — 실제로 챕터→마을
	#   귀환 경로에 호출이 빠져 있었고 헤드리스는 그걸 통과시켰다(verify §3 사각). 실기로 확인해라.
	gg.set_sub_slot(0, "")
	gg.set_sub_slot(1, "")
	gg.grant_starting_sub_job(gg.job_def("warrior"))
	_check("배선: grant_starting_sub_job이 빈 서브 칸을 채운다(마을 진입 계약)",
		not gg.sub_slot_id(0).is_empty())
	# 🔴 손상/조작 세이브의 중복 슬롯 폐기 (리뷰 M1) — 안 막으면 한 칸이 조용히 죽고 패널은 둘 다 장착으로 그린다
	var dup_snap: Dictionary = gg.to_save_dict()
	dup_snap["sub_slots"] = ["warrior_swordmaster", "warrior_swordmaster"]
	var gdup := GameStateScript.new() as Node
	gdup.selected_job_id = "warrior"
	gdup.from_save_dict(dup_snap)
	_check("저장: 중복 서브 슬롯 → 한 칸만 남는다",
		not (gdup.sub_slot_id(0) == gdup.sub_slot_id(1) and not gdup.sub_slot_id(0).is_empty()))
	dup_snap["sub_slots"] = "손상된값"  # Array가 아닌 페이로드 (리뷰 M2)
	var gbad := GameStateScript.new() as Node
	gbad.from_save_dict(dup_snap)
	_check("저장: sub_slots가 Array가 아니면 빈 칸으로 폐기(런타임 에러 없음)",
		gbad.sub_slot_id(0).is_empty() and gbad.sub_slot_id(1).is_empty())
	gdup.free()
	gbad.free()
	gg.set_main_sub_job("warrior_swordsman")
	gg.set_sub_slot(0, "")
	gg.set_sub_slot(1, "")
	gg.sub_job_exp.erase("warrior_swordmaster")  # 이후 저장 검사에 영향 주지 않게 원복
	gg.sub_job_exp.erase("shared_acrobat")

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

	_check_all_data_loads()
	_check_content_reachability()

	gs.free()
	if _fails == 0:
		print("TEST_OK game_state")
		quit(0)
	else:
		printerr("TEST_FAIL game_state — %d건 실패" % _fails)
		quit(1)


# 🔴 **`data/**/*.tres` 전수 로드 트립와이어** (2026-07-27 신설).
# 이 프로젝트가 **같은 결함 클래스로 세 번** 값을 치렀다 — 전부 "에러 없이 초록불"이었다:
#   ⑴ 2026-07-26 보스 `.tres`가 `.aseprite`(로컬 전용 임포터)를 참조 → 챕터1 보스전이 통째로
#      로드 실패했는데 **웹 익스포트가 exit 0**이었다(실패는 로그 ERROR 줄에만 남는다).
#   ⑵ 2026-07-27 브루트가 어느 씬에도 없어 루프가 안 도는데 **스위트 8종이 내내 그린**.
#   ⑶ 2026-07-27 하위 직업 3장이 아이콘 미존재로 전량 로드 실패인데 **TEST_OK + exit 0**.
# 🔴 공통점 = **스위트는 계약을 지키지만 "그 파일이 실제로 열리는가"는 아무도 안 봤다.**
#   리졸버 테스트가 이걸 못 잡는 이유: `sub_job_def()` 류가 로드 실패 시 **null을 돌려주고 조용히
#   건너뛰므로**, 계열 목록이 비면 "미작성 계열"과 "깨진 계열"이 구분되지 않는다.
# ⚠ 그래서 여기서는 리졸버를 거치지 않고 **`ResourceLoader.load()`를 직접** 부른다(verify §2-5의
#   그 확인법 그대로). 새 데이터 폴더가 생기면 DirAccess 스캔이 자동으로 덮는다.
func _check_all_data_loads() -> void:
	var root := "res://data"
	var dirs := DirAccess.get_directories_at(root)
	_check("data 폴더 스캔 0건 아님(경로가 바뀌면 이 테스트가 통째로 무력해진다)", not dirs.is_empty())
	var total := 0
	for sub: String in dirs:
		var dir_path := "%s/%s" % [root, sub]
		for f: String in DirAccess.get_files_at(dir_path):
			# 익스포트본에서는 .tres가 .remap으로 바뀔 수 있다 — 확장자를 벗겨 원본 경로로 되돌린다.
			if f.ends_with(".remap"):
				f = f.trim_suffix(".remap")
			elif not f.ends_with(".tres"):
				continue
			total += 1
			var path := "%s/%s" % [dir_path, f]
			if ResourceLoader.load(path) == null:
				_check("데이터 로드: %s" % path, false)
	_check("data/**/*.tres 전수 로드 (%d개)" % total, true)


func _check(what: String, ok: bool) -> void:
	if ok:
		print("  ok: %s" % what)
	else:
		_fails += 1
		printerr("  FAIL: %s" % what)


# 🔴 **콘텐츠 도달성 트립와이어** (2026-07-28 신설).
# 위 `_check_all_data_loads`가 "그 파일이 열리는가"를 본다면, 이쪽은 **"그 콘텐츠에 손이 닿는가"** 를 본다.
# 🔴 정확히 이 축이 비어 있어서 2026-07-27에 값을 치렀다 — 유일한 도면 드랍원(브루트)이 어느 씬에도
#   배치돼 있지 않아 **3직업 전부 제작대에 도달할 수 없었는데 스위트 8종이 내내 그린**이었다.
#   파일은 전부 멀쩡히 열렸기 때문이다("코드상 닫힘"을 루프가 돈다는 근거로 쓰지 마라 — CLAUDE.md).
# 보는 것 넷 — 전부 **에러 없이 조용히 깨지는** 부류다:
#   ⑴ 레시피 결과 장비 실재 — 오타 하나면 제작 버튼이 조용히 아무것도 안 만든다
#   ⑵ 레시피 재료 실재 — 없는 재료를 요구하면 **영원히 제작 불가**인데 UI는 정상으로 보인다
#   ⑶ 적 드랍표 ref_id 실재 — 모르는 id는 `unlock_blueprint`/`add_material`이 경고 후 폐기(드랍이 증발)
#   ⑷ 🔴 모든 레시피에 **드랍원이 있는가** — 아무 적도 그 도면을 안 떨구면 그 무기는 없는 것과 같다
# ⚠ ⑷는 "그 적이 씬에 배치돼 있는가"까지는 못 본다(씬 스캔은 test_stage_dressing 몫). 한 겹 더 얕지만,
#   드랍표에 아예 없는 경우는 여기서 확실히 잡힌다.
func _check_content_reachability() -> void:
	var equip_ids := _data_ids("res://data/equipment")
	var material_ids := _data_ids("res://data/materials")
	var recipe_ids := _data_ids("res://data/recipes")

	# 적 드랍표에서 참조되는 도면·재료 id 수집 (⑶·⑷ 공용)
	var dropped_blueprints := {}
	var drop_ref_bad := 0
	for f: String in DirAccess.get_files_at("res://data/enemies"):
		if f.ends_with(".remap"):
			f = f.trim_suffix(".remap")
		elif not f.ends_with(".tres"):
			continue
		var edef := ResourceLoader.load("res://data/enemies/%s" % f) as EnemyDef
		if edef == null or edef.drop_table == null:
			continue
		for entry: DropEntry in edef.drop_table.entries:
			if entry == null:
				continue
			match entry.kind:
				"blueprint":
					dropped_blueprints[entry.ref_id] = true
					if not recipe_ids.has(entry.ref_id):
						_check("드랍 도면 실재: %s → data/recipes/%s.tres" % [f, entry.ref_id], false)
						drop_ref_bad += 1
				"material":
					if not material_ids.has(entry.ref_id):
						_check("드랍 재료 실재: %s → data/materials/%s.tres" % [f, entry.ref_id], false)
						drop_ref_bad += 1
	_check("적 드랍표 ref_id 전수 실재 (오류 %d건)" % drop_ref_bad, drop_ref_bad == 0)

	var recipe_bad := 0
	var unreachable := 0
	for rid: String in recipe_ids:
		var r := ResourceLoader.load("res://data/recipes/%s.tres" % rid) as RecipeDef
		if r == null:
			continue
		# ⑴ 결과 장비
		if not equip_ids.has(r.result_equip_id):
			_check("레시피 결과 장비 실재: %s → %s" % [rid, r.result_equip_id], false)
			recipe_bad += 1
		# ⑵ 재료
		for mid: Variant in r.material_costs.keys():
			if not material_ids.has(str(mid)):
				_check("레시피 재료 실재: %s → %s" % [rid, str(mid)], false)
				recipe_bad += 1
		# ⑷ 도달성 — 도면 드랍원이 없으면 그 무기는 영원히 못 만든다
		if not r.unlocked_by_default and not dropped_blueprints.has(rid):
			_check("🔴 도면 드랍원 없음: %s — 어떤 적도 이 설계도를 떨구지 않는다(영원히 제작 불가)" % rid,
				false)
			unreachable += 1
	_check("레시피 참조 전수 실재 (오류 %d건)" % recipe_bad, recipe_bad == 0)
	_check("🔴 레시피 도달성 전수: 모든 도면에 드랍원이 있다 (고아 %d건)" % unreachable, unreachable == 0)


# 폴더의 .tres 파일명(확장자 제거) 집합 — id = 파일명 관례(rules §4)에 기댄다.
func _data_ids(dir_path: String) -> Dictionary:
	var out := {}
	for f: String in DirAccess.get_files_at(dir_path):
		if f.ends_with(".remap"):
			f = f.trim_suffix(".remap")
		elif not f.ends_with(".tres"):
			continue
		out[f.trim_suffix(".tres")] = true
	return out
