extends Camera2D
# 로컬 플레이어 추적 카메라 + 스크린셰이크 (src/feel, 사용자 확정 2026-07-23: 로컬 추적).
# player.tscn의 자식 — 로컬 플레이어 인스턴스만 enabled=true(=현재 카메라). 원격 피어의
# 카메라는 비활성이라 뷰포트를 잡지 않는다(player.gd setup에서 enabled=is_local).
# 흔들림 = offset에 감쇠하는 랜덤 변위. Engine.time_scale 안 건드림 (rules §5 멀티 안전).
# EventBus 구독은 씬 스크립트라 전역 식별자 허용 (rules §5 — 헤드리스 -s 대상 아님).
# 연출값 (rules §0 예외).

# 🔴 확대 배율 (사용자 요청 2026-07-26: 16px 전환 후 "좀더 확대해줘").
# 🔴 **줌은 1.5다 — 2026-08-02에 1.0 · 1.5 · 2.0을 실기로 나란히 보고 골랐다.**
# 이 상수는 원래 없었다. 2026-07-26에 아트를 16px로 내리면서 캐릭터가 화면 세로의 1/22이 되자
# **그 보정으로** 2.0이 들어왔고(`a29991a`), 같은 날 32px로 되돌아오면서 1.0으로 돌렸다(07-27).
# 08-02에 다시 올린 이유는 그때와 다르다 — 아트가 작아서가 아니라 **궤적 질감·손맛이 화면에서
# 읽히려면 이 배율이 필요했다**(리본 질감 도입과 같은 세션). 2.0은 시야가 320×180까지 좁아진다.
# ⚠ **1.5는 비정수배다** — 픽셀 1개가 어디선 2px, 어디선 1px로 늘어난다. 원래 이 자리엔 "정수
#   배율만 써라(1.5·2.5는 픽셀이 뭉갠다)"는 경고가 있었고, 그 경고는 **실기 비교로 뒤집혔다**:
#   2.0의 깨끗한 픽셀보다 1.5의 넓은 시야가 낫다고 판단했다(전 맵 어그로로 8~10마리가 동시에 온다).
#   🔴 되돌리려면 그 비교를 **다시 눈으로** 해라 — 계산이 아니라 화면을 보고 정한 값이다.
# ⚠ HUD는 CanvasLayer라 영향을 안 받는다.
# ⚠ 올리면 보이는 범위가 그만큼 줄어 맵이 넓게 느껴지고 같은 move_speed가 더 빠르게 보인다 —
#   아래 두 상한도 배율만큼 나눠야 한다(그 미러가 이 파일 안에 있다).
const ZOOM := 1.5

const SHAKE_DECAY := 14.0   # 초당 감쇠량(클수록 빨리 잦아든다)
# ⚠ 아래 두 상한은 **줌 좌표계**다 — offset에 zoom이 곱해져 화면에 나가므로, 확대 배율만큼
#   나눠야 체감이 유지된다. 안 그러면 확대한 만큼 화면이 더 크게 흔들려 멀미가 난다.
const SHAKE_MAX := 4.67     # 오프셋 상한(px) — 640×360 / ZOOM 1.5 기준 (7.0 / 1.5)
const SMOOTH_SPEED := 9.0   # 위치 추적 부드러움
# combat_impact 종류별 기본 셰이크 강도 (내가 맞으면 더 크게)
const IMPACT_SHAKE := {"enemy": 1.5, "player": 3.0}
const CRIT_SHAKE_MULT := 1.6  # 치명타 셰이크 가중 (성장축 2026-07-25 — 연출값, rules §0 예외)
# 방향성 반동 (사용자 요청 2026-07-26: "카메라가 좀더 쫀득해야함 — 반동이 필요").
# 셰이크와 **다른 축**이라 따로 쌓고 offset에서 합친다: 셰이크는 무작위 진동, 반동은 방향이 읽히는 밀림.
const KICK_MAX := 6.0        # 반동 변위 상한(px) — 줌 좌표계 (9.0 / 1.5). 셰이크와 합쳐도 화면이 안 무너지는 선
const KICK_DECAY := 34.0     # 밀린 뒤 되돌아오는 속도(px/s). 셰이크보다 훨씬 빨라야 "톡" 치는 느낌
const KICK_SMOOTH := 26.0    # 밀리는 순간의 부드러움 — 즉시 점프하면 프레임 튀듯 보인다

