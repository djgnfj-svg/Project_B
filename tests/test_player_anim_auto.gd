extends SceneTree
# 몸통 애니 데이터 계약 전수 — 🔴 **rules §5의 "애니 클립을 손대면 `play(...)`·`autoplay`를 grep해
#   이름 집합을 대조해라"를 자동화한 자리다** (콤보 타수별 공격 애니 2026-08-01).
#
# 🔴 **왜 필요한가: 이 축은 전부 「에러 없이 화면만 어긋난다」이다.**
#   · 이름이 없으면 `AnimatedSprite2D`가 조용히 아무것도 안 바꾼다 → 캐릭터가 옛 클립에 얼어붙는다.
#   · 방향 접미사가 일부만 있으면 **그 방향에서만** 안 나온다(정면만 멀쩡해 테스트 플레이에서 안 걸린다).
#   · `loop`가 반대면 공격이 창 안에서 다시 시작하거나 구르기가 영영 돈다.
#   · `roll` 길이가 `ROLL_TIME_S`와 어긋나면 **마지막 프레임에 얼어붙는다**(rules §3 미러).
#
# ⚠ **`player.gd`는 씬 글루라 `-s`가 preload를 못 한다** — 그래서 이 테스트는 코드를 부르지 않고
#   **데이터가 만족해야 하는 계약**만 본다(J-1·J-2와 같은 규율). 아래 `REQUIRED_BASES`·`COMBO_BASES`는
#   `player._update_anim`/`_attack_anim_base`가 부르는 이름과 **미러**다 — 코드에서 새 base를 부르기
#   시작하면 여기 추가해라(추가를 잊으면 이 테스트가 그 클립을 안 지킬 뿐, 거짓 통과는 아니다).

# `_play_dir_anim`이 붙이는 접미사 — ⚠ `player.DIR_SUFFIX`와 미러. "w"(서)는 **동을 flip해 쓰므로
# 시트에 존재하지 않는다** — 그래서 요구 집합에서 빼야 한다(넣으면 정상 시트가 빨개진다).
const DIR_SUFFIXES: Array[String] = ["e", "s", "n"]
# 몸통 애니가 없으면 캐릭터가 통째로 얼어붙는 base — 모든 직업 시트가 반드시 갖는다.
const REQUIRED_BASES: Array[StringName] = [&"idle", &"run", &"roll"]
# 콤보 타수별 공격 클립 — **all-or-nothing**이어야 한다(근거는 아래 ⑶).
const COMBO_BASES: Array[StringName] = [&"attack1", &"attack2", &"attack3"]
# loop 규약 — 도는 것 / 한 번만 도는 것.
const LOOPING_BASES: Array[StringName] = [&"idle", &"run"]
const ONESHOT_BASES: Array[StringName] = [&"roll", &"attack", &"attack1", &"attack2", &"attack3"]


