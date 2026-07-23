class_name BossPatternDef
extends Resource
# 보스 패턴 정의 스키마 (core — 리드 전용). 패턴 수치는 data/enemies/*.tres의 인라인 sub_resource가 쥔다 (projectb-rules §4).
# 판정 형태(shape)는 combat_math의 판정 함수와 짝: "circle"=is_strike_hit, "cone"=is_hit_in_cone.
# 텔레그래프 표시 반경/각 = 이 값(range·half_angle) — "맞는 곳=보이는 곳" (§3).

@export var id: String = ""              # "swing"/"slam"/"spray" — G_BOSS_ATK "p"·텔레그래프 텍스처 선택 키
@export var shape: String = "circle"     # "circle"(원) | "cone"(전방 부채꼴) — 판정 형태
@export var telegraph_s: float = 1.0     # 예고 길이 — 구르기(0.25s)보다 충분히 길게 (기믹 원칙 §5)
@export var damage: int = 10
@export var range: float = 60.0          # 원 반경 / 부채꼴 사거리
@export var half_angle: float = 0.6      # 부채꼴 반각(rad) — shape=="cone"만 사용

@export var cooldown_s: float = 3.0      # 이 패턴 재사용 대기 (재선택 게이트 — RECOVER와 별개, "빈틈" 방지)
@export var recover_s: float = 0.5       # STRIKE 후 회복(경직) 시간 — 짧게. 이게 길면 공격 사이 보스가 멈춰 서 빈틈이 커진다. 쿨다운(cooldown_s)은 재선택만 막고, 회복은 이 값만큼만
@export var priority: int = 0            # 패턴 선택 우선순위 — 유효 후보 중 높은 게 선택(가까이=평타 우선 등 거리별 역할 분리). 동률이면 range 작은 것
@export var use_min_dist: float = 0.0    # 대상과 이 거리 이상일 때만 선택 후보
@export var use_max_dist: float = 99999.0
@export var min_phase: int = 1           # 이 페이즈 이상에서만 개방 (페이즈2 패턴 = 2)

@export var creates_swamp: bool = false  # 슬램만 true — 착탄 순간 착탄점에 늪 생성 (기믹 연결)
# 여러 원 착탄(물 뿌리기) — burst_count>1이면 산포 반경 안에 원 착탄 여러 발. 솔로 시 party_scale로 개수↓.
@export var burst_count: int = 1
@export var burst_spread: float = 80.0

@export var telegraph_tex: Texture2D     # 형태별 예고 텍스처 (원/부채꼴 — 판정 기하와 정합되게 그림)
