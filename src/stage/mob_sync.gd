extends Node
# 잔몹 표시 동기화 전담 컴포넌트 — 호스트: mpos(10Hz 배치)·matk 브로드캐스트, 게스트: 수신 반영.
# 권한·판정은 여기 없다(그건 CombatAuthority) — rules §2 책임 분리. 스테이지가 자식 노드로 문다.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")

const SEND_RATE := 10.0  # Hz — 배치 1건으로 묶어 릴레이 메시지 2KB 상한·빈도 부담 완화 (rules §2)

var _mobs: Dictionary = {}  # eid -> mob (그룹 "mob" 씬 배치 스캔 — 동적 스폰 없음)
var _send_accum: float = 0.0
# 🔴 배치 시퀀스 — G_POS의 `n`과 **같은 목적·같은 판정 함수**(CombatMath.is_pos_seq_fresh).
#   G_MOB_POS는 `Net.RTC_FAST_KINDS`라 P2P 직결에서 **unordered**다. 뒤바뀐 배치를 적용하면
#   게스트의 `_remote_target`이 송신 주기 하나만큼(100ms) **과거로 되돌아가고**, 그 좌표는
#   표시로 안 끝난다 — `player.gd`가 `intersect_shape` 결과의 `global_position`을
#   `is_melee_in_cone`에 넣으므로 **게스트의 로컬 근접 질의가 낡은 자리로 각을 잰다.**
#   증상은 "스윙·궤적·소리는 다 나는데 적 HP만 안 깎인다" = §3 「각 축 지연 보상」 결함과
#   **구분되지 않아 서로를 가린다.** ⚠ 직결에서만·게스트에서만 난다(릴레이는 TCP라 구조적으로
#   불가능) → `dev_local.sh`로도 배포 릴레이로도 재현이 안 되고 **P2P가 붙은 배포본에서만** 드러난다.
# ⚠ 씬 컴포넌트라 씬마다 새로 태어난다 = 씬 전환 시 리셋이 공짜다(peer_sync `_melee_combo`와 같다).
var _mpos_seq: int = 0        # 호스트: 다음 배치에 실을 번호
var _last_mpos_seq: int = 0   # 게스트: 마지막으로 적용한 번호
# 씬 에폭 판정 문턱 — 번호가 이보다 크게 **뒤로** 점프하면 "새 씬이 1부터 다시 센다"로 본다.
# 🔴 진짜 순서 뒤바뀜과 구별되어야 하므로 그 최대 거리보다 넉넉히 커야 한다: fast 채널 패킷은
#   `Net.RTC_FAST_LIFETIME_MS`(60ms)를 넘기면 폐기되고 송신 간격이 100ms(SEND_RATE 10Hz)라
#   **재전송으로 뒤바뀔 수 있는 거리가 1을 못 넘는다.** 10이면 1초분 = 두 자릿수 여유다.
# ⚠ `SEND_RATE`를 올리면 이 여유가 줄어든다 — 부등식은 `test_net_transport_auto`가 지킨다.
const EPOCH_GAP := 10


func _ready() -> void:
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.mob_telegraph.connect(_on_mob_telegraph)
	EventBus.mob_shoot.connect(_on_mob_shoot)
	EventBus.boss_telegraph.connect(_on_boss_telegraph)
	EventBus.boss_spray.connect(_on_boss_spray)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	EventBus.boss_wide_view.connect(_on_boss_wide_view)
	# 🔴 **자기 씬 하위만 등록한다** — combat_authority._ready와 같은 이유이고, 여기 피해는
	#   네트워크로 나간다: 씬 스왑 프레임의 유령이 박히면 다음 프레임부터 아래 `_physics_process`의
	#   `_mobs[eid] as Node2D`가 **캐스트에서** 터져(`Trying to cast a freed object`) 함수가 중단되고,
	#   그러면 `G_MOB_POS`가 **한 통도 안 나가** 게스트 화면의 잔몹이 통째로 얼어붙는다
	#   (초당 60회 에러 · 2026-08-01 "스테이지2에서 멈춘다" 신고의 게스트 쪽 증상).
	#   ⚠ 아래 루프의 `mob == null` 가드는 이걸 못 막는다 — **캐스트가 먼저 터진다.**
	# 🔴 **기준은 `owner`(그 .tscn의 루트)다** — combat_authority._ready와 같은 이유. `get_parent()`는
	#   컴포넌트를 한 겹만 감싸도 껍데기를 반환해 **자기 씬 잔몹이 하나도 안 통과한다**(조용한 전면
	#   무등록 = `G_MOB_POS` 0통 = 방금 고친 그 증상인데 SCRIPT ERROR조차 없다 · netreview 2026-08-01).
	var scene_root: Node = owner if owner != null else get_parent()
	var passed := 0
	for m: Node in get_tree().get_nodes_in_group("mob"):
		if scene_root == null or not scene_root.is_ancestor_of(m):
			continue
		passed += 1
		var eid_v: Variant = m.get("eid")
		if eid_v is String and not str(eid_v).is_empty():
			_mobs[str(eid_v)] = m
	# 전면 무등록 진단 — 화면에는 "게스트 잔몹이 안 움직인다"로만 나타나므로 에러를 코드로 박아 둔다.
	if scene_root != null:
		var under := _count_in_group_under(scene_root, &"mob")
		if passed < under:
			push_error("[MobSync] 씬 하위 잔몹 %d마리 중 %d마리만 등록됐다 — 씬 스캔 필터가 자기 씬을 떨어뜨린다(scene_root=%s)"
				% [under, passed, scene_root.name])


