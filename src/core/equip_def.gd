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
@export var weapon_grip: Vector2 = Vector2(4, 8)
@export var weapon_hold_dist: float = 8.0  # 몸 중심 → 무기 그립까지 거리(px). 큰 무기(활 34px)는 크게 잡아 몸과 안 겹치게(대검=8 기본)

# 공격 모션 타입 (§2 리팩터 게이트, 2026-07-24) — player.gd _do_attack/_update_weapon이 이 값으로 분기한다.
#   "swing" = 근접 호 스윙(대검·기본, 로컬 원형 질의 판정) · "shoot" = 원거리 발사(궁수 활, 화살 스폰·호스트 화살 판정)
#   "charge" = 기 모아 발사(법사 지팡이) — shoot 경로 재사용 + 차지 단계·착탄 폭발(범위). 아래 "차지" 그룹이 수치.
#   "thrust" = 찌르기(장창, 2026-07-28 구현) — **판정은 "swing"과 완전히 같은 경로다**
#     (`CombatMath.is_projectile_weapon`이 false → 호스트 근접 확정). 갈리는 것은 무기 스프라이트의
#     모션 곡선뿐이다(`player._motion_at`: 각이 아니라 **거리**가 주 모션 + 겨눈 선으로 모인다).
#   🔴 `player._local_combat`의 모션 분기는 **shoot/charge만 명시로 걸러내고 나머지를 근접으로 떨군다** —
#     거기에 `elif motion == "swing"`을 넣으면 찌르기가 **에러 없이 공격 자체를 못 하게** 된다.
#   아래 스윙 손맛·모션 필드는 swing·thrust 공용이다(shoot/charge는 swing_sfx만 재활용).
@export_enum("swing", "shoot", "charge", "thrust") var motion_type: String = "swing"
# (shoot/charge 무기) 투사체 최대 사거리(px) — 이 거리 넘으면 소멸(charge는 그 자리에서 폭발). 호스트가 MAX로 clamp(§3).
# 🔴 **기본값이 0인 것은 안전장치다 — 올리지 마라** (2026-07-27 netreview M4 후속).
#   근접 무기 `.tres`엔 이 필드가 아예 없으므로 기본값이 곧 "근접 무기가 쏠 경우의 사거리"다.
#   전에는 360이어서, 변조 클라가 대검을 공지한 채 G_SHOOT을 쏘면 호스트가 **360px 권한 화살**을
#   전사 공격력으로 확정했다 — 궁수의 정당한 마무리 타(300/306px)보다도 멀었다.
#   0이면 `clamp_arrow_range`가 `MIN_ARROW_RANGE`(40)로 떨어뜨려 **40px짜리 화살**이 된다 = 위협이 아니다.
# 🔴 이 기본값은 `combat_authority`의 발사형 가드(`CombatMath.is_projectile_weapon`)와 **서로 독립인
#   두 번째 층**이다. 가드가 뚫리거나(호출부를 지우거나 새 발사 경로가 생기거나) 해도 여기가 남고,
#   반대도 같다. 🔴 **한쪽을 "이미 막고 있으니 불필요하다"고 지우지 마라** — 특히 가드 쪽은 씬 글루라
#   헤드리스가 겨눌 수 없어서(아래 combat_authority 주석) 이 층이 유일한 자동 방어다.
# ⚠ 발사형 무기는 **반드시 이 값을 명시**해야 한다(안 쓰면 40px 화살). `test_combat_math_auto`가 전수로 지킨다 —
#   빠뜨리면 빨개지고, 설령 새어 나가도 "조용히 멀어짐"이 아니라 "눈에 띄게 짧아짐"이라 방향이 안전하다.
@export var arrow_range: float = 0.0

# 투사체 겉모습·속도 (shoot/charge 공용) — 발사 시 무기 id(G_SHOOT "w")로 각 클라가 리졸브한다.
# ⚠ 텍스처 "경로"는 네트워크로 보내지 않는다 (rules §3) — 무기 id allowlist 리졸브만.
@export var projectile_texture: Texture2D          # 비면 기본 화살 텍스처(arrow.tscn) 사용
@export var projectile_speed: float = 0.0          # 탄속(px/s). 0 = CombatMath.ARROW_SPEED 기본. 표시·호스트 공용(결정론) — CombatMath가 clamp
@export var projectile_spin: bool = false          # true = 진행 방향 회전 대신 자전(구형 마법탄). false = 화살처럼 방향 정렬

