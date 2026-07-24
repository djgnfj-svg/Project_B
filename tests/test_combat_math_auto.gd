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
