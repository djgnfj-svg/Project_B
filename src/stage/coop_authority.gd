extends Node
# 코옵 파훼 기믹 컨트롤러 — 여러 패턴을 순서대로 순환 발동한다.
# 각 패턴은 3·2·1 카운트다운(이름·설명) 후 발동. 판정 권한 = 호스트 (rules §1·§3).
# 게스트는 입력을 호스트에 보내고 결과를 받는다. 보스 엔진 무접촉·독립 병렬 구동. ⚠ 씬 전용 글루 (rules §5).
#
# 판정 모델: 조기 성공 없음 — 제한시간 끝까지 조건을 유지해야 한다. 만료 순간에만 판정,
#   조건 미충족자 위로 메테오 낙하 → 즉사(FAIL_DAMAGE). 전원 충족 시 성공(메테오 없음).
# 패턴 종류:
#  · CAGE(소울 케이지): 한 명 속박+발밑 즉사 장판 → 파트너가 근접 WASD로 풀어야 산다(늦으면 피해자에 메테오).
#  · REACH/SCATTER/HUDDLE(위치): 초록 안전지대 안에서 만료까지 버텨라 — 밖이면 메테오.
#  · SOLVE(직면/봉인진): 전원 각자 WASD 키패드를 시간 내 완료 — 미완료자에 메테오. (직면=1키, 봉인진=4키)

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerActor := preload("res://src/player/player.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")

const FAIL_DAMAGE := 9999
const FIRST_DELAY_S := 3.0
const INTERVAL_S := 10.0
const RESCUE_RADIUS := 44.0

const KEYS: Array[int] = [KEY_W, KEY_A, KEY_S, KEY_D]
const SYMS: Array[String] = ["W", "A", "S", "D"]
const MARKER_TEX := preload("res://assets/sprites/fx/coop_marker.png")  # 안전지대 레티클(흰 베이스→틴트)
const STAR_TEX := preload("res://assets/sprites/fx/coop_star.png")      # 별의 낙하 위협
const CAGE_TEX := preload("res://assets/sprites/fx/coop_cage.png")      # 소울 케이지(피해자 위)
const SEAL_TEX := preload("res://assets/sprites/fx/coop_seal.png")      # 봉인진(발밑 룬)
const HUDDLE_TEX := preload("res://assets/sprites/fx/coop_huddle.png")  # 뭉치기 집결 링
const GAZE_TEX := preload("res://assets/sprites/fx/coop_gaze.png")      # 직면(시선)
const METEOR_TEX := preload("res://assets/sprites/fx/coop_meteor.png")  # 만료 시 낙하 메테오
const IMPACT_TEX := preload("res://assets/sprites/fx/coop_impact.png")  # 착탄 폭발
const DOOM_TEX := preload("res://assets/sprites/fx/coop_doom.png")      # 즉사 장판(케이지 피해자)
# 유령/데이터 필터 — 모든 협동 FX에 공유 씌워 반투명 유령 + 지직 데이터로 통일(재작화 없이).
# 표시 전용(네트워크·권한 무접촉). 그림 형태는 유지하고 질감만 얹는다. 계약 = assets/shaders/wraith_fx.gdshader.
const WRAITH_FX_SHADER := preload("res://assets/shaders/wraith_fx.gdshader")

const DANGER_LEAD_S := 1.5       # 만료 전 붉은 예고 고조 구간
const REACH_RADIUS := 40.0       # 별낙하 표식 도달 반경
const SAFE_MARGIN := 12.0        # 안전 반경 관용 여유 (지연·지터 흡수)
const GRACE_S := 0.3             # 만료 직전 이 시간 안에 안전지대에 있었으면 살려줌 (네트워크 지연 관용)

const MECH_CAGE := "cage"        # 한 명 속박 → 파트너 근접+키패드 구출
const MECH_SOLVE := "solve"      # 전원 각자 키패드(공유 순서) 완료
const MECH_REACH := "reach"      # 전원 표식 지점으로 대피(이동)
const MECH_SCATTER := "scatter"  # 각자 다른 표식으로 갈라짐(분산·이동)
const MECH_HUDDLE := "huddle"    # 둘이 바짝 붙기(뭉치기·이동)
# C1 영혼 비석 결박 — 한 명(A) 비석에 결박(연타 버티기) + 파트너(B)가 비석 파괴. 두 게이지 맞물림.
# (stele_bind_coop.md §4·§6-4 — CAGE 확장. win = A 저항시간.)
const MECH_STELE := "stele"
const STELE_DURA_MAX := 100.0    # 비석 내구도(B가 깎음, 0=파괴=성공)
const STELE_HIT := 6.0           # B 타격 1회당 내구도 감소
const STELE_REGEN := 10.0        # 내구도 자연회복(/s) — 단 A가 버티는(연타) 동안은 정지
const RESIST_DRAIN := 6.0        # A 저항시간 기본 감소(/s)
const RESIST_MASH_DRAIN := 3.0   # A 연타 중 감소(/s) — 버티면 느려짐
const STELE_MASH_WINDOW_MS := 500  # 이 시간 안에 연타 입력이 있으면 "버티는 중"
const STELE_B_HIT_COOLDOWN_MS := 220  # B 타격 최소 간격(연타 스팸 방지 — 호스트/로컬 게이트)
const STELE_FAIL_HP_FRAC := 0.4  # 저항 0(실패) 시 A가 잃는 HP 비율
const STELE_BOSS_HEAL_FRAC := 0.06  # 실패 시 보스 소량 회복 비율
# 가시 링(비석 주기 hazard) + 파편(회수 강타 아이템) — §4
const THORN_INTERVAL := 2.5      # 가시 링 방출 주기(s)
const THORN_TELEGRAPH := 0.7     # 링 예고(커지는 구간) — 구르기로 피할 시간
const THORN_RADIUS := 52.0       # 링 판정 반경(B가 안이면 피격)
const THORN_DAMAGE := 8          # 링 피격 데미지(B)
const SHARD_TTL := 3.0           # 파편 잔존(s)
const SHARD_PICKUP_RADIUS := 26.0
const SHARD_BUFF_HITS := 3       # 파편 회수 = 다음 N타 강타
const STELE_HIT_STRONG := 18.0   # 강타 시 내구도 감소(§4 −18)

const HUDDLE_RADIUS := 50.0      # 뭉치기 성공 = 서로 이 거리 안

