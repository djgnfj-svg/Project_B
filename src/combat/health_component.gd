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

# 테스트 랩 무적 — 켜지면 권한 경로 apply_damage가 항등(HP 안 깎임). 기본 false라 프로덕션 무영향.
# 로컬 플레이어·랩 NPC에만 세운다(TestMode 게이트, 외부에서). 여긴 필드만 — 오토로드 전역 참조 금지(-s, rules §5).
var invincible: bool = false

# 테스트 랩 데미지 캡 — 켜지면 모든 apply_damage가 1로(전 개체 공용). 기본 false라 프로덕션·헤드리스 무영향.
# 정적이라 랩이 한 번만 켜면 보스·잔몹 전부 적용. 오토로드 참조 아님(rules §5 준수 — 외부가 켠다).
static var force_damage_one: bool = false

var _respawns: bool = false
var _respawn_delay: float = 0.0
var _respawn_left: float = 0.0  # apply_damage(권한 경로)만 arm한다

# 마지막 HP 변동이 치명타였나 — 피격 글루가 hp_changed 직후 읽어 combat_impact로 올린다 (성장축 2026-07-25).
# 🔴 사이드채널이다: **emit 직전에 반드시 덮어써야** 한다(비-치명 경로는 false로). 안 덮으면 다음 평타가
#   이전 치명 강조를 물려받는다 — 에러 없이 화면만 거짓말한다(rules §5). hp_changed 시그니처를 늘리지
#   않는 이유 = 리스너 5곳(적·잔몹·보스·플레이어·테스트)을 건드리지 않기 위해.
var last_crit: bool = false

# 마지막 HP 변동에서 **실제로 들어간 데미지** — `last_crit`과 같은 사이드채널이다 (2026-08-01
#   사용자 요구: *"5남았을 때 대미지가 5뜨는 거 → 그냥 들어간 딜이 뜨게"*).
# 🔴 **왜 hp 감소량으로는 못 구하나:** `hp = maxi(0, hp - dmg)`라 **오버킬이 잘린다.** 5 남은 적을
#   10으로 때리면 감소량은 5뿐이고, 글루가 그걸 그대로 띄워 **막타만 실제보다 작게 표시**됐다
#   (가장 자주 보이는 타격인 마무리 일격이 하필 제일 거짓말을 했다).
# 🔴 `last_crit`과 **똑같은 규약**: emit 직전에 반드시 덮어쓴다. 안 덮으면 다음 타격이 이전 값을
#   물려받아 화면만 거짓말한다(rules §5). `hp_changed` 시그니처를 늘리지 않는 이유도 같다 —
#   리스너 5곳(적·잔몹·보스·플레이어·테스트)을 건드리지 않기 위해서다.
# 🔴 **0 = "미상"이고 글루가 hp 감소량으로 폴백한다.** `confirm_hp`(부활·피흡·모닥불처럼 HP를
#   통째로 대입하는 경로)는 데미지라는 개념이 없어 값을 만들 수 없다 — 거기서 0을 넣어 폴백을
#   태우는 것이 옛 동작과 항등이다.
# ⚠ **상한 clamp가 없다 — 의도된 예외다**(netreview M-1). 이 프로젝트는 네트워크로 오는 수치에
#   상한을 두는 것이 관례지만(`TRAIT_MAX`·`LEVEL_STAT_MAX`·`MAX_ARROW_RANGE`), 여기서 값을 싣는 것은
#   **호스트뿐**이고 호스트는 이미 `hp` 자체를 임의로 정하는 권한을 갖는다 — `d`가 주는 추가 권능이
#   **0**이다(조작 호스트는 그냥 적을 즉사시키면 된다). 소비처도 안전하다: 데미지 숫자는 라벨
#   문자열로만 쓰이고, 카메라 셰이크·SFX는 `amount`를 **아예 안 읽는다**(kind·crit로만 결정).
#   최악은 라벨이 길어지는 것뿐이라, 근거 없는 상수를 상한으로 박지 않는다.
# ⚠ **`set_max_hp`는 이 값을 안 덮는다 — `last_crit`과 같은 예외다**(netreview M-2). 그쪽은
#   `dropped = false`로 emit하고 소비처가 전부 조기 리턴하므로 도달하지 않는다. 즉 안전 근거가
#   **소비처 쪽에** 있다 — `if dropped` 밖에서 이 값을 읽는 리스너를 만들면 그때 깨진다.
var last_damage: int = 0


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
func apply_damage(dmg: int, crit: bool = false, bypass_invincible: bool = false) -> void:
	if invincible and not bypass_invincible:
		return  # 무적(테스트 랩) — 단 bypass_invincible이면 뚫는다(특정 판정만 대가를 주게)  # 테스트 랩 무적 — 데미지 무시 (로컬 플레이어·NPC 더미)
	if hp <= 0 or dmg <= 0:
		return
	if force_damage_one:
		dmg = 1  # 테스트 랩 — 모든 데미지 1
	last_crit = crit  # emit 직전 덮어쓰기 (평타가 이전 치명 강조를 물려받지 않게)
	last_damage = dmg  # 🔴 **clamp 전 값** — 이걸 `hp` 감소량으로 재면 오버킬이 잘린다(위 주석)
	hp = maxi(0, hp - dmg)
	hp_changed.emit(hp, true)
	hp_confirmed.emit(hp)
	if hp <= 0 and _respawns:
		_respawn_left = _respawn_delay


# 호스트 전용 — HP 확정 (부활 등). 대기 중인 부활 타이머는 해제한다.
func confirm_hp(new_hp: int) -> void:
	_respawn_left = 0.0
	last_crit = false  # 확정/회복(부활·피흡·모닥불)은 치명타가 아니다 — 스테일 플래그 제거
	last_damage = 0    # 데미지 개념이 없는 경로 = 미상 → 글루가 hp 감소량으로 폴백(옛 동작과 항등)
	var dropped := new_hp < hp
	hp = new_hp
	hp_changed.emit(hp, dropped)
	hp_confirmed.emit(hp)


# 게스트 표시 전용 — 호스트가 확정한 HP 반영. 타이머 arm·hp_confirmed 절대 없음.
func set_hp_display(new_hp: int, crit: bool = false, dmg: int = 0) -> void:
	last_crit = crit  # 게스트는 ehp "cr"로만 치명을 안다 — 권한 경로와 같은 규약(emit 직전 덮어쓰기)
	# 🔴 게스트가 실데미지를 아는 유일한 경로 = ehp "d"(치명 "cr"과 같은 자리). 인자를 생략하면
	#   0 = 미상 → 폴백이라, 구버전 호스트·다른 호출부와 **완전 항등**이다.
	last_damage = maxi(dmg, 0)
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
