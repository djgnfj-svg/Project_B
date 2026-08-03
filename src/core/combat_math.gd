class_name CombatMath
extends RefCounted
# 전투 수치 계산 — 단일 소스 (projectb-rules §3 하드 계약).
# UI 표시·실전투(호스트 확정)가 전부 이 함수만 부른다. 다른 곳에서 같은 계산을 만들면 갈라진다.


# 최종 데미지. bonus_attack = 착용 장비 공격 합(total_stats.attack). 미착용=0 → 기존 동작과 동일(항등 폴백).
static func calc_damage(job: JobDef, bonus_attack: int = 0) -> int:
	return job.attack_damage + bonus_attack


# --- 메인 전용 특성: 검기 파형(평타 사거리) — 단일 소스 (§3) ---
# GDD §5·§6 v1.9: **메인** 하위 직업의 특성만 발동한다(서브는 5스탯만 합산된다).
# 🔴 레벨로 자라지 않는 켜짐/꺼짐 값이라 LEVEL_STAT_KEYS 루프에 **얹지 않는다** — 얹으면 서브 가중(×0.4)이
#   곱해져 "메인 전용"이 조용히 깨지고, 레벨 곱까지 타 예산 밖 스탯이 레벨 스탯 상한 검증에 섞인다.
# 🔴 아래 사거리 3함수(is_hit_in_reach·attack_center_offset·attack_radius)는 **전부 이 함수를 지난다.**
#   haste_scale과 같은 이유다 — 배율 함수를 공유하는 것 자체가 "맞는 곳 = 보이는 곳" 계약의 증명이고,
#   한 곳이라도 job.attack_range를 직접 읽으면 파형이 판정과 표시 중 한쪽에만 걸린다.
const MAX_REACH_BONUS := 0.5  # 하드 상한 +50% (GDD §6) — 근접이 원거리가 되는 것 + 공지 스푸핑 차단


# --- 하위 직업 특성 카탈로그 (GDD v2.0 §6) — 단일 소스 (§3) ---
# 🔴 특성 = **(효과 키, 값)** 이다. 키마다 적용 지점이 **1곳**뿐이고, 새 하위 직업이 기존 키를
#   재사용하면 순수 데이터 한 장이다(rules §4). 키를 늘릴 때만 코드가 늘어난다.
# 와이어/데이터 공용 키 = 아래 문자열 **그대로**(SubJobDef.main/sub_trait_key · clamp 키).
#   LEVEL_STAT_KEYS와 같은 관용구 — 별도 매핑 표를 만들면 그게 두 번째 진실원이 되어 갈라진다.
# 🔒 여기 들어올 수 있는 것 = **합계 데미지에 곱해지지 않는 축**뿐이다(GDD §6 예산).
#   공격력·체력(장비 축)·공속·치명(5스탯 축)을 키로 추가하는 변경은 기획 변경이 선행 조건이다.
const TRAIT_KEYS: Array[String] = ["reach", "roll_cd", "roll_dist", "campfire_heal", "kill_move", "drop_find", "proj_range", "auto_fire"]

# 키별 **하드 상한** — 같은 키를 메인·서브가 같이 밀면 합산된 뒤 여기서 잘린다.
# 🔴 상한을 두는 이유는 키마다 다르다(GDD §6에 근거를 남겼다):
#   reach — 무한이면 근접이 원거리가 되어 "직업 = 플레이 방식의 변환"이 무너진다(전사 42 → 63).
#   roll_cd — 🔴 **가장 인색하게 잡는다.** i-frame 창 0.37s(ROLL_TIME_S + GRACE) / 쿨 0.8s이라
#     **정직한 플레이의 무적 시간이 이미 46%**다. −30%면 0.56s 쿨 = 66%, −40%면 0.48s = 77%로
#     사실상 상시 무적이 되어 §5 "패턴을 읽고 구른다"가 "계속 구른다"가 된다.
#     ⚠ **호스트 게이트 기준으로는 더 높다** — `is_roll_grant_ok`가 지터 여유로 ×0.9를 곱하므로
#     연타하는 클라의 상한은 특성 0에서 370/720 = **51%**, −30%에서 370/504 = **73%**다.
#     (그 여유는 지연 환경에서 정당한 구르기를 거부하지 않기 위한 것 — 협동 2인이라 수용한다.
#      이 축을 더 열 때는 66%가 아니라 **73% 쪽 숫자**를 기준으로 봐라.)
#   나머지 — 자원·회복·기동이라 상한은 "데이터 실수와 공지 스푸핑 차단"이 목적이다.
const TRAIT_MAX: Dictionary = {
	"reach": MAX_REACH_BONUS,  # 평타 사거리 증가율
	"roll_cd": 0.3,            # 구르기 쿨다운 **감소**율 (0.3 = −30%)
	"roll_dist": 0.3,          # 구르기 거리 증가율 — 🔴 원격 변위 clamp도 같이 유도한다(§3 이동속도 계약)
	"campfire_heal": 0.6,      # 모닥불 회복 속도 증가율
	# 🔴 kill_move는 5스탯 `move`와 **같은 축이라 더해진 뒤 함께** LEVEL_STAT_MAX["move"](0.3)에서 잘린다
	#   (`player._move_speed`). 그래서 상한을 그 여유 안쪽으로 좁게 잡는다 — 넓게 잡으면 이속을 키운
	#   플레이어에게서 「광란」이 조용히 사라진다(표시는 +15%인데 실제 0). 이 부등식은
	#   test_game_state_auto의 트립와이어가 지킨다: 데이터 최대 move + 이 값 ≤ LEVEL_STAT_MAX["move"].
	#   ⚠ 별도 축으로 분리하고 싶으면 LAG_MAX_LEAD_DIST를 함께 재유도해야 한다(115 → ~150).
	"kill_move": 0.15,         # 적 처치 후 일시 이동속도 증가율
	"drop_find": 0.3,          # 골드·재료 드랍량 증가율
	# 투사체 사거리 증가율 — 근접 reach의 원거리 대칭(reach는 근접 3함수 전용이라 활·지팡이엔 안 걸린다).
	# 🔴 **상한 근거는 `MAX_ARROW_RANGE`(480)다** — 데이터상 최장 원거리 무기 iron_staff(arrow_range 260)가
	#   260 × 1.5 = 390 < 480이라 정당한 무기가 `clamp_arrow_range`에서 **조용히 절삭되지 않는다**.
	#   ⚠ 화면 해상도(640×360)에서 유도하지 마라 — GDD §9에서 아직 TBD라, 미확정 값이 판정 기하의 근거로
	#   승격된다. `test_combat_math_auto`가 이 부등식을 원거리 무기 전수로 지킨다(넘으면 빨개진다).
	# ⚠ 값이 MAX_REACH_BONUS와 같지만 **별칭으로 묶지 않는다** — 근거가 다른 축이라(근접은 "직업 = 플레이
	#   방식" 경계, 여기는 절삭 여유) 별칭으로 두면 한쪽 튜닝이 다른 쪽을 조용히 움직인다.
	"proj_range": 0.5,
	# 🔴 **첫 on/off 축이다** — 나머지 7개는 전부 비율인데 이것만 "켜짐/꺼짐"이다(상한 1.0 = 켜짐).
	#   판정은 `is_trait_on` 하나로만 한다(아래) — 호출부에서 `> 0.0`을 직접 쓰면 다음 사람이 `>=`로
	#   적는 순간 0.0(= 특성 없음)이 켜진 것으로 읽힌다.
	# 🔴 **화력 예산 밖인 근거**: 발사 간격은 여전히 `effective_cooldown`이 정하고 호스트 게이트
	#   (`is_fire_rate_ok`)도 그대로다 — 이 키가 여는 것은 **입력 유지 방식**(탭 연타 → 홀드)뿐이라
	#   DPS **상한**이 안 움직인다. 움직이는 것은 그 상한에 도달하는 난이도다.
	#   ⚠ 대신 홀드 중에는 콤보를 전진시키지 않는다(player `_local_combat`) — 안 그러면 마무리 타
	#   (사거리 2배·데미지 2.5배)가 자동으로 무한 반복돼 그때는 진짜로 예산 밖이 된다.
	"auto_fire": 1.0,
}
# on/off 축 — 값이 비율이 아니라 스위치라 UI에 "+100%"로 적으면 안 된다(`trait_text`가 라벨만 낸다).
const TRAIT_TOGGLE: Array[String] = ["auto_fire"]

const KILL_MOVE_TIME_S := 3.0  # 처치 후 이속 버프 지속(연출/손맛값 — §0 예외, 사용자가 조인다)


# on/off 특성이 켜졌는지 판정하는 **단일 소스**. 비교식을 호출부에 흩뿌리면 다음 사람이 `>=`로 적어
# 특성이 **없는**(0.0) 대상까지 켜진 것으로 읽는다. 토글 축이 아닌 키는 항상 false(비율 키 오용 차단).
#
# 🔴 **이것은 신뢰 경계 함수가 아니다 — 로컬 입력 모드 스위치다** (2026-07-28 netreview I2 정정).
#   `auto_fire`를 읽는 곳은 `player._local_combat`(자기 아바타) **하나뿐이고 호스트는 어디서도 안 본다.**
#   그래서 하위 직업 id를 사칭해 이 특성을 주장해도 얻는 것이 없다 — 변조 클라는 특성과 무관하게
#   이미 `is_fire_rate_ok` 상한까지 G_SHOOT을 뿌릴 수 있다(수용 표면 증가 0).
# ⚠ **호스트 판정 입력을 이 스위치에 매달지 마라.** `peer_traits`는 발신자 트러스트이고 보유 검증이
#   없다(rules §2 G_STATS 게이트). 발사율 완화·콤보 규칙 분기처럼 **호스트가 보는 값**을 여기 걸면
#   그때 비로소 진짜 구멍이 된다 — 그 순간 이 함수는 성격이 바뀌고 §2 게이트를 먼저 통과해야 한다.
static func is_trait_on(key: String, value: float) -> bool:
	return key in TRAIT_TOGGLE and clamp_trait(key, value) > 0.0


# 🔴 비율 보너스를 **정수 수량**에 적용하는 단일 소스 — 소수 잔량을 누적해 1 이상일 때만 올린다.
#   피흡(`combat_authority._leech_frac`)과 **같은 관용구**이고, 같은 이유로 필요하다:
#   드랍 수량이 1~2라 `round(1 × 1.15) = 1`이 되어 **+15%가 정확히 0**이 된다(리뷰 C1에서 실측).
#   반올림/절삭 어느 쪽도 작은 수량에서 비율을 죽인다 — 기댓값을 보존하려면 잔량을 들고 가야 한다.
# carry는 호출부(호스트)가 보관한다 — CombatMath는 상태를 안 쥔다(테스트 결정론).
static func accrue_bonus(base_qty: int, rate: float, carry: float) -> Dictionary:
	var c := carry if (is_finite(carry) and carry > 0.0) else 0.0
	if base_qty <= 0 or not is_finite(rate) or rate <= 0.0:
		return {"qty": base_qty, "carry": c}
	var total := c + float(base_qty) * rate
	var whole := int(floor(total))
	return {"qty": base_qty + whole, "carry": total - float(whole)}


# 특성 한 칸 clamp — 유한성 가드 먼저(JSON 1e999 → INF, clamp_level_stat과 같은 철학).
# 음수는 0 — 디버프 주입 차단. **모르는 키는 0**(TRAIT_MAX에 없으면 상한 0이라 자동 폐기).
static func clamp_trait(key: String, value: float) -> float:
	if not is_finite(value):
		return 0.0
	return clampf(value, 0.0, float(TRAIT_MAX.get(key, 0.0)))


# 특성 묶음 clamp — 🔴 **payload가 아니라 TRAIT_KEYS를 순회한다**(clamp_level_stats 관용구):
# 모르는 키는 자동 폐기되고, 빠진 키는 0.0으로 채워져 하류가 항등 폴백을 얻는다.
static func clamp_traits(traits: Dictionary) -> Dictionary:
	var out := {}
	for key: String in TRAIT_KEYS:
		out[key] = clamp_trait(key, float(traits.get(key, 0.0)))
	return out


# 빈 특성(전부 0) — 특성 없음/미공지 경로의 항등 폴백.
static func empty_traits() -> Dictionary:
	var out := {}
	for key: String in TRAIT_KEYS:
		out[key] = 0.0
	return out


# 🔴 UI 문구는 **여기서 파생**한다 — 훈련소 패널이 특성 설명을 하드코딩하면 값과 문구가 갈라져
#   "표시는 +30%인데 실제는 +10%"가 된다(rules §2 게이트가 요구한 것). 이름만 데이터(SubJobDef).
const TRAIT_LABEL: Dictionary = {
	"reach": "평타 사거리",
	"roll_cd": "구르기 쿨다운",
	"roll_dist": "구르기 거리",
	"campfire_heal": "모닥불 회복 속도",
	"kill_move": "처치 후 이동속도",
	"drop_find": "골드·재료 드랍",
	"proj_range": "투사체 사거리",  # 근접 "평타 사거리"(reach)와 문구로도 구분된다 — 두 축이 서로 안 걸린다
	"auto_fire": "홀드 연사",  # on/off 축 — 퍼센트가 아니라 라벨만 나간다(TRAIT_TOGGLE)
}
# 값이 클수록 "줄어드는" 축 — 부호를 뒤집어 표기한다(쿨다운 −15%).
const TRAIT_REDUCTION: Array[String] = ["roll_cd"]


static func trait_text(key: String, value: float) -> String:
	if key.is_empty() or not TRAIT_LABEL.has(key):
		return ""
	var v := clamp_trait(key, value)
	# on/off 축은 수치가 의미를 갖지 않는다 — 꺼져 있으면 아예 문구가 없고(빈 문자열 = 특성 없음과
	# 같은 취급), 켜져 있으면 라벨만. 여기서 "+100%"를 내면 값이 곱해지는 축처럼 읽힌다.
	if key in TRAIT_TOGGLE:
		return str(TRAIT_LABEL[key]) if is_trait_on(key, v) else ""
	var sign_s := "−" if key in TRAIT_REDUCTION else "+"
	return "%s %s%d%%" % [str(TRAIT_LABEL[key]), sign_s, int(round(v * 100.0))]


# 유한성 가드 먼저(JSON 1e999 → INF, clamp_level_stat과 같은 철학). 음수는 0 — 사거리 디버프 주입 차단.
# 🔴 상한은 TRAIT_MAX["reach"] 하나에서 온다 — 사본을 만들면 특성 상한과 사거리 상한이 갈라진다.
static func clamp_reach(reach: float) -> float:
	return clamp_trait("reach", reach)


# reach = 그 피어가 공지한 메인 하위 직업에서 **호스트가 로컬 리졸브한** 특성값(peer_sync.peer_reach_bonus).
# 0 = 항등 = 특성 없음/도입 전과 완전히 동일.
# equip = 착용 근접 무기 — `melee_range > 0`이면 **직업 기본 사거리를 대신한다**.
#   ⚠ 여기에 실제 수치를 적지 마라(2026-07-28 리뷰 m-1: 적어 뒀던 셋이 전부 데이터와 갈라져 있었다).
#   값은 `data/equipment/*.tres`가 정본이고, 하필 이 함수가 "수치를 복사하지 마라"를 가르치는 자리다.
#   🔴 무기별 사거리를 여기 한 곳에서만 고르는 이유는 위 주석과 같다: 사거리 3함수가 전부 이 함수를
#   지나므로, 호출부 하나라도 job.attack_range를 직접 읽으면 창의 긴 사거리가 판정과 표시 중
#   한쪽에만 걸린다. null/0 = **직업 기본 = 도입 전과 완전 항등**.
# is_finish = 그 타가 콤보 마무리인가 (GDD v2.3 §6 「사거리」). false = 도입 전과 완전 항등.
# 🔴 **`is_finish`가 는 것은 이 함수 안의 분기다** — 호출부가 만들 수 있는 값은 여전히 「이 함수의
#   반환값」 하나뿐이라 §3 「사거리 3함수가 전부 이 함수를 지난다」가 그대로 유지된다.
#   **콤보 배율을 호출부에서 곱하는 형태로 만들지 마라** — 그게 곧 제3의 값이고, `melee_half_angle`
#   주석이 각 축에서 금지한 것과 같은 자리다.
# 🔴🔴 **판정은 각 축과 **같이** 「`req or claim`」으로 리졸브한다** (netreview 2026-08-02 I-1·I-2).
#   ⚠ 처음엔 「센 타수만」으로 갔다가 뒤집혔다 — 근거였던 *"사거리엔 우회로가 없다"* 가 거짓이었다.
#   우회로는 `dx`/`dy`가 아니라 **무기 id 공지**이고(§2), 창을 공지하면 오늘도 수용 208~240px가 열린다.
#   `or`로 얻는 최대치(철대검 189px)가 그보다 작아 **한계 표면이 안 늘고**, 반대로 「센 타수만」의
#   대가는 실재했다: 여유가 `2·E_base − E_fin`로 반토막(42 → 21px)인데 마무리 대시가 20px를 먹는다.
#   아래 clamp는 그래도 남는다 — 그것이 「로컬 ⊆ 호스트」의 하한을 구조로 보장한다.
static func effective_attack_range(job: JobDef, reach: float = 0.0, equip: EquipDef = null,
		is_finish: bool = false) -> float:
	var base := job.attack_range
	if equip != null and equip.melee_range > 0.0:
		base = equip.melee_range
	if is_finish and equip != null and is_finite(equip.combo_finish_range) \
			and equip.combo_finish_range > 0.0:
		# 🔴🔴 **이 `minf` 하나가 「거부 띠 0」을 구조로 만든다 — 호출부로 옮기지 마라.**
		#   로컬 질의는 여유 없이 `E(claim)`, 호스트 확정은 `E(req) × HIT_REACH_SLACK`이다.
		#   최악(claim=마무리 · req=평타)에서 로컬 통과 ⟹ 호스트 통과의 충분조건은
		#     `R_f × (1+r) ≤ 2 × R_b × (1+r)` ⟺ `R_f ≤ R_b × HIT_REACH_SLACK`
		#   이고 **(1+r)이 약분되므로 reach와 무관하게** 참이다(호스트도 공격자 아바타에서 같은
		#   reach를 읽는다 — §3). 즉 데이터가 무엇을 적든 아래 clamp가 그 부등식을 강제한다.
		#   ⚠ `MAX_MELEE_RANGE` clamp도 이 증명을 안 깬다: 호스트 쪽 최종값이 `min(…,130) × 2`라
		#   `R_b(1+r) ≥ 65`면 260 ≥ 130 ≥ 로컬이고, 아니면 `2R_b(1+r) ≥ R_f(1+r) ≥ 로컬`이다.
		base = minf(equip.combo_finish_range, base * HIT_REACH_SLACK)
	return minf(base * (1.0 + clamp_reach(reach)), MAX_MELEE_RANGE)


# 마무리 타의 **표시** 배율 — 판정이 커진 그 비율을 **나눗셈으로 유도한다**(사본 금지).
# 🔴 칼·리본·잔상은 사거리를 안 읽고 **텍스처 폭**에서 도달을 만든다(`_weapon_local_dist`). 그래서
#   판정만 늘리면 표시가 한 픽셀도 안 따라오고, 대검은 현행 여유가 **+2px뿐**이라(칼끝 44 vs 판정 42)
#   42 → 63으로 올리는 순간 **−19px의 「안 보이는데 맞는다」** 가 생긴다 — §3이 금지하는 방향이다.
#   비율을 그대로 곱하면 현행 여유가 **비율째 보존**되므로 튜닝값이 아니라 갈라질 축이 없다.
# ⚠ 표시는 「주장 타수」로 그린다(판정과 부호가 다르다) — 로컬이 자기 스윙을 그리는 것이라 남의
#   화면을 칠하지 않고, 표시가 판정보다 넓은 것은 §3이 허용하는 방향이다.
static func combo_finish_show_mult(job: JobDef, equip: EquipDef, reach: float = 0.0) -> float:
	var base := effective_attack_range(job, reach, equip, false)
	if base <= 0.0:
		return 1.0
	return effective_attack_range(job, reach, equip, true) / base


# 🔴 근접 도달 거리의 **하드 상한** — `MAX_REACH_BONUS`가 특성 축에서 막는 것("근접이 원거리가 되면
#   직업 = 플레이 방식의 변환이 무너진다")을 무기 축에서도 막는다. `melee_range`가 무기 데이터로
#   열리면서 특성 상한만으로는 부족해졌다 — `melee_range = 1000` 한 줄이면 화면 전체가 근접 사거리다.
# 🔴 **근거는 최단 원거리 무기(`worn_bow.arrow_range` 150)다** — 근접 도달이 그걸 넘으면 "창이 활보다
#   멀리 닿는" 역전이 생긴다. 여유를 두고 130: 창 후보(80) × 특성 상한 1.5 = 120 < 130이라 정당한
#   무기가 **조용히 절삭되지 않는다**. ⚠ 이 부등식은 아래 전수 트립와이어가 지킨다 — 창을 100으로
#   만들면(100 × 1.5 = 150 > 130) 빨개지고, 그때 상한과 무기 중 무엇을 고칠지 판단하게 된다.
#   (`proj_range` 상한을 `MAX_ARROW_RANGE`에서 유도한 것과 같은 관용구.)
const MAX_MELEE_RANGE := 130.0