# 로테이션 6종 — 이동/위치 기반 위주(키패드는 봉인진·직면 2개뿐), 유형 다양.
const MECHS: Array[Dictionary] = [
	{"m": MECH_CAGE, "name": "소울 케이지", "desc": "한 명 갇힘 — 즉사 장판! 파트너가 달려가 WASD로 풀어라, 늦으면 메테오!", "len": 4, "win": 8.0},
	{"m": MECH_REACH, "name": "별의 낙하", "desc": "메테오 낙하! 초록 표식 안에서 끝까지 버텨라 — 밖이면 즉사!", "win": 6.0},
	{"m": MECH_SOLVE, "name": "봉인진", "desc": "시간 안에 WASD 순서를 풀어라 — 못 풀면 메테오!", "len": 4, "win": 6.0},
	{"m": MECH_SCATTER, "name": "분산", "desc": "각자 다른 표식(초록·주황) 안에서 버텨라 — 나가면 즉사!", "win": 6.0},
	{"m": MECH_HUDDLE, "name": "뭉치기", "desc": "초록 링 안에 둘 다 모여 버텨라 — 밖이면 즉사!", "win": 5.0},
	{"m": MECH_SOLVE, "name": "직면", "desc": "시간 안에 표시 키를 눌러라 — 못 누르면 메테오!", "len": 1, "win": 4.0},
	{"m": MECH_STELE, "name": "영혼 비석 결박", "desc": "한 명 결박! A는 연타로 버티고 B는 비석을 부숴 구출하라 — 저항 소진 전에!", "win": 18.0},
]

@export var boss_eid: String = "boss1"
@export var stele_only: bool = false  # 실보스: true면 로테이션 대신 영혼 비석(STELE)만 발동(다른 테스트 메커니즘 제외)
const BUILD_TAG := "v0725g-menu"

var _mech_idx: int = 0            # 다음 발동할 패턴 인덱스
var _mech: String = ""           # 현재 활성 패턴 종류
var _mech_name: String = ""
var _mech_desc: String = ""

var _active: bool = false
var debug_hold: bool = false  # 테스트 랩 — true면 자동 순환 안 함(버튼으로만 발동). TestMode 게이트, 외부 설정.
var _window_left: float = 0.0
var _window_max: float = 8.0
var _next_left: float = FIRST_DELAY_S
var _victim: int = -1             # CAGE 피해자 (SOLVE는 -1)
var _seq: Array[int] = []         # 키패드 순서열
var _seq_pos: int = 0             # 로컬 진행 위치
var _engaged: bool = false        # CAGE 구조자: 파트너 근처 도달
var _my_solved: bool = false      # 로컬: 내 키패드 완료
var _done_set: Dictionary = {}    # 호스트: SOLVE 완료한 peer_id 집합
var _target: Vector2 = Vector2.ZERO   # REACH/SCATTER 표식 A
var _target2: Vector2 = Vector2.ZERO  # SCATTER 표식 B
var _marker: Sprite2D = null      # 표식 A(월드)
var _marker2: Sprite2D = null     # SCATTER 표식 B(월드)
var _cage: Sprite2D = null        # CAGE 창살(피해자 추적)
var _doom: Sprite2D = null        # CAGE 즉사 장판(피해자 발밑 추적)
var _fx: Array[Sprite2D] = []     # 패턴별 부가 이펙트(별·봉인진·직면·집결) — 정적
var _danger: ColorRect = null     # 화면 붉은 예고/플래시 오버레이 (표시 전용)
var _last_safe_t: Dictionary = {} # 호스트: 위치 패턴에서 피어가 마지막으로 안전지대 안에 있던 시각(msec)
# --- C1 영혼 비석 결박 상태 (호스트 확정) ---
var _stele_dura: float = STELE_DURA_MAX   # 비석 내구도(호스트 확정)
var _resist: float = 100.0                # A 저항시간(호스트 확정, win에서 초기화)
var _a_mash_msec: int = -1                # A가 마지막으로 연타한 시각(호스트) — "버티는 중" 판정
var _b_hit_msec: int = -1                 # B가 마지막으로 비석 타격한 시각(로컬 스팸 게이트)
var _stele_obj: Sprite2D = null           # 영혼 비석 스프라이트(피해자 옆 고정)
var _stele_pos: Vector2 = Vector2.ZERO    # 비석 월드 위치(결박 시작점 고정)
var _soul_line: Line2D = null             # 비석↔A 붉은 결박선
var _resist_bar_bg: ColorRect = null      # A 저항 게이지(내구도 바 아래 별도)
var _resist_bar_fg: ColorRect = null
var _thorn_next: float = 0.0              # 다음 가시 링까지(호스트)
var _shard: Sprite2D = null               # 현재 가시 파편(1개 유지)
var _shard_pos: Vector2 = Vector2.ZERO
var _shard_left: float = 0.0              # 파편 잔존 타이머(호스트)
var _b_buff_hits: int = 0                 # B 강타 남은 횟수(파편 회수, 호스트)
var _gauge_next: float = 0.0              # 게이지 표시 브로드캐스트 스로틀(호스트)
var _roll_grant_msec: Dictionary = {}     # 원격 피어 구르기 i-frame 창(가시 링 회피, Critical4)
var _npc_b_msec: int = -1                 # 랩: NPC가 B일 때(인간이 A) 자동 타격 스로틀

var _log_left: float = 0.0

# UI
var _status: Label = null
var _count_label: Label = null
var _name_label: Label = null
var _desc_label: Label = null
var _prompt: CanvasLayer = null
var _title: Label = null
var _keys_box: HBoxContainer = null
var _bar_bg: ColorRect = null
var _bar_fg: ColorRect = null


func _ready() -> void:
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.peer_left.connect(_on_peer_left)
	_build_prompt()
	print("[coop] ready · my_id=%d host=%s" % [Net.my_id, str(Net.is_host())])


func _process(delta: float) -> void:
	_update_status()
	if _active:
		if _mech == MECH_STELE:
			_update_stele(delta)
			return
		_window_left -= delta
		_update_bar()
		_update_danger()
		if _mech == MECH_CAGE:
			_update_rescuer_proximity()
			var vic := _player_by_id(_victim)
			if vic != null:
				if _cage != null:
					_cage.global_position = vic.global_position + Vector2(0, -4)
				if _doom != null:
					_doom.global_position = vic.global_position + Vector2(0, 6)
		# 조기 성공 없음 — 제한시간 끝까지 버텨야 한다. 만료 순간에만 판정(메테오).
		if Net.is_host():
			_track_safe()                    # 매 프레임 안전지대 체류 시각 기록(유예 판정용)
			if _window_left <= 0.0:
				_expire()
		return
	if debug_hold:
		return  # 테스트 랩 — 자동 순환 발동 안 함 (패턴 버튼으로만)
	_log_left -= delta
	if _log_left <= 0.0:
		_log_left = 1.0
		print("[coop] host=%s players=%d boss=%s next=%.1f" % [str(Net.is_host()), _alive_peer_ids().size(), str(_boss_alive()), _next_left])
	if not Net.is_host() or _alive_peer_ids().is_empty():
		return
	_next_left -= delta
	if _next_left <= 0.0:
		_trigger()