# 씬 하위의 그룹 소속 노드 수 — 위 진단 전용. `_ready` 1회라 재귀 비용은 무시할 수준.
func _count_in_group_under(n: Node, group: StringName) -> int:
	var c := 1 if n.is_in_group(group) else 0
	for ch: Node in n.get_children():
		c += _count_in_group_under(ch, group)
	return c


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_send_accum += delta
	if _send_accum < 1.0 / SEND_RATE:
		return
	_send_accum = 0.0
	var batch: Array = []
	for eid: String in _mobs:
		var mob := _mobs[eid] as Node2D
		if mob == null or not mob.visible:
			continue  # 사망(숨김) 잔몹 제외 — 사망 전파는 ehp가 담당
		batch.append(mob.call("get_sync_state"))
	if not batch.is_empty():
		# 🔴 번호는 **보내는 배치마다** 오른다 — 빈 배치를 건너뛰는 위 가드 때문에 번호에 구멍이
		#   생기지만, 수신 판정이 `>`(단조 증가)라 구멍은 무해하다. 반대로 여기서 올리지 않으면
		#   같은 번호가 두 번 나가 뒤 배치가 통째로 폐기된다.
		_mpos_seq += 1
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_MOB_POS, "n": _mpos_seq, "m": batch})


# 호스트 전용 수신 경로 — 잔몹 AI가 알린 텔레그래프를 전원에 중계 (게스트는 emit하지 않는다)
func _on_mob_telegraph(eid: String, center: Vector2) -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_MOB_ATK, "eid": eid, "x": center.x, "y": center.y})


# 호스트 전용 수신 경로 — 원거리 잔몹의 발사를 전원에 중계 (matk 규약 확장, 2026-08-01).
# 🔴 **게스트도 같은 시그널을 로컬 emit한다**(아래 G_MOB_SHOOT 수신 → mob.play_shoot → mob_shoot).
#   그 재emit이 여기로 되돌아와 무한 중계가 되지 않도록 호스트 가드가 **필수**다 — `_on_boss_telegraph`가
#   방어적으로 달아 둔 같은 가드가 여기서는 실제로 동작에 필요하다.
# 🔴 **수치는 하나도 싣지 않는다** — eid만 보내면 각 클라가 자기 씬의 EnemyDef에서 속도·사거리·
#   판정 반경·텍스처를 리졸브한다(`peer_weapon_id`·`projectile_params` 철학, rules §3).
#   그래서 스푸핑 표면이 0이고 "맞는 곳 = 보이는 곳"이 구조로 유지된다.
# ⚠ 채널: 이 kind는 **사건**이라 유실 허용(fast)에 넣으면 안 된다 — 한 통이 사라지면 게스트 화면에
#   화살 없이 데미지만 들어온다. `RTC_FAST_KINDS`는 allowlist라 기본이 safe다(rules §3 채널 분류).
func _on_mob_shoot(eid: String, origin: Vector2, dir: Vector2, aid: String, _def: EnemyDef) -> void:
	if not Net.is_host():
		return
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_MOB_SHOOT, "eid": eid,
		"ox": origin.x, "oy": origin.y, "dx": dir.x, "dy": dir.y, "aid": aid})


