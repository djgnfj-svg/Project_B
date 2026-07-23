extends Node
# HP·피격·부활 공용 컴포넌트 — 바디 타입(StaticBody2D/CharacterBody2D) 무관하게 자식 노드로 문다.
# 권한 경로(호스트): apply_damage()/confirm_hp() → hp_changed + hp_confirmed emit (글루가 브로드캐스트).
# 표시 경로(게스트): set_hp_display() → hp_changed만 — 부활 타이머를 절대 돌리지 않는다
# (자가 부활 금지: 탭 백그라운드로 타이머가 멎으면 영구 드리프트, rules §1).
# ⚠ 오토로드 전역 식별자 금지 — -s 헤드리스 테스트 대상 (rules §5). 노드 로컬 시그널만.

signal hp_changed(hp: int, dropped: bool)  # 모든 경로 — 비주얼 글루용
signal hp_confirmed(hp: int)               # 권한 경로만 — 브로드캐스트 글루용

var hp: int = 0
var max_hp: int = 0

var _respawns: bool = false
var _respawn_delay: float = 0.0
var _respawn_left: float = 0.0  # apply_damage(권한 경로)만 arm한다


func setup(p_max_hp: int, p_respawns: bool = false, p_respawn_delay: float = 0.0) -> void:
	max_hp = p_max_hp
	hp = p_max_hp
	_respawns = p_respawns
	_respawn_delay = p_respawn_delay
	_respawn_left = 0.0


func is_dead() -> bool:
	return hp <= 0


# 최대치만 변경 — setup과 달리 현재 HP를 리셋하지 않는다 (챕터 스테이지 간 HP 이월 보존).
# 늦게 도착한 직업 공지가 setup으로 이월 HP를 조용히 풀피로 되돌리는 경합 방지 (player.set_job 경로).
# 최초 셋업(max 0)은 setup으로 위임 = 풀피 시작. 새 최대치 초과분은 클램프만 하고 확정 방송은
# 다음 확정에 맡긴다 (직업은 첫 공지에 잠기므로 실전에서 초과 클램프는 사실상 없다).
func set_max_hp(p_max: int) -> void:
	if max_hp == 0:
		setup(p_max)
		return
	max_hp = p_max
	if hp > max_hp:
		hp = max_hp
		hp_changed.emit(hp, false)  # 최대치 축소 클램프는 피격 아님 — dropped=false (거짓 손맛 방지, 장비 교체 시)


# 호스트 권한 경로 전용 — 데미지 확정. 사망 + respawns면 부활 타이머 arm.
# 음수 dmg 방어: 힐 경로가 아니다 — 회복은 confirm_hp로 (공용 컴포넌트 방어선)
func apply_damage(dmg: int) -> void:
	if hp <= 0 or dmg <= 0:
		return
	hp = maxi(0, hp - dmg)
	hp_changed.emit(hp, true)
	hp_confirmed.emit(hp)
	if hp <= 0 and _respawns:
		_respawn_left = _respawn_delay


# 호스트 전용 — HP 확정 (부활 등). 대기 중인 부활 타이머는 해제한다.
func confirm_hp(new_hp: int) -> void:
	_respawn_left = 0.0
	var dropped := new_hp < hp
	hp = new_hp
	hp_changed.emit(hp, dropped)
	hp_confirmed.emit(hp)


# 게스트 표시 전용 — 호스트가 확정한 HP 반영. 타이머 arm·hp_confirmed 절대 없음.
func set_hp_display(new_hp: int) -> void:
	var dropped := new_hp < hp
	hp = new_hp
	hp_changed.emit(hp, dropped)


func _process(delta: float) -> void:
	tick(delta)


# 부활 카운트다운 — 테스트가 직접 틱할 수 있게 분리 (헤드리스에선 _process가 안 돈다)
func tick(delta: float) -> void:
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			confirm_hp(max_hp)
