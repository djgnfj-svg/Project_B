class_name EnemyDef
extends Resource
# 적 정의 스키마 (core — 리드 전용). 개체 수치는 data/enemies/*.tres가 쥔다 (projectb-rules §4).

@export var display_name: String = ""
@export var max_hp: int = 10
@export var respawns: bool = false        # 허수아비 등 훈련용 — 사망 후 자동 재생성
@export var respawn_delay: float = 3.0
@export var sprite: Texture2D             # 개체 스프라이트 — 씬 1장을 데이터로 재사용 (§4)
@export var frames: SpriteFrames          # 애니 시트(idle/walk/attack/death) — 있으면 sprite보다 우선. 없으면 sprite 1장을 idle로 감싼다

@export var body_radius: float = 6.0      # 몸 판정 반경(px) — 플레이어 공격 원형 질의가 맞는 몸집. 스프라이트 크기와 정합 유지 (48px 브루트 등 덩치 큰 개체용)

# 이동/AI (호스트 전용 구동 — 0 = 고정형). 수치는 전부 임시값 — 사용자가 플레이하며 조인다.
@export var move_speed: float = 0.0
@export var aggro_range: float = 120.0    # 이 안의 가장 가까운 생존 플레이어를 추격
@export var attack_range: float = 28.0    # 이 안이면 WINDUP(텔레그래프) 진입

# 공격 — 기믹 원칙(GDD §5): 텔레그래프 보고 구를 수 있어야 한다
@export var strike_radius: float = 18.0   # 타격 판정 반경 = 텔레그래프 표시 반경 (같은 값 — "맞는 곳=보이는 곳")
@export var attack_damage: int = 5
@export var telegraph_s: float = 0.6      # 예고 길이 — 구르기(0.25s)보다 충분히 길게
@export var attack_cooldown_s: float = 1.2

# --- 원거리 잔몹 (2026-08-01) — "새 원거리 적 = .tres 한 장 + 시트 한 장" (§4) ---
# 판별은 값에서 유도한다: `CombatMath.is_ranged_enemy(def)` = proj_speed > 0 and proj_range > 0.
# 🔴 별도 bool 플래그를 두지 마라 — 두 번째 진실원이 되어 배우 분기와 트립와이어가 갈라진다.
# 전부 기본값 0/null이라 기존 근접 적 전량과 **완전 항등**이다.
@export var proj_speed: float = 0.0     # 화살 속도(px/s). 비행 시간이 곧 회피 창이라 유도할 수 없는 밸런스 값
# ⚠ `attack_range`와 같게 두지 마라 — 발사 시점 좌표에서 수명이 끝나 걷는 플레이어를 영원히 못 맞힌다.
@export var proj_range: float = 0.0     # 소멸 거리(px)
@export var proj_texture: Texture2D     # 화살 스프라이트(§0 도형 금지). null이면 기본 화살 폴백
# 이 거리 안으로 붙으면 물러난다(카이팅). 0 = 제자리 사격(포탑형).
# ⚠ `attack_range`보다 크면 자기 사거리 밖으로 물러나 영구 진동하며 한 발도 못 쏜다.
@export var keep_dist: float = 0.0

# 드랍 테이블 (골드·일반/핵심 재료·도면) — 없으면 드랍 없음. 호스트만 롤 (rules §1·§3). "새 적 = 파일 한 장" (§4)
@export var drop_table: DropTable

# 처치 시 파티 전원에게 주는 EXP (GDD §6 v1.8). 0 = EXP 없음. BossDef가 상속한다.
# ⚠ respawns=true(허수아비)는 EXP를 주지 않는다 — 값이 아니라 **코드**로 차단한다(ExpAuthority, rules §5 무한 파밍 함정).
@export var exp: int = 0
