extends Node2D
# 바닥 변주 타일 깔기 — 기존 바닥 Sprite2D(한 장 반복) 위에 변주 타일 A/B를 32px 그리드로 띄엄띄엄
# 덮어 **패턴 반복을 깬다**. 사용자 지적 2026-07-26: "바닥이 하나로 되어있어서 어색".
#
# 🔴 **기존 Ground 노드를 안 건드린다** — 위에 얹기만 하므로 TileMap 도입 없이, 씬 구조 변경 없이 붙는다.
#   (변주 타일은 불투명 심리스라 덮인 자리는 통째로 그 타일이 된다. 아트가 세 장의 평균 휘도를
#   ±1로 맞춰 놨기 때문에 섞여도 체크무늬로 안 읽힌다.)
# 🔴 **결정론적이다** — 고정 시드라 호스트·게스트 지면이 같다(ground_detail과 같은 규약).
# ⚠ z_index는 바닥과 **같은 -10**이다: 같은 부모 안에서 나중에 add_child된 쪽이 위로 그려지므로,
#   이 노드를 씬 트리에서 Ground **아래(뒤)** 에 두면 안 보인다. 반드시 Ground 다음 형제로 둘 것.
# 표시 전용 · 충돌 없음 · 네트워크 0.

const Z_INDEX := -10

@export var area: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)  # 깔 범위(부모 로컬 좌표)
@export var tile_size: float = 32.0                       # 그리드 한 칸 = 타일 크기
@export var variants: Array[Texture2D] = []               # 변주 타일들(A/B). 비면 아무것도 안 한다
@export var fill_ratio: float = 0.34                      # 각 칸이 변주로 덮일 확률(0=전부 원본, 1=전부 변주)
@export var rng_seed: int = 6102026


func _ready() -> void:
	if variants.is_empty() or tile_size <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var cols := int(ceilf(area.size.x / tile_size))
	var rows := int(ceilf(area.size.y / tile_size))
	for cy in rows:
		for cx in cols:
			if rng.randf() >= fill_ratio:
				continue
			var tex := variants[rng.randi_range(0, variants.size() - 1)]
			if tex == null:
				continue
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false  # 그리드에 딱 맞춰야 이음새가 안 생긴다(중심 정렬은 반 픽셀을 만든다)
			s.position = area.position + Vector2(float(cx), float(cy)) * tile_size
			s.z_index = Z_INDEX
			add_child(s)