func _init() -> void:
	var failures := 0
	var jobs := 0
	var sheets_with_combo := 0
	for jf: String in DirAccess.get_files_at("res://data/jobs"):
		var jbase := jf.trim_suffix(".remap")
		if jbase.get_extension() != "tres":
			continue
		var job := load("res://data/jobs/%s" % jbase) as JobDef
		if job == null:
			continue
		jobs += 1
		var sf := job.frames
		failures += _check(sf != null, "%s: frames가 지정돼 있다" % job.id)
		if sf == null:
			continue

		# ⑴ 🔴 **필수 base가 `_play_dir_anim`의 조회 규칙으로 resolve 되는가.**
		#    그 규칙 = `base_<접미사>`를 먼저 보고, 없으면 무접미사 `base`로 폴백. 둘 다 없으면
		#    `play()`가 아예 안 불려 **직전 클립에 얼어붙는다**(에러 0).
		for b: StringName in REQUIRED_BASES:
			failures += _check(_resolves(sf, b),
				"%s: 필수 애니 `%s`가 방향판 또는 무접미사로 존재한다" % [job.id, b])

		# ⑵ 🔴 **방향판은 세트로 있어야 한다 — 일부만 있으면 그 방향에서만 조용히 안 나온다.**
		#    무접미사 폴백이 있으면 면제된다(그쪽으로 떨어지므로 화면이 빈 적이 없다).
		#    ⚠ 이것이 "정면만 보고 테스트 플레이했더니 멀쩡하더라"를 잡는 유일한 자동 검사다.
		var partial: Array[String] = []
		for b2: StringName in (REQUIRED_BASES + COMBO_BASES + [&"attack"] as Array[StringName]):
			if sf.has_animation(b2):
				continue  # 무접미사 폴백 보유 — 어느 방향이든 최소한 뭔가 나온다
			var have := 0
			for s: String in DIR_SUFFIXES:
				if sf.has_animation(StringName(String(b2) + "_" + s)):
					have += 1
			if have > 0 and have < DIR_SUFFIXES.size():
				partial.append("%s(%d/%d)" % [b2, have, DIR_SUFFIXES.size()])
		failures += _check(partial.is_empty(),
			"%s: 방향판이 부분만 있는 base 없음 — 있으면 그 방향에서만 안 나온다 (%s)"
				% [job.id, ", ".join(partial)])

		# ⑶ 🔴 **콤보 공격 클립은 all-or-nothing.** 셋 중 일부만 있으면 `_attack_anim_base`의 폴백이
		#    조용히 `attack1`로 뭉쳐 **마무리 타와 되돌려 베기가 평타와 같은 그림**이 된다 —
		#    "판정은 마무리인데 몸은 평타"의 약한 판이고, 화면에 이유가 안 드러난다.
		var combo_have := 0
		for b3: StringName in COMBO_BASES:
			if _resolves(sf, b3):
				combo_have += 1
		failures += _check(combo_have == 0 or combo_have == COMBO_BASES.size(),
			"%s: 콤보 공격 클립이 전무하거나 3종 전부다 (현재 %d/3)" % [job.id, combo_have])
		if combo_have == COMBO_BASES.size():
			sheets_with_combo += 1

		# ⑷ 🔴 **`roll` 길이 ↔ `CombatMath.ROLL_TIME_S` 미러** (rules §3이 명시한 부채).
		#    구르기에는 `speed_scale` 유도가 **없다**(`ROLL_TIME_S`가 상수라 미러가 성립한다) —
		#    그래서 시트가 어긋나면 그대로 어긋난다: 짧으면 **마지막 프레임에 얼어붙고**, 길면 잘린다.
		#    ⚠ 공격 클립에는 이 단정을 걸지 마라 — 그쪽은 `swing_time`이 무기별·haste별로 달라
		#      **고정 길이가 성립할 수 없고**, 그래서 코드가 매 스윙 배율을 유도한다.
		for s2: String in DIR_SUFFIXES:
			var roll_name := StringName("roll_" + s2)
			if not sf.has_animation(roll_name):
				continue
			var len_s := _anim_length(sf, roll_name)
			failures += _check(is_equal_approx(len_s, CombatMath.ROLL_TIME_S),
				"%s: `%s` 길이 %.3fs == ROLL_TIME_S %.3fs (어긋나면 마지막 프레임에 얼어붙는다)"
					% [job.id, roll_name, len_s, CombatMath.ROLL_TIME_S])
		if sf.has_animation(&"roll"):
			var len_bare := _anim_length(sf, &"roll")
			failures += _check(is_equal_approx(len_bare, CombatMath.ROLL_TIME_S),
				"%s: `roll` 길이 %.3fs == ROLL_TIME_S %.3fs" % [job.id, len_bare, CombatMath.ROLL_TIME_S])

		# ⑸ loop 규약 — 반대면 공격이 창 안에서 다시 시작하거나 구르기가 영영 돈다.
		var loop_bad: Array[String] = []
		for name_i: StringName in sf.get_animation_names():
			var base := _base_of(name_i)
			if base in LOOPING_BASES and not sf.get_animation_loop(name_i):
				loop_bad.append("%s(loop=false여야 아님)" % name_i)
			elif base in ONESHOT_BASES and sf.get_animation_loop(name_i):
				loop_bad.append("%s(loop=true)" % name_i)
		failures += _check(loop_bad.is_empty(),
			"%s: loop 규약 — idle/run은 반복 · roll/attack*은 1회 (%s)" % [job.id, ", ".join(loop_bad)])

		# ⑹ 🔴 **길이가 0인 클립이 없는가.** 0이면 `_anim_speed_scale_for`가 **1.0 항등으로 폴백**해
		#    미러가 조용히 꺼진다("배율이 왜 안 걸리지"). 프레임 0·speed 0 둘 다 여기서 걸린다.
		var zero_len: Array[String] = []
		for name_j: StringName in sf.get_animation_names():
			if _anim_length(sf, name_j) <= 0.0:
				zero_len.append(String(name_j))
		failures += _check(zero_len.is_empty(),
			"%s: 길이 0인 클립 없음 — 0이면 speed_scale 유도가 조용히 항등으로 꺼진다 (%s)"
				% [job.id, ", ".join(zero_len)])

	failures += _check(jobs > 0, "★검출력: data/jobs를 실제로 순회했다 (0건이면 위 전부가 침묵 통과다)")
	failures += _check(sheets_with_combo > 0,
		"★검출력: 콤보 공격 클립 3종을 가진 시트가 최소 1장 존재한다 (0장이면 ⑶이 공허하게 통과한다)")

	if failures == 0:
		print("TEST_OK player_anim")
		quit(0)
	else:
		printerr("TEST_FAIL player_anim — %d개 실패" % failures)
		quit(1)


# `_play_dir_anim`의 조회 규칙 미러 — 방향판 하나라도 있거나 무접미사판이 있으면 resolve 된다.
func _resolves(sf: SpriteFrames, base: StringName) -> bool:
	if sf.has_animation(base):
		return true
	for s: String in DIR_SUFFIXES:
		if sf.has_animation(StringName(String(base) + "_" + s)):
			return true
	return false


# "attack1_e" → "attack1" · "idle" → "idle". 접미사가 아는 값일 때만 자른다(임의 `_` 이름 보호).
func _base_of(anim: StringName) -> StringName:
	var s := String(anim)
	for suf: String in DIR_SUFFIXES:
		if s.ends_with("_" + suf):
			return StringName(s.substr(0, s.length() - suf.length() - 1))
	return anim


# 클립 총 길이(s) = Σ프레임 duration ÷ speed. ⚠ `boss._anim_base_length`·`player._anim_speed_scale_for`와
# 같은 식이다 — 프레임 수만 세면 duration이 1.0이 아닌 시트에서 갈라진다.
func _anim_length(sf: SpriteFrames, anim: StringName) -> float:
	var spd := sf.get_animation_speed(anim)
	var count := sf.get_frame_count(anim)
	if spd <= 0.0 or count <= 0:
		return 0.0
	var total := 0.0
	for i: int in count:
		total += sf.get_frame_duration(anim, i)
	return total / spd


func _check(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	printerr("  FAIL %s" % label)
	return 1
