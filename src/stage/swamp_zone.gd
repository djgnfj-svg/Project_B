extends Area2D
# 늪 존 — 보스 슬램 착탄점에 생기는 감속 장판. SwampField가 런타임에 스폰·셋업한다 (drop_item 미러).
# 물리 레이어 5=enemy_attack, mask 2=player_body (rules §5 배정표 — 적 공격/장판이 플레이어 몸을 mask).
# 로컬 플레이어가 겹치면 player.enter_swamp/exit_swamp만 부른다 — 이동 슬로우는 각 클라 자기 플레이어
#   기준의 로컬 처리(네트워크 0, rules §3: 위치는 각자 소유. 호스트 재검증 불요 — 느려진 위치가 net_anchor로 자연 반영).
# ttl 만료 → queue_free (결정론 — 각 클라 로컬 타이머 despawn, 네트워크 메시지 없음).
# 비주얼 = Sprite2D + 텍스처(도형 금지 rules §0). z_index=-9 (바닥 -10 < 늪 -9 < 텔레그래프 -1 < 몸 0).

const SWAMP_TEX_SIZE := 96.0  # swamp_pool.png 한 변(px) — 스케일 기준 (텍스처와 미러)

# SwampField.setup이 add_child 전에 채운다 — 노드 접근 없이 값만 보관 (@onready 미해결 시점, drop_item 미러)
var sid: String = ""
var _world_pos: Vector2 = Vector2.ZERO
var _radius: float = 40.0
var _ttl: float = 6.0
var _slow: float = 0.5
var _field: Node = null

var _age: float = 0.0
var _local_inside: Node2D = null  # 겹친 로컬 플레이어 캐시 — 서 있는 채 ttl 만료 시 exit를 명시 호출하려고
var _despawning: bool = false     # 소멸 중 — free 시 발화하는 body_exited가 exit_swamp를 이중 호출해 다른 늪 배율을 조기 제거하는 것 차단

@onready var _sprite: Sprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision


func setup(p_sid: String, p_world_pos: Vector2, p_radius: float, p_ttl: float,
		p_slow: float, field: Node) -> void:
	sid = p_sid
	_world_pos = p_world_pos
	_radius = p_radius
	_ttl = p_ttl
	_slow = p_slow
	_field = field


func _ready() -> void:
	global_position = _world_pos
	# 판정 반경 = _radius. shape 리소스는 씬 인스턴스 간 공유라 복제 후 적용 (boss_croc body_radius 미러, rules §5)
	var shape := _collision.shape.duplicate() as CircleShape2D
	if shape != null:
		shape.radius = _radius
		_collision.shape = shape
	# 보이는 웅덩이 지름 ≈ 판정 지름(2*radius) — "맞는 곳=보이는 곳"
	_sprite.scale = Vector2.ONE * (_radius * 2.0 / SWAMP_TEX_SIZE)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _ttl:
		_despawn()  # 로컬 결정론 despawn — 네트워크 메시지 없음


# ttl 만료 소멸 — 서 있는 채 만료되면 body_exited가 안 와 플레이어가 영구 슬로우로 남는다 → 명시 해제.
func _despawn() -> void:
	if _despawning:
		return
	_despawning = true
	if is_instance_valid(_local_inside):
		_local_inside.call("exit_swamp", _slow)
		_local_inside = null
	queue_free()


# 로컬 플레이어만 슬로우 대상 — 원격 아바타/적은 무시 (각 클라 자기 플레이어 기준, drop_item is_local 판별 미러).
func _on_body_entered(body: Node2D) -> void:
	if _despawning or not _is_local_player(body):
		return
	_local_inside = body
	body.call("enter_swamp", _slow)


func _on_body_exited(body: Node2D) -> void:
	if _despawning or not _is_local_player(body):
		return  # 소멸 중이면 _despawn이 이미 exit 처리 — 이중 제거 차단
	if body == _local_inside:
		_local_inside = null
	body.call("exit_swamp", _slow)


func _is_local_player(body: Node2D) -> bool:
	return body.is_in_group("player") and body.get("is_local") == true
