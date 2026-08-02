extends Node
# 보스방 진입 게이트 — 복도를 걸어 들어와 아레나에 발을 들이면 **출입구가 낙석으로 막히고**
# 그때서야 보스가 깨어난다. 확정 권한 = 호스트 (rules §1·§3).
# 설계 정본 = docs/plans/active/2026-08-02-boss-gate.md
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).
#
# 🔵 **신규 네트워크 kind 0개.** 게스트가 알아야 하는 것은 「지형이 생겼다」 하나뿐이라
#   (보스 AI·코옵 카운트다운이 **둘 다 호스트 전용**이다) 기존 `EventBus.rock_spawn_local`
#   → `RockField` → `G_ROCK` 경로에 **페이로드 형식 그대로** 얹는다. stage_token 가드 ·
#   `from_id == HOST_ID` 검증 · 신뢰 채널 · 중복 스폰 가드가 전부 공짜로 따라온다.
#
# 🔴 **왜 Area2D가 아니라 좌표 임계인가** (설계 §2): Area2D는 각 클라의 로컬 물리 몸에서
#   발화하므로 ⑴ 게스트가 로컬로 상태를 확정하게 되거나(§1 위반) ⑵ 호스트가 가진 게스트 몸은
#   **보간된 표시 아바타**라 판정이 `net_anchor()`가 아닌 좌표계에서 난다. 좌표 임계는 호스트의
#   다른 모든 판정과 **같은 소스**를 쓴다.

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerActor := preload("res://src/player/player.gd")
const BossActor := preload("res://src/enemies/boss.gd")
const CoopAuthorityNode := preload("res://src/stage/coop_authority.gd")

# 게이트 바위 rid 접두 — 보스 낙석(P4)은 `"<eid>:rock:<seq>"`라 충돌하지 않는다.
# 🔴 게스트가 「이 G_ROCK이 게이트인가」를 가르는 유일한 키다. 바꾸면 게스트 화면만 안 흔들린다.
const GATE_RID_PREFIX := "gate:"
# 🔴 ttl 0 = 영구 (`boss_rock.gd`가 `ttl <= 0`을 안 지운다). 낙석은 10초라 항등.
const GATE_TTL := 0.0
# 연출값 (rules §0 예외 — 사용자가 조인다, docs/TUNING.md 대상). SHAKE_MAX(4.67) 안쪽.
const GATE_SHAKE := 3.2

# 🔧 아래 기하는 전부 `scripts/gen_stage.py`가 소유한다 — 복도(BOSS 스펙의 `open` 사각)에서
#   **재서** 씬에 찍는다. 씬이나 여기 기본값을 손으로 고치지 마라(생성기를 다시 돌리면 덮인다).
#   기본값은 "게이트 없음"에 가깝게 두어, 배선이 빠진 씬에서 조용히 막히지 않게 한다.
@export var boss_path: NodePath
@export var coop_path: NodePath
@export var trigger_x: float = 0.0    # 이 x를 **생존 피어 전원**이 넘으면 닫힌다
@export var gate_x: float = 0.0       # 바위 중심 x (복도 안)
@export var gate_y0: float = 0.0      # 복도 단면 위쪽 (첫 바위 중심)
@export var gate_y1: float = 0.0      # 복도 단면 아래쪽 (마지막 바위 중심)
@export var gate_count: int = 0       # 바위 개수 (≥2)
@export var gate_radius: float = 24.0 # 바위 콜리전 반경 — `boss_rock.tscn`과 미러(생성기가 읽어 찍는다)

var _closed: bool = false   # 한 번 닫히면 재무장 없음 (씬이 새로 태어나면 자동 초기화 — 설계 §9)
# 피어 대기 경고 주기(s) — 매 프레임 찍으면 콘솔이 묻힌다. 값은 연출·진단용(rules §0 예외).
const WAIT_WARN_PERIOD_S := 5.0
var _wait_warn_left: float = WAIT_WARN_PERIOD_S