# 평타 콤보 리듬 (shoot/charge 무기 — 궁수 "평·평·쭉", 2026-07-27) — 🔴 **리듬은 무기가 정한다.**
# 하위 직업(특성)이 아니라 여기 두는 이유: 리듬 변경은 필연적으로 DPS를 건드리는데 GDD §6 🔒이
#   "특성은 합계 데미지에 곱해지지 않는 축만"이라고 못박고 있다. 장비 축이면 예산 경계를 안 건드리고
#   제작/강화 루프에도 물린다 → **새 활 = .tres 한 장으로 새 리듬**(rules §4).
# 🔴 **셋 다 비면 기존 동작과 완전 항등**(균일 발사) — 법사 지팡이는 비워 두면 지금 그대로다.
# 콤보 길이 = 세 배열 크기의 **최대값**(CombatMath.combo_len) — 한 축만 채워도 된다. 모자란 칸은
#   배율 1.0 · 뜸 0.0으로 채워지므로 길이를 손으로 맞출 필요가 없다.
#
# 🔴 **조항 두 개를 함께 지켜야 한다.** 하나만 읽고 배열을 쓰면 나머지가 조용히 갈라진다
#   (보스 콘 텔레그래프 계약이 "각도"만 적어 둬서 형태·반지름이 갈라졌던 것과 **같은 실패 형태**다 —
#    rules §3의 그 교훈. 그래서 여기 둘을 나란히 적는다. `test_combat_math_auto`가 전수로 지킨다.)
#
#   **㉠ 예산**: `arrow_range × max(combo_range_mult) ≤ MAX_ARROW_RANGE / (1 + TRAIT_MAX["proj_range"])`
#     = 480/1.5 = **320**. 넘기면 `clamp_arrow_range`가 정당한 무기를 **조용히 절삭**한다.
#
#   🔴 **㉡ 비감소(단조 증가)**: `combo_range_mult`·`combo_damage_mult`는 **뒤 타가 앞 타보다 작으면 안 된다.**
#     예: `[1, 1, 2]` ✓ · `[2, 1, 1]` ✗.
#     이유는 손맛이 아니라 **신뢰 경계**다. 호스트는 판정 타수를 `min(주장, 자기 계수)`로 잡아
#     "판정 index ≤ 표시 index"를 보장하는데, 그게 실제로 필요한 **"판정 거리 ≤ 표시 거리"** 로 이어지려면
#     `index → 배율` 사상이 비감소여야 한다. 뒤집힌 배열을 넣으면 min이 오히려 **판정 300px / 표시 150px**
#     (화면에 없는데 맞는다)를 만든다 — `authoritative_combo` 주석이 금지한 바로 그 방향이다.
#     "첫 발이 제일 센 활"을 만들고 싶으면 배열을 뒤집지 말고 **타수 순서를 그렇게 설계**해라(마무리가 곧 3타).
@export_group("평타 콤보")
@export var combo_range_mult: PackedFloat32Array = PackedFloat32Array()   # 타별 사거리 배율 (예: [1, 1, 2] = 3타만 2배)
@export var combo_damage_mult: PackedFloat32Array = PackedFloat32Array()  # 타별 데미지 배율 — confirm_damage 안에서 곱해진다(반올림 1회, §3)
@export var combo_delay: PackedFloat32Array = PackedFloat32Array()        # 그 타 **직전**의 추가 뜸(s). 쿨다운에 더해진다(haste로 같이 짧아짐)

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
# 🔴 **`swing_texture` / `swing_tex_radius`는 2026-07-28에 삭제했다 — 궤적은 이제 셰이더가 그린다**
#   (`assets/shaders/swing_arc.gdshader`). 각·도달을 PNG 픽셀에 박아 두니 `swing_arc`를 튜닝할 때마다
#   갈라졌다 — 실측 격차가 worn +45° / iron +61°였고(양옆 각각 "안 보이는데 맞는" 구역), 창(±17°)처럼
#   좁은 무기는 텍스처 방식으로 아예 성립하지 않는다. 보스 콘 텔레그래프를 텍스처에서 셰이더로
#   옮긴 것과 **같은 판단·같은 이유**다(rules §3). 무늬를 얹고 싶으면 정사각 풀블리드(알파 1)
#   패턴이어야 하고 그건 `player.gd` 변경이다 — **형태를 그린 텍스처는 셰이더 형태를 다시 잘라
#   정합이 깨지므로 데이터 자리를 아예 없앴다.**
@export var swing_color: Color = Color(1, 1, 1, 1) # 궤적 틴트(그레이스케일 도트 재활용용, 페이드 알파와 곱)
@export var swing_sfx: String = "swing"            # 스윙(휘두름) 효과음 id (Audio.SFX 키)
@export var hit_sfx: String = ""                   # 적중 시 무기 고유 타격음 id (비면 무음 — 범용 피격음은 combat_impact가 별도 재생)
# 🔴 **이 무기의 "무게" 단일 소스다** (무기 모션 개편 2026-07-28). 스크린셰이크뿐 아니라 **카메라 킥
#   (`player.HIT_KICK`·`COMBO_FINISH_KICK`)과 적중 시 스윙 박힘(`SWING_BITE_S`)이 전부 여기서 파생한다**
#   — `player._weapon_weight()` = `hit_shake / HIT_SHAKE_REF`. 무게 필드를 따로 만들지 마라: 같은 것을
#   뜻하는 숫자가 둘이 되면 도끼를 무겁게 조였는데 셰이크만 커지고 킥은 그대로인 갈라짐이 생긴다.
# ⚠ 배율 상한 `player.HIT_WEIGHT_MAX`(3.0)에 걸리면 그 위로는 킥·박힘이 안 따라온다(셰이크만 커진다).
@export var hit_shake: float = 1.5                 # 적중 시 스크린셰이크 강도 (무기 무게감)