# 호스트 전용 수신 경로 — 보스 AI가 알린 패턴 텔레그래프를 전원에 중계 (matk 규약 확장, 표시 전용)
func _on_boss_telegraph(eid: String, pattern_id: String, center: Vector2, angle: float) -> void:
	if not Net.is_host():
		return  # 방어적 — 보스 AI는 호스트만 emit하지만, 게스트 발신 시 릴레이 낭비 차단 (게스트 위조는 수신부 HOST_ID 검증이 이미 거부)
	# 🔴 돌진 **회차 인덱스**는 시그널 인자에 없다 — 배우에게 직접 묻는다(`get_sync_state`·
	#   `show_telegraph`와 같은 덕타이핑 API). `boss_telegraph` emit이 **동기**라 이 시점의 값이
	#   곧 그 예고의 회차다. 없으면 0 = 회차 단축 없음 = 도입 전과 항등.
	# ⚠ **수치(단축 배율)는 안 싣는다** — 각 클라가 `CombatMath.charge_telegraph_scale`로 자기
	#   `.tres`에서 리졸브한다(`peer_weapon_id`·`projectile_params`와 같은 철학, rules §3).
	var idx := 0
	var actor: Node = _mobs.get(eid)
	if actor != null and actor.has_method("charge_telegraph_idx"):
		idx = int(actor.call("charge_telegraph_idx"))
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_ATK,
		"eid": eid, "p": pattern_id, "x": center.x, "y": center.y, "a": angle, "i": idx})


# 호스트 전용 — 보스 물뿌리기 착탄점들을 전원에 중계(표시 전용). 게스트가 N개 원 텔레그래프 렌더.
# Vector2는 JSON 왕복이 안 되므로 [[x,y], …] 평면 배열로 직렬화 (G_SWAMP/G_DROP 규약 미러).
func _on_boss_spray(eid: String, pattern_id: String, centers: Array, _angle: float) -> void:
	if not Net.is_host():
		return
	var arr: Array = []
	for c: Variant in centers:
		var v := c as Vector2
		arr.append([v.x, v.y])
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_SPRAY, "eid": eid, "p": pattern_id, "c": arr})


# 호스트 전용 — 보스 페이즈 전이를 전원에 중계(표시 큐). 정본 판정은 호스트 hp — 이건 배너 동기화일 뿐.
func _on_boss_phase_changed(phase: int) -> void:
	if not Net.is_host():
		return
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_PHASE, "ph": phase})


