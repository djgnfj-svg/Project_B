extends Node2D
# 모닥불 씬 — 스테이지 사이 체크포인트 (GDD §4·§5 확정: 각자 앉아야 하고, 앉는 동안 천천히 회복).
# 회복도 상태 확정이므로 호스트 권한 경로만 쓴다 (Health.confirm_hp → CombatAuthority가 php
# 브로드캐스트, rules §1·§3). G_SIT은 본인 상태 공지(힌트)일 뿐 — 호스트는 거리·생존을 재검증한다.
# 출발 = 호스트가 게이트에서 F → 다음 칸 (SceneFlow.request_stage — 마을 게이트와 같은 규약).
# 수치(회복량·간격·반경)는 def(.tres)가 쥔다 (rules §0·§4).

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerActor := preload("res://src/player/player.gd")
const SceneFlowNode := preload("res://src/net/scene_flow.gd")
const PeerSyncNode := preload("res://src/net/peer_sync.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")

@export var def: CampfireDef

var _local_in_fire: bool = false
var _local_in_gate: bool = false
var _sit_sent: bool = false  # 마지막으로 공지한 내 앉기 상태 — 변화(자동 해제 포함)를 감지해 송신
var _seated_remote: Dictionary = {}  # peer_id -> bool (G_SIT 수신 — 호스트 회복 판정의 힌트)
var _heal_accum: float = 0.0

@onready var _fire: Area2D = $Fire
@onready var _fire_hint: Label = $Fire/Hint
@onready var _gate_hint: Label = $Gate/Hint
@onready var _peer_sync: PeerSyncNode = $PeerSync
@onready var _scene_flow: SceneFlowNode = $SceneFlow


func _ready() -> void:
	_peer_sync.scene_id = GameState.stage_token()  # 칸 좌표 토큰 — stage.gd와 동일 규약
	set_meta("map_rect", Rect2(0, 0, 640, 360))  # 카메라 맵 클램프 — stage.gd와 동일 규약
	if def == null:
		push_error("[Campfire] def 미배선 — 회복 불능")
	else:
		# 앉기 자격 판정(Area 진입)과 호스트 회복 검증이 같은 반경을 읽게 — def가 단일 소스 (rules §3).
		# ⚠ shape 리소스는 공유라 duplicate 후 적용 (mob_melee body_radius와 같은 수법)
		var col := $Fire/Collision as CollisionShape2D
		var circle := col.shape.duplicate() as CircleShape2D
		if circle != null:
			circle.radius = def.sit_radius
			col.shape = circle
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.peer_left.connect(func(peer_id: int) -> void: _seated_remote.erase(peer_id))
	_fire.body_entered.connect(_on_fire_body.bind(true))
	_fire.body_exited.connect(_on_fire_body.bind(false))
	var gate := $Gate as Area2D
	gate.body_entered.connect(_on_gate_body.bind(true))
	gate.body_exited.connect(_on_gate_body.bind(false))
	_fire_hint.visible = false
	_gate_hint.visible = false


# 상호작용은 폴링이 아니라 _unhandled_input — UI가 소비한 입력은 여기 안 온다 (마을 게이트 규약)
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _local_in_gate:
		# 게스트의 F는 request_stage가 무시 — 출발 권한은 호스트만 (안내는 진입 시 표시)
		_scene_flow.request_stage(GameState.current_chapter_id, GameState.current_stage_idx + 1)
		return
	if _local_in_fire:
		var me := _peer_sync.player(Net.my_id)
		if me != null and me.is_alive():
			me.seated = not me.seated


func _physics_process(delta: float) -> void:
	var me := _peer_sync.player(Net.my_id)
	if me != null and me.seated != _sit_sent:
		# 상태 변화(수동 토글·이동 입력 자동 해제 둘 다)를 여기서 한 번에 감지해 공지
		_sit_sent = me.seated
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SIT, "on": me.seated})
	if _local_in_fire and me != null:
		_fire_hint.text = "F — 일어나기" if me.seated else "F — 모닥불에 앉기"
	if Net.is_host():
		_host_heal_tick(delta)


# 호스트 전용 — 앉기 공지 + 모닥불 거리(sit_radius) + 생존을 모두 통과한 플레이어만 주기 회복.
# 신뢰 경계(rules §3): G_SIT은 힌트일 뿐 — 거리 검증이 없으면 조작 클라가 맵 반대편에서 회복한다.
func _host_heal_tick(delta: float) -> void:
	if def == null:
		return
	_heal_accum += delta
	if _heal_accum < def.heal_interval_s:
		return
	_heal_accum = 0.0
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p == null or not p.is_alive():
			continue
		var claims_sit := p.seated if p.is_local else bool(_seated_remote.get(p.peer_id, false))
		if not claims_sit:
			continue
		if p.net_anchor().distance_to(_fire.global_position) > def.sit_radius:
			continue
		var health := p.get_node("Health") as HealthComponent
		if health.hp < health.max_hp:
			health.confirm_hp(mini(health.hp + def.heal_amount, health.max_hp))


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if str(data.get(NetSchema.KEY_KIND, "")) == NetSchema.G_SIT:
		_seated_remote[from_id] = bool(data.get("on", false))


func _on_fire_body(body: Node2D, entered: bool) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return
	_local_in_fire = entered
	_fire_hint.visible = entered


func _on_gate_body(body: Node2D, entered: bool) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return
	_local_in_gate = entered
	_gate_hint.text = "F — 다음 스테이지로" if Net.is_host() else "방장이 출발할 수 있어요"
	_gate_hint.visible = entered
