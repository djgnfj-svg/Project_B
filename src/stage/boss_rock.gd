extends StaticBody2D
# 낙석(P4) 바위 지형 — 미노 낙석 착탄점에 남는 정적 몸. RockField가 런타임 스폰·셋업(SwampZone 미러).
# 돌진(P3)이 물리로 박는 몸: 그룹 "boss_rock" + collision_layer 1(보스 charge + 각 클라 로컬 플레이어가 로컬 충돌).
# 🔴 데미지 판정 없음 — 지형일 뿐이다(spray 데미지는 boss_strike가 착탄 순간 이미 냈다). ttl 로컬 despawn(네트워크 0).
# 돌진이 박으면 boss.gd가 shatter()를 부른다 → 금 간 프레임 후 부서져 조기 제거.
# 비주얼 = Sprite2D(2프레임: 0 온전 · 1 금 간) + 낙하 연출. 도형 금지(rules §0)라 텍스처로만.

const FALL_HEIGHT := 64.0   # 낙하 연출 시작 높이(px) — 예고는 이미 windup(spray N원)에 떴다
const FALL_TIME := 0.28     # 낙하 연출 시간(초)
# 착지 먼지 FX(rock_dust.png 미러) — 80×48 5프레임, 하단중심 앵커(로컬 40,40). 착지 순간 1회 재생 후 자소멸.
const DUST_FRAMES := preload("res://assets/sprites/fx/rock_dust_frames.tres")
const DUST_GROUND_Y := 20.0  # 먼지 노드 y — 먼지 접지선(하단중심)을 (1.45배 커진) 바위 발밑에 맞춤
const DUST_SCALE := 1.4      # 커진 바위에 맞춰 먼지도 크게

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


# 🔴 **`ttl`이 두 가지를 동시에 정한다 — 수명과 「돌진 표적인가」.** 갈래가 하나뿐인 것이 요점이다:
#   별도 플래그를 두면 `G_ROCK` 페이로드에 필드가 하나 늘고(= 신뢰 표면), 두 값이 어긋난 조합
#   ("영구인데 부술 수 있다")이 생겨 다음 사람이 어느 쪽이 옳은지 모른다.
#   낙석(P4)은 10.0을 넘기므로 두 축 모두 **완전 항등**이다.
static func is_dash_target(ttl: float) -> bool:
	return ttl > 0.0


func setup(p_rid: String, p_world_pos: Vector2, p_radius: float, p_ttl: float, field: Node) -> void:
	rid = p_rid
	_world_pos = p_world_pos
	_radius = p_radius
	_ttl = p_ttl
	_field = field


func _ready() -> void:
	# 돌진 충돌 감지 키 (boss.gd _dash_rock_collision).
	# 🔴 **영구 바위(= 보스방 진입 게이트)는 넣지 않는다 — 지형이지 돌진 표적이 아니다.**
	#   넣으면 P3 돌진(`breaks_rock = false`)이 박는 순간 `_enter_charge_hit` → `_break_rock`으로
	#   **게이트 한 칸이 부서진다.** 5개 중 하나가 빠지면 이웃 간격이 32 → 64px가 되어 겹침이
	#   사라지고 **16px 틈**이 열린다 → 플레이어는 빠져나가는데 보스(반경 63)는 못 따라가
	#   싸움이 성립하지 않는다. 도달 경로도 평범하다: 게이트 앞에 선 플레이어를 P3가 쫓아온다
	#   (`use_max_dist` 420 · `charge_travel_max` 260).
	#   ⚠ 그룹에 없으면 `_dash_rock_collision`이 null을 돌려 **벽과 똑같이** 취급된다 —
	#     그게 게이트에 옳은 의미다(그 함수 주석: "벽은 무시 → 헛참으로 처리").
	if is_dash_target(_ttl):
		add_to_group("boss_rock")
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
	tw.tween_callback(_spawn_dust)   # 착지 순간 — 먼지 확산 + 잔돌
	tw.tween_property(_sprite, "scale:y", 0.86, 0.05)
	tw.tween_property(_sprite, "scale:y", 1.0, 0.08)


# 착지 먼지 — 바위 발밑에 rock_dust puff 1회 재생 후 자소멸(하단중심 앵커라 위로 안 뜬다).
func _spawn_dust() -> void:
	var dust := AnimatedSprite2D.new()
	dust.sprite_frames = DUST_FRAMES
	dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dust.z_index = -1                       # 바위(-2)보다 위, 캐릭터 아래
	dust.scale = Vector2(DUST_SCALE, DUST_SCALE)
	dust.position = Vector2(0, DUST_GROUND_Y)
	dust.play(&"puff")
	dust.animation_finished.connect(dust.queue_free)
	add_child(dust)


func _process(delta: float) -> void:
	if _gone:
		return
	_age += delta
	# 🔴 `ttl <= 0` = **영구**(보스방 진입 게이트). 낙석(P4)은 10.0을 넘기므로 **완전 항등**이고,
	#   0 이하를 넘기는 호출부는 게이트가 유일하다. ⚠ 거대한 ttl(1e9)로 우회하지 마라 —
	#   데이터에 거짓말을 심으면 다음 사람이 "왜 10초가 아니지"를 두 번 묻는다.
	if _ttl > 0.0 and _age >= _ttl:
		_despawn()


# 돌진 충돌 시 boss.gd(_enter_charge_hit)가 호출 — 5단계 파괴 애니(균열→갈라짐→파편→붕괴)를 프레임으로
# 밟고, 붕괴 잔해를 잠깐 보인 뒤 페이드해 사라진다(조기 제거). 프레임 = boss_rock.png 1~4번.
func shatter() -> void:
	if _gone:
		return
	_gone = true
	_collision.set_deferred("disabled", true)   # 부서지는 중엔 더 안 막는다
	var tw := create_tween()
	for f: int in [1, 2, 3, 4]:                  # 균열 → 갈라짐 → 파편 → 붕괴
		tw.tween_callback(_set_frame.bind(f))
		tw.tween_interval(0.07)
	tw.tween_interval(0.16)                       # 붕괴 잔해 잠깐 보여주고
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)


func _set_frame(f: int) -> void:
	_sprite.frame = f


# ttl 만료 로컬 소멸(네트워크 메시지 없음 — 결정만 호스트, despawn은 각 클라 로컬 타이머). 페이드 아웃.
func _despawn() -> void:
	if _gone:
		return
	_gone = true
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