func _update_status() -> void:
	if _status == null:
		return
	var alive := _alive_peer_ids().size()
	var boss := "O" if _boss_alive() else "X"
	var state := ("ACTIVE:%s" % _mech) if _active else ("host next %.0fs" % _next_left if Net.is_host() else "guest")
	_status.text = "coop %s · boss:%s · 인원:%d · %s" % [BUILD_TAG, boss, alive, state]
	# 3·2·1 카운트다운 + 다음 패턴 이름·설명 (호스트, 3초 이내)
	var show_count := Net.is_host() and not _active and not debug_hold and not _alive_peer_ids().is_empty() and _next_left <= 3.0 and _next_left > 0.0
	_count_label.visible = show_count
	_name_label.visible = show_count
	_desc_label.visible = show_count
	if show_count:
		var up: Dictionary = MECHS[_mech_idx]
		_count_label.text = str(int(ceil(_next_left)))
		_name_label.text = "◆ " + str(up.get("name", ""))
		_desc_label.text = str(up.get("desc", ""))


# ── 발동 (호스트): 다음 패턴 선택 ──
func _trigger() -> void:
	var alive := _alive_peer_ids()
	if alive.size() < 2:
		_next_left = INTERVAL_S   # 2인 전용
		return
	if stele_only:
		_mech_idx = MECHS.size() - 1   # STELE는 MECHS 마지막 — 실보스는 이것만
	var cfg: Dictionary = MECHS[_mech_idx]
	_mech_idx = (_mech_idx + 1) % MECHS.size()
	_mech = str(cfg["m"])
	_mech_name = str(cfg["name"])
	_mech_desc = str(cfg["desc"])
	_window_max = float(cfg.get("win", 8.0))
	var seq_len := int(cfg.get("len", 4))
	_seq = []
	for _i in seq_len:
		_seq.append(randi() % KEYS.size())
	_victim = alive[randi() % alive.size()] if (_mech == MECH_CAGE or _mech == MECH_STELE) else -1
	# 랩: 피해자(A)를 NPC로 고정 → 님(B)이 달려가 구출/비석 파괴(패턴을 님이 푼다)
	if TestMode.is_active() and (_mech == MECH_CAGE or _mech == MECH_STELE) and _player_by_id(TestMode.NPC_PEER_ID) != null:
		_victim = TestMode.NPC_PEER_ID
	# 위치 표식 결정 (생존 평균 위치 기준)
	var avg := Vector2.ZERO
	for pid: int in alive:
		var pp := _player_by_id(pid)
		if pp != null:
			avg += pp.global_position
	avg /= float(maxi(alive.size(), 1))
	if _mech == MECH_REACH:
		var ang := randf() * TAU
		_target = avg + Vector2(cos(ang), sin(ang)) * 160.0
	elif _mech == MECH_SCATTER:
		_target = avg + Vector2(-150.0, -40.0)   # A(왼쪽)
		_target2 = avg + Vector2(150.0, 40.0)    # B(오른쪽)
	elif _mech == MECH_HUDDLE:
		_target = avg                            # 집결 안전 지점 = 파티 중심
	print("[coop] ★TRIGGER %s victim=%d seq=%s" % [_mech, _victim, str(_seq)])
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_CALL, "m": _mech, "t": _window_max,
		"v": _victim, "s": _seq, "n": _mech_name, "d": _mech_desc,
		"tx": _target.x, "ty": _target.y, "tx2": _target2.x, "ty2": _target2.y})
	_begin(_window_max)


# 테스트 랩 전용 — 특정 코옵 패턴을 즉시 강제 발동(순환 무시). 호스트만·비활성 중만.
# _trigger를 그대로 타므로(2인 = 님+NPC 필요) 실제 발동·판정·FX가 진짜와 동일하다.
func debug_force_mech(idx: int) -> void:
	if not Net.is_host() or _active:
		return
	if idx < 0 or idx >= MECHS.size():
		return
	_mech_idx = idx
	_trigger()


# 테스트 랩 — STELE를 **지정 victim**으로 즉시 발동. 인간이 A(=victim=자기) / B(=victim=NPC)를 골라 솔로 테스트.
func debug_force_stele(victim_pid: int) -> void:
	if not Net.is_host() or _active:
		return
	if _alive_peer_ids().size() < 2:
		return   # 2인(인간+NPC) 필요
	_mech = MECH_STELE
	_mech_name = "영혼 비석 결박"
	_window_max = 18.0
	_victim = victim_pid
	_npc_b_msec = -1
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_CALL, "m": _mech, "t": _window_max,
		"v": _victim, "s": [], "n": _mech_name, "d": "", "tx": 0.0, "ty": 0.0, "tx2": 0.0, "ty2": 0.0})
	_begin(_window_max)


func _begin(t: float) -> void:
	_active = true
	_window_left = t
	_window_max = t
	_seq_pos = 0
	_engaged = false
	_my_solved = false
	_done_set = {}
	_last_safe_t = {}
	if _danger != null:
		_danger.color.a = 0.0
	var me := _local_player()
	if me != null:
		if _mech == MECH_CAGE or _mech == MECH_STELE:
			me.bound = (me.peer_id == _victim)   # 피해자만 정지, 구조자는 이동
		elif _mech == MECH_SOLVE:
			me.bound = true                      # SOLVE = 전원 정지(WASD가 키패드로)
		else:
			me.bound = false                     # REACH = 이동해야 하니 자유
	if _mech == MECH_REACH:
		_marker = _mk_marker(_target, Color(0.4, 1.0, 0.5, 0.85))
		_fx.append(_mk_sprite(STAR_TEX, _target + Vector2(0, -12), Color(1, 1, 1, 1), 6))
	elif _mech == MECH_SCATTER:
		_marker = _mk_marker(_target, Color(0.4, 1.0, 0.5, 0.85))    # A 초록
		_marker2 = _mk_marker(_target2, Color(1.0, 0.65, 0.2, 0.85)) # B 주황
	elif _mech == MECH_HUDDLE:
		_marker = _mk_marker(_target, Color(0.5, 1.0, 0.6, 0.5))          # 안전 링(초록)
		_fx.append(_mk_sprite(HUDDLE_TEX, _target, Color(1, 1, 1, 0.9), 5))
	elif _mech == MECH_CAGE:
		_cage = _mk_sprite(CAGE_TEX, Vector2.ZERO, Color(1, 1, 1, 0.95), 8)  # _process가 피해자 추적
		_doom = _mk_sprite(DOOM_TEX, Vector2.ZERO, Color(1, 1, 1, 0.9), 3)   # 즉사 장판(발밑)
	elif _mech == MECH_SOLVE and me != null:
		if _mech_name == "직면":
			_fx.append(_mk_sprite(GAZE_TEX, me.global_position + Vector2(0, -22), Color(1, 1, 1, 0.95), 6))
		else:
			_fx.append(_mk_sprite(SEAL_TEX, me.global_position + Vector2(0, 8), Color(1, 1, 1, 0.95), 4))
	elif _mech == MECH_STELE:
		# 두 게이지 초기화(호스트 확정 · 게스트는 표시용 max에서 시작 — 동기화는 후속). A 옆에 비석 낙하 + 붉은 결박선.
		_stele_dura = STELE_DURA_MAX
		_resist = 100.0
		_a_mash_msec = -1
		_b_hit_msec = -1
		_thorn_next = THORN_INTERVAL
		_shard_left = 0.0
		_b_buff_hits = 0
		var vic := _player_by_id(_victim)
		_stele_pos = (vic.global_position + Vector2(22, -2)) if vic != null else Vector2.ZERO
		_stele_obj = _mk_stele(_stele_pos)
		_soul_line = _mk_soul_line()
		var bnode := _boss_node()
		if bnode != null and bnode.has_method("play_c1_clip"):
			bnode.set("coop_locked", true)   # 결박 중 보스 AI 정지(설계 §9)
			bnode.call("play_c1_clip", "roar")   # 지목 포효
			get_tree().create_timer(0.5).timeout.connect(_stele_start_grab.bind(bnode))
	_show_prompt(true)