# --- 근접 판정 부채꼴 (무기 모션 축, 2026-07-28) — 단일 소스 (§3) ---
# 🔴 **판정 각 = `EquipDef.swing_arc` 그 자체다 — 판정용 각 필드를 따로 만들지 마라.**
#   swing_arc는 원래 "휘두르는 궤적의 반각"(표시)이었다. 판정용 각을 신설하면 같은 것을 뜻하는
#   숫자가 둘이 되어, 도끼를 넓게 튜닝했을 때 궤적만 넓어지고 판정은 그대로인(또는 반대인) 갈라짐이
#   생긴다 — 보스 콘 텔레그래프가 "각이 픽셀에 박혀 데이터와 갈라진" 그 실패 형태와 같다(§3).
#   하나로 두면 "넓게 휘두르는 무기가 넓게 맞는다"가 **구조로** 보장된다.
# 🔴 **마무리 타는 v2.2(2026-07-29)부터 판정도 넓어진다 — 이 주석이 한 번 뒤집힌 자리다.**
#   전에는 *"`COMBO_FINISH_ARC` 배율은 판정에 넣지 않는다 — 넣으려면 호스트가 콤보 타수를 알아야
#   해서 신뢰 경계가 는다"* 였다. 그 근거가 해소됐다: 호스트는 이제 `G_ATK`(매 스윙·헛침 포함·safe
#   채널)를 직접 세고 클라 주장은 `min` 상한으로만 쓴다(`authoritative_combo` — 활 경로와 같다).
#   **새 네트워크 메시지 0개**이므로 표면이 넓어진 것이 아니라 이미 오던 메시지의 쓰임이 바뀐 것이다.
# 🔴 **그러나 배율이 아니라 절대값으로 받는다** (`EquipDef.combo_finish_arc`). 배율은 포화 문턱이
#   `π ÷ swing_arc`라 무기마다 다르고, 균일 1.25는 도끼(문턱 1.122)만 전방위로 만들어 **무기 구별을
#   없앤다** = 07-28에 없앤 "등 뒤도 맞는다"의 마무리 타 한정 복귀. 판정용 각을 신설하는 것이 아니라
#   **`swing_arc`가 그 타에서 갈아입는 값**이라는 점에서 §3 「반각 = 휘두르는 각 그 자체」는 유지된다.
const MELEE_FULL_ARC := PI  # 전방위(각 검사 없음) = 무기 미착용·미지정의 기본 = 도입 전과 항등
# 🔴 엡실론은 float 반올림으로 "전방위"가 각 분기로 새는 것을 막는다 (보스 셰이더의 같은 가드와 미러).
const MELEE_FULL_ARC_EPS := 0.01
const HIT_REACH_SLACK := 2.0  # 호스트 사거리 여유 배율 — 지연 동안 벌어진 거리를 수용(정직한 타격 거부 방지)
# 🔴 **마무리 타에서 표시가 판정보다 넓은 여유(rad) — 데이터가 아니라 코드가 쥔다.**
#   여유를 `.tres` 두 필드(판정용·표시용)로 두면 데이터 한 줄로 **표시 < 판정**(= 안 보이는데 맞는다)이
#   열린다. 하나만 받고 여유를 코드가 더하면 그 부호가 **구조로** 고정된다.
# ⚠ 이것이 지키는 것은 손맛이 아니라 **관측 가능성**이다: 표시 = 판정이면 *"판정 안인데 궤적이 안
#   지나간 자리"* 를 눈으로 잡을 수 없고, 그게 궤적 결손(`docs/TUNING.md` §13 A-2)의 유일한 검사법이다.
# ⚠ 비마무리 타에는 적용하지 않는다 — 거기 표시·판정은 `swing_arc` 하나이고 **도입 전과 항등**이어야 한다.
const COMBO_FINISH_SHOW_MARGIN := 0.15


# 그 무기의 근접 판정 반각. 미착용/미지정 = 전방위(PI) = **도입 전과 완전 항등**.
# is_finish = 그 타가 콤보 **마무리 타**인가(호출부가 `combo_len − 1`과 대조해 넘긴다).
# 🔴 **`half_angle` 인자에 넘길 수 있는 값은 여전히 둘뿐이다** — 이 함수의 반환값 또는
#   `MELEE_FULL_ARC`(각 생략). `is_finish`가 는 것은 **이 함수 안의 분기**이고, 호출부가 제3의
#   값(튜닝 상수·배율)을 만들 자유도는 늘지 않았다(§3 계약 유지).
static func melee_half_angle(equip: EquipDef, is_finish: bool = false) -> float:
	if equip == null:
		return MELEE_FULL_ARC
	if is_finish and is_finite(equip.combo_finish_arc) and equip.combo_finish_arc > 0.0:
		# 🔴 상한에서 여유를 **미리** 뺀다 — 판정을 먼저 좁혀야 표시(판정 + 여유)가 포화하지 않는다.
		#   표시가 전방위로 새면 궤적 진행 게이트가 꺼져 부채꼴이 한 번에 번쩍인다(개편 전 그림).
		return clampf(equip.combo_finish_arc, 0.0,
			MELEE_FULL_ARC - MELEE_FULL_ARC_EPS - COMBO_FINISH_SHOW_MARGIN)
	return clampf(equip.swing_arc, 0.0, MELEE_FULL_ARC)


# 그 타의 **표시**(궤적·잔상) 반각 — 판정 반각에 마무리 타 여유를 더한 값.
# 🔴 표시를 그리는 쪽은 반드시 이 함수를 지난다. `melee_half_angle`을 직접 읽어 그리면 마무리 타에서
#   표시 = 판정이 되어 위 관측 경로가 사라지고, 거기에 자체 배율을 곱하면 §3이 금지한 제3의 값이 된다.
static func melee_show_half_angle(equip: EquipDef, is_finish: bool = false) -> float:
	var a := melee_half_angle(equip, is_finish)
	if not is_finish or a >= MELEE_FULL_ARC - MELEE_FULL_ARC_EPS:
		return a  # 비마무리 = 항등 · 전방위는 넓힐 곳이 없다
	return minf(a + COMBO_FINISH_SHOW_MARGIN, MELEE_FULL_ARC - MELEE_FULL_ARC_EPS)


# 호스트의 적중 요청 검증 — 공격자 위치 기준 **부채꼴** 안인가 (지연 감안 여유 배율).
# enemy_radius = 적 몸 반경 — 중심거리에서 빼 준다. 거대 보스(radius ~48)는 중심이 멀어
# "붙어도 사거리 밖"이 되므로 몸통 표면까지로 판정한다 (기본 0 = 기존 잔몹 동작 불변).
# facing = 공격 방향(rad, G_HIT_REQ "dx"/"dy") · half_angle = 무기 반각.
# 🔴 **half_angle 기본값이 전방위라 기존 호출부는 전부 항등이다** — 각을 넘기지 않으면 거리 검사만 한다.
# 🔴 **각도 여유는 적 반경에서 유도한다**(`asin(radius/dist)`) — 상수 여유를 두면 가까운 적에겐
#   턱없이 좁고 먼 적에겐 헐렁해진다. 거리 쪽이 이미 `- enemy_radius`로 몸통 표면을 보므로 대칭이고,
#   "몸통이 부채꼴에 걸치면 맞는다"는 화면과 같은 판단이 된다.
static func is_hit_in_reach(attacker_pos: Vector2, enemy_pos: Vector2, job: JobDef,
		enemy_radius: float = 0.0, reach: float = 0.0, equip: EquipDef = null,
		facing: float = 0.0, half_angle: float = MELEE_FULL_ARC,
		is_finish: bool = false) -> bool:
	return is_melee_in_cone(attacker_pos, enemy_pos, facing, half_angle,
		effective_attack_range(job, reach, equip, is_finish) * HIT_REACH_SLACK, enemy_radius)


# 근접 부채꼴 판정 코어 — 🔴 **로컬 질의(player)와 호스트 확정(combat_authority)이 같은 이 함수를 지난다.**
#   여유 배율만 다르다(로컬은 지연이 없어 정확한 기하 / 호스트는 `HIT_REACH_SLACK`). 그래서
#   `reach_dist`를 **이미 계산된 거리**로 받는다 — 여기서 다시 job/equip을 읽으면 두 호출부가 서로
#   다른 여유를 갖는 순간 형태까지 갈라진다.
# ⚠ 로컬이 호스트보다 **엄격하면** 정당한 타격이 아예 요청되지 않아 조용히 사라진다(로컬 탈락 =
#   G_HIT_REQ 미송신). 그래서 각·반경 규칙은 반드시 공유하고 거리 여유만 벌린다.
static func is_melee_in_cone(attacker_pos: Vector2, enemy_pos: Vector2, facing: float,
		half_angle: float, reach_dist: float, enemy_radius: float = 0.0) -> bool:
	if attacker_pos.distance_to(enemy_pos) - enemy_radius > reach_dist:
		return false
	return is_angle_in_cone(attacker_pos, enemy_pos, facing, half_angle, enemy_radius)


# 부채꼴의 **각 축만** — 거리와 분리해 둔 이유는 하나다: 호스트가 게스트의 근접타를 확정할 때
# apex(공격자 좌표)가 지연으로 어긋나므로 **두 apex로 각각 물어야** 하는데, 그때 거리까지 같이
# 물으면 "lead에서 각은 맞는데 거리에서 탈락"이 생겨 보상이 반쪽이 된다(is_hit_in_reach_lagged).
# target_radius = 대상 몸 반경 — 중심이 각 밖이어도 **몸통이 걸치면** 맞는다(거리 쪽 -radius와 대칭).
static func is_angle_in_cone(apex: Vector2, target: Vector2, facing: float,
		half_angle: float, target_radius: float = 0.0) -> bool:
	if half_angle >= MELEE_FULL_ARC - MELEE_FULL_ARC_EPS:
		return true  # 전방위 = 각 검사 없음 (도입 전 동작)
	var to_target := target - apex
	var dist := to_target.length()
	if dist <= target_radius or dist < 0.01:
		return true  # 몸통 안/겹침 — 각 계산 무의미
	var angle_slack := asin(clampf(target_radius / dist, 0.0, 1.0))
	return absf(angle_difference(facing, to_target.angle())) <= half_angle + angle_slack


# 🔴 **근접 적중 검증의 지연 보상판** (netreview C-1, 2026-07-28) — 호스트가 게스트 타격을 확정할 때 쓴다.
#   거리 축엔 `HIT_REACH_SLACK`(×2.0) 여유가 원래 있었지만 **각 축엔 아무 보상이 없었다.** apex가
#   `net_anchor()`(외삽 없는 마지막 수신 좌표 = 편도 + 송신주기만큼 낡음)라서, 이동 중인 게스트는
#   각이 통째로 틀어진다. 실측 근거는 이 파일이 이미 갖고 있다 — `LAG_MAX_LEAD_DIST`(115px)가
#   **근접 교전 거리(30~80px)의 2~3배**다. 걷기만 해도 13px, 구르기 직후엔 ~35px 어긋난다.
#   증상은 **게스트에서만·배포본에서만**: 스윙·궤적·타격음·화면 반동이 다 나오는데 **적 HP만 안 깎인다**.
#   ⚠ 좁은 각 무기(창 ±17°)가 오면 예외가 아니라 **상시**가 된다 — 40px에서 13px 오차 = 각 18°.
#
# 🔴 **각만 `or`, 거리는 anchor 하나 — 이 비대칭이 계약이다.**
#   ⑴ 거리를 anchor에만 묶어 두면 판정 집합이 **(anchor 중심, 그 무기 사거리) 원의 부분집합**으로
#      남는다 → 신뢰 경계가 안 넓어진다(부채꼴 도입의 안전성 논거가 그대로 보존된다).
#   ⑵ 각은 두 apex 중 **하나만** 통과하면 된다.
# 🔴 **§3 「방어자 우대」(`is_strike_hit_lagged`의 `and`)와 의도적으로 반대 부호다 — 헷갈리지 마라.**
#   저쪽은 게스트가 **방어자**이고 오차가 "안 맞는 쪽"으로 떨어져야 안전하다. 여기는 게스트가
#   **공격자**라 안전한 방향이 정반대다: 오차가 "안 맞는 쪽"으로 떨어지면 그게 곧 삭제된 타격이다.
#   두 규약을 같은 부호로 통일하려는 변경은 둘 중 하나를 반드시 망가뜨린다.
#
# ✅ **이 안전성 논거는 `LAG_MAX_LEAD_DIST` clamp에 의존하지 않는다** (리뷰 확인) — 거리 술어가
#   `lead_pos`가 등장하기 **전에** 무조건 `return false`하는 조기 반환이고, `lead_pos`는 그 뒤
#   `is_angle_in_cone`의 인자로만 쓰여 `bool`을 돌릴 뿐 반지름을 바꿀 경로가 없다. lead가 무한대여도
#   최악이 "각 검사 생략 폴백과 동일" = 도입 전 동작이다. **조기 반환의 위치가 근거이고 전수 테스트는
#   그 확인이다.** clamp를 조일 때 여기까지 재검토할 필요가 없고, 반대로 **여기가 clamp를 지켜준다고
#   오해해 `is_strike_hit_lagged` 쪽 「외삽 상한 불변식」 트립와이어를 빼지도 마라** — 그쪽이 정본이다.
# 🔴 **`target_lag_px`는 부등호 반대편(대상 좌표)의 지연분이다 — `or`로는 원리적으로 못 덮는다.**
#   (2026-07-28 netreview 2차 C-1.) 위 `or`는 **공격자** apex 두 개를 훑지만, 적 좌표는 두 apex가
#   똑같이 쓰므로 아무리 or를 걸어도 그 축이 안 덮인다. 그리고 적 좌표가 플레이어보다 **더 낡다**:
#   `G_MOB_POS`는 10Hz·fast(유실 허용)이고 수신부에 **외삽이 없다**(플레이어는 15Hz + 속도 외삽).
#   호스트는 몹 실시간 좌표를 아는데 게스트 화면은 낡아서, **게스트가 정당하게 맞힌 것을 호스트가
#   거부**한다 → `mob_lag_slack_px`만큼 각 슬랙을 넓혀 그 시야 차를 수용한다.
# ⚠ **각에만 더한다 — 거리에는 안 더한다.** 거리에 넣으면 판정 원 자체가 커져 "판정 집합 ⊆ anchor
#   원"이 깨진다(이 함수의 안전성 논거 전체가 거기 걸려 있다).
# ⚠ **넓히는 방향이 관대한 것은 의도다.** 여기서 관대해지는 대상은 **적(NPC)**이지 플레이어가 아니라,
#   §3 「방어자 우대」가 지키려는 것("피했는데 맞았다")과 이해가 충돌하지 않는다. 반대로 좁히면
#   플레이어의 정당한 타격이 조용히 사라진다. 거리 축은 `HIT_REACH_SLACK`(×2.0)으로 **이미 2배
#   관대**했고 각만 엄격했던 것이 비대칭이었다.
static func is_hit_in_reach_lagged(anchor: Vector2, lead_pos: Vector2, enemy_pos: Vector2,
		job: JobDef, enemy_radius: float = 0.0, reach: float = 0.0, equip: EquipDef = null,
		facing: float = 0.0, half_angle: float = MELEE_FULL_ARC,
		target_lag_px: float = 0.0, is_finish: bool = false) -> bool:
	if anchor.distance_to(enemy_pos) - enemy_radius \
			> effective_attack_range(job, reach, equip, is_finish) * HIT_REACH_SLACK:
		return false
	var angle_radius := enemy_radius + maxf(target_lag_px, 0.0)
	return is_angle_in_cone(anchor, enemy_pos, facing, half_angle, angle_radius) \
		or is_angle_in_cone(lead_pos, enemy_pos, facing, half_angle, angle_radius)


# 대상(잔몹) 좌표가 게스트 화면에서 낡은 만큼의 **횡변위 예산(px)** — 각 슬랙 전용.
# 유도 = 최대 몹 이속 × (몹 송신 주기 + 편도 지연). 실측(2026-08-01): 최대 `move_speed` **74**
#   (mino_sword) · `MobSync.SEND_RATE` 10Hz. 배포본 편도 70~108ms에서 약 12~16px.
#   ⚠ 옛 주석은 "최대 70(chaser·goblin_melee)"였는데 **그 두 적은 2026-08-01에 삭제됐다** — 없는
#   파일을 근거로 상수를 조이지 않게 갱신했다. 여유는 20 → 16으로 줄었다.
# 🔴 **왜 창에서만 문제가 되나**: 각 오차 = `asin(변위/거리)`인데 창은 반각이 17°로 좁고 사거리가
#   80px로 길다. 14px 변위가 80px에서 10°를 만들어 예산(반각 17.2 + 몸통 슬랙 7.2 = 24.4°)의 40%를
#   먹는다. 검(109~137°)·도끼(160°)는 각 예산이 커서 무해하고, 보스는 **`body_radius`가 커서**
#   그 자체로 큰 슬랙을 주므로 이미 덮인다 — **창 × 잔몹**에서만 상시가 된다.
# ⚠ **여기 보스 반경 숫자를 박지 마라** (2026-08-02에 실제로 낡았다). 이 자리엔 오래 `42`가 적혀
#   있었는데 실제 데이터는 63이었고, 같은 날 덩치를 줄이며 50이 됐다 — **셋이 전부 달랐다.**
#   결론은 안 바뀐다(`asin(50/80)` = 38.7° > 예산 24.4°)지만, 데이터 값을 주석에 복제한 것이
#   문제였다. 현재 값의 정본은 `data/enemies/*.tres`의 `body_radius`다.
const MOB_LAG_SLACK_SPEED := 90.0  # 유도 상한(px/s) — 실측 최대 74 + 새 적 여지. 초과 시 트립와이어
const MOB_POS_PERIOD_S := 0.1      # ⚠ `MobSync.SEND_RATE`(10Hz)와 **미러** — 그 값을 바꾸면 여기도 고친다


static func mob_lag_slack_px(one_way_ms: float) -> float:
	return MOB_LAG_SLACK_SPEED * (MOB_POS_PERIOD_S + clamp_one_way_ms(one_way_ms) / 1000.0)


# 히트 기하 — 단일 소스 (§3). 실제 판정(부채꼴 질의)과 공격 FX 크기가 같은 함수에서 파생된다.
# 한쪽만 조이면 "맞는 곳"과 "보이는 곳"이 어긋난다 — 손맛 튜닝은 반드시 여기서.
# ⚠ **판정 도달 거리는 `effective_attack_range` 그 자체다**(부채꼴 반경). 아래 두 스케일은 이제
#   판정 형태가 아니라 **FX 기하**(궤적 굵기·파형 출발점)를 잡는 데 쓴다 — 부채꼴 전환(2026-07-28)
#   전에는 "전방 오프셋 원"이 곧 판정이라 둘이 같았다. 도달 거리를 여기서 다시 유도하지 마라.
const ATTACK_CENTER_SCALE := 0.6  # FX 중심까지의 거리 = range * 이 값
const ATTACK_RADIUS_SCALE := 0.5  # FX 굵기(파형 세로 반높이 정합) = range * 이 값


# ⚠ `is_finish` = 적중 FX 원점이 마무리 타에 그만큼 앞으로 나간다(순수 표시 — `weapon_impact`).
static func attack_center_offset(dir: Vector2, job: JobDef, reach: float = 0.0,
		equip: EquipDef = null, is_finish: bool = false) -> Vector2:
	return dir * (effective_attack_range(job, reach, equip, is_finish) * ATTACK_CENTER_SCALE)


static func attack_radius(job: JobDef, reach: float = 0.0, equip: EquipDef = null) -> float:
	return effective_attack_range(job, reach, equip) * ATTACK_RADIUS_SCALE


# 한 스윙이 여러 적을 치는 것은 허용하되(SAME_SWING_MS 안), 스윙 간격은 쿨다운(지터 여유 0.9배)을 강제.
# 앵커(last_confirm_msec)는 새 스윙에서만 갱신해야 한다 — 매 확정마다 갱신하면 창이 미끄러져 연사 스팸이 뚫린다.
const SAME_SWING_MS := 50
# 🔴 호스트 간격 게이트의 **지터 여유** — 요구 간격을 이 배율만큼 깎아 정직한 발사가 네트워크 지터로
#   거부되지 않게 한다. 근접 쿨다운·발사율·차지 시간·콤보 전진 **네 곳이 같은 값을 쓴다**: 여유를
#   따로 두면 한쪽만 조였을 때 "어떤 공격은 관대하고 어떤 공격은 오탐 거부"가 되고, 그건 화면에
#   "가끔 공격이 씹힌다"로만 보인다. 조일 땐 여기 한 곳.
const FIRE_RATE_SLACK := 0.9


# haste = 그 피어가 공지한(그리고 호스트가 clamp한) 공격속도 보너스 — 0 = 항등(성장축 도입 전과 동일).
static func is_hit_cooldown_ok(last_confirm_msec: int, now_msec: int, job: JobDef, haste: float = 0.0) -> bool:
	var dt := now_msec - last_confirm_msec
	return dt <= SAME_SWING_MS or dt >= int(effective_cooldown(job, haste) * FIRE_RATE_SLACK * 1000.0)


# 구르기 타이밍 — 단일 소스 (§3). 로컬 이동(player)과 호스트 i-frame 검증이 같은 값을 읽는다.
# player.gd에 사본을 남기면 첫 손맛 튜닝에서 구르기 거리와 무적 창이 갈라진다.
# ⚠ 애니 미러: assets/sprites/player/*_frames.tres의 roll(4프레임/speed 16 = 0.25s)이 이 값과 맞물린다.
#   ROLL_TIME_S를 바꾸면 3개 .tres의 roll speed도 같이 조정할 것 (애니가 짧으면 마지막 프레임에 얼어붙는다).
const ROLL_TIME_S := 0.25
const ROLL_COOLDOWN_S := 0.8
const ROLL_IFRAME_GRACE_MS := 120  # 지연 여유 — 사거리 검증 2.0배 완충과 같은 철학
# 구르기 이동 배율 — 로컬 이동·원격 변위 clamp·LAG_MAX_LEAD_DIST 유도가 **전부 이 상수 하나**를 읽는다.
# (player.gd에 있던 것을 v2.0에서 여기로 이사: roll_dist 특성이 붙으면서 세 곳의 유도가 갈라질 자리가 됐다.)
const ROLL_SPEED_MULT := 2.6


# 유효 구르기 쿨다운 — roll_cd 특성(0.15 = −15%)만큼 짧아진다. 0 = 항등(특성 도입 전과 동일).
# 🔴 로컬 쿨(player)과 호스트 그랜트 검증이 **같은 함수**를 지난다 — 사본을 만들면 게스트가
#   "내 화면에선 굴러지는데 무적이 안 걸리는" 상태가 되고, 그건 화면에 이유가 안 드러난다.
static func effective_roll_cooldown(roll_cd: float = 0.0) -> float:
	return ROLL_COOLDOWN_S * (1.0 - clamp_trait("roll_cd", roll_cd))


