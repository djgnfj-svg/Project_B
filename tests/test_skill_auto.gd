extends SceneTree
# 하위 직업 스킬(2026-08-02) 트립와이어 — `data/skills` 전수 + `data/subjobs` 배선 + 판정 기하.
# 성공/실패 모두 한 줄씩 찍는다 (침묵 통과 방지 — projectb-verify §3).
# 실행: ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_skill_auto.gd
#
# 🔴 **여기서 잡는 것은 「에러 없이 조용히 깨지는」 여섯 부류다:**
#   ⑴ **밸런스 상한 초과** — clamp가 없는 축이라(`SKILL_DPS_ADD_MAX`) **테스트가 유일한 방어**다.
#      clamp로 만들면 데이터에 적은 값과 실제가 갈라지고 그 갈라짐이 화면에 안 드러난다.
#   ⑵ **조용한 clamp** — `clamped == raw`로 단정한다. 🔴 상한 **값**을 테스트에 복제하면(예:
#      `radius <= 130`) 상한이 바뀌었을 때 테스트만 통과하는 「코드와 테스트가 같은 모델을 공유」
#      상태가 된다(리뷰 J-1 · N-1이 실제로 밟은 자리). 함수를 통과시켜 비교하는 것이 요점이다.
#   ⑶ **모르는 shape / beam의 length 0** — `is_skill_hit`이 false로 떨어져 **아무도 안 맞는데
#      에러가 없다**(FX도 같이 사라져 "발동은 됐는데 아무 일도 없다"만 남는다).
#   ⑷ **공유 하위 직업에 스킬** — `GameState.main_skill_of`가 `main_slot_def`(공유 배제)를 지나므로
#      **영원히 안 켜진다.** 데이터에 적어 두면 다음 사람이 "왜 안 나가지"로 며칠을 쓴다.
#   ⑸ **아이콘 없음** — HUD 칸이 빈 채로 뜨는데 에러가 없다.
#   ⑹ **다단이 쿨다운을 잡아먹는다** (2026-08-02 「환영검무」) — 총 시전 길이가 발동 게이트에
#      가까우면 다음 시전이 아직 안 끝난 다단을 덮어써 남은 타가 통째로 사라진다(호스트
#      `_skill_ticks`·클라 `_skill_fx_*` 둘 다 **시전자당 한 칸**이다).


# 🔴 이 비율만은 코드에 대응 상수가 없다 — **테스트 전용 불변식**이라 여기 사는 것이 맞다
#   (J-1이 금지하는 것은 「코드에 있는 상한 값의 복제」다).
const MAX_SPAN_RATIO := 0.5

# 🔴 터널링 불변식(⑺)의 분모 — 역시 **테스트 전용**이다(코드에 대응 상수가 없다).
#   보수적으로 30fps를 쓴다: `_physics_process`는 보통 60Hz 고정이지만 웹 Compatibility에서
#   물리 틱이 렌더에 묶여 떨어지는 경우가 있고, 여기서 틀리려면 **관대한 쪽**으로 틀려야 한다
#   (틀린 방향이 곧 "판정이 적을 통과했는데 아무도 모른다"이기 때문).
# ⚠ 코드 쪽은 이 값에 의존하지 않는다 — `combat_authority._step_skill_travel`의 **서브스텝**이
#   한 걸음을 판정 반경 이하로 자르므로 안전성은 구조가 보장한다. 이 단정은 그 위에 얹는
#   **데이터 감시**다(전진이 반경에 근접하면 서브스텝이 돌기 시작 = 프레임 비용이 는다).
const MIN_FPS := 30.0


# 🔴 **본 단정과 검출력 프로브가 같은 식을 지나게 하는 창구** — 사본을 두면 한쪽만 고쳐진다.
func _dps_add(s: SkillDef) -> float:
	var gate := _gate_s(s)
	return (CombatMath.skill_total_mult(s) / gate) if gate > 0.0 else INF


# 그 스킬이 실제로 나가는 최소 간격(초) = 클라 게이트. 🔴 원본 `cooldown_s`가 아니다(netreview C-2).
func _gate_s(s: SkillDef) -> float:
	return CombatMath.skill_cast_gap_s(s.cooldown_s)


# 첫 타 ~ 마지막 타의 간격(초). 단발이면 0 = 다단 도입 전과 항등.
func _cast_span_s(s: SkillDef) -> float:
	var hits := CombatMath.clamp_skill_hit_count(s.hit_count)
	if hits <= 1:
		return 0.0
	return float(hits - 1) * CombatMath.clamp_skill_hit_interval(s.hit_interval_s)


# `data/enemies` 전수에서 가장 작은 몸 판정 반경 — 🔴 **터널링 불변식의 분자에 들어간다.**
#   값을 여기 적지 않고 스캔하는 이유: 다음 사람이 `body_radius`가 작은 적을 넣으면 **그 순간**
#   불변식이 다시 계산돼 빨개진다(적어 두면 데이터와 갈라진 채 초록이다 — 화살 주석이 경고하는
#   *"body_radius 0인 적을 넣으면 부등식이 깨진다"* 가 바로 이 자리다).
func _min_enemy_body_radius() -> float:
	var lo := INF
	for f: String in DirAccess.get_files_at("res://data/enemies"):
		var base := f.trim_suffix(".remap")
		if base.get_extension() != "tres":
			continue
		var e := load("res://data/enemies/%s" % base) as EnemyDef
		if e == null:
			continue
		lo = minf(lo, e.body_radius)
	return lo