func _mk_marker(pos: Vector2, col: Color) -> Sprite2D:
	return _mk_sprite(MARKER_TEX, pos, col, 5)


func _mk_sprite(tex: Texture2D, pos: Vector2, col: Color, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.modulate = col
	s.global_position = pos
	s.z_index = z
	s.material = _wraith_mat()   # 유령/데이터 필터 (공유 머티리얼)
	get_parent().add_child(s)
	return s


# 공유 유령 필터 머티리얼 — 1회 생성, 모든 FX가 문다(TIME 구동이라 공유해도 무방). uniform 전부 명시(웹 안전).
var _wraith_mat_cache: ShaderMaterial = null
func _wraith_mat() -> ShaderMaterial:
	if _wraith_mat_cache == null:
		var m := ShaderMaterial.new()
		m.shader = WRAITH_FX_SHADER
		m.set_shader_parameter(&"alpha_mul", 0.82)
		m.set_shader_parameter(&"flicker", 0.14)
		m.set_shader_parameter(&"scan_amt", 0.22)
		m.set_shader_parameter(&"glitch", 0.03)
		m.set_shader_parameter(&"dissolve", 0.22)
		_wraith_mat_cache = m
	return _wraith_mat_cache


func _clear_marker() -> void:
	if _marker != null:
		_marker.queue_free()
		_marker = null
	if _marker2 != null:
		_marker2.queue_free()
		_marker2 = null
	if _cage != null:
		_cage.queue_free()
		_cage = null
	if _doom != null:
		_doom.queue_free()
		_doom = null
	if _stele_obj != null:
		_stele_obj.queue_free()
		_stele_obj = null
	if _soul_line != null:
		_soul_line.queue_free()
		_soul_line = null
	if _shard != null:
		_shard.queue_free()
		_shard = null
		_shard_left = 0.0
	for s: Sprite2D in _fx:
		if is_instance_valid(s):
			s.queue_free()
	_fx.clear()


# ── C1 영혼 비석 결박 (CAGE 확장 — 두 게이지 맞물림) ──

# soul_stele.png 텍스처 (런타임 load — 아트 랜딩 전에도 파스 통과, 없으면 CAGE_TEX 폴백).
func _stele_tex() -> Texture2D:
	var t := load("res://assets/sprites/enemies/soul_stele.png") as Texture2D
	return t if t != null else CAGE_TEX


func _mk_stele(pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _stele_tex()
	s.hframes = 5   # idle 0~1 · break 2~4 (soul_stele 시트)
	s.frame = 0
	s.global_position = pos
	s.z_index = 4
	get_parent().add_child(s)
	return s


func _mk_soul_line() -> Line2D:
	var l := Line2D.new()
	l.width = 3.0
	l.default_color = Color(0.95, 0.15, 0.2, 0.85)   # 붉은 영혼 결박선
	l.z_index = 3
	get_parent().add_child(l)
	return l


# STELE 매 프레임 (활성 중). 결박선 갱신 + 호스트 두 게이지 판정. 게스트는 표시만(게이지 동기화는 후속).
func _update_stele(delta: float) -> void:
	var vic := _player_by_id(_victim)
	if _soul_line != null and vic != null:
		_soul_line.points = PackedVector2Array([_stele_pos, vic.global_position + Vector2(0, -8)])
	if Net.is_host():
		var now := Time.get_ticks_msec()
		# 랩: NPC가 반대 역할을 자동으로 → 인간이 A/B 어느 쪽이든 솔로로 테스트 가능(설계 요구)
		if TestMode.is_active():
			if _victim == TestMode.NPC_PEER_ID:
				_a_mash_msec = now   # NPC=A 자동 버티기 (인간이 B일 때)
			elif _player_by_id(TestMode.NPC_PEER_ID) != null and now - _npc_b_msec >= 500:
				_npc_b_msec = now
				_stele_b_hit()       # NPC=B 자동 타격 ~2/s (인간이 A일 때 — B가 비석을 깬다)
		var a_holding := (now - _a_mash_msec) <= STELE_MASH_WINDOW_MS
		# A 저항: 항상 감소, 버티는 중엔 느리게(§4)
		_resist -= (RESIST_MASH_DRAIN if a_holding else RESIST_DRAIN) * delta
		# 비석 내구도: A가 버티면 자연회복 정지(=B 진전 열림), 아니면 회복. B 타격은 input에서 즉시 감산.
		if not a_holding:
			_stele_dura = minf(STELE_DURA_MAX, _stele_dura + STELE_REGEN * delta)
		_thorn_next -= delta
		if _thorn_next <= 0.0:
			_thorn_next = THORN_INTERVAL
			_spawn_thorn_ring()
		_update_shard(delta)
		_gauge_next -= delta
		if _gauge_next <= 0.0:
			_gauge_next = 0.15
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_GAUGE, "du": _stele_dura, "re": _resist})
		if _stele_dura <= 0.0:
			_stele_success()
			return
		if _resist <= 0.0:
			_stele_fail()
			return
	_update_stele_bars()