# 유효 구르기 속도 — roll_dist 특성만큼 빨라진다(= ROLL_TIME_S가 고정이므로 곧 거리 증가).
# 🔴 로컬 이동·원격 변위 clamp가 같은 유도식을 쓴다(§3 이동속도 계약과 같은 이유) —
#   원격 clamp만 기본값으로 남기면 정당하게 길어진 구르기가 깎여 외삽이 과소평가되고,
#   2026-07-24에 고친 "피했는데 맞았다"가 roll_dist 보유자에게 부분 재발한다.
static func effective_roll_speed(base_move_speed: float, roll_dist: float = 0.0) -> float:
	return base_move_speed * ROLL_SPEED_MULT * (1.0 + clamp_trait("roll_dist", roll_dist))


# 호스트의 구르기 그랜트 검증 — 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 구르기 이상의 무적을 못 얻는다.
# roll_cd = 그 피어가 공지한 하위 직업에서 **호스트가 로컬 리졸브한** 특성값(peer_sync.peer_traits).
static func is_roll_grant_ok(last_grant_msec: int, now_msec: int, roll_cd: float = 0.0) -> bool:
	return now_msec - last_grant_msec >= int(effective_roll_cooldown(roll_cd) * 0.9 * 1000.0)


# 그랜트된 i-frame 창이 현재 유효한가 (호스트가 데미지 확정 직전에 조회).
static func is_iframe_active(grant_msec: int, now_msec: int) -> bool:
	return now_msec - grant_msec <= int(ROLL_TIME_S * 1000.0) + ROLL_IFRAME_GRACE_MS


# 투사체(궁수 화살) 단일 소스 (§3, 2026-07-24). 화살은 결정론적 직선 등속 —
# 각 클라 표시 화살과 호스트 권한 화살이 같은 속도/사거리 상수를 읽어야 위치가 일치한다("맞는 곳=보이는 곳").
# 속도·사거리·굵기는 손맛/도달 튜닝값(§0 예외 — 사용자가 조인다). 무기별로 갈라야 하면 나중에 EquipDef로 이관.
const ARROW_SPEED := 420.0        # 화살 이동 속도(px/s) — 표시·호스트 공용(결정론 필수)
const DEFAULT_ARROW_RANGE := 360.0  # 무기 미지정 시 사거리 폴백(px). 무기별 실값 = EquipDef.arrow_range
const MAX_ARROW_RANGE := 480.0    # 사거리 상한 — 호스트가 게스트 전송값을 이 이상으로 못 쓰게 clamp(§3 신뢰 경계). ⚠ 정당 무기도 이 이상은 조용히 잘림 — 신규 활 EquipDef.arrow_range는 이 값 이하 유지
const MIN_ARROW_RANGE := 40.0     # 사거리 하한 — 0/음수 전송으로 화살이 즉시 소멸하는 것 방지
const ARROW_HIT_RADIUS := 6.0     # 화살 굵기(px) — 명중 반경 = ARROW_HIT_RADIUS + 적 body_radius
# ⚠ 터널링 불변식(§5): 프레임당 전진(ARROW_SPEED/60 ≈ 7px) < 최소 명중 지름(2×(ARROW_HIT_RADIUS+min body_radius)).
#   EnemyDef.body_radius 기본 6 → 최소 지름 24px ≫ 7px라 프레임 사이 관통 없음. ARROW_SPEED를 크게 올리거나
#   body_radius 0인 적을 넣으면 이 부등식이 깨진다 — 그땐 스텝을 세그먼트로 쪼개 질의할 것.
const SHOT_ORIGIN_TOL := 44.0     # 발사 원점 허용 오차(px) — 발사자 net_anchor에서 이보다 멀면 스푸핑으로 거부.
# MUZZLE_OFFSET(26, 화살이 몸 밖에서 나가게) + 발사~마지막 수신 좌표 사이 이동·지연 여유(~18px). ⚠ 수용된 한계
#   (G_ROLL 그랜트 창과 같은 성격): 조작 클라가 원점을 적 쪽으로 최대 ~18px 당기는 미세 이득은 막지 않는다(2인 협동 실익 낮음).


# 전송받은 사거리를 안전 범위로 clamp — 호스트가 게스트 G_SHOOT의 "r"에 적용(스푸핑 상한, §3 신뢰 경계). G_STATS clamp 미러.
# ⚠ NaN 가드 먼저: clampf(NAN,…)는 NaN을 그대로 반환 → life=NaN → 수명 만료 안 되는 무한 화살(누수). dir is_finite 가드와 대칭.
static func clamp_arrow_range(arrow_range: float) -> float:
	if not is_finite(arrow_range):
		return DEFAULT_ARROW_RANGE
	return clampf(arrow_range, MIN_ARROW_RANGE, MAX_ARROW_RANGE)


# 화살 수명(s) = 사거리/속도. 사거리는 무기별(EquipDef.arrow_range) — 표시·권한이 같은 값을 받아 결정론 유지("맞는 곳=보이는 곳").
static func arrow_lifetime_s(arrow_range: float = DEFAULT_ARROW_RANGE) -> float:
	return clamp_arrow_range(arrow_range) / ARROW_SPEED


# 투사체 속도 clamp — 무기별 탄속(EquipDef.projectile_speed, 0 = 기본 화살 속도)의 유일한 진입점.
# ⚠ 터널링 불변식(위): 상한을 올리면 프레임당 전진 > 최소 명중 지름이 될 수 있다 — MAX는 그 여유 안에서 고른 값.
const MIN_PROJECTILE_SPEED := 60.0
const MAX_PROJECTILE_SPEED := 600.0


static func clamp_projectile_speed(speed: float) -> float:
	if not is_finite(speed) or speed <= 0.0:
		return ARROW_SPEED  # 미지정(0)·오염값 = 기본 화살 속도
	return clampf(speed, MIN_PROJECTILE_SPEED, MAX_PROJECTILE_SPEED)


# 🔴 그 무기가 **탄을 쏠 수 있는가** — 호스트의 G_SHOOT 신뢰 경계 (2026-07-27 netreview M4).
#   `EquipDef.motion_type`의 발사형 판정을 여기 한 곳에 모은다: `player._local_combat`의 모션 분기와
#   호스트의 발사 수락이 같은 기준을 써야 "로컬은 못 쏘는데 호스트는 받아준다"가 안 생긴다.
# ⚠ **null은 false다** — 다만 호출부는 null을 **거부하지 않는다.** null = "G_STATS 미도착" 정상 창이고,
#   그 창의 폴백(기본 화살)은 의도된 동작이다. 거부 대상은 **리졸브에 성공했는데 발사형이 아닌** 무기다.
# 🔴 왜 필요한가: `EquipDef.arrow_range` 기본값이 DEFAULT_ARROW_RANGE(360)이고 근접 무기 `.tres`엔
#   그 필드가 아예 없다 — 즉 대검을 공지한 채 G_SHOOT을 쏘면 호스트가 **360px 권한 화살**을 등록하고
#   전사 공격력으로 확정한다. 활 사거리를 150으로 내린 뒤로는 그 사칭 화살이 궁수의 정당한
#   마무리 타(300/306px)보다도 **멀리** 나간다.
static func is_projectile_weapon(equip: EquipDef) -> bool:
	return equip != null and (equip.motion_type == "shoot" or equip.motion_type == "charge")


# --- 무기 모션 데이터 계약 (무기 모션 개편 2026-07-28) — 🔴 **여기 있는 것 자체가 계약이다.**
#   `player.gd`는 씬 글루라 `-s` 헤드리스가 preload를 못 한다(rules §5). 그래서 **데이터가 만족해야
#   하는 상수를 거기 두면 `data/equipment` 전수 트립와이어를 만들 수 없다** — 테스트는 코드보다
#   느슨한 근사만 쓸 수 있고, 그 틈으로 "조용히 clamp된 값"이 초록으로 샌다(2026-07-28 리뷰 J-1·J-2:
#   `swing_windup_ratio = 0.02`와 구간 합 0.97이 **둘 다 초록으로 통과**했다).
#   ⚠ 아래 둘은 **판정을 만들지 않는다**(표시 타이밍·손맛 배율). 그래도 여기 있는 이유는 오직
#     "테스트가 닿아야 하는 데이터 계약"이기 때문이다 — 판정 함수와 헷갈리지 마라.

# 공격 모션 구간 (선딜, 스윕) — 후딜은 `1 - windup - strike` 파생이라 필드가 없다.
# 🔴 세 구간이 전부 양수 폭이어야 한다: 0이면 정규화가 0으로 나누고, 합이 1 이상이면 후딜이 사라져
#   무기가 휘두른 자세로 **얼어붙는다**(에러 없이 화면만 어긋난다). 데이터를 믿지 않고 여기서 clamp한다.
# ⚠ clamp가 발동하면 작성자가 적은 값이 **조용히** 안 쓰인다("왜 내 도끼 예비가 안 길어지지").
#   `test_combat_math_auto`가 `motion_phases(e)`의 출력이 입력과 같은지를 전수로 단정해 그걸 잡는다 —
#   **상한 값을 테스트에 복제하지 않고도** 상한을 조이면 단정이 따라온다.
const MOTION_PHASE_MIN := 0.05
# ⚠ `EquipDef.swing_windup_ratio`/`swing_strike_ratio`의 기본값과 **미러**다(무장 해제 폴백).
const DEFAULT_SWING_WINDUP := 0.28
const DEFAULT_SWING_STRIKE := 0.47


static func motion_phases(equip: EquipDef) -> Vector2:
	var w: float = equip.swing_windup_ratio if equip != null else DEFAULT_SWING_WINDUP
	var s: float = equip.swing_strike_ratio if equip != null else DEFAULT_SWING_STRIKE
	w = clampf(w, MOTION_PHASE_MIN, 1.0 - 2.0 * MOTION_PHASE_MIN)
	return Vector2(w, clampf(s, MOTION_PHASE_MIN, 1.0 - MOTION_PHASE_MIN - w))


# 무기 타격 무게 배율 — 🔴 **`EquipDef.hit_shake` 하나에서 파생한다.** 스크린셰이크뿐 아니라 카메라
#   킥(`player.HIT_KICK`·`COMBO_FINISH_KICK`)과 적중 시 스윙 박힘(`SWING_BITE_S`)이 전부 이걸 지난다.
#   무게 필드를 따로 만들지 마라 — 같은 것을 뜻하는 숫자가 둘이 되면 도끼를 무겁게 조였는데
#   셰이크만 커지고 킥은 그대로인 갈라짐이 생긴다(rules §3의 반복된 실패 형태).
# 🔴 **상한에 걸리면 그 위로는 킥·박힘이 안 따라오고 셰이크만 커진다** = 무게 단일 소스가 조용히
#   반쪽이 된다. 현행 최대가 파쇄 도끼 4.4/1.5 = 2.93이라 **한 칸(4.5)만 올려도** 걸렸다 —
#   `test_combat_math_auto`의 「★무게 배율 전수」가 그걸 잡는다.
const HIT_SHAKE_REF := 1.5    # 배율 1.0의 기준점 = EquipDef.hit_shake 기본값
const HIT_WEIGHT_MIN := 0.4
const HIT_WEIGHT_MAX := 3.0


static func weapon_weight(equip: EquipDef) -> float:
	var hs: float = equip.hit_shake if equip != null else HIT_SHAKE_REF
	return clampf(hs / HIT_SHAKE_REF, HIT_WEIGHT_MIN, HIT_WEIGHT_MAX)


# --- 넉백 (2026-08-02) — 층①(흠칫 표시)과 층②(몸 밀림)의 **공용 단일 소스** ---
#
# 🔴 **세기는 `EquipDef.hit_shake` 하나에서 파생한다** — 바로 위 `weapon_weight`가 그 창구다.
#   무게 필드를 따로 만들지 마라(§3): 스크린셰이크·카메라 킥·적중 박힘이 이미 거기서 나오고,
#   넉백만 다른 숫자를 쥐면 "도끼를 무겁게 조였는데 밀림만 그대로"가 된다.
# 🔴 **`mob_melee.gd`·`combat_authority.gd`가 아니라 여기 사는 이유는 검출력이다**(리뷰 J-1·J-2).
#   씬 글루는 `-s` preload가 안 돼 `data/**` 전수 트립와이어를 만들 수 없고, 그러면 테스트는
#   코드보다 느슨한 근사만 쓸 수 있어 조용히 clamp된 값이 초록으로 샌다.
#
# 두 층이 갈리는 지점은 **`knock_resist` 하나뿐**이다:
#   층① 흠칫(표시, 스프라이트 로컬)   = knock_show_px()        ← 적 저항 **없음**
#   층② 밀림(몸 월드 좌표, 호스트)    = knockback_px()          ← 층① × knock_resist(적)
# ⚠ **층①에 저항을 곱하지 않는 것은 의도된 해석이다**(리드 확인 요청 대상). 저항은 "얼마나
#   밀리는가"의 축이고(A-5), 층①이 고치려는 결함은 *"파쇄 도끼든 낡은 대검이든 똑같이 5px
#   흠칫한다"* = **무기 무게**다. 저항을 곱하면 보스(반경 63 → 저항 0.036)의 흠칫이 0.1~0.4px가
#   되어 **가장 많이 때리는 적에서 층①이 통째로 사라진다.** 되돌리려면 `knockback_px`를
#   층①에도 쓰면 되고, 그 한 줄이 이 해석의 전부다.
const KNOCK_BASE_PX := 4.0        # 무게 1.0(hit_shake 1.5) 평타의 밀림 거리(px) — 손맛값(§0 예외)
const KNOCK_FINISH_MULT := 1.6    # 마무리 타 배수 — `is_combo_finish` 단일 소스로 갈린다(사본 금지)
# 🔴 **상한은 「내가 따라가는 거리」에서 유도한다 — 독립 상수가 아니다.**
#   불변식: `MAX_KNOCK_PX ≤ min over data/equipment of combo_dash_dist(equip, true)`.
#   플레이어는 **모든 타에 전진**하므로(마무리 전량 · 평타 `NONFINISH_DASH_RATIO`) 상한을 최소
#   마무리 대시 아래로 묶으면 *"밀어낸 만큼 내가 따라간다"* 가 데이터가 아니라 **부등식**으로
#   보장된다 — 안 묶으면 "때릴수록 못 때린다"가 되고 화면에 이유가 안 드러난다.
#   현행 우변 = min(16, 20, 20, 20) = 16.0(낡은 대검 16) → 여유 25%.
#   ⚠ 여유가 필요한 이유는 **창(槍) 판례**다 — 「폴백 창 불변식」이 84 vs 80으로 4px 여유뿐이라
#     위험 등급이 됐다. `test_combat_math_auto`의 「★넉백 전수」가 전수로 지킨다.
const MAX_KNOCK_PX := 12.0
# 🔴 **넉백 속도 상한 = `MOB_LAG_SLACK_SPEED`(90)** — §3 「대상 좌표 각 슬랙」 유도식을 **문자 그대로
#   참인 채로** 남기려는 것이다. 그 유도는 `mob_lag_slack_px = MOB_LAG_SLACK_SPEED × (송신주기 + 편도)`
#   이고 근거가 "실측 최대 몹 이속 74 + 새 적 여지"다. 넉백이 몹을 90px/s보다 빠르게 움직이면
#   **유도가 거짓이 되고** 게스트 화면의 몹 좌표가 슬랙 예산보다 낡아져 **게스트의 정당한 근접타가
#   무음 거부**된다(증상: 스윙·궤적·소리는 다 나는데 적 HP만 안 깎인다 — 배포본·게스트에서만).
#   대안이던 「상수를 270으로 올린다」는 창의 콘을 +44°(사실상 전방위)로 벌려 **기각**했다.
#   대가 = 무거운 넉백이 "펀치"가 아니라 "밀침"으로 읽힌다. 🔵 **그래도 손맛은 안 죽는다 — 그건
#   층①이 즉시·로컬·양쪽 화면에서 이미 팔기 때문이다**(두 층을 가른 것이 여기서 값을 한다).
const KNOCK_TIME_MIN_S := 0.05
# 저항 1.0의 기준 몸 반경 = 일반 잔몹(미노 12). 🔴 **`EnemyDef.knock_resist` 필드를 만들지 마라** —
#   `body_radius`는 이미 판정 반경·그림자 폭·텔레그래프·화살 총구·길찾기 반경의 단일 소스이고,
#   저항을 그 목록에 넣으면 **새 적 = 여전히 .tres 한 장**이다(§4). 덩치를 키운 적이 자동으로 덜
#   밀린다 — 사람이 두 값을 손으로 맞출 자리를 안 만든다.
# ⚠ 알려진 한계(수용): *작은데* 안 밀리는 적(고정 포탑·뿌리내린 적)은 이 유도로 표현할 수 없다.
#   그런 적이 실제로 필요해질 때가 필드를 정당화하는 시점이다.
const KNOCK_REF_RADIUS := 12.0
# 🔴 **그 타의 전진(대시) 대비 상한 — `MAX_KNOCK_PX`(전역)로는 못 막는 두 구멍을 닫는다**
#   (netreview 2026-08-02 M-A·M-B. 둘 다 **같은 뿌리**라 이 한 줄이 동시에 닫는다).
#   ⒜ **무장 해제·거부된 무기**(`equip == null`): `weapon_weight(null)` = 1.0이라 마무리 6.4px가
#      나오는데 `combo_dash_dist(null)` = **0.0**이다 → 적은 밀리는데 내 전진이 0 = 순수 손해.
#      ⚠ 전역 상한은 이걸 **원리적으로** 못 본다 — `null`은 `data/equipment`에 없어서 전수
#      트립와이어의 표본에 존재하지 않는다(테스트가 "지키는 척"만 하던 축이다).
#   ⒝ **평타 축**: A-6 불변식은 `is_finish = true`만 걸었고 설계 A-8 표도 마무리만 계산했다.
#      실측 = 파쇄 도끼 평타 밀림 11.73px vs 평타 대시 8.0px → **+3.73px 벌어진다**(미노 저항
#      1.0이라 감쇠 없음, 게다가 도끼는 `melee_range` 38로 4종 중 최단이다).
#   → 상한을 **그 타의 대시에서** 유도하면 "때릴수록 멀어진다"가 무기·타수·데이터와 무관하게
#     **부등식으로** 불가능해진다. A-6의 정신을 전역 상수에서 **타별**로 정밀화한 것이다.
# 🔴 **층②에만 건다 — 층①(흠칫)은 이 상한을 안 탄다.** 근거가 "내가 따라간다"(공간)인데 층①은
#   몸을 안 움직이므로 그 근거가 성립하지 않는다. 걸면 도끼 평타 흠칫이 11.7 → 6.0px로 죽어
#   **손맛만 잃고 얻는 것이 없다**(설계 A-0: 손맛은 ①이 팔고 공간은 ②가 판다).
# 여유 0.25는 `MAX_KNOCK_PX`(12 vs 최소 마무리 대시 16)와 **같은 근거·같은 값**이다(창 판례).
const KNOCK_DASH_RATIO := 0.75


# 적 저항 [0, 1] — 질량 ∝ 면적 가정. 반경이 기준보다 작으면 1.0(clamp)이라 작은 적은 전부 온전히 밀린다.
static func knock_resist(def: EnemyDef) -> float:
	if def == null:
		return 1.0
	var r: float = def.body_radius
	if not is_finite(r) or r <= 0.0:
		return 1.0
	var k := KNOCK_REF_RADIUS / r
	return clampf(k * k, 0.0, 1.0)


# 층① 흠칫 세기(px) — 적 저항 **전**의 상한 적용값. 표시 전용이라 네트워크 메시지가 0개다.
# ⚠ `charge_lv`는 근접 차지(단계 C) 자리다 — 지금 근접은 항상 0을 넘기므로 **완전 항등**이고,
#   발사형(법사 지팡이)만 실제로 0이 아닌 값을 쓴다. 배율표는 데미지와 **같은 표**를 지난다
#   (배율을 따로 두면 "세게 모았는데 밀림만 그대로"가 된다).
static func knock_show_px(equip: EquipDef, is_finish: bool = false, charge_lv: int = 0) -> float:
	var raw := KNOCK_BASE_PX * weapon_weight(equip) \
		* (KNOCK_FINISH_MULT if is_finish else 1.0) \
		* CHARGE_DAMAGE_MULT[clamp_charge_level(charge_lv)]
	return minf(raw, MAX_KNOCK_PX)


# 층② 밀림 거리(px) = 층① × 적 저항.
# 🔴 **`resist`는 cap 「뒤」에 곱한다 — 순서가 계약이다.** 그래야 `knockback_px ≤ MAX_KNOCK_PX`
#   불변식이 **모든 적에 대해** 성립하고, 위 A-6 부등식(대시 ≥ 넉백)이 데이터와 무관하게 참이 된다.
#   앞에 곱하면 저항이 큰 적에서 cap이 먼저 걸려 상한이 사실상 `MAX_KNOCK_PX / resist`가 된다.
#   🔴 **대시 상한도 `resist` 「앞」이다** — 같은 이유다(cap류는 전부 저항 앞). 뒤로 옮기면 저항이
#     큰 적에서 상한이 `dash × RATIO / resist`로 부풀어 A-6·M-B가 같이 무너진다.
static func knockback_px(equip: EquipDef, is_finish: bool = false, enemy_def: EnemyDef = null,
		charge_lv: int = 0) -> float:
	# 🔴 그 타의 전진 이하로 묶는다(`KNOCK_DASH_RATIO` 주석 = 근거). `equip == null`이면 대시가
	#   0이므로 넉백도 0 = **도입 전과 완전 항등**이고, 그것이 무기를 모르는 경로의 안전한 폴백이다.
	var push := minf(knock_show_px(equip, is_finish, charge_lv),
		combo_dash_dist(equip, is_finish) * KNOCK_DASH_RATIO)
	return push * knock_resist(enemy_def)


# 그 거리를 미는 데 걸리는 시간(s) — 속도가 아니라 **시간**을 유도해 속도 상한을 구성으로 만든다.
static func knock_time_s(px: float) -> float:
	if not is_finite(px) or px <= 0.0:
		return KNOCK_TIME_MIN_S
	return maxf(px / MOB_LAG_SLACK_SPEED, KNOCK_TIME_MIN_S)


