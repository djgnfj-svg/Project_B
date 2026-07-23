extends SceneTree
# CombatMath(§3 하드 계약) 단위 테스트 — 신뢰 경계(사거리·쿨다운)의 경계값 전 구간.
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
