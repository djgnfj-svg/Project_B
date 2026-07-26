extends SceneTree
# CombatMath(§3 하드 계약) 단위 테스트 — 신뢰 경계(사거리·쿨다운·화살 발사율/원점/명중)의 경계값 전 구간.
# 성공/실패 모두 한 줄씩 찍는다 (침묵 통과 방지 — projectb-verify §3).
# 실행: ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_combat_math_auto.gd


func _initialize() -> void:
	var failures := 0
	var job := JobDef.new()
	job.attack_damage = 7
	job.attack_range = 20.0    # 여유 배율 2.0 → 검증 한계 40.0
	job.attack_cooldown = 0.4  # 0.9배 → 360ms

	failures += _check(CombatMath.calc_damage(job) == 7, "calc_damage = attack_damage")

	var origin := Vector2.ZERO
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(39.9, 0.0), job), "reach: 한계 안(39.9) 허용")
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(40.0, 0.0), job), "reach: 경계선(40.0) 허용")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(40.1, 0.0), job), "reach: 한계 밖(40.1) 거부")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(0.0, 500.0), job), "reach: 원거리(500) 거부")

	failures += _check(CombatMath.is_hit_cooldown_ok(1000, 1030, job), "cooldown: 같은 스윙(30ms) 허용")
	failures += _check(CombatMath.is_hit_cooldown_ok(1000, 1050, job), "cooldown: 같은 스윙 경계(50ms) 허용")
	failures += _check(not CombatMath.is_hit_cooldown_ok(1000, 1051, job), "cooldown: 스윙 창 직후(51ms) 거부")
	failures += _check(not CombatMath.is_hit_cooldown_ok(1000, 1359, job), "cooldown: 쿨다운 직전(359ms) 거부")
	failures += _check(CombatMath.is_hit_cooldown_ok(1000, 1360, job), "cooldown: 쿨다운 경과(360ms) 허용")

	# 구르기 그랜트 — ROLL_COOLDOWN_S 0.8 × 0.9 → 720ms
	failures += _check(not CombatMath.is_roll_grant_ok(1000, 1719), "roll grant: 쿨다운 직전(719ms) 거부")
	failures += _check(CombatMath.is_roll_grant_ok(1000, 1720), "roll grant: 쿨다운 경과(720ms) 허용")
	failures += _check(not CombatMath.is_roll_grant_ok(1000, 1000), "roll grant: 즉시 재요청(0ms) 거부")

	# --- 하위 직업 특성 (GDD v2.0) — 카탈로그 clamp + 구르기 파생 ---
	# 🔴 값은 네트워크로 안 온다(id만) — 여기 검사는 "데이터 실수와 상한 초과 주장을 어디서 자르나"다.
	failures += _check(is_equal_approx(CombatMath.clamp_trait("roll_cd", 0.15), 0.15), "trait: 정상값 통과")
	failures += _check(is_equal_approx(CombatMath.clamp_trait("roll_cd", 0.9),
		float(CombatMath.TRAIT_MAX["roll_cd"])), "trait: 상한 초과 → TRAIT_MAX clamp")
	failures += _check(is_equal_approx(CombatMath.clamp_trait("roll_cd", -0.5), 0.0), "trait: 음수 → 0 (디버프 주입 차단)")
	failures += _check(is_equal_approx(CombatMath.clamp_trait("roll_cd", INF), 0.0), "trait: INF → 0 (유한성 가드)")
	# 🔴 모르는 키는 상한 0이라 자동 폐기 — TRAIT_KEYS에 없는 축이 데이터 오타로 새어들지 않는다
	failures += _check(is_equal_approx(CombatMath.clamp_trait("attack", 99.0), 0.0), "trait: 모르는 키 → 0 (축 경계 방어)")
	var traits_in := {"reach": 0.3, "bogus": 5.0}
	var traits_out := CombatMath.clamp_traits(traits_in)
	failures += _check(is_equal_approx(float(traits_out.get("reach", -1.0)), 0.3), "trait: 묶음 clamp 정상 키 보존")
	failures += _check(not traits_out.has("bogus"), "trait: 묶음 clamp가 모르는 키 폐기(TRAIT_KEYS 순회)")
	failures += _check(is_equal_approx(float(traits_out.get("roll_cd", -1.0)), 0.0), "trait: 빠진 키는 0으로 채움(항등 폴백)")
	# 구르기 파생 — 로컬 쿨과 호스트 그랜트 게이트가 같은 함수를 지난다(§3)
	failures += _check(is_equal_approx(CombatMath.effective_roll_cooldown(0.0), CombatMath.ROLL_COOLDOWN_S),
		"roll cd: 특성 0 = 항등(도입 전과 동일)")
	failures += _check(is_equal_approx(CombatMath.effective_roll_cooldown(0.2), 0.64), "roll cd: −20% → 0.64s")
	failures += _check(is_equal_approx(CombatMath.effective_roll_cooldown(0.9),
		CombatMath.ROLL_COOLDOWN_S * (1.0 - float(CombatMath.TRAIT_MAX["roll_cd"]))),
		"roll cd: 상한 초과 주장도 TRAIT_MAX까지만 (상시 무적 차단)")
	# 🔴 게이트가 특성을 실제로 먹는지 — 안 먹으면 "굴러지는데 무적이 안 걸린다"가 된다(화면에 이유 안 드러남)
	failures += _check(CombatMath.is_roll_grant_ok(1000, 1576, 0.2), "roll grant+특성: 짧아진 창(576ms) 허용")
	failures += _check(not CombatMath.is_roll_grant_ok(1000, 1575, 0.2), "roll grant+특성: 창 직전(575ms) 거부")
	failures += _check(not CombatMath.is_roll_grant_ok(1000, 1576, 0.0), "roll grant: 특성 0이면 576ms는 여전히 거부(항등 보존)")
	failures += _check(is_equal_approx(CombatMath.effective_roll_speed(100.0, 0.0), 100.0 * CombatMath.ROLL_SPEED_MULT),
		"roll speed: 특성 0 = 항등")
	failures += _check(is_equal_approx(CombatMath.effective_roll_speed(100.0, 0.2), 100.0 * CombatMath.ROLL_SPEED_MULT * 1.2),
		"roll speed: +20% 반영")
	# 🔴 비율 보너스를 정수 수량에 살리는 소수 누적 — **리뷰 C1의 회귀 테스트**.
	#   드랍 재료가 1~2개라 반올림/절삭하면 +15%가 **정확히 0**이 된다(실측). 잔량을 누적해야 산다.
	var acc1 := CombatMath.accrue_bonus(1, 0.15, 0.0)
	failures += _check(int(acc1.get("qty", -1)) == 1 and is_equal_approx(float(acc1.get("carry", -1.0)), 0.15),
		"accrue: qty 1 + 15% → 이번엔 1, 잔량 0.15 (반올림이면 영원히 0이던 자리)")
	var carry := 0.0
	var got := 0
	for _i in range(20):
		var a := CombatMath.accrue_bonus(1, 0.15, carry)
		got += int(a.get("qty", 0))
		carry = float(a.get("carry", 0.0))
	failures += _check(got == 23, "accrue: 1개 20회 × 15% → 23개 (기댓값 보존, 실제 +15%)")
	failures += _check(int(CombatMath.accrue_bonus(4, 0.15, 0.0).get("qty", -1)) == 4,
		"accrue: 큰 수량도 잔량만 쌓고 즉시 올리지 않는다(0.6 < 1)")
	failures += _check(int(CombatMath.accrue_bonus(0, 0.15, 0.9).get("qty", -1)) == 0,
		"accrue: 수량 0은 그대로(잔량도 보존)")
	failures += _check(int(CombatMath.accrue_bonus(2, INF, 0.0).get("qty", -1)) == 2,
		"accrue: INF 비율 → 항등(유한성 가드)")
	failures += _check(is_equal_approx(float(CombatMath.accrue_bonus(2, 0.5, -5.0).get("carry", -1.0)), 0.0),
		"accrue: 음수 잔량 주입 → 0으로 정규화")

	# UI 문구는 카탈로그에서 파생 — 감소 축은 부호를 뒤집는다(표시와 실제가 갈라지지 않게)
	failures += _check(CombatMath.trait_text("roll_cd", 0.15).ends_with("−15%"), "trait_text: 감소 축은 − 표기")
	failures += _check(CombatMath.trait_text("reach", 0.3).ends_with("+30%"), "trait_text: 증가 축은 + 표기")
	failures += _check(CombatMath.trait_text("", 0.3) == "", "trait_text: 특성 없음 = 빈 문자열")

	# i-frame 창 — ROLL_TIME_S 0.25×1000 + GRACE 120 → 370ms
	failures += _check(CombatMath.is_iframe_active(1000, 1000), "iframe: 그랜트 직후(0ms) 유효")
	failures += _check(CombatMath.is_iframe_active(1000, 1370), "iframe: 창 경계(370ms) 유효")
	failures += _check(not CombatMath.is_iframe_active(1000, 1371), "iframe: 창 직후(371ms) 무효")

	# 잔몹 타격 반경
	failures += _check(CombatMath.is_strike_hit(Vector2(18.0, 0.0), Vector2.ZERO, 18.0), "strike: 경계선(18.0) 적중")
	failures += _check(not CombatMath.is_strike_hit(Vector2(18.1, 0.0), Vector2.ZERO, 18.0), "strike: 반경 밖(18.1) 빗나감")
	failures += _check(CombatMath.is_strike_hit(Vector2.ZERO, Vector2.ZERO, 18.0), "strike: 중심(0) 적중")

	# --- 보스전 (§3 하드 계약 — 보스 AI 판정과 텔레그래프 표시 공용 단일 소스) ---
	# 부채꼴 — apex=원점, facing=+x(0rad), half_angle=0.6rad(~34°), radius=50
	failures += _check(CombatMath.is_hit_in_cone(Vector2(40.0, 0.0), Vector2.ZERO, 0.0, 0.6, 50.0), "cone: 정면·사거리 안 적중")
	failures += _check(CombatMath.is_hit_in_cone(Vector2.ZERO, Vector2.ZERO, 0.0, 0.6, 50.0), "cone: 꼭짓점 위 적중")
	failures += _check(not CombatMath.is_hit_in_cone(Vector2(51.0, 0.0), Vector2.ZERO, 0.0, 0.6, 50.0), "cone: 정면이나 사거리 밖(51) 빗나감")
	# 각 경계: 반경 40, 각 = 0.6rad 안(0.5)/밖(0.7)
	failures += _check(CombatMath.is_hit_in_cone(Vector2(40.0, 0.0).rotated(0.5), Vector2.ZERO, 0.0, 0.6, 50.0), "cone: 반각 안(0.5rad) 적중")
	failures += _check(not CombatMath.is_hit_in_cone(Vector2(40.0, 0.0).rotated(0.7), Vector2.ZERO, 0.0, 0.6, 50.0), "cone: 반각 밖(0.7rad) 빗나감")
	failures += _check(not CombatMath.is_hit_in_cone(Vector2(-40.0, 0.0), Vector2.ZERO, 0.0, 0.6, 50.0), "cone: 뒤쪽(180°) 빗나감")
	# facing 회전(위쪽 향함 = PI/2): 위 적중, 옆 빗나감
	failures += _check(CombatMath.is_hit_in_cone(Vector2(0.0, 40.0), Vector2.ZERO, PI / 2.0, 0.6, 50.0), "cone: facing 회전(위)·정면 적중")
	failures += _check(not CombatMath.is_hit_in_cone(Vector2(40.0, 0.0), Vector2.ZERO, PI / 2.0, 0.6, 50.0), "cone: facing 회전(위)·옆 빗나감")

	# 인원 스케일링 — 솔로(1) 약화, 2인 이상 항등
	failures += _check(is_equal_approx(CombatMath.party_scale(100.0, 2), 100.0), "party_scale: 2인 = 항등(100)")
	failures += _check(is_equal_approx(CombatMath.party_scale(100.0, 1), 60.0), "party_scale: 솔로 = base*0.6(60)")
	failures += _check(is_equal_approx(CombatMath.party_scale(100.0, 1, 0.5), 50.0), "party_scale: 솔로 커스텀 factor(0.5)=50")

	# 사거리 검증에 적 몸 반경 반영 — job.attack_range 20 → 한계 40. 반경 48 보스는 중심 80이어도 표면(80-48=32<40) 적중
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(80.0, 0.0), job, 48.0), "reach+radius: 큰 보스 중심 80·반경48 → 표면(32) 적중")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(90.0, 0.0), job, 48.0), "reach+radius: 중심 90·반경48 → 표면(42>40) 거부")
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(40.0, 0.0), job), "reach+radius: 반경 기본 0 = 기존 동작 불변(40 허용)")

	# --- 메인 전용 특성: 검기 파형(사거리) — §3 사거리 계약 (GDD v1.9) ---
	# job.attack_range 20. reach +30% → 26 → 검증 한계 52. 상한(MAX_REACH_BONUS 0.5) → 30 → 한계 60.
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job), 20.0),
		"reach bonus: 기본값 0 = 항등(20)")
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, 0.3), 26.0),
		"reach bonus: +30% = 26")
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, 5.0), 30.0),
		"reach bonus: 상한 초과 주장(5.0) → +50%(30)로 clamp")
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, -2.0), 20.0),
		"reach bonus: 음수 주장 → 0(사거리 디버프 주입 차단)")
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, INF), 20.0),
		"reach bonus: INF(JSON 1e999) → 0 폴백")
	# 판정 게이트에 실제로 걸리는가 — 특성 없으면 거부되던 거리가 특성으로 허용된다
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(45.0, 0.0), job),
		"reach bonus: 특성 없으면 45 거부(한계 40)")
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(45.0, 0.0), job, 0.0, 0.3),
		"reach bonus: 특성 +30%면 45 허용(한계 52)")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(52.1, 0.0), job, 0.0, 0.3),
		"reach bonus: +30%여도 한계 밖(52.1) 거부")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(60.1, 0.0), job, 0.0, 9.0),
		"reach bonus: 상한 clamp 후 한계(60) 밖 거부 — 무한 사거리 주장 차단")
	# 🔴 기하 3함수가 **같은 확장 사거리**에서 파생되는가 — 하나라도 job.attack_range를 직접 읽으면
	#   판정과 표시가 갈라진다("맞는 곳 ≠ 보이는 곳"). 그 갈라짐을 여기서 잡는다.
	failures += _check(is_equal_approx(
			CombatMath.attack_center_offset(Vector2.RIGHT, job, 0.3).length(), 26.0 * 0.6),
		"reach bonus: 공격 중심도 확장 사거리에서 파생(15.6)")
	failures += _check(is_equal_approx(CombatMath.attack_radius(job, 0.3), 26.0 * 0.5),
		"reach bonus: 판정 반경도 확장 사거리에서 파생(13.0)")
	failures += _check(is_equal_approx(CombatMath.attack_radius(job), 10.0),
		"reach bonus: 기하 기본값 0 = 기존 동작 불변(반경 10)")
	# 적 몸 반경과 조합 — 둘 다 걸린다(보스 표면 + 확장 사거리)
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(99.0, 0.0), job, 48.0, 0.3),
		"reach bonus+radius: 보스 표면(51) < 확장 한계(52) 적중")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(99.0, 0.0), job, 48.0),
		"reach bonus+radius: 같은 거리도 특성 없으면 거부")

	# --- 장비 스탯 (§3 하드 계약 — 제작/강화 UI·전투·HUD 공용 단일 소스) ---
	failures += _check(CombatMath.calc_damage(job, 5) == 12, "calc_damage: 장비 보너스(+5) = 12")
	failures += _check(CombatMath.calc_damage(job, 0) == 7, "calc_damage: 보너스 0 = 기존 항등 폴백")
	var wep := EquipDef.new()
	wep.base_attack = 5
	wep.atk_per_level = 3
	wep.max_level = 5
	wep.upgrade_gold_base = 15
	var arm := EquipDef.new()
	arm.base_hp = 20
	arm.hp_per_level = 15
	failures += _check(int(CombatMath.equip_stat_at_level(wep, 0)["attack"]) == 5, "equip_stat: 무기 lv0 공격 = base 5")
	failures += _check(int(CombatMath.equip_stat_at_level(wep, 2)["attack"]) == 11, "equip_stat: 무기 lv2 공격 = 5+3*2")
	failures += _check(int(CombatMath.equip_stat_at_level(arm, 3)["hp"]) == 65, "equip_stat: 방어구 lv3 체력 = 20+15*3")
	var total := CombatMath.total_stats([[wep, 1], [arm, 2]])
	failures += _check(int(total["attack"]) == 8 and int(total["hp"]) == 50, "total_stats: 무기lv1+방어구lv2 = 공8·체50")
	var empty := CombatMath.total_stats([])
	failures += _check(int(empty["attack"]) == 0 and int(empty["hp"]) == 0, "total_stats: 미착용 = 공0·체0 (항등 폴백)")
	var up := CombatMath.upgraded_stats(wep, 1, 2)
	failures += _check(int(up["attack"]) == 3, "upgraded_stats: 무기 lv1→2 델타 = 공+3")
	failures += _check(CombatMath.upgrade_cost(wep, 0) == 15, "upgrade_cost: lv0→ = base*1 = 15")
	failures += _check(CombatMath.upgrade_cost(wep, 2) == 45, "upgrade_cost: lv2→ = base*3 = 45")

	# --- 투사체(궁수 활) 신뢰 경계 (§3 단일 소스 — G_SHOOT 검증 + 표시/판정 공용) ---
	# 발사율 — job.attack_cooldown 0.4 × 0.9 → 360ms. is_hit_cooldown_ok과 달리 SAME_SWING 다중타격 허용이 없다(화살 1발=1히트)
	failures += _check(not CombatMath.is_fire_rate_ok(1000, 1359, job), "fire_rate: 쿨다운 직전(359ms) 거부")
	failures += _check(CombatMath.is_fire_rate_ok(1000, 1360, job), "fire_rate: 쿨다운 경과(360ms) 허용")
	failures += _check(not CombatMath.is_fire_rate_ok(1000, 1030, job), "fire_rate: 연사 스팸(30ms) 거부 — 근접 SAME_SWING 허용 없음")
	# 발사 원점 근접 — SHOT_ORIGIN_TOL 44 (MUZZLE_OFFSET 26 + 지연 여유, 순간이동 원점 스푸핑 완화)
	failures += _check(CombatMath.is_shot_origin_ok(origin, Vector2(44.0, 0.0)), "shot_origin: 경계선(44.0) 허용")
	failures += _check(not CombatMath.is_shot_origin_ok(origin, Vector2(44.1, 0.0)), "shot_origin: 한계 밖(44.1) 거부")
	failures += _check(not CombatMath.is_shot_origin_ok(origin, Vector2(200.0, 0.0)), "shot_origin: 순간이동 원점(200) 거부")
	# 화살 명중 반경 — ARROW_HIT_RADIUS 6 + 적 body_radius (거대 적 §3 대응)
	failures += _check(CombatMath.is_arrow_hit(Vector2(6.0, 0.0), Vector2.ZERO), "arrow_hit: body0 경계선(6.0) 적중")
	failures += _check(not CombatMath.is_arrow_hit(Vector2(6.1, 0.0), Vector2.ZERO), "arrow_hit: body0 반경 밖(6.1) 빗나감")
	failures += _check(CombatMath.is_arrow_hit(Vector2(20.0, 0.0), Vector2.ZERO, 14.0), "arrow_hit: 브루트 body14 경계선(6+14=20) 적중")
	failures += _check(not CombatMath.is_arrow_hit(Vector2(20.1, 0.0), Vector2.ZERO, 14.0), "arrow_hit: 브루트 body14 밖(20.1) 빗나감")
	# 수명 = clamp(사거리)/속도 (무기별 사거리, 표시·호스트 공용 결정론). G_SHOOT "r"이 이 함수를 지난다.
	failures += _check(is_equal_approx(CombatMath.arrow_lifetime_s(), CombatMath.DEFAULT_ARROW_RANGE / CombatMath.ARROW_SPEED), "arrow_lifetime(): 폴백 = DEFAULT_ARROW_RANGE/SPEED")
	failures += _check(is_equal_approx(CombatMath.arrow_lifetime_s(210.0), 210.0 / CombatMath.ARROW_SPEED), "arrow_lifetime(210): 무기 사거리 그대로")
	# 사거리 clamp — 게스트 스푸핑 상한/하한 (호스트 신뢰 경계)
	failures += _check(is_equal_approx(CombatMath.clamp_arrow_range(9999.0), CombatMath.MAX_ARROW_RANGE), "clamp_range: 과대(9999) → MAX")
	failures += _check(is_equal_approx(CombatMath.clamp_arrow_range(1.0), CombatMath.MIN_ARROW_RANGE), "clamp_range: 과소(1) → MIN")
	failures += _check(is_equal_approx(CombatMath.clamp_arrow_range(220.0), 220.0), "clamp_range: 정상(220) 통과")
	failures += _check(is_equal_approx(CombatMath.clamp_arrow_range(NAN), CombatMath.DEFAULT_ARROW_RANGE), "clamp_range: NaN → DEFAULT (무한 화살 방어)")
	failures += _check(is_equal_approx(CombatMath.clamp_arrow_range(INF), CombatMath.DEFAULT_ARROW_RANGE), "clamp_range: INF → DEFAULT (비유한 방어)")
	failures += _check(is_equal_approx(CombatMath.arrow_lifetime_s(9999.0), CombatMath.MAX_ARROW_RANGE / CombatMath.ARROW_SPEED), "arrow_lifetime(9999): MAX로 clamp된 수명")

	# --- 차지 발사(법사 지팡이) §3 계약 — 레벨 clamp·홀드→레벨·위력/반경 배율·폭발 판정·차지 시간 검증 ---
	var step := 0.35  # worn_staff.charge_step_time
	# 레벨 clamp — 게스트가 주장하는 c는 반드시 0..MAX 안으로 접힌다 (배열 인덱스 안전 + 위력 상한)
	failures += _check(CombatMath.clamp_charge_level(-5) == 0, "charge clamp: 음수(-5) → 0")
	failures += _check(CombatMath.clamp_charge_level(99) == CombatMath.MAX_CHARGE_LEVEL, "charge clamp: 과대(99) → MAX")
	failures += _check(CombatMath.clamp_charge_level(2) == 2, "charge clamp: 정상(2) 통과")
	# 홀드 시간 → 레벨 (단계 경계값)
	failures += _check(CombatMath.charge_level_for(0.0, step) == 0, "charge_level: 탭(0s) → 0단계")
	failures += _check(CombatMath.charge_level_for(0.349, step) == 0, "charge_level: 1단계 직전(0.349s) → 0")
	failures += _check(CombatMath.charge_level_for(0.35, step) == 1, "charge_level: 1단계 경계(0.35s) → 1")
	failures += _check(CombatMath.charge_level_for(1.05, step) == 3, "charge_level: 3단계 경계(1.05s) → 3")
	failures += _check(CombatMath.charge_level_for(99.0, step) == CombatMath.MAX_CHARGE_LEVEL, "charge_level: 무한 홀드 → MAX에서 멈춤")
	failures += _check(CombatMath.charge_level_for(1.0, 0.0) == 0, "charge_level: step 0(비차지 무기) → 0단계")
	failures += _check(CombatMath.charge_level_for(NAN, step) == 0, "charge_level: NaN 홀드 → 0단계 (오염 가드)")
	# 위력 배율 — 0단계는 항등(궁수 화살 동작 불변), 최대 단계는 배율 적용
	failures += _check(CombatMath.charge_damage(16, 0) == 16, "charge_damage: 0단계 = 항등(비차지 무기 회귀 방어)")
	failures += _check(CombatMath.charge_damage(16, 3) == int(round(16.0 * CombatMath.CHARGE_DAMAGE_MULT[3])), "charge_damage: 3단계 = 배율 적용")
	failures += _check(CombatMath.charge_damage(16, 99) == CombatMath.charge_damage(16, CombatMath.MAX_CHARGE_LEVEL), "charge_damage: 과대 레벨 = MAX와 동일(스푸핑 상한)")
	# 폭발 반경 — 무기 기준 × 레벨 배율, 상한 clamp, 0/비유한이면 폭발 없음(단일 명중)
	failures += _check(is_equal_approx(CombatMath.charge_blast_radius(28.0, 0), 28.0), "blast_radius: 0단계 = 기준 반경")
	failures += _check(is_equal_approx(CombatMath.charge_blast_radius(28.0, 3), 28.0 * CombatMath.CHARGE_RADIUS_MULT[3]), "blast_radius: 3단계 = 배율 적용")
	failures += _check(is_equal_approx(CombatMath.charge_blast_radius(9999.0, 3), CombatMath.MAX_BLAST_RADIUS), "blast_radius: 과대 무기값 → MAX clamp(신뢰 경계)")
	failures += _check(is_equal_approx(CombatMath.charge_blast_radius(0.0, 3), 0.0), "blast_radius: 기준 0(화살) → 폭발 없음")
	failures += _check(is_equal_approx(CombatMath.charge_blast_radius(NAN, 2), 0.0), "blast_radius: NaN → 폭발 없음(오염 가드)")
	# 폭발 명중 — 반경 + 적 body_radius (거대 적 §3 대응), 경계값
	failures += _check(CombatMath.is_blast_hit(Vector2(40.0, 0.0), Vector2.ZERO, 40.0), "blast_hit: 경계선(40) 적중")
	failures += _check(not CombatMath.is_blast_hit(Vector2(40.1, 0.0), Vector2.ZERO, 40.0), "blast_hit: 반경 밖(40.1) 빗나감")
	failures += _check(CombatMath.is_blast_hit(Vector2(54.0, 0.0), Vector2.ZERO, 40.0, 14.0), "blast_hit: 브루트 body14 경계선(40+14) 적중")
	# 차지 시간 검증 — "그만큼 모을 시간이 있었는가" (연사하며 MAX 주장하는 스푸핑 차단)
	failures += _check(CombatMath.is_charge_time_ok(1000, 1000, 0, step), "charge_time: 0단계는 언제나 허용(탭 발사)")
	failures += _check(not CombatMath.is_charge_time_ok(1000, 1100, 3, step), "charge_time: 0.1s 만에 3단계 주장 거부")
	# 경계 ≈ 3×0.35×0.9 = 945ms. 부동소수 반올림에 테스트가 흔들리지 않게 ±5ms 밖에서 확인한다.
	failures += _check(not CombatMath.is_charge_time_ok(1000, 1940, 3, step), "charge_time: 3단계 창 직전(940ms) 거부")
	failures += _check(CombatMath.is_charge_time_ok(1000, 1950, 3, step), "charge_time: 3단계 창 경과(950ms) 허용")
	failures += _check(CombatMath.is_charge_time_ok(1000, 1320, 1, step), "charge_time: 1단계 창(315ms) 경과 허용")
	failures += _check(not CombatMath.is_charge_time_ok(1000, 1300, 1, step), "charge_time: 1단계 창 직전(300ms) 거부")
	failures += _check(not CombatMath.is_charge_time_ok(1000, 9000, 2, 0.0), "charge_time: 비차지 무기(step 0)의 레벨 주장 거부")
	# 투사체 속도 clamp — 무기별 탄속(느린 마법탄)의 유일한 진입점
	failures += _check(is_equal_approx(CombatMath.clamp_projectile_speed(0.0), CombatMath.ARROW_SPEED), "proj_speed: 미지정(0) → 기본 화살 속도")
	failures += _check(is_equal_approx(CombatMath.clamp_projectile_speed(240.0), 240.0), "proj_speed: 정상(240) 통과")
	failures += _check(is_equal_approx(CombatMath.clamp_projectile_speed(99999.0), CombatMath.MAX_PROJECTILE_SPEED), "proj_speed: 과대 → MAX clamp")
	failures += _check(is_equal_approx(CombatMath.clamp_projectile_speed(NAN), CombatMath.ARROW_SPEED), "proj_speed: NaN → 기본(오염 가드)")
	# 수명 = clamp(사거리)/clamp(속도) — 표시(ArrowField)와 호스트 판정이 같은 값을 얻는 결정론 근거
	failures += _check(is_equal_approx(CombatMath.projectile_lifetime_s(240.0, 240.0), 1.0), "proj_lifetime: 240px/240speed = 1.0s")
	failures += _check(is_equal_approx(CombatMath.projectile_lifetime_s(240.0, 0.0), 240.0 / CombatMath.ARROW_SPEED), "proj_lifetime: 속도 0 → 기본 속도로 계산")
	# 터널링 불변식(§3 주석) — 프레임당 전진 < 최소 명중 지름. MAX_PROJECTILE_SPEED를 올리면 여기가 빨개진다.
	failures += _check(CombatMath.MAX_PROJECTILE_SPEED / 60.0 < 2.0 * (CombatMath.ARROW_HIT_RADIUS + 6.0), "터널링 불변식: 프레임 전진 < 최소 명중 지름(body_radius 6 기준)")

	# --- 지연 보상 (§3, 2026-07-24) — "피했는데 맞았다"를 없애는 계약 ---
	# 편도 지연 정규화: 음수·NaN·스파이크를 판정에 쓸 수 있는 값으로
	failures += _check(is_equal_approx(CombatMath.clamp_one_way_ms(40.0), 40.0), "one_way: 정상(40ms) 통과")
	failures += _check(is_equal_approx(CombatMath.clamp_one_way_ms(-5.0), 0.0), "one_way: 음수 → 0(보상 없음)")
	failures += _check(is_equal_approx(CombatMath.clamp_one_way_ms(NAN), 0.0), "one_way: NaN → 0(오염 가드)")
	failures += _check(is_equal_approx(CombatMath.clamp_one_way_ms(9999.0), CombatMath.LAG_MAX_ONE_WAY_MS),
		"one_way: 과대 주장 → MAX clamp(예고 무한 지연 차단)")

	# 예고 타격 지연 = 가장 느린 피어의 편도 지연. 솔로(0)면 항등 = 기존 동작 보존
	failures += _check(is_equal_approx(CombatMath.strike_delay_s(0.0), 0.0), "strike_delay: 솔로/미측정(0) → 지연 0(항등)")
	failures += _check(is_equal_approx(CombatMath.strike_delay_s(80.0), 0.08), "strike_delay: 편도 80ms → 0.08s")
	failures += _check(is_equal_approx(CombatMath.strike_delay_s(9999.0), CombatMath.LAG_MAX_ONE_WAY_MS / 1000.0),
		"strike_delay: 과대 주장 → 상한(보스 예고 무한 지연 차단)")

	# 외삽 시간 = (수신 후 경과) + 편도 지연. 수신 기록이 없으면(로컬 피어) 0
	failures += _check(is_equal_approx(CombatMath.lag_lead_s(-1, 5000, 50.0), 0.0), "lag_lead: 수신 기록 없음 → 0(로컬 항등)")
	failures += _check(is_equal_approx(CombatMath.lag_lead_s(1000, 1030, 40.0), 0.07), "lag_lead: 경과 30ms + 편도 40ms = 0.07s")
	failures += _check(is_equal_approx(CombatMath.lag_lead_s(1000, 900, 0.0), 0.0), "lag_lead: 시계 역행 → 0(음수 외삽 금지)")

	# 위치 외삽 — 마지막 관측 속도로 추정, 거리 상한으로 폭주 차단
	failures += _check(CombatMath.extrapolate(Vector2.ZERO, Vector2(100.0, 0.0), 0.1).is_equal_approx(Vector2(10.0, 0.0)),
		"extrapolate: 100px/s × 0.1s = 10px 전진")
	failures += _check(CombatMath.extrapolate(Vector2(5.0, 5.0), Vector2(100.0, 0.0), 0.0).is_equal_approx(Vector2(5.0, 5.0)),
		"extrapolate: lead 0 → 항등(로컬 피어)")
	failures += _check(CombatMath.extrapolate(Vector2.ZERO, Vector2(INF, 0.0), 0.1).is_equal_approx(Vector2.ZERO),
		"extrapolate: Inf 속도 → 항등(오염 가드)")
	failures += _check(is_equal_approx(CombatMath.extrapolate(Vector2.ZERO, Vector2(9999.0, 0.0), 1.0).length(),
		CombatMath.LAG_MAX_LEAD_DIST), "extrapolate: 과대 속도 → 거리 상한으로 잘림")

	# --- 위치 패킷 신선도 (P2P fast 채널 = unordered, 2026-07-26 리뷰 I3) ---
	# 순서 뒤바뀜을 폐기하지 않으면 net_anchor와 net_anchor_lead가 **함께** 과거로 돌아가
	# "둘 다 맞아야 확정"인 방어자 우대 규약이 무력화된다(§3). 폐기 조건을 지우면 아래가 빨개진다.
	failures += _check(CombatMath.is_pos_seq_fresh(5, 4), "pos_seq: 다음 시퀀스 → 수용")
	failures += _check(not CombatMath.is_pos_seq_fresh(4, 5), "pos_seq: 뒤바뀐 옛 패킷 → 폐기")
	failures += _check(not CombatMath.is_pos_seq_fresh(5, 5), "pos_seq: 같은 시퀀스(중복 도착) → 폐기")
	failures += _check(CombatMath.is_pos_seq_fresh(0, 99), "pos_seq: 미부착(0) → 항등 폴백(릴레이·구버전 호환)")
	failures += _check(CombatMath.is_pos_seq_fresh(-3, 99), "pos_seq: 음수 오염 → 항등 폴백(폐기하지 않는다)")
	failures += _check(CombatMath.is_pos_seq_fresh(1, 0), "pos_seq: 첫 패킷 → 수용")

	# 🔴 방어자 우대 규약 — 낡은 좌표와 추정 좌표가 **둘 다** 안일 때만 적중.
	# 이 4줄이 "피했는데 맞았다"의 회귀 방지선이다.
	var c := Vector2.ZERO
	var r := 20.0
	failures += _check(CombatMath.is_strike_hit_lagged(Vector2(5.0, 0.0), Vector2(8.0, 0.0), c, r),
		"lagged: 둘 다 반경 안 → 적중")
	failures += _check(not CombatMath.is_strike_hit_lagged(Vector2(19.0, 0.0), Vector2(30.0, 0.0), c, r),
		"lagged: 낡은 좌표는 안이지만 추정은 밖(빠져나가는 중) → 빗나감 ★고치려던 그 버그")
	failures += _check(not CombatMath.is_strike_hit_lagged(Vector2(30.0, 0.0), Vector2(5.0, 0.0), c, r),
		"lagged: 들어오는 중 → 빗나감(방어자 우대)")
	failures += _check(not CombatMath.is_strike_hit_lagged(Vector2(40.0, 0.0), Vector2(50.0, 0.0), c, r),
		"lagged: 둘 다 밖 → 빗나감")
	# 항등 폴백 — 호스트 자신(두 좌표 동일)은 기존 is_strike_hit과 완전히 같아야 한다
	var same := Vector2(19.9, 0.0)
	failures += _check(CombatMath.is_strike_hit_lagged(same, same, c, r) == CombatMath.is_strike_hit(same, c, r),
		"lagged: 두 좌표 동일(로컬) → is_strike_hit과 항등")

	# 부채꼴도 같은 규약 (보스 평타)
	var apex := Vector2.ZERO
	failures += _check(CombatMath.is_hit_in_cone_lagged(Vector2(10.0, 0.0), Vector2(15.0, 0.0), apex, 0.0, 0.6, 40.0),
		"cone_lagged: 둘 다 부채꼴 안 → 적중")
	failures += _check(not CombatMath.is_hit_in_cone_lagged(Vector2(10.0, 0.0), Vector2(0.0, 30.0), apex, 0.0, 0.6, 40.0),
		"cone_lagged: 추정 좌표가 각 밖(옆으로 빠짐) → 빗나감")

	# --- 직업 레벨 · 캐릭터 스탯 5종 (§3, 성장축 2026-07-25 GDD v1.8) ---
	# 레벨 스탯 합산 — 메인 온전 + 서브 × SUB_JOB_WEIGHT
	var sub_a := SubJobDef.new()   # 검사류 (균형)
	sub_a.max_level = 5
	sub_a.crit_per_level = 0.02
	sub_a.haste_per_level = 0.02
	var sub_b := SubJobDef.new()   # 광전사류 (공격 특화)
	sub_b.max_level = 5
	sub_b.crit_per_level = 0.03
	sub_b.haste_per_level = 0.035
	var defs := {"a": sub_a, "b": sub_b}
	var lv_a := CombatMath.level_stats("a", {"a": 5, "b": 5}, defs, 0.4)
	failures += _check(is_equal_approx(float(lv_a["crit"]), 0.02 * 5 + 0.03 * 5 * 0.4),
		"level_stats: 메인(a) 온전 + 서브(b) ×0.4 합산")
	var lv_b := CombatMath.level_stats("b", {"a": 5, "b": 5}, defs, 0.4)
	failures += _check(float(lv_b["crit"]) > float(lv_a["crit"]),
		"level_stats: 메인을 특화 쪽(b)으로 바꾸면 그 스탯이 더 오른다")
	var lv_none := CombatMath.level_stats("", {}, {})
	failures += _check(is_equal_approx(float(lv_none["crit"]), 0.0) and is_equal_approx(float(lv_none["haste"]), 0.0),
		"level_stats: 보유 0 = 전부 0 (항등 폴백 — 성장축 도입 전 동작)")
	failures += _check(CombatMath.level_stats("a", {"a": 5, "zzz": 5}, defs, 0.4).has("crit"),
		"level_stats: 리졸브 실패 id(zzz)는 조용히 건너뛴다(폐기가 안전한 방향)")
	failures += _check(is_equal_approx(float(CombatMath.sub_job_stat_at_level(sub_a, 99)["crit"]), 0.02 * 5.0),
		"sub_job_stat: 과대 레벨(99) → max_level(5)로 clamp")

	# 레벨 스탯 clamp — G_STATS "lv" 수신 신뢰 경계 (뮤테이션: 이 clamp를 지우면 아래 5줄이 빨개진다)
	failures += _check(is_equal_approx(float(CombatMath.clamp_level_stats({"crit": 9.0})["crit"]), 1.0),
		"clamp_level: 과대 치명(9.0) → 하드 상한 1.0")
	failures += _check(is_equal_approx(float(CombatMath.clamp_level_stats({"haste": 9.0})["haste"]), float(CombatMath.LEVEL_STAT_MAX["haste"])),
		"clamp_level: 과대 공속 → LEVEL_STAT_MAX")
	failures += _check(is_equal_approx(float(CombatMath.clamp_level_stats({"leech": -1.0})["leech"]), 0.0),
		"clamp_level: 음수 피흡 → 0 (디버프 주입 차단)")
	failures += _check(is_equal_approx(float(CombatMath.clamp_level_stats({"crit": NAN})["crit"]), 0.0),
		"clamp_level: NaN → 0 (오염 가드)")
	failures += _check(is_equal_approx(float(CombatMath.clamp_level_stats({"move": INF})["move"]), 0.0),
		"clamp_level: INF → 0 (JSON 1e999 방어)")
	failures += _check(is_equal_approx(float(CombatMath.clamp_level_stats({"crit": 0.5}, {"crit": 0.2})["crit"]), 0.2),
		"clamp_level: 데이터 유도 상한(caps 0.2)이 하드 상한보다 우선")
	var cl := CombatMath.clamp_level_stats({"bogus": 5.0, "crit": 0.1})
	failures += _check(not cl.has("bogus") and cl.size() == CombatMath.LEVEL_STAT_KEYS.size(),
		"clamp_level: 모르는 키 폐기 + 빠진 키 0 채움 (payload가 아니라 키 목록을 순회)")

	# 🔴 최종 데미지 단일 소스 — 곱 순서 (기본+장비) × 차지 × 치명, **반올림 1회**
	var none_lv := CombatMath.empty_level_stats()
	var r0 := CombatMath.confirm_damage(job, 0, none_lv, 0, 1.0)
	failures += _check(int(r0["damage"]) == CombatMath.calc_damage(job) and not bool(r0["crit"]),
		"confirm_damage: 레벨 스탯 0·차지 0 = calc_damage와 항등(회귀 방어)")
	failures += _check(int(CombatMath.confirm_damage(job, 5, none_lv, 0, 1.0)["damage"]) == 12,
		"confirm_damage: 장비 보너스(+5) 반영 = 12")
	failures += _check(int(CombatMath.confirm_damage(job, 0, none_lv, 3, 1.0)["damage"]) == CombatMath.charge_damage(7, 3),
		"confirm_damage: 차지 3단계 = charge_damage와 일치")
	var crit_always := {"crit": 1.0, "crit_dmg": 0.5}
	var rc := CombatMath.confirm_damage(job, 0, crit_always, 0, 0.0)
	failures += _check(bool(rc["crit"]) and int(rc["damage"]) == 14,
		"confirm_damage: 치명 확정(배율 1.5+0.5=2.0) → 7×2 = 14")
	failures += _check(not bool(CombatMath.confirm_damage(job, 0, {"crit": 0.2}, 0, 0.2)["crit"]),
		"confirm_damage: 굴림이 확률 경계와 같으면(0.2 < 0.2 거짓) 비치명 — 경계 규약")
	failures += _check(bool(CombatMath.confirm_damage(job, 0, {"crit": 0.2}, 0, 0.199)["crit"]),
		"confirm_damage: 굴림 < 확률 → 치명")
	failures += _check(not bool(CombatMath.confirm_damage(job, 0, {"crit": 9.0}, 0, 1.01)["crit"]),
		"confirm_damage: 부풀린 확률(9.0)도 clamp 1.0 — 굴림 1.01은 여전히 비치명(범위 밖 굴림 방어)")
	# 🔴 반올림 1회 트립와이어: base 5 × 차지1(1.7) × 치명(1.5) = 12.75 → 13.
	#    차지에서 먼저 round하면(9) × 1.5 = 13.5 → 14가 되어 빨개진다(이중 반올림 검출).
	var job5 := JobDef.new()
	job5.attack_damage = 5
	job5.attack_cooldown = 0.4
	failures += _check(int(CombatMath.confirm_damage(job5, 0, {"crit": 1.0, "crit_dmg": 0.0}, 1, 0.0)["damage"]) == 13,
		"confirm_damage: 반올림 1회(5×1.7×1.5=12.75→13) — 이중 반올림이면 14로 빨개진다")

	# 피흡 — 준 데미지 대비 소수 적립(정수 절삭으로 스탯이 죽지 않게 호출부가 누적)
	failures += _check(is_equal_approx(CombatMath.leech_gain(10, 0.06), 0.6), "leech_gain: 10뎀 × 6% = 0.6")
	failures += _check(is_equal_approx(CombatMath.leech_gain(0, 0.5), 0.0), "leech_gain: 0뎀 = 0 (오버킬 클립은 호출부가 실제 깎인 HP를 넘긴다)")
	failures += _check(is_equal_approx(CombatMath.leech_gain(10, 9.0), 10.0 * float(CombatMath.LEVEL_STAT_MAX["leech"])),
		"leech_gain: 부풀린 피흡 → 상한 clamp")

	# 공속 — 🔴 같은 배율(haste_scale)을 쿨다운·스윙 창·차지 스텝에 공유하는 것이 계약이다
	failures += _check(is_equal_approx(CombatMath.haste_scale(0.0), 1.0), "haste_scale: 0 = 1.0 (항등)")
	failures += _check(is_equal_approx(CombatMath.haste_scale(0.25), 0.8), "haste_scale: +25% → 0.8배 쿨다운")
	failures += _check(is_equal_approx(CombatMath.haste_scale(9.0), 1.0 / (1.0 + float(CombatMath.LEVEL_STAT_MAX["haste"]))),
		"haste_scale: 과대 주장 → MAX_HASTE로 clamp (연사 스푸핑 상한)")
	failures += _check(is_equal_approx(CombatMath.effective_cooldown(job), 0.4), "effective_cooldown: haste 0 = 원래 쿨다운(항등)")
	failures += _check(is_equal_approx(CombatMath.effective_cooldown(job, 0.25), 0.32), "effective_cooldown: +25% → 0.32s")
	# 검증 3함수의 haste 버전 — 빨라진 정당 타격이 거부되지 않아야 한다(호스트가 알 채널 = G_STATS "lv")
	failures += _check(not CombatMath.is_hit_cooldown_ok(1000, 1287, job, 0.25), "cooldown+haste: 창 직전(287ms) 거부")
	failures += _check(CombatMath.is_hit_cooldown_ok(1000, 1288, job, 0.25), "cooldown+haste: 창 경과(288ms) 허용 ★공속이 실제로 먹는다")
	failures += _check(not CombatMath.is_hit_cooldown_ok(1000, 1288, job), "cooldown: haste 0이면 288ms는 여전히 거부(항등 보존)")
	failures += _check(CombatMath.is_fire_rate_ok(1000, 1288, job, 0.25), "fire_rate+haste: 창 경과(288ms) 허용")
	failures += _check(not CombatMath.is_fire_rate_ok(1000, 1287, job, 0.25), "fire_rate+haste: 창 직전(287ms) 거부")
	failures += _check(is_equal_approx(CombatMath.effective_charge_step(0.35, 0.25), 0.28), "charge_step+haste: 0.35 → 0.28s")
	failures += _check(is_equal_approx(CombatMath.effective_charge_step(0.0, 0.25), 0.0), "charge_step: 0(비차지 무기)은 그대로 — '차지 불가' 판정 보존")
	failures += _check(CombatMath.is_charge_time_ok(1000, 1760, 3, 0.35, 0.25), "charge_time+haste: 3단계 창(756ms) 경과 허용")
	failures += _check(not CombatMath.is_charge_time_ok(1000, 1750, 3, 0.35, 0.25), "charge_time+haste: 3단계 창 직전(750ms) 거부")
	failures += _check(not CombatMath.is_charge_time_ok(1000, 1760, 3, 0.35), "charge_time: haste 0이면 760ms는 여전히 거부(항등 보존)")

	# 🔴 스윙 창 계약 데이터 전수 (rules §3) — 모든 무기 × 모든 직업 × haste 전 구간에서
	#    swing_time < attack_cooldown이 유지되나. 같은 배율을 곱하므로 수학적으로 자동 보존되지만,
	#    누군가 한쪽만 스케일하도록 고치면 여기가 빨개진다.
	var swing_ok := true
	var degenerate_ok := true
	var lead_ok := true
	for jf: String in DirAccess.get_files_at("res://data/jobs"):
		var jbase := jf.trim_suffix(".remap")
		if jbase.get_extension() != "tres":
			continue
		var j := load("res://data/jobs/%s" % jbase) as JobDef
		if j == null:
			continue
		# 🔴 외삽 상한 불변식(리뷰 I1, 2026-07-25): LAG_MAX_LEAD_DIST가 "최고 이속 × 구르기 배율 × 최대 lead"를
		#   덮어야 한다. 짧으면 추정 좌표가 예고 안에 남아 "둘 다 맞아야 확정" 규약이 **맞는 쪽**으로 기울고,
		#   빠르게 빠져나가는 피어가 다시 맞는다(2026-07-24에 고친 버그의 퇴행). 이속 상한을 올리면 여기가 빨개진다.
		#   ⚠ v2.0: 구르기 배율은 **특성(roll_dist)까지 포함한 최댓값**이어야 한다 — 「돌진 본능」이 구르기를
		#   길게 만드는데 여기서 빼면 상한이 실제 최대 외삽보다 작아져 같은 퇴행이 돌아온다.
		#   POS_SEND_RATE(30Hz)만 player.gd const라 여기 상수로 미러한다(구르기 배율은 CombatMath로 이사).
		var top_speed := CombatMath.effective_roll_speed(
			CombatMath.effective_move_speed(j.move_speed, float(CombatMath.LEVEL_STAT_MAX["move"])),
			float(CombatMath.TRAIT_MAX["roll_dist"]))
		var max_lead_s := CombatMath.LAG_MAX_ONE_WAY_MS / 1000.0 + 1.0 / 30.0
		if top_speed * max_lead_s > CombatMath.LAG_MAX_LEAD_DIST:
			lead_ok = false
		# 퇴화 트립와이어: 유효 쿨다운 게이트가 SAME_SWING_MS(다중 타격 창)보다 짧아지면 쿨다운 검증이 무의미해진다
		if CombatMath.effective_cooldown(j, float(CombatMath.LEVEL_STAT_MAX["haste"])) * 0.9 * 1000.0 <= float(CombatMath.SAME_SWING_MS):
			degenerate_ok = false
		for ef: String in DirAccess.get_files_at("res://data/equipment"):
			var ebase := ef.trim_suffix(".remap")
			if ebase.get_extension() != "tres":
				continue
			var e := load("res://data/equipment/%s" % ebase) as EquipDef
			if e == null or e.motion_type != "swing":
				continue
			# 직업 귀속(GameState.can_equip_job 규칙) — 실제로 착용 가능한 조합만 본다.
			# 계약은 "**착용** 직업의 attack_cooldown"이다(rules §3): 전사 대검(0.34)을 궁수 쿨다운(0.15)과
			# 비교하면 성립할 수 없는 조합에서 빨개진다. job_id가 비면 범용(아무 직업).
			if not e.job_id.is_empty() and e.job_id != j.id:
				continue
			for h: float in [0.0, 0.25, float(CombatMath.LEVEL_STAT_MAX["haste"])]:
				if e.swing_time * CombatMath.haste_scale(h) >= CombatMath.effective_cooldown(j, h):
					swing_ok = false
	failures += _check(swing_ok, "스윙 창 계약 전수: 모든 무기×직업×haste에서 swing_time < effective_cooldown")
	failures += _check(degenerate_ok, "퇴화 트립와이어: MAX_HASTE에서도 유효 쿨다운 게이트 > SAME_SWING_MS")
	failures += _check(lead_ok, "외삽 상한 불변식: LAG_MAX_LEAD_DIST ≥ 최고 이속×구르기×최대 lead (전 직업)")

	# 이동속도 — 로컬 이동과 원격 clamp가 같은 유도식을 쓰는 근거
	failures += _check(is_equal_approx(CombatMath.effective_move_speed(100.0, 0.0), 100.0), "effective_move: 보너스 0 = 항등")
	failures += _check(is_equal_approx(CombatMath.effective_move_speed(100.0, 0.15), 115.0), "effective_move: +15% = 115")
	failures += _check(is_equal_approx(CombatMath.effective_move_speed(100.0, 9.0), 100.0 * (1.0 + float(CombatMath.LEVEL_STAT_MAX["move"]))),
		"effective_move: 과대 주장 → MAX clamp")

	# EXP → 레벨 파생 (레벨은 저장하지 않는다 — 이 함수가 유일한 진실)
	var curve := PackedInt32Array([0, 25, 60, 105, 160, 300])
	failures += _check(CombatMath.level_for_exp(0, curve, 5) == 0, "level_for_exp: 0 EXP = 0레벨")
	failures += _check(CombatMath.level_for_exp(24, curve, 5) == 0, "level_for_exp: 1레벨 직전(24) = 0")
	failures += _check(CombatMath.level_for_exp(25, curve, 5) == 1, "level_for_exp: 1레벨 경계(25) = 1")
	failures += _check(CombatMath.level_for_exp(159, curve, 5) == 3, "level_for_exp: 4레벨 직전(159) = 3")
	failures += _check(CombatMath.level_for_exp(160, curve, 5) == 4, "level_for_exp: 4레벨 경계(160) = 4")
	failures += _check(CombatMath.level_for_exp(99999, curve, 5) == 5, "level_for_exp: 과대 EXP → 만레벨에서 멈춤(조작 세이브 방어)")
	failures += _check(CombatMath.level_for_exp(99999, curve, 3) == 3, "level_for_exp: max_level(3) clamp 우선")
	failures += _check(CombatMath.level_for_exp(500, PackedInt32Array(), 5) == CombatMath.level_for_exp(500, CombatMath.default_exp_curve(), 5),
		"level_for_exp: 빈 곡선 → 기본 곡선 폴백")
	var prog := CombatMath.exp_progress(30, curve, 5)
	failures += _check(int(prog["level"]) == 1 and int(prog["cur"]) == 5 and int(prog["need"]) == 35,
		"exp_progress: 30 EXP = 1레벨·구간 5/35")
	var prog_max := CombatMath.exp_progress(99999, curve, 5)
	failures += _check(int(prog_max["level"]) == 5 and int(prog_max["need"]) == 0,
		"exp_progress: 만레벨 = need 0 (잉여 EXP 폐기)")

	if failures == 0:
		print("TEST_OK combat_math")
		quit(0)
	else:
		printerr("TEST_FAIL combat_math — %d개 실패" % failures)
		quit(1)


func _check(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	printerr("  FAIL %s" % label)
	return 1