# 넉백 속도(px/s) — 🔵 **구성상 항상 ≤ `MOB_LAG_SLACK_SPEED`**: `t ≥ px / 90`이므로 `px / t ≤ 90`이다.
# 🔴 **여기에 `minf(…, MOB_LAG_SLACK_SPEED)`를 덧붙이지 마라.** 그러면 부등식이 항등적으로 참이 되어
#   `test_combat_math_auto`의 K3(속도 상한)이 **공허해진다** — 누가 `knock_time_s`를 상수로 바꿔
#   속도가 240px/s가 돼도 트립와이어가 초록이다(rules: "코드와 테스트가 같은 모델을 공유하면
#   검출력은 0이다"). 상한은 **시간 유도**가 지고, 그 유도가 살아 있는지는 테스트가 잰다.
static func knock_speed_px_s(px: float) -> float:
	var t := knock_time_s(px)
	if t <= 0.0:
		return 0.0
	return px / t


# --- 칼날 폭 리본 (2026-08-01) — 🔴 **판정을 만들지 않는다.** ---
# `motion_phases`·`weapon_weight`와 **같은 자리**다: 표시 전용인데도 여기 있는 이유는 오직
#   "`data/equipment` 전수 트립와이어가 닿아야 하기 때문"이다(J-1·J-2). `player.gd`에 두면 씬 글루라
#   `-s` preload가 안 돼 테스트가 코드보다 느슨한 근사만 쓸 수 있다. **판정 함수와 헷갈리지 마라.**
#
# 리본이 채우는 띠 = `[칼끝 − blade_length, 칼끝]`. 🔴 **칼끝 바깥으로는 절대 안 나간다** —
#   나가면 도달 거리를 실제보다 길게 오해하게 만든다. 안쪽으로 넓어지는 것은 언제나 안전한 방향이고
#   (판정 부채꼴을 **더** 덮는다), 그래서 폭이 커지는 이 변경 자체가 §3 「표시 ⊇ 판정」에 안전하다.
# ⚠ 상한(`MAX_BLADE_LENGTH`)은 "데이터 오타 방어"이고, 진짜 경계(= 무기의 전방 길이)는 텍스처 폭에서
#   나오므로 여기서 못 본다 — `test_combat_math_auto`의 「★칼날 폭 전수」가 그 축을 전수로 지킨다.
const DEFAULT_BLADE_LENGTH := 8.0  # 미지정(0) 폴백 — 옛 칼끝 리본 굵기(7px)와 거의 같다 = 근사 항등
const MIN_BLADE_LENGTH := 2.0
const MAX_BLADE_LENGTH := 64.0     # 최장 근접 무기(창 텍스처 73px) 안에 드는 상한


static func blade_length(equip: EquipDef) -> float:
	if equip == null or not is_finite(equip.blade_length) or equip.blade_length <= 0.0:
		return DEFAULT_BLADE_LENGTH
	return clampf(equip.blade_length, MIN_BLADE_LENGTH, MAX_BLADE_LENGTH)


# --- 메인 하위 직업 궤적 아이덴티티 (2026-08-01) — 표시 전용 ---
# 🔴 **`player.gd`가 아니라 여기 있는 이유는 `blade_length`·`motion_phases`·`weapon_weight`와 같다**
#   (리뷰 J-1·J-2): 씬 글루에 상한을 두면 `-s` preload가 안 돼 **`data/subjobs` 전수 트립와이어가
#   못 닿고**, 테스트는 코드보다 느슨한 근사만 쓸 수 있어 조용히 clamp된 값이 초록으로 샌다
#   (실측 선례: `swing_windup_ratio = 0.02`와 구간 합 0.97이 **둘 다 통과**했다).
#   테스트는 `clamped == raw`를 단정하므로 상한 값을 복제하지 않고도 검출력이 선다.
# 🔴 판정 함수와 헷갈리지 마라 — 이 값은 화면에만 나타나고 사거리·데미지·각 어느 것도 안 움직인다.
# 상한 근거: 잔상 한 장 = `Sprite2D` 하나 = 드로우콜이라 장수가 곧 웹 프레임 비용이다(§5 — 에디터
#   프로파일로 "괜찮다"고 결론 내지 마라). 마무리 타 6장 × 3.0 = 18장이 한 스윙(0.24~0.34s)의 최악이다.
# 하한 0.5 = 잔상을 **끄지는 못하게** 한다(0이면 마무리 타 강조가 통째로 사라지는데 이유가 화면에 없다).
const MIN_FX_GHOST_MULT := 0.5
const MAX_FX_GHOST_MULT := 3.0


static func fx_ghost_mult(sub: SubJobDef) -> float:
	if sub == null or not is_finite(sub.fx_ghost_mult):
		return 1.0
	return clampf(sub.fx_ghost_mult, MIN_FX_GHOST_MULT, MAX_FX_GHOST_MULT)


# 유효 투사체 사거리 — proj_range 특성 + 콤보 타별 배율만큼 길어진다. 둘 다 기본값(0 / 1.0)이면
# **도입 전과 완전 항등**이다.
# 🔴 근접의 effective_attack_range와 같은 자리다: 표시(ArrowField)와 판정(CombatAuthority)이 **같은
#   함수**를 지나야 "맞는 곳 = 보이는 곳"이 유지된다. 유일한 호출부는 GameState.projectile_params
#   하나이고(사거리를 거기서만 리졸브한다), 사본을 만들면 표시 탄과 권한 탄의 수명이 갈라진다.
# 🔴 결과는 그대로 projectile_lifetime_s → clamp_arrow_range(MAX_ARROW_RANGE)를 지난다 — **순서를
#   바꿔 clamp를 우회하지 마라**(심층 방어: 데이터가 커져도 상한 밖으로는 못 나간다). 비유한 base도
#   여기서 판단하지 않고 그 clamp가 DEFAULT로 떨어뜨린다(판단 지점을 늘리지 않는다).
# proj_range = 그 피어가 공지한 하위 직업에서 **각 클라가 로컬 리졸브한** 특성값(player.trait_value).
# combo_mult = 그 타의 사거리 배율(combo_range_mult_at) — **호스트가 센 타수**로 리졸브한다(아래 콤보 절).
static func effective_projectile_range(base_range: float, proj_range: float = 0.0,
		combo_mult: float = 1.0) -> float:
	return base_range * (1.0 + clamp_trait("proj_range", proj_range)) * clamp_combo_mult(combo_mult)


# --- 평타 콤보 (궁수 "평·평·쭉") 단일 소스 (§3, 2026-07-27) ---
#
# 🔴 **리듬은 무기가 정한다** — 값은 전부 `EquipDef.combo_*`(장비 축)에서 온다. 특성 축에 두면
#   GDD §6 🔒("특성은 합계 데미지에 곱해지지 않는 축만")을 어긴다. 여기 함수들은 그 데이터를 읽는
#   **유일한 창구**다: 로컬 입력(player)·표시(arrow_field)·호스트 판정(combat_authority)이 전부
#   이 함수만 지나야 "맞는 곳 = 보이는 곳"과 "클라 리듬 = 호스트가 인정하는 리듬"이 함께 유지된다.
# 🔴 **네트워크로 오가는 것은 타수(정수) 하나뿐**이다(G_SHOOT "cb") — 배율·뜸은 각자 로컬 .tres에서
#   리졸브한다. 차지 레벨(G_SHOOT "c")과 정확히 같은 철학이다: 수치를 전송하면 그게 곧 스푸핑 표면.
const MAX_COMBO_LEN := 8        # 콤보 길이 상한 — 데이터 실수(거대 배열)가 인덱스 산술을 오염시키지 않게
const MAX_COMBO_MULT := 4.0     # 타별 배율 하드 상한 — 데이터 오타(100.0)가 100배 데미지가 되지 않게
# 그 타를 치고 다음 타로 **이어지는** 여유(s) — **기본값이고, 무기가 `combo_grace`로 덮는다**(v2.2).
# 🔴 첫 값(0.45)은 총 0.60s라 훨씬 좁았고, **활은 홀드 연사가 아니라 클릭 1회 = 1발**이라
#   조준하거나 굴렀다가 다시 쏘는 흔한 페이스(0.7s+)에서 콤보가 매번 리셋돼 **"쭉"이 영영 안 나왔다.**
#   그래서 0.8이다 — 이 값은 **활의 것**이다.
# 🔴 **옛 유도("전사 근접과 같은 총 창 0.95s")는 틀렸다 — 2026-07-29에 실측으로 정정했다.**
#   근접 창은 쿨다운이 아니라 **클릭 시점**부터 `player._swing_time + COMBO_WINDOW(0.55)`를 재므로
#   **0.79~0.91s**(무기별)였다. 즉 "둘을 0.95s로 맞춰 뒀다"는 근거는 성립한 적이 없고 최대 160ms
#   어긋나 있었다. 두 창이 **갈라질 이유가 없다**는 결론도 함께 뒤집혔다: 활은 한 발 쏘고 조준하는
#   페이스를 수용해야 하고, 근접은 촘촘히 이어 치는 리듬 자체가 재미다 — **그래서 무기 데이터다.**
# ⚠ 손맛값(§0 예외 — 사용자가 조인다)이지만 **호스트 판정에도 쓰인다**(로컬·호스트가 같은 창을 봐야
#   타수가 안 갈라진다). 그래서 근접 창도 v2.2부터 여기서 나온다 — `player.COMBO_WINDOW`는 **삭제됐다**
#   (그 상수를 노브로 안내하는 문서가 있으면 `EquipDef.combo_grace`로 고쳐라).
const COMBO_GRACE_S := 0.8
# 데이터 오타 방어 — 창이 몇십 초가 되면 콤보가 사실상 영영 리셋되지 않아 마무리 타가 상시가 된다.
const MAX_COMBO_GRACE_S := 2.0
# 🔴 마무리 타 대시 거리 상한(px). **유도 = 기존 clamp를 건드리지 않는 최대치**:
#   최저 `player._max_roll_speed`(전사 `move_speed` 100 × `ROLL_SPEED_MULT` 2.6 = **260px/s**,
#   이속·`roll_dist` 특성 0일 때) × 최단 대시 구간(= `swing_time × (windup + strike) ×
#   haste_scale(0.5)` ≈ 0.09s) ≈ 23px → **여유를 두어 20px.**
# ⚠ **clamp 함수 이름을 헷갈리지 마라** — 걷기 상한 `_max_move_speed()`는 100px/s이고, 대시가 걸리는
#   것은 **구르기 상한** `_max_roll_speed()`(260)다. 이 유도가 처음엔 전자로 잘못 적혀 있었다(숫자는 맞고
#   이름이 틀렸다 — 2026-07-29 dev 보고 ⑵-5).
# 🔴 **23이 아니라 20인 이유 = 여유 1.7%는 너무 얇다.** 23px면 최대 haste에서 255.6px/s로 상한 260에
#   **1.7%**까지 붙어, 프레임 지터나 부동소수 오차 한 번에 `limit_length`가 **정당한 대시를 깎는다**
#   (그러면 원격 외삽이 과소평가되고 "피했는데 맞았다"가 부분 재발한다). 20px면 222px/s = **14.6% 여유**.
# 🔴 **이 값을 올리면 `LAG_MAX_LEAD_DIST`와 clamp 3곳**(`_max_move_speed` · 원격 속도 clamp ·
#   원격 변위 clamp)**을 함께 재유도해야 한다** — `roll_dist` 특성이 밟은 그 자리다(rules §2 게이트).
#   안 하면 정당한 대시가 원격에서 깎여 외삽이 과소평가되고 "피했는데 맞았다"가 부분 재발한다.
# ✅ 반대로 **이 상한 안에서는 재유도가 불필요하다** — `LAG_MAX_LEAD_DIST`의 유도가 이미 최대
#   483px/s(143 × 3.38)를 상정하므로 200~300px/s짜리 대시는 외삽 상한을 못 넘긴다(2026-07-29 검산).
const MAX_COMBO_DASH := 20.0


# 그 무기의 콤보 길이 — 세 배열 중 **가장 긴 것**. 전부 비면 1(= 콤보 없음, 항등).
# 한 축만 채워도 되게 max를 쓴다(길이를 손으로 맞추게 하면 다음 사람이 반드시 어긋나게 적는다).
static func combo_len(equip: EquipDef) -> int:
	if equip == null:
		return 1
	var n := maxi(equip.combo_range_mult.size(),
		maxi(equip.combo_damage_mult.size(), equip.combo_delay.size()))
	return clampi(n, 1, MAX_COMBO_LEN)


static func clamp_combo_index(index: int, equip: EquipDef) -> int:
	return clampi(index, 0, combo_len(equip) - 1)


# 그 타수가 **마무리 타**인가 — 데미지 배율·판정 각·표시 각·카메라 킥이 전부 이 술어로 갈린다.
# 🔴 **표시(player)와 판정(combat_authority)이 반드시 같은 함수를 지나야 한다** (v2.2 리뷰 요청으로
#   신설 — 그전엔 두 파일에 한 줄짜리 사본이 있었다). 갈라지면 **"판정만 마무리"** = 판정 각이 넓은데
#   궤적은 평타 = *"안 보이는데 맞는다"* 가 되고, 그건 §3이 구조로 막아 온 바로 그 방향이다.
# 🔴 **`n > 1` 가드가 항등을 지킨다** — 콤보 배열이 없는 무기(길이 1)는 index 0이 곧 마지막이라
#   가드가 없으면 **매 타가 마무리로 읽혀** 표시 각이 여유만큼 넓어지고 킥·내지르기가 상시 발동한다
#   (= 콤보 도입 전과 다른 동작). `advance_combo`의 "n ≤ 1 → 항상 0"과 같은 부호다.
static func is_combo_finish(equip: EquipDef, index: int) -> bool:
	var n := combo_len(equip)
	return n > 1 and index >= n - 1


# 이번 타를 **반대 방향으로** 휘두르는가(왕복). true = 우→좌, false = 좌→우.
# 🔴 **패리티(`index % 2`)여야 한다 — 절대 위치(`index == 1`)는 3타 이상에서 왕복이 끊긴다.**
#   두 규칙의 진리값을 그대로 적는다(⚠ **2026-07-29에 이 주석을 정정했다** — 처음 적은 근거 셋이
#   전부 사실이 아니었다. 리뷰 I-7이 검산으로 잡았다):
#     index │ 0        1      2        3
#     옛    │ 정방향   반전   정방향   **정방향**
#     새    │ 정방향   반전   정방향   **반전**
#   즉 실제로 달라지는 것은 **index 3 하나**이고, 그것이 고치는 것은 *"index 2와 3이 **연속으로 같은
#   방향**으로 나가 팔이 순간이동해 보이는 것"* 이다 — 4타 무기(창)에서만 나타난다.
# ⚠ **다음 셋은 패리티로도 안 바뀐다 — 근거로 쓰지 마라:**
#     · 도끼(2타)는 여전히 index 1이 **반전 + 마무리 동시**다(겹침은 남는다. 다만 마무리 조건이
#       `len − 1`이라 타수가 늘면 자동으로 갈라지므로, 겹치는 것 자체가 결함은 아니다)
#     · 창(4타)의 index 0과 2는 여전히 **픽셀 단위로 같은 궤적**이다(왕복의 정상 동작이다)
# 🔴 **이 함수가 `player.gd`가 아니라 여기 사는 이유는 검출력이다** — 씬 글루는 `-s` preload가 안 돼
#   테스트가 겨눌 수 없고, 실제로 이 규칙을 `== 1`로 되돌리는 뮤테이션에서 **스위트가 9/9 초록**이었다
#   (2026-07-29 dev 보고 ④). 데이터·규칙이 만족해야 하는 것은 core에 둔다(리뷰 J-1·J-2와 같은 처방).
static func is_combo_swing_reversed(index: int) -> bool:
	return index % 2 != 0


# 🔴 GDD §6 예산표의 「콤보 축(사이클 DPS 비) ≤ 1.3배」 — **코드가 쥔 정본이다.**
#   문서에만 두면 테스트가 값을 **복제**해야 하고, 그러면 예산을 고칠 때 두 곳이 갈라진다(하네스의
#   지배 고장 모드 — DECISIONS 2026-07-26). 트립와이어는 이 상수를 참조해 `data/equipment` 전수를 잰다.
# ⚠ **단위는 「사이클 DPS 비」다 — 타별 배율이 아니다.** 도끼의 타별 배율 2.2는 이 값과 비교할 수 없고
#   (사이클로 환산하면 1.219), 타별 배율의 상한은 `MAX_COMBO_MULT`(4.0)가 따로 잡는다.
const COMBO_CYCLE_DPS_MAX := 1.3


# 배율 clamp — 비유한/0 이하는 **1.0(항등)** 으로 떨어뜨린다. "데이터가 비었다"와 "데이터가 깨졌다"를
# 같은 안전값으로 모으는 것이 규약이다(clamp_projectile_speed와 같은 관용구).
static func clamp_combo_mult(mult: float) -> float:
	if not is_finite(mult) or mult <= 0.0:
		return 1.0
	return minf(mult, MAX_COMBO_MULT)


static func combo_range_mult_at(equip: EquipDef, index: int) -> float:
	return _combo_arr_at(equip.combo_range_mult if equip != null else PackedFloat32Array(), index)


static func combo_damage_mult_at(equip: EquipDef, index: int) -> float:
	return _combo_arr_at(equip.combo_damage_mult if equip != null else PackedFloat32Array(), index)


static func _combo_arr_at(arr: PackedFloat32Array, index: int) -> float:
	if index < 0 or index >= arr.size():
		return 1.0  # 배열이 짧으면(한 축만 채운 무기) 그 타는 항등
	return clamp_combo_mult(arr[index])


# 마무리 타에 몸이 앞으로 나가는 거리(px). 0 = 없음 = **도입 전과 항등**.
# 🔴 이동은 지연 보상의 입력이다 — 상한(`MAX_COMBO_DASH`)의 유도와 재유도 조건은 그 상수 주석이 정본이다.
# 🔴 부르는 쪽은 이 거리를 **`velocity`로** 흘려야 한다(`position` 대입 금지 — G_POS `vx/vy`가 0이면
#   호스트 lead 외삽이 변위를 못 덮어 마무리 타가 게스트에서 무음 거부된다).
# 평타(마무리가 아닌 타)의 전진 비율 — 사용자 요청 2026-08-01: "평타 1타 2타도 조금씩 움직이게".
# 🔴 **비율이지 별도 값이 아니다** — 무기가 `combo_dash` 하나만 쥐면 "무거운 무기가 크게 파고든다"가
#   타수와 무관하게 한 축으로 유지된다. 값을 따로 두면 둘이 갈라져 다음 튜닝에서 한쪽만 고친다.
# ⚠ 상한 재유도가 불필요한 이유: 이 비율이 1.0 이하라 **각 타의 대시가 `MAX_COMBO_DASH`(20px)를
#   절대 못 넘는다.** 그 상수 주석의 유도(최대 haste 222px/s vs 최저 clamp 260)가 그대로 성립한다.
const NONFINISH_DASH_RATIO := 0.4


# `is_finish = false`면 평타 비율이 곱해진다. 기본값 true는 도입 전과 완전 항등이다.
static func combo_dash_dist(equip: EquipDef, is_finish: bool = true) -> float:
	if not is_finish:
		var base := combo_dash_dist(equip, true)
		return base * NONFINISH_DASH_RATIO
	if equip == null or not is_finite(equip.combo_dash) or equip.combo_dash <= 0.0:
		return 0.0
	return minf(equip.combo_dash, MAX_COMBO_DASH)


# 그 타 **직전**의 추가 뜸(s). 배열 밖·비유한·음수는 0(뜸 없음).
# ⚠ 상한은 COMBO_GRACE_S가 아니라 창 유도식(combo_window_s)이 흡수한다 — 뜸이 길어지면 창도 같이 길어진다.
static func combo_delay_at(equip: EquipDef, index: int) -> float:
	if equip == null or index < 0 or index >= equip.combo_delay.size():
		return 0.0
	var d := equip.combo_delay[index]
	if not is_finite(d) or d <= 0.0:
		return 0.0
	return d


# 🔴 그 타를 치기 위한 **최소 간격**(s) = 직업 쿨다운 + 그 타의 뜸, 둘 다 haste로 짧아진다.
#   뜸에도 haste_scale을 곱하는 이유는 쿨다운·스윙 창·차지 스텝과 같다(§3 haste 계약) — 안 곱하면
#   공속을 올릴수록 리듬이 뜸에 지배돼 궁수에게 공속이 무가치해진다.
# 로컬(player가 _attack_cd_left에 심는 값)과 호스트 판정(advance_combo)이 **같은 함수**를 지난다.
static func combo_gap_s(job: JobDef, equip: EquipDef, index: int, haste: float = 0.0) -> float:
	return (job.attack_cooldown + combo_delay_at(equip, index)) * haste_scale(haste)


# 콤보가 이어지는 창(s) — 이보다 더 쉬면 처음(0타)으로 돌아간다.
# 🔴 **gap에서 유도한다(독립 상수 금지)** — `window = gap + GRACE > gap > min_gap`이 항상 성립해야
#   "너무 빨라서 리셋"과 "너무 쉬어서 리셋" 두 조건이 겹치지 않는다. 겹치면 어떤 데이터에서는
#   정직한 발사가 **어느 쪽으로도 콤보를 못 잇는** 죽은 구간이 생긴다(에러 없이 3타가 영영 안 나온다).
static func combo_window_s(job: JobDef, equip: EquipDef, index: int, haste: float = 0.0) -> float:
	return combo_gap_s(job, equip, index, haste) + combo_grace_s(equip)


# 그 무기의 콤보 이어짐 여유(s) — 0/비유한/음수는 `COMBO_GRACE_S`(활 기본)로 떨어진다 = 항등 폴백.
# 🔴 창을 읽는 곳은 `combo_window_s` 하나이고 그것이 로컬·호스트 공용이다 — 이 함수를 우회해
#   `COMBO_GRACE_S`를 직접 더하면 근접 무기에서 **클라와 호스트의 창이 갈라진다**(내 화면은 3타인데
#   판정은 평타 = `min`이 0을 택한다).
static func combo_grace_s(equip: EquipDef) -> float:
	if equip == null or not is_finite(equip.combo_grace) or equip.combo_grace <= 0.0:
		return COMBO_GRACE_S
	return minf(equip.combo_grace, MAX_COMBO_GRACE_S)