func _ready() -> void:
	EventBus.net_msg.connect(_on_net_msg)
	# 🔴 배선이 성립하는지 **여기서 한 번** 시끄럽게 확인한다 — 안 하면 "게이트가 조용히 안 닫힌다"가
	#   되고 화면에 이유가 안 드러난다(이 프로젝트가 가장 비싸게 값을 치른 결함 모양).
	var ok := true
	if _boss() == null:
		push_warning("boss_gate: boss_path 미해결 — 게이트가 영원히 안 닫힌다")
		ok = false
	if gate_count < 2 or trigger_x <= gate_x:
		push_warning("boss_gate: 기하 미설정(count=%d trigger_x=%.0f gate_x=%.0f) — gen_stage.py를 돌려라"
			% [gate_count, trigger_x, gate_x])
		ok = false
	# 🔴 **배선이 성립할 때만 재운다**(netreview m-1). 무조건 재우면 배선이 빠진 씬에서 `_physics_process`가
	#   조기 반환하므로 **보스가 영구 정지 + 코옵 영구 해제로 굳고**, 신호는 위 `push_warning` 두 줄뿐이다
	#   (웹 콘솔에서 잘 안 읽힌다). 건너뛰면 실패 시 동작이 **도입 전과 항등**(보스가 그냥 깨어 있음)으로
	#   떨어진다 = 폐기 방향이 관대한 쪽(§3 「오차는 정직한 플레이어가 살아남는 쪽으로 기울인다」).
	if ok:
		_set_dormant(true)


# 보스방에 **들어서기 전까지** 보스와 코옵 파훼를 함께 재운다.
# 🔴 코옵을 빠뜨리면 조용히 죽는다 — `CoopAuthority.FIRST_DELAY_S`(3.0s)가 복도 도보 시간(4.8s)보다
#   짧아서, 복도 한가운데서 「별의 낙하」가 터지고 안전지대가 아레나 안에 찍히면 **즉사**한다.
# ⚠ 두 플래그 모두 **기본값이 도입 전과 항등**이라(보스 false · 코옵 true) BossGate가 없는 씬
#   (시험장·테스트 랩)은 한 픽셀도 안 바뀐다.
func _set_dormant(on: bool) -> void:
	var boss := _boss()
	if boss != null:
		boss.gate_dormant = on
	var coop := get_node_or_null(coop_path) as CoopAuthorityNode
	if coop != null:
		coop.armed = not on


func _boss() -> BossActor:
	# 🔴 그룹 스캔을 하지 않는다 — NodePath 익스포트라 씬 스왑 유령이 박힐 경로가 **원리적으로 없다**
	#   (rules §5, 2026-08-01 스테이지2 결함). `peer_sync_path`·`drop_authority_path` 관용구.
	return get_node_or_null(boss_path) as BossActor


func _physics_process(_delta: float) -> void:
	if _closed or not Net.is_host():
		return
	if gate_count < 2 or trigger_x <= gate_x:
		return  # 기하 미설정 — 조용히 아무것도 안 한다(경고는 _ready에서 이미 냈다)
	if not _all_alive_past_line():
		return
	_close()


# 생존 피어 **전원**이 트리거선을 넘었는가 (호스트 판정).
# 🔴 "한 명이라도"가 아니다 — 한 명으로 닫으면 복도에 남은 파트너가 벽 반대편에 갇힌다.
# 🔴 좌표는 `net_anchor()`(호스트가 확정에 쓰는 그 좌표)다. 낡은 좌표라 실제 위치는 더 동쪽일
#   가능성이 높으므로 **"덜 닫히는" 쪽으로 틀린다** = 안전한 방향. 그래서 트리거선과 게이트 사이에
#   `LAG_MAX_LEAD_DIST`(115) 이상의 여유를 두면 닫히는 순간 게이트 위에 선 피어가 없다
#   (그 부등식은 `gen_stage.py verify_boss`가 트립와이어로 잠근다).
func _all_alive_past_line() -> bool:
	var alive := 0
	var present := 0   # 몸이 이 씬에 **도착한** 피어 수 (생존 여부와 별개로 센다)
	for node: Node in get_tree().get_nodes_in_group("player"):
		# 🔴 자기 씬 하위만 — 씬 스왑 프레임에 이전 씬 플레이어가 걸리면 **복도에 들어서기도 전에**
		#   게이트가 닫힌다(이전 칸의 x가 트리거선보다 동쪽일 수 있다). rules §5.
		if not get_parent().is_ancestor_of(node):
			continue
		var p := node as PlayerActor
		if p == null:
			continue
		present += 1
		if not p.is_alive():
			continue
		alive += 1
		if p.net_anchor().x < trigger_x:
			return false
	# 🔴🔴 **방 전원의 몸이 이 씬에 도착했는가** (netreview C-1). 원격 아바타는 씬 로드 때 안 생기고
	#   **첫 `G_POS` 수신에서만** 스폰된다(`peer_sync`: *"여기가 원격 스폰의 유일한 입구"*). 그래서
	#   씬 스왑 직후 창에는 호스트의 "player" 그룹에 **자기 몸 하나뿐**이고, `alive >= 1`만 보면
	#   **호스트가 혼자 게이트를 닫는다.** 그 결과가 둘인데 **둘 다 에러가 없다**:
	#     ⒜ 게스트가 아직 스왑 중이면 그 `G_ROCK`을 **영영 못 받는다**(옛 씬은 stage_token 불일치로
	#        폐기, 새 씬 `RockField`는 아직 `net_msg`에 안 붙었다) = **게스트 화면에만 게이트가 없다.**
	#     ⒝ 게스트가 막 도착했으면 **복도에 갇힌다.** ttl 0(영구) + 재무장 없음 = **영구 소프트락**이고,
	#        코옵은 생존 2인이면 발동하므로 안전지대가 아레나 안에 찍혀 **도달 불가 → 즉사 → 전멸.**
	#   ⚠ 호스트 화면에서는 완벽하게 동작한다 — **게스트만·배포본만·느린 기기만**(로컬은 즉시 로드).
	# `Net.peer_ids`는 **나를 뺀** 방 피어라 `present > size()`가 곧 "나 포함 총원 도착"이다.
	#   피어가 끊기면 `peer_ids`와 아바타가 **같은 신호(peer_left)에서 함께** 줄어 좀비 잔류가 없다.
	if present <= Net.peer_ids.size():
		_wait_warn_left -= get_physics_process_delta_time()
		if _wait_warn_left <= 0.0:
			_wait_warn_left = WAIT_WARN_PERIOD_S
			# ⚠ **"안 닫힌다"도 화면에 이유가 안 드러나는 축**이라 로그를 남긴다. 조용한 파티 분단보다
			#   시끄러운 정지가 낫지만, 그 정지의 이유는 어딘가에 적혀 있어야 한다.
			push_warning("[BossGate] 피어 대기 — 도착 %d / 총원 %d (아직 안 온 피어의 첫 G_POS를 기다린다)"
				% [present, Net.peer_ids.size() + 1])
		return false
	return alive >= 1   # 아무도 없으면(스폰 전·전멸) 안 닫는다