# B가 비석 근처에서 타격 — 호스트가 내구도 확정. 연타 스팸은 쿨다운 게이트.
func _stele_b_hit() -> void:
	if not Net.is_host() or not _active or _mech != MECH_STELE:
		return
	var now := Time.get_ticks_msec()
	if now - _b_hit_msec < STELE_B_HIT_COOLDOWN_MS:
		return
	_b_hit_msec = now
	var dmg := STELE_HIT
	if _b_buff_hits > 0:
		dmg = STELE_HIT_STRONG   # 파편 회수 강타
		_b_buff_hits -= 1
	_stele_dura = maxf(0.0, _stele_dura - dmg)


# A가 버티기(연타) — 호스트가 시각 기록(회복 정지 + 저항 감소 완화).
func _stele_a_mash() -> void:
	if Net.is_host():
		_a_mash_msec = Time.get_ticks_msec()


# STELE 입력 — A(속박): 아무 키 연타=버티기 · B(자유): 비석 근처에서 아무 키=타격.
func _stele_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	var kc := ke.physical_keycode
	if not (KEYS.has(kc) or kc == KEY_SPACE or kc == KEY_J):
		return
	if Net.my_id == _victim:
		get_viewport().set_input_as_handled()   # A 버티기
		if Net.is_host():
			_stele_a_mash()
		else:
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_IN, "act": "mash"})
	else:
		var me := _local_player()
		if me == null or me.global_position.distance_to(_stele_pos) > RESCUE_RADIUS:
			return   # 비석에서 멀면 무시 — 달려가야 타격
		get_viewport().set_input_as_handled()   # B 타격
		if Net.is_host():
			_stele_b_hit()
		else:
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_IN, "act": "hit"})


func _stele_success() -> void:
	# 내구도 0 → 비석 파괴 + 보스 경직(공동 딜 창) + A 해방. _finish(성공·메테오 없음) 재사용.
	if _stele_obj != null:
		_stele_obj.frame = 4   # 산산조각
	var boss := _boss_node()
	if boss != null and boss.has_method("enter_groggy"):
		boss.call("enter_groggy", 3.0)   # 호스트 상태(무방비 창) — 클립/락은 _apply_resolution이 양쪽 처리
	_finish(true, [])


func _stele_fail() -> void:
	# 저항 0 → A가 HP 큰 덩이 잃고 강제 해방(즉사 아님 — 진행 계속). 메테오 없음.
	var vic := _player_by_id(_victim)
	if vic != null and vic.is_alive():
		var h := vic.get_node_or_null("Health") as HealthComponent
		if h != null:
			var mx: int = int(h.get("max_hp")) if h.get("max_hp") != null else 100
			h.apply_damage(int(mx * STELE_FAIL_HP_FRAC))
	_finish(false, [])   # dead 비움 = 메테오/즉사 없음, 실패 표시(붉은 플래시)만


func _on_peer_left(peer_id: int) -> void:
	_roll_grant_msec.erase(peer_id)
	if _active and _mech == MECH_STELE:
		if Net.is_host():
			_finish(false, [])
		else:
			_apply_resolution(false, [], false)


func _boss_node() -> Node:
	for node: Node in get_tree().get_nodes_in_group("mob"):
		if str(node.get("eid")) == boss_eid:
			return node
	return null


# STELE 보스 클립 전환 (타이머 콜백 — bind로 노드 넘김)
func _stele_start_grab(b: Node) -> void:
	if is_instance_valid(b) and _active and _mech == MECH_STELE:
		b.call("play_c1_clip", "grab")


func _stele_end_clip(b: Node) -> void:
	if is_instance_valid(b):
		b.set("coop_locked", false)
		b.call("end_c1_clip")


# ── 가시 링 hazard + 파편 (STELE 중 B 회피 게임플레이 · §4) ──
func _plain_sprite(tex: Texture2D, pos: Vector2, z: int, a: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.global_position = pos
	sp.z_index = z
	sp.modulate = Color(1, 1, 1, a)
	get_parent().add_child(sp)
	return sp


func _spawn_thorn_ring() -> void:
	# 호스트: 로컬 링 시각 + 전원 브로드캐스트(게스트도 보고 피하게, Critical3) + 예고 후 판정
	_spawn_thorn_visual(_stele_pos)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_THORN, "x": _stele_pos.x, "y": _stele_pos.y, "t": "ring"})
	get_tree().create_timer(THORN_TELEGRAPH).timeout.connect(_thorn_judge.bind(_stele_pos))


func _spawn_thorn_visual(pos: Vector2) -> void:
	var tex := load("res://assets/sprites/enemies/thorn_ring.png") as Texture2D
	if tex == null:
		return
	var ring := _plain_sprite(tex, pos, 3, 0.55)
	ring.scale = Vector2.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector2.ONE * (THORN_RADIUS * 2.0 / 64.0), THORN_TELEGRAPH)
	tw.parallel().tween_property(ring, "modulate:a", 0.95, THORN_TELEGRAPH)
	tw.tween_property(ring, "modulate:a", 0.0, 0.2)
	tw.tween_callback(ring.queue_free)


func _thorn_judge(pos: Vector2) -> void:
	if not (Net.is_host() and _active and _mech == MECH_STELE):
		return
	for pid: int in _alive_peer_ids():
		if pid == _victim:
			continue
		var p := _player_by_id(pid)
		if p == null:
			continue
		if p.net_anchor().distance_to(pos) <= THORN_RADIUS and not _b_rolling(p):
			var h := p.get_node_or_null("Health") as HealthComponent
			if h != null:
				h.apply_damage(THORN_DAMAGE)
	_spawn_shard(pos)


func _b_rolling(p) -> bool:
	if p.is_local:
		return p.is_rolling()
	return CombatMath.is_iframe_active(int(_roll_grant_msec.get(p.peer_id, -1000000000)), Time.get_ticks_msec())


func _spawn_shard(pos: Vector2) -> void:
	_spawn_shard_visual(pos)
	if Net.is_host():
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_THORN, "x": pos.x, "y": pos.y, "t": "shard"})


func _spawn_shard_visual(pos: Vector2) -> void:
	if _shard != null and is_instance_valid(_shard):
		_shard.queue_free()
	var tex := load("res://assets/sprites/enemies/thorn_shard.png") as Texture2D
	_shard = _plain_sprite(tex, pos + Vector2(0, 4), 4, 1.0) if tex != null else null
	_shard_pos = pos + Vector2(0, 4)
	_shard_left = SHARD_TTL


func _update_shard(delta: float) -> void:
	if _shard_left <= 0.0:
		return
	_shard_left -= delta
	for pid: int in _alive_peer_ids():
		if pid == _victim:
			continue
		var p := _player_by_id(pid)
		if p != null and p.net_anchor().distance_to(_shard_pos) <= SHARD_PICKUP_RADIUS:
			_b_buff_hits = SHARD_BUFF_HITS   # 회수 → 다음 N타 강타
			_shard_left = 0.0
			break
	if _shard_left <= 0.0 and _shard != null and is_instance_valid(_shard):
		_shard.queue_free()
		_shard = null