# 🔴 호스트가 그 타를 **인정하는 최소 간격**(s) — `combo_gap_s`(클라가 실제로 내는 간격)보다 관대하다.
#
# 왜 따로 있나: 호스트가 재는 것은 **자기 수신 시각의 차**이지 상대가 쏜 시각의 차가 아니다.
#   연속 두 G_SHOOT의 편도 지연이 다르면(앞 패킷이 더 늦게 도착하면) 측정 간격이 **실제보다 짧아** 보이고,
#   그러면 뜸을 정직하게 낸 궁수가 마무리 타를 못 받는다 — 발사가 사라지는 것보단 낫지만
#   "가끔 강화살이 안 나온다"가 되고 원인이 화면에 안 드러난다. 관대한 쪽으로 틀리는 것이 안전한 방향이다.
#
# 🔴 유도식 (독립 상수를 두지 않는다 — 전부 기존 값에서 나온다):
#     min_gap(i) = (attack_cooldown × FIRE_RATE_SLACK + max(0, delay_i − LAG_MAX_ONE_WAY_MS)) × haste_scale
#   ⑴ **기본 쿨다운분은 기존 관용구 그대로**(×FIRE_RATE_SLACK) — `is_fire_rate_ok`가 이미 그 값으로
#      게이트하고 있으므로, 여기서 더 조이면 그 게이트를 통과한 발사를 두 번째 잣대로 다시 재는 셈이 된다.
#   ⑵ **뜸(추가분)에서는 `LAG_MAX_ONE_WAY_MS`(200ms)를 통째로 깎는다.** 그 상수가 이 프로젝트가
#      선언한 "편도 지연 인정 상한"이고, 측정 간격이 실제보다 짧아질 수 있는 양의 상한이 바로
#      앞 패킷의 편도 지연이다(= 최악 200ms). 즉 **전송이 삼킬 수 있다고 우리가 이미 인정한 만큼**을
#      정직한 플레이어에게 돌려준다. 이보다 좁게 잡을 근거가 이 코드베이스 안에 없다.
#   ⚠ **delay ≤ LAG_MAX_ONE_WAY_MS면 뜸분이 0이 되어 게이트가 `is_fire_rate_ok`와 같아진다** — 즉
#      "전송 불확실성보다 작은 뜸은 호스트가 검증할 수 없다"를 그대로 인정하는 것이다(있는 척하지 않는다).
#      그 무기는 마무리 타를 사실상 공짜로 준다 → `test_combat_math_auto`가 **무기별로** 그 상태를
#      단정해 빨개진다("최속 스팸이 마무리 타에 도달"). 조용한 절벽을 시끄럽게 만든 것이다.
#
# ⚠ 이 게이트는 **리듬 확인이지 치트 방지 원장이 아니다.** 조작 클라는 여기까지만 앞당길 수 있고
#   (현 데이터에서 마무리 타 0.40s → 0.185s), 그 상한은 여전히 `is_fire_rate_ok`가 잡는다.
#   협동 2인·PvP 없음이라 수용한다(rules §2 4인/PvP 게이트에서 재검토).
static func combo_min_gap_s(job: JobDef, equip: EquipDef, index: int, haste: float = 0.0) -> float:
	var extra := maxf(0.0, combo_delay_at(equip, index) - LAG_MAX_ONE_WAY_MS / 1000.0)
	return (job.attack_cooldown * FIRE_RATE_SLACK + extra) * haste_scale(haste)


# 🔴 다음 콤보 타수 — 로컬(player)과 호스트 판정(combat_authority)이 **같은 함수**를 지난다(§3).
#   elapsed_s = 직전 발사로부터의 경과. 클라는 자기 발사 시각, 호스트는 자기 수신 시각으로 잰다.
# 규칙은 셋뿐이다:
#   ⑴ 콤보 없는 무기(길이 1) → 항상 0 (법사 지팡이 = 도입 전과 항등)
#   ⑵ 너무 **쉬었으면**(> window) 처음부터 — 리듬이 끊긴 것
#   ⑶ 🔴 너무 **빨랐으면**(< combo_min_gap_s) 처음부터 — **뜸을 내지 않은 자는 다음 타를 못 얻는다**
#      ⚠ 기준이 `combo_gap_s`가 아니라 **`combo_min_gap_s`**(관대한 하한)인 것이 핵심이다 —
#        호스트는 자기 수신 간격으로 재므로 지터가 정직한 간격을 짧아 보이게 만들 수 있다(그 함수 주석).
# 🔴 ⑶이 "발사 거부"가 아니라 "리셋"인 것이 계약의 핵심이다. 거부로 만들면 호스트/클라의 타수가
#   창 경계 지터로 한 번 어긋났을 때 **정당한 발사가 통째로 사라진다**(화살이 안 생기고 이유가 화면에
#   안 드러난다 — 이 프로젝트가 반복해 겪은 "조용히 깨진다" 부류). 리셋이면 최악이 "이번 타는 평타"다.
#   그러면서 방어력은 더 세다: 쿨다운만 지키며 스팸하는 조작 클라는 index가 0↔1만 오가 **마무리 타에
#   영영 도달하지 못한다**(뜸이 곧 마무리 타의 대가라는 설계 그대로).
static func advance_combo(prev_index: int, elapsed_s: float, job: JobDef, equip: EquipDef,
		haste: float = 0.0) -> int:
	var n := combo_len(equip)
	if n <= 1 or job == null:
		return 0
	if not is_finite(elapsed_s):
		return 0
	var nxt := (clampi(prev_index, 0, n - 1) + 1) % n
	if elapsed_s < combo_min_gap_s(job, equip, nxt, haste) \
			or elapsed_s > combo_window_s(job, equip, nxt, haste):
		return 0
	return nxt


# 🔴 **판정에 쓰는 콤보 타수 = 이 함수 하나**(호스트 전용, §3 신뢰 경계).
#   claimed = G_SHOOT "cb"(발신자 주장, 표시용) · prev_index = 호스트가 그 피어에게 마지막으로 인정한 타수.
# 🔴 호스트는 주장을 **믿지 않고 직접 센다** — 안 그러면 클라가 매 발사에 "나 마무리 타야"라고 주장해
#   항상 강화살(사거리 2배·데미지 2.5배)을 얻는다. 근접 콤보(G_ATK "cb")가 궤적만 정해 조작돼도 화면만
#   달라졌던 것과 **성격이 다르다** — 여기 타수는 사거리·데미지를 바꾸므로 신뢰 경계가 새로 생긴다.
# 🔴 주장을 **상한으로만** 쓴다(min): 호스트가 센 값보다 크게는 못 가고, 작게 주장하면 자기 손해다.
#
# 🔴 **규약 — "화면에 없는데 맞는" 방향은 구조적으로 불가능해야 한다** (2026-07-27 리드 승격).
#   표시(ArrowField)는 발신자 주장 타수를 그대로 그리므로 `min` 덕에 **판정 ≤ 표시**가 항상 성립한다.
#   min이 없으면 창 경계 지터에서 **화면엔 짧은 화살인데 판정은 300px 밖 적을 죽이는** 방향이 열린다.
#   있으면 갈라짐은 항상 "그려졌는데 안 맞는다"(빗나감으로 읽히는 쪽)로만 떨어진다.
#   같은 규약의 다른 구현이 이미 둘 있다 — 보스 텔레그래프는 경계 여유를 격자에서 유도해 **틀리면 반드시
#   과예고 방향**으로 고정했고(rules §3), `projectile_params`의 `w`(무기 사칭)는 사칭자 화면에만
#   폭발을 그린다. **새 표시/판정 쌍을 만들 때 이 부등호의 방향부터 정해라.**
static func authoritative_combo(claimed: int, prev_index: int, elapsed_s: float,
		job: JobDef, equip: EquipDef, haste: float = 0.0) -> int:
	var counted := advance_combo(prev_index, elapsed_s, job, equip, haste)
	return mini(clamp_combo_index(claimed, equip), counted)


# 투사체 수명(s) = clamp(사거리)/clamp(속도). arrow_lifetime_s의 일반화 —
# 무기별 탄속이 갈리는 charge 무기(느린 마법탄)도 표시·권한이 같은 값을 리졸브해 결정론 유지.
static func projectile_lifetime_s(travel_range: float, speed: float) -> float:
	return clamp_arrow_range(travel_range) / clamp_projectile_speed(speed)


# --- 차지 발사(법사 지팡이) 단일 소스 (§3, 2026-07-24) ---
# 마우스를 눌러 모은 단계(0~MAX)만큼 위력·폭발 반경이 커진다. 단계 배율은 여기 공용 상수 —
# 네트워크로는 "레벨(정수)"만 오가고(G_SHOOT "c"), 실제 수치는 각 클라·호스트가 이 표에서 리졸브한다.
# (배율 자체를 전송하면 스푸핑 표면이 된다 — 궁수 r clamp 철학과 동일.)
const MAX_CHARGE_LEVEL := 3
const CHARGE_DAMAGE_MULT: Array[float] = [1.0, 1.7, 2.5, 3.4]   # 레벨별 데미지 배율 (0 = 탭 발사)
const CHARGE_RADIUS_MULT: Array[float] = [1.0, 1.45, 1.9, 2.4]  # 레벨별 폭발 반경 배율
const CHARGE_ORB_SCALE: Array[float] = [0.6, 0.85, 1.1, 1.4]    # 레벨별 탄/차지 오브 표시 스케일 (표시 전용 — 반경 미러 아님)
const MAX_BLAST_RADIUS := 140.0  # 폭발 반경 상한 — 게스트 주장 무기(w)가 어떤 값이든 이 이상으로는 안 터진다(§3 신뢰 경계)


static func clamp_charge_level(level: int) -> int:
	return clampi(level, 0, MAX_CHARGE_LEVEL)


# 홀드 시간 → 차지 레벨. step_time이 0/음수/비유한이면 차지 불가(레벨 0) — 데이터 오염 가드.
static func charge_level_for(held_s: float, step_time: float) -> int:
	if not (is_finite(held_s) and is_finite(step_time)) or step_time <= 0.0 or held_s <= 0.0:
		return 0
	return clamp_charge_level(int(held_s / step_time))


# 차지 데미지 = 기본 데미지(calc_damage) × 레벨 배율. UI 표시와 호스트 확정이 같은 함수.
static func charge_damage(base_damage: int, level: int) -> int:
	return int(round(float(base_damage) * CHARGE_DAMAGE_MULT[clamp_charge_level(level)]))


# 폭발 반경 = 무기 기준 반경 × 레벨 배율 (상한 clamp). 호스트 판정 반경 = 표시 FX 스케일 기준 —
# 한쪽만 고치면 "맞는 곳"과 "보이는 곳"이 어긋난다 (§3, is_strike_hit·telegraph와 같은 철학).
static func charge_blast_radius(base_radius: float, level: int) -> float:
	if not is_finite(base_radius) or base_radius <= 0.0:
		return 0.0  # 폭발 없는 무기(일반 화살) — 단일 명중
	return minf(base_radius * CHARGE_RADIUS_MULT[clamp_charge_level(level)], MAX_BLAST_RADIUS)


# 폭발 명중 판정 — 폭발 중심에서 반경 안의 적/대상 전부. is_strike_hit 재사용(같은 거리 질의, 단일 소스).
static func is_blast_hit(target_pos: Vector2, blast_center: Vector2, radius: float, target_radius: float = 0.0) -> bool:
	return is_strike_hit(target_pos, blast_center, radius + target_radius)


# 호스트의 차지 레벨 검증 — 주장한 레벨만큼 실제로 모을 시간이 있었는가 (마지막 발사 이후 경과 기준).
# 연사하며 항상 c=MAX를 주장하는 스푸핑을 막는다 (is_fire_rate_ok의 차지 버전 — 지터 여유 0.9배 동일).
# ⚠ 첫 발사(last_shot 미기록)는 통과 — 입장 후 충분히 모을 시간이 있었다고 본다.
static func is_charge_time_ok(last_shot_msec: int, now_msec: int, level: int, step_time: float,
		haste: float = 0.0) -> bool:
	var lv := clamp_charge_level(level)
	if lv <= 0:
		return true
	if not is_finite(step_time) or step_time <= 0.0:
		return false  # 차지 못 하는 무기인데 레벨을 주장 = 거부
	# 차지 단계 시간도 공속으로 짧아진다(사용자 확정 2026-07-25) — 안 그러면 리듬이 차지에 지배되는
	# 법사에게 공속이 무가치해진다. 검증도 같은 배율을 써야 빨라진 정당 차지가 거부되지 않는다.
	var step := effective_charge_step(step_time, haste)
	return now_msec - last_shot_msec >= int(float(lv) * step * FIRE_RATE_SLACK * 1000.0)


# 화살 명중 판정 — 호스트만. 화살 현재 위치와 적 중심 거리 <= 화살굵기+적반경.
# is_strike_hit 재사용(같은 거리 질의) — 물리 레이어 대신 매 프레임 거리 질의라 물리 레이어 함정(§5) 회피 + 단위 테스트 가능.
static func is_arrow_hit(arrow_pos: Vector2, enemy_pos: Vector2, enemy_radius: float = 0.0) -> bool:
	return is_strike_hit(arrow_pos, enemy_pos, ARROW_HIT_RADIUS + enemy_radius)


# 이 적이 원거리인가 — **값에서 유도한다**(별도 bool 플래그 금지).
# 🔴 플래그를 두면 두 번째 진실원이 되어, 배우 분기(mob_melee)와 데이터 트립와이어가 서로 다른
#   기준을 보게 된다. 한 함수를 같이 지나면 "속도·사거리가 있는 적 = 원거리"가 구조로 보장된다.
# ⚠ 몹 화살 명중 판정은 `is_arrow_hit`(적을 겨눈 점-원, 지연 보상 없음)이 아니라
#   `is_strike_hit_lagged`를 쓴다 — 대상이 **플레이어**이므로 §3 「방어자 우대」가 강제된다.
static func is_ranged_enemy(def: EnemyDef) -> bool:
	return def != null and def.proj_speed > 0.0 and def.proj_range > 0.0


# 호스트의 발사 쿨다운 검증 — 발사 간격은 공격자 job 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 발사율 이상 못 얻는다.
# 근접의 is_hit_cooldown_ok와 달리 SAME_SWING 다중타격 허용이 없다 — 화살 하나=한 발이라 매 발사 독립 게이트.
static func is_fire_rate_ok(last_shot_msec: int, now_msec: int, job: JobDef, haste: float = 0.0) -> bool:
	return now_msec - last_shot_msec >= int(effective_cooldown(job, haste) * FIRE_RATE_SLACK * 1000.0)


# 🔴 홀드 연사(`auto_fire`)가 **자동으로** 내는 발사 간격(s) — 위 게이트 **위**에 오도록 유도한다.
#
# 왜 쿨다운을 그대로 쓰면 안 되나 (2026-07-28 netreview C2):
#   `is_fire_rate_ok`의 임계는 `cooldown × FIRE_RATE_SLACK`이라 **여유가 쿨다운에 비례**한다.
#   궁수 0.15초에서 그 여유는 **15ms**뿐인데, 호스트가 재는 것은 자기 **수신 처리 시각**의 차라
#   프레임 양자화 하나(웹 30fps = 33ms)만으로 넘어간다. 사람의 클릭은 경계에 안 붙어서 이 좁음이
#   지금까지 안 드러났고, 홀드 연사는 **모든 발사를 경계에 못 박는다**.
#   거부돼도 표시 화살(`arrow_field`)은 게이트 없이 날아가므로 **데미지만 0**이 된다 —
#   HUD·소리·반동이 전부 정상이라 화면에 이유가 없다. 게다가 호스트 자신은 이 게이트를 안 지나
#   (`combat_authority._on_player_shoot`) **게스트만** 손해 본다.
#
# 🔴 **클라가 물러선다 — 게이트를 넓히지 않는다.** `FIRE_RATE_SLACK`을 키우면 조작 클라의 스팸 상한이
#   같이 올라가 신뢰 경계가 넓어진다(rules §2 4인/PvP 게이트 대상). 클라가 여유를 내면 표면은 그대로다.
#   대가 = 홀드의 실효 DPS가 상한에 못 미치는 것인데, 그건 오히려 "홀드는 **편의**이지 강화가 아니다"
#   (TRAIT_MAX["auto_fire"] 주석)와 부합한다. 클릭으로 끊어 치는 쪽이 리듬·사거리 둘 다 얻는다.
#
# 🔴 유도 — **여유의 목표선은 "호스트 프레임 1주기"이지 비율이 아니다.** 슬랙을 나눠서 되돌리는
#   것(`cooldown / SLACK`)만으로는 궁수 0.15초에서 여유가 **31.7ms**라 30fps 프레임(33.3ms)에
#   못 미친다 — 비율 여유는 쿨다운이 짧을수록 작아지는데 **양자화는 쿨다운에 비례하지 않기** 때문이다.
#   그래서 둘 중 큰 쪽을 쓴다:
#     ⑴ `cooldown / SLACK`      — 긴 쿨다운(전사 0.4·법사 0.5)에서 지배. 비율 여유가 이미 충분하다.
#     ⑵ `cooldown × SLACK + 프레임` — 짧은 쿨다운(궁수 0.15)에서 지배. **임계 위에 프레임 하나**를 얹는다.
#   경계는 `cooldown ≈ 0.158초`다. 결과적으로 궁수 홀드 간격 = 168ms(쿨다운 150ms의 **112%**) —
#   실효 DPS가 클릭 리듬의 약 92%가 되어 "홀드는 편하지만 조금 약하다"가 데이터로 성립한다.
const AUTO_FIRE_HOST_FRAME_S := 1.0 / 30.0  # 호스트 수신 처리의 최악 양자화(웹 30fps). 60fps면 절반이 여유로 남는다
# ⚠ 실기에서 여전히 화살이 산발적으로 씹히면 여기를 조인다 — `docs/TUNING.md` §9.
static func auto_fire_gap_s(job: JobDef, haste: float = 0.0) -> float:
	var cd := effective_cooldown(job, haste)
	return maxf(cd / FIRE_RATE_SLACK, cd * FIRE_RATE_SLACK + AUTO_FIRE_HOST_FRAME_S)


# --- 클릭 발사 경로의 `auto_fire_gap_s` 대칭 (선입력 버퍼, netreview C-1~C-3 2026-08-01) ---
# 🔴 **C2(2026-07-28)가 홀드에만 여유를 붙인 근거가 깨졌다.** 그 근거는 *"사람의 클릭은 경계에 안
#   붙는다"* 였는데, 선입력 버퍼가 살려 낸 클릭은 발사 간격을 `combo_gap_s`에 **정확히 못 박는다.**
#   그러면 남는 여유가 구조적 마진(`cd × (1 − FIRE_RATE_SLACK)`)뿐이고, **웹 30fps 호스트의 수신
#   프레임 양자화**(`AUTO_FIRE_HOST_FRAME_S`)가 그중 33.3ms를 먹어 전사 haste 0의 실예산이 6.7ms다.
# 🔴 실패는 셋 다 **무증상**이다:
#   · `advance_combo` 하한 미달 → 콤보 리셋 뒤 호스트 인덱스가 클라보다 **영구히 1 뒤처져** 마무리
#     타가 그 교전 내내 평타로 확정된다(해제 = 800ms 이상 정지). 연출은 전부 정상.
#   · `is_hit_cooldown_ok` 미달 → 타격 **통째로 소실**(스윙·궤적·소리·반동 다 나오고 적 HP만 그대로).
# 🔴 **클라가 물러선다 — 호스트 게이트를 넓히지 않는다.** `FIRE_RATE_SLACK`은 근접·발사율·차지·콤보
#   **네 게이트 공유**라 넓히면 스팸 상한이 같이 오른다(`auto_fire_gap_s`가 세운 그 선례 그대로).
# 🔴 **여유는 「버퍼가 살려 낸 클릭」에만 문다 — 즉시 클릭은 완전 항등이다.** 쿨다운이 이미 끝난 뒤에
#   누른 클릭은 사람의 반응 지연 덕에 간격이 이미 `combo_gap_s`보다 크다. 새로 연 경로만 새 비용을
#   낸다는 부호이고, §3 「오차는 누가 대가를 치르는가로 기울인다」와 같은 자리다.
#   ⚠ 그래서 이 함수는 **DPS 상한을 안 내린다** — 프레임 완벽하게 치는 사람은 여전히 `combo_gap_s`다.
static func buffered_attack_grace_s() -> float:
	return AUTO_FIRE_HOST_FRAME_S


# 버퍼가 살려 낸 클릭의 **실제 발사 간격**(s) — `player.gd`가 쓰는 값이자 트립와이어가 겨누는 값.
# ⚠ 트립와이어가 `combo_gap_s`를 직접 적으면 "여유 항을 지우는 뮤테이션"을 못 잡는다(J-1 관용구).
static func buffered_attack_gap_s(job: JobDef, equip: EquipDef, index: int, haste: float = 0.0) -> float:
	return combo_gap_s(job, equip, index, haste) + buffered_attack_grace_s()


# --- 근접 스윙의 두 게이트 (선딜/후딜 축 2026-07-28, netreview I-3) ---
# 🔴 **둘 다 호스트 임계에서 한 프레임만큼 물러나되 부호가 반대다 — 그게 계약이다.**
#   호스트가 재는 것은 클라의 입력 간격이 아니라 **도착 간격**이고, 게스트에선
#   `도착 = 클라 간격 + (편도₂ − 편도₁)`이라 임계에 딱 붙이면 음의 지터 한 번에 갈린다.
#   · 스로틀(+): "호스트가 받아 줄 만큼 **늦게**" — 판정을 미룬다. 늦는 쪽이 안전.
#   · 연출 게이트(−): "호스트가 받아 주는 타격은 **반드시 보여야**" — 관대한 쪽이 안전.
#   🔴 같은 부호로 통일하려는 변경은 둘 중 하나를 반드시 망가뜨린다
#     (§3 「방어자 우대」와 「대상 좌표 각 슬랙」이 의도적으로 반대 부호인 것과 같은 형태).

