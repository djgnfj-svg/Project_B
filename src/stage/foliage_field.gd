extends Node2D
# 흔들리는 지형 오브젝트 뿌리기 — foliage.tscn을 결정론적으로 배치한다.
# 씬에 손으로 열몇 개를 놓는 대신 여기서 한다: 밀도·범위를 한 줄로 조절할 수 있고, 스테이지가 늘어도
# 복붙이 안 생긴다(rules §2 "복사 금지"와 같은 이유).
#
# 🔴 **결정론적이다** — 고정 시드라 호스트·게스트가 같은 자리에서 같은 풀을 본다.
# 🔴 **스폰 제외 영역**을 받는다 — 플레이어 스폰·게이트 앞에 덤불이 돋아 시야를 가리는 것 방지.
# ⚠ 각 인스턴스는 Area2D(감지 전용, collision_layer=0)라 판정에 아무 영향이 없다. 표시 전용·네트워크 0.

@export var foliage_scene: PackedScene
@export var area: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)
@export var textures: Array[Texture2D] = []   # 후보 겉모습(풀·덤불·나무). 비면 아무것도 안 한다
@export var count: int = 18
@export var rng_seed: int = 917
@export var exclude: Array[Rect2] = []        # 이 사각형들 안에는 안 심는다(스폰 지점·게이트 등)


func _ready() -> void:
	if foliage_scene == null or textures.is_empty() or count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var placed := 0
	var tries := 0
	# 제외 영역에 걸리면 다시 뽑는다 — 무한 루프를 막으려 시도 횟수에 상한을 둔다(빽빽한 제외 영역 대비).
	while placed < count and tries < count * 12:
		tries += 1
		var p := Vector2(
			rng.randf_range(area.position.x, area.end.x),
			rng.randf_range(area.position.y, area.end.y))
		var blocked := false
		for r: Rect2 in exclude:
			if r.has_point(p):
				blocked = true
				break
		if blocked:
			continue
		var tex := textures[rng.randi_range(0, textures.size() - 1)]
		if tex == null:
			continue
		var f := foliage_scene.instantiate() as Node2D
		if f == null:
			continue
		f.position = p
		f.set("sprite_texture", tex)
		# 바람 위상을 개체마다 흩어 놓는다 — 같으면 숲 전체가 한 몸처럼 움직여 인형처럼 보인다.
		f.set("wind_phase", rng.randf_range(0.0, TAU))
		add_child(f)
		placed += 1
