extends Sprite2D
# 표시 화살 — ArrowField가 런타임에 스폰. 결정론적 직선 등속(각 클라 로컬 시뮬, 네트워크 0).
# 명중 판정·데미지는 호스트 권한(CombatAuthority)이 별도로 한다 — 이 노드는 순수 연출(충돌 없음, rules §0 스프라이트).
# 조기 소멸(적중) = ArrowField가 G_ARROW_HIT/arrow_gone_local 수신 시 queue_free.
# 빗나감 = 수명 만료로 각 클라 동시 로컬 정리(같은 속도/사거리 상수 → 결정론, 브로드캐스트 불필요).

signal expired(world_pos: Vector2)  # 수명 만료(빗나감) 직전 — ArrowField가 폭발탄이면 그 자리에 폭발 FX를 얹는다

const SPIN_SPEED := 6.0  # 자전 투사체(마법탄)의 회전 속도(rad/s) — 연출값

var _dir: Vector2 = Vector2.RIGHT
var _speed: float = 0.0
var _life_left: float = 0.0
var _spin: bool = false


# ArrowField._spawn이 add_child 후 부른다 (Sprite2D라 @onready 자식 없음 — 즉시 설정 가능).
# texture/orb_scale/spin = 무기별 탄 겉모습 (EquipDef.projectile_* 리졸브 결과, 전부 표시 전용).
func setup(origin: Vector2, dir: Vector2, speed: float, lifetime: float,
		tex: Texture2D = null, orb_scale: float = 1.0, spin: bool = false) -> void:
	global_position = origin
	_dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	_speed = speed
	_life_left = lifetime
	_spin = spin
	if tex != null:
		texture = tex
	scale = Vector2.ONE * maxf(0.05, orb_scale)
	# 화살은 진행 방향 정렬(우향 +x 규격), 구형 마법탄은 방향 무의미 → 자전만
	rotation = 0.0 if spin else _dir.angle()
	z_index = 1  # 몸(z=1)·바닥(z=-10) 사이가 아니라 몸 높이로 — 투사체가 캐릭터·적 뒤로 묻히지 않게


func _process(delta: float) -> void:
	global_position += _dir * _speed * delta
	if _spin:
		rotation += SPIN_SPEED * delta
	_life_left -= delta
	if _life_left <= 0.0:
		expired.emit(global_position)  # 폭발탄이면 ArrowField가 이 자리에 폭발 FX (호스트도 같은 지점에서 판정)
		queue_free()  # 빗나감 — 각 클라 같은 수명이라 동시 소멸(결정론)