# 클라 자기 스로틀 — 근접 판정(G_HIT_REQ)을 이 간격보다 촘촘히 내보내지 않는다.
# 🔴 **`cd`로 clamp하는 것이 안정성 조건이다.** 점화식이 `x[n+1] = max(t_hit, x[n] − cd + gate)`라
#   `gate > cd`면 매 스윙 `(gate − cd)`씩 **영구 누적**된다. clamp가 있으면 `gate ≤ cd`라 수렴하고,
#   덤으로 **"같은 무기 연타는 완전 항등"이 데이터가 아니라 구조로** 보장된다(항등 조건 = `gate ≤ cd`).
# 🔴 **clamp는 에지 케이스가 아니라 상시 동작이다** (2026-07-28 netreview 3차 정정).
#   `LEVEL_STAT_MAX["haste"]`가 **0.5**이므로 전사 실측:
#     haste 0.0 → cd 0.4000 · gate 0.3933 (−6.7ms, 안정)
#     haste 0.2 → cd 0.3333 · gate 0.3333 (**0 = clamp 발동점**)
#     haste 0.5 → cd 0.2667 · gate 0.2733 (**+6.7ms 발산**)
#   즉 발동 조건이 `cd ≤ 1/3` ⇔ 전사 `haste ≥ 0.2`라 **haste 범위의 상위 60%에서 상시 걸린다.**
#   ⚠ 이 수치를 "최대 haste에서 1.3ms"로 적었던 초판은 상한을 0.25로 잘못 잡은 것이었다 —
#     5배 작은 값이라 "무시해도 되겠네"로 읽히던 자리다. 테스트는 `LEVEL_STAT_MAX`를 읽으므로 옳았다.
# 🔴 **clamp가 걸리면 감쇠율(`cd − gate`)이 0이 되어 점화식이 `x[n+1] = max(t_hit, x[n])` = 래칫이다.**
#   느린 무기의 부풀린 지연을 빠른 무기가 영구히 물고 간다(헛치기 한 번이 유일한 해제).
#   그래서 이 clamp만으로는 부족하고 **한 스윙의 추가 지연 자체에 상한**이 필요하다 — 아래 참조.
static func melee_throttle_gap_s(job: JobDef, haste: float = 0.0) -> float:
	var cd := effective_cooldown(job, haste)
	return minf(cd * FIRE_RATE_SLACK + AUTO_FIRE_HOST_FRAME_S, cd)


# 원격 스윙 연출 스팸 게이트 — 이 간격 안에 다시 온 G_ATK는 연출을 재시작하지 않는다.
# 🔴 호스트 임계보다 **관대**해야 한다: 삼켜지면 상대 화면에서 그 타격이 **없었던 일**이 되는데
#   (궤적·소리·무기 모션이 전부 사라진다) HP는 깎인다 — 화면에 이유가 안 드러나는 부류다.
static func melee_fx_gate_s(job: JobDef, haste: float = 0.0) -> float:
	var cd := effective_cooldown(job, haste)
	return maxf(cd * FIRE_RATE_SLACK - AUTO_FIRE_HOST_FRAME_S, 0.0)


# 🔴 **한 스윙이 자기 스로틀로 미뤄질 수 있는 최대 추가 지연** (netreview 3차 ②, 2026-07-28).
#   위 `minf(..., cd)` clamp는 `cd ≤ 1/3` ⇔ **전사 haste ≥ 0.2에서 상시** 발동한다(상한 0.5의 상위 60%).
#   그 구간에선 `gate == cd`라 점화식의 감쇠가 **0**이 되어 `x[n+1] = max(t_hit, x[n])` = **단조
#   비감소(래칫)** 가 된다 — 도끼(t_hit .216) → 낡은 대검(.132)으로 바꾸면 빠른 무기가 느린 무기의
#   부풀린 지연을 계속 물고 간다(에러 0 · 데미지 손실 0 · 양쪽 화면 동일 · 풀리는 조건이 **헛치기
#   한 번**이라 보스전에서 오래 간다). 상한을 두면 `x[n+1] ≤ t_hit + 이 값`으로 **위에서 막혀**
#   발산도 무한 래칫도 원리적으로 불가능하다.
# 🔴 **유도 = `data/equipment` 근접 무기 전수의 `max(t_hit) − min(t_hit)`.** 스로틀이 메워야 하는
#   결손이 정확히 그만큼이고 그 이상은 필요 없다. 실측 0.084s(도끼 0.216 − 낡은 대검 0.132, haste 0이
#   최악 — haste는 양쪽에 같은 배율이라 차이도 함께 줄어든다). 여유를 두고 0.09.
#   ⚠ `test_combat_math_auto`가 전수로 지킨다: 이 값 ≥ 실제 차이 · `t_hit + 이 값 ≤ swing_time`(창 안
#     판정) · 이 값 < `MELEE_TRAIL_FADE_S`(궤적이 사라진 뒤 판정 금지).
# ⚠ **상한 안에서는 여전히 지속된다**(감쇠 0이므로) — 84ms에서 멈출 뿐이고 헛치기 한 번에 해제된다.
#   감쇠를 되살리려면 `gate < cd`가 필요한데 그건 `+프레임` 여유를 포기하는 것이라 I-3 회귀다.
#   천장(`cd × (1 − FIRE_RATE_SLACK)`, 상한 haste에서 26.7ms < 프레임 33.3ms)이 그 트레이드오프를
#   **구조적으로** 강제한다 — 여기서 고를 수 있는 것이 아니다.
# 🔴 **haste로 함께 줄어들어야 한다 — 덮는 대상이 그렇기 때문이다** (2026-07-28 자체 점검 정정).
#   절대값으로 두면 `t_hit·k + CAP > swing_time·k`가 되어(haste ≥ 0.25에서 `worn`) 판정이
#   **스윙 창 밖**으로 샌다 = 무기가 평상 자세로 돌아간 뒤 데미지 숫자만 뜬다. 곱해 두면 그
#   부등식이 `t_hit + CAP ≤ swing_time`으로 **haste 불변**이 된다(worn 여유 18ms, 전 구간 동일).
#   ⚠ **바로 위 "haste는 양쪽에 같은 배율이라 차이도 함께 줄어든다"가 그 근거인데, 초판은 그것을
#     적어 두고도 상한만 절대값으로 뒀다** — 주석이 사실을 알고 있는데 코드가 안 따른 형태다.
#     그래서 `melee_throttle_max_s()`가 유일한 소비 경로이고, 트립와이어가 haste 전수로 곱을 단정한다.
const MELEE_THROTTLE_MAX_S := 0.09


static func melee_throttle_max_s(haste: float = 0.0) -> float:
	return MELEE_THROTTLE_MAX_S * haste_scale(haste)

# 스윕 완료 뒤 근접 궤적이 흩어지기까지(s). 🔴 **`player.gd`가 아니라 여기 있는 이유**: 위 상한과의
#   부등식(`MELEE_THROTTLE_MAX_S < MELEE_TRAIL_FADE_S`)을 트립와이어가 걸려면 양변이 같은 곳에 있어야
#   한다(J-1·J-2와 같은 규율 — `player.gd`는 씬 글루라 `-s`가 preload를 못 한다). 깨지면 **궤적이
#   사라진 뒤 판정이 나** 「표시 ⊇ 판정」이 시간 축에서 무너진다 — 이 작업 전체가 세운 불변식이
#   마지막 구간에서만 조용히 깨지는 형태다.
# ⚠ 연출값이라 사용자가 조인다(rules §0 예외). 조일 때 위 부등식을 트립와이어가 지킨다.
const MELEE_TRAIL_FADE_S := 0.18


# 호스트의 발사 원점 검증 — 원점이 발사자 net_anchor 근처인가 (순간이동 원점 스푸핑 완화, §3 신뢰 경계).
static func is_shot_origin_ok(shooter_anchor: Vector2, origin: Vector2) -> bool:
	return shooter_anchor.distance_to(origin) <= SHOT_ORIGIN_TOL


# 잔몹 타격 판정 — 단일 소스 (§3). 호스트 판정과 텔레그래프 표시가 같은 반경(def.strike_radius)을 읽는다.
static func is_strike_hit(player_pos: Vector2, strike_center: Vector2, strike_radius: float) -> bool:
	return player_pos.distance_to(strike_center) <= strike_radius


# 부채꼴 판정 — 단일 소스 (§3, 보스전 2026-07-23). 보스 평타/전방 분사 등 전방 원뿔형 공격.
# apex = 부채꼴 꼭짓점(보스 중심), facing = 향한 각(rad), half_angle = 반각(rad), radius = 사거리.
# 판정 각/반경 = 텔레그래프 표시(부채꼴 텍스처 스케일·회전)와 같은 값 — "맞는 곳=보이는 곳".
static func is_hit_in_cone(pt: Vector2, apex: Vector2, facing: float, half_angle: float, radius: float) -> bool:
	var to_pt := pt - apex
	var dist := to_pt.length()
	if dist > radius:
		return false
	if dist < 0.01:
		return true  # 꼭짓점 위 = 안쪽 (각 계산 무의미)
	return absf(angle_difference(facing, to_pt.angle())) <= half_angle


# --- 횡단 돌진 (2026-08-02 · docs/plans/active/2026-08-02-boss-dash-pattern.md) — 단일 소스 (§3) ---
#
# 🔴 **왜 여기인가**: `src/enemies/boss.gd`는 씬 글루라 `-s`가 preload를 못 한다(rules §5).
#   데이터가 만족해야 하는 상수·유도를 거기 두면 `data/enemies` **전수 트립와이어를 만들 수 없고**,
#   그러면 "속도를 낮췄더니 조용히 미완주" · "예고가 구르기보다 짧아졌다"의 자동 방어가 0이 된다.
#   `player.gd`에서 같은 값을 치른 자리가 리뷰 J-1·J-2다 — 함수째 여기로 올리고 boss.gd는 부르기만 한다.

# 돌진 타임아웃 여유(초) — 돌진 지속의 하한 = 이동시간 + 이 값(벽·바위에 낀 채 무한 돌진 방지).
# ⚠ 옛날엔 `boss.gd`에 **선언만 되고 아무도 안 쓰는 죽은 상수**였다. 그 자리에는 고정 1.0초가
#   박혀 있었고, 그래서 "이동 거리와 시간이 서로를 몰라" 속도를 낮추는 순간 **조용히 미완주**였다.
const CHARGE_TIMEOUT_MARGIN := 0.4

# 회차 단축의 하한 배율. 🔴 **근거 = `ROLL_TIME_S`(0.25s)** — 예고가 구르기보다 짧아지면
#   「예고를 읽고 구른다」(GDD §5 기믹 원칙)가 **원리적으로** 불가능해진다. 그래서 하한은 손맛
#   튜닝값이 아니라 **구르기에서 유도된 값**이고, 전수 트립와이어가 그 부등식을 지킨다.
const CHARGE_TELEGRAPH_MIN := 0.35

# `BossPatternDef.target_mode` allowlist — 코드가 실제로 구현한 모드의 전부다.
# 🔴 `_select_target`은 **모르는 값을 조용히 `nearest`로 떨어뜨린다**(데이터 오타가 패턴을 죽이지
#   않게 하려는 폴백이 계약이다). 그 관대함의 대가가 "적었는데 안 먹는다"이므로 데이터 축에서
#   전수로 막는다. ⚠ `"alternate"`(번갈아)는 4인 파티 게이트(rules §2)와 함께 열린다 — 지금
#   `.tres`에 적으면 nearest로 떨어져 **아무 일도 안 일어난다.**
const TARGET_MODES := ["nearest", "host"]

# 🔴 가리비(scallop) 예산(px) — 이산 판정(원)과 연속 표시(캡슐) 사이에 파이는 최대 깊이.
#   돌진은 프레임당 `speed/60`px씩 점프하므로 판정 원들의 합집합이 캡슐 **안쪽으로** 파인다:
#       D = r − √(r² − (d/2)²)   (r = 스윕 반경 · d = 프레임당 전진)
#   🔵 방향은 언제나 안전하다(가리비는 안쪽으로만 판다 = 판정 ⊆ 표시 유지). 그래서 이 상수는
#     §3 위반을 막는 것이 아니라 **손맛 예산**이다 — "띠 안인데 안 맞았다"가 눈에 띄는 폭.
#   근거 = 캐릭터 32px의 6%. `ARROW_SPEED` 터널링 불변식의 1:1 미러이되, 이쪽은 **반경이 패턴
#   데이터**라 상수가 아니라 함수(`max_charge_speed`)로 유도한다.
const SWEEP_SCALLOP_MAX_PX := 2.0
# 스윕 표본 주기 = 물리 틱. ⚠ `Engine.physics_ticks_per_second`(project.godot 60)와 미러 —
#   물리 틱을 바꾸면 여기도 고친다(안 고치면 상한만 조용히 틀려진다).
const SWEEP_STEP_FPS := 60.0

# 🔴 돌진 1회가 떨어뜨리는 낙석 수 상한. **근거는 면적이 아니라 「바위는 위협이 아니라 지형」이라는
#   성질이다** — 낙석은 데미지 판정이 없고(`_fire_strike` 주석: 지형일 뿐이다) `rock_ttl` 동안 남는
#   **정적 몸**이다. 즉 개수를 늘려도 위험이 커지는 것이 아니라 **아레나가 좁아진다**: 회차마다
#   쌓이므로 실제 최대치는 이 값 × `charge_repeat`이고, 보스방은 768×416px밖에 안 된다.
#   ⚠ 상한을 넘기면 「예고를 읽고 구른다」(GDD §5)가 **구를 자리가 없어서** 불가능해진다 —
#   예고는 정상적으로 뜨고 판정도 정확하므로 **화면에 이유가 안 드러난다.**
const MAX_DASH_ROCKS_PER_RUN := 3


# 회차별 예고 배율 — 호스트(`_telegraph_hold_s` 확정)와 게스트(`_telegraph_duration`)가 **같은
# 함수**를 지나야 「다 찼다 = 지금 맞는다」가 양쪽 화면에서 동시에 성립한다.
# 🔴 `charge_speedup == 0`이면 항상 1.0 = **모든 기존 패턴과 완전 항등**이다(이 축의 안전 근거 전부).
# ⚠ 큰 idx(버그·조작)는 하한으로 포화하고 음수는 `maxi`가 0으로 누른다 — 별도 clamp 불필요.
static func charge_telegraph_scale(pat: BossPatternDef, idx: int) -> float:
	if pat == null:
		return 1.0
	return maxf(1.0 - pat.charge_speedup * float(maxi(idx, 0)), CHARGE_TELEGRAPH_MIN)


# 돌진이 `charge_travel_max`를 지나는 데 걸리는 시간(초). 예고 재장전 분모(돌진 내내 켜 두는
# 차오름)와 아래 지속 유도가 **같은 값**을 써야 "선단이 도착 = 보스가 도착"이 유지된다.
static func charge_travel_s(pat: BossPatternDef) -> float:
	if pat == null:
		return 0.0
	return pat.charge_travel_max / maxf(pat.charge_speed, 1.0)


# 돌진 서브상태의 총 지속(초) = max(도달 후 회전 유지, 이동시간 + 타임아웃 여유).
# 🔴 **`maxf`를 빼지 마라** — 빼면 P3(`charge_spin_s` 1.0)가 1.0 → 0.92s로 **조용히 짧아진다**(회귀).
# 🔴 반대로 우변을 빼고 `charge_spin_s` 하나로 두면(= 도입 전 고정 상수) 속도를 낮추는 순간
#   **에러 없이 미완주**가 된다 — 예고 띠는 끝까지 그려져 있는데 보스가 중간에 선다.
#   `test_combat_math_auto`의 「★돌진 완주 불변식」이 양쪽 방향을 다 잡는다.
static func charge_dash_duration_s(pat: BossPatternDef) -> float:
	if pat == null:
		return 0.0
	return maxf(pat.charge_spin_s, charge_travel_s(pat) + CHARGE_TIMEOUT_MARGIN)


# 이 스윕 반경에서 허용되는 최대 돌진 속도(px/s) — 가리비 예산에서 역산.
#   D = r − √(r² − (d/2)²) ≤ SWEEP_SCALLOP_MAX_PX  ⇒  d ≤ 2√(r² − (r − D)²)  ⇒  speed = d·fps
# 🔴 **속도를 올릴 때 이것이 유일한 자동 방어다**(전수 트립와이어).
# ⚠ 반경이 예산보다 작으면 (r − D)²가 r²를 넘어 0으로 포화한다 = 어떤 속도도 거부 = 안전한 방향.
static func max_charge_speed(sweep_radius: float) -> float:
	var r := maxf(sweep_radius, 0.01)
	var inner := r - SWEEP_SCALLOP_MAX_PX
	return 2.0 * SWEEP_STEP_FPS * sqrt(maxf(r * r - inner * inner, 0.0))


# 돌진 1회가 **실제로** 지속되는 물리 프레임 수.
# 🔴🔴 **`charge_dash_duration_s`와 헷갈리지 마라 — 그쪽은 타임아웃 상한이지 지속이 아니다.**
#   돌진은 타이머가 아니라 **이동 거리**로 끝나고(`boss.gd`의 `State.CHARGE_DASH`), 프레임당 전진이
#   `charge_speed ÷ SWEEP_STEP_FPS`로 양자화돼 있어 실제 종료는 그 나눗셈의 **올림 프레임**이다.
#   ⚠ 리드가 2026-08-03에 정확히 이것을 혼동해 낙석 간격을 **2배로 잘못** 잡았다(모델 2개 · 실제
#   1개). 타임아웃(`charge_dash_duration_s`)까지 사는 것은 **몸이 막혔을 때뿐**인데 `breaks_rock`
#   패턴은 바위를 부수고 아레나 벽은 `_cross_segment`가 `body_radius` 안쪽으로 잡아 안 닿는다 —
#   즉 정상 경로에서 그 상한은 **도달 불가**이고, 그것을 지속으로 쓰면 튜닝 손잡이가 죽는다.
static func charge_dash_frames(pat: BossPatternDef) -> int:
	if pat == null:
		return 0
	var step := maxf(pat.charge_speed, 1.0) / SWEEP_STEP_FPS
	return int(ceil(maxf(pat.charge_travel_max, 0.0) / step))


# 돌진 1회가 실제로 떨어뜨리는 낙석 수 — `boss._tick_dash_rockfall`의 카운트다운을 **프레임 산수로
# 독립 유도**한다(첫 개는 한 간격 뒤에 떨어진다).
# 🔴 코드(float 감산)와 테스트(정수 프레임)가 **다른 모델로 같은 답에 도달**하는 것이 요점이다 —
#   같은 식을 공유하면 검출력이 0이 된다(§3 「코드와 테스트가 같은 모델을 공유하면」 판례).
# 🔴 `boss.gd`가 아니라 여기 있는 이유 = 그 파일은 씬 글루라 `-s`가 preload를 못 해 `data/enemies`
#   전수 트립와이어를 만들 수 없다(리뷰 J-1·J-2와 같은 규율).
static func dash_rock_count(pat: BossPatternDef) -> int:
	if pat == null or pat.dash_rock_interval <= 0.0:
		return 0
	var step_frames := int(ceil(pat.dash_rock_interval * SWEEP_STEP_FPS))
	if step_frames <= 0:
		return 0
	return int(charge_dash_frames(pat) / step_frames)


# 목표점으로 다가가는 이번 프레임 속도 — **마지막 한 걸음을 잔여 거리로 clamp한다.**
# 🔴🔴 **clamp가 없으면 「도착 판정 창」이 프레임 스텝보다 좁을 때 목표를 영원히 못 맞힌다.**
#   등속 접근은 잔여 거리를 `speed·delta`씩 깎으므로 창(ε)에 들어가려면 `d₀ mod (speed·delta)`가
#   `[0, ε]` 또는 `[speed·delta − ε, speed·delta]`에 있어야 하고, 그 밖이면 목표를 **지나쳐 되돌아오며
#   두 값 사이를 진동**한다. 실측(2026-08-03): 횡단 접근 800px/s → 프레임당 13.33px vs 창 3px에서
#   **55%가 도달 실패** → 타임아웃 → 패턴이 발동만 하고 사라진다(화면엔 아무 일도 안 일어난다).
# 🔴 **창(ε)을 키워서 고치지 마라 — 그게 이 결함을 만든 방식이다.** ε을 `speed·delta`의 미러로 두면
#   ⑴ 최대 한 프레임분(13px)의 **순간이동**이 생기고 ⑵ 속도를 바꿀 때마다 창이 따라와야 하는데
#   사람이 그 미러를 지킨다(실제로 600 → 800으로 올렸을 때 안 따라와 실패율이 40% → 55%가 됐다).
#   clamp는 잔여 거리를 **단조 감소**시켜 도달을 산수로 보장하므로 미러 자체가 생기지 않는다.
# ⚠ 대가는 도달이 최대 1프레임 늦는 것뿐이다.
static func approach_velocity(to_target: Vector2, speed: float, delta: float) -> Vector2:
	var d := to_target.length()
	if d <= 0.0 or delta <= 0.0:
		return Vector2.ZERO
	return (to_target / d) * minf(maxf(speed, 1.0), d / delta)


# 🔴 이 패턴의 예고는 **띠(캡슐)** 여야 하는가 = 위협이 「이동하는 원」인가.
#
# 🔴🔴 **부채꼴로는 이동 원을 원리적으로 덮을 수 없다.** apex에서 콘의 반폭이 0이므로, 경로 위
#   거리 t의 지점에서 콘이 반경 r 원을 품으려면 `t·sin(half_angle) ≥ r`이어야 하는데 동시에
#   끝단이 `t + r ≤ range`도 만족해야 한다. P3 실측(r=72 · half_angle=0.3 · range=260)에서
#   앞 조건은 t ≥ 243.6, 뒤 조건은 t ≤ 188 — **해가 없다.** 즉 경로 전 구간이 과소예고이고,
#   최악은 apex 주변(보스 옆·뒤 72px)이 통째로 무예고다 = §3이 금지한 **「표시 < 판정」**.
#   `boss_pattern_def.gd`가 캡슐을 만들며 이미 못 박은 결론인데 **P3만 마이그레이션이 안 됐다.**
#
# 🔴 **`shape` 문자열로 이 축을 판정하지 마라.** 그 필드는 애니 선택(`_play_dash_sheet` vs
#   `play_spin_clip`) · 돌진선 핀(`_pin_to_dash_line`) · 표시 기하 **세 축의 공용 키**라,
#   `.tres`에서 `cone` → `capsule`로 바꾸면 여섯 분기가 동시에 켜진다: 좌우 횡단 전용 시트가
#   임의 각 돌진에 물리고, 회전 클립과 겹쳐 재생되고, P3가 명시적으로 배제한 돌진선 핀이 켜져
#   「바위에 박으면 옆으로 미끄러진다」는 연출 계약이 사라진다. 표시 축만 떼어 여기 둔다.
#
# 🔴 이 함수가 `boss.gd`가 아니라 여기 있는 이유 = 그 파일은 씬 글루라 `-s`가 preload를 못 해
#   `data/enemies` 전수 트립와이어를 만들 수 없다(리뷰 J-1·J-2). 위 부등식은 **데이터가 만족해야
#   하는 것**이므로 반드시 여기서 유도한다.
static func is_band_telegraph(pat: BossPatternDef) -> bool:
	return pat != null and pat.is_charge and pat.charge_sweep_radius > 0.0


