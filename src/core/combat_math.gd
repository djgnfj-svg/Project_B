class_name CombatMath
extends RefCounted
# 전투 수치 계산 — 단일 소스 (projectb-rules §3 하드 계약).
# UI 표시·실전투(호스트 확정)가 전부 이 함수만 부른다. 다른 곳에서 같은 계산을 만들면 갈라진다.


# 최종 데미지. 장비 도입 시 total_stats() 결과를 받도록 확장한다 (§3 예약).
static func calc_damage(job: JobDef) -> int:
	return job.attack_damage


# 호스트의 적중 요청 검증 — 공격자 위치 기준 사거리 내인가 (지연 감안 여유 배율).
static func is_hit_in_reach(attacker_pos: Vector2, enemy_pos: Vector2, job: JobDef) -> bool:
	return attacker_pos.distance_to(enemy_pos) <= job.attack_range * 2.0


# 히트 기하 — 단일 소스 (§3). 실제 판정(원형 질의)과 공격 FX 위치가 같은 함수를 부른다.
# 한쪽만 조이면 "맞는 곳"과 "보이는 곳"이 어긋난다 — 손맛 튜닝은 반드시 여기서.
const ATTACK_CENTER_SCALE := 0.6  # 공격 중심까지의 거리 = range * 이 값
const ATTACK_RADIUS_SCALE := 0.5  # 판정 반경 = range * 이 값


static func attack_center_offset(dir: Vector2, job: JobDef) -> Vector2:
	return dir * (job.attack_range * ATTACK_CENTER_SCALE)


static func attack_radius(job: JobDef) -> float:
	return job.attack_range * ATTACK_RADIUS_SCALE


# 한 스윙이 여러 적을 치는 것은 허용하되(SAME_SWING_MS 안), 스윙 간격은 쿨다운(지터 여유 0.9배)을 강제.
# 앵커(last_confirm_msec)는 새 스윙에서만 갱신해야 한다 — 매 확정마다 갱신하면 창이 미끄러져 연사 스팸이 뚫린다.
const SAME_SWING_MS := 50


static func is_hit_cooldown_ok(last_confirm_msec: int, now_msec: int, job: JobDef) -> bool:
	var dt := now_msec - last_confirm_msec
	return dt <= SAME_SWING_MS or dt >= int(job.attack_cooldown * 0.9 * 1000.0)


# 구르기 타이밍 — 단일 소스 (§3). 로컬 이동(player)과 호스트 i-frame 검증이 같은 값을 읽는다.
# player.gd에 사본을 남기면 첫 손맛 튜닝에서 구르기 거리와 무적 창이 갈라진다.
const ROLL_TIME_S := 0.25
const ROLL_COOLDOWN_S := 0.8
const ROLL_IFRAME_GRACE_MS := 120  # 지연 여유 — 사거리 검증 2.0배 완충과 같은 철학


# 호스트의 구르기 그랜트 검증 — 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 구르기 이상의 무적을 못 얻는다.
static func is_roll_grant_ok(last_grant_msec: int, now_msec: int) -> bool:
	return now_msec - last_grant_msec >= int(ROLL_COOLDOWN_S * 0.9 * 1000.0)


# 그랜트된 i-frame 창이 현재 유효한가 (호스트가 데미지 확정 직전에 조회).
static func is_iframe_active(grant_msec: int, now_msec: int) -> bool:
	return now_msec - grant_msec <= int(ROLL_TIME_S * 1000.0) + ROLL_IFRAME_GRACE_MS


# 잔몹 타격 판정 — 단일 소스 (§3). 호스트 판정과 텔레그래프 표시가 같은 반경(def.strike_radius)을 읽는다.
static func is_strike_hit(player_pos: Vector2, strike_center: Vector2, strike_radius: float) -> bool:
	return player_pos.distance_to(strike_center) <= strike_radius
