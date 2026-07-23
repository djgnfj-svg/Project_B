extends Node2D
# 마을 앰비언스 — 표시 전용 품질 레이어 (그림자·벚꽃 낙화·발광 펄스·강 반짝).
# 판정·네트워크 무접촉 — 각 클라 로컬 재생 (feel 계층과 같은 규약, 네트워크 메시지 0).
# 그림자/발광/반짝은 절차 텍스처(GradientTexture2D), 낙화만 기존 에셋(petal.png) 재사용.
# 아래 상수는 전부 연출값 (rules §0 예외 — 사용자가 눈으로 조인다).

const SHADOW_ALPHA := 0.22
const SHADOW_W_RATIO := 0.72   # 그림자 폭 = 스프라이트 폭 대비
const SHADOW_H_RATIO := 0.30   # 납작한 타원 비율 (폭 대비 높이)
const GLOW_PULSE_S := 1.7      # 발광 펄스 주기(초)
const GLOW_PULSE_AMOUNT := 0.25
const PETAL_AMOUNT := 5
const SPARKLE_AMOUNT := 12

var _glows: Array[Sprite2D] = []
var _time: float = 0.0

@onready var _petal_tex: Texture2D = preload("res://assets/sprites/village/nature/petal.png")


func _ready() -> void:
	_add_shadow_pass()
	_add_petals(get_node("../Blossom1") as Sprite2D)
	_add_petals(get_node("../Blossom2") as Sprite2D)
	_add_glow(get_node("../EmberBarrel") as Sprite2D, Color(1.0, 0.55, 0.2, 0.5), 26.0)
	_add_glow(get_node("../Campfire") as Sprite2D, Color(1.0, 0.62, 0.25, 0.55), 34.0)
	_add_river_sparkle()


func _process(delta: float) -> void:
	# 발광 펄스 — 사인파 알파 (타이머/트윈 없이 프레임당 계산, 웹 부담 0)
	_time += delta
	var pulse := 1.0 + GLOW_PULSE_AMOUNT * sin(_time * TAU / GLOW_PULSE_S)
	for g in _glows:
		g.scale = g.get_meta("base_scale") as Vector2 * pulse


# --- 발밑 그림자 (나무·벚꽃·NPC — 세로 실루엣만, 다리/부두 등 평면 소품 제외) ---

func _add_shadow_pass() -> void:
	var targets: Array[Sprite2D] = []
	for child: Node in get_node("../Trees").get_children():
		var s := child as Sprite2D
		if s != null:
			targets.append(s)
	for child: Node in get_node("../Npcs").get_children():
		var s := child as Sprite2D
		if s != null and s.name != "Bobber":  # 물 위 찌는 그림자 없음
			targets.append(s)
	targets.append(get_node("../Blossom1") as Sprite2D)
	targets.append(get_node("../Blossom2") as Sprite2D)
	for s in targets:
		if s == null or s.texture == null:
			continue
		var w := s.texture.get_width() * SHADOW_W_RATIO
		var shadow := Sprite2D.new()
		shadow.texture = _radial_tex(Color(0, 0, 0, SHADOW_ALPHA))
		shadow.scale = Vector2(w / 32.0, w * SHADOW_H_RATIO / 32.0)
		# 발 위치(로컬) = offset 기준 렉트에서 계산 — Y-소트용 발밑 원점 스프라이트
		# (offset=(-w/2,-h))는 foot=(0,0)이 되고, offset 없는 기존 스프라이트도 같은 식으로 맞는다.
		# centered=false: 렉트 좌상단 = offset → foot = offset + (폭/2, 높이). centered: 렉트 중심 = offset → foot = offset + (0, 높이/2)
		var foot := s.offset + (Vector2(s.texture.get_width() * 0.5, float(s.texture.get_height())) \
			if not s.centered else Vector2(0.0, s.texture.get_height() * 0.5))
		shadow.position = foot - Vector2(0.0, 1.0)  # 발보다 1px 위 — 끝단에 걸치게
		shadow.show_behind_parent = true
		s.add_child(shadow)


# --- 벚꽃 낙화 (캐노피 아래로 잎이 흩날림) ---

func _add_petals(tree: Sprite2D) -> void:
	if tree == null or tree.texture == null:
		return
	var p := CPUParticles2D.new()
	p.texture = _petal_tex
	p.amount = PETAL_AMOUNT
	p.lifetime = 3.5
	p.preprocess = 3.5  # 씬 진입 순간부터 흩날리는 중이게
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(tree.texture.get_width() * 0.4, 4.0)
	p.direction = Vector2(0.3, 1.0)
	p.spread = 25.0
	p.gravity = Vector2(0, 9.0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	# 캐노피 상단 중앙 기준 — 렉트 좌상단 = position + scale*offset (centered=false, 발밑 원점이면 offset≠0)
	var top_left := tree.position + tree.scale * tree.offset
	p.position = top_left + Vector2(tree.texture.get_width() * 0.5, tree.texture.get_height() * 0.35)
	add_child(p)


# --- 발광 펄스 (화덕·모닥불 — 가산 블렌드 라디얼) ---

func _add_glow(target: Sprite2D, color: Color, radius: float) -> void:
	if target == null or target.texture == null:
		return
	var g := Sprite2D.new()
	g.texture = _radial_tex(color)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	var base := Vector2(radius / 16.0, radius / 16.0)
	g.scale = base
	g.set_meta("base_scale", base)
	# 렉트 좌상단 = position + scale*offset (centered=false, 발밑 원점이면 offset≠0)
	var top_left := target.position + target.scale * target.offset
	g.position = top_left + Vector2(target.texture.get_width() * 0.5, target.texture.get_height() * 0.45)
	add_child(g)
	_glows.append(g)


# --- 강 반짝 (물결 위 흰 점 깜빡임) ---

func _add_river_sparkle() -> void:
	var p := CPUParticles2D.new()
	p.texture = _radial_tex(Color(0.85, 0.93, 0.97, 0.8))
	p.amount = SPARKLE_AMOUNT
	p.lifetime = 1.4
	p.preprocess = 1.4
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(430.0, 22.0)  # 강 전폭 (river 충돌띠 y≈492 미러)
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.10
	p.position = Vector2(462.0, 492.0)
	add_child(p)


# 라디얼 그라디언트(중심 → 투명) 절차 텍스처 — 32×32 기준, scale로 크기 조절
func _radial_tex(color: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	return tex