# 두 게이지 바 갱신 — 내구도(주황, _bar_fg 재사용) + A 저항(붉음, _resist_bar_fg).
func _update_stele_bars() -> void:
	if _bar_fg != null:
		var dr: float = clampf(_stele_dura / STELE_DURA_MAX, 0.0, 1.0)
		_bar_fg.size = Vector2(240.0 * dr, 10.0)
		_bar_fg.color = Color(0.92, 0.5, 0.2)
	if _resist_bar_fg != null:
		var rr: float = clampf(_resist / 100.0, 0.0, 1.0)
		_resist_bar_fg.size = Vector2(240.0 * rr, 8.0)


# ── 만료 판정 (호스트): 버티지 못한 자에게 메테오 ──
func _expire() -> void:
	var dead: Array[int] = []
	for pid: int in _alive_peer_ids():
		if not _is_safe(pid):
			dead.append(pid)
	_finish(dead.is_empty(), dead)


# 위치 패턴에서 각 피어의 안전지대 체류 시각 기록 (호스트, 매 프레임)
func _track_safe() -> void:
	if not (_mech == MECH_REACH or _mech == MECH_SCATTER or _mech == MECH_HUDDLE):
		return
	var now := Time.get_ticks_msec()
	for pid: int in _alive_peer_ids():
		if _inside_now(pid):
			_last_safe_t[pid] = now


# 지금 이 피어가 안전지대 기하 안에 있나. 판정 좌표 = net_anchor()(최신 수신 좌표, 보간 지연 제외 — rules §3,
# 전투 판정과 동일). 마진으로 지터 흡수.
func _inside_now(pid: int) -> bool:
	var p := _player_by_id(pid)
	if p == null:
		return true
	var pos := p.net_anchor()
	match _mech:
		MECH_REACH:
			return pos.distance_to(_target) <= REACH_RADIUS + SAFE_MARGIN
		MECH_SCATTER:
			var ids := _alive_peer_ids()
			ids.sort()
			var tgt := _target if ids.find(pid) % 2 == 0 else _target2
			return pos.distance_to(tgt) <= REACH_RADIUS + SAFE_MARGIN
		MECH_HUDDLE:
			return pos.distance_to(_target) <= HUDDLE_RADIUS + SAFE_MARGIN
		_:
			return false


# 만료 시점, 이 피어가 안전한가 (안전지대 안 / 키패드 완료 / 구출됨)
func _is_safe(pid: int) -> bool:
	if TestMode.is_active() and pid == TestMode.NPC_PEER_ID:
		return true  # 랩: NPC 더미는 자기 역할 자동 통과 (님만 풀면 성공)
	match _mech:
		MECH_CAGE:
			return pid != _victim        # 만료까지 미구출 = 피해자만 위험(구조자 안전)
		MECH_SOLVE:
			return _done_set.has(pid)    # 키패드 완료자만 안전
		_:
			# 위치 패턴: 지금 안에 있거나, 최근 GRACE_S 안에 있었으면 살림 (네트워크 지연·지터 관용)
			if _inside_now(pid):
				return true
			var t: int = _last_safe_t.get(pid, -999999)
			return Time.get_ticks_msec() - t <= int(GRACE_S * 1000.0)


# 내 SCATTER 배정 표식 색 (인덱스 짝수=A 초록 / 홀수=B 주황)
func _my_scatter_is_a() -> bool:
	var ids := _alive_peer_ids()
	ids.sort()
	return ids.find(Net.my_id) % 2 == 0


# ── CAGE 구조자 근접 판정 ──
func _update_rescuer_proximity() -> void:
	if Net.my_id == _victim:
		return
	var me := _local_player()
	var vic := _player_by_id(_victim)
	if me == null or vic == null:
		return
	var near := me.global_position.distance_to(vic.global_position) <= RESCUE_RADIUS
	if near and not _engaged:
		_engaged = true
		me.bound = true
		_seq_pos = 0
		_show_prompt(true)
	elif not near and _engaged:
		_engaged = false
		me.bound = false
		_seq_pos = 0
		_show_prompt(true)


# ── 로컬 키패드 입력 ──
func _unhandled_input(event: InputEvent) -> void:
	if not _active or _my_solved:
		return
	if _mech == MECH_STELE:
		_stele_input(event)
		return
	if _mech == MECH_CAGE and (Net.my_id == _victim or not _engaged):
		return   # CAGE: 구조자가 파트너 근처일 때만
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	var idx := KEYS.find(ke.physical_keycode)
	if idx < 0:
		return
	get_viewport().set_input_as_handled()
	if _seq_pos < _seq.size() and idx == _seq[_seq_pos]:
		_seq_pos += 1
		_refresh_keys()
		if _seq_pos >= _seq.size():
			_on_solved()
	else:
		_seq_pos = 0
		_refresh_keys()


func _on_solved() -> void:
	_my_solved = true
	if _mech == MECH_CAGE:
		# 구조자가 갇힌 파트너를 풀었다 → 즉시 구출 확정(메테오 없음)
		if Net.is_host():
			_finish(true, [])
		else:
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_IN, "done": 1})
	else:
		# SOLVE: 내 키패드 완료 통지 — 전원 완료 시 성공
		_title.text = "완료! 파트너 대기 중…"
		_keys_box.visible = false
		if Net.is_host():
			_done_set[Net.my_id] = true
			_check_all_solved()
		else:
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_IN, "done": 1})


func _check_all_solved() -> void:
	for pid: int in _alive_peer_ids():
		if TestMode.is_active() and pid == TestMode.NPC_PEER_ID:
			continue  # 랩: NPC는 자동 완료 취급 (님만 풀면 성공)
		if not _done_set.has(pid):
			return
	_finish(true, [])   # 전원 완료 → 성공(메테오 없음)


# ── 판정 종료 (호스트 발신 + 로컬 적용) ──
# dead = 메테오 맞고 죽는 피어 목록(비면 전원 생존 = 성공)
func _finish(success: bool, dead: Array) -> void:
	if not _active:
		return
	_next_left = INTERVAL_S
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_COOP_RES, "ok": 1 if success else 0, "dead": dead})
	if not success:
		print("[coop] ☄METEOR %s dead=%s" % [_mech, str(dead)])
	_apply_resolution(success, dead, true)


