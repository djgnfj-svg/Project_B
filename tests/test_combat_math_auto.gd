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

	# --- on/off 특성: 홀드 연사(auto_fire) — **첫 토글 축** (속사수, 2026-07-28) ---
	# 🔴 나머지 7키는 전부 비율인데 이것만 스위치다. 그래서 검사 축이 둘이다 —
	#   ⑴ 카탈로그 등록 3곳(다른 키와 같은 함정: 하나라도 빠지면 상한 0으로 **조용히** 폐기된다)
	#   ⑵ 토글 관용구 자체(비교 부호·표기·축 오용) — 이쪽은 이 키가 처음이라 준거가 없다.
	var af_max := float(CombatMath.TRAIT_MAX.get("auto_fire", 0.0))
	failures += _check("auto_fire" in CombatMath.TRAIT_KEYS, "auto_fire: TRAIT_KEYS 등록(묶음 clamp 순회 대상)")
	failures += _check(is_equal_approx(af_max, 1.0), "auto_fire: 상한 1.0 (켜짐/꺼짐 — 비율이 아니다)")
	failures += _check(is_equal_approx(float(CombatMath.clamp_traits({"auto_fire": 1.0}).get("auto_fire", -1.0)), 1.0),
		"auto_fire: 묶음 clamp 통과 — TRAIT_MAX 미등록이면 여기가 0으로 빨개진다")
	failures += _check("auto_fire" in CombatMath.TRAIT_TOGGLE,
		"auto_fire: TRAIT_TOGGLE 등록 — 빠지면 아래 표기 두 줄이 '+100%'로 빨개진다")
	# 🔴 판정 단일 소스는 `>` 여야 한다 — `>=`로 바뀌면 특성이 **없는**(0.0) 대상까지 홀드 연사를 얻는다.
	# ⚠ 이것은 **로컬 입력 모드**의 정확성이지 신뢰 경계가 아니다(호스트는 auto_fire를 안 읽는다).
	#   사칭 방어를 여기서 증명했다고 읽지 마라 — 그 축은 `is_trait_on` 주석 참조.
	failures += _check(CombatMath.is_trait_on("auto_fire", 1.0), "auto_fire: 값 1.0 = 켜짐")
	failures += _check(not CombatMath.is_trait_on("auto_fire", 0.0),
		"auto_fire: 값 0.0 = 꺼짐 (>= 로 바뀌면 여기가 빨개진다 — 아무나 홀드 연사)")
	failures += _check(not CombatMath.is_trait_on("auto_fire", -1.0), "auto_fire: 음수 → 꺼짐 (clamp 경유)")
	failures += _check(not CombatMath.is_trait_on("auto_fire", INF), "auto_fire: INF(JSON 1e999) → 꺼짐 (유한성 가드)")
	# 🔴 비율 키를 스위치로 오용하는 것 차단 — reach는 값이 커도 토글 축이 아니라 항상 false다
	failures += _check(not CombatMath.is_trait_on("reach", 0.3),
		"auto_fire: 비율 키는 is_trait_on이 항상 false (축 오용 차단)")
	# 🔴 표기 — 스위치를 "+100%"로 내면 **곱해지는 축**처럼 읽혀 GDD §6 🔒 경계가 화면에서 흐려진다
	failures += _check(CombatMath.trait_text("auto_fire", 1.0) == "홀드 연사",
		"auto_fire: 켜짐 = 라벨만 (퍼센트 표기 금지)")
	failures += _check(CombatMath.trait_text("auto_fire", 0.0) == "",
		"auto_fire: 꺼짐 = 빈 문자열 (subjob_panel이 이걸로 스킵한다 — 안 그러면 '홀드 연사'가 항상 뜬다)")

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

	# --- 무기 부채꼴 근접 판정 (무기 모션 축 2026-07-28) — §3 히트 기하 계약 ---
	# 검/도끼/창을 가르는 축은 "사거리 × 반각" 둘뿐이고, 반각은 **EquipDef.swing_arc 그 자체**다
	# (판정용 각 필드를 신설하면 표시와 판정이 갈라진다 — 보스 콘 텔레그래프의 그 실패 형태).
	var spear := EquipDef.new()
	spear.melee_range = 80.0
	spear.swing_arc = 0.30      # 좁게 찌른다(±17°)
	var axe := EquipDef.new()
	axe.melee_range = 24.0
	axe.swing_arc = 1.9         # 넓게 쓸어낸다(±109°)
	var bare_weapon := EquipDef.new()  # melee_range 0 · swing_arc 기본 — 사거리는 직업 폴백
	var spear_arc := CombatMath.melee_half_angle(spear)
	var axe_arc := CombatMath.melee_half_angle(axe)

	# 사거리: 무기가 직업 기본을 **대신한다**. 0/null = 항등 폴백.
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, 0.0, spear), 80.0),
		"무기 사거리: melee_range 80이 직업 20을 대신한다")
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, 0.0, bare_weapon), 20.0),
		"무기 사거리: melee_range 0 = 직업 기본(20) 폴백")
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, 0.0, null), 20.0),
		"무기 사거리: 무장 해제(null) = 도입 전과 항등(20)")
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, 0.3, spear), 104.0),
		"무기 사거리: reach 특성도 무기 기준으로 곱해진다(80→104)")
	# 🔴 하드 상한 — 데이터 한 줄로 근접이 원거리가 되는 것 차단
	var far_weapon := EquipDef.new()
	far_weapon.melee_range = 1000.0
	failures += _check(is_equal_approx(CombatMath.effective_attack_range(job, 0.0, far_weapon),
			CombatMath.MAX_MELEE_RANGE),
		"무기 사거리: melee_range 1000 → MAX_MELEE_RANGE(130) clamp")

	# 반각: swing_arc가 곧 판정 각. 무장 해제 = 전방위(= 각 검사 없음).
	failures += _check(is_equal_approx(spear_arc, 0.30), "부채꼴: 반각 = EquipDef.swing_arc 그대로")
	failures += _check(is_equal_approx(CombatMath.melee_half_angle(null), CombatMath.MELEE_FULL_ARC),
		"부채꼴: 무장 해제 = 전방위(PI)")

	# 🔴 항등 — 각을 넘기지 않으면 도입 전과 완전히 같다(등 뒤도 맞았다)
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(-30.0, 0.0), job),
		"부채꼴: 각 미지정 = 등 뒤(-30)도 허용 — 도입 전 항등")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(-30.0, 0.0), job,
			0.0, 0.0, null, 0.0, 1.0),
		"부채꼴: 각 1.0이면 등 뒤(180°) 거부 — 이 전환의 요점")

	# 각 경계 — facing 0(오른쪽) 기준 ±1.0rad
	var pt_in := Vector2(cos(0.9), sin(0.9)) * 30.0
	var pt_out := Vector2(cos(1.1), sin(1.1)) * 30.0
	failures += _check(CombatMath.is_hit_in_reach(origin, pt_in, job, 0.0, 0.0, null, 0.0, 1.0),
		"부채꼴: 각 안(0.9 < 1.0) 허용")
	failures += _check(not CombatMath.is_hit_in_reach(origin, pt_out, job, 0.0, 0.0, null, 0.0, 1.0),
		"부채꼴: 각 밖(1.1 > 1.0) 거부")
	# 적 반경 각 여유 — asin(r/dist). 중심이 각 밖이어도 **몸통이 걸치면** 맞는다(거리 쪽 -radius와 대칭)
	failures += _check(CombatMath.is_hit_in_reach(origin, pt_out, job, 12.0, 0.0, null, 0.0, 1.0),
		"부채꼴: 각 밖이어도 몸통(r12, asin=0.41)이 걸치면 허용")
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(5.0, 0.0), job, 20.0, 0.0, null,
			PI, 0.30),
		"부채꼴: 몸통 안(dist 5 < r20)이면 각 무관 허용 — 등 뒤 조준도 겹침이면 맞는다")

	# 창 vs 도끼 — 같은 무기 축(사거리 × 각)이 정반대 성격을 만든다
	var side_pt := Vector2(cos(0.5), sin(0.5)) * 40.0
	failures += _check(CombatMath.is_hit_in_reach(origin, Vector2(90.0, 0.0), job, 0.0, 0.0,
			spear, 0.0, spear_arc),
		"창: 정면 90 허용(도달 80 × 여유 2.0)")
	failures += _check(not CombatMath.is_hit_in_reach(origin, side_pt, job, 0.0, 0.0,
			spear, 0.0, spear_arc),
		"창: 옆 40(각 0.5 > 0.30) 거부 — 좁게 찌른다")
	failures += _check(CombatMath.is_hit_in_reach(origin, side_pt, job, 0.0, 0.0, axe, 0.0, axe_arc),
		"도끼: 같은 옆 40(각 0.5 < 1.9) 허용 — 넓게 쓸어낸다")
	failures += _check(not CombatMath.is_hit_in_reach(origin, Vector2(90.0, 0.0), job, 0.0, 0.0,
			axe, 0.0, axe_arc),
		"도끼: 정면 90 거부(도달 24 × 여유 2.0 = 48) — 짧다")

	# 🔴🔴 **로컬 ≤ 호스트 불변식** — 로컬 질의(player)가 통과시킨 타격을 호스트가 거부하면
	#   G_HIT_REQ는 갔는데 확정이 안 나 **데미지만 조용히 사라진다**(에러 0). 두 경로가 각·반경
	#   규칙을 공유하고 거리 여유만 벌리는 구조가 이 부등식의 근거다 — 한쪽에 조건을 더하면 빨개진다.
	var strict_violations := 0
	for probe: EquipDef in [spear, axe, bare_weapon]:
		var p_range := CombatMath.effective_attack_range(job, 0.0, probe)
		var p_arc := CombatMath.melee_half_angle(probe)
		for ai in range(0, 36):
			var ang := TAU * float(ai) / 36.0
			for di in range(1, 16):
				var probe_pt := Vector2(cos(ang), sin(ang)) * (float(di) * 8.0)
				for prad: float in [0.0, 14.0, 42.0]:
					var local_ok := CombatMath.is_melee_in_cone(origin, probe_pt, 0.0, p_arc,
						p_range, prad)
					var host_ok := CombatMath.is_hit_in_reach(origin, probe_pt, job, prad, 0.0,
						probe, 0.0, p_arc)
					if local_ok and not host_ok:
						strict_violations += 1
	failures += _check(strict_violations == 0,
		"★로컬≤호스트 전수: 로컬이 통과시킨 근접타를 호스트가 거부하지 않는다 (위반 %d건)"
			% strict_violations)

	# --- 각 축 지연 보상 (netreview C-1, 2026-07-28) ---
	# 🔴 거리엔 HIT_REACH_SLACK 여유가 원래 있었지만 **각엔 아무 보상이 없었다.** apex가 net_anchor()
	#   (낡은 좌표)라 이동 중인 게스트는 각이 통째로 틀어져 정당한 타격이 거부됐다 — 게스트에서만·
	#   배포본에서만 "스윙은 보이는데 적 HP만 안 깎인다". 좁은 각 무기(창)가 오면 상시가 된다.
	# 위 전수 불변식은 두 apex에 **같은 좌표**를 넣으므로 이 축의 검출력이 0이다 — 여기서 따로 잡는다.
	var lag_target := Vector2(30.0, 0.0)   # 정면 30px
	var apex_off := Vector2(0.0, -20.0)    # 낡은 apex가 옆으로 20px 밀려 있다(걷기 ~150ms분)
	# anchor에서 보면 적이 각 밖(atan2(20,30) = 0.588 > 0.30)이지만 lead(정확한 위치)에서는 정면
	failures += _check(not CombatMath.is_hit_in_reach(apex_off, lag_target, job, 0.0, 0.0,
			spear, 0.0, spear_arc),
		"지연 보상 없음: 낡은 apex에서 각 밖(0.588 > 0.30) 거부 — 이것이 C-1의 증상")
	failures += _check(CombatMath.is_hit_in_reach_lagged(apex_off, Vector2.ZERO, lag_target, job,
			0.0, 0.0, spear, 0.0, spear_arc),
		"★지연 보상: lead가 각 안이면 통과 — 정당한 타격이 삭제되지 않는다")
	failures += _check(CombatMath.is_hit_in_reach_lagged(Vector2.ZERO, apex_off, lag_target, job,
			0.0, 0.0, spear, 0.0, spear_arc),
		"지연 보상: 반대(anchor가 각 안·lead가 밖)도 통과 — or 규약")
	failures += _check(not CombatMath.is_hit_in_reach_lagged(apex_off, apex_off * 1.5, lag_target,
			job, 0.0, 0.0, spear, 0.0, spear_arc),
		"지연 보상: 둘 다 각 밖이면 거부 — or가 무조건 통과가 아니다")
	# 🔴 **거리는 anchor 하나로 묶여 있다** — lead가 아무리 가까워도 anchor에서 사거리 밖이면 거부.
	#   이 비대칭이 "판정 집합 ⊆ (anchor 중심, 그 무기 사거리) 원"을 지켜 신뢰 경계를 보존한다.
	var far_anchor := Vector2(-400.0, 0.0)
	failures += _check(not CombatMath.is_hit_in_reach_lagged(far_anchor, Vector2.ZERO, lag_target,
			job, 0.0, 0.0, spear, 0.0, spear_arc),
		"★지연 보상: 거리는 anchor 기준 — lead가 코앞이어도 anchor가 멀면 거부(신뢰 경계 보존)")
	# 항등 — lead == anchor(호스트 자신·정지)면 비보상판과 완전히 같다
	var lagged_identity := true
	for ai2 in range(0, 24):
		var a2 := TAU * float(ai2) / 24.0
		for di2 in range(1, 10):
			var p2 := Vector2(cos(a2), sin(a2)) * (float(di2) * 9.0)
			if CombatMath.is_hit_in_reach_lagged(origin, origin, p2, job, 0.0, 0.0, axe, 0.0, axe_arc) \
					!= CombatMath.is_hit_in_reach(origin, p2, job, 0.0, 0.0, axe, 0.0, axe_arc):
				lagged_identity = false
	failures += _check(lagged_identity,
		"★지연 보상 항등 전수: lead == anchor면 비보상판과 완전 동일(호스트 자신·정지는 영향 0)")
	# 🔴 **판정 집합이 그 무기의 원을 절대 못 넘는가** — lead를 임의로 주장해도(스푸핑 상한 밖까지)
	#   anchor 기준 원 밖은 통과하지 못한다. 이 성질이 깨지면 각 보상이 사거리 우회로가 된다.
	var lead_escape := 0
	for ai3 in range(0, 24):
		var a3 := TAU * float(ai3) / 24.0
		var lead_far := Vector2(cos(a3), sin(a3)) * 500.0
		for di3 in range(1, 20):
			var p3 := Vector2(cos(a3 * 1.7), sin(a3 * 1.7)) * (float(di3) * 20.0)
			var host_reach := CombatMath.effective_attack_range(job, 0.0, spear) \
				* CombatMath.HIT_REACH_SLACK
			if CombatMath.is_hit_in_reach_lagged(origin, lead_far, p3, job, 0.0, 0.0, spear,
					0.0, spear_arc) and origin.distance_to(p3) > host_reach:
				lead_escape += 1
	failures += _check(lead_escape == 0,
		"★지연 보상: 임의 lead 주장으로도 anchor 기준 사거리를 못 넘는다 (탈출 %d건)" % lead_escape)

	# --- 대상(잔몹) 좌표 지연 보상 (netreview 2차 C-1, 2026-07-28) ---
	# 🔴 위 `or`는 **공격자** apex 두 개를 훑는다 — 적 좌표는 두 apex가 똑같이 쓰므로 **원리적으로
	#   못 덮는다**. 그리고 적 좌표가 더 낡다(G_MOB_POS 10Hz·fast·외삽 없음 vs 플레이어 15Hz+외삽).
	#   창은 각 예산이 좁아(반각 17.2° + 몸통 7.2°) 정상 지연 14px만으로 40%를 먹는다.
	failures += _check(CombatMath.mob_lag_slack_px(0.0) > 0.0,
		"몹 지연 슬랙: 편도 0이어도 송신 주기(0.1s)분은 남는다")
	failures += _check(
		CombatMath.mob_lag_slack_px(100.0) > CombatMath.mob_lag_slack_px(0.0),
		"몹 지연 슬랙: 편도가 크면 슬랙도 커진다")
	# 창(80px/±17°) + 옆으로 14px 밀린 몹 — 보상 없으면 거부, 있으면 통과
	var mob_off := Vector2(cos(0.30 + 0.12), sin(0.30 + 0.12)) * 80.0  # 각 0.42 > 반각 0.30
	failures += _check(not CombatMath.is_hit_in_reach_lagged(origin, origin, mob_off, job,
			0.0, 0.0, spear, 0.0, spear_arc),
		"몹 지연: 보상 0이면 각 밖(0.42 > 0.30) 거부 — 이것이 2차 C-1의 증상")
	failures += _check(CombatMath.is_hit_in_reach_lagged(origin, origin, mob_off, job,
			0.0, 0.0, spear, 0.0, spear_arc, 12.0),
		"★몹 지연: 슬랙 12px면 통과 — 게스트의 낡은 시야를 수용한다")
	# 🔴 **슬랙은 각만 넓히고 거리는 못 넓힌다** — 넣으면 판정 원이 커져 부분집합 성질이 깨진다
	var far_pt := Vector2(200.0, 0.0)  # 정면(각 통과) · 창 수용 160px 밖
	failures += _check(not CombatMath.is_hit_in_reach_lagged(origin, origin, far_pt, job,
			0.0, 0.0, spear, 0.0, spear_arc, 500.0),
		"★몹 지연: 슬랙 500px여도 사거리(160)는 못 넘는다 — 각 전용")

	# 🔴 데이터 전수: 모든 적 이속이 슬랙 유도 상한 안인가. 더 빠른 적을 추가하면 슬랙이 모자라
	#   창 타격이 다시 조용히 사라진다(그때 상한을 올릴지 그 적을 느리게 할지 판단하게 된다).
	var mob_speed_ok := true
	var fastest_mob := 0.0
	for enf: String in DirAccess.get_files_at("res://data/enemies"):
		var ebase := enf.trim_suffix(".remap")
		if ebase.get_extension() != "tres":
			continue
		var edef := load("res://data/enemies/%s" % ebase) as EnemyDef
		if edef == null:
			continue
		fastest_mob = maxf(fastest_mob, edef.move_speed)
		if edef.move_speed > CombatMath.MOB_LAG_SLACK_SPEED:
			mob_speed_ok = false
	failures += _check(mob_speed_ok,
		"★몹 이속 전수: 최대 %.0f ≤ MOB_LAG_SLACK_SPEED(%.0f) — 슬랙 유도가 성립한다"
			% [fastest_mob, CombatMath.MOB_LAG_SLACK_SPEED])

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
	var step := 0.35  # 합성 단계 시간(s) — 특정 무기 미러가 **아니다**(데이터를 조여도 이 단위 테스트는 안 흔들린다)
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

	# --- 원거리 특성: 투사체 사거리(proj_range) — §3 투사체 계약 (궁수·법사 계열) ---
	# 🔴 값은 네트워크로 안 온다(하위 직업 id만) — 여기 검사는 "데이터 실수와 상한 초과 주장을 어디서 자르나"다.
	# 🔴 reach는 근접 3함수 전용이라 원거리에 안 걸린다 — 그래서 별도 키다(두 축이 서로 안 샌다).
	var pr_max := float(CombatMath.TRAIT_MAX.get("proj_range", 0.0))
	failures += _check(is_equal_approx(CombatMath.clamp_trait("proj_range", 0.2), 0.2), "proj_range: 정상값(0.2) 통과")
	failures += _check(is_equal_approx(CombatMath.clamp_trait("proj_range", 0.9), pr_max),
		"proj_range: 상한 초과(0.9) → TRAIT_MAX(0.5) clamp")
	failures += _check(is_equal_approx(pr_max, 0.5), "proj_range: 상한 = 0.5 (사용자 확정 — reach와 대칭)")
	failures += _check(is_equal_approx(CombatMath.clamp_trait("proj_range", -1.0), 0.0),
		"proj_range: 음수 → 0 (사거리 디버프 주입 차단)")
	failures += _check(is_equal_approx(CombatMath.clamp_trait("proj_range", INF), 0.0),
		"proj_range: INF(JSON 1e999) → 0 (유한성 가드)")
	# 🔴 등록 3곳(TRAIT_KEYS·TRAIT_MAX·TRAIT_LABEL) — 하나라도 빠지면 clamp_trait가 상한 0으로 **조용히** 폐기한다
	failures += _check("proj_range" in CombatMath.TRAIT_KEYS, "proj_range: TRAIT_KEYS 등록(묶음 clamp 순회 대상)")
	failures += _check(is_equal_approx(float(CombatMath.clamp_traits({"proj_range": 0.3}).get("proj_range", -1.0)), 0.3),
		"proj_range: 묶음 clamp 통과 — TRAIT_MAX 미등록이면 여기가 0으로 빨개진다")
	failures += _check(CombatMath.trait_text("proj_range", 0.3).ends_with("+30%"),
		"proj_range: TRAIT_LABEL 등록 + 증가 축 표기(+) — TRAIT_REDUCTION에 넣으면 빨개진다")
	# 유효 사거리 — 표시(ArrowField)와 판정(CombatAuthority)이 **같이 지나는** 단일 소스
	failures += _check(is_equal_approx(CombatMath.effective_projectile_range(240.0), 240.0),
		"proj_range: 기본값 0 = 항등(특성 도입 전과 완전 동일)")
	failures += _check(is_equal_approx(CombatMath.effective_projectile_range(240.0, 0.25), 300.0),
		"proj_range: +25% → 300")
	failures += _check(is_equal_approx(CombatMath.effective_projectile_range(240.0, 9.0), 240.0 * (1.0 + pr_max)),
		"proj_range: 상한 초과 주장 → +50%까지만 (무한 사거리 주장 차단)")
	# 🔴 항등 트립와이어 — 특성 0의 수명이 도입 전 값과 **정확히** 같아야 한다(궁수 기존 동작 회귀 방어)
	failures += _check(is_equal_approx(
			CombatMath.projectile_lifetime_s(CombatMath.effective_projectile_range(240.0, 0.0), 240.0),
			CombatMath.projectile_lifetime_s(240.0, 240.0)),
		"proj_range: 특성 0의 life = 도입 전 life (항등 폴백)")
	failures += _check(
		CombatMath.projectile_lifetime_s(CombatMath.effective_projectile_range(240.0, pr_max), 240.0)
			> CombatMath.projectile_lifetime_s(240.0, 240.0),
		"proj_range: 특성이 실제로 수명(=날아가는 거리)을 늘린다 ★안 늘면 표시만 바뀌고 판정은 그대로")
	# 상한 밖 데이터는 여전히 MAX_ARROW_RANGE에서 잘린다 — 특성이 clamp를 우회하지 않는다(심층 방어)
	failures += _check(is_equal_approx(
			CombatMath.projectile_lifetime_s(CombatMath.effective_projectile_range(9999.0, pr_max), CombatMath.ARROW_SPEED),
			CombatMath.MAX_ARROW_RANGE / CombatMath.ARROW_SPEED),
		"proj_range: 과대 사거리 × 특성도 MAX_ARROW_RANGE clamp를 지난다(우회 없음)")
	# 🔴 절삭 불변식 전수 (데이터가 늘면 여기가 빨개진다): 정당한 원거리 무기가 상한에 **조용히** 잘리지
	#   않는가 — arrow_range × (1 + TRAIT_MAX) ≤ MAX_ARROW_RANGE. 이것이 상한 0.5의 근거 그 자체다
	#   (현: 최장 iron_staff 260 × 1.5 = 390 < 480). 화면 해상도에서 유도하지 마라 — GDD §9 TBD다.
	var proj_range_ok := true
	for ef2: String in DirAccess.get_files_at("res://data/equipment"):
		var ebase2 := ef2.trim_suffix(".remap")
		if ebase2.get_extension() != "tres":
			continue
		var e2 := load("res://data/equipment/%s" % ebase2) as EquipDef
		if e2 == null or (e2.motion_type != "shoot" and e2.motion_type != "charge"):
			continue
		if CombatMath.effective_projectile_range(e2.arrow_range, pr_max) > CombatMath.MAX_ARROW_RANGE:
			proj_range_ok = false
	failures += _check(proj_range_ok,
		"proj_range 절삭 불변식 전수: 모든 원거리 무기 × 상한 ≤ MAX_ARROW_RANGE(480)")

	# --- 평타 콤보 (궁수 "평·평·쭉") — §3 콤보 계약 (2026-07-27) ---
	# 🔴 여기 검사의 핵심은 **신뢰 경계**다: 사거리·데미지를 바꾸는 타수를 클라가 주장할 수 있는데,
	#   호스트가 그걸 그대로 믿으면 매 발사가 마무리 타(사거리 2배·데미지 2.5배)가 된다.
	var bow := EquipDef.new()
	bow.motion_type = "shoot"
	bow.arrow_range = 150.0
	bow.combo_range_mult = PackedFloat32Array([1.0, 1.0, 2.0])
	bow.combo_damage_mult = PackedFloat32Array([1.0, 1.0, 2.5])
	bow.combo_delay = PackedFloat32Array([0.0, 0.0, 0.25])
	var plain := EquipDef.new()  # 콤보 없는 무기(법사 지팡이·구 궁수 활) — 전 경로 항등이어야 한다
	plain.motion_type = "shoot"
	plain.arrow_range = 150.0
	var ajob := JobDef.new()
	ajob.attack_damage = 1
	ajob.attack_cooldown = 0.15

	failures += _check(CombatMath.combo_len(bow) == 3, "combo: 길이 = 배열 최대 크기(3)")
	failures += _check(CombatMath.combo_len(plain) == 1, "combo: 배열이 비면 길이 1 = 콤보 없음")
	failures += _check(CombatMath.combo_len(null) == 1, "combo: 무기 미착용(null)도 길이 1 (항등 폴백)")
	# 한 축만 채운 무기 — 모자란 칸은 배율 1.0·뜸 0.0으로 채워진다(길이를 손으로 맞추게 하지 않는다)
	var partial := EquipDef.new()
	partial.combo_damage_mult = PackedFloat32Array([1.0, 1.0, 3.0])
	failures += _check(CombatMath.combo_len(partial) == 3, "combo: 한 축만 채워도 길이가 잡힌다")
	failures += _check(is_equal_approx(CombatMath.combo_range_mult_at(partial, 2), 1.0),
		"combo: 안 채운 축은 그 타에서 항등(1.0)")
	# 배율 clamp — 데이터 오타(거대값·음수·NaN)가 판정에 새지 않는가
	failures += _check(is_equal_approx(CombatMath.clamp_combo_mult(9999.0), CombatMath.MAX_COMBO_MULT),
		"combo: 배율 상한 초과 → MAX_COMBO_MULT clamp (데이터 오타 100.0이 100배 데미지가 되지 않게)")
	failures += _check(is_equal_approx(CombatMath.clamp_combo_mult(-2.0), 1.0), "combo: 음수 배율 → 1.0(항등)")
	failures += _check(is_equal_approx(CombatMath.clamp_combo_mult(NAN), 1.0), "combo: NaN 배율 → 1.0(항등)")
	failures += _check(is_equal_approx(CombatMath.combo_range_mult_at(bow, 99), 1.0),
		"combo: 배열 밖 타수 주장(99) → 항등 (인덱스 오염 차단)")
	failures += _check(is_equal_approx(CombatMath.combo_range_mult_at(bow, -5), 1.0),
		"combo: 음수 타수 주장 → 항등")
	# 뜸·간격·창 — 로컬 쿨다운(player)과 호스트 계수(advance_combo)가 같이 지나는 유도식
	failures += _check(is_equal_approx(CombatMath.combo_delay_at(bow, 2), 0.25), "combo: 3타 뜸 = 0.25s")
	failures += _check(is_equal_approx(CombatMath.combo_delay_at(bow, 0), 0.0), "combo: 1타 뜸 없음")
	failures += _check(is_equal_approx(CombatMath.combo_gap_s(ajob, bow, 0), 0.15),
		"combo: 1타 간격 = 직업 쿨다운(0.15)")
	failures += _check(is_equal_approx(CombatMath.combo_gap_s(ajob, bow, 2), 0.40),
		"combo: 3타 간격 = 쿨다운 + 뜸(0.40)")
	# 🔴 뜸도 haste로 짧아진다 — 쿨다운·스윙 창·차지 스텝과 **같은 배율**(§3 haste 계약).
	#   안 곱하면 공속을 올릴수록 리듬이 뜸에 지배돼 궁수에게 공속이 무가치해진다.
	failures += _check(is_equal_approx(CombatMath.combo_gap_s(ajob, bow, 2, 0.25),
			0.40 * CombatMath.haste_scale(0.25)),
		"combo: 뜸에도 haste_scale이 걸린다 ★안 걸리면 공속이 궁수에게 무가치해진다")
	# 🔴 창 > 실제 간격 > 인정 하한 불변식 — 겹치면 "너무 빨라서 리셋"과 "너무 쉬어서 리셋"이 만나
	#   정직한 발사가 **어느 쪽으로도 콤보를 못 잇는** 죽은 구간이 생긴다(3타가 영영 안 나온다).
	failures += _check(CombatMath.combo_window_s(ajob, bow, 2) > CombatMath.combo_gap_s(ajob, bow, 2)
			and CombatMath.combo_gap_s(ajob, bow, 2) > CombatMath.combo_min_gap_s(ajob, bow, 2),
		"combo: 창 > 실제 간격 > 인정 하한 (죽은 구간 없음)")
	# 🔴 인정 하한(combo_min_gap_s)의 유도 — 기본 쿨다운분은 is_fire_rate_ok와 **같은 값**이고,
	#   뜸에서만 LAG_MAX_ONE_WAY_MS(전송이 삼킬 수 있다고 이미 인정한 양)를 깎는다.
	failures += _check(is_equal_approx(CombatMath.combo_min_gap_s(ajob, bow, 2),
			0.15 * CombatMath.FIRE_RATE_SLACK + (0.25 - CombatMath.LAG_MAX_ONE_WAY_MS / 1000.0)),
		"combo: 인정 하한 = 쿨다운×0.9 + (뜸 − 편도지연 상한) = 0.185s")
	failures += _check(is_equal_approx(CombatMath.combo_min_gap_s(ajob, bow, 0),
			0.15 * CombatMath.FIRE_RATE_SLACK),
		"combo: 뜸 없는 타의 인정 하한 = is_fire_rate_ok와 **정확히 같은 값**(두 잣대로 재지 않는다)")
	failures += _check(CombatMath.combo_min_gap_s(ajob, bow, 2) < CombatMath.combo_gap_s(ajob, bow, 2),
		"combo: 인정 하한 < 실제 간격 (정직한 플레이어에게 여유가 실제로 있다)")
	# 🔴 **창의 구조적 하한 — 구르기 한 번보다는 길어야 한다** (2026-07-27 netreview M3).
	#   활은 클릭 1회 = 1발이라 "언제 다시 쏘나"를 아무것도 강제하지 않는다. 창이 구르기(0.25s)보다
	#   짧으면 **한 번만 굴러도 콤보가 반드시 끊겨** 마무리 타가 구조적으로 도달 불가능해진다.
	#   ⚠ 값 자체는 사용자 튜닝 노브(docs/TUNING.md §9)라 등호로 못 박지 않는다 — 취향은 자유롭게 두되
	#     "굴러서 피하면 리듬이 사라지는" 구간만 막는다.
	failures += _check(CombatMath.COMBO_GRACE_S > CombatMath.ROLL_TIME_S,
		"★combo: 창(%.2fs) > 구르기 1회(%.2fs) — 한 번 구르면 마무리 타가 불가능해지는 구간 차단"
			% [CombatMath.COMBO_GRACE_S, CombatMath.ROLL_TIME_S])

	# 전진 규칙 ⑴ 콤보 없는 무기는 항상 0 (법사·구 궁수 = 도입 전과 완전 항등)
	failures += _check(CombatMath.advance_combo(0, 0.15, ajob, plain) == 0,
		"combo: 콤보 없는 무기는 언제 쏴도 0타 (항등 폴백)")
	failures += _check(CombatMath.advance_combo(0, 0.15, ajob, null) == 0, "combo: 무기 null도 0타")
	# ⑵ 정직한 리듬 — 0 → 1 → 2 → 0 순환
	failures += _check(CombatMath.advance_combo(0, 0.15, ajob, bow) == 1, "combo: 1타 뒤 쿨다운(0.15) → 2타")
	failures += _check(CombatMath.advance_combo(1, 0.40, ajob, bow) == 2,
		"combo: 2타 뒤 뜸까지 기다림(0.40) → 마무리 타")
	failures += _check(CombatMath.advance_combo(2, 0.15, ajob, bow) == 0, "combo: 마무리 뒤 다시 1타로 순환")
	# ⑶ 너무 쉬면 처음부터
	failures += _check(CombatMath.advance_combo(0, 5.0, ajob, bow) == 0, "combo: 오래 쉬면(5s) 처음부터")
	failures += _check(CombatMath.advance_combo(1, 0.40 + CombatMath.COMBO_GRACE_S + 0.01, ajob, bow) == 0,
		"combo: 창을 막 넘기면(gap+GRACE 초과) 처음부터")
	failures += _check(CombatMath.advance_combo(1, 0.40 + CombatMath.COMBO_GRACE_S - 0.01, ajob, bow) == 2,
		"combo: 창 안이면 마무리 타 유지 (경계 바로 안)")
	# 🔴 ⑷ 너무 빠르면 처음부터 — **뜸을 안 낸 자는 마무리 타를 못 얻는다**(이게 delay의 강제 수단)
	failures += _check(CombatMath.advance_combo(1, 0.15, ajob, bow) == 0,
		"combo: 뜸을 안 내고 쿨다운만에 쏘면 마무리 타가 아니라 리셋 ★조작 클라의 스팸 차단")
	var min_gap2 := CombatMath.combo_min_gap_s(ajob, bow, 2)
	failures += _check(CombatMath.advance_combo(1, min_gap2, ajob, bow) == 2, "combo: 인정 하한 경계 = 인정")
	failures += _check(CombatMath.advance_combo(1, min_gap2 - 0.01, ajob, bow) == 0,
		"combo: 인정 하한보다 빠르면 리셋")
	# 🔴 **지터 여유 — 이 규약의 존재 이유이자 마진 뮤테이션의 표적.**
	#   호스트는 자기 **수신 시각**의 차로 재므로, 앞 패킷이 더 늦게 도착하면 정직한 0.40s가 짧아 보인다.
	#   그때 마무리 타를 뺏기면 "가끔 강화살이 안 나온다"가 되고 원인이 화면에 안 드러난다.
	#   ★마진을 없애면(인정 하한 = 실제 간격) 아래 세 줄이 빨개진다.
	var honest_gap2 := CombatMath.combo_gap_s(ajob, bow, 2)
	for shrink_ms: int in [60, 120, 200]:
		failures += _check(
			CombatMath.advance_combo(1, honest_gap2 - float(shrink_ms) / 1000.0, ajob, bow) == 2,
			"★지터 여유: 정직한 0.40s가 %dms 짧게 측정돼도 마무리 타 유지" % shrink_ms)
	# 여유의 상한 근거 = LAG_MAX_ONE_WAY_MS(전송이 삼킬 수 있다고 이 프로젝트가 선언한 양) 전부를 준다
	failures += _check(is_equal_approx(honest_gap2 - CombatMath.combo_min_gap_s(ajob, bow, 2),
			CombatMath.LAG_MAX_ONE_WAY_MS / 1000.0 + 0.15 * (1.0 - CombatMath.FIRE_RATE_SLACK)),
		"★지터 여유의 크기 = 편도지연 상한(200ms) + 쿨다운 관용구분(15ms) = 215ms")
	# 🔴 스팸 시뮬 — 쿨다운만 지키며 연사하는 조작 클라는 0↔1만 오가 **마무리 타에 영영 도달 못 한다**.
	#   ⚠ 클라 자기 쿨다운(0.15)이 아니라 **호스트가 허용하는 최속**(is_fire_rate_ok 문턱 = 쿨다운×0.9)으로
	#     민다 — 조작 클라는 자기 쿨다운을 안 지키므로 그게 실제 최악이다.
	var fastest := 0.15 * CombatMath.FIRE_RATE_SLACK
	var spam_idx := 0
	var spam_reached_finish := false
	for _i: int in range(30):
		spam_idx = CombatMath.advance_combo(spam_idx, fastest, ajob, bow)
		if spam_idx == 2:
			spam_reached_finish = true
	failures += _check(not spam_reached_finish,
		"★combo: 호스트 허용 최속(135ms) 스팸 30발 동안 마무리 타 0회 — 마진을 줘도 스팸은 못 닿는다")
	# 🔴 **무기별 전수** — 위 성질은 데이터에 달려 있다. 뜸이 LAG_MAX_ONE_WAY_MS(200ms) 이하로 내려가면
	#   인정 하한이 is_fire_rate_ok 문턱과 같아져 **최속 스팸이 마무리 타를 공짜로 얻는다**(조용한 절벽).
	#   여기서 무기마다 확인해 그 절벽을 시끄럽게 만든다 — 뜸을 낮추는 튜닝은 이 줄을 빨갛게 만들어야 한다.
	var spam_free := ""
	var combo_weapons := 0
	for ef4: String in DirAccess.get_files_at("res://data/equipment"):
		var ebase4 := ef4.trim_suffix(".remap")
		if ebase4.get_extension() != "tres":
			continue
		var ew := load("res://data/equipment/%s" % ebase4) as EquipDef
		if ew == null or CombatMath.combo_len(ew) <= 1:
			continue  # 콤보 없는 무기는 애초에 마무리 타가 없다
		var jw := load("res://data/jobs/%s.tres" % ew.job_id) as JobDef
		if jw == null:
			continue
		combo_weapons += 1
		var last := CombatMath.combo_len(ew) - 1
		var idx := 0
		var fast := jw.attack_cooldown * CombatMath.FIRE_RATE_SLACK
		for _i2: int in range(30):
			idx = CombatMath.advance_combo(idx, fast, jw, ew)
			if idx == last:
				spam_free += "%s " % ew.id
				break
	failures += _check(combo_weapons > 0, "무기 전수: 콤보 무기가 실제로 스캔됐다(스캔 0건 = 침묵 통과 방지)")
	failures += _check(spam_free.is_empty(),
		"★무기 전수: 최속 스팸이 마무리 타에 닿는 무기 없음 (닿는 무기: %s)"
			% ("없음" if spam_free.is_empty() else spam_free))
	# 정직한 리듬 시뮬 — 0.15 / 0.15 / 0.40을 반복하면 3발마다 정확히 한 번 마무리 타
	var honest_idx := 0
	var honest_finishes := 0
	for i2: int in range(30):
		var gap_s := CombatMath.combo_gap_s(ajob, bow, (honest_idx + 1) % 3)
		honest_idx = CombatMath.advance_combo(honest_idx, gap_s, ajob, bow)
		if honest_idx == 2:
			honest_finishes += 1
	failures += _check(honest_finishes == 10,
		"combo: 정직한 리듬 30발 = 마무리 타 10회 ★로컬 쿨다운이 심는 간격이 호스트 게이트를 항상 통과한다")

	# 🔴 신뢰 경계 — authoritative_combo. **판정에 쓰는 타수는 이 함수 하나**다.
	#   ★뮤테이션 표적: 이 함수를 `return claimed`(클라 주장 그대로)로 되돌리면 아래 두 줄이 빨개진다.
	failures += _check(CombatMath.authoritative_combo(2, 1, 0.15, ajob, bow) == 0,
		"★신뢰 경계: 쿨다운만에 쏘며 '나 마무리 타'라고 주장 → 0 (주장 그대로 믿으면 여기가 빨개진다)")
	failures += _check(CombatMath.authoritative_combo(2, 0, 0.15, ajob, bow) == 1,
		"★신뢰 경계: 호스트가 센 값이 1인데 2를 주장 → 1 (호스트 계수가 상한)")
	failures += _check(CombatMath.authoritative_combo(99, 1, 0.40, ajob, bow) == 2,
		"신뢰 경계: 범위 밖 주장(99)도 호스트 계수(2)로 잘린다")
	failures += _check(CombatMath.authoritative_combo(-3, 1, 0.40, ajob, bow) == 0,
		"신뢰 경계: 음수 주장은 clamp 후 min → 0 (자기 손해, 무해)")
	# 🔴 min 규약 — 주장이 호스트 계수보다 **작으면 주장을 따른다**(판정 ≤ 표시).
	#   표시는 주장값을 그리므로, 이게 없으면 "화면엔 짧은 화살인데 판정은 300px 밖 적을 죽이는" 방향이 열린다.
	failures += _check(CombatMath.authoritative_combo(0, 1, 0.40, ajob, bow) == 0,
		"★판정 ≤ 표시: 호스트는 2로 셌지만 주장이 0이면 0 (안 그리고 맞히는 방향 차단)")
	failures += _check(CombatMath.authoritative_combo(3, 1, 0.40, ajob, plain) == 0,
		"신뢰 경계: 콤보 없는 무기에 실린 타수 주장은 전부 0 (지팡이가 강화탄을 얻지 못한다)")
	# 🔴 **"거부 신호가 없다"가 계약이다** — 어떤 입력에도 유효한 타수만 돌아온다(음수 sentinel 없음).
	#   ⚠ 이 함수가 -1 같은 값을 돌려주게 바꾸면 호출부(combat_authority)가 그걸 "발사 거부"로 쓰기
	#     쉬워지는데, 그러면 창 경계 지터에서 **정당한 화살이 조용히 사라진다**. 최악은 "이번 타는
	#     평타"여야 한다. 실제 "발사를 안 떨군다"는 호출부 성질이라 여기선 반환 계약만 못박는다.
	var sentinel_ok := true
	for claim: int in [-999, -1, 0, 1, 2, 3, 999]:
		for el: float in [-1.0, 0.0, 0.001, 0.185, 0.40, 5.0, INF, NAN]:
			for prev: int in [-7, 0, 2, 42]:
				var r := CombatMath.authoritative_combo(claim, prev, el, ajob, bow)
				if r < 0 or r >= CombatMath.combo_len(bow):
					sentinel_ok = false
	failures += _check(sentinel_ok,
		"★신뢰 경계: 어떤 주장·간격·이전 타수에도 반환은 항상 [0, len) — 거부 sentinel이 없다")

	# 데미지 배율 — confirm_damage **안쪽**에서 곱해져 반올림이 여전히 1회인가
	var no_stats: Dictionary = {}
	var d_plain := int(CombatMath.confirm_damage(ajob, 3, no_stats, 0, 1.0).get("damage", -1))
	var d_combo := int(CombatMath.confirm_damage(ajob, 3, no_stats, 0, 1.0, 2.5).get("damage", -1))
	failures += _check(d_plain == 4, "combo 데미지: 기준 = 직업1 + 장비3 = 4")
	failures += _check(int(CombatMath.confirm_damage(ajob, 3, no_stats, 0, 1.0, 1.0).get("damage", -1)) == d_plain,
		"combo 데미지: 배율 1.0 = 도입 전과 완전 항등")
	failures += _check(d_combo == 10, "combo 데미지: ×2.5 → 10 ★적용 지점 검출(안 곱하면 4로 남는다)")
	# 🔴 반올림 1회 — **이중 반올림이면 값이 실제로 갈라지는 케이스**로 확인한다(안 그러면 검출력 0).
	#   base 7(직업1+장비6) × 콤보 1.5 × 치명 1.5(crit_dmg 0):
	#     안쪽 한 번   = round(7 × 1.5 × 1.5) = round(15.75) = 16  ← 계약
	#     밖에서 곱함  = round(round(7 × 1.5) × 1.5) = round(11 × 1.5) = round(16.5) = 17  ← 빨개져야 한다
	var crit_stats: Dictionary = {"crit": 1.0, "crit_dmg": 0.0}
	failures += _check(int(CombatMath.confirm_damage(ajob, 6, crit_stats, 0, 0.0, 1.5).get("damage", -1)) == 16,
		"★combo 데미지: 콤보 × 치명이 한 식에서 곱해진다(반올림 1회 — 밖에서 곱하면 17)")
	failures += _check(int(CombatMath.confirm_damage(ajob, 3, no_stats, 0, 1.0, 9999.0).get("damage", -1))
			== int(round(4.0 * CombatMath.MAX_COMBO_MULT)),
		"combo 데미지: 상한 밖 배율도 MAX_COMBO_MULT를 지난다(데이터 오타 방어)")

	# 🔴 절삭 불변식 전수 — 콤보 사거리 배율까지 포함해서 정당한 무기가 조용히 잘리지 않는가.
	#   예산 = base × max(combo_range_mult) ≤ MAX_ARROW_RANGE / (1 + TRAIT_MAX["proj_range"]) = 320.
	#   ⚠ 넘으면 clamp_arrow_range가 **에러 없이** 사거리를 깎아 "보이는 곳 ≠ 맞는 곳"이 된다.
	var combo_range_ok := true
	var worst_id := ""
	var worst_val := 0.0
	for ef3: String in DirAccess.get_files_at("res://data/equipment"):
		var ebase3 := ef3.trim_suffix(".remap")
		if ebase3.get_extension() != "tres":
			continue
		var e3 := load("res://data/equipment/%s" % ebase3) as EquipDef
		if e3 == null or (e3.motion_type != "shoot" and e3.motion_type != "charge"):
			continue
		for ci: int in range(CombatMath.combo_len(e3)):
			var reach_px := CombatMath.effective_projectile_range(
				e3.arrow_range, pr_max, CombatMath.combo_range_mult_at(e3, ci))
			if reach_px > worst_val:
				worst_val = reach_px
				worst_id = "%s[%d]" % [e3.id, ci]
			if reach_px > CombatMath.MAX_ARROW_RANGE:
				combo_range_ok = false
	failures += _check(combo_range_ok,
		"★콤보 절삭 불변식 전수: 모든 원거리 무기 × 모든 타수 × proj_range 상한 ≤ 480 (최대 %s = %.1f)"
			% [worst_id, worst_val])

	# 🔴 **비감소(단조) 불변식 전수** — `min` 규약이 실제로 보장해야 하는 것은 **"판정 거리 ≤ 표시 거리"**인데,
	#   `authoritative_combo`의 min이 직접 주는 것은 **"판정 index ≤ 표시 index"** 뿐이다. 둘을 잇는
	#   `index → 배율` 사상이 비감소여야 부등호가 실제로 넘어간다.
	#   ⚠ 뒤집힌 배열(`[2,1,1]` = "첫 발이 강한 활")을 .tres 한 장으로 넣으면 min이 오히려
	#     **판정 300px / 표시 150px**(화면에 없는데 맞는다)를 만든다 — 규약이 금지한 바로 그 방향이고
	#     다른 모든 단정은 그린이다. 보스 콘 계약이 "각도"만 적어 형태가 갈라졌던 것과 같은 실패 형태.
	var mono_bad := ""
	for ef5: String in DirAccess.get_files_at("res://data/equipment"):
		var ebase5 := ef5.trim_suffix(".remap")
		if ebase5.get_extension() != "tres":
			continue
		var e5 := load("res://data/equipment/%s" % ebase5) as EquipDef
		if e5 == null:
			continue
		for ci2: int in range(1, CombatMath.combo_len(e5)):
			if CombatMath.combo_range_mult_at(e5, ci2) < CombatMath.combo_range_mult_at(e5, ci2 - 1):
				mono_bad += "%s.range[%d] " % [e5.id, ci2]
			if CombatMath.combo_damage_mult_at(e5, ci2) < CombatMath.combo_damage_mult_at(e5, ci2 - 1):
				mono_bad += "%s.damage[%d] " % [e5.id, ci2]
	failures += _check(mono_bad.is_empty(),
		"★콤보 배율 비감소 전수: 뒤 타가 앞 타보다 작은 무기 없음 — 뒤집히면 '판정 > 표시'가 된다 (위반: %s)"
			% ("없음" if mono_bad.is_empty() else mono_bad))
	# 합성 데이터로 **검출력 자체**를 확인한다 — 위 전수는 현 데이터가 통과라 "루프가 도는가"를 못 보여준다.
	var flipped := EquipDef.new()
	flipped.combo_range_mult = PackedFloat32Array([2.0, 1.0, 1.0])
	var flip_caught := false
	for ci3: int in range(1, CombatMath.combo_len(flipped)):
		if CombatMath.combo_range_mult_at(flipped, ci3) < CombatMath.combo_range_mult_at(flipped, ci3 - 1):
			flip_caught = true
	failures += _check(flip_caught, "★비감소 검사의 검출력: 뒤집힌 배열([2,1,1])을 실제로 잡는다")
	# 🔴 **데미지 축의 검출력도 따로 본다** — 위 전수는 두 축을 같이 훑지만 검출력 확인은 사거리 축만
	#   썼다. v2.2에서 **근접이 데미지 축만 채우므로**(사거리 배율 금지, 아래 ⑴) 이 축이 안 돌면
	#   "뒤집힌 근접 배열"이 통째로 새어 나간다 — 그때 `min` 규약이 판정 > 표시를 만든다.
	var flipped_dmg := EquipDef.new()
	flipped_dmg.combo_damage_mult = PackedFloat32Array([2.0, 1.0])
	var flip_dmg_caught := false
	for ci6: int in range(1, CombatMath.combo_len(flipped_dmg)):
		if CombatMath.combo_damage_mult_at(flipped_dmg, ci6) \
				< CombatMath.combo_damage_mult_at(flipped_dmg, ci6 - 1):
			flip_dmg_caught = true
	failures += _check(flip_dmg_caught, "★비감소 검사의 검출력(데미지 축): 뒤집힌 배열([2,1])을 실제로 잡는다")

	# ══ 🔴 스윙 방향 패리티 (v2.2) — 옛 `index == 1` 규칙과 갈리는 곳은 **index 3 하나뿐**이다 ══
	# 옛 규칙(절대 위치)과 새 규칙(패리티)의 진리값: 0 → 둘 다 정방향 · 1 → 둘 다 반전 · 2 → 둘 다 정방향 ·
	#   **3 → 옛 정방향 / 새 반전.** 즉 **창(4타)의 마지막 타만이 판별자**이고, 2타·3타 무기로는 이 회귀를
	#   영원히 못 잡는다. 이 단정이 없으면 규칙을 되돌리는 뮤테이션에서 스위트가 **9/9 초록**이다(실측).
	# ⚠ 그래서 이 술어는 `player.gd`가 아니라 `CombatMath`에 산다 — 씬 글루는 `-s` preload가 안 돼
	#   테스트가 겨눌 수 없다(리뷰 J-1·J-2와 같은 처방).
	failures += _check(not CombatMath.is_combo_swing_reversed(0), "패리티: 0타 = 정방향")
	failures += _check(CombatMath.is_combo_swing_reversed(1), "패리티: 1타 = 반전")
	failures += _check(not CombatMath.is_combo_swing_reversed(2), "패리티: 2타 = 정방향")
	failures += _check(CombatMath.is_combo_swing_reversed(3),
		"★패리티 유일 판별자: 3타 = 반전 (옛 `index == 1` 규칙이면 정방향이 되어 창 4타 중 둘이 같은 궤적)")

	# ══ 🔴 근접 콤보 데이터 전수 (v2.2 2026-07-29) — 넷 다 **에러 없이 조용히 깨지는** 부류다 ══
	# ✅ **예산은 이제 코드가 쥔다 — `CombatMath.COMBO_CYCLE_DPS_MAX`** (2026-07-29 리드 반영).
	#   전엔 GDD §6의 1.3을 여기 **복제**했고, 그러면 예산을 고칠 때 문서와 테스트가 갈라진다
	#   (하네스의 지배 고장 모드). 이제 숫자는 한 곳에만 산다 — 이 줄에 상수를 다시 쓰지 마라.
	const COMBO_DPS_BUDGET := CombatMath.COMBO_CYCLE_DPS_MAX
	var melee_has_range := ""     # ⑴ 근접에 combo_range_mult가 실렸는가
	var combo_raw_ok := true      # ⑵ 타별 배율이 조용히 clamp되지 않았는가(= 함수가 데이터를 실제로 읽는가)
	var finish_show_ok := true    # ⑶ 마무리 타: 판정 반각 < 표시 반각
	var finish_wider_ok := true   #    + 마무리 각 ≥ 기본 각 (로컬 ≤ 호스트가 성립하는 조건)
	var finish_clamp_ok := true   #    + 적은 마무리 각이 그대로 쓰이는가 (clamped == raw)
	var dps_bad := ""             # ⑷ 사이클 DPS 비 ≤ 예산
	var dps_worst := 0.0
	var dps_worst_id := ""
	var dash_worst_ratio := 0.0   # ⑸ 대시 속도 ÷ 원격 위치 clamp 하한 (netreview I-1)
	var dash_worst_id := ""
	var dash_clamp_ok := true     # ⑹ combo_dash_dist의 상한 clamp가 살아 있는가 (리뷰 I-1)
	var grace_ok := true          # ⑺ combo_grace_s가 무기 값을 읽는가 (리뷰 I-1)
	var grace_roll_bad := ""      #    + 구르기 1회보다 긴가 (리뷰 I-2)
	var clamp_probe_done := false
	var melee_combo_seen := 0
	var combo_scanned := 0
	for cf: String in DirAccess.get_files_at("res://data/equipment"):
		var cbase := cf.trim_suffix(".remap")
		if cbase.get_extension() != "tres":
			continue
		var cw := load("res://data/equipment/%s" % cbase) as EquipDef
		if cw == null or cw.slot() != EquipDef.SLOT_WEAPON:
			continue
		combo_scanned += 1
		# ⑵ 🔴 **`combo_damage_mult_at`이 데이터를 실제로 읽는가 + 조용히 clamp되지 않았는가.**
		#    ⓐ 이 함수를 상수 1.0으로 못 박는 뮤테이션은 다른 어떤 단정도 못 잡는다(아래 DPS 비는
		#      1.0 밑으로 내려가 예산을 통과하고, 비감소도 통과한다) — 여기가 유일한 표적이다.
		#    ⓑ `MAX_COMBO_MULT` 초과값(4.5)은 clamp가 **조용히** 4.0으로 떨구므로, 적은 값이 안 쓰인
		#      것을 아무도 모른다. 상한을 복제하지 않고 `clamped == raw`로 본다(J-1 관용구).
		for ri: int in range(cw.combo_damage_mult.size()):
			if not is_equal_approx(CombatMath.combo_damage_mult_at(cw, ri),
					cw.combo_damage_mult[ri]):
				combo_raw_ok = false
		if not CombatMath.is_projectile_weapon(cw):
			melee_combo_seen += 1
			# ⑴ 🔴 **근접은 `combo_range_mult`를 쓰지 않는다.** 근접 사거리는 `effective_attack_range`가
			#    정하고 그 함수엔 콤보 인자가 **아예 없다**. 그런데 `combo_len`이 세 배열의 **최대 크기**라,
			#    실수로 적으면 **사거리는 안 바뀌고 타수와 마무리 타 위치만 조용히 옮겨간다**(도끼가
			#    3타가 되고 마무리가 2타째에서 사라진다). `MAX_MELEE_RANGE`·「폴백 창」 트립와이어
			#    **어느 것도 이 축을 안 본다.**
			#    ⚠ 근접의 기준은 `is_projectile_weapon`의 부정이다(호스트 근접 거부 게이트와 **같은
			#      함수**) — `motion_type == "swing"`으로 좁히면 찌르기(창)가 말없이 빠진다.
			if cw.combo_range_mult.size() > 0:
				melee_has_range += "%s " % cw.id
			# ⑸ 🔴 **대시 속도 ≤ 원격 위치 clamp 하한** (netreview I-1). 넘으면 정당한 대시가 원격에서
			#    깎여 외삽이 과소평가되고 **"피했는데 맞았다"가 부분 재발**한다(2026-07-24에 고친 버그).
			#    유도는 `MAX_COMBO_DASH` 주석이 정본이고, 이 단정은 **그 유도의 입력이 바뀌는 것**을 잡는다:
			#    `LEVEL_STAT_MAX["haste"]` 상향 · `ROLL_SPEED_MULT` 하향 · `move_speed`가 더 낮은 직업이
			#    대시 무기 착용 · 구간(`swing_time × (windup+strike)`)이 더 짧은 대시 무기 추가 — 넷 다
			#    코드·데이터 변경이라 여기서 빨개진다. 상한 숫자를 복제하지 않고 **비율로** 잰다(J-1 관용구).
			#    ⚠ 분모가 `effective_roll_speed(..., 0.0)`인 것은 **특성 0인 최악**이 clamp 하한이기 때문이다
			#      (`roll_dist`가 붙으면 상한이 올라가 여유가 늘어난다 — 관대한 쪽으로 틀리는 것이 안전하다).
			var dash_px := CombatMath.combo_dash_dist(cw)
			if dash_px > 0.0:
				# 🔴 **착용 가능한 직업 중 `move_speed`가 가장 낮은 것**으로 잰다 — clamp 하한이 그것이다.
				#    ⚠ 귀속 무기는 그 직업 하나지만 **범용 무기(`job_id`가 빈)는 전 직업이 들 수 있다**
				#      (법사 90 < 전사 100). 그 갈래를 `job_id`로만 리졸브해 skip하면 반례가 조용히
				#      통과한다(리뷰 I-3): `combo_dash 20` + `swing_time 0.2` + 구간합 0.5인 범용 무기는
				#      300px/s인데 법사 clamp는 234라 66px/s가 깎여 외삽이 과소평가된다.
				var slowest := 0.0
				for djf: String in DirAccess.get_files_at("res://data/jobs"):
					var djb := djf.trim_suffix(".remap")
					if djb.get_extension() != "tres":
						continue
					var djd := load("res://data/jobs/%s" % djb) as JobDef
					if djd == null or (not cw.job_id.is_empty() and cw.job_id != djd.id):
						continue
					if slowest <= 0.0 or djd.move_speed < slowest:
						slowest = djd.move_speed
				if slowest > 0.0:
					var dph := CombatMath.motion_phases(cw)
					var t_min: float = cw.swing_time * (dph.x + dph.y) \
						* CombatMath.haste_scale(float(CombatMath.LEVEL_STAT_MAX.get("haste", 0.0)))
					var dratio := (dash_px / maxf(t_min, 0.0001)) \
						/ maxf(CombatMath.effective_roll_speed(slowest, 0.0), 0.0001)
					if dratio > dash_worst_ratio:
						dash_worst_ratio = dratio
						dash_worst_id = cw.id
			# 🔴 **`combo_dash_dist`의 상한 clamp가 살아 있는가** (리뷰 I-1 — 검출력이 **정확히 0**이었다).
			#    데이터 20.0이 `MAX_COMBO_DASH` 20.0에 **딱 붙어 있어** `minf`를 지워도 어떤 단정도 안
			#    깨진다. 그러면 다음 사람이 25를 적었을 때 조용히 절삭된다. 합성 초과값으로 확인한다
			#    (⑶의 `over_arc` 관용구 그대로 — 상한 숫자를 테스트에 복제하지 않는다).
			if not clamp_probe_done:
				clamp_probe_done = true
				var probe := EquipDef.new()
				probe.combo_dash = CombatMath.MAX_COMBO_DASH * 1.5
				dash_clamp_ok = is_equal_approx(
					CombatMath.combo_dash_dist(probe), CombatMath.MAX_COMBO_DASH)
				probe.combo_grace = 0.0
				grace_ok = is_equal_approx(CombatMath.combo_grace_s(probe), CombatMath.COMBO_GRACE_S)
			# 🔴 **`combo_grace_s`가 무기 값을 실제로 읽는가 + 구르기 1회보다 긴가** (리뷰 I-1·I-2).
			#    ⑴ 상수 0.8로 못 박아도 스위트가 초록이었다 — 창을 쓰는 단정이 전부 활(값 미기재 = 0.8
			#      폴백)만 넘겼기 때문이다. 깨지면 근접 콤보가 안 끊겨 **마무리 타가 상시화**된다(예산 잠식).
			#    ⑵ `ROLL_TIME_S`보다 짧아지면 **한 번만 굴러도 콤보가 반드시 끊겨** 마무리 타에 영영 못
			#      닿는다. 기존 단정은 상수 0.8만 봐서 근접 0.4(여유 0.15s)를 안 봤고, TUNING §14 D-4가
			#      "너무 쉽게 유지되면 내려라"로 안내하므로 내려질 것이 **예정돼** 있다.
			var raw_grace: float = cw.combo_grace
			var want_grace: float = raw_grace if raw_grace > 0.0 else CombatMath.COMBO_GRACE_S
			if not is_equal_approx(CombatMath.combo_grace_s(cw), want_grace):
				grace_ok = false
			if CombatMath.combo_grace_s(cw) <= CombatMath.ROLL_TIME_S:
				grace_roll_bad += "%s " % cw.id
			# ⑶ 🔴 **마무리 타의 판정 각 < 표시 각** — 표시 = 판정이 되면 *"판정 안인데 궤적이 안 지나간
			#    자리"* 를 눈으로 검사할 수단이 사라지고, 그것이 궤적 결손(TUNING §13 A-2)의 **유일한
			#    관측 경로**다. 여유는 `COMBO_FINISH_SHOW_MARGIN`이 코드로 쥐므로 부호가 구조로 고정되지만,
			#    `swing_arc`가 포화(≥ PI−EPS)면 넓힐 곳이 없어 등호가 되어 그 경로가 죽는다 → 여기서 잡는다.
			if CombatMath.melee_show_half_angle(cw, true) <= CombatMath.melee_half_angle(cw, true):
				finish_show_ok = false
			# 🔴 **마무리 각 ≥ 기본 각** — 「로컬 ≤ 호스트」가 콤보 축으로 넘어가는 **필요조건**이다.
			#    호스트는 `min(주장, 자기 계수)`라 확정 타수 ≤ 로컬 주장 타수인데, 마무리를 기본보다
			#    ⚠ **논거를 2026-07-29에 정정했다 — 전엔 부호를 거꾸로 적어 뒀다**(netreview C-1).
			#    사실관계: `finish < base`면 로컬(마무리·좁음) ⊆ 호스트(평타·넓음)라 **안전**하고,
			#    `finish ≥ base`가 오히려 그 부호를 깬다 — 그래서 C-1은 각을 **주장 타수**로 정렬해
			#    닫았다(`combat_authority`의 `_melee_claim`). 즉 이 단정이 지키는 것은 「로컬 ≤ 호스트」가
			#    아니라 **기획 요구**(GDD §6: 마무리는 더 넓게 친다)이고, 어기면 광역이 조용히 사라진다.
			#    ⚠ 옛 논거를 근거로 이 부등호를 **뒤집지 마라** — 뒤집으면 마무리가 평타보다 좁아진다.
			#    🔴🔴 **이 단정은 `motion_type == "thrust"`에서 공허하다 — 초록불을 근거로 쓰지 마라.**
			#      반각 비교가 「표시 ⊇ 판정」(집합 포함)과 동치인 것은 **양쪽으로 훑는 모션에서만**이다.
			#      찌르기는 `_swing_to = 0`이라 각 창이 조준선 한쪽뿐인데 판정은 양쪽 ±half_angle이라,
			#      반각이 아무리 넓어도 **반대쪽 절반은 안 그려진 채 판정에 든다**(`player._tick_swing_motion`
			#      주석이 실측과 함께 정본). 창에 `combo_finish_arc`를 주지 않는 이유가 이것이다.
			if CombatMath.melee_half_angle(cw, true) < CombatMath.melee_half_angle(cw, false) - 0.000001:
				finish_wider_ok = false
			# 🔴 **적은 마무리 각이 그대로 쓰이는가**(clamped == raw). 상한
			#    (`MELEE_FULL_ARC − EPS − MARGIN` = 2.98)을 넘겨 적으면 **조용히 절삭**된다.
			if cw.combo_finish_arc > 0.0 \
					and not is_equal_approx(CombatMath.melee_half_angle(cw, true), cw.combo_finish_arc):
				finish_clamp_ok = false
		# ⑷ 🔴 **사이클 DPS 비 ≤ 예산** — GDD §6을 코드가 지킨다. 한 사이클(전 타수)을 돌리는 데 드는
		#    시간과 그동안의 데미지를 "콤보 없이 1타만 반복"과 비교한다:
		#      사이클 = Σ(쿨다운 + 뜸[i]) · 데미지 = Σ 배율[i] · 비 = (Σ데미지 ÷ 사이클) ÷ (1 ÷ 쿨다운)
		#    ⚠ **haste 불변이다** — 사이클과 기준선에 `haste_scale`이 똑같이 곱해져 약분된다(§3 haste
		#      계약이 뜸에도 같은 배율을 곱하는 덕이다). 그래서 haste 전수를 돌리지 않는다.
		#    ⚠ 단위 혼동 주의(GDD §6 🔴): 도끼의 **타별** 배율 2.2는 이 1.3과 비교할 값이 아니다
		#      (한 사이클로 환산하면 1.219다).
		if CombatMath.combo_len(cw) <= 1:
			continue
		for jf9: String in DirAccess.get_files_at("res://data/jobs"):
			var jbase9 := jf9.trim_suffix(".remap")
			if jbase9.get_extension() != "tres":
				continue
			var j9 := load("res://data/jobs/%s" % jbase9) as JobDef
			if j9 == null or j9.attack_cooldown <= 0.0:
				continue
			if not cw.job_id.is_empty() and cw.job_id != j9.id:
				continue  # 직업 귀속 — 실제로 착용 가능한 조합만 (스윙 창 전수와 같은 규약)
			var cyc_dmg := 0.0
			var cyc_time := 0.0
			for ki: int in range(CombatMath.combo_len(cw)):
				cyc_dmg += CombatMath.combo_damage_mult_at(cw, ki)
				cyc_time += j9.attack_cooldown + CombatMath.combo_delay_at(cw, ki)
			var ratio := (cyc_dmg / cyc_time) * j9.attack_cooldown
			if ratio > dps_worst:
				dps_worst = ratio
				dps_worst_id = "%s@%s" % [cw.id, j9.id]
			if ratio > COMBO_DPS_BUDGET:
				dps_bad += "%s@%s(%.3f) " % [cw.id, j9.id, ratio]
	failures += _check(combo_scanned > 0 and melee_combo_seen > 0,
		"근접 콤보 전수: 무기가 실제로 스캔됐다 (전체 %d · 근접 %d — 0건 = 침묵 통과)"
			% [combo_scanned, melee_combo_seen])
	failures += _check(melee_has_range.is_empty(),
		"★근접 콤보 전수 ⑴: 근접 무기에 combo_range_mult 없음 — 실리면 사거리는 그대로인데 타수만 옮겨간다 (위반: %s)"
			% ("없음" if melee_has_range.is_empty() else melee_has_range))
	failures += _check(dash_worst_ratio <= 1.0,
		"★대시 속도 전수: 최대 haste에서도 원격 위치 clamp 하한 이내 (최악 %s = %.1f%%)"
			% ["없음" if dash_worst_id.is_empty() else dash_worst_id, dash_worst_ratio * 100.0])
	# 🔴 **0건 침묵 통과 가드** (리뷰 A-2). 위 단정은 `combo_dash > 0`인 무기가 **하나도 없으면**
	#   `0 ≤ 1.0`으로 조용히 통과한다 — 즉 누가 `combo_dash`를 지우면 트립와이어가 **신호 없이 죽는다.**
	#   ⚠ 가상이 아니다: 방금 `combo_finish_arc`를 두 무기에서 지웠고(리뷰 I-4·I-5), 같은 일이
	#     `combo_dash`에 일어나면 위 줄은 계속 초록이다. `combo_scanned > 0`과 같은 관용구다.
	failures += _check(not dash_worst_id.is_empty(),
		"★대시 무기가 최소 1종 존재한다 (0건이면 위 속도 단정이 침묵 통과한다)")
	failures += _check(dash_clamp_ok,
		"★대시 거리 상한 clamp가 살아 있다 (데이터가 상한에 딱 붙어 있어 합성값으로만 잡힌다)")
	failures += _check(grace_ok,
		"★콤보 창이 무기 값을 실제로 읽는다 (0 = COMBO_GRACE_S 항등 폴백)")
	failures += _check(grace_roll_bad.is_empty(),
		"★콤보 창 > 구르기 1회(ROLL_TIME_S) — 한 번 굴러도 마무리 타에 닿을 수 있다: %s" % grace_roll_bad)
	failures += _check(combo_raw_ok,
		"★근접 콤보 전수 ⑵: combo_damage_mult_at == .tres 원본 전수 (조용한 clamp·상수화 검출)")
	failures += _check(finish_show_ok and finish_wider_ok and finish_clamp_ok,
		"★마무리 각 전수 ⑶: 판정 < 표시 · 마무리 ≥ 기본(로컬≤호스트) · 적은 각이 절삭 안 됨")
	failures += _check(dps_bad.is_empty(),
		"★콤보 예산 전수 ⑷: 사이클 DPS 비 ≤ %.2f (GDD §6) — 최대 %s = %.3f (위반: %s)"
			% [COMBO_DPS_BUDGET, dps_worst_id, dps_worst,
				"없음" if dps_bad.is_empty() else dps_bad])
	# ★검출력 — 위 넷은 현 데이터가 통과라 "루프가 실제로 도는가"를 못 보여준다. 합성으로 확인한다.
	var over_arc := EquipDef.new()
	over_arc.swing_arc = 2.8
	over_arc.combo_finish_arc = 10.0  # 상한(2.98)을 훨씬 넘겨 적었다 = 조용한 절삭 대상
	var arc_cap := CombatMath.MELEE_FULL_ARC - CombatMath.MELEE_FULL_ARC_EPS \
		- CombatMath.COMBO_FINISH_SHOW_MARGIN
	failures += _check(is_equal_approx(CombatMath.melee_half_angle(over_arc, true), arc_cap),
		"★마무리 각 검출력: 상한 초과(10.0) → clamp — 🔴 clamp를 지우는 뮤테이션이 여기서 잡힌다")
	# 🔴 **상한 초과 데이터에서도 판정은 전방위가 되지 않는다** — 이게 절대값 계약의 핵심이다(옛 균일
	#   배율 1.25는 도끼 문턱 1.122를 넘어 마무리 타마다 "등 뒤도 맞는다"를 되살렸다).
	#   ⚠ 표시는 그 상한에서 정확히 `PI − EPS`에 **닿는다**(= span 2π − 0.02, 궤적이 한 바퀴를 안 넘는
	#     최대치). 판정에서 여유를 **미리 뺀** 이유가 그것이라, 여기는 `<`가 아니라 `<=`가 계약이다.
	failures += _check(CombatMath.melee_half_angle(over_arc, true)
			< CombatMath.MELEE_FULL_ARC - CombatMath.MELEE_FULL_ARC_EPS
			and CombatMath.melee_show_half_angle(over_arc, true)
			<= CombatMath.MELEE_FULL_ARC - CombatMath.MELEE_FULL_ARC_EPS + 0.000001,
		"★마무리 각 검출력: 판정은 전방위 문턱 밖 · 표시는 문턱까지만 — 여유 자리가 남는다")
	failures += _check(not is_equal_approx(
			CombatMath.melee_half_angle(over_arc, true), over_arc.combo_finish_arc),
		"★마무리 각 검출력: 위 ⑶의 `clamped == raw`가 절삭된 데이터를 실제로 잡는다")
	var fat_combo := EquipDef.new()
	fat_combo.combo_damage_mult = PackedFloat32Array([1.0, 1.0, 4.0])  # 뜸 없이 4배 = 예산 밖
	var fat_dmg := 0.0
	var fat_time := 0.0
	for fi: int in range(CombatMath.combo_len(fat_combo)):
		fat_dmg += CombatMath.combo_damage_mult_at(fat_combo, fi)
		fat_time += 0.4 + CombatMath.combo_delay_at(fat_combo, fi)
	failures += _check((fat_dmg / fat_time) * 0.4 > COMBO_DPS_BUDGET,
		"★콤보 예산 검출력: 뜸 없는 4배 마무리(비 %.2f)는 예산 밖으로 잡힌다" % ((fat_dmg / fat_time) * 0.4))
	var bad_range := EquipDef.new()
	bad_range.motion_type = "thrust"
	bad_range.combo_range_mult = PackedFloat32Array([1.0, 2.0])
	failures += _check(not CombatMath.is_projectile_weapon(bad_range)
			and bad_range.combo_range_mult.size() > 0,
		"★근접 사거리 배율 검출력: 찌르기 + combo_range_mult 조합이 ⑴의 조건에 실제로 걸린다")

	# --- 발사형 판정 (호스트 G_SHOOT 신뢰 경계, 2026-07-27 netreview M4) ---
	# 🔴 근접 무기가 이 경로에 새면 `arrow_range` 기본값 360짜리 권한 화살이 전사 공격력으로 확정된다.
	var gsword := EquipDef.new()
	gsword.motion_type = "swing"
	var thrust := EquipDef.new()
	thrust.motion_type = "thrust"  # 예약 모션 — 아직 발사형이 아니다
	failures += _check(CombatMath.is_projectile_weapon(bow), "발사형: shoot = 발사 가능")
	# ⚠ **charge 갈래는 합성으로 겨눈다** — 실제 charge 무기(지팡이)는 궁수·법사 폐기와 함께
	#   2026-08-01에 삭제됐다. `is_projectile_weapon`은 `motion_type` 문자열만 보므로 합성으로 충분하고,
	#   이렇게 안 하면 charge 갈래가 통째로 안 재진다(라벨만 남고 커버리지가 조용히 사라진다).
	var charger := EquipDef.new()
	charger.motion_type = "charge"
	charger.arrow_range = 150.0
	failures += _check(CombatMath.is_projectile_weapon(charger),
		"발사형: charge(합성) = 발사 가능")
	failures += _check(not CombatMath.is_projectile_weapon(gsword),
		"★발사형: swing(대검) = 발사 거부 — 새면 전사 공격력짜리 권한 화살이 확정된다")
	failures += _check(not CombatMath.is_projectile_weapon(thrust), "★발사형: thrust(예약) = 발사 거부")
	failures += _check(not CombatMath.is_projectile_weapon(null),
		"발사형: null = false (⚠ 호출부는 null을 **거부하지 않는다** — G_STATS 미도착 정상 창)")
	# 🔴 **두 번째 방어층 — `EquipDef.arrow_range` 기본값이 안전한가** (2026-07-27 netreview M4 후속).
	#   위 가드는 씬 글루(combat_authority)에 있어 헤드리스가 **겨눌 수 없다** — 지워도 스위트가 초록이다.
	#   그래서 "가드가 뚫려도 위협이 아닌" 층을 데이터 쪽에 세운다: 근접 무기 `.tres`엔 이 필드가 없으니
	#   기본값이 곧 "근접 무기가 쏠 경우의 사거리"다. 전에는 360이라 궁수의 정당한 마무리 타보다 멀었다.
	var melee_range := 0.0     # 근접 무기가 실제로 갖는 사거리(= 기본값)
	var longest_real := 0.0    # 정당한 원거리 무기의 최장 도달
	var missing_range := ""    # 발사형인데 사거리를 명시 안 한 무기
	for ef6: String in DirAccess.get_files_at("res://data/equipment"):
		var ebase6 := ef6.trim_suffix(".remap")
		if ebase6.get_extension() != "tres":
			continue
		var e6 := load("res://data/equipment/%s" % ebase6) as EquipDef
		if e6 == null:
			continue
		if CombatMath.is_projectile_weapon(e6):
			# 🔴 발사형은 **반드시 명시**해야 한다 — 빠뜨리면 기본값 0 → clamp가 MIN(40)으로 떨어뜨려
			#   40px짜리 화살이 된다. ⚠ 실패 방향이 안전하다: "조용히 멀어짐"이 아니라 "눈에 띄게 짧아짐".
			if e6.arrow_range <= 0.0:
				missing_range += "%s " % e6.id
			for ci4: int in range(CombatMath.combo_len(e6)):
				longest_real = maxf(longest_real,
					e6.arrow_range * CombatMath.combo_range_mult_at(e6, ci4))
		else:
			melee_range = maxf(melee_range, e6.arrow_range)
	failures += _check(missing_range.is_empty(),
		"★발사형 무기는 arrow_range를 명시했다 — 빠뜨리면 40px 화살이 된다 (누락: %s)"
			% ("없음" if missing_range.is_empty() else missing_range))
	failures += _check(is_equal_approx(melee_range, 0.0),
		"★근접 무기의 arrow_range = 0 (기본값) — 사칭 화살의 사거리 원천을 없앤 두 번째 방어층")
	# 가드를 뚫고 근접 무기가 발사 경로에 새더라도 위협이 안 되는가 = clamp 후 정당한 최단 사거리보다 짧은가
	failures += _check(CombatMath.clamp_arrow_range(melee_range) <= CombatMath.MIN_ARROW_RANGE,
		"★사칭 화살의 사거리 = %.0fpx (MIN clamp) ≪ 정당한 최장 원거리 %.0fpx — 뚫려도 위협이 아니다"
			% [CombatMath.clamp_arrow_range(melee_range), longest_real])

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
	var fallback_reach_ok := true
	var degenerate_ok := true
	var lead_ok := true
	var auto_fire_ok := true
	var melee_gap_ok := true
	var auto_fire_margin_ok := true
	var buffer_margin_ok := true
	var buffer_worst := 1.0e9
	var buffer_worst_at := ""
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
		# 🔴 **홀드 연사가 호스트 발사율 게이트 위에 오는가 — 직업 × haste 전수** (2026-07-28 netreview C2).
		#    깨지면 정직한 홀드가 지터로 조용히 거부되는데 **표시 화살은 그대로 날아간다**(데미지만 0,
		#    HUD·소리·반동 전부 정상) — 화면에 이유가 없는 부류다. 게다가 호스트 자신은 이 게이트를
		#    안 지나(`combat_authority._on_player_shoot`) **게스트만** 손해 봐서 신고조차 엇갈린다.
		# ⚠ 검사가 둘인 이유: ⑴만으로는 "지터 0에서 간신히 통과"도 초록이다. 실기에서 문제가 되는 것은
		#    여유의 **크기**이므로 ⑵가 호스트 프레임 1주기를 흡수하는지 따로 본다.
		# 🔴 **근접 자기 스로틀 전수** (netreview I-3, 2026-07-28) — 「홀드 연사 전수」와 같은 형태다.
		#    클라는 판정 도착 간격이 호스트 게이트 아래로 내려가지 않게 스스로 물러서는데, 그 간격을
		#    호스트 임계에 **딱 붙이면 여유가 0**이라 게스트에선 편도 지터 한 번에 거부된다
		#    (증상 = 스윙·궤적·소리·반동 다 나오는데 **적 HP만 안 깎임**, 에러 0, **배포본·게스트 한정**).
		# ⚠ 표본에 **경계 양쪽**을 넣는다 (netreview m-8) — `minf(..., cd)` clamp의 발동점은 전사에서
		#    `h = 0.20`(cd = 1/3)인데 `[0, 0.25, 0.5]` 3점은 그 경계를 **한 번도 안 밟는다.**
		for h4: float in [0.0, 0.19, 0.21, 0.25, float(CombatMath.LEVEL_STAT_MAX["haste"])]:
			var cd4 := CombatMath.effective_cooldown(j, h4)
			var gap4 := CombatMath.melee_throttle_gap_s(j, h4)
			# ⑴ 호스트 근접 쿨다운 게이트를 통과하는가 — **같은 함수**로 묻는다(임계식 복제 금지).
			if not CombatMath.is_hit_cooldown_ok(0, int(gap4 * 1000.0), j, h4):
				melee_gap_ok = false
			# ⑵ 🔴 **발산 금지 — `gate ≤ cd`.** 점화식이 `x[n+1] = max(t_hit, x[n] − cd + gate)`라
			#    `gate > cd`면 매 스윙 `(gate − cd)`씩 **영구 누적**된다(최대 haste에서 실제로 그렇다:
			#    `cd×0.9 + 1/30`이 `cd`를 1.3ms 넘긴다). 이 부등식이 **"같은 무기 항등"의 근거**다.
			if gap4 > cd4 + 0.000001:
				melee_gap_ok = false
			# ⑸ 🔴 **래칫 상한** (netreview Gap A). ⑵의 `gate ≤ cd`는 **등호를 허용**하는데
			#    등호가 곧 감쇠 0 = 단조 비감소(래칫)다. 그리고 등호는 에지가 아니라 haste ≥ 0.2에서
			#    **상시**다. 그래서 "감쇠가 있는가"가 아니라 **"한 스윙이 미뤄질 수 있는 양"**을 막는다
			#    (`player._swing_attack`의 `clampf(..., _swing_hit_at + MELEE_THROTTLE_MAX_S)`).
			if CombatMath.MELEE_THROTTLE_MAX_S <= 0.0:
				melee_gap_ok = false
			# ⑹ 🔴 **상한도 haste로 줄어들어야 한다.** 덮는 대상(`t_hit` 결손)이 haste로 줄어드는데
			#    상한만 절대값이면 haste ≥ 0.25에서 `t_hit + 상한 > swing_time`이 되어 판정이 **스윙 창
			#    밖**으로 샌다(Gap C가 haste 0에서만 초록인 채로 깨진다). 실측으로 걸린 축이다.
			if not is_equal_approx(CombatMath.melee_throttle_max_s(h4),
					CombatMath.MELEE_THROTTLE_MAX_S * CombatMath.haste_scale(h4)):
				melee_gap_ok = false
			# ⑶ 여유가 실제로 붙어 있는가 — 취할 수 있는 최대(프레임 1주기 ∩ 슬랙 잔여)를 다 쓰는가.
			#    `+ AUTO_FIRE_HOST_FRAME_S` 항을 지우면 여기가 빨개진다.
			var want4 := minf(CombatMath.AUTO_FIRE_HOST_FRAME_S, cd4 * (1.0 - CombatMath.FIRE_RATE_SLACK))
			if gap4 - cd4 * CombatMath.FIRE_RATE_SLACK < want4 - 0.000001:
				melee_gap_ok = false
			# ⑷ 원격 연출 게이트는 **반대 부호**여야 한다 — 호스트가 받아 주는 타격은 반드시 보여야
			#    하므로 임계보다 관대해야 한다. 같은 부호로 통일하면 연출이 조용히 삼켜진다.
			if CombatMath.melee_fx_gate_s(j, h4) > cd4 * CombatMath.FIRE_RATE_SLACK - want4 + 0.000001:
				melee_gap_ok = false
		for h2: float in [0.0, 0.25, float(CombatMath.LEVEL_STAT_MAX["haste"])]:
			var af_gap_ms := CombatMath.auto_fire_gap_s(j, h2) * 1000.0
			# ⑴ 지터 0에서 통과하는가 (호스트 게이트와 **같은 함수**로 묻는다 — 임계식을 복제하지 않는다)
			if not CombatMath.is_fire_rate_ok(0, int(af_gap_ms), j, h2):
				auto_fire_ok = false
			# ⑵ 여유 ≥ 호스트 프레임 1주기 — `auto_fire_gap_s`를 쿨다운 그대로 되돌리면 여기가 빨개진다
			var af_thresh_ms := CombatMath.effective_cooldown(j, h2) * CombatMath.FIRE_RATE_SLACK * 1000.0
			if af_gap_ms - af_thresh_ms < CombatMath.AUTO_FIRE_HOST_FRAME_S * 1000.0 - 0.001:
				auto_fire_margin_ok = false
		# 🔴🔴 **클릭 발사 경로에도 `auto_fire_gap_s` 대칭이 필요하다** (netreview C-1~C-3, 2026-08-01).
		#   C2(2026-07-28)가 홀드 연사에만 여유를 붙인 근거는 *"사람의 클릭은 경계에 안 붙는다"* 였다.
		#   **선입력 버퍼가 그 전제를 깼다** — 버퍼가 살려 낸 클릭은 발사 간격을 `combo_gap_s`에
		#   **정확히** 못 박으므로 남는 여유가 구조적 마진(`cd × (1 − FIRE_RATE_SLACK)`)뿐인데,
		#   웹 30fps 호스트의 수신 프레임 양자화가 그중 33.3ms를 먹는다.
		#   ⚠ **입력을 보존하는 편의 기능이 들어올 때마다 이 전제가 다시 깨진다** — 이 단정이 그 감시자다.
		# 🔴 위 `melee_gap_ok` ⑴은 **엄격히 크다**만 보므로 15ms도 통과한다. 여기는 예산을
		#   **호스트 프레임 1주기**로 못 박는다(홀드 경로 ⑵와 같은 기준).
		# 🔴 실패의 성격이 축마다 다르다 — 셋 다 무증상이다:
		#   · `advance_combo` 하한 미달 → 콤보 리셋. 호스트 인덱스가 클라보다 **영구히 1 뒤처져**
		#     마무리 타가 그 교전 내내 평타로 확정된다(해제 = 800ms 이상 정지). 연출은 전부 정상.
		#   · `is_hit_cooldown_ok` 미달 → 타격 **통째로 소실**(스윙·궤적·소리·반동 다 나오고 HP만 그대로).
		for bf: String in DirAccess.get_files_at("res://data/equipment"):
			var bbase := bf.trim_suffix(".remap")
			if bbase.get_extension() != "tres":
				continue
			var be := load("res://data/equipment/%s" % bbase) as EquipDef
			if be == null or be.slot() != EquipDef.SLOT_WEAPON:
				continue
			if not be.job_id.is_empty() and be.job_id != j.id:
				continue
			for hb: float in [0.0, 0.19, 0.21, 0.25, float(CombatMath.LEVEL_STAT_MAX["haste"])]:
				for ib: int in range(CombatMath.combo_len(be)):
					# 🔴 **클라가 실제로 내는 간격**을 겨눈다 — `player.gd`가 쓰는 것과 **같은 함수**다.
					#   여기에 `combo_gap_s`를 직접 적으면 "버퍼 여유를 지우는 뮤테이션"을 못 잡는다.
					var buf_gap := CombatMath.buffered_attack_gap_s(j, be, ib, hb)
					var lo_b := CombatMath.combo_min_gap_s(j, be, ib, hb)
					var need_b := CombatMath.effective_cooldown(j, hb) * CombatMath.FIRE_RATE_SLACK
					var margin := minf(buf_gap - lo_b, buf_gap - need_b)
					if margin < buffer_worst:
						buffer_worst = margin
						buffer_worst_at = "%s/%s h=%.2f i=%d" % [j.id, be.id, hb, ib]
					if margin < CombatMath.AUTO_FIRE_HOST_FRAME_S - 0.000001:
						buffer_margin_ok = false
		for ef: String in DirAccess.get_files_at("res://data/equipment"):
			var ebase := ef.trim_suffix(".remap")
			if ebase.get_extension() != "tres":
				continue
			var e := load("res://data/equipment/%s" % ebase) as EquipDef
			# 🔴 **근접 무기 전체**를 본다 — `motion_type == "swing"`으로 좁히면 찌르기(창)가
			#   **말없이 빠진다**(무기 모션 개편 2026-07-28). 아래 두 계약(스윙 창·폴백 창)은
			#   "근접 확정을 받는 무기"의 계약이고, 그 기준의 단일 소스는 `is_projectile_weapon`이다
			#   (호스트 `combat_authority`의 근접 거부 게이트와 **같은 함수**). 하필 창이 폴백 창
			#   부등식의 가장 빡빡한 사례(80 vs 84)라, 놓치면 트립와이어가 초록인 채로 죽는다.
			if e == null or CombatMath.is_projectile_weapon(e):
				continue
			# 직업 귀속(GameState.can_equip_job 규칙) — 실제로 착용 가능한 조합만 본다.
			# 계약은 "**착용** 직업의 attack_cooldown"이다(rules §3): 전사 대검(0.34)을 궁수 쿨다운(0.15)과
			# 비교하면 성립할 수 없는 조합에서 빨개진다. job_id가 비면 범용(아무 직업).
			if not e.job_id.is_empty() and e.job_id != j.id:
				continue
			for h: float in [0.0, 0.25, float(CombatMath.LEVEL_STAT_MAX["haste"])]:
				if e.swing_time * CombatMath.haste_scale(h) >= CombatMath.effective_cooldown(j, h):
					swing_ok = false
			# 🔴 **호스트 폴백 창 불변식** (2026-07-28 netreview I-1) — `melee_range ≤ 직업 기본 × SLACK`.
			#   G_STATS 미도착 창(스테이지 전환 직후)에는 호스트가 무기를 모른 채 `melee_weapon = null`로
			#   판정한다 = **직업 기본 사거리 × HIT_REACH_SLACK**. 무기의 로컬 도달이 그걸 넘으면 그 창의
			#   정당한 팁 타격이 **무음 거부**된다(창 80 vs 전사 42×2.0 = 84 — 여유 4px뿐이다).
			#   폴백 창은 짧지만 `PeerSync._peer_stats`가 씬마다 새로 태어나 **스테이지 전환마다 재발**한다.
			#   ⚠ reach 특성은 양변에 똑같이 곱해져 상쇄되므로 기본값끼리 비교하면 충분하다.
			#   ⚠ 기존 `melee_range × 1.5 ≤ MAX_MELEE_RANGE` 트립와이어는 이 축을 **전혀 안 본다**(상한
			#     130 기준이면 창은 87까지 통과하는데 실제로는 85부터 이 부등식이 깨진다).
			if e.melee_range > 0.0 and e.melee_range > j.attack_range * CombatMath.HIT_REACH_SLACK:
				fallback_reach_ok = false
	failures += _check(swing_ok, "스윙 창 계약 전수: 모든 무기×직업×haste에서 swing_time < effective_cooldown")
	failures += _check(fallback_reach_ok,
		"★폴백 창 전수: melee_range ≤ 직업 기본 × HIT_REACH_SLACK (G_STATS 미도착 창의 무음 거부 방지)")

	# 🔴 근접 기하 데이터 전수 (무기 모션 축 2026-07-28) — 둘 다 **에러 없이 조용히 깨지는** 부류다.
	var melee_arc_ok := true
	var melee_clamp_ok := true
	var melee_phase_ok := true
	var melee_motion_ok := true
	var melee_weight_ok := true
	var melee_throttle_ok := true
	var melee_blade_ok := true
	var t_hit_min := 1.0e9
	var t_hit_max := 0.0
	for mf: String in DirAccess.get_files_at("res://data/equipment"):
		var mbase := mf.trim_suffix(".remap")
		if mbase.get_extension() != "tres":
			continue
		var mw := load("res://data/equipment/%s" % mbase) as EquipDef
		# 🔴 위와 같은 이유 — 근접 기하 계약은 **찌르기에도 그대로 걸린다**(창은 반각 0.3으로
		#   `swing_arc > 0` 단정의 실질적 최소 사례이고, `melee_range` 80으로 clamp 단정의 최대 사례다).
		# ⚠ 슬롯도 본다 — `is_projectile_weapon`은 `motion_type`만 보므로 **방어구까지 "근접 무기"로
		#   순회**한다(오늘은 무해하나 단정 문구와 실제 대상이 다르다, code-rv m-C).
		if mw == null or mw.slot() != EquipDef.SLOT_WEAPON or CombatMath.is_projectile_weapon(mw):
			continue
		# ⑴ 반각 0 = 정면 **한 점**만 판정 = 사실상 공격 불가. 휘두름은 그대로 보이고 데미지만 안 난다.
		if mw.swing_arc <= 0.0:
			melee_arc_ok = false
		# ⑵ 특성 상한까지 곱해도 MAX_MELEE_RANGE 안이어야 한다 — 넘으면 `effective_attack_range`가
		#    정당한 무기를 **조용히 절삭**한다(창을 100으로 만들면 여기서 걸린다). proj_range 관용구.
		if mw.melee_range > 0.0 \
				and mw.melee_range * (1.0 + CombatMath.MAX_REACH_BONUS) > CombatMath.MAX_MELEE_RANGE:
			melee_clamp_ok = false
		# ⑶ 🔴 **모션 곡선 구간이 셋 다 양수 폭인가** (무기 모션 개편 2026-07-28). 표시 전용이지만
		#    깨지면 **에러 없이 화면만** 망가진다: 합이 1 이상이면 복귀 구간이 사라져 무기가 휘두른
		#    자세로 얼어붙고, 0이면 그 구간이 통째로 건너뛰어진다. `player._apply_motion_shape`가
		#    코드로 clamp해 사고는 막지만, **clamp는 조용하다** — 작성자가 적은 값이 안 쓰인 것을
		#    아무도 모른다. 여기서 빨개져야 "왜 내 도끼 예비가 안 길어지지"를 안 겪는다.
		#    ⚠ 구조적 부등식만 본다(clamp 여유 상수를 복제하지 않는다 — 그러면 진실원이 둘이 된다).
		if mw.swing_windup_ratio <= 0.0 or mw.swing_strike_ratio <= 0.0 \
				or mw.swing_windup_ratio + mw.swing_strike_ratio >= 1.0:
			melee_phase_ok = false
		# ⑹ 🔴 **후딜 창이 물리 프레임 하나보다 길어야 한다** (netreview I-2, 2026-07-28).
		#    판정은 `p >= 1.0`인 프레임에서 확정되므로 그 프레임이 **최소 한 번은 관측**돼야 한다.
		#    ⑸의 `< 1.0`만으로는 부족하다 — `windup .5 / strike .45 / swing_time .24`짜리 `.tres`
		#    한 장이면 후딜 창이 12ms < 16.7ms라 **그 무기는 데미지가 0인데 스위트는 초록**이다.
		#    ⚠ 코드에도 캐치올 래치(`player._finalize_swing_sweep`)를 넣어 **이중으로** 막았다.
		#      그래도 이 단정을 남기는 이유: 래치는 판정을 살리지만 그 무기의 **스윕 궤적이 한
		#      프레임도 안 그려지는** 것(= 표시 소실)은 못 고친다. 데이터로도 막아야 한다.
		#    ⚠ 기준은 물리 틱 1주기를 **엔진 설정에서 유도**한다 — 60을 여기 박으면 두 번째 진실원이 된다.
		#    ⚠ haste는 양변에 같이 곱해지지 않는다 — 창만 짧아지므로 **최대 haste 기준**으로 본다.
		var recover_s := (1.0 - mw.swing_windup_ratio - mw.swing_strike_ratio) \
			* mw.swing_time * CombatMath.haste_scale(float(CombatMath.LEVEL_STAT_MAX["haste"]))
		if recover_s <= 1.0 / float(maxi(Engine.physics_ticks_per_second, 1)):
			melee_phase_ok = false
		# ⑺ 🔴 **clamp가 발동했는가 — 적은 값이 그대로 쓰이는가** (code-rv J-1, 2026-07-28).
		#    ⑸의 `w>0 ∧ s>0 ∧ w+s<1`은 **코드 clamp보다 느슨해서** 파국(합 ≥ 1, 0/음수)만 잡았다.
		#    `0.02`(→0.05로 clamp)·합 `0.97`(→0.95)은 **둘 다 초록으로 샜다** — 하필 이 단정이 막으려던
		#    "왜 내 도끼 예비가 안 길어지지"가 나는 바로 그 밴드다.
		#    🔴 **상한 값을 여기 복제하지 않는다** — `CombatMath.motion_phases()`(= 코드가 실제로 쓰는
		#      clamp)를 그대로 불러 **입력과 출력이 같은지**만 본다. 상한을 조여도 이 단정은 따라온다.
		var ph := CombatMath.motion_phases(mw)
		if not is_equal_approx(ph.x, mw.swing_windup_ratio) 				or not is_equal_approx(ph.y, mw.swing_strike_ratio):
			melee_phase_ok = false
		# ⑻ 🔴 **무게 배율 saturation** (code-rv J-2). `hit_shake / HIT_SHAKE_REF`가 상한에 걸리면
		#    그 위로는 **킥·박힘이 안 따라오고 셰이크만 커진다** — "무게 단일 소스"가 조용히 반쪽이
		#    된다. 현행 최대가 파쇄 도끼 4.4/1.5 = 2.93이라 **한 칸(4.5)만 올려도** 걸렸다.
		if mw.hit_shake / CombatMath.HIT_SHAKE_REF > CombatMath.HIT_WEIGHT_MAX:
			melee_weight_ok = false
		# ⑼ 🔴 **Gap C — 미뤄진 판정이 스윙 창 안에서 나는가.** 넘으면 모션이 끝난 뒤 데미지만 뜬다
		#    (무기는 평상 자세로 돌아가 있는데 숫자가 튄다). 상한까지 미뤄진 최악을 본다.
		var ph2 := CombatMath.motion_phases(mw)
		var t_hit := mw.swing_time * (ph2.x + ph2.y)
		if t_hit + CombatMath.MELEE_THROTTLE_MAX_S > mw.swing_time + 0.000001:
			melee_throttle_ok = false
		# ⑽ 🔴 **상한 유도 — `max(t_hit) − min(t_hit)`을 실제로 덮는가.** 스로틀이 메워야 하는 결손이
		#    정확히 그만큼이라, 상한이 그보다 작으면 정당한 보정이 **잘려** M-1이 부분 재발한다.
		#    ⚠ haste는 양쪽 t_hit에 같은 배율이라 차이도 함께 줄어든다 → haste 0이 최악이다.
		t_hit_min = minf(t_hit_min, t_hit)
		t_hit_max = maxf(t_hit_max, t_hit)
		# ⑷ 🔴 **근접 모션 타입은 아는 값이어야 한다.** 오타("thrusts")는 거부되지 않고 근접 분기의
		#    **베기 쪽으로 조용히 떨어진다** — 창이 검처럼 휘둘리는데 에러가 없다(이 개편이 없애려는
		#    상태 그 자체다). `is_projectile_weapon`이 이미 걸러낸 뒤라 남는 값은 이 둘뿐이어야 한다.
		if mw.motion_type != "swing" and mw.motion_type != "thrust":
			melee_motion_ok = false
		# ⑸ 🔴 **찌르기는 당김이 있어야 한다.** 둘을 한 번에 잡는 단정이다:
		#    ⓐ 설계 — `swing_pull` 0이면 예비 동작이 사라져 "앞으로 미는 베기"가 되고 창이 다시
		#      검처럼 보인다(이 개편의 출발점 그 자체다).
		#    ⓑ 🔴 **프로퍼티 이름이 어긋난 경우** — Godot은 `.tres`의 **모르는 프로퍼티를 경고 없이
		#      버린다**(이번 작업에서 실측 확인). 즉 스키마 필드명과 데이터 키가 한 글자만 달라도
		#      값이 조용히 사라지고 모션만 밋밋해진다. 이 단정이 그 창을 닫는다.
		if mw.motion_type == "thrust" and mw.swing_pull <= 0.0:
			melee_motion_ok = false
		# ⑾ 🔴 **칼날 폭 리본 — 날이 무기 안에 드는가** (칼날 폭 리본 2026-08-01).
		#    리본은 `[칼끝 − blade_length, 칼끝]`만 채운다. 이 값이 **스윕 중 칼끝이 회전 중심에서
		#    가장 가까워지는 거리**를 넘으면 안쪽 변이 손을 지나 회전 중심까지 내려가고, 거기서
		#    `player.TRAIL_MIN_INNER_DIST` 하한에 눌려 점들이 겹치면 다각형이 퇴화한다 —
		#    **리본이 에러 없이 통째로 안 그려진다**(= 07-29 이전의 "궤적이 없다"로 되돌아간다).
		# 🔴🔴 **경계식 = `텍스처 폭 − grip.x + weapon_hold_dist − swing_pull`** (reviewer I-5 정정).
		#    ⚠ 초판은 `텍스처 폭 − grip.x`만 보고 *"`hold_dist`는 양변을 같은 방향으로 밀어 안전"*
		#      이라고 적었는데, **그 근거는 절반만 맞다 — `swing_pull`이 반대 방향으로 민다.**
		#      찌르기의 스윕 시작점이 `_motion_at`에서 `lerpf(-swing_pull, peak, 0)` = **−pull**이라
		#      그 순간 칼끝이 `hold_dist − pull`만큼만 나와 있다(창은 12 − 9 = **여유 3px**).
		#      즉 옛 검사가 충분조건인 것은 `hold_dist ≥ swing_pull`일 때뿐이고, 새 찌르기 무기가
		#      `swing_pull > hold_dist`로 오면 **트립와이어 초록불인 채 리본이 사라진다** —
		#      정확히 이 단정이 막으려던 상태다. 그래서 두 항을 다 넣어 조인다.
		#    ⚠ 베기(swing)는 스윕 lunge가 `peak × sin(u·π) ≥ 0`이라 `pull`이 안 걸린다 — 현 데이터에서
		#      `swing_pull > 0`인 무기가 창뿐이라 이 식을 전 무기에 그대로 써도 **보수적**이다.
		#    ⚠ 마지막 1px(`TRAIL_MIN_INNER_DIST`)은 여기서 안 본다 — 그 상수는 `player.gd`에 있어
		#      씬 글루라 테스트가 못 읽는다(복제하면 두 번째 진실원이 된다). 경계 딱 1px 안쪽은
		#      코드 clamp가 "안팎 역전 없이 두께 0"으로 안전하게 떨어뜨린다(`_blade_base_global`).
		# ⑿ 🔴 **조용한 clamp 없음** — `clamped == raw` 관용구(J-1). 상한 값을 여기 복제하지 않고
		#    코드가 실제로 쓰는 `CombatMath.blade_length()`를 그대로 불러 입출력이 같은지만 본다.
		# ⒀ 🔴 **근접 무기는 값을 명시했는가** — 빠뜨리면 `DEFAULT_BLADE_LENGTH`(8px) 폴백이라
		#    "리본이 왜 아직 얇지"가 된다(발사형 `arrow_range` 누락 트립와이어와 같은 관용구).
		if mw.weapon_texture != null:
			var fwd_min := float(mw.weapon_texture.get_width()) - mw.weapon_grip.x \
				+ mw.weapon_hold_dist - maxf(mw.swing_pull, 0.0)
			if CombatMath.blade_length(mw) > fwd_min:
				melee_blade_ok = false
		if mw.blade_length > 0.0 \
				and not is_equal_approx(CombatMath.blade_length(mw), mw.blade_length):
			melee_blade_ok = false
		if mw.blade_length <= 0.0:
			melee_blade_ok = false
	failures += _check(melee_arc_ok,
		"근접 기하 전수: 모든 근접 무기의 swing_arc > 0 (0이면 휘둘러도 안 맞는다)")
	failures += _check(melee_clamp_ok,
		"근접 기하 전수: melee_range × 특성 상한 ≤ MAX_MELEE_RANGE (조용한 절삭 방지)")
	failures += _check(melee_phase_ok,
		"★모션 곡선 전수: 선딜·스윕·후딜 세 구간이 양수 폭 + 후딜 창 > 물리 프레임 1주기(최대 haste)")
	failures += _check(melee_motion_ok,
		"★근접 모션 전수: motion_type이 swing/thrust 중 하나 + 찌르기는 swing_pull > 0")
	# 🔴 **미러 단정** — `CombatMath.DEFAULT_SWING_*`는 `EquipDef`의 기본값을 복제한 값이다(무장 해제
	#    폴백). 사람이 지키는 미러는 조용히 깨진다(콘 텔레그래프 각·스워시 반각·보스 애니 길이가
	#    전부 그랬다). 여기서 깨지면 증상이 **무장 해제 상태에서만** 모션 구간이 달라지는 것이라
	#    더 안 보인다. ⚠ `is_equal_approx` — 그냥 `==`는 float 표현 차이로 흔들린다.
	var probe := EquipDef.new()
	failures += _check(is_equal_approx(probe.swing_windup_ratio, CombatMath.DEFAULT_SWING_WINDUP),
		"★미러: EquipDef.swing_windup_ratio 기본값 == CombatMath.DEFAULT_SWING_WINDUP")
	failures += _check(is_equal_approx(probe.swing_strike_ratio, CombatMath.DEFAULT_SWING_STRIKE),
		"★미러: EquipDef.swing_strike_ratio 기본값 == CombatMath.DEFAULT_SWING_STRIKE")
	if t_hit_max > t_hit_min and t_hit_max - t_hit_min > CombatMath.MELEE_THROTTLE_MAX_S + 0.000001:
		melee_throttle_ok = false
	# 🔴 **Gap B — 미뤄진 판정이 궤적이 아직 보일 때 나는가.** 궤적이 흩어진 **뒤에** 판정이 나면
	#    「표시 ⊇ 판정」이 시간 축에서 무너진다(이 작업 전체가 세운 불변식이 마지막 구간에서 깨진다).
	failures += _check(CombatMath.MELEE_THROTTLE_MAX_S < CombatMath.MELEE_TRAIL_FADE_S,
		"★Gap B: 스로틀 최대 지연 < 궤적 페이드 시간 (궤적이 사라진 뒤 판정 금지)")
	failures += _check(melee_throttle_ok,
		"★스로틀 상한 전수: t_hit + 상한 ≤ swing_time(창 안 판정) + 상한 ≥ max(t_hit)−min(t_hit)(결손 커버)")
	failures += _check(melee_weight_ok,
		"★무게 배율 전수: hit_shake / HIT_SHAKE_REF ≤ HIT_WEIGHT_MAX (조용한 saturation 방지)")
	failures += _check(melee_blade_ok,
		"★칼날 폭 전수: blade_length 명시 + ≤ (텍스처폭 − grip.x + hold_dist − swing_pull) + 조용한 clamp 없음")
	# ★검출력 — 부등식의 **새 두 항**(`hold_dist` · `swing_pull`)이 실제로 도는가. 합성으로 확인한다:
	#   `pull > hold_dist`인 찌르기 무기는 옛 식(전방 길이만)으로는 통과하고 새 식에서만 걸린다.
	var pull_probe := EquipDef.new()
	pull_probe.weapon_grip = Vector2(4, 8)
	pull_probe.weapon_hold_dist = 0.0
	pull_probe.swing_pull = 12.0
	pull_probe.blade_length = 40.0  # 전방 길이 44 안 → 옛 식은 통과 · 새 식 한계는 44 − 12 = 32
	failures += _check(pull_probe.blade_length > 48.0 - pull_probe.weapon_grip.x
			+ pull_probe.weapon_hold_dist - pull_probe.swing_pull,
		"★칼날 폭 검출력: `swing_pull > hold_dist`인 찌르기가 새 식에서만 걸린다 (I-5가 연 구멍)")
	# ★검출력 — 위 전수는 현 데이터가 통과라 "분기가 실제로 도는가"를 못 보여준다. 합성으로 확인한다.
	var blade_probe := EquipDef.new()
	failures += _check(is_equal_approx(CombatMath.blade_length(blade_probe), CombatMath.DEFAULT_BLADE_LENGTH),
		"★칼날 폭 검출력: 미지정(0) = 기본 폴백(옛 칼끝 리본 굵기 ≈ 7px) — 도입 전 근사 항등")
	blade_probe.blade_length = 999.0
	failures += _check(is_equal_approx(CombatMath.blade_length(blade_probe), CombatMath.MAX_BLADE_LENGTH),
		"★칼날 폭 검출력: 상한 초과(999) → clamp — 🔴 clamp를 지우는 뮤테이션이 여기서 잡힌다")
	blade_probe.blade_length = INF
	failures += _check(is_equal_approx(CombatMath.blade_length(blade_probe), CombatMath.DEFAULT_BLADE_LENGTH),
		"★칼날 폭 검출력: 비유한 값 → 기본 폴백 (리본 좌표가 NaN이 되면 다각형이 통째로 사라진다)")

	# --- 궤적 아이덴티티 전수 (하위 직업별 궤적 색·밀도, 2026-08-01) ---
	# 🔴 **`clamped == raw`를 단정한다** (리뷰 J-1·J-2의 처방 그대로): 상한 값을 테스트에 복제하지
	#    않고도 "데이터가 조용히 clamp됐다"를 잡는다. 복제하면 상한을 튜닝할 때 테스트도 같이 고쳐야
	#    하고, 그러면 트립와이어가 데이터가 아니라 자기 자신을 검사하게 된다.
	# 🔴 **알파 0 검사가 이 블록의 핵심이다** — 0이면 리본·잔상이 통째로 사라지는데(`_fx_color`가
	#    곱셈이다) **에러가 없다.** 화면에는 "칼만 도는" 것으로만 보이고 원인이 데이터에 있다는
	#    단서가 어디에도 없다. 궤적은 §3에서 「표시 ⊇ 판정」을 지는 쪽이라 사라지면 그 계약이 통째로
	#    무너진다("안 보이는데 맞는다"가 상시가 된다).
	var subjob_fx_ok := true
	var subjob_fx_seen := 0
	for sf: String in DirAccess.get_files_at("res://data/subjobs"):
		var sbase := sf.trim_suffix(".remap")
		if sbase.get_extension() != "tres":
			continue
		var sd := load("res://data/subjobs/%s" % sbase) as SubJobDef
		if sd == null:
			continue
		subjob_fx_seen += 1
		if not is_equal_approx(CombatMath.fx_ghost_mult(sd), sd.fx_ghost_mult):
			subjob_fx_ok = false  # 조용한 clamp = 데이터에 적힌 값과 화면이 갈라진 상태
		if sd.fx_color.a <= 0.0:
			subjob_fx_ok = false
		# ⚠ **RGB 상한도 본다** (netreview Minor). Godot `Color`는 1.0 초과를 허용하므로
		#   `Color(5, 5, 5, 1)`짜리 .tres가 들어오면 `_fx_color`의 곱셈이 궤적을 흰색으로 태운다
		#   — 알파 0과 같은 부류(에러 없이 화면만 망가짐)라 같은 자리에서 닫는다.
		if sd.fx_color.r > 1.0 or sd.fx_color.g > 1.0 or sd.fx_color.b > 1.0:
			subjob_fx_ok = false
	failures += _check(subjob_fx_seen > 0, "궤적 아이덴티티 전수: data/subjobs 스캔 성공(0장이면 검사가 빈다)")
	failures += _check(subjob_fx_ok,
		"★궤적 아이덴티티 전수: fx_ghost_mult 조용한 clamp 없음 + fx_color 알파 > 0 · rgb ≤ 1 (궤적 소실·번짐 방지)")
	# ★검출력 — 위 전수는 현 데이터가 통과라 "clamp 분기가 실제로 도는가"를 못 보여준다(칼날 폭 관용구).
	var fx_probe := SubJobDef.new()
	failures += _check(is_equal_approx(CombatMath.fx_ghost_mult(fx_probe), 1.0),
		"★궤적 아이덴티티 검출력: 기본값 = 배율 1.0 = 도입 전과 완전 항등")
	fx_probe.fx_ghost_mult = 99.0
	failures += _check(is_equal_approx(CombatMath.fx_ghost_mult(fx_probe), CombatMath.MAX_FX_GHOST_MULT),
		"★궤적 아이덴티티 검출력: 상한 초과 → clamp (잔상 = 드로우콜이라 웹 프레임 비용이다)")
	fx_probe.fx_ghost_mult = INF
	failures += _check(is_equal_approx(CombatMath.fx_ghost_mult(fx_probe), 1.0),
		"★궤적 아이덴티티 검출력: 비유한 값 → 항등 폴백 (int(round(INF))는 잔상 루프를 얼린다)")
	failures += _check(is_equal_approx(CombatMath.fx_ghost_mult(null), 1.0),
		"★궤적 아이덴티티 검출력: null(하위 직업 미장착) → 항등 폴백")
	# 🔴 **검기 도달 배율이 판정 배율과 같은 함수를 지나는가** — `player._trail_reach_mult()`가
	#    `1 + clamp_reach(reach)`이고 `effective_attack_range`가 `base × (1 + clamp_reach(reach))`다.
	#    같은 배율이라는 것이 "리본 길이 = 판정 도달"의 전부라, 여기가 갈라지면 검성에서만
	#    표시와 판정이 어긋난다(그게 이 변경이 고치려던 결함 자체다).
	#    ⚠ `player.gd`는 씬 글루라 `-s`가 preload를 못 한다 — **배율의 근거인 `clamp_reach`만** 여기서
	#      잠그고, 곱하는 자리가 맞는지는 코드 주석이 방어한다(rules §3 「씬 글루 사각」).
	var jr := load("res://data/jobs/warrior.tres") as JobDef
	if jr != null:
		var reach_probe := 0.3
		var mult_probe := 1.0 + CombatMath.clamp_reach(reach_probe)
		failures += _check(is_equal_approx(
				CombatMath.effective_attack_range(jr, reach_probe), jr.attack_range * mult_probe),
			"★검기 도달: 판정 사거리 = 기본 × (1 + clamp_reach) — 리본이 곱하는 배율과 같은 식")
		failures += _check(is_equal_approx(1.0 + CombatMath.clamp_reach(0.0), 1.0),
			"★검기 도달: reach 0 → 배율 1.0 = 리본이 도입 전과 한 픽셀도 다르지 않다(항등)")
		failures += _check(is_equal_approx(
				1.0 + CombatMath.clamp_reach(9.0), 1.0 + CombatMath.MAX_REACH_BONUS),
			"★검기 도달: 과대 reach도 MAX_REACH_BONUS clamp를 지난다(리본만 상한 밖으로 못 나간다)")
	failures += _check(degenerate_ok, "퇴화 트립와이어: MAX_HASTE에서도 유효 쿨다운 게이트 > SAME_SWING_MS")
	failures += _check(lead_ok, "외삽 상한 불변식: LAG_MAX_LEAD_DIST ≥ 최고 이속×구르기×최대 lead (전 직업)")
	failures += _check(melee_gap_ok,
		"★근접 스로틀 전수: 호스트 게이트 통과 + gate ≤ cd(발산 금지) + 여유 1프레임 + 연출 게이트 반대 부호")
	failures += _check(auto_fire_ok, "홀드 연사 전수: auto_fire_gap_s가 호스트 is_fire_rate_ok를 통과(직업×haste)")
	failures += _check(auto_fire_margin_ok, "홀드 연사 전수: 게이트 여유 ≥ 호스트 프레임 1주기 (산발 유실 방어)")
	failures += _check(buffer_margin_ok,
		"★선입력 버퍼 전수: 버퍼가 살린 클릭의 여유 ≥ 호스트 프레임 1주기 (최악 %s = %.1fms)"
			% [buffer_worst_at, buffer_worst * 1000.0])

	# 🔴 **차지 가치 트립와이어 — "모으는 것이 탭 연타보다 나은가"** (법사 무기 분화, 2026-07-27).
	#    유도: 레벨 L을 모아 쏘는 주기 = `쿨다운 + L×단계시간`, 위력 = `×CHARGE_DAMAGE_MULT[L]`.
	#    따라서 모으는 쪽이 이기려면   mult(L)×cd > cd + L×step   ⇔   cd > L×step / (mult(L) − 1).
	#    현 배율표에서 가장 빡빡한 것은 **L=1**이다(0.35/0.7 = cd > 0.5, L=3은 1.05/2.4 = 0.4375).
	# 🔴 **왜 트립와이어인가 — 쿨다운을 "답답하다"는 이유로 낮추는 순간 이 부등식이 조용히 뒤집힌다.**
	#    그러면 차지 무기가 **"탭 연타가 더 센 무기"** 가 되어, 보스가 100% 드랍하는 도면(iron_staff)의
	#    제작 보상이 통째로 무의미해진다. 에러도 경고도 없고 화면에도 안 드러난다(DPS를 재봐야 안다) —
	#    이 프로젝트가 반복해 겪은 "에러 없이 설계만 죽는" 부류다. 실제로 이 작업의 초안이 쿨다운
	#    0.8 → 0.4였고, 그 값이면 1~3단계가 **전부** 연타만 못하다(아래 ★검출력이 그 조합을 쓴다).
	# ⚠ haste 불변이다 — 양변에 haste_scale이 똑같이 곱해진다(§3 haste 계약, 쿨다운·차지 스텝 공유).
	#    그래도 전 구간을 쓸어 "배율 공유가 실제로 성립한다"를 데이터로도 보인다.
	var charge_worth_ok := true
	for ef7: String in DirAccess.get_files_at("res://data/equipment"):
		var ebase7 := ef7.trim_suffix(".remap")
		if ebase7.get_extension() != "tres":
			continue
		var e7 := load("res://data/equipment/%s" % ebase7) as EquipDef
		if e7 == null or e7.motion_type != "charge":
			continue
		for jf7: String in DirAccess.get_files_at("res://data/jobs"):
			var jbase7 := jf7.trim_suffix(".remap")
			if jbase7.get_extension() != "tres":
				continue
			var j7 := load("res://data/jobs/%s" % jbase7) as JobDef
			if j7 == null:
				continue
			# 직업 귀속 — 실제로 착용 가능한 조합만 본다(스윙 창 전수와 같은 규약). 비면 범용.
			if not e7.job_id.is_empty() and e7.job_id != j7.id:
				continue
			for h7: float in [0.0, 0.25, float(CombatMath.LEVEL_STAT_MAX["haste"])]:
				var cd7 := CombatMath.effective_cooldown(j7, h7)
				var st7 := CombatMath.effective_charge_step(e7.charge_step_time, h7)
				if cd7 <= 0.0 or st7 <= 0.0:
					continue  # 차지 못 하는 데이터 — is_charge_time_ok가 별도로 거부한다
				for lv7: int in range(1, CombatMath.MAX_CHARGE_LEVEL + 1):
					if CombatMath.CHARGE_DAMAGE_MULT[lv7] / (cd7 + float(lv7) * st7) <= 1.0 / cd7:
						charge_worth_ok = false
	failures += _check(charge_worth_ok,
		"차지 가치 전수: 모든 차지 무기×직업×haste×단계에서 '모아 쏘기' DPS > '탭 연타' DPS")

	# ★검출력 — 위 전수는 현 데이터가 통과라 "루프가 실제로 도는가"를 못 보여준다.
	#   초안 값(쿨다운 0.4 + 단계 0.35)을 합성으로 넣어 1~3단계가 **전부** 잡히는지 확인한다.
	var caught_lv := 0
	for lv8: int in range(1, CombatMath.MAX_CHARGE_LEVEL + 1):
		if CombatMath.CHARGE_DAMAGE_MULT[lv8] / (0.4 + float(lv8) * 0.35) <= 1.0 / 0.4:
			caught_lv += 1
	failures += _check(caught_lv == CombatMath.MAX_CHARGE_LEVEL,
		"★차지 가치 검출력: 쿨다운 0.4 + 단계 0.35면 1~3단계 전부 '연타만 못한 차지'로 잡힌다")

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