# 호스트 전용 — 보스 패턴의 광역 시야 on/off를 전원에 중계(표시 전용·판정 0). `boss_phase_changed` 미러.
# 🔴 **게스트 가드가 필수다** — 아래 수신부가 로컬 `boss_wide_view`를 재emit하고 그것이 이
#   핸들러로 되돌아온다. 가드가 없으면 무한 중계다(`_on_mob_shoot`이 같은 이유로 달고 있다).
# 🔴🔴 **이 kind를 `RTC_FAST_KINDS`에 넣지 마라** — 종료는 "다음 패킷이 곧 덮어쓰는 것"이 아니라
#   **사건**이라 한 통 유실이면 **카메라가 영영 안 돌아온다**(줌아웃에 갇힌다). 그 집합은
#   allowlist라 아무것도 안 하면 safe이고, 넣으면 `test_net_transport_auto`가 빨개진다.
func _on_boss_wide_view(active: bool) -> void:
	if not Net.is_host():
		return
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_BOSS_VIEW, "on": 1 if active else 0})


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if Net.is_host() or from_id != NetSchema.HOST_ID:
		return  # 잔몹 상태는 호스트 발신만 신뢰 (rules §3). 미등록 eid = 자연 드랍
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_MOB_POS:
			# 🔴 순서 가드 — 판정은 `CombatMath.is_pos_seq_fresh`를 **G_POS와 공유**한다(사본 금지:
			#   한쪽만 고치면 두 위치 스트림의 신선도 규칙이 갈라진다). 미부착(0)은 항등 통과라
			#   구버전 호스트·릴레이 경로와 완전히 같은 동작이다. 상세 = 위 `_mpos_seq` 주석.
			var mseq := int(data.get("n", 0))
			# 🔴🔴 **씬 에폭 리셋 — 이 가드가 없으면 결함이 「일시」에서 「사실상 영구」로 커진다**
			#   (netreview 2026-08-02 I-1). 이 노드는 씬마다 새로 태어나 `_last`가 0이지만,
			#   **직전 씬의 배치가 지연 도착하면** 그 큰 번호(수천)가 0을 이겨 그대로 박힌다.
			#   새 씬 호스트는 1부터 세므로 **이후 전량 폐기** = 번호/10초, 즉 직전 씬에 5분
			#   머물렀으면 **약 300초 동안 게스트 잔몹이 스폰 지점에 얼어붙는다.** 에러 0.
			#   ⚠ 도입 전에는 같은 패킷이 낡은 좌표를 **한 번** 쓰고 다음 배치가 덮었다(자기 치유)
			#     — 즉 순서 가드는 이 한 방향으로만 피해를 **키운다.** 그래서 짝으로 넣는다.
			#   🔴 지금 이게 안 터지는 이유는 **둘 다 우연이고 계약이 아니다**: ⑴ 마을엔 MobSync가
			#     없다 ⑵ stage→stage 전환은 클리어 뒤라 몹이 전부 `visible=false` → 배치가 빈 채로
			#     `NEXT_DELAY_S`(3초)를 보낸다. **동적 스폰(웨이브)이나 클리어 없는 전환이 생기면
			#     그 즉시 실체화한다** — rules §2 「적 동적 스폰」 게이트와 같은 자리다.
			#   ⚠ G_POS는 이 문제가 **구조적으로** 없다 — `peer_sync`가 씬 id(`"s"`)를 먼저 보고
			#     다른 씬이면 `_last_pos_seq`를 **건드리기 전에** return한다. 함수를 공유한 것과
			#     안전성을 공유한 것은 다르다. 여기선 배치에 씬 토큰이 없어 **뒤로 큰 점프 = 새 에폭**
			#     으로 판정한다(재합류·미래 동적 스폰까지 같이 덮는 값싼 처방).
			if mseq > 0 and mseq < _last_mpos_seq - EPOCH_GAP:
				_last_mpos_seq = 0
			if CombatMath.is_pos_seq_fresh(mseq, _last_mpos_seq):
				# ⚠ 갱신은 **fresh일 때만** 한다 — 무조건 `maxi`로 바꾸면 게스트가 아직 이전 씬에
				#   있을 때 도착한 새 씬 배치(작은 번호)는 무해하지만, 위 에폭 판정이 볼 「뒤로 점프」
				#   자체가 사라져 I-1 처방이 무력해진다. 관용구는 `player.gd`의 G_POS 쪽과 맞춘다.
				if mseq > 0:
					_last_mpos_seq = mseq
				for entry: Variant in (data.get("m", []) as Array):
					if not (entry is Array) or (entry as Array).size() < 4:
						continue
					var arr := entry as Array
					var mob: Node = _mobs.get(str(arr[0]))
					if mob != null:
						mob.call("apply_remote_pos",
							Vector2(float(arr[1]), float(arr[2])), bool(arr[3]))
		NetSchema.G_MOB_ATK:
			var mob: Node = _mobs.get(str(data.get("eid", "")))
			if mob != null:
				# ⚠ 원거리 개체는 같은 호출을 **활 당김 모션**으로 해석한다(그 배우가 자기 def를 본다)
				#   — 신규 kind 0개. 여기서 분기하지 마라: 갈래가 둘이 되는 순간 "메시지는 왔는데
				#   한쪽만 해석한다"가 태어난다.
				mob.call("show_telegraph",
					Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))))
		NetSchema.G_MOB_SHOOT:
			# 원거리 잔몹 발사 — 배우가 놓는 프레임으로 넘어가고 로컬 mob_shoot을 emit해
			# ArrowField가 표시 탄을 띄운다. 판정용 화살은 호스트가 이미 등록해 뒀다(CombatAuthority).
			# ⚠ 방향은 여기 실린 dx/dy가 정본이다 — G_MOB_ATK에서 유도한 자세각은 근사일 뿐이다.
			var shooter: Node = _mobs.get(str(data.get("eid", "")))
			if shooter != null:
				shooter.call("play_shoot",
					Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0))),
					Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0))),
					str(data.get("aid", "")))
		NetSchema.G_BOSS_ATK:
			var boss: Node = _mobs.get(str(data.get("eid", "")))
			if boss != null:
				# ⚠ "i"(돌진 회차) 없음 = 0 = **구버전 호스트와 항등**(회차 단축 없음).
				boss.call("show_boss_telegraph", str(data.get("p", "")),
					Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
					float(data.get("a", 0.0)), int(data.get("i", 0)))
		NetSchema.G_BOSS_SPRAY:
			# 착탄점 [[x,y], …] → Vector2 배열 복원 후 boss_spray 로컬 emit(보스 렌더러가 N개 원 그림)
			var centers: Array = []
			for e: Variant in (data.get("c", []) as Array):
				if e is Array and (e as Array).size() >= 2:
					var a := e as Array
					centers.append(Vector2(float(a[0]), float(a[1])))
			EventBus.boss_spray.emit(str(data.get("eid", "")), str(data.get("p", "")), centers, 0.0)
		NetSchema.G_BOSS_PHASE:
			EventBus.boss_phase_changed.emit(int(data.get("ph", 1)))  # HUD 배너(표시 큐)
		NetSchema.G_BOSS_VIEW:
			# 광역 시야 on/off — 로컬 재emit(`boss_phase_changed` 미러). camera_rig가 구독한다.
			# 🔵 판정에 아무것도 안 한다: 최악의 오용도 "화면이 넓어진다"뿐이라 신뢰 표면이 실질
			#   0이고, 그래서 페이로드를 `on` 하나로 좁혔다(eid·패턴 id를 안 싣는다).
			EventBus.boss_wide_view.emit(int(data.get("on", 0)) != 0)