# 판정 연출·피해 적용. do_damage=호스트만 실제 피해. 나머지는 표시(메테오·플래시).
func _apply_resolution(success: bool, dead: Array, do_damage: bool) -> void:
	if not _active:
		return
	_active = false
	# 착탄 좌표 = 죽는 피어의 현재 위치 (마커 정리 전에 수집)
	var strikes: Array[Vector2] = []
	for e: Variant in dead:
		var p := _player_by_id(int(e))
		if p != null:
			strikes.append(p.global_position)
	_show_prompt(false)
	_unbind_all()
	_clear_marker()
	_flash_danger(success)
	if not strikes.is_empty():
		_play_meteor(strikes)
	if do_damage:
		for e: Variant in dead:
			_damage_one(int(e))
	if _mech == MECH_STELE:
		var sboss := _boss_node()
		if sboss != null:
			if success and sboss.has_method("play_c1_clip"):
				sboss.call("play_c1_clip", "groggy")   # 성공: 경직 클립(양쪽) + 3.2s 뒤 원복
				get_tree().create_timer(3.2).timeout.connect(_stele_end_clip.bind(sboss))
			elif sboss.has_method("end_c1_clip"):
				sboss.set("coop_locked", false)   # 실패: 즉시 락 해제 + 원복(게스트 정지 버그 방지)
				sboss.call("end_c1_clip")
	EventBus.coop_result.emit(success)


# 메테오 낙하 연출 (표시 전용, 각 클라 로컬). 위에서 떨어져 착탄→폭발.
func _play_meteor(positions: Array) -> void:
	if EventBus.has_signal("screen_shake"):
		EventBus.screen_shake.emit(7.0)
	for p: Vector2 in positions:
		var m := _mk_sprite(METEOR_TEX, p + Vector2(0, -160), Color(1, 1, 1, 1), 40)
		var tw := create_tween()
		tw.tween_property(m, "global_position", p, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_meteor_impact.bind(m, p))


func _meteor_impact(meteor: Sprite2D, pos: Vector2) -> void:
	if is_instance_valid(meteor):
		meteor.queue_free()
	var burst := _mk_sprite(IMPACT_TEX, pos, Color(1, 1, 1, 1), 40)
	burst.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(burst, "scale", Vector2(1.7, 1.7), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(burst, "modulate:a", 0.0, 0.35)
	tw.tween_callback(burst.queue_free)


# 만료 전 붉은 예고 고조 (마지막 DANGER_LEAD_S 구간, 활성 중 매 프레임)
func _update_danger() -> void:
	if _danger == null:
		return
	if _window_left <= DANGER_LEAD_S:
		var t: float = 1.0 - _window_left / DANGER_LEAD_S          # 0→1
		var pulse: float = 0.10 + 0.22 * t * (0.6 + 0.4 * sin(_window_left * 20.0))
		_danger.color = Color(0.95, 0.12, 0.08, clampf(pulse, 0.0, 0.42))
	else:
		_danger.color.a = 0.0


# 판정 순간 화면 플래시 (실패=붉게, 성공=초록) 후 페이드
func _flash_danger(success: bool) -> void:
	if _danger == null:
		return
	_danger.color = Color(0.3, 0.95, 0.4, 0.28) if success else Color(0.98, 0.15, 0.1, 0.55)
	var tw := create_tween()
	tw.tween_property(_danger, "color:a", 0.0, 0.5)


func _damage_one(pid: int) -> void:
	var p := _player_by_id(pid)
	if p != null and p.is_alive():
		var h := p.get_node_or_null("Health") as HealthComponent
		if h != null:
			h.apply_damage(FAIL_DAMAGE)


# ── 네트워크 수신 ──
func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_COOP_CALL:
			if from_id != NetSchema.HOST_ID:
				return
			_mech = str(data.get("m", MECH_CAGE))
			_mech_name = str(data.get("n", ""))
			_mech_desc = str(data.get("d", ""))
			_victim = int(data.get("v", -1))
			_seq = []
			var s_v: Variant = data.get("s", [])
			if s_v is Array:
				for e: Variant in (s_v as Array):
					_seq.append(int(e))
			_target = Vector2(float(data.get("tx", 0.0)), float(data.get("ty", 0.0)))
			_target2 = Vector2(float(data.get("tx2", 0.0)), float(data.get("ty2", 0.0)))
			_begin(float(data.get("t", 8.0)))
		NetSchema.G_COOP_IN:
			if not Net.is_host():
				return
			if _mech == MECH_STELE:
				# 게스트 A 버티기 / B 타격 보고 → 호스트 확정. 역할=발신자 id(위조 방지) + B 근접 호스트 재검증.
				if not _active:
					return
				match str(data.get("act", "")):
					"mash":
						if from_id == _victim:
							_stele_a_mash()
					"hit":
						if from_id != _victim:
							var bp := _player_by_id(from_id)
							if bp != null and bp.net_anchor().distance_to(_stele_pos) <= RESCUE_RADIUS:
								_stele_b_hit()
				return
			if int(data.get("done", 0)) != 1:
				return
			if _mech == MECH_CAGE:
				if from_id != _victim:
					_finish(true, [])   # 구조자 완료 → 성공(메테오 없음)
			else:
				_done_set[from_id] = true
				_check_all_solved()
		NetSchema.G_COOP_RES:
			if from_id != NetSchema.HOST_ID:
				return
			var dead: Array[int] = []
			var dv: Variant = data.get("dead", [])
			if dv is Array:
				for e: Variant in (dv as Array):
					dead.append(int(e))
			_apply_resolution(int(data.get("ok", 0)) == 1, dead, false)   # 게스트: 표시만(피해 없음)
		NetSchema.G_COOP_GAUGE:
			if Net.is_host() or from_id != NetSchema.HOST_ID:
				return
			if _mech == MECH_STELE and _active:
				_stele_dura = float(data.get("du", _stele_dura))
				_resist = float(data.get("re", _resist))
				_update_stele_bars()
		NetSchema.G_ROLL:
			_roll_grant_msec[from_id] = Time.get_ticks_msec()   # 원격 구르기 i-frame 창 기록
		NetSchema.G_THORN:
			if Net.is_host() or from_id != NetSchema.HOST_ID:
				return
			if _mech != MECH_STELE or not _active:
				return
			var tpos := Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
			if str(data.get("t", "")) == "shard":
				_spawn_shard_visual(tpos)
			else:
				_spawn_thorn_visual(tpos)


# ── 헬퍼 ──
func _boss_alive() -> bool:
	for node: Node in get_tree().get_nodes_in_group("mob"):
		if str(node.get("eid")) == boss_eid:
			var h := node.get_node_or_null("Health") as HealthComponent
			return h != null and not h.is_dead()
	return false


func _alive_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p != null and p.is_alive():
			ids.append(p.peer_id)
	return ids


func _local_player() -> PlayerActor:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p != null and p.is_local:
			return p
	return null


func _player_by_id(pid: int) -> PlayerActor:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p != null and p.peer_id == pid:
			return p
	return null


func _unbind_all() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p != null:
			p.bound = false


# ── 프롬프트 UI (HUD 무접촉) ──
func _build_prompt() -> void:
	# 붉은 예고/플래시 오버레이 (프롬프트 아래 레이어, 순수 UI)
	var dlayer := CanvasLayer.new()
	dlayer.layer = 8
	add_child(dlayer)
	_danger = ColorRect.new()
	_danger.color = Color(0.95, 0.12, 0.08, 0.0)
	_danger.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlayer.add_child(_danger)

	_prompt = CanvasLayer.new()
	_prompt.layer = 10
	add_child(_prompt)
	var center := Control.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(center)

	var slayer := CanvasLayer.new()
	slayer.layer = 9
	add_child(slayer)
	_status = Label.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 — 아래 게임 클릭을 먹지 않게 (rules §5)
	_status.position = Vector2(6, 4)
	_status.add_theme_color_override("font_color", Color(0.7, 1.0, 0.6))
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_status.add_theme_constant_override("outline_size", 3)
	slayer.add_child(_status)

	var clayer := Control.new()
	clayer.set_anchors_preset(Control.PRESET_FULL_RECT)
	clayer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slayer.add_child(clayer)

	_name_label = _mk_label(clayer, 60.0, 22, Color(0.7, 1.0, 0.6), 5)
	_count_label = _mk_label(clayer, 90.0, 64, Color(1.0, 0.85, 0.3), 8)
	_desc_label = _mk_label(clayer, 168.0, 13, Color(0.85, 0.9, 0.8), 4)

	_title = _mk_label(center, 50.0, 18, Color(0.6, 1.0, 0.55), 4)
	_title.add_theme_font_size_override("font_size", 18)

	_keys_box = HBoxContainer.new()
	_keys_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_keys_box.offset_top = 78.0
	_keys_box.offset_left = -120.0
	_keys_box.offset_right = 120.0
	_keys_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_keys_box.add_theme_constant_override("separation", 10)
	_keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_keys_box)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.08, 0.12, 0.08, 0.8)
	_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bar_bg.offset_left = -120.0
	_bar_bg.offset_right = 120.0
	_bar_bg.offset_top = 128.0
	_bar_bg.offset_bottom = 138.0
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_bar_bg)
	_bar_fg = ColorRect.new()
	_bar_fg.color = Color(0.4, 0.95, 0.45)
	_bar_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar_fg)
	# STELE 전용 A 저항 게이지(내구도 바 아래 별도) — 평소엔 숨김
	_resist_bar_bg = ColorRect.new()
	_resist_bar_bg.color = Color(0.12, 0.05, 0.05, 0.8)
	_resist_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_resist_bar_bg.offset_left = -120.0
	_resist_bar_bg.offset_right = 120.0
	_resist_bar_bg.offset_top = 142.0
	_resist_bar_bg.offset_bottom = 150.0
	_resist_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resist_bar_bg.visible = false
	center.add_child(_resist_bar_bg)
	_resist_bar_fg = ColorRect.new()
	_resist_bar_fg.color = Color(0.9, 0.25, 0.25)
	_resist_bar_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resist_bar_bg.add_child(_resist_bar_fg)
	_prompt.visible = false


