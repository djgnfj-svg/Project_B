class_name BossPatternDef
extends Resource
# 보스 패턴 정의 스키마 (core — 리드 전용). 패턴 수치는 data/enemies/*.tres의 인라인 sub_resource가 쥔다 (projectb-rules §4).
# 판정 형태(shape)는 combat_math의 판정 함수와 짝: "circle"=is_strike_hit, "cone"=is_hit_in_cone.
# 텔레그래프 표시 반경/각 = 이 값(range·half_angle) — "맞는 곳=보이는 곳" (§3).

@export var id: String = ""              # "swing"/"slam"/"spray" — G_BOSS_ATK "p"·동명 공격 애니 선택 키
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
@export var center_self: bool = false    # 도끼 회전(P5)만 true — circle 판정 중심 = 보스 자신(전방위 근접). false면 circle은 대상(anchor)에 찍힌다(슬램)
@export var leaves_rock: bool = false    # 낙석(P4)만 true — 착탄점에 바위 지형이 남는다(돌진 유도용). burst_count>1 spray와 짝
@export var rock_radius: float = 24.0    # 남는 바위 충돌 반경(px) — 돌진이 박는 몸
@export var rock_ttl: float = 10.0       # 바위 지속(초) — 이 뒤 로컬 despawn (돌진에 박히면 shatter로 조기 제거)
# 여러 원 착탄(물 뿌리기) — burst_count>1이면 산포 반경 안에 원 착탄 여러 발. 솔로 시 party_scale로 개수↓.
@export var burst_count: int = 1
@export var burst_spread: float = 80.0

# --- 돌진(P3) 전용 (minotaur_patterns.md §3-1). 순수 데이터로 못 넣는 이동·스윕·분기 파라미터. ---
# 🔴 is_charge=true면 boss.gd가 기본 STRIKE 경로(_fire_strike)를 **안 타고** 돌진 서브상태(CHARGE_DASH→
#   CHARGE_HIT/RECOVER)로 분기한다. 예고(WINDUP)는 shape=="cone"의 좁은 부채꼴을 "경로 예고(긁힘 선)"로
#   재사용한다 — range=이동거리·half_angle=길이 폭. 실제 위협 판정은 스윕 원(charge_sweep_radius)이라
#   "맞는 곳=보이는 곳"이 이동 패턴에선 근사(경로 표시)임에 주의(이동 히트박스는 정적 예고 불가).
@export var is_charge: bool = false
@export var charge_speed: float = 220.0        # 돌진 속도(px/s)
@export var charge_sweep_radius: float = 70.0  # 돌진 중 몸 주위 스윕 판정 반경(원) — 플레이어당 돌진 1회 피격
@export var charge_travel_max: float = 260.0   # 최대 이동 거리(px) — 이만큼 가면 헛참(RECOVER)
@export var groggy_s: float = 3.0              # 바위에 박았을 때 그로기(무방비 처벌창) 지속(s)

# 🔴 예고 텍스처 필드는 없다 (2026-07-27 제거). 표시 기하는 위의 shape·range·half_angle에서
# `boss.gd`의 `_apply_telegraph_geometry()` + `boss_telegraph.gdshader`가 **직접 그린다** — 텍스처에
# 각이 박혀 데이터와 갈라지던 결함(68.6° 텍스처 vs 85.9° 판정 = range 130에서 19px 무예고 피격)의
# 근본 원인이 필드 자체였다. 예고 무늬를 얹고 싶으면 형태를 그린 텍스처가 아니라 **정사각 풀블리드**
# 패턴을 새 필드로 추가해라(형태를 그린 알파는 셰이더 형태를 다시 잘라 정합을 깬다).