# 스윙 모션(휘두르는 동작) — 무기별로 호 넓이·속도·내지르기를 갈라 무게감을 동작으로 표현. 스윙형 한정.
# ⚠ swing_time 계약(rules §3): 반드시 착용 직업의 attack_cooldown보다 짧아야 한다 — 원격 스윙 창-잠금
#   가드(play_attack_fx)가 정당한 연속 공격의 연출을 무시하지 않게. (전사 쿨다운 0.4s)
#
# 근접 사거리(px) — 0이면 **직업 기본**(`JobDef.attack_range`)을 쓴다 = 도입 전과 완전 항등.
# 🔴 이 값은 `CombatMath.effective_attack_range(job, reach, equip)` **한 곳에서만** 소비된다 —
#   사거리 3함수가 전부 그 함수를 지나므로 판정·FX·파형이 자동으로 같이 움직인다. 호출부에서
#   `job.attack_range`를 직접 읽으면 창의 긴 사거리가 판정과 표시 중 한쪽에만 걸린다(rules §3).
# ⚠ **`swing_arc`와 짝이다** — 좁은 각을 줬으면 사거리를 늘리고(창), 넓은 각이면 짧게(도끼).
#   한쪽만 키우면 "전방위로 멀리 닿는" 무기가 되어 모션 차별화가 사라진다.
@export var melee_range: float = 0.0
# 🔴 **이 각은 표시이자 판정이다** (무기 모션 축, 2026-07-28). 호스트의 적중 확정과 로컬 질의가
#   `CombatMath.melee_half_angle(equip)`으로 이 값을 읽는다 — **판정용 각 필드를 따로 만들지 마라.**
#   같은 것을 뜻하는 숫자가 둘이 되면 도끼를 넓게 튜닝했을 때 궤적만 넓어지고 판정은 그대로가 된다
#   (보스 콘 텔레그래프가 "각이 픽셀에 박혀 데이터와 갈라진" 그 실패 형태 — rules §3).
#   PI 이상(정확히는 `MELEE_FULL_ARC - MELEE_FULL_ARC_EPS` = 3.13 이상) = 전방위 = 각 검사 없음
#   = **부채꼴 도입 전과 완전 항등**.
# 🔴 **현행 대검 2장은 그 자리에 없다 — 부채꼴이 이미 켜져 있다** (2026-07-28 netreview I-3 정정).
#   실측: `worn_greatsword` = 1.9(필드 없음 → 기본값) · `iron_greatsword` = 2.4. 즉 전사 근접 판정은
#   이 변경으로 **360° → ±109°/±137.5°** 로 좁아졌다(등 뒤 적이 더는 안 맞는다). "항등으로 깔아 두고
#   창이 올 때 켠다"가 아니라 **지금 라이브**이니, 롤아웃 위험을 0으로 읽지 마라.
#   되돌리려면 두 `.tres`에 `swing_arc = 3.2`를 넣으면 된다(그게 진짜 항등이다).
@export var swing_arc: float = 1.9                 # 스윙 호 반각(rad) — 조준각 기준 ±이만큼 쓸고 지나감 (클수록 넓게). **판정 부채꼴의 반각이기도 하다**
@export var swing_time: float = 0.25              # 스윙 창 길이(s) — 클수록 느리고 묵직 (반드시 < attack_cooldown)
@export var swing_lunge: float = 5.0             # 스윕 중 앞으로 내지르는 거리(px)
# 공격 타이밍 = 선딜 / 스윕 / 후딜 (무기 모션 개편 2026-07-28) — 🔴 **표시 전용이 아니다.**
#   `swing_time`을 세 구간으로 나눈 비율이고, 🔴 **판정이 나가는 순간이 「선딜 + 스윕」이 끝나는
#   시점**이다(`player._tick_swing_motion` → `_resolve_swing_hit`). 전에는 클릭한 그 프레임에
#   판정이 끝나고 모션은 뒤에 재생될 뿐이라, 판정·궤적·칼이 각을 훑는 구간이 **셋 다 어긋나**
#   있었다. "칼이 지나갈 때 맞는다"로 정렬한 것이다.
#   · 선딜(windup) = 칼을 젖힌다 · 궤적 없음 · 판정 없음 (구르기로 취소 가능)
#   · 스윕(strike) = 칼이 각을 훑고 궤적이 그 뒤를 따라 자란다 → **끝나는 순간 판정 확정**
#   · 후딜(recover) = 1 − 선딜 − 스윕 (파생이라 필드가 없다). 칼을 회수 — **이동은 안 막는다**
#     (막으면 GDD §6 🔒 화력 예산에 닿는다). 재공격 금지는 `attack_cooldown`이 이미 한다.
# 🔴 도달 지연(클릭 → 판정) = `swing_time × (windup + strike)`. 키우면 손맛이 무거워지고
#   **선딜 중 적이 빠져나가 헛치는 일이 늘어난다** — 무게의 대가다(사용자가 조이는 값).
# 🔴 **여기서 도달·각을 늘리려 하지 마라** — 그 순간 "보이는 곳 ≠ 맞는 곳"이 된다(rules §3).
# 🔴 기본값이 개편 전 하드코딩 값 그대로다 — 무기가 값을 안 주면 **완전 항등**이다.
# ⚠ 세 구간이 전부 양수 폭이어야 한다(합 < 1). 어기면 `player._apply_motion_shape`가 코드로 clamp해
#   사고는 막지만 **clamp는 조용하다** — `test_combat_math_auto`의 「★모션 곡선 전수」가 빨개진다.
@export var swing_windup_ratio: float = 0.28   # 선딜이 스윙 창에서 차지하는 비율
@export var swing_strike_ratio: float = 0.47   # 스윕 구간 비율
# 스윕 이징 — 무기 성격이 여기서 갈린다. 모르는 값은 smooth로 떨어진다(항등 폴백).
#   smooth = 균등한 큰 호(대검) · accel = 천천히 들었다 확 내리꽂는다(도끼) · decel = 튀어나가 멎는다(찌르기)
@export_enum("smooth", "accel", "decel") var swing_ease: String = "smooth"
# 선딜에 무기를 **뒤로 당기는** 거리(px) — `motion_type = "thrust"`의 주 모션이다.
# 0 = 개편 전과 항등(베기 무기는 0). ⚠ 찌르기인데 0이면 "앞으로 미는 베기"가 되어 창이 다시 검처럼
# 보인다 — `test_combat_math_auto`의 「★근접 모션 전수」가 막는다.
@export var swing_pull: float = 0.0
# 궤적 룩 — 🔴 **배율만 둔다.** 절대값을 데이터에 두면 `player.gd`의 전역 크기 const(SWING_FX_*)와
# 진실원이 둘이 되어, 사용자가 const를 조여도 무기들이 안 따라온다(rules §0 "손맛 전역 크기는 const").
# ⚠ 여기 둘은 **밴드 안쪽 시작·칼끝 밝기**뿐이다 — 바깥 반지름과 각(= 판정)을 무기 데이터로 넓히는
# 자리는 **일부러 없다**.
@export var swing_fx_inner_mult: float = 1.0   # 작을수록 길게 뻗은 자국(찌르기), 클수록 얇은 띠
@export var swing_fx_tip_mult: float = 1.0     # 클수록 칼끝이 도드라진다


func slot() -> int:
	return SLOT_ARMOR if slot_name == "armor" else SLOT_WEAPON