func _mk_label(parent: Node, top: float, size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	# 🔴 안내 라벨은 장식이다 — 기본 STOP이면 480px 폭 밴드가 보스전 도중 그 아래 클릭(공격)을 통째로
	#    먹는다. 부모(center/clayer)가 IGNORE여도 자식엔 전파되지 않는다 (rules §5 1번 함정).
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -240.0
	l.offset_right = 240.0
	l.offset_top = top
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", outline)
	l.visible = false
	parent.add_child(l)
	return l


func _show_prompt(on: bool) -> void:
	if _prompt == null:
		return
	_prompt.visible = on
	_title.visible = on
	if not on:
		if _resist_bar_bg != null:
			_resist_bar_bg.visible = false
		return
	if _mech == MECH_CAGE:
		if Net.my_id == _victim:
			_title.text = "⛓ 갇혔다! 즉사 장판 — 파트너가 풀어야 산다!"
			_keys_box.visible = false
		elif _engaged:
			_title.text = "구출! 아래 키를 순서대로 눌러라!"
			_keys_box.visible = true
			_refresh_keys()
		else:
			_title.text = "⚡ 달려가 파트너를 풀어라 — 늦으면 메테오!"
			_keys_box.visible = false
	elif _mech == MECH_REACH:
		_title.text = "☄ 별의 낙하! 초록 표식 안에서 끝까지 버텨라!"
		_keys_box.visible = false
	elif _mech == MECH_SCATTER:
		_title.text = "분산! %s 표식 안에서 버텨라 — 나가면 즉사!" % ("초록(A)" if _my_scatter_is_a() else "주황(B)")
		_keys_box.visible = false
	elif _mech == MECH_HUDDLE:
		_title.text = "뭉쳐라! 초록 링 안에 둘 다 버텨라!"
		_keys_box.visible = false
	elif _mech == MECH_STELE:
		if Net.my_id == _victim:
			_title.text = "⛓ 결박됨! 아무 키나 연타해 버텨라 — 파트너가 비석을 부순다!"
		else:
			_title.text = "🔨 비석으로 달려가 연타해 부셔라 — 파트너 저항이 다하기 전에!"
		_keys_box.visible = false
	else:
		# SOLVE (봉인진/직면) — 전원 각자 키패드, 시간 내 완료 못하면 메테오
		_title.text = "%s — 시간 안에 아래 키를 순서대로!" % _mech_name
		_keys_box.visible = true
		_refresh_keys()
	_bar_bg.visible = true
	if _resist_bar_bg != null:
		_resist_bar_bg.visible = (_mech == MECH_STELE)
	if _mech == MECH_STELE:
		_update_stele_bars()
	else:
		_update_bar()


func _refresh_keys() -> void:
	if _keys_box == null:
		return
	for c: Node in _keys_box.get_children():
		c.queue_free()
	for i in _seq.size():
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 (rules §5)
		l.text = SYMS[_seq[i]]
		l.add_theme_font_size_override("font_size", 30)
		var col := Color(0.5, 1.0, 0.5) if i < _seq_pos else (Color(1, 1, 1) if i == _seq_pos else Color(0.45, 0.5, 0.55))
		l.add_theme_color_override("font_color", col)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 5)
		_keys_box.add_child(l)


func _update_bar() -> void:
	if _bar_fg == null:
		return
	var ratio: float = clampf(_window_left / maxf(_window_max, 0.01), 0.0, 1.0)
	_bar_fg.size = Vector2(240.0 * ratio, 10.0)
	_bar_fg.position = Vector2.ZERO