var _shake: float = 0.0
var _kick: Vector2 = Vector2.ZERO        # 현재 적용 중인 반동 변위
var _kick_target: Vector2 = Vector2.ZERO # 목표 변위 — 여기로 빠르게 따라간 뒤 함께 0으로 감쇠

# --- 보스 패턴 줌아웃 (2026-08-02 사용자 요청: "특정 패턴에서 카메라를 뒤로 빼서 맵이 꽉 차게") ---
# 🔴 **표시 전용·각 클라 로컬이다 — 네트워크 메시지 0개.** 발동 신호는 이미 오는
#   `EventBus.boss_telegraph`(← G_BOSS_ATK 브로드캐스트)를 **구독만** 한다(§2 손맛 계층 규약:
#   "모든 손맛은 EventBus 훅에서 파생된다 — 판정 코드에 연출을 섞지 마라").
# ⚠ **추적은 계속 플레이어를 따라간다** — 줌만 바뀐다(사용자 확정: 패턴이 끝나면 원래대로).
#   보스 고정·중점 이동은 안 한다: 피하는 것이 목적인 구간에서 내 캐릭터가 화면 밖으로 나가면
#   본말전도이고, 2인이면 각자 다른 지점이 되어 화면이 갈린다.
# 🔵 **줌 값의 근거 = 보스 아레나 실측**(`meadow_arena.png` 768×416, 화면 640×360):
#   가로 `640/768 = 0.833` · 세로 `360/416 = 0.865` → 둘 다 담으려면 **작은 쪽**이 기준이다.
#   0.8이면 보이는 영역이 800×450이라 아레나(768×416)를 여유 있게 덮는다.
#   ⚠ 아레나 텍스처를 갈면 이 값을 다시 유도해라(미러 — 그 파일 크기가 정본이다).
const ZOOM_WIDE := 0.8
# 이 패턴들에서만 줌아웃한다. ⚠ **id는 `data/enemies/*.tres`의 `BossPatternDef.id`와 미러**다 —
#   패턴 id를 바꾸면 여기도 바뀌어야 하고, 안 맞으면 **에러 없이 그냥 안 뒤로 빠진다.**
const WIDE_PATTERNS := {"spin": true}
const ZOOM_OUT_S := 0.35     # 뒤로 빠지는 시간(빠르게 — 예고를 가리면 안 된다)
const ZOOM_BACK_S := 0.55    # 돌아오는 시간(느리게 — 급히 당기면 멀미가 난다)
# 유지 시간 = 그 패턴의 예고 + 여유. ⚠ 호스트 예고 창은 지연 보상만큼 **길어질 수 있는데**
#   카메라는 그 값을 모른다(시그널에 안 실린다) → 여유를 넉넉히 두고, 모자라면 카메라가 먼저
#   돌아올 뿐이다(표시라 무해). 🔴 반대로 `TIME`이나 남은 시간을 여기서 유도하지 마라 —
#   그 금지 이유는 `boss_telegraph.gdshader`의 `progress` 주석이 정본이다.
const WIDE_HOLD_S := 2.4
# 🔴 **신호형 워치독 — 비정상 경로 전용이다.** 정상 최악(횡단 3회 + 지연 보상 ≈ 12.1s)의 1.65배라
#   **정상 경로는 절대 여기 닿지 않는다** = "시간이 아니라 신호로"가 지켜진다. 이 값이 사는 이유는
#   safe 채널이 못 덮는 끊김 경로다: 보스 사망 레이스 · 호스트 이탈 · 스테이지 중 재합류 ·
#   P2P → 릴레이 폴백 순간. ⚠ 그래서 실기 검증에서 **"결국 돌아오더라"로 통과시키지 마라** —
#   20초를 세서 확인해야 진짜 신호 경로가 검증된다.
const WIDE_WATCHDOG_S := 20.0
# 타이머형(spin — 단발 패턴, 종료 신호를 안 보낸다) + 신호형 워치독. 두 역할을 겸한다.
var _wide_left: float = 0.0
# 신호형(횡단 돌진 — `EventBus.boss_wide_view` ← G_BOSS_VIEW). 길이가 회차·지연 보상에 따라
# 가변이라 상수로는 원리적으로 불가능해서 신호로 받는다.
var _wide_signal: bool = false
# 신호형 **워치독 전용** 잔여(s) — 🔴 `_wide_left`(타이머형 spin)와 **반드시 분리**한다.
#   한 칸에 겸하면 종료 신호가 워치독 잔여에 가려져 no-op이 된다(netreview C-1 — `_on_boss_wide_view` 주석).
var _wide_guard: float = 0.0
var _wide_active: bool = false   # 지금 줌아웃 상태인가 — 합성 결과의 **엣지**에서만 트윈한다
var _zoom_tween: Tween = null


