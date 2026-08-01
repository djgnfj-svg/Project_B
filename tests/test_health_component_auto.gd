extends SceneTree
# HealthComponent(src/combat) 단위 테스트 — 권한/표시 경로 분리와 부활 타이머 규율.
# 성공/실패 모두 한 줄씩 찍는다 (침묵 통과 방지 — projectb-verify §3).
# 컴포넌트는 오토로드 무접근이라 -s로 바로 돈다 (rules §5). 타이머는 tick()을 직접 민다.
# 실행: ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_health_component_auto.gd

const HealthComponent := preload("res://src/combat/health_component.gd")


func _initialize() -> void:
	var failures := 0

	# --- 권한 경로: 데미지·클램프·사망 ---
	var h := _new_health(10, true, 3.0)
	var confirmed: Array = []
	var changed: Array = []  # [hp, dropped] 쌍
	h.hp_confirmed.connect(func(hp: int) -> void: confirmed.append(hp))
	h.hp_changed.connect(func(hp: int, dropped: bool) -> void: changed.append([hp, dropped]))

	failures += _check(h.hp == 10 and h.max_hp == 10, "setup: hp = max_hp")
	failures += _check(not h.is_dead(), "setup: is_dead 아님")
	h.apply_damage(3)
	failures += _check(h.hp == 7, "damage: 10-3 = 7")
	failures += _check(changed == [[7, true]], "damage: hp_changed(7, dropped)")
	failures += _check(confirmed == [7], "damage: hp_confirmed(7)")

	h.apply_damage(100)
	failures += _check(h.hp == 0, "overkill: 0 클램프 (음수 금지)")
	failures += _check(h.is_dead(), "overkill: is_dead")
	# 🔴🔴 **오버킬에서도 실데미지가 남는다** (2026-08-01 사용자 신고: *"5 남았을 때 대미지가 5뜨는 거"*).
	#   HP 7에 100을 넣었으니 hp 감소량은 **7뿐**인데 실제로 들어간 딜은 100이다. 피격 글루가
	#   `last_damage`를 우선하지 않고 감소량으로 되돌아가면 여기서 빨개진다 — 그 회귀는 화면에서
	#   **막타에만** 나타나 눈으로는 "원래 그런가" 싶은 종류다(에러 없음).
	failures += _check(h.last_damage == 100,
		"★overkill: last_damage = 실제 딜(100) — hp 감소량(7)이 아니다")
	# ⚠ 나머지 딜 검사는 **별도 인스턴스**로 한다 — `confirm_hp`가 부활 타이머를 해제하고
	#   `confirmed` 배열에 항목을 더해서, 여기서 부르면 아래 부활 케이스들이 통째로 무너진다.
	failures += _dmg_side_channel_checks()

	h.apply_damage(5)
	failures += _check(confirmed == [7, 0], "사망 후 apply_damage 무시 (확정 추가 없음)")

	# --- 부활 타이머: respawns=true + apply_damage 경로만 arm ---
	h.tick(2.9)
	failures += _check(h.hp == 0, "respawn: 지연 전(2.9s)엔 죽어 있음")
	h.tick(0.2)
	failures += _check(h.hp == 10, "respawn: 지연 경과(3.1s) 후 max_hp 부활")
	failures += _check(confirmed == [7, 0, 10], "respawn: 부활도 hp_confirmed (권한 경로)")
	failures += _check(changed.back() == [10, false], "respawn: hp_changed(10, not dropped)")
	h.tick(999.0)
	failures += _check(confirmed == [7, 0, 10], "respawn: 부활 후 타이머 재발화 없음")
	h.free()

	# --- respawns=false: 부활 안 함 ---
	var h2 := _new_health(5, false)
	h2.apply_damage(5)
	h2.tick(999.0)
	failures += _check(h2.hp == 0 and h2.is_dead(), "respawns=false: 시간이 흘러도 죽은 채")
	h2.free()

	# --- 표시 경로(게스트): hp 반영만 — 타이머·hp_confirmed 절대 없음 ---
	var h3 := _new_health(10, true, 3.0)
	var confirmed3: Array = []
	var changed3: Array = []
	h3.hp_confirmed.connect(func(hp: int) -> void: confirmed3.append(hp))
	h3.hp_changed.connect(func(hp: int, dropped: bool) -> void: changed3.append([hp, dropped]))
	h3.set_hp_display(4)
	failures += _check(h3.hp == 4, "display: hp 반영")
	failures += _check(changed3 == [[4, true]], "display: hp_changed(4, dropped)")
	h3.set_hp_display(0)
	h3.tick(999.0)
	failures += _check(h3.hp == 0, "display: respawns=true여도 타이머 안 돎 (게스트 자가 부활 금지)")
	h3.set_hp_display(10)
	failures += _check(changed3.back() == [10, false], "display: 부활 수신은 hp_changed(not dropped)")
	failures += _check(confirmed3.is_empty(), "display: hp_confirmed 무발신")
	h3.free()

	# --- 음수 데미지 방어: 힐 경로 아님 (회복은 confirm_hp만) ---
	var h5 := _new_health(10, false)
	h5.apply_damage(3)
	h5.apply_damage(-100)
	failures += _check(h5.hp == 7, "negative: 음수 dmg는 무시 (max_hp 초과 힐 차단)")
	h5.free()

	# --- confirm_hp(호스트 외부 확정): 대기 타이머 해제 ---
	var h4 := _new_health(10, true, 3.0)
	h4.apply_damage(10)
	h4.confirm_hp(10)
	h4.tick(999.0)
	failures += _check(h4.hp == 10, "confirm_hp: 부활 확정이 대기 타이머를 해제 (이중 부활 없음)")
	h4.free()

	if failures == 0:
		print("TEST_OK health_component")
		quit(0)
	else:
		printerr("TEST_FAIL health_component — %d개 실패" % failures)
		quit(1)


