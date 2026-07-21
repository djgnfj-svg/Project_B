class_name EnemyDef
extends Resource
# 적 정의 스키마 (core — 리드 전용). 개체 수치는 data/enemies/*.tres가 쥔다 (projectb-rules §4).

@export var display_name: String = ""
@export var max_hp: int = 10
@export var respawns: bool = false        # 허수아비 등 훈련용 — 사망 후 자동 재생성
@export var respawn_delay: float = 3.0
