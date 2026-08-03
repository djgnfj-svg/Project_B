class_name BossPatternDef
extends Resource
# 보스 패턴 정의 스키마 (core — 리드 전용). 패턴 수치는 data/enemies/*.tres의 인라인 sub_resource가 쥔다 (projectb-rules §4).
# 판정 형태(shape)는 combat_math의 판정 함수와 짝: "circle"=is_strike_hit, "cone"=is_hit_in_cone.
# 텔레그래프 표시 반경/각 = 이 값(range·half_angle) — "맞는 곳=보이는 곳" (§3).

@export var id: String = ""              # "swing"/"slam"/"spray" — G_BOSS_ATK "p"·동명 공격 애니 선택 키
@export var shape: String = "circle"     # "circle"(원) | "cone"(전방 부채꼴) | "capsule"(띠 — 횡단 돌진 예고)
# 🔴 **"capsule"은 표시 전용 형태다** — 판정은 여전히 **이동하는 원**(`charge_sweep_radius`)이고
#   캡슐은 그 원이 경로를 따라 쓸고 간 **합집합**이다. 부채꼴로는 원리적으로 못 맞춘다(apex가
#   보스에 붙어 있어 경로 띠를 덮지 못한다). 「판정 ⊆ 표시」는 가리비 부등식으로 증명된다 —
#   `half_len_px = 0`이면 원·콘과 **비트 단위 항등**이라 기존 패턴은 안 바뀐다(설계 §3-6·§3-7).
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

# --- 횡단 돌진 확장 (2026-08-02 · docs/plans/active/2026-08-02-boss-dash-pattern.md) ---
# 🔵 **기본값이 전부 현행 P3와 항등이다** — 값을 안 적은 기존 `.tres`는 한 픽셀도 안 바뀐다.
#   새 패턴(`pat_cross`)만 이 칸들을 채운다.

# 도달 후에도 제자리 회전을 유지할 **총** 시간(s). P3 = 1.0(옛 `CHARGE_SPIN_TIME` 상수) · 횡단 = 0.0.
# 🔴 **이 필드가 세 가지를 동시에 닫는다**(설계 §3-2): ⑴ 상수 고정이라 **속도를 낮추는 순간 조용히
#   미완주**가 되던 것 ⑵ 완주 후 남는 죽은 시간 ⑶ 🔴 **도달 후에도 `boss_sweep`이 매 프레임 나가
#   그 자리가 계속 위험하던 것**(P3에선 의도 — 도끼를 휘두르며 돈다. 횡단에선 아니다).
# 🔴 소비 측 유도에서 `maxf`를 빼지 마라 —
#   `_state_left = maxf(charge_spin_s, charge_travel_max / charge_speed + CHARGE_TIMEOUT_MARGIN)`.
#   빼면 P3가 1.0 → 0.92s로 **조용히 짧아진다**(회귀).
@export var charge_spin_s: float = 1.0
# 왕복 횟수. 1 = 현행(한 번 긋고 끝). 🔴 회차 카운터는 `dash_seq`(1회 히트 dedup)가 **아니다** —
#   그쪽을 재사용하면 회차마다 같은 플레이어를 다시 못 때린다.
@export var charge_repeat: int = 1
# 회차마다 예고를 줄이는 비율(0 = 안 줄임). 🔴 하한은 `CombatMath`가 쥐고 근거는 `ROLL_TIME_S`다 —
#   예고가 구르기보다 짧아지면 「예고를 읽고 구른다」(GDD §5)가 **원리적으로** 불가능해진다.
@export var charge_speedup: float = 0.0
# 아레나 가장자리로 붙는 접근 속도(px/s). 0 = 접근 단계 없음 = P3 항등.
@export var charge_approach_speed: float = 0.0
# 조준 방식 — "nearest"(현행 폴백) | "host". 🔴 **폴백이 계약이다**(호스트 사망 시 대상 없음).
#   ⚠ 조준 결과는 `x/y/a`로만 나가므로 **모드를 바꿔도 네트워크 표면은 0**이다.
@export var target_mode: String = "nearest"
# 이 패턴이 **넓은 화면**을 요구하는가 → `EventBus.boss_wide_view` → `NetSchema.G_BOSS_VIEW`.
# 🔴 카메라는 "누구의 패턴인가"를 안 본다 — "이 화면에서 보여줄 가치가 있는가"만 본다.
#   시간이 아니라 **신호**인 이유: 이 패턴은 길이가 회차·지연 보상에 따라 가변이라 상수로 불가능하다.
@export var wide_view: bool = false
# 돌진이 바위를 **부수고 그대로 지나가는가**(true) — false면 현행 P3(박고 그로기)와 항등.
# 🔴 `shatter()`가 콜리전을 즉시 끄므로 통과는 공짜지만, **수직 고정이 없으면 한 프레임 슬라이드로
#   「판정 ⊆ 표시」가 깨진다.** 고정은 `move_and_slide()` **뒤** · `boss_sweep.emit` **앞**(순서가 계약).
@export var breaks_rock: bool = false
# 질주(CHARGE_DASH) 중 아레나 랜덤 위치에 낙석을 떨어뜨리는 간격(초). 0 = 없음 = **완전 항등**
# (기존 P3·spray는 한 픽셀도 안 바뀐다).
# 🔴 **반경·수명은 위의 `rock_radius`/`rock_ttl`을 그대로 재사용한다 — 전용 필드를 만들지 마라.**
#   같은 바위인데 크기를 두 곳에서 정하면 다음 튜닝에서 갈라지고, `G_ROCK` 페이로드는 이미 그 둘을
#   싣고 있어 새 필드는 곧 신뢰 표면이다(게이트 바위의 「ttl 한 축」 판단과 같은 이유).
# 🔴🔴 **`rock_ttl > 0`이 계약이다** — `BossRock.is_dash_target(ttl)`가 `ttl > 0`으로 「돌진 표적인가」와
#   「영구인가」를 **동시에** 정하므로, 0 이하를 넘기면 낙석이 **보스방 진입 게이트와 같은 영구 지형**이
#   되어 아레나에 영구히 쌓인다. 전수 트립와이어가 지킨다.
# 🔴 개수 상한 = `CombatMath.dash_rock_count()` ≤ `MAX_DASH_ROCKS_PER_RUN`. 간격을 줄이면 위험이
#   커지는 것이 아니라 **구를 자리가 없어진다**(낙석은 판정 없는 정적 몸이다).
@export var dash_rock_interval: float = 0.0

# 🔴 예고 텍스처 필드는 없다 (2026-07-27 제거). 표시 기하는 위의 shape·range·half_angle에서
# `boss.gd`의 `_apply_telegraph_geometry()` + `boss_telegraph.gdshader`가 **직접 그린다** — 텍스처에
# 각이 박혀 데이터와 갈라지던 결함(68.6° 텍스처 vs 85.9° 판정 = range 130에서 19px 무예고 피격)의
# 근본 원인이 필드 자체였다. 예고 무늬를 얹고 싶으면 형태를 그린 텍스처가 아니라 **정사각 풀블리드**
# 패턴을 새 필드로 추가해라(형태를 그린 알파는 셰이더 형태를 다시 잘라 정합을 깬다).
