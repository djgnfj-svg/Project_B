extends Node2D
# 바닥 디테일 스캐터 — 사용자 지적 2026-07-26: "바닥이 생각보다 단순함. 지금은 하나로 되어있어서 어색".
# 32px 타일 한 장을 반복하면 패턴이 눈에 띄게 반복된다 → 그 위에 작은 것들(풀포기·자갈·갈라짐·꽃)을
# 흩뿌려 반복을 깬다. **바닥 타일 자체는 그대로 두고 위에 얹기만** 하므로 기존 씬 구조를 안 건드린다.
#
# 🔴 **표시 전용 · 충돌 없음 · 네트워크 0.** 판정에 닿는 것이 하나도 없다(밟히지도, 막지도 않는다).
# 🔴 **결정론적이다** — 고정 시드 RNG를 쓰므로 호스트·게스트 화면의 배치가 같다. `randi()` 전역을
#   쓰면 클라마다 다른 지면이 되고, 그건 "같은 방을 보고 있다"는 감각을 깬다(무해하지만 어긋난다).
# ⚠ z_index는 바닥(-10)과 흔들리는 지형(-3) 사이에 둔다 — 디테일은 밟고 지나가는 무늬지 장애물이 아니다.

# 바닥(-10)·변주 타일(-10) 바로 위, 폴리지(-3)보다 아래. ⚠ 늪(swamp_zone)이 -9라 **같은 층**이다 —
# 보스방처럼 늪이 깔리는 씬에는 뿌리지 마라(흙 무늬가 늪 위에 뜬 것처럼 보인다). rules §5 z 배치.
const Z_INDEX := -9

@export var area: Rect2 = Rect2(-320.0, -180.0, 640.0, 360.0)  # 뿌릴 범위(부모 로컬 좌표)
@export var textures: Array[Texture2D] = []                     # 후보 무늬들 — 비면 아무것도 안 한다
@export var count: int = 70                                     # 뿌릴 개수
@export var rng_seed: int = 20260726                            # 배치 시드 — 씬마다 바꾸면 다른 지면이 된다
@export var min_alpha: float = 0.55                             # 무늬가 바닥에 묻히는 정도(랜덤 범위 하한)
@export var max_alpha: float = 0.95


func _ready() -> void:
	if textures.is_empty() or count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in count:
		var tex := textures[rng.randi_range(0, textures.size() - 1)]
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.position = Vector2(
			rng.randf_range(area.position.x, area.end.x),
			rng.randf_range(area.position.y, area.end.y))
		s.flip_h = rng.randf() < 0.5  # 좌우 반전만 — 회전은 픽셀아트를 뭉갠다(Nearest 필터에서 계단이 생긴다)
		s.z_index = Z_INDEX
		s.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(min_alpha, max_alpha))
		add_child(s)