func _initialize() -> void:
	var failures := 0

	# ══════════════════════════════════════════════════════════════════
	# `data/skills` 전수 — 🔴 스킬이 늘면 여기가 자동으로 그것도 검사한다
	# ══════════════════════════════════════════════════════════════════
	var min_body := _min_enemy_body_radius()
	var scanned := 0
	var over_dps := ""       # ⑴ 초당 배율 예산 초과
	var clamped_mult := ""   # ⑵ 배율이 조용히 잘린다
	var clamped_radius := ""
	var clamped_length := ""
	var clamped_cd := ""
	var bad_shape := ""      # ⑶ 모르는 형태
	var zero_beam := ""      # ⑶ beam인데 사거리 0 = 아무도 안 맞는다
	var zero_radius := ""    # ⑶ 반경 0 = spin은 아무도 안 맞고 beam은 띠가 선이 된다
	var bad_windup := ""     # 음수·비유한 선딜 = 발동이 영영 안 오거나 즉시 두 번 온다
	var bad_id := ""         # 파일명 ↔ id 관례 (복붙 사고 검출)
	var no_icon := ""        # ⑸
	var clamped_hits := ""   # ⑵ 타수가 조용히 잘린다
	var clamped_gap := ""    # ⑵ 타 간격이 조용히 잘린다
	var long_span := ""      # ⑹ 다단이 쿨다운을 잡아먹는다
	var clamped_tspeed := "" # ⑵ 이동 속도가 조용히 잘린다
	var clamped_tdist := ""  # ⑵ 이동 거리가 조용히 잘린다
	var half_travel := ""    # ⑺ 속도·거리 중 **하나만** 적었다 = is_travel()이 false = 조용히 제자리
	var travel_multi := ""   # ⑻ 이동형 + 다단이 동시에 켜짐 = 어느 모델인지 아무도 모른다
	var tunnel := ""         # ⑼ 프레임당 전진 ≥ 최소 명중 지름 = 적을 통과한다(에러 0)
	var worst_step := 0.0    # (전진 ÷ 최소 명중 지름) 최댓값
	var worst_step_id := "없음"
	var travel_count := 0
	var worst_dps := 0.0
	var worst_dps_id := "없음"
	var worst_span := 0.0
	var worst_span_id := "없음"

	for f: String in DirAccess.get_files_at("res://data/skills"):
		var base := f.trim_suffix(".remap")   # 익스포트 빌드는 .remap 사이드카가 붙는다
		if base.get_extension() != "tres":
			continue
		var s := load("res://data/skills/%s" % base) as SkillDef
		if s == null:
			continue
		scanned += 1

		# ⑴ 🔴 **밸런스 상한 — clamp가 아니라 여기가 유일한 방어다**(CombatMath 주석이 근거).
		#    전사 평타가 배율 기준 초당 2.5를 내므로 0.30이면 스킬 기여가 그 12% 이내다.
		# 🔴🔴 **분모는 「게임이 실제로 내는 발동 간격」이어야 한다 = `skill_cast_gap_s`**
		#    (netreview C-2 2026-08-02). 원본 `cooldown_s`로 나누면 **테스트가 게임이 하지 않는 쪽을
		#    잰다** — 실제 간격이 그보다 짧으면 실효 DPS가 예산을 넘긴 채 초록이 된다. 이 파일이
		#    겨누는 실패 형태(rules §3 N-1 「선택 지표와 소비 지점은 같은 함수여야 한다」)의 시간축
		#    판박이라, 두 값이 같은 함수를 지나게 해서 구조로 닫는다.
		# 🔴🔴 **분자도 「그 스킬이 실제로 내는 총 배율」이어야 한다 = `skill_total_mult`**
		#    (다단 도입 2026-08-02). `damage_mult`만 보면 그것은 **타당** 배율이라(SkillDef 헤더)
		#    5타 스킬의 화력을 **5배 과소평가**한다 — 「환영검무」는 실제 2.5인데 0.5로 읽혔다.
		#    분모(`skill_cast_gap_s`)를 고친 것과 **정확히 같은 실패 형태**이고(N-1: 선택 지표와
		#    소비 지점이 같은 함수여야 한다), 이번엔 시간축이 아니라 화력축이다.
		var dps_add := _dps_add(s)
		if dps_add > worst_dps:
			worst_dps = dps_add
			worst_dps_id = s.id
		if dps_add > CombatMath.SKILL_DPS_ADD_MAX + 0.0001:
			over_dps += "%s(%.3f) " % [s.id, dps_add]

		# ⑹ 🔴 **다단의 총 시전 길이가 쿨다운을 잡아먹으면 안 된다.** 첫 타 ~ 마지막 타의 간격이
		#    발동 게이트에 가까워지면 다음 시전이 **아직 안 끝난 다단 위로** 떨어지는데, 호스트
		#    (`combat_authority._skill_ticks`)도 클라 FX(`player._skill_fx_*`)도 **시전자당 한 칸**이라
		#    남은 타가 통째로 버려진다 = 데이터에 적은 타수가 화면·판정 어디에도 안 나온다(에러 0).
		var span := _cast_span_s(s)
		var span_ratio := (span / _gate_s(s)) if _gate_s(s) > 0.0 else INF
		if span_ratio > worst_span:
			worst_span = span_ratio
			worst_span_id = s.id
		if span_ratio > MAX_SPAN_RATIO:
			long_span += "%s(%.2fs/%.2f) " % [s.id, span, span_ratio]

		# ⑵ 🔴 `clamped == raw` — 상한 값을 복제하지 않고도 「조용히 잘렸다」를 잡는다.
		if not is_equal_approx(CombatMath.clamp_skill_mult(s.damage_mult), s.damage_mult):
			clamped_mult += "%s " % s.id
		if not is_equal_approx(CombatMath.clamp_skill_radius(s.radius), s.radius):
			clamped_radius += "%s " % s.id
		if not is_equal_approx(CombatMath.clamp_skill_cooldown(s.cooldown_s), s.cooldown_s):
			clamped_cd += "%s " % s.id
		# ⚠ length는 **beam에서만** 의미가 있다(spin은 무시된다) — spin의 0을 위반으로 세지 않는다.
		if s.is_beam() and not is_equal_approx(CombatMath.clamp_skill_length(s.length), s.length):
			clamped_length += "%s " % s.id
		# 다단 두 칸도 같은 `clamped == raw` 관용구로 — 상한 **값**은 여기 복제하지 않는다.
		if CombatMath.clamp_skill_hit_count(s.hit_count) != s.hit_count:
			clamped_hits += "%s(%d) " % [s.id, s.hit_count]
		# ⚠ 간격은 **다단에서만** 의미가 있다(1타는 안 쓴다) — length ↔ beam과 같은 게이트다.
		if s.hit_count > 1 \
				and not is_equal_approx(CombatMath.clamp_skill_hit_interval(s.hit_interval_s), s.hit_interval_s):
			clamped_gap += "%s(%.3f) " % [s.id, s.hit_interval_s]

		# --- 이동형 (2026-08-02 「월륜」) ---
		# ⑵ 같은 `clamped == raw` 관용구 — 상한 **값**은 여기 복제하지 않는다.
		if not is_equal_approx(
				CombatMath.clamp_skill_travel_speed(s.travel_speed), s.travel_speed):
			clamped_tspeed += "%s(%.1f) " % [s.id, s.travel_speed]
		if not is_equal_approx(
				CombatMath.clamp_skill_travel_dist(s.travel_dist), s.travel_dist):
			clamped_tdist += "%s(%.1f) " % [s.id, s.travel_dist]
		# ⑺ 🔴 **속도·거리는 한 쌍이다** — `is_travel()`이 둘 다 > 0을 요구하므로 하나만 적으면
		#    **에러 없이 제자리 스킬로 떨어진다**(데이터에는 "날아간다"고 적혀 있는데 안 날아간다).
		if (s.travel_speed > 0.0) != (s.travel_dist > 0.0):
			half_travel += "%s(속도 %.1f · 거리 %.1f) " % [s.id, s.travel_speed, s.travel_dist]
		if s.is_travel():
			travel_count += 1
			# ⑻ 🔴 **두 모델이 동시에 켜지면 안 된다.** 코드는 이동형을 먼저 보고 `hit_count`를
			#    무시하지만(`SkillDef` 계약 · `_resolve_skill`), 데이터에 5타라고 적혀 있으면
			#    예산 계산(`skill_total_mult`)이 **나가지도 않는 5배**를 세고, 반대로 누군가 코드
			#    순서를 뒤집으면 그때는 **진짜로** 5배가 나간다. 어느 쪽이든 화면에 안 드러난다.
			if CombatMath.clamp_skill_hit_count(s.hit_count) > 1:
				travel_multi += "%s(%d타) " % [s.id, s.hit_count]
			# ⑼ 🔴 **터널링 불변식 — 화살(`ARROW_SPEED` 주석)의 미러다.**
			#    프레임당 전진 < 최소 명중 지름 = `2 × (판정 반경 + 가장 작은 적 body_radius)`.
			#    깨지면 검기가 적을 **통과**하고 아무 일도 안 일어난다(에러 0).
			var step_px := CombatMath.clamp_skill_travel_speed(s.travel_speed) / MIN_FPS
			var min_dia := 2.0 * (CombatMath.clamp_skill_radius(s.radius) + min_body)
			var step_ratio := (step_px / min_dia) if min_dia > 0.0 else INF
			if step_ratio > worst_step:
				worst_step = step_ratio
				worst_step_id = s.id
			if step_ratio >= 1.0:
				tunnel += "%s(%.1fpx/%.1fpx) " % [s.id, step_px, min_dia]

		# ⑶ 형태·필수 수치
		if s.shape != SkillDef.SHAPE_SPIN and s.shape != SkillDef.SHAPE_BEAM:
			bad_shape += "%s(%s) " % [s.id, s.shape]
		if s.is_beam() and s.length <= 0.0:
			zero_beam += "%s " % s.id
		if s.radius <= 0.0:
			zero_radius += "%s " % s.id
		if not is_finite(s.windup_s) or s.windup_s < 0.0:
			bad_windup += "%s " % s.id

		# 관례 — 파일명 = id (rules §4). 복붙으로 id를 안 고치면 `.tres`는 둘인데 하나로 읽힌다.
		if s.id != base.get_basename():
			bad_id += "%s≠%s " % [base.get_basename(), s.id]
		# ⑸ 아이콘 — HUD 칸이 빈 채로 뜬다(에러 없음)
		if s.icon == null:
			no_icon += "%s " % s.id

	failures += _check(scanned > 0,
		"스킬 전수: data/skills가 실제로 스캔됐다 (%d장 — 0장 = 침묵 통과)" % scanned)
	failures += _check(over_dps.is_empty(),
		"★스킬 전수 ⑴: skill_total_mult(배율×타수) ÷ skill_cast_gap_s ≤ SKILL_DPS_ADD_MAX(%.2f) — **clamp가 없는 축이라 여기가 유일한 방어다** (최대 %s = %.3f · 위반: %s)"
			% [CombatMath.SKILL_DPS_ADD_MAX, worst_dps_id, worst_dps,
				"없음" if over_dps.is_empty() else over_dps])
	failures += _check(clamped_hits.is_empty(),
		"★스킬 전수 ⑵ⓔ: hit_count가 조용히 clamp되지 않는다 — 잘리면 **데이터에 적은 타수와 실제 타수가 갈라진다**(에러 0) (위반: %s)"
			% ("없음" if clamped_hits.is_empty() else clamped_hits))
	failures += _check(clamped_gap.is_empty(),
		"★스킬 전수 ⑵ⓕ: hit_interval_s가 조용히 clamp되지 않는다 — 잘리면 FX 수명(multi_life_s)과 판정 간격이 데이터와 갈라진다 (위반: %s)"
			% ("없음" if clamped_gap.is_empty() else clamped_gap))
	failures += _check(long_span.is_empty(),
		"★스킬 전수 ⑹: 다단 총 시전 길이((타수−1)×간격)가 발동 게이트의 %.0f%% 이내 — 넘으면 다음 시전이 **안 끝난 다단을 덮어** 남은 타가 통째로 사라진다 (최악 %s = 게이트의 %.1f%% · 위반: %s)"
			% [MAX_SPAN_RATIO * 100.0, worst_span_id, worst_span * 100.0,
				"없음" if long_span.is_empty() else long_span])
	failures += _check(clamped_tspeed.is_empty(),
		"★스킬 전수 ⑵ⓖ: travel_speed가 조용히 clamp되지 않는다 — 잘리면 **FX는 원본 속도로 날고 판정은 잘린 속도로 민다** (위반: %s)"
			% ("없음" if clamped_tspeed.is_empty() else clamped_tspeed))
	failures += _check(clamped_tdist.is_empty(),
		"★스킬 전수 ⑵ⓗ: travel_dist가 조용히 clamp되지 않는다 — 잘리면 수명이 데이터보다 짧아 검기가 **적기 전에 사라진다** (위반: %s)"
			% ("없음" if clamped_tdist.is_empty() else clamped_tdist))
	failures += _check(half_travel.is_empty(),
		"★스킬 전수 ⑺: travel_speed와 travel_dist는 **한 쌍**이다(`is_travel`이 둘 다 요구) — 하나만 적으면 에러 없이 제자리 스킬로 떨어진다 (위반: %s)"
			% ("없음" if half_travel.is_empty() else half_travel))
	failures += _check(travel_multi.is_empty(),
		"★스킬 전수 ⑻: 이동형과 다단이 **동시에 켜지지 않는다** — 겹치면 어느 모델인지 아무도 모르고 예산 계산이 나가지도 않는 배율을 센다 (이동형 %d장 · 위반: %s)"
			% [travel_count, "없음" if travel_multi.is_empty() else travel_multi])
	failures += _check(tunnel.is_empty(),
		"★스킬 전수 ⑼: 터널링 — 프레임당 전진(%.0ffps 기준) < 최소 명중 지름 `2×(반경 + 최소 body_radius %.1f)`. 깨지면 검기가 적을 **통과**한다(에러 0) (최악 %s = 지름의 %.1f%% · 위반: %s)"
			% [MIN_FPS, min_body, worst_step_id, worst_step * 100.0,
				"없음" if tunnel.is_empty() else tunnel])
	failures += _check(is_finite(min_body) and min_body > 0.0,
		"★터널링 분자: data/enemies에서 최소 body_radius를 실제로 읽었다 (%.1f — INF/0이면 위 ⑼가 침묵 통과다)"
			% min_body)
	failures += _check(clamped_mult.is_empty(),
		"★스킬 전수 ⑵ⓐ: damage_mult가 조용히 clamp되지 않는다 (clamped == raw) (위반: %s)"
			% ("없음" if clamped_mult.is_empty() else clamped_mult))
	failures += _check(clamped_radius.is_empty(),
		"★스킬 전수 ⑵ⓑ: radius가 조용히 clamp되지 않는다 — 잘리면 **FX는 원본, 판정은 잘린 값**이 되어 '보이는데 안 맞는' 띠가 생긴다 (위반: %s)"
			% ("없음" if clamped_radius.is_empty() else clamped_radius))
	failures += _check(clamped_length.is_empty(),
		"★스킬 전수 ⑵ⓒ: beam length가 조용히 clamp되지 않는다 (위반: %s)"
			% ("없음" if clamped_length.is_empty() else clamped_length))
	failures += _check(clamped_cd.is_empty(),
		"★스킬 전수 ⑵ⓓ: cooldown_s가 조용히 clamp되지 않는다 — 잘리면 HUD 게이지 분모와 호스트 게이트가 갈라진다 (위반: %s)"
			% ("없음" if clamped_cd.is_empty() else clamped_cd))
	failures += _check(bad_shape.is_empty(),
		"★스킬 전수 ⑶ⓐ: shape가 아는 값이다 — 모르면 is_skill_hit이 **전부 false**(아무도 안 맞는데 에러 0) (위반: %s)"
			% ("없음" if bad_shape.is_empty() else bad_shape))
	failures += _check(zero_beam.is_empty(),
		"★스킬 전수 ⑶ⓑ: beam은 length > 0 — 0이면 띠가 점이 되어 아무도 안 맞는다(에러 0) (위반: %s)"
			% ("없음" if zero_beam.is_empty() else zero_beam))
	failures += _check(zero_radius.is_empty(),
		"★스킬 전수 ⑶ⓒ: radius > 0 (spin = 판정 원 · beam = 띠 반폭) (위반: %s)"
			% ("없음" if zero_radius.is_empty() else zero_radius))
	failures += _check(bad_windup.is_empty(),
		"스킬 전수: windup_s가 유한한 0 이상 (위반: %s)" % ("없음" if bad_windup.is_empty() else bad_windup))
	failures += _check(bad_id.is_empty(),
		"스킬 전수: 파일명 == id (rules §4 관례) (위반: %s)" % ("없음" if bad_id.is_empty() else bad_id))
	failures += _check(no_icon.is_empty(),
		"★스킬 전수 ⑸: icon이 있다 — 없으면 HUD 칸이 **빈 채로** 뜬다(에러 0) (위반: %s)"
			% ("없음" if no_icon.is_empty() else no_icon))

	# ══════════════════════════════════════════════════════════════════
	# 검출력 증명 — 위 전수는 현 데이터가 전부 통과라 "루프가 실제로 도는가"를 못 보여준다.
	# 합성 SkillDef로 각 상한이 **실제로 반응하는지** 본다 (뮤테이션 없이 검출력을 세우는 관용구).
	# ══════════════════════════════════════════════════════════════════
	var bad := SkillDef.new()
	bad.damage_mult = CombatMath.SKILL_DAMAGE_MULT_MAX + 10.0
	bad.radius = CombatMath.SKILL_RADIUS_MAX + 10.0
	bad.length = CombatMath.SKILL_LENGTH_MAX + 10.0
	bad.cooldown_s = CombatMath.SKILL_COOLDOWN_MIN - 1.0
	failures += _check(not is_equal_approx(CombatMath.clamp_skill_mult(bad.damage_mult), bad.damage_mult),
		"검출력: 상한 초과 배율은 clamped != raw로 **실제로 걸린다**")
	failures += _check(not is_equal_approx(CombatMath.clamp_skill_radius(bad.radius), bad.radius),
		"검출력: 상한 초과 반경이 걸린다")
	failures += _check(not is_equal_approx(CombatMath.clamp_skill_length(bad.length), bad.length),
		"검출력: 상한 초과 사거리가 걸린다")
	failures += _check(not is_equal_approx(CombatMath.clamp_skill_cooldown(bad.cooldown_s), bad.cooldown_s),
		"검출력: 하한 미만 쿨다운이 걸린다")
	# 🔴 **검출력 프로브도 본 단정과 같은 함수를 지난다**(`_dps_add`) — 여기서 식을 손으로 다시 쓰면
	#    "테스트가 자기 모델을 검사"하는 그 상태가 된다(rules §3 N-1).
	failures += _check(_dps_add(bad) > CombatMath.SKILL_DPS_ADD_MAX,
		"검출력: 예산 초과 조합이 ⑴ 단정에 실제로 걸린다")

	# 🔴 다단 축 검출력 — 현 데이터가 전부 통과라 "루프가 실제로 도는가"를 합성으로 세운다.
	var multi := SkillDef.new()
	multi.damage_mult = 1.0
	multi.hit_count = CombatMath.SKILL_HIT_COUNT_MAX + 3
	multi.hit_interval_s = CombatMath.SKILL_HIT_INTERVAL_MAX + 1.0
	multi.cooldown_s = CombatMath.SKILL_COOLDOWN_MIN
	failures += _check(CombatMath.clamp_skill_hit_count(multi.hit_count) != multi.hit_count,
		"검출력: 상한 초과 타수가 clamped != raw로 **실제로 걸린다**")
	failures += _check(not is_equal_approx(
			CombatMath.clamp_skill_hit_interval(multi.hit_interval_s), multi.hit_interval_s),
		"검출력: 상한 초과 타 간격이 걸린다")
	failures += _check(_cast_span_s(multi) / _gate_s(multi) > MAX_SPAN_RATIO,
		"검출력: 쿨다운을 잡아먹는 다단(%.2fs / 게이트 %.2fs)이 ⑹ 단정에 실제로 걸린다"
			% [_cast_span_s(multi), _gate_s(multi)])
	# 🔴 **총 배율이 타수를 실제로 곱하는가** — 이 한 줄이 없으면 `skill_total_mult`가 `damage_mult`를
	#    그대로 돌려주도록 퇴화해도 위 ⑴이 초록이다(현 데이터가 상한에 안 붙어 있어서).
	var single := SkillDef.new()
	single.damage_mult = 0.5
	single.hit_count = 1
	var five := SkillDef.new()
	five.damage_mult = 0.5
	five.hit_count = 5
	failures += _check(is_equal_approx(CombatMath.skill_total_mult(five),
			CombatMath.skill_total_mult(single) * 5.0),
		"★검출력: skill_total_mult가 타수를 곱한다(5타 = 단발 ×5 = %.2f) — 안 곱하면 다단 화력을 **5배 과소평가**한 채 초록이다"
			% CombatMath.skill_total_mult(five))

	# ══════════════════════════════════════════════════════════════════
	# 이동형 축 (2026-08-02 「월륜」) — 현 데이터가 전부 통과라 합성으로 검출력을 세운다
	# ══════════════════════════════════════════════════════════════════
	var tv := SkillDef.new()
	tv.travel_speed = CombatMath.SKILL_TRAVEL_SPEED_MAX + 100.0
	tv.travel_dist = CombatMath.SKILL_TRAVEL_DIST_MAX + 100.0
	failures += _check(not is_equal_approx(
			CombatMath.clamp_skill_travel_speed(tv.travel_speed), tv.travel_speed),
		"검출력: 상한 초과 이동 속도가 clamped != raw로 **실제로 걸린다**")
	failures += _check(not is_equal_approx(
			CombatMath.clamp_skill_travel_dist(tv.travel_dist), tv.travel_dist),
		"검출력: 상한 초과 이동 거리가 걸린다")
	# 🔴 **`is_travel`이 둘 다 요구하는가** — 한쪽만 보도록 퇴화하면 위 ⑺가 영영 안 걸린다.
	var half := SkillDef.new()
	half.travel_speed = 300.0
	half.travel_dist = 0.0
	failures += _check(not half.is_travel(),
		"★검출력: 속도만 있고 거리가 0이면 is_travel() = false — 이 한 줄이 ⑺ 단정의 근거다")
	half.travel_speed = 0.0
	half.travel_dist = 520.0
	failures += _check(not half.is_travel(),
		"★검출력: 거리만 있고 속도가 0이면 is_travel() = false")
	half.travel_speed = 300.0
	failures += _check(half.is_travel(), "검출력: 둘 다 있으면 is_travel() = true")

	# 🔴🔴 **표시 수명 = 판정 수명 = `skill_travel_lifetime_s` 한 함수** (§3 단일 소스).
	#   클라 FX(`player._spawn_skill_fx` → `SkillFx.setup`)와 호스트 큐(`_step_skill_travel`의 "life")가
	#   **같은 이 함수**를 부른다 — 사본을 두면 "검기는 아직 나는데 판정은 끝났다"가 되고, 그 어긋남은
	#   화면에 이유가 안 드러난다(적을 지나가는데 HP가 안 깎인다 = 지연 결함과 구분되지 않는다).
	failures += _check(is_equal_approx(CombatMath.skill_travel_lifetime_s(300.0, 520.0), 520.0 / 300.0),
		"★이동형 수명 = 거리 ÷ 속도 (%.3fs)" % CombatMath.skill_travel_lifetime_s(300.0, 520.0))
	failures += _check(is_equal_approx(CombatMath.skill_travel_lifetime_s(0.0, 520.0), 0.0),
		"★이동형 수명: 속도 0 = 0s — 제자리 스킬이 **비행 큐에 들어가지 않는다**(0이 아니면 영원히 안 끝나는 항목이 생긴다)")
	# 🔴 상한 초과 데이터로도 수명이 **잘린 값 기준**으로 나온다 = FX·판정이 같이 잘린다(둘 다 이 함수를 지나므로).
	failures += _check(is_equal_approx(
			CombatMath.skill_travel_lifetime_s(CombatMath.SKILL_TRAVEL_SPEED_MAX + 100.0,
				CombatMath.SKILL_TRAVEL_DIST_MAX + 100.0),
			CombatMath.SKILL_TRAVEL_DIST_MAX / CombatMath.SKILL_TRAVEL_SPEED_MAX),
		"★이동형 수명: 상한 초과 입력도 clamp된 값으로 계산된다(표시·판정이 함께 잘린다)")
	# 🔴 터널링 단정이 실제로 반응하는가 — ⚠ **정직한 데이터로는 못 깬다**: 속도 상한
	#   `SKILL_TRAVEL_SPEED_MAX` ÷ `MIN_FPS`가 한 걸음의 상한이고, 현재 최소 body_radius만으로도
	#   최소 명중 지름이 그보다 크다. 즉 이 축의 안전은 **지금 clamp가 이미 보장**하고 있고
	#   ⑼는 "그 전제가 무너지는 순간"(더 작은 적 · 상한 인상)을 잡는 감시다.
	#   → 그래서 **식이 반응하는지**만 상한 밖 합성 수로 확인한다(전수 단정과 같은 비교식).
	var probe_step := (CombatMath.SKILL_TRAVEL_SPEED_MAX * 6.0) / MIN_FPS
	var probe_dia := 2.0 * (1.0 + min_body)
	failures += _check(probe_step >= probe_dia,
		"★검출력: 터널링 비교식이 실제로 반응한다(합성 전진 %.1fpx ≥ 합성 지름 %.1fpx) — 실데이터 최악은 위 ⑼의 %.1f%%다"
			% [probe_step, probe_dia, worst_step * 100.0])

	# ══════════════════════════════════════════════════════════════════
	# `data/subjobs` 배선 — 🔴 ⑷ **공유 하위 직업의 스킬은 영원히 안 켜진다**
	# ══════════════════════════════════════════════════════════════════
	# `GameState.main_skill_of` → `main_slot_def`가 공유(`series_id == "*"`)를 배제한다(메인 자리는
	# 계열 전용, GDD §5). 데이터에 적어 두면 **에러 없이** 아무 일도 안 일어난다.
	var shared_with_skill := ""
	var subjob_scanned := 0
	var with_skill := 0
	for f2: String in DirAccess.get_files_at("res://data/subjobs"):
		var base2 := f2.trim_suffix(".remap")
		if base2.get_extension() != "tres":
			continue
		var sj := load("res://data/subjobs/%s" % base2) as SubJobDef
		if sj == null:
			continue
		subjob_scanned += 1
		if sj.skill == null:
			continue
		with_skill += 1
		if sj.is_shared():
			shared_with_skill += "%s " % sj.id
	failures += _check(subjob_scanned > 0,
		"하위 직업 전수: data/subjobs가 실제로 스캔됐다 (%d장)" % subjob_scanned)
	failures += _check(shared_with_skill.is_empty(),
		"★하위 직업 전수 ⑷: 공유 하위 직업에 스킬이 없다 — 있으면 `main_slot_def`가 배제해 **영원히 안 켜진다**(에러 0) (위반: %s)"
			% ("없음" if shared_with_skill.is_empty() else shared_with_skill))
	# 사용자 확정(2026-08-02) = 광전사·검성 둘만. ⚠ **개수를 못 박지 않는다** — 늘리는 것이 이 축의
	#   목적이라(하위 직업마다 하나씩) 개수 단정은 정상 확장에서 빨개진다. "0이 아니다"만 본다.
	failures += _check(with_skill > 0,
		"하위 직업 전수: 스킬이 물린 하위 직업이 실제로 있다 (%d개 — 0개면 배선이 통째로 끊긴 것)" % with_skill)

	# ══════════════════════════════════════════════════════════════════
	# 판정 기하 `is_skill_hit` — 🔴 로컬 FX(skill_fx.gdshader)가 **이 조건을 그대로 그린다**
	# ══════════════════════════════════════════════════════════════════
	var c := Vector2.ZERO
	var right := Vector2.RIGHT
	# spin = 시전자 중심 원 (≡ is_strike_hit) — 방향과 무관해야 한다
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_SPIN, Vector2(99.9, 0.0), c, right, 100.0, 0.0),
		"spin: 반경 안(99.9) 허용")
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_SPIN, Vector2(100.0, 0.0), c, right, 100.0, 0.0),
		"spin: 경계선(100.0) 허용")
	failures += _check(not CombatMath.is_skill_hit(SkillDef.SHAPE_SPIN, Vector2(100.1, 0.0), c, right, 100.0, 0.0),
		"spin: 반경 밖(100.1) 거부")
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_SPIN, Vector2(-100.0, 0.0), c, right, 100.0, 0.0),
		"★spin: 등 뒤도 맞는다(360°) — 방향은 spin 판정에 관여하지 않는다")
	# 몸 반경·슬랙은 **넓히는 쪽**으로만 더해진다
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_SPIN, Vector2(110.0, 0.0), c, right, 100.0, 0.0, 10.0),
		"spin: 적 body_radius(10)가 더해진다")
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_SPIN, Vector2(115.0, 0.0), c, right, 100.0, 0.0, 10.0, 5.0),
		"★spin: 몹 지연 슬랙(5)이 더해진다 — 없으면 게스트의 정직한 발동이 **무음 거부**된다")
	# beam = 전방 캡슐 (≡ capsule_depth >= 0)
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_BEAM, Vector2(200.0, 0.0), c, right, 20.0, 220.0),
		"beam: 축 위 사거리 안(200) 허용")
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_BEAM, Vector2(200.0, 20.0), c, right, 20.0, 220.0),
		"beam: 반폭 경계(±20) 허용")
	failures += _check(not CombatMath.is_skill_hit(SkillDef.SHAPE_BEAM, Vector2(200.0, 20.1), c, right, 20.0, 220.0),
		"beam: 반폭 밖(20.1) 거부")
	failures += _check(not CombatMath.is_skill_hit(SkillDef.SHAPE_BEAM, Vector2(241.0, 0.0), c, right, 20.0, 220.0),
		"beam: 사거리 밖(241 > 220+20) 거부")
	failures += _check(not CombatMath.is_skill_hit(SkillDef.SHAPE_BEAM, Vector2(-100.0, 0.0), c, right, 20.0, 220.0),
		"beam: 등 뒤 100px는 안 맞는다(반폭 20 · 몸반경 0 · 슬랙 0)")
	# 🔴 **위 단정을 "등 뒤는 안 맞는다"로 읽지 마라 — 게임 조건에서는 거짓이다**(netreview I-3).
	#   캡슐은 시작단에도 반구가 있어 후방 도달 = `반폭 + body_radius + slack`이다. 보스(반경 63)에
	#   최악 슬랙(27)이면 **시전자 뒤 110px까지 맞는다.** 의도된 성질이고(캡슐을 쓰는 대가) 대상이
	#   NPC라 안전하지만, 문구가 "축이 곧 판정"이라고 단언하면 다음 사람이 후방 안전지대를 믿는다.
	failures += _check(CombatMath.is_skill_hit(SkillDef.SHAPE_BEAM, Vector2(-100.0, 0.0), c, right, 20.0, 220.0, 63.0, 27.0),
		"★beam: 몸반경+슬랙이 붙으면 **등 뒤 110px도 맞는다** — 후방 안전지대는 없다")
	failures += _check(not CombatMath.is_skill_hit(SkillDef.SHAPE_BEAM, Vector2(10.0, 0.0), c, Vector2.ZERO, 20.0, 220.0),
		"★beam: 방향 0 = 거부 — 길이 0 캡슐이 **원이 되어** 등 뒤까지 맞는 것을 막는다")
	failures += _check(not CombatMath.is_skill_hit("bogus", Vector2(1.0, 0.0), c, right, 100.0, 100.0),
		"★모르는 shape = false(안 맞는 쪽 폴백) — 데이터 오타가 판정을 **넓히지** 않는다")

	# 🔴🔴 **클라 게이트가 호스트 게이트보다 「수신 프레임 양자화」만큼은 늦어야 한다** (netreview C-1).
	#   이것이 없어서 두 게이트가 같은 문턱을 쓰던 시절이 있었고, 그때 게스트는 게이지가 0을 찍는
	#   순간 Q를 누르면 **대략 절반이 무음 거부**되면서 쿨다운 8~9초를 통째로 잃었다(호스트는 동기
	#   호출이라 영향 0 = "호스트 화면에서는 완벽한 버그"). 발사 경로의 같은 트립와이어를 미러한다.
	for cd_probe: float in [3.0, 8.0, 9.0, 20.0]:
		var client_gap := CombatMath.skill_cast_gap_s(cd_probe)
		var host_gate := CombatMath.clamp_skill_cooldown(cd_probe) * CombatMath.FIRE_RATE_SLACK
		failures += _check(client_gap >= host_gate + CombatMath.AUTO_FIRE_HOST_FRAME_S,
			"★클라 게이트(%.3fs) ≥ 호스트(%.3fs) + 프레임(%.3fs) — cd %.1f" \
				% [client_gap, host_gate, CombatMath.AUTO_FIRE_HOST_FRAME_S, cd_probe])
		# 편도 변동 최악(`LAG_MAX_ONE_WAY_MS`)까지 덮는지 — 이 여유가 곧 "정직한 발동이 산다"의 폭이다.
		failures += _check(client_gap - host_gate >= float(CombatMath.LAG_MAX_ONE_WAY_MS) / 1000.0,
			"★여유(%.3fs)가 편도 변동 상한(%dms)을 덮는다 — cd %.1f" \
				% [client_gap - host_gate, CombatMath.LAG_MAX_ONE_WAY_MS, cd_probe])

	# 발동률 게이트 — 로컬(HUD·player)과 호스트가 **같은 함수**를 지난다(§3)
	var cd9 := 9.0
	var gate_ms := int(cd9 * CombatMath.FIRE_RATE_SLACK * 1000.0)
	failures += _check(not CombatMath.is_skill_ready(1000, 1000 + gate_ms - 1, cd9),
		"is_skill_ready: 게이트 직전(%dms) 거부" % (gate_ms - 1))
	failures += _check(CombatMath.is_skill_ready(1000, 1000 + gate_ms, cd9),
		"is_skill_ready: 게이트 경과(%dms) 허용" % gate_ms)
	failures += _check(CombatMath.is_skill_ready(-1000000000, 0, cd9),
		"★is_skill_ready: 최초 발동(앵커 미설정)은 즉시 허용 — 씬 입장마다 1회가 준비돼 있다")
	# 🔴 하한이 실제로 게이트를 올리는가 — `SKILL_COOLDOWN_MIN` 미만을 적어도 그 아래로는 안 내려간다
	var min_gate := int(CombatMath.SKILL_COOLDOWN_MIN * CombatMath.FIRE_RATE_SLACK * 1000.0)
	failures += _check(not CombatMath.is_skill_ready(1000, 1000 + min_gate - 1, 0.01),
		"★is_skill_ready: 쿨 0.01s를 주장해도 SKILL_COOLDOWN_MIN 게이트 아래로는 못 내려간다")

	if failures == 0:
		print("TEST_OK skill")
		quit(0)
	else:
		printerr("TEST_FAIL skill — %d개 실패" % failures)
		quit(1)


func _check(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	printerr("  FAIL %s" % label)
	return 1