func _ready() -> void:
	zoom = Vector2(ZOOM, ZOOM)
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTH_SPEED
	EventBus.combat_impact.connect(_on_impact)
	EventBus.screen_shake.connect(add_shake)
	EventBus.camera_kick.connect(add_kick)
	# 내 무기 적중(공격자 로컬 예측) — 무기 무게감 셰이크. enabled(로컬 카메라)일 때만 흔들린다.
	EventBus.weapon_impact.connect(func(_pos: Vector2, _sfx: String, shake: float) -> void: add_shake(shake))
	# 보스 특정 패턴 = 뒤로 빠져서 맵 전체를 보여준다(위 상수 주석이 근거). 표시 전용.
	EventBus.boss_telegraph.connect(_on_boss_telegraph)
	# 신호형 — 길이가 가변인 패턴(횡단 돌진)은 시작/종료를 **신호로** 받는다. 타이머형과 공존한다.
	EventBus.boss_wide_view.connect(_on_boss_wide_view)
	# 씬 루트가 map_rect 메타를 선언하면 맵 경계로 클램프 — 맵 밖(공허)이 안 보이게.
	# 각 씬은 _ready에서 set_meta("map_rect", Rect2(...)) 한 줄만 선언한다 (복붙 배선 방지).
	# ⚠ current_scene은 못 쓴다 — main의 씬 스왑이 수동 add_child라 항상 부팅 씬(Main)이다.
	#   대신 조상 체인을 올라가며 메타를 찾는다 (플레이어 → 씬 루트 → Main 순).
	var n: Node = get_parent()
	while n != null:
		if n.has_meta("map_rect"):
			set_limits(n.get_meta("map_rect") as Rect2)
			break
		n = n.get_parent()


# 보스 예고 수신 → 지정된 패턴이면 뒤로 뺀다. 그 외 패턴은 **아무 일도 안 한다**(항등).
# ⚠ eid는 안 본다 — 보스가 하나뿐이고, 둘이 되면 "누구의 패턴인가"가 아니라 "이 화면에서
#   보여줄 가치가 있는가"가 기준이라 그때 다시 판단한다.
func _on_boss_telegraph(_eid: String, pattern_id: String, _center: Vector2, _angle: float) -> void:
	if not WIDE_PATTERNS.has(pattern_id):
		return
	# 같은 패턴이 창 안에 또 오면 유지 시간만 갱신한다(줌 트윈을 다시 시작하면 튄다 — `_refresh_wide`의
	# 엣지 게이트가 그것을 구조로 막는다).
	_wide_left = WIDE_HOLD_S
	_refresh_wide()


# 신호형 광역 시야 — 호스트 보스가 패턴 시작/종료를 알린다(G_BOSS_VIEW → EventBus 재emit).
# 🔴🔴 **워치독은 `_wide_left`와 별개 칸이어야 한다**(netreview C-1, 2026-08-02). 설계 §6-6은
#   `_wide_left`가 "타이머형(spin) + 신호형 워치독" 두 역할을 겸하게 했는데 **그 겸용이 종료 신호를
#   통째로 무력화한다**: `on=0`이 와서 `_wide_signal = false`가 돼도 워치독 잔여(10~13초)가
#   `want = _wide_signal or _wide_left > 0.0`을 **참으로 유지**해 엣지가 안 생기고 `_refresh_wide`가
#   그냥 return한다 → 줌은 워치독 20초를 **매번 다 채운다.**
#   🔴 증상이 지독하다 — 메시지는 정상 왕복하고 에러도 없고 화면도 "결국은" 돌아온다. 즉
#   **이 kind가 존재하는 이유(§6 "시간이 아니라 신호로")가 죽었는데 "줌이 좀 오래 유지되네"로만 보인다.**
#   게다가 실기 검증 절차("20초를 세서 신호 경로를 확인한다")를 **깨진 경로도 그대로 통과한다.**
# 🔴 워치독은 **끊김 경로 전용**이다(사망 레이스·호스트 이탈·재합류·릴레이 폴백). safe 채널이라
#   정상 경로엔 유실이 없고, 정상 최악(≈9.7s)의 2배라 여기 닿으면 그 자체가 비정상 신호다.
func _on_boss_wide_view(active: bool) -> void:
	_wide_signal = active
	_wide_guard = WIDE_WATCHDOG_S if active else 0.0
	_refresh_wide()