# 🔴 실데미지 사이드채널(`last_damage`) — 데미지 숫자 표시의 단일 소스 (2026-08-01).
# 신고: *"5 남았을 때 대미지가 5뜨는 거 → 그냥 들어간 딜이 뜨게"*. `hp = maxi(0, hp - dmg)`라
#   hp 감소량으로 역산하면 **오버킬이 잘려** 막타만 실제보다 작게 떴다.
# ⚠ 격리된 인스턴스로 도는 이유는 호출부 주석 참조(부활 타이머·confirmed 배열 오염).
func _dmg_side_channel_checks() -> int:
	var f := 0
	var d := _new_health(50, false)
	d.apply_damage(12)
	f += _check(d.last_damage == 12, "★deal: 평범한 타격은 감소량과 실딜이 같다(항등 구간)")
	# **0 = 미상 폴백**이 성립하는가 — `confirm_hp`(부활·피흡·모닥불)엔 데미지 개념이 없다.
	#   스테일 값이 남으면 회복 직후 타격이 **이전 딜을 물려받아** 거짓 숫자를 띄운다
	#   (`last_crit` 스테일 함정과 같은 부류, rules §5).
	d.confirm_hp(40)
	f += _check(d.last_damage == 0,
		"★confirm_hp: last_damage 0 리셋 (스테일 딜을 다음 타격이 물려받지 않게)")
	var g := _new_health(50, false)
	g.set_hp_display(30, false, 33)
	f += _check(g.last_damage == 33, "★display: 게스트는 ehp \"d\"로 실데미지를 받는다")
	g.set_hp_display(28)
	f += _check(g.last_damage == 0,
		"★display: 인자 생략 = 0 = 미상 → 감소량 폴백 (구버전 호스트와 항등)")
	g.set_hp_display(20, false, -5)
	f += _check(g.last_damage == 0, "★display: 음수 딜은 0으로 (오염 페이로드 방어)")
	return f


func _new_health(max_hp: int, respawns: bool, delay: float = 0.0) -> HealthComponent:
	var h := HealthComponent.new()
	h.setup(max_hp, respawns, delay)
	return h


func _check(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	printerr("  FAIL %s" % label)
	return 1