# 호스트 확정 — 게이트 지형 스폰 + 보스/코옵 각성.
func _close() -> void:
	if _closed:
		return
	_closed = true
	# 🔴 `Net.send_game`을 직접 부르지 않는다 — 호스트 루프백이 없어 자기 화면만 안 바뀐다.
	#   `RockField`가 로컬 스폰 + G_ROCK 브로드캐스트를 **함께** 한다(낙석 P4와 같은 배선).
	EventBus.rock_spawn_local.emit(_gate_rocks())
	_apply_closed()


# 게이트 바위 목록 — `G_ROCK "rk"` 튜플 형식 그대로 `[rid, x, y, r, ttl]` (필드 추가 0개).
# 간격·개수는 씬에 찍힌 값에서 유도한다(생성기가 복도 단면을 재서 넣은 값).
func _gate_rocks() -> Array:
	var rocks: Array = []
	var step := (gate_y1 - gate_y0) / float(maxi(1, gate_count - 1))
	for i: int in gate_count:
		rocks.append(["%s%d" % [GATE_RID_PREFIX, i], gate_x, gate_y0 + step * float(i),
			gate_radius, GATE_TTL])
	return rocks


# 닫힘이 확정된 뒤의 로컬 반영 — 호스트는 `_close`에서, 게스트는 G_ROCK 관찰에서.
# 🔴 표시·게이트 해제만 한다. **바위 스폰은 여기서 안 한다** — 그건 `RockField`의 몫이고,
#   두 곳에서 스폰하면 중복 가드에 기대는 배선이 된다.
func _apply_closed() -> void:
	_set_dormant(false)
	EventBus.screen_shake.emit(GATE_SHAKE)  # 표시 전용 (rules §2 손맛 계층 — 네트워크 0)


# 게스트: 게이트 낙석이 도착한 것을 **관찰만** 한다(상태 확정 아님 — 스폰은 RockField).
# 가드 셋은 `rock_field.gd`와 **같은 형태**로 맞춰 둔다(사본을 만들지 말고 모양을 맞춘다).
func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if _closed or Net.is_host():
		return
	if str(data.get(NetSchema.KEY_KIND, "")) != NetSchema.G_ROCK:
		return
	if from_id != NetSchema.HOST_ID:
		return
	if str(data.get("s", "")) != GameState.stage_token():
		return
	for entry: Variant in (data.get("rk", []) as Array):
		if not (entry is Array) or (entry as Array).size() < 1:
			continue
		if str((entry as Array)[0]).begins_with(GATE_RID_PREFIX):
			_closed = true
			_apply_closed()
			return
