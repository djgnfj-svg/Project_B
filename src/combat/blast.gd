extends Sprite2D
# 폭발 표시 FX (차지 무기 착탄) — ArrowField가 런타임에 스폰. 순수 연출(충돌 없음, rules §0 스프라이트).
# 🔴 크기 계약(rules §3): 스케일 = 판정 반경(CombatMath.charge_blast_radius) / TEX_RADIUS —
#   호스트의 폭발 판정 반경과 이 원의 겉보기 반경이 같아야 "맞는 곳=보이는 곳"이다.
#   blast.png의 원 바깥 반지름이 바뀌면 TEX_RADIUS도 같이 고친다 (텍스처와 미러).

# blast.png(32×32)의 원 바깥 반지름(px) — ⚠ 텍스처와 미러. 값은 캔버스 크기가 아니라 **실측**이다:
# 가장자리를 일부러 울퉁불퉁하게(터지는 형태) 그려서 방향별 외곽이 다르다 → 36방향 평균 실측.
# 캔버스 기준(16)을 쓰면 그려진 원이 판정보다 작아진다("맞는데 안 보임"). 아트를 다시 그리면 재실측할 것.
# 16px 전환(2026-07-26): 텍스처 64→32로 다운스케일, 실측 30.25→15.08 (비율 0.4986) → 상수도 절반.
const TEX_RADIUS := 15.3
const LIFE := 0.26        # 잔상 시간(s) — 연출값(rules §0 예외)
const GROW := 0.18        # 페이드 동안 살짝 더 커지는 비율 — 터지는 느낌

var _life_left: float = 0.0
var _base_scale: float = 1.0


# radius = 판정 반경(px). tint = 무기 색(EquipDef.swing_color 재활용 — 알파는 페이드가 구동).
func setup(world_pos: Vector2, radius: float, tint: Color = Color(1, 1, 1, 1)) -> void:
	global_position = world_pos
	_base_scale = maxf(0.05, radius / TEX_RADIUS)
	scale = Vector2.ONE * _base_scale
	modulate = Color(tint.r, tint.g, tint.b, tint.a)
	z_index = 2  # 몸(z=1) 위 — 폭발이 캐릭터에 가리지 않게
	_life_left = LIFE


func _process(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()
		return
	var t := 1.0 - _life_left / LIFE  # 0 → 1
	scale = Vector2.ONE * (_base_scale * (1.0 + GROW * t))
	modulate.a = 1.0 - t
