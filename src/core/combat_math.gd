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


# 한 스윙이 여러 적을 치는 것은 허용하되(SAME_SWING_MS 안), 스윙 간격은 쿨다운(지터 여유 0.9배)을 강제.
# 앵커(last_confirm_msec)는 새 스윙에서만 갱신해야 한다 — 매 확정마다 갱신하면 창이 미끄러져 연사 스팸이 뚫린다.
const SAME_SWING_MS := 50


static func is_hit_cooldown_ok(last_confirm_msec: int, now_msec: int, job: JobDef) -> bool:
	var dt := now_msec - last_confirm_msec
	return dt <= SAME_SWING_MS or dt >= int(job.attack_cooldown * 0.9 * 1000.0)