# 🔴 **`boss_sweep`이 실제로 나가는 시간**(초) = 띠 예고를 켜 두어야 하는 시간과 **같은 값**이어야 한다.
#   그 둘이 갈라지면 차이만큼 **무예고 스윕**이 된다(§3이 금지한 「표시 < 판정」의 시간축 형태).
#
# 🔴 종료 조건이 둘이라 갈래가 둘이다(`boss.gd`의 `State.CHARGE_DASH`):
#   ⑴ `charge_spin_s > 0` → 도달 후에도 제자리 회전을 유지하므로 **타이머**(`charge_dash_duration_s`)가 끝낸다.
#   ⑵ `charge_spin_s <= 0` → **이동 거리 도달**이 끝낸다 = 프레임 양자화된 `charge_dash_frames`.
#
# ⚠ 옛 유도 `maxf(charge_travel_s, charge_spin_s)`는 ⑵에서 **한 프레임 짧았다**(횡단 실측 0.428 vs
#   실제 0.433) — 이동 시간을 연속값으로 쟀기 때문이다. 그 5ms가 곧 마지막 프레임의 무예고 스윕이다.
# ⚠ ⑴에 `charge_dash_duration_s`를 쓰는 것이 옳다 — 거기 섞인 `CHARGE_TIMEOUT_MARGIN`은 「여유」가
#   아니라 그 갈래에서 **상태가 실제로 사는 시간**이고, 그동안 스윕이 계속 나간다.
static func charge_sweep_duration_s(pat: BossPatternDef) -> float:
	if pat == null:
		return 0.0
	if pat.charge_spin_s > 0.0:
		return charge_dash_duration_s(pat)
	return float(charge_dash_frames(pat)) / SWEEP_STEP_FPS


# 실제 가리비 깊이(px) — 트립와이어가 **값을 찍는** 용도(실패 조건이 아니다). 속도를 바꾼 사람이
# 숫자를 보게 만드는 것이 목적이다(§9-2 4c).
static func sweep_scallop_px(sweep_radius: float, speed: float) -> float:
	var r := maxf(sweep_radius, 0.01)
	var half_step := maxf(speed, 0.0) / SWEEP_STEP_FPS * 0.5
	return r - sqrt(maxf(r * r - half_step * half_step, 0.0))


# 캡슐(선분 + 반경) 안쪽 깊이 — 양수면 안, 0이 경계. **표시 형태의 단일 소스**다.
# 🔴 판정은 여전히 **이동하는 원**(`charge_sweep_radius`)이고 캡슐은 그 원이 경로를 따라 쓸고 간
#   **합집합**이다. 부채꼴로는 원리적으로 못 맞춘다 — apex가 보스에 붙어 있어 끝으로 갈수록
#   넓어지는데 스윕은 폭이 일정하다(642px에서 2.76배 과예고 = 아레나 세로의 95%가 붉어진다).
# 🔴 `a == b`이면 `is_strike_hit`과 **완전 항등**이다 — 그게 셰이더 `half_len_px = 0` 항등의
#   GDScript 쪽 짝이고, 「기존 원·콘 예고는 한 픽셀도 안 바뀐다」의 근거다.
# ⚠ 소비자는 `assets/shaders/boss_telegraph.gdshader`(같은 식을 GLSL로)와 트립와이어다. 한쪽을
#   고치면 같이 고쳐라 — 테스트는 엔진 함수(`Geometry2D.get_closest_point_to_segment`)를 독립
#   오라클로 써서 **둘 다 틀린 채 초록**이 되는 것을 막는다.
static func capsule_depth(pt: Vector2, a: Vector2, b: Vector2, radius: float) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.000001 else clampf((pt - a).dot(ab) / l2, 0.0, 1.0)
	return radius - pt.distance_to(a + ab * t)


# 조준 = 호스트 고정인가. 🔴 **모르는 문자열은 여기서 false로 떨어져 `nearest` 폴백이 된다** —
#   폴백이 계약이다(호스트가 죽어 관전 중이면 대상이 없고, 데이터 오타가 패턴을 죽이면 안 된다).
static func is_host_targeted(mode: String) -> bool:
	return mode == "host"


# --- 지연 보상 (2026-07-24) — 단일 소스 (§3). "피했는데 맞았다"를 없애는 계약. ---
#
# 문제: 호스트 권한 모델에서 게스트만 구조적으로 손해본다 (실측 2026-07-24, RTT 83~207ms).
#   ⑴ 호스트가 예고를 띄운 순간 → 게스트 화면에 뜨기까지 **편도 지연**만큼 늦다.
#   ⑵ 호스트가 타격을 판정할 때 아는 게스트 좌표는 **편도 지연 + 송신 주기**만큼 과거다.
#   합쳐서 게스트의 실효 회피 창 = telegraph_s − (왕복 + 송신주기). RTT 207ms일 때 0.6s → 0.36s(40% 손실).
#   호스트는 둘 다 0이라 손실이 없다 — 그래서 "호스트는 괜찮은데 게스트만 맞는" 비대칭이 생긴다.
#
# 해법 두 축 (둘 다 호스트에서만 계산 — 게스트 코드에 상태 확정은 없다, §1):
#   ⓐ **STRIKE 지연**(`strike_delay_s`): 예고 타격 시각을 원격 피어 편도 지연만큼 늦춘다 → ⑴ 상쇄.
#      게스트는 자기 화면 기준 온전한 telegraph_s를 갖고, 호스트는 예고가 그만큼 길어져 공평해진다.
#   ⓑ **위치 외삽 + 방어자 우대**(`lag_lead_s`·`extrapolate`·`is_strike_hit_lagged`): 판정 시 게스트의
#      "지금" 위치를 마지막 관측 속도로 추정하고, **낡은 좌표와 추정 좌표가 둘 다 맞아야** 확정 → ⑵ 상쇄.
#
# 🔴 왜 "둘 다"인가 (핵심 설계): 외삽은 방향 전환 순간에 틀린다 — 한쪽만 믿으면 새 오탐이 생긴다.
#   둘 다 요구하면 오차가 **항상 방어자에게 유리한 쪽**으로만 떨어진다:
#     빠져나가는 중 → 추정 좌표가 밖 → 안 맞음 (게스트 화면과 일치 = 고치려던 그 버그)
#     들어오는 중   → 낡은 좌표가 밖 → 안 맞음 (관대 — 협동 게임이라 무해)
#     계속 안       → 둘 다 안 → 맞음 (정상)
#   PvP가 생기면 이 관대함이 표면이 된다 → rules §2 4인/PvP 게이트에서 재검토.
const LAG_MAX_ONE_WAY_MS := 200.0   # 편도 지연 인정 상한 — 조작 피어가 큰 RTT를 주장해 보스 예고를
                                    # 무한 지연시키거나 외삽을 뻥튀기하는 것 차단 (신뢰 경계 §3)
const LAG_MAX_LEAD_DIST := 115.0    # 외삽 거리 상한(px) — 지연 스파이크 한 번이 판정을 화면 밖으로 날리지 않게.
# 🔴 유도식(조립축 2026-07-26 재산정): 최고 이속 × 최대 구르기 배율 × 최대 lead
#   = (110 × (1+LEVEL_STAT_MAX["move"]=0.3)) × (2.6 × (1+TRAIT_MAX["roll_dist"]=0.3))
#     × (LAG_MAX_ONE_WAY_MS 0.2s + 송신주기 1/30s) ≈ 113px → 115.
#   ⚠ **roll_dist 특성이 구르기 배율을 키우므로 여기가 같이 커진다** — 안 키우면 정당하게 길어진
#   구르기가 외삽에서 과소평가돼 "피했는데 맞았다"가 부분 재발한다(아래 ⚠와 같은 실패 모드).
#   ⚠ 상한을 무한정 키울 수도 없다 — 두 목적이 충돌한다(스파이크 억제는 작기를, 정당 외삽 커버는 크기를 요구).
#   그래서 이속 하드 상한을 0.3으로 조여 균형을 잡았다.
#   ⚠ 이 값이 실제 최대 외삽보다 **작으면** 추정 좌표가 예고 안에 남아 "둘 다 맞아야 확정" 규약이
#   맞는 쪽으로 기운다 → 빠르게 빠져나가는 피어가 다시 맞는다(2026-07-24에 고친 버그의 부분 퇴행).
#   이속 상한(LEVEL_STAT_MAX["move"])·구르기 거리 상한(TRAIT_MAX["roll_dist"])·직업 move_speed 중
#   무엇을 올리든 여기도 재유도해라 —
#   test_combat_math_auto의 데이터 전수 불변식이 그때 빨개진다.

# 편도 지연 = RTT의 절반. 음수·NaN·스파이크를 상한으로 눌러 판정에 쓸 수 있는 값으로 정규화한다.
static func clamp_one_way_ms(one_way_ms: float) -> float:
	if not is_finite(one_way_ms):
		return 0.0
	return clampf(one_way_ms, 0.0, LAG_MAX_ONE_WAY_MS)


# 예고 타격을 늦출 시간(초) — 원격 피어 중 **최대** 편도 지연. 가장 느린 피어도 온전한 예고 창을 갖는다.
# 솔로/호스트뿐이면 0 = 기존 동작과 완전히 동일(항등 폴백).
static func strike_delay_s(max_one_way_ms: float) -> float:
	return clamp_one_way_ms(max_one_way_ms) / 1000.0


# 외삽 시간(초) — 마지막 위치 패킷이 담은 시점부터 "지금"까지.
#   (패킷 수신 후 흐른 시간) + (그 패킷이 날아오는 데 걸린 편도 지연)
# 로컬 피어(지연 0·수신 기록 없음)는 0을 넘겨 항등이 되게 한다.
static func lag_lead_s(last_recv_msec: int, now_msec: int, one_way_ms: float) -> float:
	if last_recv_msec < 0:
		return 0.0
	var since_ms := float(maxi(now_msec - last_recv_msec, 0))
	return (since_ms + clamp_one_way_ms(one_way_ms)) / 1000.0


# 위치 패킷 신선도 — 순서가 뒤바뀐 G_POS를 폐기해 판정 앵커가 과거로 되돌아가는 것을 막는다.
# 🔴 **왜 필요한가 (P2P 직결 도입, 2026-07-26):** fast 데이터 채널은 unordered(유실 허용)라 위치 패킷이
#   뒤바뀌어 도착할 수 있다. 릴레이(TCP)에선 구조적으로 불가능했던 상황이다. 뒤늦게 도착한 옛 패킷을
#   적용하면 `_remote_target`과 `_remote_vel`이 **함께** 한 틱 과거로 돌아가는데, 그러면
#   `net_anchor()`(낡은 좌표)와 `net_anchor_lead()`(추정 좌표)가 **같은 방향으로** 틀려
#   "둘 다 맞아야 확정"인 방어자 우대 규약(is_strike_hit_lagged)이 무력화된다 — 규약은 두 좌표가
#   **서로 다른 방향**으로 틀릴 때만 방어자를 보호하기 때문이다. 결과는 "빠져나왔는데 맞았다"의 부분 재발.
# ⚠ 변위 clamp(player.apply_remote_pos)는 이걸 못 막는다 — 되돌아가는 거리가 한 송신 간격분(~4px)이라
#   상한(~13px) 안에 들어와 그냥 통과한다. 그래서 순서를 **명시적으로** 봐야 한다.
# seq <= 0 = 시퀀스 미부착(릴레이 경로·구버전) → 항등 폴백으로 전부 통과시킨다.
static func is_pos_seq_fresh(seq: int, last_seq: int) -> bool:
	if seq <= 0:
		return true
	return seq > last_seq


# 마지막 관측 속도로 추정한 "지금" 위치. 거리 상한(LAG_MAX_LEAD_DIST)으로 폭주를 막는다.
static func extrapolate(pos: Vector2, vel: Vector2, lead_s: float) -> Vector2:
	if not (is_finite(vel.x) and is_finite(vel.y)) or lead_s <= 0.0:
		return pos
	var offset := vel * lead_s
	if offset.length() > LAG_MAX_LEAD_DIST:
		offset = offset.normalized() * LAG_MAX_LEAD_DIST
	return pos + offset


# 지연 보상 원형 타격 판정 — 낡은 좌표와 추정 좌표가 **둘 다** 안일 때만 맞은 것 (방어자 우대, 위 설명).
# lead_pos == anchor(로컬 피어·속도 0)면 is_strike_hit과 완전히 같다 — 항등 폴백.
static func is_strike_hit_lagged(anchor: Vector2, lead_pos: Vector2,
		strike_center: Vector2, strike_radius: float) -> bool:
	return is_strike_hit(anchor, strike_center, strike_radius) \
		and is_strike_hit(lead_pos, strike_center, strike_radius)


# 지연 보상 부채꼴 판정 — 원형과 같은 규약(둘 다 안일 때만). 보스 평타 등 cone 패턴용.
static func is_hit_in_cone_lagged(anchor: Vector2, lead_pos: Vector2, apex: Vector2,
		facing: float, half_angle: float, radius: float) -> bool:
	return is_hit_in_cone(anchor, apex, facing, half_angle, radius) \
		and is_hit_in_cone(lead_pos, apex, facing, half_angle, radius)


# 인원 스케일링 — 솔로 시 보스 약화 (§3 예약 → 구현, GDD §11·§5 확정). party_size>=2 → base(항등),
# 1(솔로) → base*solo_factor. max_hp·물 착탄 수·늪 자동 생성 빈도에 곱한다. 호스트가 계산(게스트도
# 같은 피어 수로 동일 계산 → 표시 일치). solo_factor·적용 대상 수치는 사용자 실기 튜닝.
static func party_scale(base: float, party_size: int, solo_factor: float = 0.6) -> float:
	if party_size >= 2:
		return base
	return base * solo_factor


# --- 장비 스탯 (드랍·제작 2026-07-23) — 단일 소스 (§3). 제작/강화 UI·전투·HUD가 전부 이 함수만 부른다. ---

# 한 장비의 레벨별 스탯 = base + step*level. total_stats·강화 미리보기가 같이 부른다(갈라짐 방지).
static func equip_stat_at_level(equip: EquipDef, level: int) -> Dictionary:
	return {
		"attack": equip.base_attack + equip.atk_per_level * level,
		"hp": equip.base_hp + equip.hp_per_level * level,
	}


# 착용 장비 총 스탯. equip_levels = [[EquipDef, level], …]. 미착용이면 {attack=0, hp=0} (항등 폴백).
static func total_stats(equip_levels: Array) -> Dictionary:
	var atk := 0
	var hp := 0
	for pair: Array in equip_levels:
		var s := equip_stat_at_level(pair[0] as EquipDef, int(pair[1]))
		atk += int(s["attack"])
		hp += int(s["hp"])
	return {"attack": atk, "hp": hp}


# 강화 미리보기 델타(from→to 레벨). 강화 UI "다음 단계"와 실제 적용이 같은 함수를 부른다.
static func upgraded_stats(equip: EquipDef, from_level: int, to_level: int) -> Dictionary:
	var a := equip_stat_at_level(equip, from_level)
	var b := equip_stat_at_level(equip, to_level)
	return {"attack": int(b["attack"]) - int(a["attack"]), "hp": int(b["hp"]) - int(a["hp"])}


# 강화 비용(골드). UI 미리보기 = 실제 차감 단일 소스. 곡선 = base * (다음 레벨).
static func upgrade_cost(equip: EquipDef, current_level: int) -> int:
	return equip.upgrade_gold_base * (current_level + 1)


# --- 직업 레벨 · 캐릭터 스탯 5종 (성장축 2026-07-25, GDD v1.8) — 단일 소스 (§3) ---
#
# 🔒 축 경계(GDD §6 확정): 이 절은 **레벨 스탯만** 다룬다. 공격력·체력은 위 장비 절(total_stats)의 몫이다.
#   두 파이프를 하나로 합치지 마라 — 합치면 data/equipment/*.tres에 "crit"을 적어도 코드가 조용히 받아들인다
#   (기획 위반이 컴파일도 리뷰도 안 걸리고 통과한다). 분리하면 EquipDef엔 crit 필드가 아예 없다.
#
# 와이어 키 = 아래 문자열 **그대로** 쓴다: G_STATS "lv" 페이로드 키 · SubJobDef.step() 키 · clamp 키.
#   별도 매핑 표를 만들면 그게 두 번째 진실원이 되어 갈라진다.
const LEVEL_STAT_KEYS: Array[String] = ["crit", "crit_dmg", "haste", "move", "leech"]

# 키별 **하드 상한** — 데이터가 잘못 커지거나 조작 공지가 와도 여기서 잘린다.
# 데이터 유도 상한(GameState.max_level_stats)과 이중 방어: 정직한 최대치는 데이터 상한이,
# 데이터 자체의 실수는 이 상수가 잡는다(max_equip_stats + 상한 상수 철학의 미러).
const LEVEL_STAT_MAX: Dictionary = {
	"crit": 1.0,      # 확률 — 100% 초과는 무의미
	"crit_dmg": 3.0,  # 치명 배율 추가분(총 배율 = CRIT_BASE_MULT + 이 값)
	"haste": 0.5,     # 공속 +50% → 쿨다운 ×1/1.5. ⚠ 퇴화 한계: effective_cooldown*0.9 > SAME_SWING_MS를 지켜야 한다
	"move": 0.3,      # 이속 +30% — GDD 예산(+15%)의 2배 여유. 🔴 이 값을 올리면 LAG_MAX_LEAD_DIST(외삽 상한)를
	                  #   같이 재유도해야 한다 — 안 하면 지연 보상이 퇴행한다(테스트 불변식이 그때 빨개진다)
	"leech": 0.5,     # 피흡 50%
}

const SUB_JOB_WEIGHT := 0.4  # 서브(비-메인) 하위 직업 기여 배율 — GDD §5 "서브도 효과가 있다" · 값은 §11 실기 TBD
const CRIT_BASE_MULT := 1.5  # 치명타 기본 배율 (GDD §6 = 150%). 치명 총 배율 = 이 값 + lv_stats.crit_dmg


# 레벨 스탯 한 칸 clamp — 유한성 가드 먼저(JSON 1e999 → INF, clamp_arrow_range와 같은 철학).
# cap = 데이터 유도 상한(없으면 하드 상한만). 음수는 0으로 — 디버프 주입 차단.
static func clamp_level_stat(key: String, value: float, cap: float = INF) -> float:
	if not is_finite(value):
		return 0.0
	var hard := float(LEVEL_STAT_MAX.get(key, 0.0))
	var top := hard if not is_finite(cap) else minf(hard, maxf(cap, 0.0))
	return clampf(value, 0.0, top)


# 레벨 스탯 묶음 clamp — 🔴 **payload가 아니라 LEVEL_STAT_KEYS를 순회한다**(allowlist 관용구):
# 모르는 키는 자동 폐기되고, 빠진 키는 0.0으로 채워져 하류가 항등 폴백을 얻는다.
static func clamp_level_stats(stats: Dictionary, caps: Dictionary = {}) -> Dictionary:
	var out := {}
	for key: String in LEVEL_STAT_KEYS:
		out[key] = clamp_level_stat(key, float(stats.get(key, 0.0)), float(caps.get(key, INF)))
	return out


# 빈 레벨 스탯(전부 0) — 성장축 미도입/미착용 경로의 항등 폴백.
static func empty_level_stats() -> Dictionary:
	var out := {}
	for key: String in LEVEL_STAT_KEYS:
		out[key] = 0.0
	return out


# 하위 직업 하나의 레벨별 스탯 = step * level (base 없음 — GDD §6).
static func sub_job_stat_at_level(def: SubJobDef, level: int) -> Dictionary:
	var out := {}
	var lv := clampi(level, 0, def.max_level)
	for key: String in LEVEL_STAT_KEYS:
		out[key] = def.step(key) * float(lv)
	return out


# 총 레벨 스탯 = 메인 온전 + 서브들 × SUB_JOB_WEIGHT (GDD §5 "메인 1개 + 서브 합산").
#   levels = {sub_id: level} (보유분) · defs = {sub_id: SubJobDef}
# ⚠ CombatMath는 오토로드를 참조하지 않는다(-s 테스트 호환, 위 total_stats와 같은 규약) —
#   id→SubJobDef 리졸브는 부르는 쪽(GameState.current_level_stats)이 한다.
# 보유 0이면 전부 0 = 항등 폴백.
static func level_stats(main_id: String, levels: Dictionary, defs: Dictionary,
		sub_weight: float = SUB_JOB_WEIGHT) -> Dictionary:
	var out := empty_level_stats()
	for sid: String in levels:
		var def := defs.get(sid) as SubJobDef
		if def == null:
			continue  # allowlist 밖 / 리졸브 실패 — 조용히 건너뛴다(폐기가 안전한 방향)
		var w := 1.0 if sid == main_id else maxf(sub_weight, 0.0)
		var s := sub_job_stat_at_level(def, int(levels[sid]))
		for key: String in LEVEL_STAT_KEYS:
			out[key] = float(out[key]) + float(s[key]) * w
	return clamp_level_stats(out)


# 치명타 총 배율. crit_dmg = 레벨 스탯의 배율 **추가분**(0 = 기본 150%).
static func crit_mult(crit_dmg: float) -> float:
	return CRIT_BASE_MULT + clamp_level_stat("crit_dmg", crit_dmg)


