class_name CampfireDef
extends Resource
# 모닥불 수치 스키마 (core — 리드 전용). 회복량·간격·판정 반경은 GDD §11 TBD —
# 전부 임시값, 사용자가 플레이하며 조인다 (rules §0 — 밸런스 수치는 데이터로).

@export var heal_amount: int = 1          # 틱당 회복량
@export var heal_interval_s: float = 0.8  # 회복 틱 간격 (초)
@export var sit_radius: float = 44.0      # 모닥불 중심에서 이 안이어야 앉기 회복 유효 — 호스트 검증도 같은 값
