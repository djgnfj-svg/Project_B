class_name EnemyDef
extends Resource
# 적 정의 스키마 (core — 리드 전용). 개체 수치는 data/enemies/*.tres가 쥔다 (projectb-rules §4).

@export var display_name: String = ""
@export var max_hp: int = 10
@export var respawns: bool = false        # 허수아비 등 훈련용 — 사망 후 자동 재생성
@export var respawn_delay: float = 3.0
@export var sprite: Texture2D             # 개체 스프라이트 — 씬 1장을 데이터로 재사용 (§4)
@export var frames: SpriteFrames          # 애니 시트(idle/walk/attack/death) — 있으면 sprite보다 우선. 없으면 sprite 1장을 idle로 감싼다

# 이동/AI (호스트 전용 구동 — 0 = 고정형). 수치는 전부 임시값 — 사용자가 플레이하며 조인다.
@export var move_speed: float = 0.0
@export var aggro_range: float = 120.0    # 이 안의 가장 가까운 생존 플레이어를 추격
@export var attack_range: float = 28.0    # 이 안이면 WINDUP(텔레그래프) 진입

# 공격 — 기믹 원칙(GDD §5): 텔레그래프 보고 구를 수 있어야 한다
@export var strike_radius: float = 18.0   # 타격 판정 반경 = 텔레그래프 표시 반경 (같은 값 — "맞는 곳=보이는 곳")
@export var attack_damage: int = 5
@export var telegraph_s: float = 0.6      # 예고 길이 — 구르기(0.25s)보다 충분히 길게
@export var attack_cooldown_s: float = 1.2
