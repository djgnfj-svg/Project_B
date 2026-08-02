extends Node
# 잔몹 타격 순간 충격파 (src/feel) — 예고가 다 찬 **그 프레임**에 타격 원 자리에서 터진다.
# preload로만 쓴다 — `class_name` 금지(rules §0).
#
# 🔴 **표시 전용 · 각 클라 로컬 — 네트워크 메시지 0개**(rules §2 손맛 계층). 판정·확정은
#   `EventBus.mob_strike` → `CombatAuthority`가 **따로** 한다. 여기서 데미지·상태를 건드리지 않는다.
#
# 🔴 **`EventBus.mob_strike`에 매달지 마라 — 그 시그널은 호스트 전용 emit이다**(event_bus.gd:31).
#   구독하면 **호스트 화면에만** 충격파가 뜨고 게스트는 아무것도 못 본다 = 두 화면이 갈라진다.
#   대신 각 클라가 **자기 예고 카운트다운이 0이 되는 순간** 로컬로 부른다(`mob_melee`가 호출부).
#   그 순간이 실제 확정과 정렬되는 근거는 §3 지연 보상이다 — 호스트가 `strike_delay_s`만큼 타격을
#   늦추고 게스트는 편도 지연만큼 늦게 예고를 시작하므로, **양쪽 예고가 같은 순간에 끝난다.**
#
# 🔴 크기는 호출부가 `EnemyDef.strike_radius`(= `CombatMath.is_strike_hit`의 판정 반경, §3)를 그대로
#   넘긴다. 여기 상수는 전부 **시간·두께·색**뿐이다 — 반지름 배율을 만들지 마라(연출값 = rules §0 예외).

const TelegraphFx := preload("res://src/feel/telegraph_fx.gd")
const SHADER := preload("res://assets/shaders/mob_strike.gdshader")

# 연출값 (rules §0 예외 — 사용자가 조인다, docs/TUNING.md 대상)
const LIFE := 0.22           # 터지고 사라지기까지(초) — 다음 공격(쿨다운 1.2s)과 안 겹치게 짧게
const RING_PX := 4.0         # 충격파 링 두께(월드 px)
const CORE_END := 0.34       # 중심 섬광이 사라지는 진행도
const FADE_START := 0.55
const CORE_COLOR := Color(1.000, 0.945, 0.812, 0.880)  # 흰-크림 섬광
const RING_COLOR := Color(1.000, 0.494, 0.208, 0.950)  # 주황 충격파
# 쿼드 여유 — 링 끝이 잘리지 않게. 유도 근거는 `telegraph_fx.quad_span` 주석이 정본이다.
const AA_PX := 1.0
const QUAD_MARGIN_PX := 1.0
# z = -1 : 예고 장판과 **같은 층**이다(바닥 -10 위 · 그림자 -2 위 · 몸 0 아래, rules §5 z표).
# 🔴 몸 위로 올리지 마라 — 이건 땅에 떨어지는 충격이고, 위로 올리면 잔몹 8~10마리 칸에서
#   화면이 통째로 가려진다.
const Z := -1


# `parent` = 스테이지 루트(잔몹의 부모). 🔴 몹의 자식으로 붙이지 마라 — 몸이 추격·넉백으로
#   움직이면 충격파가 끌려가 「보이는 충격 ≠ 맞은 자리」가 된다(예고가 `_reassert_telegraph_pos`로
#   막고 있는 것과 정확히 같은 함정). 몹이 그 프레임에 죽어 free돼도 충격파는 제 수명을 산다.
static func burst(parent: Node, world_pos: Vector2, radius_px: float) -> void:
	if parent == null or not parent.is_inside_tree() or radius_px <= 0.0:
		return
	var spr := Sprite2D.new()
	spr.z_index = Z
	# 쿼드·centered·**균일** scale 규약은 예고와 **같은 함수**를 지난다(사본 금지 — 갈라지면
	# 정원이 타원이 되거나 링 끝이 잘린다).
	TelegraphFx.fit_quad(spr, TelegraphFx.quad_span(radius_px, AA_PX, QUAD_MARGIN_PX))
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"quad_px", TelegraphFx.quad_span(radius_px, AA_PX, QUAD_MARGIN_PX))
	mat.set_shader_parameter(&"radius_px", radius_px)
	mat.set_shader_parameter(&"progress", 0.0)
	mat.set_shader_parameter(&"ring_px", RING_PX)
	mat.set_shader_parameter(&"aa_px", AA_PX)
	mat.set_shader_parameter(&"core_end", CORE_END)
	mat.set_shader_parameter(&"fade_start", FADE_START)
	mat.set_shader_parameter(&"core_color", CORE_COLOR)
	mat.set_shader_parameter(&"ring_color", RING_COLOR)
	spr.material = mat
	parent.add_child(spr)
	spr.global_position = world_pos
	# 🔴 `progress`를 트윈이 민다 — **`TIME`을 쓰지 않는다.** 노드마다 자기 수명이 있어야 겹쳐 터진
	#   충격파가 각자 옳고, 위상이 클라 시계에 묶이지 않는다(예고 `progress` 규약과 같은 부호).
	# ⚠ 트윈을 `spr`에 묶어 두면 스프라이트가 free될 때 같이 죽는다(고아 트윈 없음).
	var tw := spr.create_tween()
	tw.tween_method(
		func(v: float) -> void: mat.set_shader_parameter(&"progress", v),
		0.0, 1.0, LIFE)
	tw.tween_callback(spr.queue_free)
