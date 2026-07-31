extends StaticBody2D
# 낙석(P4) 바위 지형 — 미노 낙석 착탄점에 남는 정적 몸. RockField가 런타임 스폰·셋업(SwampZone 미러).
# 돌진(P3)이 물리로 박는 몸: 그룹 "boss_rock" + collision_layer 1(보스 charge + 각 클라 로컬 플레이어가 로컬 충돌).
# 🔴 데미지 판정 없음 — 지형일 뿐이다(spray 데미지는 boss_strike가 착탄 순간 이미 냈다). ttl 로컬 despawn(네트워크 0).
# 돌진이 박으면 boss.gd가 shatter()를 부른다 → 금 간 프레임 후 부서져 조기 제거.
# 비주얼 = Sprite2D(2프레임: 0 온전 · 1 금 간) + 낙하 연출. 도형 금지(rules §0)라 텍스처로만.

const FALL_HEIGHT := 64.0   # 낙하 연출 시작 높이(px) — 예고는 이미 windup(spray N원)에 떴다
const FALL_TIME := 0.28     # 낙하 연출 시간(초)

# RockField.setup이 add_child 전에 채운다 — 노드 접근 없이 값만 보관 (@onready 미해결 시점, SwampZone 미러)
var rid: String = ""
var _world_pos: Vector2 = Vector2.ZERO
var _radius: float = 24.0
var _ttl: float = 10.0
var _field: Node = null

var _age: float = 0.0
var _gone: bool = false      # shatter/despawn 진행 중 — 이중 호출·ttl 경합 차단

@onready var _sprite: Sprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision


func setup(p_rid: String, p_world_pos: Vector2, p_radius: float, p_ttl: float, field: Node) -> void:
	rid = p_rid
	_world_pos = p_world_pos
	_radius = p_radius
	_ttl = p_ttl
	_field = field


func _ready() -> void:
	add_to_group("boss_rock")  # 돌진 충돌 감지 키 (boss.gd _dash_rock_collision)
	global_position = _world_pos
	# 판정 반경 = _radius. shape 리소스는 인스턴스 간 공유라 복제 후 적용 (SwampZone 미러, rules §5)
	var shape := _collision.shape.duplicate() as CircleShape2D
	if shape != null:
		shape.radius = _radius
		_collision.shape = shape
	# 낙하 연출 — 위에서 떨어져 앉는다(offset.y 애니 + 착지 스쿼시). 텍스처 프레임0(온전).
	_sprite.frame = 0
	_sprite.offset.y = -FALL_HEIGHT
	var tw := create_tween()
	tw.tween_property(_sprite, "offset:y", 0.0, FALL_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_sprite, "scale:y", 0.86, 0.05)
	tw.tween_property(_sprite, "scale:y", 1.0, 0.08)


func _process(delta: float) -> void:
	if _gone:
		return
	_age += delta
	if _age >= _ttl:
		_despawn()


# 돌진 충돌 시 boss.gd(_enter_charge_hit)가 호출 — 금 간 프레임으로 바꾸고 부서져 사라진다(조기 제거).
func shatter() -> void:
	if _gone:
		return
	_gone = true
	_collision.set_deferred("disabled", true)   # 부서지는 중엔 더 안 막는다
	_sprite.frame = 1                            # 금 간 바위
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_property(_sprite, "scale", Vector2(1.15, 0.5), 0.12)   # 납작하게 부서짐
	tw.parallel().tween_property(_sprite, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)


# ttl 만료 로컬 소멸(네트워크 메시지 없음 — 결정만 호스트, despawn은 각 클라 로컬 타이머). 페이드 아웃.
func _despawn() -> void:
	if _gone:
		return
	_gone = true
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