# 🔴 최종 데미지 확정 — 단일 소스 (§3). 근접·투사체·폭발 **3경로 전부** 이 함수만 부른다.
# 곱 순서 고정: (직업 기본 + 장비 보너스) × 차지 배율 × 치명 배율 → **반올림 1회**.
#   경로마다 곱 순서나 반올림 횟수가 갈라지면 같은 상황에서 데미지가 달라진다
#   (charge_damage가 이미 round를 하므로, 치명을 그 밖에서 곱하면 이중 반올림이 된다).
# 🔴 굴림(crit_roll01)은 **호출부(호스트 RNG)** 가 만든다 — CombatMath가 RNG를 쥐면 테스트가 결정론을 잃는다.
#   굴림 단위 = 데미지 인스턴스 1회(폭발이 3마리를 때리면 3번 굴린다 — 사용자 확정 2026-07-25).
# lv_stats 비어 있고 charge 0·combo_mult 1이면 calc_damage와 **정확히 같은 값**(항등 폴백).
# 🔴 combo_mult = 평타 콤보 타별 데미지 배율(combo_damage_mult_at). **곱셈 안쪽**에 넣어 반올림이
#   여전히 1회이게 한다 — 호출부에서 결과에 곱하면 이중 반올림이 되고, 그게 정확히 이 함수가
#   존재하는 이유다. 🔴 배율은 **호스트가 센 타수**로 리졸브한다(authoritative_combo) — 발신자가
#   주장한 타수로 곱하면 매 발사가 마무리 타가 된다.
static func confirm_damage(job: JobDef, bonus_attack: int, lv_stats: Dictionary,
		charge_level: int, crit_roll01: float, combo_mult: float = 1.0) -> Dictionary:
	var base := float(calc_damage(job, bonus_attack))
	var mult := CHARGE_DAMAGE_MULT[clamp_charge_level(charge_level)]
	var chance := clamp_level_stat("crit", float(lv_stats.get("crit", 0.0)))
	var is_crit := is_finite(crit_roll01) and crit_roll01 >= 0.0 and crit_roll01 < chance
	var cmult := crit_mult(float(lv_stats.get("crit_dmg", 0.0))) if is_crit else 1.0
	return {"damage": int(round(base * mult * clamp_combo_mult(combo_mult) * cmult)), "crit": is_crit}


# 피흡 적립량(소수) — 🔴 **실제로 깎인 HP** 기준으로 부른다(오버킬 기준이면 1HP 잔몹을 치명타로 때려
# 회복을 부풀릴 수 있다). 정수 절삭은 호출부가 소수 잔량을 누적해 처리한다(데미지가 4~34 정수라
# 매 타격 절삭하면 6% 흡혈이 0이 되어 스탯이 아예 작동하지 않는다 — GDD §6 소수 누적 확정).
static func leech_gain(applied_damage: int, leech: float) -> float:
	if applied_damage <= 0:
		return 0.0
	return float(applied_damage) * clamp_level_stat("leech", leech)


# --- 공격속도 (haste) — 단일 소스 (§3) ---
#
# 🔴 **핵심 계약: 쿨다운과 스윙 창(EquipDef.swing_time)·차지 스텝에 같은 배율을 곱한다.**
#   그러면 rules §3의 스윙 창 부등식(swing_time < attack_cooldown)이 k = haste_scale(h) > 0 어디서나
#   `swing_time·k < cooldown·k`로 **자동 보존**된다 — 부등식을 haste마다 다시 검사할 필요가 없다.
#   배율 함수를 공유하는 것 자체가 계약의 증명이다. 각자 1/(1+h)를 다시 쓰면 그 증명이 깨진다.
static func clamp_haste(haste: float) -> float:
	return clamp_level_stat("haste", haste)


static func haste_scale(haste: float) -> float:
	return 1.0 / (1.0 + clamp_haste(haste))


static func effective_cooldown(job: JobDef, haste: float = 0.0) -> float:
	return job.attack_cooldown * haste_scale(haste)


static func effective_charge_step(step_time: float, haste: float = 0.0) -> float:
	if not is_finite(step_time) or step_time <= 0.0:
		return step_time  # 차지 무기가 아님 — 그대로 넘겨 호출부의 "0 = 차지 불가" 판정을 보존
	return step_time * haste_scale(haste)


# --- 이동속도 (move) — 단일 소스 (§3) ---
# ⚠ 로컬 이동만 고치면 안 된다: 원격 위치 clamp(player.gd)가 job.move_speed를 기준으로 상한을 잡으므로,
#   빨라진 정당 이동이 깎이면 지연 보상의 외삽이 과소평가되고 "피했는데 맞았다"가 빠른 피어에게 재발한다
#   (2026-07-24에 고친 그 버그). 두 상한 모두 이 함수로 유도한다.
static func clamp_move(move: float) -> float:
	return clamp_level_stat("move", move)


static func effective_move_speed(base_speed: float, move: float) -> float:
	return base_speed * (1.0 + clamp_move(move))


# --- EXP · 레벨 파생 (§3) ---
# 🔴 레벨은 **저장하지 않고 EXP에서 파생**한다 — 둘을 다 저장하면 어긋난 상태(손상·구버전 세이브)가
#   생기고, 레벨은 스탯 공지의 근거라서 어긋남이 곧 클라 간 스탯 발산이다.
# 곡선 = 레벨 n 도달에 필요한 **누적** EXP(인덱스 = 레벨, [0] = 0). 데이터 = JobDef.exp_curve.
static func default_exp_curve() -> PackedInt32Array:
	return PackedInt32Array([0, 60, 150, 280, 460, 700])


# 누적 EXP → 레벨. curve가 비었거나 깨졌으면 기본 곡선. max_level로 clamp(초과분은 폐기 = 만레벨 유지).
static func level_for_exp(exp: int, curve: PackedInt32Array, max_level: int) -> int:
	var c := curve if curve.size() >= 2 else default_exp_curve()
	var top := mini(max_level, c.size() - 1)
	var lv := 0
	for n: int in range(1, top + 1):
		if exp >= c[n]:
			lv = n
		else:
			break
	return lv


# UI 진행 바용 — {"level", "cur"(현 레벨 구간 진행량), "need"(구간 총량, 만레벨 = 0)}.
# 레벨업 판정과 바 표시가 같은 함수를 지난다(갈라짐 방지).
static func exp_progress(exp: int, curve: PackedInt32Array, max_level: int) -> Dictionary:
	var c := curve if curve.size() >= 2 else default_exp_curve()
	var lv := level_for_exp(exp, c, max_level)
	var top := mini(max_level, c.size() - 1)
	if lv >= top:
		return {"level": lv, "cur": 0, "need": 0}  # 만레벨 = 바 없음(잉여 EXP는 폐기, GDD §11)
	var floor_exp := c[lv]
	return {"level": lv, "cur": exp - floor_exp, "need": c[lv + 1] - floor_exp}


# ============================================================================
# 하위 직업 스킬 (2026-08-02 — GDD §3이 조작을 확정해 둔 자리 · §11 「직업별 스킬 구성」 TBD의 첫 입주)
# ============================================================================
# 🔴 **여기가 스킬의 단일 소스다 — 로컬 표시(FX 크기)와 호스트 판정이 같은 함수를 지난다**(§3).
#   한쪽이 자기 계산을 갖는 순간 "맞는 곳 ≠ 보이는 곳"이 되고, 그건 에러 없이 손맛으로만 드러난다.
# 🔴 **수치는 네트워크로 오지 않는다.** G_SKILL이 싣는 것은 방향뿐이고 배율·반경·사거리·쿨다운은
#   호스트가 그 피어의 공지 하위 직업 id로 리졸브한다(`SkillDef` 헤더 · `peer_weapon_id` 철학).
#   아래 clamp들은 **데이터가 깨졌을 때**의 안전망이자 공지 스푸핑의 절대 상한이다.

# 데미지 배율 하드 상한. ⚠ 이것은 신뢰 경계용 절대 상한이고, **밸런스는 아래 DPS 트립와이어가 잡는다**
#   — 상한 하나로 두 일을 시키면 "예산은 넘겼는데 clamp는 안 걸린" 값이 조용히 통과한다.
const SKILL_DAMAGE_MULT_MAX := 3.0

# spin(360°) 판정 반경 상한 = 근접 하드 상한과 **같은 값**이다.
# 🔴 "스킬이니까 더 넓어도 된다"로 올리지 마라 — 평타 부채꼴은 각이 제한되지만 spin은 **전방위**라
#   같은 반경에서도 면적이 몇 배다(대검 반각 109°면 3.3배 · 창 17°면 21배). 반경을 근접 상한에
#   묶어 두는 것이 "근접이 원거리가 되면 직업 = 플레이 방식의 변환이 무너진다"(MAX_MELEE_RANGE의
#   근거)를 스킬 축에서도 지키는 방법이다.
const SKILL_RADIUS_MAX := MAX_MELEE_RANGE

# beam(직선 관통) 사거리 상한.
# 🔴🔴 **beam은 위 `SKILL_RADIUS_MAX`의 근접 상한 축 밖이다 — 그것이 이 스킬의 존재 이유다.**
#   윗 줄만 읽고 "스킬은 근접 상한(130)에 묶여 있다"고 믿지 마라. 검성 비검은 220px를 뻗고,
#   실효 도달은 최장 근접(창 80px · 특성 최대 120px)의 **2배가 넘는다**. 두 형태에 다른 축을 준
#   것은 의도다 — spin은 "둘러싸였을 때 쓸어버린다"(전방위라 면적이 곧 위력)이고 beam은
#   "닿지 않는 것을 벤다"(축이 곧 정보라 길이가 곧 위력)다. 같은 잣대를 대면 둘 중 하나가 죽는다.
# ⚠ **유도를 원거리 무기에서 하지 마라** — 2026-08-02에 한 번 그렇게 적었다가 틀렸다: 근거로 든
#   `iron_staff`(arrow_range 260)·`worn_bow`(150)는 **2026-08-01에 데이터가 전량 삭제됐다**
#   (궁수·법사 폐기). 지금 `data/equipment`에 남은 것은 근접 4종뿐이라 그 유도는 존재하지 않는
#   수를 인용한 것이었다. 살아 있는 근거는 **화면**이다: 줌 1.3에서 보이는 영역이 492×277px이라
#   260은 가로 절반이 조금 넘는다 — "화면 안에서 끝나는 사거리"가 상한의 뜻이다.
const SKILL_LENGTH_MAX := 260.0

# 쿨다운 하한(초). 🔴 이것이 사실상의 화력 게이트다 — 배율이 아무리 clamp돼도 쿨다운이 0에
#   가까우면 스킬이 곧 평타가 된다.
const SKILL_COOLDOWN_MIN := 3.0

# 🔴 **데이터 트립와이어용 — 스킬이 더하는 초당 배율 상한**(= damage_mult ÷ cooldown_s).
#   전사 평타는 `attack_cooldown` 0.4s라 배율 기준 초당 2.5를 낸다. 0.30이면 스킬 기여가
#   그 **12% 이내**로 묶인다 — "쿨마다 한 방이 시원하되 평타를 대체하지는 않는다"의 수치화다.
#   ⚠ clamp가 아니라 **테스트가 `data/skills` 전수로 단정**한다(밸런스는 조용히 잘리면 안 된다 —
#   잘리는 순간 데이터에 적은 값과 실제가 갈라지고, 그 갈라짐이 화면에 안 드러난다).
const SKILL_DPS_ADD_MAX := 0.30

# 다단 히트 상한 (2026-08-02). 🔴 타수는 **화력이 아니라 프레임 비용**의 축이기도 하다 —
#   한 타마다 판정 질의 + `G_ENEMY_HP` 브로드캐스트가 나가므로, 웹 Compatibility에서 8타 × 다수 적은
#   그 자체로 히치를 만든다. 화력은 `SKILL_DPS_ADD_MAX`가 이미 잡으므로 여기는 **비용 상한**이다.
const SKILL_HIT_COUNT_MAX := 8
# 타 간격(초) 하한 — 🔴 이보다 촘촘하면 웹 30fps에서 **여러 타가 한 프레임에 몰려** "다단"이 아니라
#   그냥 큰 한 방이 되고, 적이 빠져나갈 틈이 사라진다(= 회피 불가능한 광역이 된다).
const SKILL_HIT_INTERVAL_MIN := 0.05
const SKILL_HIT_INTERVAL_MAX := 0.5


# --- 이동형 스킬 (2026-08-02 — 검성 「월륜」) ---
# 🔴 속도 상한 = **화살과 같은 선**(`ARROW_SPEED` 420). 검기가 화살보다 빠를 근거가 없고, 넘으면
#   터널링을 화살과 같은 방식으로 다시 따져야 한다(프레임당 전진 < 최소 명중 지름).
const SKILL_TRAVEL_SPEED_MAX := ARROW_SPEED
# 🔴 사거리 상한 = **전투 칸 가로(1280px)의 절반**. 유도 근거 둘:
#   ⑴ 화면 가로가 줌 1.3에서 492px이므로 640이면 **화면 밖으로 확실히 사라진다** = 사용자가 말한
#      *"맵 끝까지 가면서 서서히 사라지는"* 그림이 성립한다.
#   ⑵ 그런데도 맵 **반대편 끝까지는 못 간다** — 한 방으로 칸 전체를 훑으면 위치 선정이 무의미해진다.
# ⚠ `SKILL_LENGTH_MAX`(beam 260)와 **다른 축이다**. 저쪽은 「제자리에서 뻗는 띠」라 즉시 판정이고,
#   이쪽은 날아가는 데 시간이 걸려 적이 피할 수 있다 — 그래서 더 멀리 허용한다.
const SKILL_TRAVEL_DIST_MAX := 640.0


static func clamp_skill_travel_speed(v: float) -> float:
	if not is_finite(v) or v <= 0.0:
		return 0.0    # 0 = 제자리 = 이동형 도입 전과 항등
	return minf(v, SKILL_TRAVEL_SPEED_MAX)


static func clamp_skill_travel_dist(v: float) -> float:
	if not is_finite(v) or v <= 0.0:
		return 0.0
	return minf(v, SKILL_TRAVEL_DIST_MAX)


# 이동형 검기의 비행 시간(초) — 🔴 **표시(FX 수명)와 호스트 판정 수명이 같은 함수를 지난다**.
#   사본을 두면 "검기는 아직 날아가는데 판정이 끝났다"(또는 그 반대)가 되고, 그건 화면에
#   이유가 안 드러난다(`arrow_lifetime_s`와 같은 관용구·같은 이유).
static func skill_travel_lifetime_s(speed: float, dist: float) -> float:
	var v := clamp_skill_travel_speed(speed)
	if v <= 0.0:
		return 0.0
	return clamp_skill_travel_dist(dist) / v


static func clamp_skill_hit_count(n: int) -> int:
	return clampi(n, 1, SKILL_HIT_COUNT_MAX)   # 0·음수 = 1(단발) = 이 축 도입 전과 항등


static func clamp_skill_hit_interval(s: float) -> float:
	if not is_finite(s):
		return SKILL_HIT_INTERVAL_MIN
	return clampf(s, SKILL_HIT_INTERVAL_MIN, SKILL_HIT_INTERVAL_MAX)


# 🔴 **그 스킬이 한 사이클에 내는 총 배율** — 예산 트립와이어와 밸런스 판단이 **같은 이 함수**를
#   지나야 한다. `damage_mult`만 보면 다단 스킬의 화력을 타수만큼 과소평가하고, 그 오차는
#   "데이터에 적은 값"과 "실제로 나가는 값"이 갈라진 형태라 화면에 안 드러난다.
static func skill_total_mult(sk: SkillDef) -> float:
	if sk == null:
		return 0.0
	return clamp_skill_mult(sk.damage_mult) * float(clamp_skill_hit_count(sk.hit_count))


static func clamp_skill_mult(m: float) -> float:
	if not is_finite(m) or m <= 0.0:
		return 1.0    # "비었다"와 "깨졌다"를 같은 항등값으로 (clamp_combo_mult와 같은 관용구)
	return minf(m, SKILL_DAMAGE_MULT_MAX)


static func clamp_skill_radius(r: float) -> float:
	if not is_finite(r) or r <= 0.0:
		return 0.0    # 0 = 아무도 안 맞는다(안전한 폴백 — 넓어지는 쪽으로 틀리지 않는다)
	return minf(r, SKILL_RADIUS_MAX)


static func clamp_skill_length(l: float) -> float:
	if not is_finite(l) or l <= 0.0:
		return 0.0
	return minf(l, SKILL_LENGTH_MAX)


static func clamp_skill_cooldown(c: float) -> float:
	if not is_finite(c) or c <= 0.0:
		return SKILL_COOLDOWN_MIN
	return maxf(c, SKILL_COOLDOWN_MIN)


# 스킬 발동 가능한가 — 🔴 로컬 쿨다운(HUD 게이지)과 호스트 검증이 **같은 함수**를 지난다.
#   `is_fire_rate_ok`와 같은 규약: 호스트는 클라 주장이 아니라 **자기 수신 시각**으로 재고,
#   `FIRE_RATE_SLACK`만큼 관대하게 잡는다(네트워크가 삼킬 수 있다고 이미 인정한 몫 —
#   조이면 정직한 발동이 무음 거부되고 그 증상이 지연 결함과 구분되지 않는다).
static func is_skill_ready(last_msec: int, now_msec: int, cooldown_s: float) -> bool:
	return now_msec - last_msec >= int(clamp_skill_cooldown(cooldown_s) * FIRE_RATE_SLACK * 1000.0)


# 🔴 **클라가 스스로 물러서는 간격(초) — 호스트 게이트에 딱 붙이지 마라** (netreview C-1 2026-08-02).
#
# 왜 `is_skill_ready`를 클라가 그대로 쓰면 안 되나:
#   호스트가 재는 것은 클라의 입력 간격이 아니라 **자기 수신 프레임 간격**이다.
#     호스트 델타 = 클라 델타 + (편도₂ − 편도₁) + 수신 프레임 양자화(웹 30fps = ±33.3ms)
#   클라가 같은 문턱(`cd × FIRE_RATE_SLACK`)을 쓰면 여유가 **정확히 0**이라, 위 두 항 중 하나만
#   음수여도 거부된다. 그리고 HUD 게이지가 그 문턱에서 0을 찍어 **플레이어를 그 경계로 유도한다.**
# 🔴 대가가 근접·발사보다 훨씬 크다: 거부돼도 클라는 앵커를 갱신하므로 **쿨다운 8~9초를 통째로
#   잃는다**(근접은 400ms 뒤 다시 친다). 게다가 호스트 자신은 동기 호출이라 **영향이 0**이라,
#   "호스트 화면에서는 완벽한 버그"가 된다 — 이 프로젝트가 가장 경계하는 형태다.
# 증상은 무증상에 가깝다: 선딜·FX·타격음·카메라 킥이 전부 정상이고 **적 HP만 안 깎인다.**
#
# 🔴 첫 항이 `cd`이지 `cd / FIRE_RATE_SLACK`이 아니다 — `auto_fire_gap_s`와 갈리는 유일한 자리다.
#   거긴 쿨다운이 0.15~0.4s라 나눗셈이 40ms를 더할 뿐이지만, 스킬은 8~9s라 **1초를 더 기다리게**
#   된다. `cd`만으로 여유가 이미 `cd × (1 − FIRE_RATE_SLACK)` = 300ms(하한 3s)~900ms이고,
#   이는 편도 변동 최악(`LAG_MAX_ONE_WAY_MS` 200ms) + 프레임 양자화(33ms)를 덮는다.
# ⚠ 두 번째 항은 짧은 쿨다운에서 첫 항을 넘길 때를 위한 안전망이다(현행 하한 3s에서는 안 걸린다).
#   `SKILL_COOLDOWN_MIN`을 0.4s 아래로 내리면 그때부터 이 항이 지배한다.
# 🔴 **HUD 남은 시간도 이 함수를 지나야 한다** — 안 그러면 "0초인데 안 나간다"가 된다.
static func skill_cast_gap_s(cooldown_s: float) -> float:
	var cd := clamp_skill_cooldown(cooldown_s)
	return maxf(cd, cd * FIRE_RATE_SLACK + AUTO_FIRE_HOST_FRAME_S)


# 스킬 명중 판정 — 🔴 **단일 소스**(로컬 표시 · 호스트 확정이 같이 부른다).
#   spin = 시전자 중심 원        ≡ is_strike_hit          (보스 원형 패턴과 같은 함수)
#   beam = 시전자에서 dir 방향 띠 ≡ capsule_depth >= 0     (보스 횡단 돌진과 같은 함수)
# 🔴 **새 기하를 만들지 않았다** — 두 형태 모두 이 파일이 이미 쥔 판정을 재사용한다.
#   그래서 "예고 셰이더가 그리는 도형"도 그대로 재사용할 수 있다(boss_telegraph의 원/캡슐 분기).
# slack_px = 대상(잔몹) 좌표가 낡은 만큼의 여유. 🔴 **호스트만 `mob_lag_slack_px`를 넘긴다** —
#   G_MOB_POS가 10Hz·외삽 없음이라 게스트 화면의 적은 호스트보다 낡았고, 그 차이만큼 정직한
#   발동이 거부되면 증상이 "스킬은 나갔는데 적 HP만 안 깎인다"가 되어 §3 근접 지연 결함과
#   **구분되지 않는다**. 관대해지는 대상이 NPC라 「방어자 우대」와 이해가 충돌하지 않는다
#   (근접 각 슬랙과 같은 판단 — rules §3).
# ⚠ 모르는 shape는 **false**로 떨어진다(안 맞는 쪽 = 안전한 폴백, 보스 `shape` 규약 미러).
static func is_skill_hit(shape: String, enemy_pos: Vector2, caster_pos: Vector2, dir: Vector2,
		radius: float, length: float, enemy_radius: float = 0.0, slack_px: float = 0.0) -> bool:
	var r := clamp_skill_radius(radius) + maxf(enemy_radius, 0.0) + maxf(slack_px, 0.0)
	if shape == SkillDef.SHAPE_SPIN:
		return is_strike_hit(enemy_pos, caster_pos, r)
	if shape == SkillDef.SHAPE_BEAM:
		var d := dir.normalized()
		if d == Vector2.ZERO:
			return false   # 방향 없는 beam은 띠가 정의되지 않는다(길이 0 캡슐 = 원이 되면 안 된다)
		var tip := caster_pos + d * clamp_skill_length(length)
		return capsule_depth(enemy_pos, caster_pos, tip, r) >= 0.0
	return false