# 타이머형(spin)과 신호형(횡단)의 **합성** — 둘 중 하나라도 원하면 넓다.
# 🔴 엣지에서만 트윈한다: 매 프레임 `_tween_zoom`을 부르면 트윈이 계속 재시작돼 줌이 굳는다.
func _refresh_wide() -> void:
	var want := _wide_signal or _wide_left > 0.0
	if want == _wide_active:
		return
	_wide_active = want
	_tween_zoom(ZOOM_WIDE if want else ZOOM, ZOOM_OUT_S if want else ZOOM_BACK_S)


# 🔴 **줌 트윈은 하나만 산다** — 이전 것을 죽이지 않으면 되돌아오는 트윈과 나가는 트윈이 겹쳐
#   줌이 진동한다(`hit_flash`·`flinch`가 쓰는 `(prev as Tween).kill()` 관용구와 같은 이유).
func _tween_zoom(target: float, dur: float) -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(self, "zoom", Vector2(target, target), dur)


func _on_impact(kind: String, _world_pos: Vector2, _amount: int, crit: bool) -> void:
	var shake := float(IMPACT_SHAKE.get(kind, 1.0))
	add_shake(shake * CRIT_SHAKE_MULT if crit else shake)  # 치명타는 조금 더 묵직하게(표시 전용)


func add_shake(strength: float) -> void:
	_shake = minf(SHAKE_MAX, _shake + strength)


# 방향성 반동 — dir 방향으로 strength만큼 밀렸다 돌아온다. 셰이크와 독립적으로 쌓인다.
# dir이 0이면 무시(정규화 불가) — 방향 없는 충격은 add_shake 쪽이다.
func add_kick(dir: Vector2, strength: float) -> void:
	if dir.length_squared() < 0.000001 or not (is_finite(dir.x) and is_finite(dir.y)):
		return
	_kick_target = (_kick_target + dir.normalized() * strength).limit_length(KICK_MAX)


# 맵 경계 클램프 — 씬(마을 등)이 스폰 후 호출해 카메라가 맵 밖(공허)을 못 보게 한다.
# 맵이 뷰포트(640×360)보다 큰 씬에서만 의미 있다 — 미호출 시 기본(무제한) 유지.
func set_limits(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


func _process(delta: float) -> void:
	if not enabled:
		return  # 원격 피어 카메라는 흔들 필요 없음(현재 카메라 아님)
	# 보스 패턴 줌아웃 복귀 — 유지 시간이 다하면 원래 줌으로 되돌아온다(추적은 내내 유지됐다).
	# ⚠ `enabled` 가드 **뒤**에 있는 것이 의도다: 원격 피어 카메라는 줌을 만질 필요가 없고,
	#   만지면 그 노드가 현재 카메라가 되는 순간 낯선 줌을 물고 들어온다.
	# 타이머형(spin) 만료 — 🔵 도입 전과 **같은 두 호출**이다(줌아웃 → WIDE_HOLD_S 뒤 ZOOM/ZOOM_BACK_S).
	if _wide_left > 0.0:
		_wide_left -= delta
		if _wide_left <= 0.0:
			_wide_left = 0.0
			_refresh_wide()
	# 신호형 워치독 만료 — **끊김 경로 전용 폴백**. 🔴 `_wide_signal`을 내리는 것은 여기 하나뿐이다
	#   (안 내리면 합성이 계속 true라 안전망 자체가 무의미해진다). 정상 경로는 `on=0`이 먼저 와서
	#   `_wide_guard`를 0으로 만들므로 이 블록에 **도달하지 않는다.**
	if _wide_guard > 0.0:
		_wide_guard -= delta
		if _wide_guard <= 0.0:
			_wide_guard = 0.0
			_wide_signal = false
			_refresh_wide()
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	# 반동: 목표를 0으로 끌어당기면서, 현재 변위는 그 목표를 빠르게 따라간다.
	# (목표를 즉시 offset에 대입하면 한 프레임 점프로 보이고, 감쇠만 쓰면 밀리는 순간이 뭉개진다)
	_kick_target = _kick_target.move_toward(Vector2.ZERO, KICK_DECAY * delta)
	_kick = _kick.lerp(_kick_target, minf(1.0, KICK_SMOOTH * delta))
	var shake_off := Vector2.ZERO
	if _shake > 0.05:
		shake_off = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	var next := shake_off + _kick
	if next.length_squared() < 0.0025:
		next = Vector2.ZERO  # 미세 잔여로 카메라가 영원히 떨리지 않게 스냅
	if offset != next:
		offset = next
