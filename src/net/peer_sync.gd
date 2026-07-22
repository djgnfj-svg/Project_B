extends Node
# 피어/직업 동기화 공용 컴포넌트 — 마을·스테이지가 자식 노드로 문다 (rules §2 리팩터 게이트).
# 책임: 피어당 플레이어 스폰(부모 씬에 add_child)·G_POS 반영·G_JOB 공지/잠금·G_ATK 연출 중계.
# 권한·전투 확정은 여기 없다 — 그건 CombatAuthority(src/stage) 몫.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerScene := preload("res://src/player/player.tscn")
const PlayerActor := preload("res://src/player/player.gd")

@export var scene_id: String = ""  # net_schema SCENE_* 중 하나 — G_POS 씬 필터의 기준
@export var spawn_base: Vector2 = Vector2(280.0, 180.0)
@export var spawn_gap: float = 80.0  # 피어별 가로 간격 (연출값)

var _players: Dictionary = {}  # peer_id -> PlayerActor
var _peer_jobs: Dictionary = {}  # peer_id -> 잠긴 직업 id — "시작 시 선택·이후 고정"(GDD §5) 강제
var _pos_seen: Dictionary = {}  # peer_id -> true — 첫 G_POS 수신 시 재공지 트리거 (공지 유실 경합 복구)


func _ready() -> void:
	EventBus.peer_joined.connect(_on_peer_joined)
	EventBus.peer_left.connect(_on_peer_left)
	EventBus.net_msg.connect(_on_net_msg)
	# ⚠ _ready 시점 부모는 아직 자식 셋업 중 — 여기서 get_parent().add_child 하면
	# "busy setting up children"으로 스폰이 조용히 실패한다 (웹 실기에서 확인) → 한 프레임 미룬다.
	_initial_spawn.call_deferred()


# 원격은 여기서 눈뜨자마자 스폰하지 않는다 — 같은 씬임을 증명하는 첫 G_POS 수신에서만 스폰.
# (다른 씬에 있는 피어를 즉시 스폰하면 pos를 영영 못 받는 유령 아바타가 된다 — 재접속/전환 창 케이스)
func _initial_spawn() -> void:
	_spawn(Net.my_id, true)
	_announce_job()


# CombatAuthority 등 형제 컴포넌트용 조회 (없으면 null)
func player(peer_id: int) -> PlayerActor:
	return _players.get(peer_id) as PlayerActor


func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)


func _spawn(peer_id: int, is_local: bool) -> void:
	if peer_id == 0 or _players.has(peer_id):
		return
	var p := PlayerScene.instantiate() as PlayerActor
	get_parent().add_child(p)
	# 스폰 슬롯 = 방 내 순번(현재 인원). peer_id 기반이면 재접속마다 id가 증가해
	# (릴레이는 id 재사용 안 함) 몇 번 새로고침이면 뷰포트 밖에서 스폰된다.
	# 클라이언트마다 순번이 달라도 무해 — 원격 위치는 첫 G_POS 수신에서 실좌표로 스냅된다.
	p.setup(peer_id, is_local, spawn_base + Vector2(spawn_gap * float(_players.size()), 0.0), scene_id)
	if is_local:
		p.set_job(GameState.selected_job())
	else:
		# 스폰 전에 도착해 쌓인 공지 반영 — 없으면 기본(전사)으로 두고 G_JOB 수신 시 확정
		var jid := str(_peer_jobs.get(peer_id, ""))
		if not jid.is_empty():
			p.set_job(GameState.job_def(jid))
	_players[peer_id] = p


# 직업 공지 — 내 직업 id를 방 전원에 브로드캐스트.
# 씬 입장 시 1회 + 새 피어 합류 시 재공지(늦게 온 피어도 기존 피어 직업을 알게).
func _announce_job() -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_JOB, "job": GameState.selected_job_id})


func _on_peer_joined(_peer_id: int) -> void:
	_announce_job()  # 스폰은 안 한다 — 상대의 첫 G_POS(씬 일치)가 스폰 트리거


func _on_peer_left(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)
	_peer_jobs.erase(peer_id)  # 같은 id로 새 피어가 들어와도 이전 잠금이 남지 않게
	_pos_seen.erase(peer_id)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_POS:
			if str(data.get("s", "")) != scene_id:
				return  # 다른 씬의 피어 (전환 창·재접속 대기) — 유령 스폰/좌표 오염 방지
			if not _players.has(from_id):
				_spawn(from_id, false)  # 첫 G_POS = 같은 씬 증명 — 여기가 원격 스폰의 유일한 입구
				if not _players.has(from_id):
					return  # 스폰 거부(peer_id 0 등) — 인덱싱 에러 방지
			_players[from_id].apply_remote_pos(
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
				bool(data.get("f", false)),
				float(data.get("a", 0.0)))
			if not _pos_seen.has(from_id):
				# 첫 G_POS = 상대가 같은 씬에서 듣고 있다는 증명 — 씬 전환 중 드랍된 공지를 재전송
				_pos_seen[from_id] = true
				_announce_job()
		NetSchema.G_JOB:
			if _peer_jobs.has(from_id):
				return  # 첫 공지에서 잠금 — 판 도중 직업 변경(스탯 취사선택 이득)은 무시 (GDD §5)
			# 신뢰 경계(rules §3): id 문자열만 받고 수치는 내 data/jobs에서 리졸브.
			# 모르는 id는 GameState가 기본 직업으로 떨어뜨린다. 이후 사거리·쿨다운 검증이 이 job 기준.
			# 아직 스폰 전이면 기록만 — _spawn이 반영한다 (G_JOB은 씬 무관 전역 공지라 스폰 트리거 아님).
			_peer_jobs[from_id] = str(data.get("job", ""))
			if _players.has(from_id):
				_players[from_id].set_job(GameState.job_def(str(data.get("job", ""))))
		NetSchema.G_ATK:
			if _players.has(from_id):
				var dir := Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0)))
				_players[from_id].play_attack_fx(dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT)
		NetSchema.G_ROLL:
			# 구르기 연출 중계 — 표시 전용. i-frame 판정은 CombatAuthority(호스트 그랜트)가 별도로 한다.
			if _players.has(from_id):
				_players[from_id].play_roll_fx(
					Vector2(float(data.get("dx", 0.0)), float(data.get("dy", 0.0))))
