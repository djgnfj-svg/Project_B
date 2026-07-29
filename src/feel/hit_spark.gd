extends Node2D
# 타격 스파크 (src/feel) — `combat_impact` 구독, 피격 지점(월드 좌표)에 터지는 섬광.
# 🔴 **표시 전용·각 클라 로컬 — 네트워크 메시지 0개**(rules §2 손맛 계층). 판정 코드에 연출을 섞지
#   않는다는 규약대로 훅을 **구독만** 한다. i-frame 중에는 호스트가 데미지를 확정 안 해 훅이 안 와
#   거짓 스파크가 자동으로 안 뜬다.
#
# 오토로드 Node2D인 이유는 `damage_numbers`와 같다: /root 아래라 현재 Camera2D의 캔버스 변환을 그대로
#   받아 월드 좌표에 그려진다(스테이지 3종을 안 건드리고 전 씬 커버). 전투 없는 씬(로비·마을)에선
#   훅이 안 와 아무것도 안 한다.
#
# ⚠ **근접 전용이 아니다** — 화살·폭발·보스 공격까지 모든 피격에 뜬다. 타격이 있는 곳에 항상 반응이
#   있는 편이 액션감에 맞아 필터를 두지 않았다. 근접만 원하면 `kind`가 아니라 훅에 축을 늘려야 한다
#   (`combat_impact`는 "누가 맞았나"만 알고 "무엇에 맞았나"는 모른다).
#
# 연출값 = 스크립트 const (rules §0 예외 — 사용자가 조인다).

# 🔴 `assets/sprites/fx/hit_spark.png`는 **240×48 = 48px 5프레임 가로 시트**다 — `HFRAMES`가 그
#   프레임 수와 **미러**다. 시트를 다시 그려 프레임 수가 바뀌면 이 상수도 같이 고쳐야 한다
#   (안 고치면 에러 없이 엉뚱한 칸이 잘려 나온다 — `blast.png`의 `TEX_RADIUS`와 같은 함정).
const TEX := preload("res://assets/sprites/fx/hit_spark.png")
const HFRAMES := 5

const LIFE := 0.20          # 한 번 터지고 사라지기까지(초) — 짧아야 다음 타격과 안 겹친다
const BASE_SCALE := 1.80    # 48px 원본 기준 배율 → 화면 86px (캐릭터 32px의 약 2.7배)
const CRIT_SCALE := 1.45    # 치명타는 크게 — 굴림은 호스트가 이미 확정했다(여기서 다시 굴리지 않는다)
# 🔴 시트는 **중립 그레이스케일**이라 색을 여기서 입힌다(`blast.png`와 같은 관례). 무기 원소색이
#   생기면 그때 `EquipDef.swing_color`를 태우면 되고, 그 자리는 이 딕셔너리 하나다.
const COLORS := {
	"enemy": Color(1.0, 1.0, 1.0),      # 적이 맞음 = 흰 섬광
	"player": Color(1.0, 0.45, 0.38),   # 내가 맞음 = 붉게 (damage_numbers와 같은 부호)
}
const CRIT_COLOR := Color(1.0, 0.88, 0.42)  # 금색 — 데미지 숫자의 치명 색과 맞춘다
const Z := 90               # 데미지 숫자(100) 아래, 몸·무기 위


func _ready() -> void:
	EventBus.combat_impact.connect(_on_impact)


func _on_impact(kind: String, world_pos: Vector2, amount: int, crit: bool) -> void:
	if amount <= 0:
		return
	var s := Sprite2D.new()
	s.texture = TEX
	s.hframes = HFRAMES
	s.frame = 0
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 전 게임 도트와 같은 계단
	s.z_index = Z
	s.position = world_pos
	# 방사형이라 매번 돌려 주면 연타해도 같은 그림이 반복되지 않는다(표시 전용 난수 — 판정 무관).
	s.rotation = randf() * TAU
	s.scale = Vector2.ONE * (BASE_SCALE * (CRIT_SCALE if crit else 1.0))
	s.modulate = CRIT_COLOR if crit else COLORS.get(kind, Color.WHITE)
	add_child(s)
	var tw := s.create_tween()
	# `frame`은 int라 Tween이 반올림해 칸을 넘긴다 — 5칸이 LIFE 동안 균등하게 지나간다.
	tw.tween_property(s, "frame", HFRAMES - 1, LIFE)
	tw.parallel().tween_property(s, "modulate:a", 0.0, LIFE).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)
