class_name EquipDef
extends Resource
# 장비 정의 스키마 (core — 리드 전용). 개체는 data/equipment/*.tres (projectb-rules §4).
# 🔒 장비는 수치만 (GDD §6). 스탯 합산·강화 결과는 CombatMath 단일 소스가 계산 (rules §3).

const SLOT_WEAPON := 0
const SLOT_ARMOR := 1

@export var id: String = ""            # data/equipment/<id>.tres 파일명과 일치 — 인벤/레시피/저장의 키
@export var display_name: String = ""
@export_multiline var description: String = ""  # 아이템 툴팁 설명(선택) — 비면 스탯만 표시 (UI item_ui 헬퍼)
@export var icon: Texture2D            # 제작/강화 UI·인벤 표시 (도형 금지, rules §0)
@export_enum("weapon", "armor") var slot_name: String = "weapon"
@export var job_id: String = ""  # 직업 귀속 — 비면 범용(아무 직업), 값 있으면 그 직업만 착용/제작 가능(전사는 활 못 듦). GameState.can_equip_job 단일 소스

# 기본 수치 + 강화 단계당 증가 (레벨 0 = 미강화). CombatMath.equip_stat_at_level이 base + step*level.
@export var base_attack: int = 0
@export var base_hp: int = 0
@export var atk_per_level: int = 0
@export var hp_per_level: int = 0
@export var max_level: int = 5
@export var upgrade_gold_base: int = 10  # 강화 비용 = base * (다음레벨) — CombatMath.upgrade_cost

# 무기 표시용 (slot=weapon만) — JobDef.weapon_texture/grip을 장비로 이관하는 자리 (rules §3).
# 장비 착용 시 player.gd의 WeaponPivot/Weapon 텍스처를 이걸로 교체 (후속 슬라이스).
@export var weapon_texture: Texture2D
@export var weapon_grip: Vector2 = Vector2(2, 4)
@export var weapon_hold_dist: float = 4.0  # 몸 중심 → 무기 그립까지 거리(px). 큰 무기(활 34px)는 크게 잡아 몸과 안 겹치게(대검=8 기본)

# 공격 모션 타입 (§2 리팩터 게이트, 2026-07-24) — player.gd _do_attack/_update_weapon이 이 값으로 분기한다.
#   "swing" = 근접 호 스윙(대검·기본, 로컬 원형 질의 판정) · "shoot" = 원거리 발사(궁수 활, 화살 스폰·호스트 화살 판정)
#   "charge" = 기 모아 발사(법사 지팡이) — shoot 경로 재사용 + 차지 단계·착탄 폭발(범위). 아래 "차지" 그룹이 수치.
#   "thrust"(찌르기)는 예약 — 추가 시 여기 enum 확장 + _do_attack 분기. 스윙 손맛 필드(아래)는 swing 한정.
@export_enum("swing", "shoot", "charge", "thrust") var motion_type: String = "swing"
@export var arrow_range: float = 360.0  # (shoot/charge 무기) 투사체 최대 사거리(px) — 이 거리 넘으면 소멸(charge는 그 자리에서 폭발). 호스트가 MAX로 clamp(§3)

# 투사체 겉모습·속도 (shoot/charge 공용) — 발사 시 무기 id(G_SHOOT "w")로 각 클라가 리졸브한다.
# ⚠ 텍스처 "경로"는 네트워크로 보내지 않는다 (rules §3) — 무기 id allowlist 리졸브만.
@export var projectile_texture: Texture2D          # 비면 기본 화살 텍스처(arrow.tscn) 사용
@export var projectile_speed: float = 0.0          # 탄속(px/s). 0 = CombatMath.ARROW_SPEED 기본. 표시·호스트 공용(결정론) — CombatMath가 clamp
@export var projectile_spin: bool = false          # true = 진행 방향 회전 대신 자전(구형 마법탄). false = 화살처럼 방향 정렬

# 차지 발사 (motion_type="charge" 한정) — 마우스를 눌러 모으고 놓으면 발사, 착탄 지점에서 범위 폭발.
# 단계별 위력·폭발 반경 배율은 CombatMath.CHARGE_* 공용 상수(§3 단일 소스) — 무기는 "기준값"만 쥔다.
@export_group("차지")
@export var charge_step_time: float = 0.35   # 한 단계 모으는 시간(s). 레벨 = floor(홀드/이 값), 최대 CombatMath.MAX_CHARGE_LEVEL. 호스트의 차지 시간 검증 기준이기도 하다(§3)
@export var blast_radius: float = 0.0        # 0단계 폭발 반경(px). 0 = 폭발 없음(단일 명중 = 화살과 동일). 판정 = 표시 반경 미러(§3)
@export var charge_sfx: String = "charge_step"  # 단계 상승 시 효과음 id (Audio.SFX 키)
@export var blast_sfx: String = "blast"      # 폭발 효과음 id

# 무기 손맛 (slot=weapon만) — 무기별 평타 연출. player.set_weapon_visual이 읽어 로컬·원격 모두 반영.
# ⚠ 손맛 "전역 크기"(셰이크 상한·페이드 시간 등)는 스크립트 const가 정본(rules §0) — 여기 값은
#   "이 무기가 어느 연출을 쓰는가"(콘텐츠·rules §4)와 무게 배율뿐이다. 전부 표시 전용(네트워크 0).
@export_group("무기 손맛")
@export var swing_texture: Texture2D               # 스윙 궤적 FX 트레일 (null → 기본 swoosh_arc 폴백)
@export var swing_tex_radius: float = 23.0         # swing_texture 호 바깥 반지름(px) — 스케일=도달/반지름 정합 (rules §3)
@export var swing_color: Color = Color(1, 1, 1, 1) # 궤적 틴트(그레이스케일 도트 재활용용, 페이드 알파와 곱)
@export var swing_sfx: String = "swing"            # 스윙(휘두름) 효과음 id (Audio.SFX 키)
@export var hit_sfx: String = ""                   # 적중 시 무기 고유 타격음 id (비면 무음 — 범용 피격음은 combat_impact가 별도 재생)
@export var hit_shake: float = 1.5                 # 적중 시 스크린셰이크 강도 (무기 무게감)

# 스윙 모션(휘두르는 동작) — 무기별로 호 넓이·속도·내지르기를 갈라 무게감을 동작으로 표현. 스윙형 한정.
# ⚠ swing_time 계약(rules §3): 반드시 착용 직업의 attack_cooldown보다 짧아야 한다 — 원격 스윙 창-잠금
#   가드(play_attack_fx)가 정당한 연속 공격의 연출을 무시하지 않게. (전사 쿨다운 0.4s)
@export var swing_arc: float = 1.9                 # 스윙 호 반각(rad) — 조준각 기준 ±이만큼 쓸고 지나감 (클수록 넓게)
@export var swing_time: float = 0.25              # 스윙 창 길이(s) — 클수록 느리고 묵직 (반드시 < attack_cooldown)
@export var swing_lunge: float = 5.0             # 스윕 중 앞으로 내지르는 거리(px)


func slot() -> int:
	return SLOT_ARMOR if slot_name == "armor" else SLOT_WEAPON
