class_name BossDef
extends EnemyDef
# 보스 정의 스키마 (core — 리드 전용). EnemyDef 상속 → max_hp·drop_table·body_radius·sprite·frames·
# aggro_range를 그대로 물려받는다: CombatAuthority(def as EnemyDef)·DropAuthority(def.drop_table)가
# 캐스트/변경 없이 동작한다. 보스 고유(다패턴·페이즈·늪)만 여기 추가. "새 보스 = 파일 한 장" (§4).
# ⚠ EnemyDef의 strike_radius/attack_damage/telegraph_s/attack_range는 안 쓴다(패턴이 대체) — patterns가 정본.

@export var patterns: Array[BossPatternDef] = []
@export var phase2_hp_ratio: float = 0.5         # 이 비율 이하 HP → 페이즈2 (min_phase=2 패턴 개방)

# 늪 기믹 파라미터 (보스 종속 — 별도 SwampDef 불필요). 수치는 GDD §11 TBD, 사용자 실기 튜닝.
@export var swamp_radius: float = 40.0
@export var swamp_slow_factor: float = 0.5       # 늪 안 이동 배율 (1=영향없음, 0.5=절반 속도)
@export var swamp_ttl: float = 6.0               # 늪 지속(초) — 각 클라 로컬 타이머 despawn
@export var swamp_auto_interval_p2: float = 4.0  # 페이즈2 자동 늪 생성 간격(초). 솔로 시 party_scale로 완화
