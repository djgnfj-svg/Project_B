extends CharacterBody2D
# 플레이어 배우 — 로컬(입력 구동) / 원격(수신 보간) 겸용.
# 자기 위치·공격 입력은 자기가 소유하고, 데미지 확정은 호스트가 한다 (rules §1·§3).
# 조작(GDD §5 v1.5): WASD 이동, 마우스 조준(2방향 플립), 좌클릭 공격, Shift 구르기.

const NetSchema := preload("res://src/core/net_schema.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")
const AfterImage := preload("res://src/feel/afterimage.gd")

# 연출값 (rules §0 예외 — 사용자가 플레이하며 조인다)
# ⚠ 구르기 시간·쿨다운은 여기 없다 — CombatMath.ROLL_TIME_S/ROLL_COOLDOWN_S(§3 단일 소스,
#   호스트 i-frame 검증과 같은 값). 사본을 만들면 무적 창과 이동이 갈라진다.
const REMOTE_LERP_SPEED := 12.0
# 위치 송신 빈도(Hz). 이 값이 곧 **호스트가 게스트 위치를 모르고 있는 평균 시간**(1/2주기)이라
# 지연 보상의 바닥이 된다 — 15Hz면 평균 33ms가 판정에서 그냥 손실이었다(2026-07-24 계측).
# 30Hz로 올려 17ms로 줄인다. 2인 기준 피어당 ~3.5KB/s라 릴레이 부담은 무시 가능.
const POS_SEND_RATE := 30.0
const REMOTE_TINT := Color(1.0, 0.75, 0.75)
const GHOST_ALPHA := 0.4
# 🔴 **궤적 표시 시점은 이제 상수가 아니다 — 칼이 지나가는 그 순간이다** (선딜/후딜 축 2026-07-28).
#   전에는 클릭 후 고정 0.07s였고, 판정(0s)·궤적(0.07s)·스윕이 실제로 각을 훑는 구간이 **전부 어긋나**
#   있었다. 지금은 셋이 `_tick_swing_motion` 한 곳에서 같은 `t`로 나온다.
# 🔴 **`CombatMath`가 쥔다 — 트립와이어가 스로틀 상한과 비교해야 하기 때문이다**(netreview Gap B).
#   판정이 궤적이 사라진 **뒤에** 나면 「표시 ⊇ 판정」이 시간 축에서 무너진다. 그 부등식
#   (`MELEE_THROTTLE_MAX_S < MELEE_TRAIL_FADE_S`)을 데이터로 지키려면 양변이 같은 곳에 있어야 한다.
const ATTACK_FX_TIME := CombatMath.MELEE_TRAIL_FADE_S  # 스윕 완료 뒤 궤적이 흩어지는 시간(잔상 페이드)
# 궤적 꼬리의 최소 알파 — 스윕이 끝나면 1.0으로 수렴한다(`lerpf(TAIL_MIN, 1.0, u)`). 스윕 도중에만
#   보이고 그때는 아직 판정이 없다.
# 🔴 **"판정 순간 = 균일 부채꼴"은 이 상수 혼자가 아니라 `_draw_swing_trail`의 선단 래치와 함께
#   성립한다** (netreview M-2 정정 — 여기에 그 보장을 단독으로 단언해 뒀던 것은 거짓이었다).
#   래치가 없으면 판정 프레임에 무기 각이 이미 복귀 분기로 물러나 있어 **최대 약 19°가 안 그려진
#   채로** 굳는다. 둘 중 하나라도 빠지면 보장이 깨지니 같이 본다.
# --- 칼끝 리본 궤적 (2026-07-29) — 🔴 **부채꼴 셰이더를 대신한다.** ---
# 왜 바꿨나: 셰이더는 "칼이 지나간 **영역**"(반지름 35~51 × 각 104°짜리 부채꼴 띠)을 칠하는데
#   칼은 그 영역의 **테두리 한 줄**이다. 형태가 다르니 각을 3°까지 맞춰도 절대 포개지지 않는다
#   (사용자 요구: *"검의 궤적과 vfx 궤적을 하나로 깔끔하게 포개달라"*). 리본은 **칼끝 좌표를 그대로
#   읽어** 잇기 때문에 각·반지름·회전중심이라는 어긋날 축이 **애초에 없다** — 정합이 구조로 보장된다.
# 🔴 §3(표시 ≥ 판정)은 그대로 지켜진다: 칼이 지나가는 각 `[-arc×젖힘, +arc]` ⊇ 판정 각 `±arc`이고,
#   부채꼴 **안쪽**을 비우는 것은 셰이더 시절부터 "순수 연출"로 허용된 자리다(안 보이는데 맞는다가
#   아니라, 가까운 적은 칼이 몸을 지나가는 것으로 읽힌다).
const TRAIL_SUBSTEPS := 4       # 프레임 사이 각 보간 — 60fps 스윕이 5~7프레임뿐이라 없으면 각진다
const TRAIL_MAX_POINTS := 48    # 점 상한(안전판) — 스윕 길이 × SUBSTEPS를 넉넉히 덮는다
# --- 칼날 폭 리본 (2026-08-01) — 🔴 칼끝 **한 점**이 아니라 칼끝~칼밑 **면**이다 ---
# 사용자 요구: *"리본도 칼날에 맞게 두꺼웠으면 좋겠음"*. 07-29 리본은 칼끝 좌표만 이은 7px `Line2D`라
#   무기 굵기와 무관했다. 이제 같은 배치식에서 **칼밑 궤적**을 하나 더 뽑아 두 궤적 사이를 채운다.
# 🔴 **바깥 변 = 칼끝 그 자체다 — 넘어가면 안 된다.** 리본이 칼끝보다 밖으로 나가면 도달 거리를
#   실제보다 길게 오해하게 만든다. 안쪽으로 넓어지는 것만 안전하다(판정 부채꼴을 **더** 덮는다) —
#   그래서 이 변경 자체는 §3 「표시 ⊇ 판정」에 안전한 방향이고, 각 창은 **전혀 안 건드린다**.
# 🔴 **`Line2D.width`를 키우는 방식은 안 된다** — 그 폭은 「선 진행 방향의 수직」이라 베기(호)에서는
#   우연히 radial이 되지만 찌르기(창)에서는 **칼 옆으로 퍼진다**(칼날 밖 = 금지 방향). 면이면 두 변이
#   각각 칼끝·칼밑이라 어떤 모션에서도 칼 안에 머문다.
# 🔴 리본 폭의 단일 소스 = `CombatMath.blade_length(equip)` (→ `EquipDef.blade_length`).
const TRAIL_TAIL_WIDTH := 0.35   # 꼬리 폭 비율 — 오래된 자국일수록 칼끝 쪽으로 좁아진다(1.0 = 균일)
# 안쪽 변의 최소 반지름 — 🔴 **하는 일을 정확히 적는다**(reviewer m-1 정정). 이 하한이 막는 것은
#   **0으로 나누기와 정확한 점 중복**뿐이고, 퇴화 자체를 못 막는다: 겹침이 없어지는 게 아니라
#   반지름 1px 원으로 **옮겨 갈** 뿐이라 인접 점 간격이 최악 0.04px까지 좁아진다.
# 🔴 **퇴화를 실제로 막는 것은 데이터 쪽 전수 트립와이어다**(`test_combat_math_auto`의 「★칼날 폭 전수」
#   — `blade_length ≤ 텍스처폭 − grip.x + hold_dist − swing_pull`). 이 상수를 키워서 고치려 하지 마라:
#   키우면 리본이 칼밑보다 안쪽에서 시작해 **칼날 폭이 데이터와 갈라진다.**
const TRAIL_MIN_INNER_DIST := 1.0
# 🔴 **검기 표시 증폭 — `reach` 특성값에 곱해 리본에만 얹는 배율** (2026-08-01 사용자 요구:
#   *"검성이 좀더 검기가 날아갔으면 좋겠음 크고 두껍게"*). 판정 배율은 `1 + reach`인데 표시는
#   `1 + reach × 이 값`이다 = 검성 메인(reach 0.3)에서 판정 1.3배 vs 리본 **1.6배**.
# 🔴 **연출값이라 여기 const다**(rules §0 예외: 손맛 전역 크기는 스크립트 const, 무기별로 갈리는
#   것만 데이터). 데이터가 만족해야 할 제약이 아니라 "얼마나 화려한가"라서 `CombatMath`로 올리는
#   J-1 규율의 대상이 아니다 — 전수 트립와이어가 물을 대상이 없다.
# ⚠ **실기에서 조일 값이 바로 이것이다.** 너무 넓어 "휘둘렀는데 안 맞는다"가 되면 판정이 아니라
#   여기를 내려라(1.0 = 판정과 정확히 일치하는 도입 시점 동작).
const TRAIL_REACH_SHOW_MULT := 2.0
# 🔴 **검기 반달의 타수별 차등** (2026-08-02 사용자 확정: *"1·2·3타 전부 반달이고 크기만 차등"*).
#   마무리 타에서 **판정 각·사거리가 실제로 넓어지므로**(v2.2 `combo_finish_arc` · v2.3
#   `combo_finish_range`) 화면이 그 방향과 일치해야 한다 — 타수가 오를수록 크고 넓게.
# 🔴 **둘 다 비율이다 — 절대 px/rad을 적지 마라.** 반경은 `CombatMath.effective_attack_range`,
#   반각은 `melee_show_half_angle`에서 오고 여기 곱은 그 위에 얹는 **연출 램프**뿐이다. 절대값을
#   적는 순간 무기를 바꾸거나 `melee_range`를 튜닝해도 검기가 안 따라오는 두 번째 진실원이 된다.
# ⚠ **이 램프는 판정에 닿지 않는다.** 검기는 자체 데미지가 없고(GDD §6) 이 값들은 `SlashFx`의
#   셰이더 유니폼으로만 흐른다 — `is_hit_in_reach`/`is_melee_in_cone`의 `half_angle` 인자에는
#   **절대 넘어가지 않는다**(§3이 금지한 「제3의 값」은 그 인자 자리를 말한다).
# ⚠ 반각 램프의 상한이 1.0인 것도 의도다 — 검기가 그 스윙의 **표시 반각을 넘지 않으므로**
#   "궤적은 안 지나갔는데 검기만 그 각에 있다"가 생기지 않는다.
# ⚠ **실기에서 조일 값이다** → `docs/TUNING.md` 등재 대상.
const SLASH_ARC_RAMP_MIN := 0.55      # 1타 검기 반각 / 그 스윙의 표시 반각 (마지막 타 = 1.0)
const SLASH_RADIUS_RAMP_MIN := 0.85   # 1타 검기 반경 / 판정 도달
const SLASH_RADIUS_RAMP_MAX := 1.15   # 마지막 타 검기 반경 / 판정 도달
# 🔴 **반각 포화 상한 = 「반달」의 정의 그 자체(±90° = 전체 180°)다.**
#   램프만 두면 넓은 무기의 마무리가 반각 **175°**(철 대검 `combo_finish_arc` 2.9 + 표시 여유)까지
#   가서 사실상 **고리**가 된다 — 그건 사용자가 이번에 버린 옛 `slash_2`(링) 그림 그 자체이고,
#   진행 방향으로 날아가는데 양 끝이 **뒤를 향해** 있어 "날아가는 날"로도 안 읽힌다.
# 🔴 **하드 clamp가 아니라 `tanh` 포화다** — clamp면 철 대검 2·3타가 **둘 다 90°**로 같아져
#   "타수가 오를수록 넓게"라는 요구가 넓은 무기에서만 죽는다(도끼는 88° → 90°로 차이가 사라진다).
#   tanh는 상한에 점근할 뿐 **절대 도달하지 않아 순서가 엄밀히 보존**되고, 좁은 무기(창 0.17rad)는
#   `tanh(x) ≈ x` 구간이라 **사실상 항등**이다 — 즉 좁은 무기의 데이터 차이를 하나도 안 먹는다.
# ⚠ 크기 축의 차등은 반경이 계속 진다(철 대검 마무리 반경 55 → 94px). 각이 포화해도 마무리가
#   확연히 커 보이는 것은 그쪽 축이 보장한다.
# ⚠ **실기에서 조일 값이다** → `docs/TUNING.md` 등재 대상.
const SLASH_MAX_HALF_ANGLE := PI * 0.5
# 선에서 면이 되면서 칠해지는 면적이 5배 가까이 늘었다 — 알파 1.0이면 잔상·칼과 겹쳐 하얗게 탄다.
# 🔴 **0.72 → 0.88** (2026-08-02 사용자: *"검기 임팩트? 리본들을 좀더 강렬하게 해줄래?"*).
#   ⚠ 올린 것은 **알파뿐이고 기하는 한 픽셀도 안 건드렸다** — 리본의 두 변은 여전히 칼밑·칼끝
#     좌표 그 자체다(위 주석의 "포개짐"이 그대로 산다). 탁하면 짝 노브는 `AfterImage.WEAPON_ALPHA`다.
const TRAIL_ALPHA_MAX := 0.88
# 꼬리 알파 곡선 — 옛 씬 `Gradient`(0 / 0.45→0.55 / 1)와 **같은 모양**을 코드로 옮긴 것이다
# (면 리본은 정점 색을 직접 넣어야 해서 Line2D의 gradient를 쓸 수 없다).
const TRAIL_FADE_MID := 0.45
const TRAIL_FADE_MID_A := 0.55
# 칼 잔상 장수 — 🔴 **시간이 아니라 스윕 진행(u) 간격으로 센다.** 시간 타이머로 돌리면 프레임률과
#   무기 속도(0.24~0.34s)에 따라 장수가 들쭉날쭉해져 "빠른 무기는 잔상이 한 장"이 된다.
# ⚠ **4 → 5** (2026-08-02 강렬화). 밀도만 늘고 각·반경은 `_swing_angle_at` 하나가 정하므로 §3 무관.
#   🔴 **더 올리지 마라 — 여기는 드로우콜 축이다**: 실제 장수 = 이 값 × `_subjob_fx_ghost`(상한
#     `CombatMath.MAX_FX_GHOST_MULT` 3.0)이라 광전사(1.8)에서 9장, 마무리는 아래 상수로 12.6장이
#     된다. 웹 Compatibility에서 잔상 한 장 = Sprite2D 하나 = 드로우콜 하나다(rules §5).
const GHOST_STEPS := 5
# 🔴 **어깨에 걸치기 — 선딜에 칼을 젖히는 각의 배율** (2026-07-28 사용자 요구: *"검과 도끼는 어깨에
#   걸치듯이 진행이 되어야 함"*). `_begin_swing`이 **시작각에만** 곱한다.
# 왜 시작각만인가: 끝각(`_swing_to`)은 궤적 선단이 판정 부채꼴을 덮는다는 불변식(§3)이 걸려 있어
#   건드리면 안 된다. 시작각을 뒤로 더 젖히는 것은 **칼이 더 뒤에서 출발한다**는 뜻이라 판정과
#   무관하고, 궤적도 그만큼 뒤로 넓어질 뿐이다(표시 > 판정 = 안전한 방향).
# ⚠ **무한정 젖힐 수 없다** — 셰이더의 궤적 진행 게이트가 `span < 2π-0.02`에서만 돌고, 넘으면 진행이
#   통째로 꺼져 부채꼴이 한 번에 번쩍인다(= 이 개편 전 그림). 그래서 `_begin_swing`이 무기 각에서
#   최대치를 유도해 자른다: 넓은 무기(도끼 160°)일수록 남은 여유가 작아 자동으로 덜 젖혀진다.
# 🔴 **1.5 → 1.8** (2026-08-01 3차 — 사용자 재신고 *"2타할 때 좀 더 티내줘, 검을 뒤로 뺐다가 때리는 거"*).
#   앞선 두 차례는 **젖힘 비율**(`COMBO_WINDBACK_*` = 그 거리 중 대기 구간에 미리 가 있는 몫)만 올렸는데,
#   평타→평타의 **젖힐 거리 자체가 `arc × (배율 − 1)`뿐**이라 비율을 1.0으로 해도 상한이 낡은 대검
#   54.4°였다(그마저 선딜이 할 일을 잃는다). 거리를 늘려야 뒤로 빼는 동작이 눈에 남는다.
# ⚠ **cap이 무기별로 자동 제한하므로 실제로 늘어나는 것은 각이 좁은 무기뿐이다** — 낡은 대검 1.5 → 1.8 ·
#   철 대검 1.5 → 1.609(cap) · **도끼는 1.237(cap)로 불변**(원래 160°라 감을 여유가 없다) · 창은 thrust라
#   이 배율을 아예 안 지난다. "넓게 휘두르는 무기는 크게 감지 않는다"가 데이터가 아니라 기하에서 나온다.
const SWING_WINDUP_ARC_MULT := 1.8
# 🔴 **검기 파형(`WaveFx` · `sword_wave.png`)은 2026-07-29에 삭제했다** — 사용자 요청.
#   검성 특성(`reach`)이 켜지면 초승달이 칼과 **별개로 앞으로 날아가던** 연출인데, 칼끝을 따라가는
#   리본·잔상과 나란히 두니 "칼과 무관한 것이 하나 더 날아간다"로 읽혔다. `reach` 특성 자체(사거리
#   증가)는 그대로다 — 사라진 것은 그 사거리를 눈에 보여주던 표시뿐이다.
#   ⚠ 되살릴 거면 파형을 **칼 궤도 위에서** 뻗게 해야 한다(옛 코드처럼 직선으로 날리면 같은 신고가 돈다).
# ⚠ 미러(rules §3): 스윙 창은 모든 JobDef.attack_cooldown보다 짧아야 한다 (전사 0.4s) —
#   원격 창-잠금 가드(play_attack_fx)가 정당한 연속 공격의 스윙을 무시하지 않으려면.
#   아래 두 상수는 무장 해제/폴백 기본값이고, 무기별 실값은 EquipDef.swing_time/lunge(→ _swing_*).
const ATTACK_ANIM_TIME := 0.25       # 스윙 창 기본값(폴백) — 무기별은 EquipDef.swing_time
# ⚠ 스윙 호 반각의 폴백 상수는 **없다** — 표시 각은 `CombatMath.melee_show_half_angle(equip, is_finish)`
#   하나에서만 나온다(v2.2). 사본을 두면 마무리 타에서 표시와 판정이 갈라진다(§3).
# --- 공격 타이밍 = 선딜 / 스윕 / 후딜 (무기 모션 개편 2026-07-28) ---
# 🔴 **곡선의 "모양"은 표시 전용이지만 구간 "길이"는 판정 시점을 정한다** (netreview m-3 정정 —
#   이 자리에 "판정은 이 곡선을 전혀 보지 않는다 / 클릭 프레임에 끝난다"고 적어 뒀던 것은 선딜 축
#   도입 전 서술이고 지금은 **거짓**이다. `equip_def.gd`의 새 주석과 정면으로 어긋나 있었다).
#   판정이 나가는 순간 = **「선딜 + 스윕」이 끝나는 시점**(`_tick_swing_motion` → `_resolve_swing_hit`).
#   각·반경(`swing_arc`·`melee_range`)은 여전히 이 곡선과 무관하다 — "맞는 **곳**"은 안 움직이고
#   바뀌는 것은 "맞는 **때**"다.
# 구간 셋 = 선딜(젖히고/당기고) → 스윕(급가속) → 후딜(회수). 비율·이징·당김은 무기별(EquipDef.swing_*),
#   아래는 **폴백/기본**(= 개편 전 하드코딩 값 그대로라 무기가 값을 안 주면 완전 항등).
# ⚠ 폴백 기본값도 `CombatMath`가 쥔다 — 여기에 사본을 두면 EquipDef 기본값과 갈라진다(J-1과 같은 이유).
# 🔴 세 구간이 **전부 양수 폭**이어야 한다 — 0이면 정규화가 0으로 나누고, 합이 1을 넘으면 후딜이
#   사라져 무기가 휘두른 자세로 얼어붙는다(에러 없이 화면만 어긋난다). 데이터를 믿지 않고 코드가 clamp한다.
# 🔴 **그 clamp는 `CombatMath.motion_phases()`에 있다 — 여기 두면 테스트가 못 닿는다** (code-rv J-1).
#   `player.gd`는 씬 글루라 `-s` preload가 안 되므로, 상한을 여기 두면 전수 트립와이어가 `w>0 ∧ s>0 ∧
#   w+s<1`처럼 **코드보다 느슨한** 것밖에 못 쓴다. 실제로 `0.02`(→0.05로 clamp)와 합 `0.97`(→0.95)이
#   **둘 다 초록으로 샜다** — 하필 "왜 내 도끼 예비가 안 길어지지"가 나는 바로 그 밴드다.
# --- 타격 무게 (무기별) ---
# 🔴 **무게의 단일 소스는 `EquipDef.hit_shake` 하나다** — 카메라 킥·스윙 "박힘"이 전부 여기서
#   파생한다. 무게 필드를 따로 만들면 같은 것을 뜻하는 숫자가 둘이 되어, 도끼를 무겁게 조였는데
#   셰이크만 커지고 킥은 그대로인 갈라짐이 생긴다(rules §3의 반복된 실패 형태).
# 🔴 **기준점·상한은 `CombatMath`가 쥔다 — 여기 두면 전수 트립와이어를 만들 수 없다** (code-rv J-2).
#   `player.gd`는 씬 글루라 `-s`가 preload를 못 해서, 여기 있는 상수로는 `data/equipment` 전수
#   단정을 쓸 수 없다. 실제로 `hit_shake`를 4.5로 한 칸만 올리면 상한에 걸려 **킥·박힘은 안
#   따라오고 셰이크만 커지는데** 아무도 못 잡는 상태였다 = `swing_arc = 0`과 같은 부류.
# 적중 순간 **공격자 자신의 스윙**이 살에 박혀 잠깐 멎는다(무게 배율이 곱해진다).
# 🔴 스윙 **창**(`_attack_anim_left`)은 절대 늘리지 않는다 — 늘리면 `swing_time < attack_cooldown`
#   미러 계약(§3)이 깨져 원격 창-잠금 가드가 정당한 연속 공격의 연출을 삼킨다. 대신 모션 파라미터
#   `t`를 그 자리에 붙들어 둔다(남은 구간이 그만큼 빨리 지나간다 = 창 길이 불변).
# ⚠ 공격자 로컬 전용이다 — 셰이크·타격음과 같은 자리(원격은 적중 사실을 모른다).
const SWING_BITE_S := 0.045
const SWING_BITE_MAX_S := 0.10
# 🔴 **박힘은 후딜 창 안에 들어가야 한다** (code-rv J-3, 2026-07-28). 박힘 중엔 `t`가 `선딜+스윕`에
#   고정된 채 창만 흐르므로, **창이 먼저 끝나면** `_attack_anim_left = 0` → `_motion_off = 0`으로
#   **완전 전개(도끼 2.8 rad)에서 평상 자세로 한 프레임에 스냅한다** — 복귀 모션이 통째로 사라진다.
#   적중했을 때만 나므로 하필 가장 잘 보이는 순간이다. 파쇄 도끼가 최고 공속에서 **이미** 그랬다
#   (후딜 `0.40 × 0.36 × 2/3` = 96ms < 박힘 100ms). 그래서 상한을 그 창에 비례해 함께 묶는다.
const SWING_BITE_RECOVER_MAX := 0.7  # 후딜 창의 이 비율까지만 — 나머지는 회수 모션이 보이게 남긴다
const WEAPON_AIM_LERP := 18.0        # 원격 조준각 보간 속도
const HOLD_DIST := 8.0               # 몸 중심 → 그립 거리 (몸에 붙지 않게 떨어뜨려 든다)
# 무장 해제(무기 없음) 때의 회전 중심. ⚠ `EquipDef.weapon_pivot`의 기본값과 **같아야 한다** —
# 갈라지면 "맨손일 때와 무기 낄 때 회전 중심이 다르다"가 에러 없이 생긴다(그쪽 필드 주석이 짝).
const WEAPON_PIVOT_DEFAULT := Vector2(0.0, -4.0)
const LUNGE_DIST := 5.0              # 스윕 중 앞으로 내지르는 거리
const REMOTE_MAX_SPEED_MULT := 1.5  # 원격 변위 클램프 여유 — 순간이동 스푸핑 완화 (rules §3)
const ENEMY_BODY_MASK := 1 << 2  # 물리 레이어 3 enemy_body — rules §5 배정표가 단일 소스
# 발사(shoot 무기 = 궁수 활) — 표시 연출값(§0 예외, 사용자 튜닝). 화살 속도/사거리는 CombatMath(결정론 공용).
const MUZZLE_OFFSET := 26.0          # 발사 원점 = 몸 중심 → 조준 방향 이만큼 앞. 화살 길이 18(반9)+몸 반경 16 → 26이면 화살 뒤끝(17)이 몸 밖 (겹침 방지). SHOT_ORIGIN_TOL이 이 값+지연을 수용
const RECOIL_DIST := 4.0             # 발사 시 활을 뒤로 당기는 거리(px) — 반동 손맛
const RECOIL_TIME := 0.14            # 반동 복귀 시간(s)
# 차지 발사(charge 무기 = 법사 지팡이) — 표시 연출값(§0 예외, 사용자 튜닝).
# 단계 수·위력/반경 배율은 CombatMath.CHARGE_*(§3 단일 소스), 단계 시간은 무기별(EquipDef.charge_step_time).
const CHARGE_MOVE_MULT := 0.5        # 기 모으는 동안 걷기 속도 배율 (모으는 대가 — 구르기로 취소 가능)
const ORB_LERP := 14.0               # 차지 오브 크기 보간 속도
const ORB_POP := 0.55                # 단계 상승 순간 확대 비율
const ORB_POP_TIME := 0.16           # 그 팝이 가라앉는 시간(s)
const REMOTE_CHARGE_SFX_MIN_MS := 250  # 원격 차지음 최소 간격 — G_POS "c"를 0↔2로 진동시켜 소리를 도배하는 그리핑 차단 (play_roll_fx 창-잠금 미러). 정직한 단계 상승은 350ms 간격이라 안 걸린다

# --- 4방향(4분면) 표시 (사용자 확정 2026-07-26) ---
# 애니 이름 규칙 = "<base>_e" / "_s" / "_n" — **서쪽은 동쪽 프레임을 flip_h**로 쓴다(픽셀아트 표준:
# 좌우가 대칭이라 장수를 반으로 줄인다). SpriteFrames에 방향 애니가 **없으면 기존 2방향으로 폴백**하므로,
# 4방향 시트가 아직 없는 지금도 동작이 완전히 그대로다 — 아트가 나오면 PNG/.tres 교체만으로 켜진다.
# 🔴 방향의 단일 소스는 **조준각(_aim_angle)** 이다: 로컬은 마우스, 원격은 G_POS "a"라 **네트워크 필드 0개**로
#   원격도 같은 방향을 얻는다. flip_h를 여기 말고 다른 곳에서 대입하면 프레임마다 서로 덮어써 깜빡인다.
const DIR_SUFFIX: Array[String] = ["e", "s", "w", "n"]  # _facing_index 순서와 미러
# --- 몸통 공격 애니 (콤보 타수별 3종, 2026-08-01) ---
# 🔴 **애니 길이는 `swing_time`과 미러가 될 수 없다 — 그래서 미러를 만들지 않고 매 스윙 유도한다.**
#   시트는 speed 16 = 0.25s **고정**인데 `swing_time`은 무기별 0.24~0.36s이고 haste가 더 줄인다
#   (최대 haste 0.5에서 0.24 → 0.16s). 손으로 맞추는 미러는 원리적으로 불가능하고, 어긋나면
#   **몸 애니가 스윙 창보다 길어져 잘린다**(에러 없이 화면만 어긋난다).
#   준거 = `boss.gd`의 `_telegraph_duration()`/`_apply_anim_scale()` — 같은 문제를 같은 방식으로 푼다
#   (rules §3 「공격 애니 길이 ↔ 예고 시간」). 프레임 수·speed를 **시트에서 읽으므로** 아트가 프레임을
#   늘려도 자동 추종한다.
# 🔴 speed_scale 하한 — 0/음수는 애니를 세우거나 거꾸로 돌린다. 히트스톱 정지(0.0) 판별과도 안 겹치게.
const MIN_ANIM_SPEED_SCALE := 0.01
# --- 대쉬 손맛 (구르기 = 잔상 대쉬, 사용자 확정 2026-07-26 "연출만") ---
# 🔴 i-frame·쿨다운·거리는 **그대로다** — CombatMath.ROLL_TIME_S/effective_roll_*(§3 단일 소스,
#   호스트 검증과 같은 값)를 건드리지 않는다. 바뀐 것은 화면에 보이는 것뿐(잔상·먼지·카메라 킥).
const DASH_KICK := 2.2          # 대쉬 시작 시 진행 방향 카메라 반동
const DASH_END_KICK := 1.1      # 대쉬가 끝나며 멈출 때의 되튐(반대 방향)
# --- 무기 스탠스 (사용자 지적: "검도 idle이 있는건지 캐릭터에 붙어있음") ---
# 평상시 무기가 조준각에 못 박혀 있으면 몸에 용접된 것처럼 보인다 → 살짝 내려 들고 호흡하듯 흔든다.
# 전부 표시 전용이다 — 발사 원점(_aim_dir)·판정 기하는 sway를 **안 본다**(§3 "맞는 곳 = 보이는 곳"의
# 기준은 조준각이지 흔들린 각이 아니다). 스윙·차지·반동 중엔 sway를 끈다(모션끼리 섞이면 지저분해진다).
const STANCE_DROP := 0.20       # 평상시 무기를 내려 드는 각(rad)
const IDLE_SWAY_AMP := 0.055    # 정지 중 호흡 흔들림 진폭(rad)
const IDLE_SWAY_SPEED := 2.6
const RUN_SWAY_AMP := 0.15      # 이동 중 흔들림 — 걸음에 맞춰 크게
const RUN_SWAY_SPEED := 7.5
const STANCE_LERP := 9.0        # 스탠스↔조준 전환 부드러움
const COMBO_POSE_RETURN_SPEED := 18.0 # 입력이 끊긴 뒤 끝 포즈에서 기본 자세로 돌아오는 속도(rad/s)
# --- 평타 콤보 (v2.2 2026-07-29 — 연출 전용이었던 것이 판정·화력으로 승격됐다) ---
# 🔴 **더 이상 연출 전용이 아니다.** 타수·타별 데미지·뜸·마무리 각·돌진이 전부 **무기 데이터**
#   (`EquipDef.combo_*`)에서 오고 호스트가 G_ATK 간격으로 타수를 직접 센다(GDD §6 「공격 리듬」).
#   여기 남은 것은 **연출 배율 둘뿐**이고 나머지는 전부 `CombatMath` 단일 소스를 지난다(§3):
#     타수 = `combo_len` · 창 = `combo_window_s` · 뜸 포함 쿨다운 = `combo_gap_s`
#     판정 각 = `melee_half_angle(equip, is_finish)` · 표시 각 = `melee_show_half_angle(...)`
#     데미지 = `combo_damage_mult_at` · 돌진 = `combo_dash_dist`
# 🔴 **`COMBO_MAX`·`COMBO_WINDOW`·`COMBO_FINISH_ARC` 셋은 삭제했다 — 되살리지 마라.**
#   ⑴ `COMBO_MAX`(3 하드코딩)는 "타수를 무기가 정한다"와 정면으로 어긋난다(도끼 2 · 대검 3 · 창 4).
#   ⑵ `COMBO_WINDOW`는 클릭 시점부터 `_swing_time + 0.55`를 재서 호스트 창(`combo_window_s`)과
#      최대 160ms 어긋나 있었다 — 두 창이 갈라지면 "내 화면은 3타인데 판정은 평타"가 된다.
#   ⑶ `COMBO_FINISH_ARC`(균일 1.25 배율)는 포화 문턱(`π ÷ 반각`)이 무기마다 달라 **넓은 무기만
#      전방위로 만든다.** 도끼(2.8)에서 span이 401°(= TAU 초과)라 실제로 "한 바퀴 넘게" 휘둘렀고
#      어깨걸치기 `cap`은 기본 span을 안 줄인다. 절대값(`EquipDef.combo_finish_arc`) + **코드가 쥔**
#      여유(`COMBO_FINISH_SHOW_MARGIN`)로 오면 그 방향이 구조로 닫힌다.
# ⚠ _swing_time을 콤보로 늘리지 마라: 스윙 창 < attack_cooldown 미러 계약(§3)이 깨지면 원격
#   창-잠금 가드가 정당한 연속 공격의 연출을 삼킨다.
# 🔴 **마무리 타의 내지르기 배율** (연출 — 무기 스프라이트만 움직인다. `velocity`에 안 들어간다).
#   2026-08-01에 1.7 → 2.3. 사용자 요구 *"3타때 범위가 눈에 뛰게증가"* 에 실제로 쓸 수 있는 축이
#   **반경뿐**이었기 때문이다(각은 아래 주석의 계산대로 화면 변화가 0이다).
# ⚠ 이 배율은 **`swing_lunge`(무기 데이터)에 곱해진다** — 무기마다 절대 증분이 다르다
#   (낡은 대검 4 → 9.2px · 철 대검 9 → 20.7 · 도끼 10 → 23 · 창 15 → 34.5).
# ⚠ 칼끝이 **판정 도달보다 밖으로** 더 나간다(이미 그랬다 — 스프라이트가 길어서다). 리본은 여전히
#   칼끝을 안 넘으므로 §3 계약은 유지되지만, 더 키우면 "칼은 닿는데 안 맞는" 오해가 커진다.
const COMBO_FINISH_LUNGE := 2.3
# 🔴🔴 **찌르기는 이 배율을 안 쓴다 — 두 모션에서 `swing_lunge`의 역할이 다르기 때문이다.**
#   베기: `peak × sin(uπ)`라 **판정 프레임(u = 1)에 정확히 0**이다 → 키워도 부풀어 보이는 것은
#         스윕 중간뿐이고 "칼끝 vs 판정 도달"의 관계는 안 변한다(낡은 대검 칼끝 44 vs 도달 42 불변).
#   찌르기: `lerpf(-pull, peak, u)`라 **판정 프레임에 peak 그 자체**다 → 배율이 곧 그 순간의
#         칼끝 거리다. 창을 2.3으로 올리면 칼끝 88.5 → 97.5px인데 판정 도달은 80 그대로라,
#         *"겨눈 한 줄 밖은 스치지도 않는다"* 는 그 무기에서 **오차가 11% → 22%로 두 배**가 된다.
# ⚠ 같은 이름의 값이 둘이라 미러처럼 보이지만 **미러가 아니다** — 위 두 곡선이 다른 것을 뜻한다.
#   창의 마무리를 더 뻗게 하고 싶으면 이 값이 아니라 `combo_dash`(몸이 같이 나간다)를 본다.
const COMBO_FINISH_THRUST_LUNGE := 1.7
const COMBO_FINISH_KICK := 2.6  # 마무리 타의 카메라 반동 (연출)
# 🔴🔴 **마무리 각(`EquipDef.combo_finish_arc`)을 올려 "범위"를 키우려 하지 마라 — 화면 변화가 0이다**
#   (2026-08-01 실측). 어깨걸치기 `cap`(`_begin_swing`)이 리본 span을 `TAU − 0.02`로 **포화**시키기
#   때문이다: span = arc × (1 + mult)이고 `arc > 2.505`면 mult가 cap으로 눌려 span이 항상 6.2632다.
#     낡은 대검 평타 4.75rad(272°) → 마무리(2.4) **6.2632rad(358.9°)**
#     철 대검   평타 6.00rad(344°) → 마무리(2.9) **6.2632rad(358.9°)**
#     도끼      평타 6.2632(359°) → 마무리(2.8) **6.2632(358.9°)**  ← 평타부터 이미 포화
#   즉 마무리 각을 2.4 → 2.9로 올려도 **그려지는 호는 한 픽셀도 안 변하고 판정 부채꼴만 넓어진다**
#   = "눈에 띄게"의 정반대(안 보이는 버프). 게다가 철 대검 2.9는 blind wedge가 13.8°뿐이라
#   `asin(고블린 반경 10 ÷ 도달 42)` = 13.8°와 같아 **등 뒤 적이 이미 맞는다** — 07-28에 없앤 그 상태다.
#   → 마무리를 "커 보이게" 하는 축은 **반경(위 LUNGE) · 몸 이동(`combo_dash`) · 아래 표시 강조** 셋이다.
# 마무리 타 리본의 알파 상한 (평타 = `TRAIL_ALPHA_MAX` 0.88). 🔴 **0.88 → 0.98** (2026-08-02 강렬화).
# ⚠ 1.0을 쓰지 않는 이유는 그대로다 — 잔상·칼과 겹쳐 **하얗게 탄다**(색이 사라져 오히려 약해 보인다).
const COMBO_FINISH_TRAIL_ALPHA := 0.98
# 마무리 타의 칼 잔상 장수 (평타 = `GHOST_STEPS` 5) — 호를 더 촘촘히 채워 "크게 휘둘렀다"가 읽힌다.
# ⚠ 6 → 7 (2026-08-02 강렬화). 드로우콜 경고는 `GHOST_STEPS` 주석이 정본이다.
const COMBO_FINISH_GHOSTS := 7
# 마무리 타의 벤 자국이 남아 있는 시간 배율 (평타 = `ATTACK_FX_TIME` 그대로).
# ⚠ 페이드 정규화가 `_fx_total`을 지난다 — 여기만 키우고 나눗셈을 `ATTACK_FX_TIME`으로 두면 자국이
#   1.0을 넘는 알파로 clamp돼 **앞부분이 통째로 안 흐려진다**(뚝 끊기는 것처럼 보인다).
const COMBO_FINISH_FX_TIME_MULT := 1.5
# --- 마무리 직전 타의 젖힘 (2026-08-01 사용자 요구: *"2타때 검을 살짝 뒤로했다가 3타떄"*) ---
# 🔴 **문제는 "예비 동작이 없다"가 아니라 "예비 동작이 마무리 타 안에 갇혀 있다"였다.** 마무리의
#   선딜은 이미 직전 타 끝각에서 시작각까지 젖히는데(낡은 대검 −1.9 → −3.713 = **104°**), 그 선딜이
#   0.048s(0.24 × 0.2)뿐이라 순간이동으로 읽힌다 — 그래서 3타가 "갑자기 튀어나온다".
# 🔴 **처방 = 그 젖힘의 일부를 「대기 자세」로 앞당긴다.** 마무리 직전 타의 후딜~콤보 대기 동안
#   자세를 끝각에서 **다음 타의 선딜 시작 자세** 쪽으로 천천히 민다. 낡은 대검은 그 구간이 488ms라
#   시간이 충분하다(스윕 종료 0.132s → 다음 클릭 가능 0.62s).
# 🔴 **젖힘 목표는 새 자세가 아니다 — 다음 타가 실제로 지나는 자세다**(`_swing_entry_angle` ·
#   `-_swing_pull`). 그래서 이 연출은 **새 각 범위를 만들지 않는다**: 스윙 창 밖이라 판정과 무관하고,
#   `_combo_entry_from_previous` 보간이 남은 거리를 이어받아 이음매도 안 생긴다.
# 🔴 **젖힘은 콤보로 이어지는 「모든 타」 사이에 걸린다** (2026-08-01 2차 — 사용자 재신고
#   *"2타하기 전에 검이 살짝 뒤로 빠진다거나"*). 1차 구현은 **마무리 직전 타에만** 걸어서, 3타 대검의
#   1타 → 2타 사이에는 예비 동작이 아예 없었다 — 사용자가 지목한 바로 그 자리다.
# 🔴 **양은 뒤 타로 갈수록 커진다**(MIN → RATIO) = "점점 크게 감아친다". 마무리 각이 더 넓어 젖힐
#   거리 자체가 이미 1.2배(1.52 → 1.813 rad)라, 비율 점증이 그 위에 곱해진다.
# 🔴 **MIN 0.35 → 0.55** (2026-08-01 3차, 위 `SWING_WINDUP_ARC_MULT`와 **한 쌍**이다 — 거리를 늘리고
#   그중 대기 구간에 보이는 몫도 같이 올려야 "뒤로 뺐다가 때린다"가 읽힌다). 실측(비율 → 젖힘 각):
#     낡은 대검 1→2타 0.60 → **52.3°**(전 27.2°) · 2→마무리 0.65 → **67.5°**(불변)
#     철 대검  1→2타 0.60 → **50.3°**(전 34.4°) · 도끼 1→마무리 0.65 → **19.1°**(불변, cap)
# 🔴 **마무리 진입은 일부러 안 건드렸다** — 거기는 이미 67.5°이고 `RATIO`를 더 올리면 선딜이 할 일을
#   잃어 "마무리가 즉발로 보인다"(아래 RATIO 경고)가 된다. 이번 요구는 **평타 사이**의 예비 동작이다.
const COMBO_WINDBACK_RATIO := 0.65      # 마무리 직전 타 — 다음 타 시작 자세까지 미리 가 있는 비율
const COMBO_WINDBACK_RATIO_MIN := 0.55  # 첫 타 — 0에 가까우면 그 타만 예비 동작이 없어 리듬이 끊긴다
# 🔴🔴 **젖힘에 쓸 시간은 상수가 아니라 「그 타의 실제 빈 구간」에서 유도한다** (2026-08-01 2차).
#   빈 구간 = `combo_gap_s(다음 타) − 스윕 완료 시각`이고 **타마다·haste마다 4배 넘게 벌어진다**:
#     낡은 대검 1→2타 268ms / 2→마무리 **488ms** · 철 대검 0→1타 196ms / 1→마무리 416ms
#     최대 haste 최악 = 도끼 마무리→1타 **123ms** · 철 대검 0→1타 131ms
#   고정 상수(옛 0.18s)를 쓰면 짧은 구간의 타에서 **젖힘이 68%만 진행된 채 다음 타가 나가** 칠 때마다
#   자세가 달라진다 — "리듬이 아니라 들쭉날쭉"이 된다. 빈 구간에 비례시키면 **모든 타·모든 haste에서
#   끝까지 젖히고 잠깐 머문 뒤** 나가므로 박자가 일정해진다.
# ⚠ 뜸(`combo_delay`)이 마무리 **직전**에 붙어 있어서(대검 0.22 · 도끼 0.25) 빈 구간이 마무리 타에서
#   자동으로 가장 길다 — 가장 크게 젖혀야 할 타에 시간이 가장 많다. 데이터가 이미 그 모양이다.
const COMBO_WINDBACK_FILL := 0.7    # 빈 구간의 이 비율에 걸쳐 젖힌다 — 나머지 30%는 젖힌 채 머무는 「멈춤」
const COMBO_WINDBACK_MIN_S := 0.05  # 너무 짧으면 순간이동으로 읽힌다
const COMBO_WINDBACK_MAX_S := 0.22  # 너무 길면 굼떠 보인다(빈 구간이 488ms까지 벌어지므로 상한이 필요)
# --- 타별 감각 점증 (2026-08-01 2차) — 🔴 **전부 표시 전용. 판정·화력·쿨다운 무관.** ---
# 사용자 요구는 *"리듬감이 티가 나는 것"* 이지 젖힘 그 자체가 아니다. 그래서 **하나의 진행값
#   (`_combo_ramp`, 0 = 첫 타 → 1 = 마무리)** 이 눈(리본·잔상)·손(반동)·무게(박힘)를 **함께** 민다.
# 🔴 값 하나가 전부를 몰아야 한다 — 축마다 따로 두면 다음 튜닝에서 "리본만 커지고 반동은 그대로"가 된다.
# ⚠ `_combo_ramp = 0`이면 전부 **도입 전과 완전 항등**이고, `= 1`이면 1차 구현의 마무리 값과 같다
#   (즉 이 확장은 마무리 타를 안 건드리고 **중간 타에만** 새 값을 준다).
const COMBO_SWING_KICK := 0.6       # 첫 타의 스윙 반동 (마무리 = COMBO_FINISH_KICK 2.6까지 점증)
# 🔴 **콤보 타수 → 스윙음 피치** (2026-08-01, 사용자 요구 *"리듬감이 티가 났으면"*).
#   젖힘·반동이 리듬을 **눈**에 준다면 이쪽은 **귀**에 준다 — 실기에서 가장 싸게 체감이 오르는 레버다.
#   평타는 타수마다 반음쯤 오르고 **마무리만 뚝 떨어진다** → "타-타-쾅". 올리기만 하면 마무리가
#   가볍게 들려 「묵직한 마지막 타」와 정반대가 된다.
# ⚠ **표시 전용이다** — `EventBus.player_swing`은 로컬·원격 공용이라 두 화면이 같은 리듬을 듣는다
#   (원격도 `play_attack_fx` → `_begin_swing(combo)`로 `_combo_index`가 서 있다).
# ⚠ 발사·차지 경로는 이 훅을 **재사용**하므로 그쪽엔 1.0(항등)을 싣는다 — `event_bus.gd`가 근거.
const COMBO_PITCH_STEP := 0.07     # 평타 한 타당 상승분 (≈ 반음 1.0595에 가깝게)
const COMBO_PITCH_FINISH := 0.86   # 마무리 타 — 낮을수록 묵직하다
const COMBO_FINISH_BITE_MULT := 1.6 # 마무리 타의 적중 박힘 배율 — ⚠ SWING_BITE_MAX_S·후딜 창 clamp는 그대로다
# `job`이 없는 비정상 상태에서 `_swing_attack`이 돌려주는 쿨다운(s). 🔴 **0을 돌려주면 안 된다** —
#   쿨다운이 사라져 클라가 매 물리 프레임 reliable 채널로 `G_ATK`를 쏜다(netreview m-4). 값 자체는
#   중요하지 않고 "0이 아닐 것"만 중요하다(그 상태에선 스윙을 시작하지 않는다).
# ⚠ **전사 `attack_cooldown`(0.4)과 값이 같은 것은 우연이다 — 미러가 아니니 동기화하지 마라.**
#   부수적으로 `> ATTACK_ANIM_TIME`(0.25)도 만족해 가드가 나중에 옮겨져도 스윙 창이 겹치지 않는다.
const NO_JOB_SWING_CD_S := 0.4
const HIT_KICK := 1.7           # 근접 적중 시 때린 방향 반동 — 셰이크(무작위)와 달리 "밀어냈다"가 읽힌다
const SHOOT_KICK := 1.5         # 발사 시 **반대** 방향 반동 (총·활의 반동)
# --- 하위 직업 스킬 손맛 (연출값 = 스크립트 const, rules §0 예외. 🔴 판정에 한 픽셀도 안 닿는다) ---
const SKILL_WINDUP_PITCH := 0.72  # 시전 시작음 = 무기 스윙음을 낮춰 재활용(새 에셋 0) — 낮을수록 "모은다"로 들린다
const SKILL_SHAKE_MULT := 1.8     # 적중 셰이크 = 평타 대비. 쿨 8~9초짜리 한 방이라 평타보다 크게
const SKILL_KICK_MULT := 1.6      # 적중 카메라 킥 = 평타 대비 (셰이크와 **다른 축** — 방향이 읽힌다)
# --- beam 스킬의 반달 연타 (2026-08-02 「환영검무」 — 사용자: *"검을 와다다다 하는 느낌"*) ---
# 🔴 **여기 넷 중 도달 거리를 만드는 값은 하나도 없다.** 반달의 바깥 끝은 판정 캡슐의 끝
#   (`length + radius`)에서 유도되고(`_spawn_skill_slash`), 아래는 그 위의 형태·리듬뿐이다.
const SKILL_SLASH_HALF_ANGLE := 1.45   # 반달 반각(rad ≈ 83°) — 판정 캡슐의 옆폭을 덮는 각(함수 주석에 유도)
const SKILL_SLASH_TILT := 0.34         # 타마다 좌우로 틀어 넣는 각(rad ≈ 19.5°) — "와다다다"의 정체가 이 교대다
# 🔴 두께 배율 — 평타 검기(1.0)보다 **훨씬 두껍다**. 판정이 「테두리」가 아니라 **채워진 캡슐**이라
#   얇은 초승달이면 안쪽이 통째로 빈다(함수 주석의 덮임 유도가 정본). 상한은 `SlashFx._thick_ratio`의
#   **호 길이 항**이 여전히 쥔다 = 덩어리가 되지 않는다(실측: 두께 96.5 < 반호 길이 128.6).
# ⚠ 이 값에서는 근접 4종이 **전부 그 상한에 포화한다** = 스킬 반달의 두께가 무기로 안 갈린다.
#   의도다(그 축의 주인은 하위 직업 틴트이고, 무게는 `sharpness`(끝 모양)로만 남는다).
const SKILL_SLASH_THICK_SCALE := 5.6
# 앞으로 나가는 속도(px/s) — 평타 검기는 330으로 **날아간다**. 스킬 반달은 "시전자 앞에서 터진다"라
#   거의 제자리여야 평타 검기와 구분된다(0이 아닌 이유 = 완전 정지는 도장 찍은 것처럼 굳어 보인다).
const SKILL_SLASH_SPEED := 45.0
const SKILL_SLASH_GHOSTS := 2          # 타마다 남기는 칼 잔상 장수(×`_subjob_fx_ghost`) — "잔상이 남을 만큼 빠르게"
const SKILL_SLASH_GHOST_SPAN := 0.55   # 잔상을 뿌리는 각 폭 / 반달 반각
# 🔴🔴 **공격 선입력 버퍼** (2026-08-01) — 쿨다운·구르기 때문에 지금 못 내는 클릭을 이 시간만큼 들고
#   있다가 조건이 열리는 **첫 프레임에** 발동한다.
#   왜 필요했나: 전에는 `_local_combat`이 `_attack_queued`를 **무조건** 비워서, 사람이 스윙을 보며
#   리듬을 타는 바로 그 타이밍(= 쿨다운 중)에 누른 클릭이 통째로 버려졌다. 그래서 콤보 창
#   (`EquipDef.combo_grace` 0.4s) 안에 **정확히** 재클릭해야만 콤보가 이어지고, 못 이으면
#   `_combo_pose_active`가 꺼져 무기가 중립으로 복귀했다 — 사용자 신고 *"공격마다 무기가 제자리로
#   돌아가는 게 이상하다"* 의 정체다. 콤보 이어가기(`_combo_entry_from_previous`)는 이미 구현돼
#   있었고 **도달을 못 하고 있었다.**
# 🔴 **DPS 상한은 안 움직인다 — 이것이 이 값의 전제이자 GDD §6 🔒 예산 무변경의 근거다.**
#   발동 조건(`_attack_cd_left <= 0.0`)도 쿨다운(`CombatMath.combo_gap_s`)도 그대로다. 버퍼가 바꾸는
#   것은 "이미 낼 수 있었던 타를 놓치지 않는 것"뿐이라, `auto_fire` 특성이 예산 밖으로 인정받은 것과
#   **같은 논거**다(여는 것은 입력 유지 방식이지 상한이 아니다 — `CombatMath.TRAIT_MAX` 주석).
# 🔴🔴 **그러나 간격이 `combo_gap_s`에 딱 붙는 것 자체가 결함이었다** (netreview C-1~C-3, 2026-08-01).
#   사람의 반응 지연이 메워 주던 여유가 사라지고 구조적 마진(`cd × (1 − FIRE_RATE_SLACK)`)만 남는데,
#   **웹 30fps 호스트의 수신 프레임 양자화**가 그중 33.3ms를 먹어 전사 haste 0의 실예산이 6.7ms다.
#   실측 탈락(수정 전): 궁수 10.0ms · 전사 26.7ms · 창은 위험 전이가 둘이라 발생률 두 배.
#   → 처방 = `CombatMath.buffered_attack_grace_s()`(그 함수 주석이 정본). **버퍼가 살려 낸 클릭에만**
#     여유를 물고 즉시 클릭은 **완전 항등**이다 — 구현은 `_attack_buf_grace`(멤버 주석).
# 🔴 **이 값은 쿨다운으로 묶인다**(`_unhandled_input`). 상수만으로는 직업마다 뜻이 갈린다 —
#   전사(cd 0.4)는 쿨다운의 마지막 62%지만 법사(0.5)는 50%, **궁수(0.15)는 167%** 라 쿨다운 전
#   구간이 버퍼 안 = 사실상 클릭 오토파이어가 된다. 묶어 두면 "쿨다운의 마지막 일부"가 전 직업에서 참이다.
# ⚠ 그래서 **너무 일찍 누른 클릭은 여전히 버려진다** — 그게 의도다(무한 선입력이 아니라 리듬 보정).
const ATTACK_BUFFER_S := 0.25

@export var job: JobDef

var peer_id: int = 0
var is_local: bool = false
const SlashFx := preload("res://src/feel/slash_fx.gd")     # 검성 검기 반달(셰이더, 표시 전용)
const SkillFx := preload("res://src/feel/skill_fx.gd")     # 하위 직업 스킬 원/띠(셰이더, 표시 전용)

# 🔴 **호스트가 자기 스킬을 아는 유일한 입구** (2026-08-02). Net에 루프백이 없어 호스트는 자기
#   `G_SKILL`을 **받지 않으므로**, 게스트와 같은 `_on_net_msg` 경로로는 자기 발동이 영영 안 온다
#   (2026-07-25 「호스트 자기 공속」 Critical과 같은 함정 — `_on_player_shoot`이 `EventBus.player_shoot`로
#   같은 구멍을 메운 그 자리다). `CombatAuthority`가 로컬 아바타의 이 시그널에 붙는다.
# ⚠ EventBus가 아니라 노드 시그널인 것은 **core 시그널 추가가 리드 몫**이기 때문이다(rules §0) —
#   `combat_authority.gd`는 이미 `player.gd`를 preload하고 `melee_combo_mult()` 같은 메서드를 직접
#   부르므로 결합도가 새로 생기지는 않는다. 🔴 리드 판단 대기: `EventBus.player_skill`로 올리는 것이
#   `player_shoot` 선례와 일관된다(보고서에 올렸다).
# 🔴 **발동 순간에 정확히 한 번** emit한다 — 선딜이 끝나 `G_SKILL`을 보내는 그 프레임이다.
#   그래야 호스트 자기 판정과 화면 FX가 **같은 순간**에 정렬된다(§3 근접 「선딜+스윕 끝 = 판정」 미러).
signal skill_cast(dir: Vector2)
var scene_id: String = ""  # 소속 씬 (net_schema SCENE_*) — G_POS에 실어 다른 씬 피어의 유령 스폰 방지
# 모닥불 앉기 — 이동·구르기·공격 입력이 들어오면 스스로 풀린다. 공지(G_SIT)는 campfire가 상태 변화를
# 보고 송신. 🔴 **쓰기는 반드시 `set_seated()`를 지난다**(그 함수 주석이 근거 — 선입력 버퍼 회귀).
var seated: bool = false
var equip_atk_bonus: int = 0  # 착용 장비 공격 보너스 (G_STATS 공지/수신) — 호스트가 calc_damage에 더한다
var equip_hp_bonus: int = 0   # 착용 장비 체력 보너스 — max_hp = job.max_hp + 이 값 (set_max_hp로 이월 HP 보존)
# 직업 레벨 5스탯 {crit, crit_dmg, haste, move, leech} (G_STATS "lv" 공지/수신, 성장축 GDD v1.8).
# 호스트가 치명 굴림·피흡 적립·공속 검증에 **자기가 clamp한 이 값**을 읽는다 (combat_authority).
# 장비 스탯(위 2개)과 **분리돼 있다** — 축 경계(GDD §6 🔒): 레벨은 공격력·체력을 건드리지 않는다.
var level_stats: Dictionary = {}
# 하위 직업 특성 {reach, roll_cd, roll_dist, campfire_heal, kill_move, drop_find} (GDD v2.0 §5,
# G_STATS "ms"/"ss" 공지 → 각 클라가 자기 data/subjobs에서 리졸브한 값).
# 🔴 5스탯과 분리: 레벨로 자라지 않고 **낀 자리에 따라** 켜지므로 level_stats에 섞으면 서브 가중·레벨 곱이 붙는다.
var traits: Dictionary = {}
var _kill_move_left: float = 0.0  # 「광란」(kill_move) 남은 지속 — 로컬 연출/이동 전용(네트워크 0)
# 메인 하위 직업의 궤적 아이덴티티 (2026-08-01, GameState.main_fx_of가 리졸브) — **표시 전용**이라
# `traits`와 분리돼 있다: 저쪽은 판정 기하에 들어가고 이쪽은 한 픽셀도 판정을 안 움직인다.
# 🔴 위 `traits`와 **같은 공지(G_STATS "ms")에서 나오지만 값은 각자 로컬 리졸브**다 — 새 필드 0개.
# 기본값이 항등(흰색 · 배율 1)이라 미공지 창·특성 없는 하위 직업은 도입 전과 완전히 같다.
var _subjob_fx_color: Color = Color(1, 1, 1, 1)
var _subjob_fx_ghost: float = 1.0
var _subjob_fx_tex: Texture2D = null  # 리본 질감(null = 단색 = 도입 전 항등)
# 하위 직업 몸 시트(2026-08-02, 옷 색 치환본) — null = 직업 기본(`job.frames`) = 도입 전 항등.
# 🔴 `_weapon_override`와 **같은 이유로 멤버에 보관한다**: `set_job`이 재공지·재합류로 다시 불려도
#   겉모습이 유지돼야 한다. 저쪽 주석이 이미 그 함정을 적어 뒀고 여기가 두 번째 사례다.
var _subjob_frames: SpriteFrames = null

# 무기 겉모습 — 착용 무기(EquipDef.weapon_texture)에서 그린다. 미착용이면 직업 기본 무기로 폴백.
# _weapon_grip은 _update_weapon이 매 프레임 참조 → 착용/직업에 따라 바뀌므로 멤버로 보관(job.weapon_grip 직참 금지).
var _weapon_grip: Vector2 = Vector2(4.0, 8.0)
# 등에 멘 무기인가 — `_update_weapon`의 앞뒤(z) 규칙을 뒤집는다. 무기 교체마다 재대입(EquipDef.weapon_on_back).
var _weapon_on_back: bool = false
var _weapon_override: EquipDef = null       # 마지막 착용 무기 — set_job 재호출(재공지/재합류) 시 겉모습 유지용 보관. null = 무장 해제

# 무기 손맛 — set_weapon_visual이 착용 무기(EquipDef)에서 세팅, 미착용/미지정이면 기본값 폴백. 전부 표시 전용(네트워크 0).
var _swing_color: Color = Color(1, 1, 1, 1)    # 궤적 틴트(페이드 알파와 곱해 적용)
var _swing_sfx: String = "swing"               # 스윙(휘두름) 효과음 id
var _hit_sfx: String = ""                       # 적중 시 무기 고유 타격음 id (비면 무음)
var _hit_shake: float = 1.5                     # 적중 시 스크린셰이크 강도
# 스윙 모션(무기별) — 기본값 = 대검 기준(폴백). ⚠ _swing_time < job.attack_cooldown 유지 (rules §3)
# ⚠ **호 반각 사본(`_swing_arc`)은 v2.2에서 없앴다** — 각은 `_begin_swing`이 `melee_show_half_angle`에서
#   직접 받는다. 멤버로 들고 있으면 마무리 타 분기가 그 값에 배율을 곱하고 싶어지고, 그 순간 표시가
#   판정과 갈라진다(옛 `COMBO_FINISH_ARC`가 정확히 그랬다).
var _swing_time: float = ATTACK_ANIM_TIME
var _swing_time_base: float = ATTACK_ANIM_TIME  # 무기가 준 원본 스윙 창 — _swing_time은 여기에 haste 배율을 곱해 파생한다
var _swing_lunge: float = LUNGE_DIST
# 모션 곡선(무기별) — 전부 표시 전용. 값이 없으면 폴백 = 개편 전과 완전 항등.
var _swing_windup: float = CombatMath.DEFAULT_SWING_WINDUP   # 예비 구간 비율 (0~1)
var _swing_strike: float = CombatMath.DEFAULT_SWING_STRIKE   # 타격 구간 비율 (복귀 = 나머지)
var _swing_ease: String = "smooth"              # 타격 구간 이징 (smooth/accel/decel)
var _swing_pull: float = 0.0                    # 예비에 뒤로 당기는 거리(px) — 찌르기의 주 모션, 0 = 항등
# 궤적 표시 배율 — 위 const 주석이 정본. **표시 전용**이라 무기 데이터(EquipDef)가 아니라 여기 있다
# (rules §0: 손맛 전역 크기는 const, 무기별로 갈리는 것만 데이터). F2 튜너가 실기에서 이 값을 민다.
# 선딜 젖힘 배율 — 위 const 주석이 정본. 표시 전용(각 시작점만 움직인다)이라 여기 있다.
var _windup_arc_mult: float = SWING_WINDUP_ARC_MULT
var _hold_dist: float = HOLD_DIST      # 몸 중심 → 무기 그립 거리 (무기별 = EquipDef.weapon_hold_dist, 대검 8·활 20)
var _arrow_range: float = 360.0         # shoot/charge 무기 투사체 사거리 (무기별 = EquipDef.arrow_range) — 발사 시 G_SHOOT로 전송
var _weapon_id: String = ""             # 착용 무기 id — G_SHOOT "w"(수신 측이 탄 겉모습/속도/폭발 반경을 allowlist 리졸브)
var _charge_step_time: float = 0.0      # charge 무기: 한 단계 모으는 시간(s). 0 = 차지 무기 아님
var _charge_step_time_base: float = 0.0  # 무기가 준 원본 단계 시간 — _charge_step_time은 haste 배율을 곱해 파생
var _charge_sfx: String = "charge_step"  # 단계 상승 효과음 id (무기별 = EquipDef.charge_sfx)

var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _remote_vel: Vector2 = Vector2.ZERO  # G_POS "vx/vy" — 호스트 지연 보상 외삽의 입력 (§3). 수신 시 이동 상한으로 clamp
var _pos_seq: int = 0                   # 내 G_POS 송신 시퀀스(단조 증가) — 수신부 순서 뒤바뀜 폐기의 근거
var _last_pos_seq: int = 0              # 이 원격 피어에게서 받은 마지막 시퀀스 — 이보다 낮으면 옛 패킷
var _send_accum: float = 0.0
var _attack_cd_left: float = 0.0
var _roll_time_left: float = 0.0
var _roll_cd_left: float = 0.0
var _roll_dir: Vector2 = Vector2.RIGHT
var roll_suppressed: bool = false   # 외부(테스트 랩)가 켜면 구르기 입력 무시 — 돌진 중 F=카운터가 구르기와 안 겹치게. 기본 false=프로덕션 무영향
var _fx_left: float = 0.0           # 스윕 완료 뒤 궤적 페이드 잔여(s)
# 🔴 이번 자국의 **총** 페이드 시간(s) — 마무리 타만 `COMBO_FINISH_FX_TIME_MULT`배다.
#   페이드 알파가 `_fx_left / _fx_total`이라 **분모가 같이 커져야** 한다(그 상수 주석이 근거).
var _fx_total: float = ATTACK_FX_TIME
var _swing_fx_armed: bool = false   # 이번 스윙의 궤적이 아직 그려지는 중인가(스윕 완료 시 꺼진다)
# 리본에 마지막으로 찍은 진행값 — 프레임 사이를 보간해 각지지 않게 한다. 음수 = 이번 스윙 첫 점 이전.
var _trail_last_u: float = -1.0
# 🔴 리본의 두 변 — **칼밑(안쪽)·칼끝(바깥)의 월드 좌표를 같은 인덱스로** 쌓는다(칼날 폭 리본).
#   둘을 한 배열의 짝수/홀수로 섞지 않는 이유: 다각형 고리를 만들 때 바깥 변만 **역순**으로 붙여야
#   하는데, 섞어 두면 그 역순 조립이 인덱스 산술로 숨어 다음 사람이 반드시 어긋나게 적는다.
var _trail_base: PackedVector2Array = PackedVector2Array()
var _trail_tip: PackedVector2Array = PackedVector2Array()
# 다음 칼 잔상을 남길 스윕 진행값 — `_arm_swing_trail`이 0으로 되돌린다.
var _ghost_next_u: float = 0.0
# 검기 파형 진행 상태 (표시 전용) — 방향·출발/도착 거리를 스윙 시점에 굳혀 두고 선형 보간한다.
# 🔴 **공격 선입력 버퍼 잔여(s). > 0 = 아직 살아 있는 클릭** (2026-08-01 — 옛 `_attack_queued: bool`).
#   근거는 `ATTACK_BUFFER_S` 상수 주석이 정본. ⚠ **소진(`= 0.0`)은 실제로 발동한 자리에서만 한다** —
#   `_local_combat` 첫 줄에서 비우면 옛 동작(쿨다운 중 클릭 유실)으로 그대로 되돌아간다.
var _attack_buf_left: float = 0.0
# 🔴 **버퍼가 살려 낸 클릭이 추가로 기다리는 시간(s)** (netreview C-1~C-3, 2026-08-01).
#   > 0 = 버퍼는 살아 있지만 아직 못 낸다. 🔴 **쿨다운이 끝난 뒤에만 흐른다** — 쿨다운과 겹쳐 흘리면
#   여유가 통째로 사라져 처방이 조용히 무효가 된다(그게 이 값이 별도 타이머인 이유다).
# 🔴 **무는 조건 = "쿨다운이 막 끝난 프레임에 버퍼가 아직 살아 있다"** — 그 클릭은 버퍼 없이는
#   버려졌을 것이고, 그때만 발사 간격이 `combo_gap_s`에 정확히 붙는다. 쿨다운이 이미 끝난 뒤에 누른
#   **즉시 클릭에는 안 붙는다 = 완전 항등**(사람의 반응 지연이 이미 간격을 벌려 놓았다).
# ⚠ 구르기로 미뤄진 클릭에도 안 붙는다 — 그 경우 간격이 이미 `쿨다운 + 구르기 잔여`라 더 크다.
var _attack_buf_grace: float = 0.0
var _shot_seq: int = 0          # 로컬 발사 카운터 — 투사체 고유 id "my_id:seq" 생성 (shoot/charge 무기)
var _recoil_left: float = 0.0   # 발사 반동 잔여(s) — _update_weapon이 활을 뒤로 당김 (로컬·원격 공용 연출)
# 차지(charge 무기) — 로컬은 입력에서, 원격은 G_POS "c"에서. 레벨 자체는 표시용이고 실제 발사 레벨은 호스트가 재검증(§3).
var _charging: bool = false
var _charge_held: float = 0.0     # 누른 시간(s) — 레벨 = CombatMath.charge_level_for(held, step)
var _charge_level: int = 0
var _remote_charge: int = -1      # 원격 피어의 차지 레벨(-1 = 차지 중 아님) — G_POS "c" 디코드(표시 전용)
var _orb_pop_left: float = 0.0    # 단계 상승 팝 잔여(s)
var _remote_charge_sfx_msec: int = -1000000000  # 원격 차지음 스팸 게이트 앵커
var _last_remote_msec: int = -1
var _alive: bool = true
var bound: bool = false  # 코옵 속박(소울 케이지) — CoopAuthority가 켠다/끈다 (움직임 봉인)
var _saved_layer: int = 0
var _saved_mask: int = 0
var _remote_roll_left: float = 0.0  # 원격 구르기 연출 창 (G_ROLL 수신 — 표시 전용, 판정 아님)
var _attack_anim_left: float = 0.0  # 공격 스윙 창 — 로컬은 공격 발동, 원격은 G_ATK 수신 시 (표시 전용)
var _aim_angle: float = 0.0  # 무기 조준각 — 로컬은 마우스, 원격은 _remote_aim으로 보간
var _remote_aim: float = 0.0  # G_POS "a" 수신 목표각 (표시 전용, 판정 아님)
var _remote_moving: bool = false
var _afterimage_left: float = 0.0   # 다음 잔상까지 남은 시간(s) — 대쉬 중에만 돈다
var _was_dashing: bool = false      # 직전 프레임 대쉬 여부 — 종료 순간(되튐 킥)을 잡는 엣지 감지
var _stance_sway: float = 0.0       # 현재 적용 중인 무기 스탠스 각(rad) — 목표로 부드럽게 따라간다
# 지금 몸통 스프라이트에 걸려 있어야 할 `speed_scale`. 공격 애니만 1.0이 아니다.
# 🔴 **소유자가 매 물리 프레임 재주장해야 한다** — `HitStop.punch()`가 `speed_scale`을 **무조건 1.0으로
#   리셋**하기 때문이다(rules §2 · 그 함수 주석이 근거). 재주장이 없으면 스윙 중 한 대 맞는 순간
#   늘려둔 배율이 날아가 **몸 애니만 스윙 창과 어긋난다**(에러 없음, 화면만). 보스가 밟은 그 자리다.
var _anim_scale: float = 1.0
# 이 스윙이 시작될 때의 스탠스 각 — 🔴 **선딜 동안 0까지 끌어내리는 기준점**이다(`_tick_stance`).
#   lerp로 흘려보내면 프레임률에 따라 잔량이 달라져 "칼만 몇 도 기울어진 채 궤적이 시작"된다.
var _stance_enter_sway: float = 0.0
var _sway_phase: float = 0.0        # 흔들림 위상 — delta로 누적(Time 전역 대신, 일시정지·씬 전환에 안전)
# 근접 스윙 콤보 타수(0..`CombatMath.combo_len(무기) − 1`). 🔴 **v2.2부터 표시 전용이 아니다** —
#   G_ATK "cb"로 나가 호스트의 데미지 배율·판정 각을 고른다(상한으로만 — `authoritative_combo`).
var _combo_index: int = 0
var _combo_left: float = 0.0        # 근접 콤보가 이어지는 남은 시간(s) — 창은 CombatMath.combo_window_s
# 🔴 **이 스윙이 마무리 타인가 — `_begin_swing`이 굳힌다.** 판정 각(`_resolve_swing_hit`)과 표시 각
#   (`_begin_swing`의 `arc`)이 **같은 판단**을 봐야 「표시 ⊇ 판정」이 유지되므로, 스윙 도중 무기 교체·
#   레벨업이 둘을 갈라놓지 못하게 시간 축(`_swing_win_total`)과 같은 자리에서 래치한다(netreview M-1 미러).
var _swing_is_finish: bool = false
# 🔴 **마무리 타 돌진**(`EquipDef.combo_dash` — 창) — px/s. 0 = 이번 스윙은 대시 아님.
#   ⑴ **`velocity`로만 흘린다. `position` 대입 금지** — G_POS의 `vx/vy`가 0이면 호스트 lead 외삽이 그
#      변위를 **원리적으로 못 덮어** 마무리 타가 게스트에서 통째로 무음 거부된다(각 오차 =
#      `asin(변위 ÷ 도달)`가 반각을 넘는다).
#   ⑵ **끝나는 조건이 판정과 같은 플래그(`_swing_hit_armed`)다 — 별도 타이머를 두지 마라.** 판정 전에
#      멈추면 `net_anchor_lead == net_anchor`가 되어 오차 = 대시 거리 **전체**가 남는다(최악).
#      `_physics_process`가 `_tick_timers`(감산) → `_local_move`(velocity) → `_tick_swing_motion`(발화)
#      순서라, 같은 플래그를 보면 **판정 프레임의 velocity가 반드시 살아 있다**.
#   ⑶ 속도를 「선딜 시작 → 판정」 **전 구간**으로 나눈다(스윕에만 몰면 `_max_move_speed` 260px/s를 넘어
#      원격 clamp가 정당한 대시를 깎는다). 나누는 값이 `_swing_hit_left`(스로틀 반영된 **실제** 판정
#      시각)이라 스로틀로 미뤄져도 **이동 거리는 데이터 그대로**다.
# ⚠ 로컬 전용이다 — 원격 아바타의 좌표는 G_POS lerp가 구동하므로 여기서 밀면 수신 좌표와 싸운다.
var _dash_speed: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
# 원거리(shoot/charge) 평타 콤보 — 궁수 "평·평·쭉". 🔴 **근접 콤보와 상태를 공유하지 않는다**:
#   근접은 궤적만 정하는 표시값이지만 이쪽은 사거리·데미지를 바꿔 신뢰 경계가 걸려 있고, 규칙도
#   호스트와 미러여야 한다(CombatMath.advance_combo). 섞으면 근접 손맛 튜닝이 원거리 판정을 움직인다.
# ⚠ 창 판정은 카운트다운 타이머가 아니라 **타임스탬프 간격**이다 — 호스트가 수신 시각으로 같은
#   산술을 하므로(양쪽이 같은 함수를 지나려면) 클라도 같은 형태로 재야 한다.
var _shot_combo_index: int = 0
var _last_shot_msec: int = -1000000000
# 홀드 연사(속사수 `auto_fire` 특성) — 버튼을 누르고 있는 동안 쿨다운마다 자동 발사 중인가.
# ⚠ **엣지로만 켜진다**(첫 발은 반드시 클릭) — 차지와 같은 관용구다: 시작은 `_unhandled_input`이라
#   UI가 소비한 클릭으로는 안 열리고, 유지만 폴링으로 본다. 폴링으로 시작까지 하면 패널 위에서
#   클릭할 때마다 화살이 나간다(rules §5 mouse_filter 규약을 우회하게 된다).
# 🔴 **막는 것은 "시작"뿐이다 — 이미 켜진 연사는 모달 위에서도 이어진다** (2026-07-28 netreview M-2).
#   유지가 원시 폴링(`Input.is_action_pressed`)이라 마우스를 누른 채 F1/I를 열면 Backdrop(STOP)이
#   클릭을 먹는 것과 **무관하게** 화살이 계속 나간다. `_tick_charge`가 같은 트레이드오프를 의도적으로
#   택했으므로(UI 위에서 버튼을 떼도 발사되게) 규약 위반은 아니지만, **실기에서 발사율을 잴 때는
#   패널을 열기 전에 버튼을 떼라** — 안 그러면 로그가 오염된다.
var _auto_firing: bool = false
var _swing_from: float = 0.0        # 이번 스윙의 시작 각 오프셋(rad) — 콤보 타수에 따라 방향이 뒤집힌다
var _swing_to: float = 0.0          # 이번 스윙의 끝 각 오프셋(rad)
var _swing_lunge_mult: float = 1.0  # 이번 스윙의 내지르기 배율(마무리 타만 크게)
# 스윙 "박힘"(적중 순간 무기가 잠깐 멎는 손맛) — 공격자 로컬 표시 전용. 창 길이는 안 건드린다(위 상수 주석).
var _swing_bite_left: float = 0.0   # 박혀서 멎어 있는 남은 시간
var _swing_bite_t: float = 0.0      # 멎은 순간의 모션 파라미터 — 그 자리에 붙들어 둔다
# 🔴 **이번 스윙의 방향 — 클릭 순간 고정되고 스윙이 끝날 때까지 안 바뀐다** (선딜 축 2026-07-28).
#   무기 스프라이트·궤적·판정·G_ATK·원격 재생이 **전부 이 하나**를 쓴다. 라이브 조준각(`_aim_angle`)을
#   쓰면 선딜 동안 마우스를 돌렸을 때 ⑴ 내 칼과 궤적이 어긋나고(도입 전에도 이미 그랬다) ⑵ 상대
#   화면은 G_ATK에 실린 클릭 방향으로 그려서 **두 화면이 서로 다른 곳을 벤다.** 근거는 `_swing_attack`.
var _swing_dir: Vector2 = Vector2.RIGHT
# 🔴 **판정까지 남은 시간(s). > 0 = 판정 예약 중.** 불리언 + "`p >= 1`인 프레임 관측"이 아니라
#   **카운트다운**인 이유가 둘이다:
#   ⑴ (netreview I-2) `p >= 1`인 프레임이 한 번도 안 오는 데이터(후딜 창 < 1프레임)에서도 판정이
#      난다 — **프레임 격자 의존이 구조적으로 사라진다**(캐치올 래치보다 강하다).
#   ⑵ (netreview M-1의 실제 결과) 앞 스윙보다 `t_hit`가 짧은 무기로 바꾸면 호스트 게이트 아래로
#      내려가는데, **여기서 뒤로 물러설 수 있다**(아래 `_swing_attack`의 자기 스로틀).
var _swing_hit_left: float = 0.0
# 🔴🔴 **감산은 `_tick_timers`에서 — `_attack_anim_left`와 같은 자리여야 한다.** 자체 점검에서
#   잡았다(2026-07-28): `_tick_swing_motion`에서 깎으면 스윙이 시작된 프레임에 **이 값만 한 번 더**
#   깎인다(창은 `_tick_timers` **뒤에** 대입되므로 그 프레임엔 안 깎인다). 그러면 판정이 궤적보다
#   **정확히 한 프레임 먼저** 나고, 그 순간 **19.1°가 안 그려진 채로 확정**된다 — M-2가 없애려던
#   결함이 감산 위치 때문에 같은 크기로 되살아난다.
#   같은 자리에 두면 두 조건이 `n × delta ≥ _swing_hit_at`로 **문자 그대로 같아져** 락스텝이 구조가 된다.
var _swing_hit_armed: bool = false
# 마지막으로 **적중을 확정한**(= G_HIT_REQ를 보낸) 시각(ms). 호스트의 `last_confirm_msec` 로컬 미러 —
# 호스트도 확정 때만 앵커를 옮기므로(헛치면 안 옮긴다) 여기도 `connected`일 때만 갱신한다.
var _last_swing_hit_msec: int = -1000000000
var _swing_onset_pending: bool = false  # 스윕 시작 이벤트(휘두름 소리·검기 파형)가 아직 안 났는가
# 이 프레임의 모션 출력 — `_tick_swing_motion`이 **한 번** 계산하고 `_update_weapon`이 소비한다.
# 🔴 무기 각과 궤적 진행이 같은 계산에서 나오게 하는 장치다(사본을 만들면 또 갈라진다).
var _motion_off: float = 0.0
var _motion_lunge: float = 0.0
# 콤보 연결 포즈. 공격이 끝난 뒤에도 칼/도끼/창의 끝 자세를 콤보 창 동안 유지해,
# 다음 타가 기본 자세가 아니라 직전 타의 끝에서 출발하게 한다. 표시 전용이다.
var _combo_pose_active: bool = false
var _combo_entry_off: float = 0.0
var _combo_entry_lunge: float = 0.0
var _combo_entry_from_previous: bool = false
# 🔴 **마무리 직전 타의 젖힘 진행(0~1)** — 위 `COMBO_WINDBACK_*` 주석이 정본.
#   ⚠ **스윕이 끝난 뒤에만 흐른다**(`_tick_combo_windback`의 `_swing_fx_armed` 가드) — 스윕 중에
#     흐르면 대기 자세가 아니라 **스윙 중인 칼**을 밀어 궤적이 판정 각과 갈라진다.
#   ⚠ 리셋은 `_begin_swing`·`_cancel_swing` 둘뿐이다. 조건이 잠깐 거짓이 될 때 0으로 되돌리면
#     (예: 콤보 창이 닫히는 프레임) 자세가 **한 프레임 튄다**.
var _windback_t: float = 0.0
# 🔴 이번 타의 젖힘 **소요 시간**(s) — `_begin_swing`이 그 타의 실제 빈 구간에서 유도한다
#   (상수 주석이 정본). 상수로 두면 짧은 구간의 타에서 젖힘이 덜 진행된 채 다음 타가 나간다.
var _windback_time: float = COMBO_WINDBACK_MAX_S
# 🔴 **타별 감각 점증의 단일 진행값** (0 = 첫 타 · 1 = 마무리). 리본 알파·잔상 장수·자국 지속·
#   스윙 반동·적중 박힘이 **전부 이것 하나**를 지난다 — 축마다 따로 두면 다음 튜닝에서 갈라진다.
# ⚠ 콤보 없는 무기(n = 1)는 항상 0 = 도입 전과 완전 항등이다.
var _combo_ramp: float = 0.0
# 🔴🔴 **이 스윙이 태어날 때 굳힌 시간 축** (netreview M-1, 2026-07-28).
#   `t`를 **살아 있는** `_swing_time`/`_swing_windup`에서 구하면 스윙 도중 그 값이 바뀔 때
#   **판정 시점이 움직인다.** 그리고 판 도중 장비 변경 경로는 **열려 있다** — 내가 "F1뿐"이라고
#   본 것은 틀렸다: `stage_hud`의 I키 인벤 → `inventory_panel` → `GameState.equip()`에는
#   `in_chapter` 가드가 없다(`subjob_panel`엔 있는데 인벤엔 없다). 레벨업
#   (`growth_changed` → `_refresh_growth_derived`)도 같은 경로다.
#   실측: 도끼(t_hit .216) → 낡은 대검(.132)으로 바꾼 직후 한 타의 도달 간격이
#   `400 + 132 − 216 = 316ms` < 요구 360ms가 되어 호스트가 **무음 거부**한다
#   (스윙·궤적·소리·반동은 다 나오고 **적 HP만 안 깎인다** · 에러 0 · **호스트 자신도 걸린다**).
#   굳혀 두면 기획 변경 없이 닫히고 **신뢰 경계 변화가 0**이다.
# ⚠ "판 도중 장비 교체를 허용하나"는 별개의 기획 질문이다 — 여기서 답하지 않는다.
var _swing_win_total: float = ATTACK_ANIM_TIME   # 이 스윙의 창 길이 (태어날 때의 _swing_time)
var _swing_windup_l: float = CombatMath.DEFAULT_SWING_WINDUP  # 이 스윙의 선딜 비율
var _swing_strike_l: float = CombatMath.DEFAULT_SWING_STRIKE  # 이 스윙의 스윕 비율
var _swing_hit_at: float = 0.0  # 판정이 나는 경과 시각(s) = 창 × (선딜 + 스윕) — 위 셋에서 파생
# 원격 G_ATK 스팸 게이트 앵커 — 마지막으로 **받아들인** 공격 연출 시각(ms). 근거 = play_attack_fx.
var _last_atk_fx_msec: int = -1000000000
var _swamp_factors: Array[float] = []  # 현재 겹친 늪들의 이동 배율 (SwampZone enter/exit로 추가·제거). 걷기 속도에 min 적용, 구르기 예외

var _prev_hp: int = 0  # 피격 손맛(combat_impact 감소량) 계산용 — hp_changed 표시 경로 추적

# --- 하위 직업 스킬 (Q, 2026-08-02) — 메인 자리 하나당 하나(GDD §3 조작 · §11 「직업별 스킬 구성」) ---
# 🔴 **로컬 쿨다운 앵커 = `G_SKILL`을 실제로 보낸 시각**이다(누른 시각이 아니다). 호스트는 자기
#   **수신 시각**으로 재므로(`is_skill_ready`), 앵커를 「누름」에 두면 선딜 길이만큼 두 시계가
#   체계적으로 어긋난다. 보낸 시각에 두면 두 간격이 「클라 간격 + (편도₂ − 편도₁)」로만 갈리고
#   그 지터는 쿨다운 8~9s 대비 무시할 수준이다(근접 `melee_throttle_gap_s`가 필요했던 것은
#   쿨다운이 0.4s이고 `t_hit`가 무기마다 달라서다 — 여기는 두 항 다 없다).
# ⚠ 씬마다 리셋된다(아바타가 씬마다 새로 태어난다). 호스트 쪽 `_skill_msec`도 **씬 컴포넌트**라
#   같이 리셋되므로 두 시계가 함께 열린다 = 스테이지 입장마다 스킬 1회가 즉시 준비된 상태다(의도).
var _last_skill_msec: int = -1000000000
# 선딜(`SkillDef.windup_s`) 잔여. > 0 = 시전 중 — 🔴 이 창에서 Q를 다시 눌러도 안 나간다(이중 발동 차단).
var _skill_windup_left: float = 0.0
# 🔴 **발동 순간에 고정된 방향** — 라이브 마우스(`_aim_angle`)를 쓰지 않는다. 검기가 `_swing_dir`을
#   쓰는 것과 **같은 이유**이고(player.gd `_try_spawn_slash` 주석), beam은 **축이 곧 판정**이라
#   더 세다: 선딜 동안 마우스가 돌면 화면의 띠와 호스트가 세우는 캡슐이 통째로 갈라진다.
var _skill_dir: Vector2 = Vector2.RIGHT
# 시전 중인 스킬 — 선딜이 끝나는 프레임에 FX·질의·`G_SKILL`이 **전부 이 한 값**에서 파생한다.
# 🔴 발동 순간에 굳혀 둔다(선딜 중 하위 직업이 바뀌어도 그 시전은 처음 것으로 끝난다 —
#   안 굳히면 "쿨다운은 A가 먹고 데미지는 B가 내는" 조합이 열린다).
var _skill_pending: SkillDef = null
# --- 다단 스킬의 남은 **표시** 타 (2026-08-02 「환영검무」) ---
# 🔴 **로컬·원격이 같은 멤버를 쓴다** — `play_skill_fx`가 두 경로의 단일 지점이라(로컬 = `_fire_skill`
#   / 원격 = `peer_sync`의 G_SKILL 중계) 반복도 거기서 걸리면 양쪽이 자동으로 같은 그림이 된다.
# 🔴 **네트워크 메시지·필드 0.** 타수·간격은 각 클라가 자기 `SkillDef`에서 리졸브하므로(로컬 =
#   `GameState.active_skill` · 원격 = `peer_sync.peer_skill`) 실을 것이 애초에 없다 — 호스트가
#   `_skill_ticks`로 도는 것과 **같은 데이터·같은 clamp**라 타수가 갈라지지 않는다.
# ⚠ 한 칸뿐이다 = 새 시전이 진행 중이던 반복을 **대체**한다(호스트 `_skill_ticks`와 같은 규약).
var _skill_fx_def: SkillDef = null
var _skill_fx_dir: Vector2 = Vector2.RIGHT
var _skill_fx_left: int = 0
var _skill_fx_timer: float = 0.0
# 이번 시전에서 지금까지 그린 타 번호(0 = 첫 타) — 🔴 **반달 좌우 교대의 유일한 소스**다.
# ⚠ 로컬·원격 공용이다(`play_skill_fx`가 0으로 되돌린다) — 두 화면의 교대 순서가 같아야
#   "내 쪽은 오른쪽부터, 상대 쪽은 왼쪽부터"가 안 생긴다. 판정과는 무관하다(순수 표시).
var _skill_fx_index: int = 0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _swing_trail: Polygon2D = $SwingTrail  # 칼날 폭 리본 궤적 — 표시 전용(판정 무관)
@onready var _health: HealthComponent = $Health
@onready var _weapon_pivot: Node2D = $WeaponPivot
@onready var _weapon: Sprite2D = $WeaponPivot/Weapon
@onready var _camera: Camera2D = $Camera
@onready var _shadow: Sprite2D = $Shadow
@onready var _dust: CPUParticles2D = $Dust
@onready var _charge_orb: Sprite2D = $ChargeOrb


func _ready() -> void:
	add_to_group("player")
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	# 권한 경로(호스트의 apply_damage/confirm_hp)에서만 발화 — 게스트 표시 경로는 confirm_hp_from_net이 별도 emit
	_health.hp_confirmed.connect(_on_hp_confirmed)
	# 표시 경로(모든 클라 — 호스트 apply_damage·게스트 set_hp_display 둘 다) — 피격 손맛 연출
	_health.hp_changed.connect(_on_hp_changed_feel)
	if job != null:
		_health.setup(job.max_hp)
		_prev_hp = job.max_hp
	# @onready 자식에 의존하는 무기 표시값(차지 오브 텍스처) 재적용 — set_weapon_visual이 _ready 전에
	# 불리는 경로가 생겨도 오브가 조용히 무텍스처로 남지 않게 (현 호출 경로는 전부 ready 이후, 심층 방어)
	_apply_weapon_feel(_weapon_override)
	# 「광란」(kill_move) 트리거 — 적 사망 표시 훅에 매단다(손맛 계층 규약: 이미 모든 클라에서
	# 1회씩 발화하는 훅을 재사용 → **네트워크 메시지 0개**). 원격 인스턴스는 자기 좌표를 수신으로
	# 받으므로 버프를 굴릴 필요가 없다 — 대신 clamp는 _max_move_speed가 항상 관대하게 잡는다.
	EventBus.entity_died.connect(_on_entity_died)


func setup(p_peer_id: int, p_is_local: bool, spawn_pos: Vector2, p_scene_id: String) -> void:
	peer_id = p_peer_id
	is_local = p_is_local
	scene_id = p_scene_id
	global_position = spawn_pos
	_remote_target = spawn_pos
	_camera.enabled = is_local  # 로컬 플레이어만 현재 카메라 (원격 인스턴스는 뷰포트 안 잡음)
	if not is_local:
		_sprite.modulate = REMOTE_TINT
	set_job(job)


# 직업 적용 — 애니 프레임까지 교체. 원격은 G_JOB 공지 수신 시 stage가 다시 부른다.
func set_job(j: JobDef) -> void:
	if j == null:
		return
	job = j
	_apply_body_frames()
	# 무기 겉모습은 착용 무기(EquipDef)에서만 그린다(무기 = 장비). 직업 재공지/재합류로 set_job이
	# 다시 불려도 override(마지막 착용) 재적용해 겉모습 유지. 미착용이면 무장 해제(무기 미표시).
	set_weapon_visual(_weapon_override)
	if is_node_ready():
		# setup이 아니라 set_max_hp — 직업 재공지가 챕터 이월 HP(호스트 확정)를 풀피로 되돌리지 않게
		_health.set_max_hp(j.max_hp + equip_hp_bonus)  # 장비 체력 보너스 유지


# 장비 총 스탯 반영 — 로컬은 GameState.current_stats(), 원격은 G_STATS 수신(peer_sync가 부른다). max_hp 재계산.
func set_equip_stats(atk: int, hp: int) -> void:
	equip_atk_bonus = maxi(0, atk)
	equip_hp_bonus = maxi(0, hp)
	_apply_max_hp()


func _apply_max_hp() -> void:
	if job != null and is_node_ready():
		_health.set_max_hp(job.max_hp + equip_hp_bonus)


# 직업 레벨 5스탯 반영 — 로컬은 GameState.current_level_stats(), 원격은 G_STATS "lv" 수신(peer_sync가 부른다).
# 🔴 여기서 한 번 더 clamp한다(수신부 clamp와 이중): 이 인스턴스의 값이 곧 호스트 판정 입력이라
#   경로 어디서든 오염값이 새어들면 안 된다. 하드 상한(CombatMath.LEVEL_STAT_MAX)은 항상 적용된다.
func set_level_stats(stats: Dictionary) -> void:
	level_stats = CombatMath.clamp_level_stats(stats)
	_refresh_growth_derived()


# 하위 직업 특성 반영 (GDD v2.0 §5).
# 로컬 = GameState.active_traits() · 원격 = 그 피어가 공지한 하위 직업 id들을 리졸브한 값
# (둘 다 peer_sync가 넣는다 — 로컬은 _peer_stats에 항목이 없으므로 GameState에서 직접).
# 🔴 **호스트는 판정에 쓸 특성을 항상 "공격자 아바타"에서 읽는다**(combat_authority) — 이 인스턴스가
#   그 단일 소스다. peer_sync._peer_stats에는 로컬 항목이 영원히 없어서(Net 루프백 없음) 그쪽을
#   읽으면 "내 것만 안 먹힌다"가 된다 — 2026-07-25 공속 Critical과 같은 함정.
# 🔴 reach 하나가 **판정 기하·스워시 크기·파형 연출을 동시에** 움직인다(§3 사거리 계약).
#   한쪽만 받으면 "맞는 곳 ≠ 보이는 곳"이 되고, 그건 에러 없이 손맛으로만 드러난다.
# 여기서 한 번 더 clamp한다(수신부 clamp와 이중) — set_level_stats와 같은 규약.
func set_traits(t: Dictionary) -> void:
	traits = CombatMath.clamp_traits(t)


# 메인 하위 직업 궤적 아이덴티티 반영 (2026-08-01) — **표시 전용**.
# set_traits와 **같은 자리에서 같은 공지로** 불린다(peer_sync): 로컬 = GameState.active_main_fx() ·
#   원격 = 그 피어가 공지한 "ms"를 리졸브한 값. 🔴 둘을 갈라 놓으면 "특성은 검성인데 색은 광전사"가
#   되고, 그건 화면만 보고는 어느 쪽이 틀렸는지 알 수 없는 종류의 어긋남이다.
# 🔴 clamp는 GameState.main_fx_of가 이미 지났다(→ CombatMath.fx_ghost_mult) — 여기서 다시 하지
#   않는 것은 저쪽이 **유일한 리졸브 경로**이기 때문이다(set_traits의 이중 clamp와 다른 점: 저쪽은
#   네트워크 payload가 직접 들어오지만 여기 오는 것은 항상 로컬 .tres에서 나온 값이다).
func set_subjob_fx(fx: Dictionary) -> void:
	var c: Variant = fx.get("color", Color(1, 1, 1, 1))
	_subjob_fx_color = (c as Color) if c is Color else Color(1, 1, 1, 1)
	_subjob_fx_ghost = float(fx.get("ghost", 1.0))
	var t: Variant = fx.get("tex")
	_subjob_fx_tex = (t as Texture2D) if t is Texture2D else null
	var f: Variant = fx.get("frames")
	_subjob_frames = (f as SpriteFrames) if f is SpriteFrames else null
	_apply_body_frames()


# 몸 시트 **단일 대입 지점** — 하위 직업 시트가 있으면 그것, 없으면 직업 기본(항등).
# 🔴 `set_job`과 `set_subjob_fx` **둘 다** 여기를 지난다. 각자 대입하면 호출 순서에 따라
#   하위 직업 겉모습이 직업 기본으로 조용히 덮인다 — 두 함수는 peer_sync가 공지마다 부르므로
#   순서가 고정돼 있지 않다. 관용구는 `_apply_anim_scale()`과 같다(rules §2: 소유자가 자기
#   의도를 유일한 대입 지점에 모은다).
# 🔴 **같은 시트면 아무것도 하지 않는다 — 이 가드가 계약이다.** 없으면 `set_subjob_fx`가
#   G_STATS 공지마다 불리면서 원격 아바타의 애니를 **매번 idle로 리셋**한다(달리다 말고 멈춘 것처럼
#   보이는데 에러는 없다). `sprite_frames`는 대입만으로 재생 상태를 날리므로 비교가 먼저다.
func _apply_body_frames() -> void:
	if _sprite == null:   # @onready — setup()이 _ready보다 먼저 오는 경로 대비(항등)
		return
	var want: SpriteFrames = _subjob_frames
	if want == null and job != null:
		want = job.frames
	if want == null or _sprite.sprite_frames == want:
		return
	_sprite.sprite_frames = want
	# 🔴 **`play("idle")` 직접 호출 금지 — 방향 시트엔 무접미사 `idle`이 없다**(2026-08-01).
	#   새 전사 시트는 `idle_e`/`_s`/`_n`뿐이라 그대로 두면 **한 프레임짜리 에러 로그**가 났다.
	#   다음 프레임에 `_update_anim`이 회복시켜 **화면은 멀쩡하므로 더 안 보인다.**
	#   `_play_dir_anim`을 지나면 조회 규칙이 한 곳으로 모이고 무접미사 폴백도 그 안에 있다.
	# ⚠ `_aim_angle`은 이 시점에 유효하다 — 기본값 0.0이 곧 동쪽이고(`_facing_index(0)` = 0),
	#   `setup()`이 `set_job`을 부른 다음 프레임부터 `_update_aim`이 실값을 넣는다.
	_play_dir_anim(&"idle")
	# 시트가 바뀌면 이전 시트에 걸려 있던 배율도 초기화한다 — 안 하면 새 시트 idle이
	# 옛 공격 배율로 돈다(`speed_scale`은 클립이 아니라 **노드** 속성이다).
	_anim_scale = 1.0
	_apply_anim_scale()


# 이 아바타의 특성값 — 모르는 키/미설정은 0(항등).
func trait_value(key: String) -> float:
	return float(traits.get(key, 0.0))


# 🔴🔴 **모닥불 앉기의 유일한 진입점** (reviewer C-1, 2026-08-01). `seated`에 직접 대입하지 마라.
#   선입력 버퍼가 만든 회귀를 닫는다: 쿨다운 중에 누른 클릭이 **0.25s 동안 살아 있으므로**,
#   그 창 안에 F로 앉으면 ⑴ 다음 프레임 `_local_move`가 그 묵은 버퍼를 "입력이 왔다"로 읽어 즉시
#   기상시키고 ⑵ 같은 프레임 `_local_combat`이 버퍼를 소진하며 **스윙까지 나가고** ⑶ `campfire`가
#   `G_SIT` on→off 두 통을 쏜다. 화면에는 ***"F가 안 먹힌다"*** 로만 보인다.
#   ⚠ 옛 코드에선 `_attack_queued`가 매 프레임 비워져 이 창이 **1프레임**(사실상 도달 불가)이었다 —
#     버퍼가 그 창을 250배로 넓혔고, **전투 직후 모닥불은 챕터1 정규 동선**이다.
# 🔴 지우는 것은 **앉기 이전의 묵은 클릭뿐**이다. 앉은 **뒤에** 새로 누른 클릭은 `_unhandled_input`이
#   버퍼를 다시 채우므로 여전히 기상시킨다 = GDD §5 *"입력이 오면 스스로 일어난다"* 유지.
# 🔴 **`_local_move`의 조건을 `Input.is_action_just_pressed("attack")`으로 되돌려 고치지 마라** —
#   공격 입력이 `_unhandled_input`인 이유(UI가 소비한 클릭은 안 온다 = `mouse_filter` 규약)를 깬다.
func set_seated(on: bool) -> void:
	seated = on
	if on:
		_attack_buf_left = 0.0
		_attack_buf_grace = 0.0


# 「광란」(kill_move) — 적이 쓰러지면 잠깐 빨라진다. **로컬 아바타만** 굴린다(원격은 좌표를 수신으로 받는다).
# 🔴 협동이라 **누가 막타를 냈는지 묻지 않는다** — EXP 전원 동일 지급과 같은 철학이고, 막타는 호스트만
#   아는 정보라 게스트에게 알리려면 새 메시지가 필요하다(그만한 값이 안 나온다).
func _on_entity_died(kind: String, _world_pos: Vector2, respawns: bool) -> void:
	if not is_local or kind != "enemy":
		return
	# 🔴 **되살아나는 적(훈련용 허수아비)은 광란을 주지 않는다** — 안 그러면 시험장에서 버프가
	#   **상시 유지**된다(때리고 또 때리면 되니까). 데이터 값(`exp`)을 0으로 두는 것에 기대지 않고
	#   `exp_authority`가 EXP를 **코드로** 제외한 것과 같은 자리다 — 다음 사람이 값을 넣으면 그만이니까.
	#   rules §2가 "허수아비를 씬에 배치하기 전"의 선행 조건으로 걸어 뒀던 항목이고, 시험장을 만들면서
	#   해소했다(2026-07-28).
	if respawns:
		return
	if trait_value("kill_move") > 0.0:
		_kill_move_left = CombatMath.KILL_MOVE_TIME_S


# 레벨 스탯에서 파생되는 표시/이동 값을 다시 계산한다. 입력이 둘(레벨 스탯 변동·무기 교체)이라
# 반드시 한 함수로 모은다 — 한쪽에서만 갱신하면 무기를 바꾼 뒤 공속이 사라지는 식으로 조용히 갈라진다.
# 🔴 스윙 창·차지 스텝에 쿨다운과 **같은 배율**(haste_scale)을 곱하는 것이 §3 계약이다:
#   그래야 swing_time < attack_cooldown 부등식이 haste 어디서나 보존되고, 원격 창-잠금 가드가
#   빨라진 피어의 정당한 연속 공격 연출을 삼키지 않는다(원격 인스턴스도 그 피어의 haste로 파생된다).
func _refresh_growth_derived() -> void:
	var k := CombatMath.haste_scale(_haste())
	_swing_time = _swing_time_base * k
	_charge_step_time = CombatMath.effective_charge_step(_charge_step_time_base, _haste())


# 이 아바타의 공속 보너스 (로컬 = 내 레벨, 원격 = 그 피어가 공지한 값 — 둘 다 clamp된 값이다)
func _haste() -> float:
	return float(level_stats.get("haste", 0.0))


# 이 아바타의 실효 이동속도 — 로컬 이동과 **원격 위치 clamp가 같은 값을 써야 한다**(§3).
# 원격 clamp만 기본 이속으로 남기면 빨라진 정당 이동이 깎여 외삽이 과소평가되고,
# 2026-07-24에 고친 "피했는데 맞았다"가 빠른 피어에게 재발한다.
func _move_speed() -> float:
	if job == null:
		return 0.0
	# 「광란」(kill_move) — 적을 처치한 뒤 잠깐 빨라진다. 5스탯 move와 **같은 축이라 더해서** 넘긴다:
	# 그러면 원격 변위 clamp·외삽 상한도 자동으로 같은 값을 보고(_roll_speed 경유), 빨라진 정당
	# 이동이 깎이지 않는다(§3 이동속도 계약). 상한은 effective_move_speed 안의 clamp_move가 건다.
	var m := float(level_stats.get("move", 0.0))
	if _kill_move_left > 0.0:
		m += trait_value("kill_move")
	return CombatMath.effective_move_speed(job.move_speed, m)


# 🔴 **clamp 전용 상한** — kill_move를 타이머와 무관하게 **항상** 포함한다.
#   버프 창은 각 클라의 로컬 타이머라 호스트의 원격 인스턴스와 몇십 ms 어긋날 수 있는데,
#   clamp가 그 순간 좁으면 빨라진 정당 이동이 깎여 외삽이 과소평가되고 "피했는데 맞았다"가
#   부분 재발한다(§3). clamp는 상한이므로 관대한 쪽으로 틀리는 것이 안전한 방향이다.
func _max_move_speed() -> float:
	if job == null:
		return 0.0
	return CombatMath.effective_move_speed(
		job.move_speed, float(level_stats.get("move", 0.0)) + trait_value("kill_move"))


# 이 아바타의 구르기 속도 — 로컬 이동용(현재 버프 상태 반영).
func _roll_speed() -> float:
	return CombatMath.effective_roll_speed(_move_speed(), trait_value("roll_dist"))


# 원격 속도/변위 clamp용 구르기 상한 — 위와 같은 유도식에 관대한 이동 상한을 넣는다(§3).
func _max_roll_speed() -> float:
	return CombatMath.effective_roll_speed(_max_move_speed(), trait_value("roll_dist"))


# 구르기 쿨 남은 비율 0.0~1.0 (1 = 방금 굴러 꽉 참, 0 = 지금 구를 수 있음). **HUD 표시 전용 읽기 접근자**
# — 상태를 바꾸지 않는다. (특성 축 절반이 구르기에 걸리는데 남은 쿨이 안 보이면 −%가 체감되지 않는다, GDD v2.0)
# 🔴 분모는 상수 ROLL_COOLDOWN_S가 아니라 **현재 특성이 반영된 유효 쿨**이다 — 상수로 나누면
#   roll_cd 특성이 켜졌을 때 바가 끝까지 안 차 "감소가 안 걸린 것처럼" 보인다(§3 단일 소스와 같은 이유).
func roll_cooldown_ratio() -> float:
	if _roll_cd_left <= 0.0:
		return 0.0
	var total := CombatMath.effective_roll_cooldown(trait_value("roll_cd"))
	if total <= 0.0:
		return 0.0
	return clampf(_roll_cd_left / total, 0.0, 1.0)


# 무기 겉모습 적용 — 착용 무기(equip)의 텍스처/그립, 없으면(null·텍스처 없음) 직업 기본 무기로 폴백.
# 로컬은 peer_sync가 GameState 착용 무기로, 원격은 G_STATS의 weapon id 리졸브로 부른다 (표시 전용, 판정 무관).
func set_weapon_visual(equip: EquipDef) -> void:
	_weapon_override = equip  # 재공지/재합류 대비 마지막 착용 무기 보관 (set_job이 재적용)
	var tex: Texture2D = null  # 미착용 = 무장 해제 (직업 폴백 없음 — 무기 = 장비)
	var grip := Vector2(4.0, 8.0)
	if equip != null and equip.weapon_texture != null:
		tex = equip.weapon_texture
		grip = equip.weapon_grip
	_weapon.texture = tex
	_weapon_grip = grip
	_weapon.position = -grip + Vector2(_hold_dist, 0.0)
	# 🔴 회전 중심은 **매번 전량 대입한다** — 노드가 재사용돼 무기를 오가므로, 지정 없는 무기로
	#   바꿨을 때 대입을 건너뛰면 이전 무기(어깨)의 피벗이 그대로 남는다(궤적 셰이더 유니폼과 같은 함정).
	#   씬(`player.tscn`)의 WeaponPivot position은 에디터 미리보기용이고 런타임 진실원은 여기다.
	_weapon_pivot.position = equip.weapon_pivot if equip != null else WEAPON_PIVOT_DEFAULT
	_weapon_on_back = equip != null and equip.weapon_on_back
	_weapon_pivot.visible = tex != null
	_apply_weapon_feel(equip)


# 무기 손맛(궤적 색·SFX·타격 셰이크·스윙 모션) 반영 — 착용 무기가 지정하면 그 값, 아니면 대검 기본.
# ⚠ 궤적의 **각·반지름·회전중심**은 여기서 안 정한다 — 리본은 칼끝·칼밑 좌표를 그대로 잇고 잔상은 칼
#   스프라이트를 그대로 복제하므로, 그 축을 정하는 데이터가 **존재하지 않는다**(2026-07-29).
# 🔴 **그러나 폭은 데이터다 — `EquipDef.blade_length`**(칼날 폭 리본 2026-08-01). 여기서 멤버로 캐시하지
#   않고 `_blade_base_global`이 `CombatMath.blade_length()`로 **매번 리졸브**한다(단일 소스 유지).
#   ⚠ *"형태를 정하는 데이터가 존재하지 않는다"* 는 옛 서술은 **거짓이 됐다** — 리본이 칼끝 한 점일
#     때의 이야기이고, 면이 되면서 「어디까지가 날인가」가 데이터가 됐다.
# set_weapon_visual이 로컬·원격 모두 부르므로 무기 교체 시 손맛도 자동으로 갈린다 (표시 전용, 판정 무관).
func _apply_weapon_feel(equip: EquipDef) -> void:
	_swing_color = equip.swing_color if equip != null else Color(1, 1, 1, 1)
	_swing_sfx = equip.swing_sfx if equip != null and not equip.swing_sfx.is_empty() else "swing"
	_hit_sfx = equip.hit_sfx if equip != null else ""
	_hit_shake = equip.hit_shake if equip != null else 1.5
	# 스윙 모션 — 무기 지정값, 미착용이면 대검 기본. swing_time은 §3 미러(< attack_cooldown) 유지.
	_swing_time_base = equip.swing_time if equip != null else ATTACK_ANIM_TIME
	_swing_lunge = equip.swing_lunge if equip != null else LUNGE_DIST
	_swing_ease = equip.swing_ease if equip != null else "smooth"
	_swing_pull = maxf(equip.swing_pull, 0.0) if equip != null else 0.0
	_apply_motion_shape(equip)
	_hold_dist = equip.weapon_hold_dist if equip != null else HOLD_DIST  # 큰 무기(활)는 멀리 잡아 몸과 안 겹침
	_arrow_range = equip.arrow_range if equip != null else CombatMath.DEFAULT_ARROW_RANGE  # shoot/charge 사거리
	_weapon_id = equip.id if equip != null else ""  # G_SHOOT "w" — 수신 측 탄 겉모습/속도/폭발 반경 리졸브 키
	# 차지(charge 무기) — 무기가 바뀌면 모으던 것도 취소한다(무장 해제·교체 중 유령 오브 방지)
	var is_charge := equip != null and equip.motion_type == "charge"
	_charge_step_time_base = equip.charge_step_time if is_charge else 0.0
	_charge_sfx = equip.charge_sfx if (is_charge and not equip.charge_sfx.is_empty()) else "charge_step"
	# 무기가 바뀌면 콤보도 처음부터 — 리듬은 무기가 정하므로 옛 무기의 타수를 이어받으면 새 무기의
	# 배율 배열에 엉뚱한 칸이 걸린다(호스트는 자기 간격으로 세니 표시만 어긋난다).
	_shot_combo_index = 0
	# 🔴 근접도 같이 리셋한다(v2.2) — 근접 타수가 이제 **데미지와 판정 각**을 고르므로, 옛 무기의
	#   타수를 새 무기에 물려주면 그 배열의 엉뚱한 칸이 판정에 걸린다. 방향은 **안전한 쪽**이다:
	#   0으로 떨어뜨리면 `authoritative_combo`의 `min`이 그 주장을 상한으로 써 판정도 평타가 된다.
	# ⚠ `_last_shot_msec`은 여기서도 안 지운다(그쪽 규율과 같은 이유 — 호스트는 자기 기록을 안 지운다).
	_combo_index = 0
	_combo_left = 0.0
	# 🔴 **비행 중 스윙도 끊는다 — `_swing_is_finish`가 래치된 채 남으면 판정이 새 무기 기준으로
	#   넓어진다** (리뷰 Minor, 2026-07-29). 예: 낡은 대검 마무리(표시 2.55)로 휘두르는 중에 도끼로
	#   교체하면 `_resolve_swing_hit`이 도끼의 마무리 각 기준으로 물어 **판정이 표시보다 0.35 rad
	#   넓어진다**(= 안 보이는데 맞는다, §3 금지 방향). 도달성은 극히 낮지만(모달을 열고 0.24~0.36s
	#   안에 장착 + `in_chapter` 가드) 한 줄로 닫힌다.
	# ⚠ `_cancel_swing`이 `_swing_hit_armed`·`_dash_speed`까지 함께 내리므로 **대시도 같이 멎는다** —
	#   그게 맞는 방향이다(무기가 바뀌었으니 그 무기의 이동을 계속할 근거가 없다).
	if _swing_hit_armed:
		_cancel_swing()
	_auto_firing = false  # 무기가 바뀌면 홀드 연사도 끊는다 — 새 무기가 shoot가 아닐 수 있다
	_refresh_growth_derived()  # 무기 교체도 파생 입력 — 새 base에 현재 haste를 다시 곱한다
	if is_node_ready():
		# 차지 오브 = 그 무기의 투사체 텍스처(표시 전용) — 모으는 탄과 날아가는 탄이 같은 그림.
		# ⚠ 틴트 없음(항등 흰색): 탄 텍스처는 이미 제 색을 갖고 있어 swing_color를 곱하면 탁해진다.
		#   swing_color는 **중립(흰색) 폭발 텍스처를 원소색으로 물들이는 용도**다 (불=주황, 이후 얼음=파랑).
		_charge_orb.texture = equip.projectile_texture if is_charge else null
		_charge_orb.modulate = Color(1, 1, 1, 1)
	if not is_charge:
		_cancel_charge()


# 모션 구간 비율 확정 — 🔴 **데이터를 믿지 않고 코드가 clamp한다.** 세 구간(예비·타격·복귀)이 전부
# 양수 폭을 가져야 `_motion_at`의 나눗셈이 성립하고, 합이 1을 넘으면 복귀가 사라져 무기가 휘두른
# 자세로 얼어붙는다 — 둘 다 `.tres` 한 줄로 **에러 없이** 도달할 수 있는 상태다.
func _apply_motion_shape(equip: EquipDef) -> void:
	var ph := CombatMath.motion_phases(equip)
	_swing_windup = ph.x
	_swing_strike = ph.y


# 타격 구간 이징 — 무기 성격이 여기서 갈린다. 모르는 값은 기본(smoothstep)으로 떨어진다(항등 폴백).
func _ease_strike(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	if _swing_ease == "accel":
		return x * x * x            # 천천히 들었다가 확 내리꽂는다 (도끼)
	if _swing_ease == "decel":
		return 1.0 - pow(1.0 - x, 3.0)  # 튀어나가 멎는다 (찌르기)
	return x * x * (3.0 - 2.0 * x)  # smoothstep — 기본(대검, 개편 전과 동일)


# 스윙 모션 곡선 — t(0~1, 스윙 창 진행) → (각 오프셋 rad, 내지르기 px).
# 🔴 **곡선의 모양은 표시 전용이지만 구간 길이는 판정 시점을 정한다**(m-5 정정 — 여기에 "판정은
#   클릭 프레임에 끝났다"고 적어 뒀던 것은 선딜 축 도입 전 서술이고 `:57`·`equip_def.gd`와 어긋났다).
#   판정은 `선딜 + 스윕`이 끝나는 시점이다. 각·도달(`swing_arc`·`melee_range`)만 이 곡선과 무관하다.
# 🔴 **모션 타입이 "무엇이 주 모션인가"를 가른다** — 베기는 각이, 찌르기는 거리가 주다.
#   찌르기에서 각을 좌우로 훑으면(베기와 같은 곡선) `swing_arc`가 좁은 무기는 "거의 안 움직이는 검"이
#   되고, 판정은 창인데 모션은 검인 상태가 된다(이 개편의 출발점).
# ⚠ `u`(이징된 타격 진행)는 **호출부가 계산해 넘긴다** — 궤적도 같은 값을 쓰기 때문이다.
#   여기서 다시 구하면 무기 각과 궤적 진행이 각자의 사본을 갖게 된다(rules §3의 반복된 실패 형태).
# 🔴 **이 스윙의 각 오프셋 — 무기 각과 궤적 선단이 둘 다 여기서 나온다** (code-rv m-6).
#   전에는 같은 `lerpf(_swing_from, _swing_to, u)`가 `_motion_at`과 `_draw_swing_trail`에 **문자 그대로
#   복제**돼 있었다. 입력이 같아 오늘은 등식이지만, 스윕 분기에 항이 하나라도 붙으면(예: 내지르기
#   연동 각) **조용히 다시 갈라진다** — M-2가 없애려던 형태 그대로다.
func _swing_angle_at(u: float) -> float:
	return lerpf(_swing_from, _swing_to, u)


func _motion_at(t: float, u: float) -> Vector2:
	# 🔴 굳힌 비율만 읽는다 — 살아 있는 `_swing_windup`을 읽으면 M-1 방어가 무효다.
	var w := _swing_windup_l
	var s := _swing_strike_l
	var thrust := _weapon_motion() == "thrust"
	var peak := _swing_lunge * _swing_lunge_mult
	if t < w:
		# 예비(선딜) — 각을 시작각까지 젖히고, `swing_pull`만큼 뒤로 당긴다(0 = 개편 전과 항등).
		var a := t / w
		if _combo_entry_from_previous:
			# 연계 타는 직전 타격의 끝 포즈에서 출발한다. 특히 창은 뻗은 끝에서
			# 다음 찌르기의 당김 자세로 이어져, 매 타마다 중립 자세를 거치지 않는다.
			return Vector2(lerpf(_combo_entry_off, _swing_from, a),
				lerpf(_combo_entry_lunge, -_swing_pull, a))
		return Vector2(_swing_from * a, -_swing_pull * a * a)
	if t < w + s:
		if thrust:
			# 찌르기 — 각은 겨눈 선(_swing_to = 0)으로 **모이고** 무기가 앞으로 쏘아진다.
			return Vector2(_swing_angle_at(u), lerpf(-_swing_pull, peak, u))
		# 베기 — 각이 주 모션. 내지르기는 스윕 중간이 최대(들어갔다 나온다).
		return Vector2(_swing_angle_at(u), peak * sin(u * PI))
	# 콤보 무기는 후딜에 끝 포즈를 유지한다. 입력이 끊겨 콤보 창이 닫힐 때만
	# `_tick_swing_motion`에서 기본 자세로 복귀한다.
	# 🔴 대기 자세는 `_combo_hold_pose()` **한 곳**에서 나온다 — 후딜(여기)과 창이 닫힌 뒤
	#   (`_tick_swing_motion`의 else 갈래)가 같은 값을 써야 그 경계에서 자세가 안 튄다.
	if _combo_pose_active:
		return _combo_hold_pose()
	# 단발은 기존 복귀를 유지한다.
	var r := (t - w - s) / maxf(1.0 - w - s, 0.0001)
	return Vector2(_swing_to * (1.0 - r), (peak * (1.0 - r * r)) if thrust else 0.0)


# 이 콤보에서 **다음에 나올** 타수. `_swing_attack`의 `idx` 산식과 같은 자리를 봐야 하므로
# 여기 하나로 모은다(콤보 창이 살아 있을 때만 뜻이 있다 — 끊기면 다음은 0이다).
func _next_combo_index() -> int:
	return (_combo_index + 1) % maxi(_combo_len(), 1)


# 검성(warrior_swordmaster)이 메인 하위 직업일 때만 검격이 나간다.
func _is_swordmaster_active() -> bool:
	return GameState.main_sub_job_id == "warrior_swordmaster"


# 검성 검격 — 타수별 반달 검기를 스윙 방향으로 날린다(로컬·표시 전용, 네트워크 0).
# 🔴 **모든 타가 셰이더 반달이다 — 갈래가 하나뿐이다**(2026-08-02 사용자 확정).
#   ⚠ 전에는 「구르기(Shift) 후 0.5초 내 공격 = 4번 소용돌이」라는 **롤-어택** 갈래가 있었고
#   `AnimatedSprite2D` + `slash_4` 시트로 따로 살았다. 사용자 요청으로 **제거**했다 —
#   되살리려면 갈래가 아니라 그 시절 커밋을 봐라(노드 타입부터 달라 한 파일에 안 들어간다).
func _try_spawn_slash(index: int) -> void:
	if not _is_swordmaster_active():
		return
	# 🔴 **막타(마무리 타)에만 날아간다** (사용자 확정 2026-08-02: *"초승달로 날아가는거 막타만"*).
	#   그전에는 **매 타** 나갔고, 그래서 검기가 "늘 켜져 있는 배경"이 되어 콤보의 끝이 안 읽혔다.
	# 🔴 판별은 `_is_combo_finish` **하나**를 지난다 — 판정 각·표시 각·자세가 전부 같은 함수를 쓰므로
	#   "검기만 마무리, 판정은 평타" 같은 어긋남이 원리적으로 생기지 않는다(§3 단일 소스).
	# ⚠ 가드를 **호출부가 아니라 여기**에 둔다 — 호출부(`_begin_swing`)에 두면 다음 사람이 다른
	#   자리에서 이 함수를 부를 때 조용히 빠진다(`apply_job_loadout` 세 호출부가 밟은 그 함정).
	# ⚠ 아래 램프 상수(`SLASH_ARC_RAMP_MIN`·`SLASH_RADIUS_RAMP_*`)는 타수별 점증용인데, 이제 막타
	#   하나만 남으므로 **항상 램프 최댓값**이 걸린다. 상수를 지우지는 않았다 — 타수별로 되돌리는
	#   결정이 오면 이 가드 한 줄만 빼면 되게 남겨 둔 것이다.
	if not _is_combo_finish(index):
		return
	# 🔴 무장 해제면 검기가 없다 — `melee_show_half_angle(null)`이 **전방위(PI)**를 돌려주므로
	#   가드 없이 통과시키면 반달이 아니라 **온전한 고리**가 뜬다(에러 없음, 화면만 이상하다).
	# ⚠ `job` 가드도 같이 — `effective_attack_range`가 `job.attack_range`를 바로 읽는다
	#   (`_combo_window_s`가 이미 같은 이유로 같은 가드를 갖고 있다).
	if _weapon_override == null or job == null:
		return
	var sfx := SlashFx.new()
	get_parent().add_child(sfx)              # 씬 루트 = 앞으로 날아감
	# 🔴 노드 원점 = 스윙 회전 중심 = 반달의 **곡률 중심**이다(`_weapon_point_global`과 같은 자리).
	#   그래서 검기가 "방금 휘두른 호가 떨어져 나가" 앞으로 나가는 그림이 된다.
	sfx.global_position = _weapon_pivot.global_position
	# 🔴 조준각(_aim_angle 라이브 마우스)이 아니라 스윙 개시 때 고정된 _swing_dir을 쓴다 —
	#   무기·궤적과 같은 단일 소스. _aim_angle을 쓰면 스윙 중 마우스가 움직여 어긋난다.
	# 🔴 색은 `_fx_color(1.0)` — 리본·칼 잔상과 **같은 단일 소스**다. 전에는 `Color(1,1,1,1)`을
	#   넘겨 틴트가 항등이었고 시트 자체가 노랑이라 **궤적만 하늘색이고 검기만 노랬다**.
	# 🔴 넷째 인자 = **무기 무게**(2026-08-02). 그 전에는 검기가 무기에서 반경·반각만 받아
	#   파쇄 도끼(무게 2.93)와 낡은 대검(0.67)이 화면에서 구분되지 않았다(사용자 신고).
	#   출처는 `CombatMath.weapon_weight` 하나이고 — `_weapon_weight()`가 그 래퍼다 —
	#   두께·뾰족함만 바뀐다(반경·반각은 판정 유도라 그대로, `slash_fx.gd` 상수 주석이 전문).
	sfx.setup(_swing_dir.angle(), _fx_color(1.0),
		_crescent_radius(index), _crescent_half_angle(index), _weapon_weight())


# 🔴 **검기 반달의 반각 — 출처는 그 스윙의 표시 반각 하나다.**
#   `melee_show_half_angle`(§3 표시 전용 단일 소스)에 타수 램프를 곱한다. 상한이 1.0이라 검기는
#   **그 스윙이 실제로 그린 각을 넘지 않는다** — "궤적은 안 지나갔는데 검기만 거기 있다"가 불가능.
# 🔴 `melee_half_angle`(판정 각)을 직접 읽어 여유를 곱하지 마라 — 그게 §3이 금지한 「제3의 값」이다.
# ⚠ 순서가 계약이다: **램프 → 포화**. 포화를 먼저 걸면 넓은 무기가 상한에 붙은 뒤에 램프가 곱해져
#   1타가 필요 이상으로 좁아지고, 타수 간 간격이 무기마다 뒤죽박죽이 된다.
func _crescent_half_angle(index: int) -> float:
	var arc := CombatMath.melee_show_half_angle(_weapon_override, _is_combo_finish(index))
	arc *= lerpf(SLASH_ARC_RAMP_MIN, 1.0, _combo_ramp_at(index))
	# 「반달」 포화 — 상한에 점근만 하므로 순서가 엄밀히 보존된다(상수 주석이 근거).
	return SLASH_MAX_HALF_ANGLE * tanh(arc / SLASH_MAX_HALF_ANGLE)


# 🔴 **검기 반달의 반경 — 출처는 판정 도달 거리다.** `effective_attack_range`가 무기 `melee_range`·
#   `reach` 특성·마무리 `combo_finish_range`를 전부 리졸브하는 단일 소스이므로, 무기를 바꾸거나
#   특성이 켜지면 검기가 **저절로** 따라온다(연출 상수로 도달 거리를 만들어 내지 않는다).
# ⚠ 램프는 그 위에 얹는 비율일 뿐이고 최댓값도 1.15배다 — 반경 축의 진실원은 여전히 하나다.
func _crescent_radius(index: int) -> float:
	var base := CombatMath.effective_attack_range(
		job, trait_value("reach"), _weapon_override, _is_combo_finish(index))
	return base * lerpf(SLASH_RADIUS_RAMP_MIN, SLASH_RADIUS_RAMP_MAX, _combo_ramp_at(index))


# 🔴 **타별 감각 점증의 진행값(0 = 첫 타 · 1 = 마지막 타) — `_combo_ramp` 멤버와 같은 식이다.**
#   `_begin_swing`이 그 멤버를 심기 **전에** 검기가 스폰되므로(스폰이 각·젖힘보다 앞이다) 멤버를
#   그대로 읽으면 **직전 스윙의 값**을 쓴다. 사본을 두지 않으려고 함수 하나로 모았다.
# ⚠ n = 1(콤보 없는 무기)이면 0이다 — `CombatMath.is_combo_finish`가 그 경우 마무리로 안 세는 것과
#   같은 규약이라, 검기만 마무리 크기로 뜨는 갈라짐이 없다.
func _combo_ramp_at(index: int) -> float:
	var n := _combo_len()
	if n <= 1:
		return 0.0
	return clampf(float(index) / float(n - 1), 0.0, 1.0)


# 🔴 **그 타의 시작 각 오프셋(rad) — `_begin_swing`과 젖힘 목표가 같은 이 함수를 지난다.**
#   사본을 두면 젖힘이 "다음 타가 실제로 출발하는 각"과 갈라져, 마무리 선딜이 **되돌아가는**
#   구간을 갖는다(칼이 젖혔다가 앞으로 갔다가 다시 젖히는 것처럼 보인다).
# ⚠ 어깨걸치기 `cap`도 여기 안에 있다 — 밖으로 빼면 젖힘 목표만 상한을 안 받아 span이 2π를 넘는다.
func _swing_entry_angle(index: int) -> float:
	var arc := CombatMath.melee_show_half_angle(_weapon_override, _is_combo_finish(index))
	var from := arc if CombatMath.is_combo_swing_reversed(index) else -arc
	if _weapon_motion() == "thrust":
		return from  # 찌르기는 좌우로 훑지 않아 젖힘 상한이 필요 없다(`_begin_swing`과 같은 갈래)
	# span = arc × (1 + 배율) < 2π — 근거는 `SWING_WINDUP_ARC_MULT` 상수 주석이 정본.
	var cap := (TAU - 0.02) / maxf(arc, 0.0001) - 1.0
	return from * clampf(maxf(1.0, _windup_arc_mult), 1.0, maxf(1.0, cap))


# 이번 스윙의 스윙음 피치 — 콤보 리듬을 귀로 들리게 한다(`COMBO_PITCH_*` 상수 주석이 정본).
# 🔴 **`_swing_is_finish`를 본다 — `is_combo_finish`를 여기서 다시 부르지 마라.** 그 값은
#   `_begin_swing`이 굳힌 것이라 각·표시·판정이 **같은 판단**을 쓰고 있고, 소리만 따로 물으면
#   스윙 도중 무기 교체에서 "각은 마무리인데 소리는 평타"로 갈라진다(M-1 방어의 미러).
# ⚠ 로컬·원격 공용이다 — 원격도 `play_attack_fx` → `_begin_swing(combo)`로 두 값이 서 있다.
func _swing_pitch() -> float:
	if _swing_is_finish:
		return COMBO_PITCH_FINISH
	return 1.0 + COMBO_PITCH_STEP * float(_combo_index)


# 이 타 뒤의 젖힘 비율 — 뒤 타로 갈수록 크다(상수 주석이 정본). 인덱스는 **다음 타**다.
func _windback_ratio() -> float:
	var n := _combo_len()
	if n <= 1:
		return 0.0
	var t := float(_next_combo_index()) / float(n - 1)
	return lerpf(COMBO_WINDBACK_RATIO_MIN, COMBO_WINDBACK_RATIO, clampf(t, 0.0, 1.0))


# 🔴 **콤보 대기 자세 (각 오프셋, 내지르기) — 표시 전용, 스윙 창 밖이다.**
#   기본은 이번 타의 끝각이고, 콤보가 이어지는 동안 **다음 타의 선딜 시작 자세** 쪽으로
#   `_windback_ratio()`만큼 미리 젖힌다(그 상수 주석이 정본).
# 🔴 목표가 `_swing_entry_angle(다음)`·`-_swing_pull`이라 **다음 타가 어차피 지나는 자세**다 —
#   새 각 범위를 만들지 않으므로 §3 「표시 ⊇ 판정」에 손대지 않는다(판정은 스윕 창 안에서만 난다).
# 🔴🔴 **다음 타가 반대쪽에서 출발하면 젖히지 않는다 — 그건 젖힘이 아니라 앞을 가로지르는 이동이다.**
#   방향이 패리티(`index % 2`)라 끝각과 다음 시작각은 보통 같은 쪽인데, **홀수 타수의 마지막 → 첫 타**
#   에서만 패리티가 같아져 부호가 뒤집힌다(대검 3타: 끝 +2.55 → 다음 시작 −2.85). 거길 천천히
#   보간하면 칼이 조준선을 가로질러 **108°를 느리게 흘러가** 젖힘이 아니라 "칼이 떠다니는" 것으로
#   읽힌다. 그 전이만 지금처럼 선딜의 빠른 보간(`_combo_entry_from_previous`)에 맡긴다.
func _combo_hold_pose() -> Vector2:
	var lunge := (_swing_lunge * _swing_lunge_mult) if _weapon_motion() == "thrust" else 0.0
	if _windback_t <= 0.0:
		return Vector2(_swing_to, lunge)
	var entry := _swing_entry_angle(_next_combo_index())
	if entry * _swing_to < 0.0:
		entry = _swing_to  # 반대쪽 출발 = 각 젖힘 없음(내지르기 회수만 남는다)
	var ratio := _windback_ratio()
	# smoothstep — 젖힘이 등속이면 기계적으로 보인다(들었다 멈추는 예비 동작이라 감속이 맞다).
	var a := _windback_t * _windback_t * (3.0 - 2.0 * _windback_t)
	var back_off := lerpf(_swing_to, entry, ratio)
	var back_lunge := lerpf(lunge, -_swing_pull, ratio)
	return Vector2(lerpf(_swing_to, back_off, a), lerpf(lunge, back_lunge, a))


# 젖힘 진행 — 🔴 **스윕이 끝난 뒤부터만 흐른다.** `_swing_fx_armed`가 스윙 시작~스윕 완료 구간에
#   정확히 true라 그것 하나로 가려낸다(별도 타이머를 두면 두 시계가 갈라진다).
#   ⚠ 그래서 젖힘은 **후딜부터** 쓴다 — 판정은 스윕 완료에 이미 났고 후딜은 순수 표시라, 빈 구간이
#     `쿨다운 − 스윙 창`이 아니라 **`쿨다운 − 스윕 완료`** 다(철 대검 마무리 앞: 60ms가 아니라 416ms).
# ⚠ **마무리 직전 타로 한정하지 않는다** (2026-08-01 2차) — 사용자가 1타 → 2타 사이도 요구했다.
#   양은 `_windback_ratio()`가 타별로 가른다.
func _tick_combo_windback(delta: float) -> void:
	if _swing_fx_armed or not _combo_pose_active or _combo_left <= 0.0:
		return
	_windback_t = minf(1.0, _windback_t + delta / maxf(_windback_time, 0.0001))


# 이 무기의 타격 무게 배율 — 유도는 `CombatMath.weapon_weight` 단일 소스(위 주석 참조).
func _weapon_weight() -> float:
	return CombatMath.weapon_weight(_weapon_override)


# 궤적 페이드 색 — (무기 틴트 × 메인 하위 직업 틴트) rgb 유지, 알파만 페이드로 구동.
# 🔴 **리본·칼 잔상이 둘 다 이 함수를 지난다 = 단일 소스다.** 한쪽만 곱하면 같은 스윙에서 띠와
#   잔상이 다른 색으로 나온다(에러 없음, 화면만 지저분해진다).
# 🔴 **곱셈인 것이 계약이다** — 무기 색을 덮어쓰면 원소 무기(불 지팡이 등 §4 "중립 텍스처 + 원소색")가
#   하위 직업 색에 먹힌다. 곱이면 둘 중 하나가 흰색(항등)일 때 다른 쪽이 그대로 나오고, 근접 4종은
#   현재 전부 흰색이라 하위 직업 색이 온전히 산다.
func _fx_color(alpha: float) -> Color:
	return Color(_swing_color.r * _subjob_fx_color.r, _swing_color.g * _subjob_fx_color.g,
		_swing_color.b * _subjob_fx_color.b, alpha * _swing_color.a * _subjob_fx_color.a)


func is_alive() -> bool:
	return _alive


# 무장 상태 — 착용 무기 텍스처가 있으면 무장(공격 가능). 미착용이면 공격·궤적 없음.
func _is_armed() -> bool:
	return _weapon.texture != null


# 호스트가 자기 로컬 플레이어의 i-frame을 직접 조회 (원격 피어는 G_ROLL 그랜트 창으로 판정)
func is_rolling() -> bool:
	return _roll_time_left > 0.0


# --- 늪 슬로우 (SwampZone이 로컬 플레이어 겹칠 때만 호출 — 네트워크 0, 이동은 각자 소유 rules §3) ---
# 여러 늪이 겹치면 가장 느린 배율(min)을 걷기 속도에 적용. exit는 factor를 받아 정확히 그 늪 항목만 제거
# (여러 늪 배율이 다를 때 min 재계산이 어긋나지 않게 — 현재는 def.swamp_slow_factor 하나라 전부 동일).
func enter_swamp(factor: float) -> void:
	_swamp_factors.append(factor)


func exit_swamp(factor: float) -> void:
	var idx := _swamp_factors.find(factor)
	if idx >= 0:
		_swamp_factors.remove_at(idx)


# 현재 유효 걷기 배율 — 겹친 늪 없으면 1.0, 있으면 가장 느린 값. 구르기엔 적용 안 한다(탈출 수단).
func _swamp_mult() -> float:
	var m := 1.0
	for f: float in _swamp_factors:
		m = minf(m, f)
	return m


# 게스트 수신 경로 — php 브로드캐스트 반영. 타이머 없는 표시 전용 (§3: 자기 HP도 이것만 믿는다)
func confirm_hp_from_net(p_hp: int, dmg: int = 0) -> void:
	# dmg = php "d"(호스트가 확정한 실데미지, 표시 전용). 0 = 미상 → 글루가 감소량 폴백 =
	# 구버전 호스트와 항등(ehp "d"와 같은 규약).
	_health.set_hp_display(p_hp, false, dmg)
	GameState.record_party_hp(peer_id, p_hp)  # 챕터 스테이지 간 이월 기록 — 확정 경로만 쓴다
	# 🔴 순서는 `_on_hp_confirmed`와 **같아야 한다**(그쪽 주석이 근거 정본) — 두 경로가 갈리면
	#   "호스트에선 전멸이 나는데 게스트 화면만 안 난다" 같은 비대칭이 생기고, 그건 화면에 이유가
	#   안 드러난다. 여기선 `_check_wipe`가 안 돌지만(호스트 전용) 규약을 하나로 유지한다.
	_update_life_state(p_hp)
	EventBus.player_hp_confirmed.emit(peer_id, p_hp)


# 이 아바타가 마지막에 실제로 받은 데미지 — 호스트가 php "d"에 실어 보낼 때 읽는다(표시 전용).
# 🔴 `_health`를 밖에서 직접 만지지 않게 하는 접근자다 — 쓰기 경로는 여전히 Health 안에만 있다.
func last_damage_taken() -> int:
	return _health.last_damage


func _on_hp_confirmed(p_hp: int) -> void:
	GameState.record_party_hp(peer_id, p_hp)  # 챕터 스테이지 간 이월 기록 — 확정 경로만 쓴다
	# 🔴🔴 **생사 갱신이 emit보다 **먼저**여야 한다 — 이 순서가 계약이다** (2026-08-02 실기에서 잡았다).
	#   `_check_wipe`(CombatAuthority)는 이 시그널을 받아 **`is_alive()`로 생존자를 센다**. 그런데
	#   `is_alive()`가 읽는 `_alive`는 `_update_life_state`에서만 갱신되므로, emit이 먼저면 방금 죽은
	#   본인이 **아직 살아 있는 것으로 세어져** 전멸이 성립하지 않는다 — 그리고 `_check_wipe`는 다음
	#   HP 확정이 올 때까지 다시 불리지 않으므로, **마지막 한 명이 죽으면 전멸이 영영 안 난다.**
	#   증상: 솔로 사망 시 관전 고스트로 스테이지에 영구 잔류(마을 복귀 없음) — 100% 재현.
	#   ⚠ 되돌리지 마라. `_update_life_state`는 `now_alive == _alive`면 early return이라 멱등이고,
	#   순서를 바꿔도 이 함수 밖에서 관측되는 것은 「생사 → 통지」라는 자연스러운 방향뿐이다.
	_update_life_state(p_hp)
	EventBus.player_hp_confirmed.emit(peer_id, p_hp)


# 표시 경로(모든 클라) 피격 손맛 — 이 인스턴스(로컬·원격 무관)의 HP가 실제로 감소했을 때.
# combat_impact(카메라 셰이크·데미지 숫자·SFX 공용 훅) + 히트스톱(맞은 대상 스프라이트만).
# i-frame(구르기) 중엔 호스트가 데미지를 확정하지 않아 hp가 안 떨어진다 → 여기 안 온다(거짓 연출 없음).
func _on_hp_changed_feel(new_hp: int, dropped: bool) -> void:
	# 🔴 실데미지 우선, hp 감소량은 폴백 — 적 3종(mob_melee·enemy·boss)과 **같은 관용구**다
	#   (2026-08-01 netreview I-1). 여기만 감소량으로 두면 `hp = maxi(0, hp - dmg)` 때문에
	#   **플레이어가 죽는 타격은 100% 오버킬이라 늘 작게 표시**되고, 게다가 같은 사실이 프로젝트
	#   안에서 두 관용구로 갈린다(적은 실딜·플레이어는 감소량).
	var amount := _health.last_damage if _health.last_damage > 0 else _prev_hp - new_hp
	_prev_hp = new_hp
	if not dropped or amount <= 0:
		return  # 회복·부활·최대치 조정은 손맛 대상 아님
	# 적은 치명타를 굴리지 않는다(GDD 범위) → 플레이어 피격은 항상 crit=false (php에 "cr"이 없는 이유와 짝)
	EventBus.combat_impact.emit("player", global_position, amount, false)
	if new_hp > 0:
		HitStop.punch(_sprite)
		HitFlash.flash(_sprite)  # 흰색 번쩍
		var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("enemy"))
		Flinch.play(_sprite, global_position - opp)  # 피격원 반대로 흠칫
	else:
		EventBus.screen_shake.emit(5.0)  # 사망은 강하게
		EventBus.entity_died.emit("player", global_position, false)  # 플레이어 부활은 별도 경로(적 데이터의 respawns가 아니다)


# 사망 = 관전 고스트 (GDD §5): 공격·구르기 차단, 이동은 자유(충돌 off), G_POS는 계속 송신
# (송신을 멈추면 부활 순간 원격 변위 클램프가 순간이동을 기어가는 걸로 만든다 — 앵커 연속성 유지)
func _update_life_state(p_hp: int) -> void:
	var now_alive := p_hp > 0
	if now_alive == _alive:
		return
	_alive = now_alive
	set_seated(false)  # 사망/부활 어느 쪽이든 앉기 해제 — 시체가 앉아서 회복받는 상태 방지
	if _alive:
		collision_layer = _saved_layer
		collision_mask = _saved_mask
		_sprite.visible = true
		_sprite.modulate.a = 1.0
		_shadow.visible = true
	else:
		collision_layer = 0
		collision_mask = 0
		_shadow.visible = false  # 관전 고스트는 그림자 없음(떠 있는 느낌)
		_dust.emitting = false
		_cancel_swing()       # 진행 중이던 스윙(선딜·스윕·판정 예약)을 통째로 끊는다
		_fx_left = 0.0        # 궤적 잔상도 즉시 정리 — 시체에서 자국이 뜨지 않게
		_trail_clear()        # 리본도 같이 — 남기면 시체 옆에 자국이 굳는다
		_roll_time_left = 0.0
		_remote_roll_left = 0.0
		_was_dashing = false     # 사망으로 끊긴 대쉬가 되튐 킥을 남기지 않게(엣지 감지 리셋)
		_combo_left = 0.0        # 부활 후 첫 스윙이 죽기 전 콤보를 이어받지 않게
		_combo_index = 0
		_shot_combo_index = 0    # 원거리 콤보도 같이 — 부활 첫 발이 죽기 전 마무리 타를 이어받지 않게
		# ⚠ _last_shot_msec은 안 건드린다: 호스트도 자기 기록을 사망으로 지우지 않으므로(발사율 게이트가
		#   그대로 살아 있다) 여기서 지우면 부활 직후 클라만 "간격 충분"으로 보고 타수가 어긋난다.
		_attack_anim_left = 0.0  # 사망 직전 발동한 공격 스윙이 고스트에 남지 않게 (_cancel_swing 미러)
		_cancel_charge()         # 모으던 차지도 소멸 — 고스트가 기를 모으고 있지 않게
		_remote_charge = -1      # 원격 아바타의 차지 오브도 즉시 정리(사망 시 마지막 c가 남아 떠 있지 않게)
		_charge_orb.visible = false
		if is_local:
			_sprite.modulate.a = GHOST_ALPHA
		else:
			_sprite.visible = false


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if is_local:
		_local_move(delta)
		# 🔴 **`_local_move` 바로 뒤다** — 발동 프레임의 좌표가 그 프레임의 **최종** 위치여야 뒤따르는
		#   `_send_pos`가 같은 좌표를 실어 보내고, 호스트가 판정에 쓰는 `net_anchor()`가 화면의 FX
		#   원점으로 가장 빨리 수렴한다(G_SKILL은 원점을 안 싣는다 — 그게 곧 스푸핑 표면이라).
		_tick_skill(delta)
		_local_combat(delta)
		_send_pos(delta)
	else:
		_remote_moving = global_position.distance_to(_remote_target) > 1.0
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		# ⚠ flip_h는 여기서 안 건드린다 — 방향/뒤집기의 단일 소스는 _play_dir_anim이다(폴백 경로가
		#   원격일 때 _remote_flip을 읽는다). 두 곳에서 대입하면 프레임마다 서로 덮어쓴다.
	# 🔴 **분기 밖이다 — 로컬·원격 둘 다 다단을 그린다.** 안쪽에 두면 "내 화면의 상대만 한 번 번쩍"
	#   이 되어 같은 스킬이 클라마다 다른 그림이 된다(호스트는 양쪽 다 N타를 확정한다).
	# ⚠ `_physics_process`인 이유 = 로컬 손맛 질의(`_skill_feel`)가 `direct_space_state`를 판다
	#   (`_try_cast_skill`이 입력 단계에서 `_fire_skill`을 부르지 않는 것과 같은 근거).
	_tick_skill_fx(delta)
	# 🔴 조준각 갱신이 **맨 앞**이다 — 방향 애니(_update_anim)와 무기 표시(_update_weapon)가 둘 다
	#   _aim_angle에서 파생하므로, 뒤에서 갱신하면 몸 방향만 한 프레임 늦게 돌아 무기와 어긋난다.
	_update_aim(delta)
	_update_anim()
	# 🔴 무기 표시 **바로 앞**이다 — 스윙 시간 축(무기 각·궤적 진행·판정 시점)의 단일 소스라
	#   여기서 계산한 것을 _update_weapon이 그대로 소비한다. 뒤로 옮기면 무기가 한 프레임 늦는다.
	_tick_swing_motion(delta)
	_update_weapon(delta)
	_update_charge_orb(delta)
	_update_dash_fx(delta)
	_update_dust()


# 이동/구르기 중 발밑 먼지 (로컬=속도, 원격=수신 이동). 사망 시 정지.
func _update_dust() -> void:
	var moving := velocity.length() > 8.0 if is_local else _remote_moving
	_dust.emitting = _alive and moving


# 대쉬(구르기) 잔상 — 지나온 자리에 현재 프레임을 떼어 놓는다. 로컬·원격 모두 자기 화면에서 재생하므로
# **네트워크 메시지 0개**다(rules §2 손맛 계층 규약: 이미 각 클라에 있는 상태에서 파생한다).
# 대쉬 창은 로컬 _roll_time_left / 원격 _remote_roll_left — i-frame 판정과는 무관한 표시 창이다.
func _update_dash_fx(delta: float) -> void:
	var dashing := _alive and (_roll_time_left > 0.0 or _remote_roll_left > 0.0)
	if dashing:
		_afterimage_left -= delta
		if _afterimage_left <= 0.0:
			_afterimage_left = AfterImage.SPAWN_INTERVAL
			AfterImage.spawn(_sprite, self)
	elif _was_dashing:
		# 멈추는 순간의 되튐 — 진행 방향 반대로 짧게 밀어 "급정거"가 읽히게 (로컬 카메라만)
		if is_local:
			EventBus.camera_kick.emit(-_roll_dir, DASH_END_KICK)
		_afterimage_left = 0.0
	_was_dashing = dashing


# 대쉬 시작 연출 — 로컬(입력)·원격(G_ROLL 수신) 공용. 잔상 첫 장 + 먼지 버스트 + 진행 방향 카메라 반동.
func _dash_burst(dir: Vector2) -> void:
	AfterImage.spawn(_sprite, self)  # 출발 프레임을 즉시 한 장 — 첫 간격을 기다리면 시작이 밋밋하다
	_afterimage_left = AfterImage.SPAWN_INTERVAL
	_was_dashing = true
	if _dust != null:
		_dust.restart()  # 튀어나가는 순간 발밑에서 확 터지게(이후는 _update_dust가 이어 뿜는다)
		_dust.emitting = true
	if is_local:
		EventBus.camera_kick.emit(dir, DASH_KICK)


func _tick_timers(delta: float) -> void:
	# 🔴 **감산 전의 쿨다운을 기억한다** — 아래 버퍼 여유 무장이 "쿨다운이 **막** 끝난 프레임"이라는
	#   엣지를 봐야 하는데, 감산 후 값만 보면 그 엣지와 "원래 0이었다"를 구분할 수 없다.
	var cd_was_running := _attack_cd_left > 0.0
	_attack_cd_left = maxf(0.0, _attack_cd_left - delta)
	_roll_cd_left = maxf(0.0, _roll_cd_left - delta)
	_remote_roll_left = maxf(0.0, _remote_roll_left - delta)
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	_recoil_left = maxf(0.0, _recoil_left - delta)
	_kill_move_left = maxf(0.0, _kill_move_left - delta)
	_orb_pop_left = maxf(0.0, _orb_pop_left - delta)
	_combo_left = maxf(0.0, _combo_left - delta)
	_swing_bite_left = maxf(0.0, _swing_bite_left - delta)
	# 선입력 버퍼도 여기서 흐른다 — 🔴 **쿨다운(`_attack_cd_left`)과 반드시 같은 자리여야** 두 시계가
	#   같은 프레임 격자를 쓰고, "쿨다운이 열리는 첫 프레임에 발동"이 프레임률과 무관해진다.
	_attack_buf_left = maxf(0.0, _attack_buf_left - delta)
	# 🔴 **버퍼 여유 무장 — 쿨다운이 막 끝난 프레임에 버퍼가 아직 살아 있는 경우에만** (멤버 주석이 근거).
	# ⚠ 여유를 문 클릭이 여유 도중에 **만료되면 안 된다** — "버퍼는 있는데 안 나간다"가 되어 이 작업
	#   전으로 부분 회귀한다(그러면 처방이 결함을 하나 고치고 하나 만드는 셈이다). 그래서 버퍼 수명을
	#   여유만큼 함께 늘린다. `+ delta`는 바로 아래 감산이 같은 프레임에 한 번 빼는 것을 상쇄한다.
	if cd_was_running and _attack_cd_left <= 0.0 and _attack_buf_left > 0.0:
		_attack_buf_grace = CombatMath.buffered_attack_grace_s()
		_attack_buf_left = maxf(_attack_buf_left, _attack_buf_grace + delta)
	_attack_buf_grace = maxf(0.0, _attack_buf_grace - delta)
	# 🔴 판정 카운트다운은 **스윙 창과 반드시 같은 자리에서** 흐른다 — 근거는 멤버 주석(락스텝).
	if _swing_hit_armed:
		_swing_hit_left -= delta


# 🔴🔴 **스윙 시간 축의 단일 소스** (선딜/후딜 + 궤적 진행 축 2026-07-28).
#   무기 각 · 궤적이 그려진 범위 · **판정이 나가는 순간**이 전부 여기 한 곳의 `t`에서 나온다.
#   하나라도 자기 `t`를 다시 구하면 "칼이 지나간 각 ≠ 그려진 궤적 ≠ 맞는 각"이 되고, 그건 이
#   프로젝트가 콘 텔레그래프·스워시 텍스처에서 **두 번** 값을 치른 결함 클래스다(rules §3).
#
# 타임라인: 클릭 → **선딜**(칼을 젖힌다 · 궤적 없음 · 판정 없음)
#           → **스윕**(칼이 각을 훑고 궤적이 그 뒤를 따라 자란다)
#           → 스윕 완료 = 🔴 **판정 확정 순간** → **후딜**(칼을 회수) → 쿨다운 종료
#
# 🔴 **판정이 스윕 완료 시점인 것이 "안 보이는데 맞는다"를 원천 차단한다.** 그 순간 그려진 각 창은
#   `[_swing_from, _swing_to]`이고 이건 판정 부채꼴 `±melee_half_angle(equip, is_finish)`과 **같거나
#   넓다** — 표시는 같은 `is_finish`로 `melee_show_half_angle`을 지나 `COMBO_FINISH_SHOW_MARGIN`만큼
#   넓기 때문이다(= 안전한 방향, v2.2). 완료 시 `reach_ratio = 1`이라 판정 반경과 정확히 일치한다.
# 🔴🔴 **⚠ 찌르기(thrust)에서는 이 논거가 성립하지 않는다 — 2026-07-29 리뷰가 잡았다.**
#   `_begin_swing`의 thrust 분기가 `_swing_to = 0.0`이라 각 창이 `[_swing_from, 0]` = **조준선 한쪽뿐**
#   인데(패리티에 따라 좌 또는 우) 판정은 `is_angle_in_cone`으로 **양쪽** ±half_angle이다. 즉 반대쪽
#   절반은 리본도 잔상도 **절대 지나가지 않으면서 판정에 든다** — 창 반각 0.3 · 도달 80px에서
#   조준선 옆 **23.6px**, 적 `body_radius` 8을 더하면 **31px**(캐릭터 32px 한 마리 폭)이다.
#   ⚠ **이것은 v2.2가 만든 것이 아니라 찌르기 도입(07-28)부터 있던 선재 결함**이고, v2.2는 창에
#   `combo_finish_arc`를 **주지 않기로** 해서 증분을 0으로 뒀다 — 그 값을 주면 이 띠가 정확히 그
#   배수로 벌어진다(0.6을 주면 45px, 적 반경까지 51px).
#   ⚠ **옛 서술("찌르기는 각 창이 처음부터 부채꼴 전체")은 부채꼴 셰이더 시절의 것**이고 07-29 리본
#   전환으로 거짓이 됐다. 고치려면 마무리 찌르기만 `_swing_to`를 반대쪽으로 넘겨야 한다(= 「휘둘러
#   찌르기」) — 모션 성격 변경이라 실기 판단이 선행한다.
#   🔴 **트립와이어가 이 축을 못 잡는다** — `melee_show_half_angle > melee_half_angle`(반각 비교)이
#   「표시 ⊇ 판정」(집합 포함)과 동치인 것은 **양쪽으로 훑는 모션에서만**이고, thrust에서는 공허하게
#   통과한다. 즉 그 단정의 초록불을 찌르기의 근거로 쓰지 마라.
func _tick_swing_motion(delta: float) -> void:
	# 🔴 **`_motion_at`보다 먼저 흘린다** — 후딜 갈래가 `_combo_hold_pose()`를 통해 이 진행을 읽으므로,
	#   뒤에 두면 대기 자세가 한 프레임 늦게 따라와 젖힘 시작이 눈에 띄게 끊긴다.
	_tick_combo_windback(delta)
	if _attack_anim_left > 0.0:
		# 🔴 **굳힌 시간 축에서만 파생한다** — 살아 있는 `_swing_time`을 쓰면 스윙 도중 무기 교체·
		#   레벨업이 판정 시점을 움직인다(netreview M-1, 멤버 주석이 근거).
		var t := clampf(1.0 - _attack_anim_left / _swing_win_total, 0.0, 1.0)
		# 적중해 "박혀" 있는 동안은 그 자리에 붙들어 둔다 — 창은 계속 흐르므로 남은 구간이 그만큼
		# 빨리 지나간다(창 길이 불변 = `swing_time < attack_cooldown` 미러 계약 보존, §3).
		if _swing_bite_left > 0.0:
			t = _swing_bite_t
		# 🔴 타격 구간의 이징된 진행 `u` — **무기 각과 궤적 진행이 공유하는 유일한 값**이다.
		#   `_motion_at`에 넘겨서 쓰게 한다(거기서 다시 구하면 그게 곧 사본이다).
		var p := clampf((t - _swing_windup_l) / maxf(_swing_strike_l, 0.0001), 0.0, 1.0)
		var u := _ease_strike(p)
		var m := _motion_at(t, u)
		_motion_off = m.x
		_motion_lunge = m.y
		if t >= _swing_windup_l:
			if _swing_onset_pending:
				_swing_onset_pending = false
				# 휘두름 소리는 **칼이 움직이기 시작할 때** 난다(클릭이 아니라). 로컬·원격 공용 —
				# 양쪽이 같은 오프셋으로 이 지점에 도달하므로 두 화면의 소리 시점이 자동으로 맞는다.
				EventBus.player_swing.emit(global_position, _swing_sfx, _swing_pitch())
				# ⚠ 카메라 킥은 **로컬만** — EventBus는 전역이라 원격 아바타가 emit하면 남이 휘두를
				#   때 내 화면이 밀린다(event_bus.gd가 명시한 함정).
				# 🔴 반동을 **모든 타**에 주되 타별로 점증시킨다 (2026-08-01 2차) — 리듬이 눈뿐 아니라
				#   손으로도 읽히게. `_combo_pose_active`(= n > 1) 가드라 **콤보 없는 무기는 도입 전과
				#   완전 항등**(반동 0)이고, `_combo_ramp = 1`인 마무리는 1차 값 그대로다.
				if is_local and _combo_pose_active:
					var kick := lerpf(COMBO_SWING_KICK, COMBO_FINISH_KICK, _combo_ramp)
					EventBus.camera_kick.emit(_swing_dir, kick * _weapon_weight())
			# 궤적 마무리 = 스윕 완료 순간. 판정은 아래 카운트다운이 따로 낸다.
			if p >= 1.0:
				_finalize_swing_sweep(delta)
			elif _swing_fx_armed:
				_draw_swing_trail(u)
	else:
		# 창이 닫히는 순간에도 궤적은 반드시 완성된 부채꼴로 굳힌다 — 후딜 창이 한 프레임보다 짧은
		# 데이터에서 `p >= 1.0`인 프레임이 한 번도 관측되지 않을 수 있다(netreview I-2).
		# ⚠ 취소·사망은 `_cancel_swing()`이 플래그를 이미 내려서 여기로 새지 않는다.
		_finalize_swing_sweep(delta)
		if _combo_pose_active and _combo_left > 0.0:
			# 🔴 후딜 갈래(`_motion_at`)와 **같은 함수**를 지난다 — 스윙 창이 닫히는 프레임에 자세가
			#   튀지 않는 것이 이 한 줄에 걸려 있다.
			var hold := _combo_hold_pose()
			_motion_off = hold.x
			_motion_lunge = hold.y
		else:
			# 콤보 입력이 끊긴 경우에만 자연스럽게 기본 자세로 복귀한다.
			_motion_off = move_toward(_motion_off, 0.0, COMBO_POSE_RETURN_SPEED * delta)
			_motion_lunge = move_toward(_motion_lunge, 0.0, COMBO_POSE_RETURN_SPEED * delta)
			if is_zero_approx(_motion_off) and is_zero_approx(_motion_lunge):
				_combo_pose_active = false
	# 🔴 **판정은 창과 독립인 카운트다운이다** (netreview I-2) — `p >= 1.0`인 프레임이 관측되는지에
	#   기대지 않으므로 프레임 격자 의존이 **구조적으로** 없다. 스로틀로 미뤄졌으면 창이 닫힌 뒤에
	#   나기도 한다(그때도 궤적은 위에서 이미 완성돼 있어 `표시 ⊇ 판정`이 유지된다).
	# 🔴 판정 발화 — 감산은 `_tick_timers`(창과 같은 자리)에서 끝났고 여기선 **발화만** 한다.
	#   위 궤적 마무리 **뒤**에 두는 것이 계약이다: 같은 프레임에 둘이 걸리면 궤적이 먼저 완성돼야
	#   `표시 ⊇ 판정`이 성립한다. 스로틀로 미뤄졌으면 창이 닫힌 뒤에 나기도 한다(그땐 이미 완성 상태).
	if _swing_hit_armed and _swing_hit_left <= 0.0:
		_swing_hit_armed = false
		if is_local:  # 원격 아바타는 판정을 만들지 않는다 (rules §1)
			_resolve_swing_hit()
	if _fx_left > 0.0:
		_fx_left -= delta
		# 자국은 칼이 회수돼도 그 자리에 남았다가 흩어진다("벤 자국").
		# 🔴 분모는 `_fx_total`이다 — 마무리 타는 자국이 더 오래 남으므로(`COMBO_FINISH_FX_TIME_MULT`)
		#   상수로 나누면 앞구간이 1.0에 clamp돼 **안 흐려지다가 뚝 끊긴다**.
		_swing_trail.modulate = _fx_color(clampf(_fx_left / maxf(_fx_total, 0.0001), 0.0, 1.0))
		if _fx_left <= 0.0:
			_trail_clear()


# 스윕 마무리 — 궤적을 완성된 부채꼴로 굳히고 판정을 확정한다. **멱등이다**(플래그를 내린다).
# 두 곳에서 부른다: 스윕이 정상 완료된 프레임 · 창이 닫히는 프레임(캐치올 래치, netreview I-2).
func _finalize_swing_sweep(delta: float) -> void:
	if _swing_fx_armed:
		# 🔴 `p = 1`로 그린다 — 그래야 선단이 `_swing_to`로 **래치**돼 부채꼴 전체가 남는다
		#   (`_draw_swing_trail`의 M-2 주석이 근거). 이 그림이 페이드 동안 그대로 굳는다.
		_draw_swing_trail(1.0)
		_swing_fx_armed = false
		# 완성된 부채꼴을 잔상 페이드로 넘긴다. `+ delta`는 위 페이드 블록이 **같은 프레임에** 한 번
		# 빼는 것을 상쇄한다 — 그래야 **판정이 나는 그 프레임의 궤적 알파가 정확히 1.0**이다
		# (스로틀로 미뤄진 경우에만 그보다 낮은 알파에서 판정이 난다 — 최대 44ms 뒤 = 약 0.76).
		# ⚠ 마무리 타만 자국이 더 오래 남는다 — 분모(`_fx_total`)를 **같이** 세워야 페이드 곡선이 산다.
		_fx_total = ATTACK_FX_TIME * lerpf(1.0, COMBO_FINISH_FX_TIME_MULT, _combo_ramp)
		_fx_left = _fx_total + delta


# 애니 상태: roll > attack > run > idle. 로컬은 자기 상태, 원격은 수신 신호(G_POS 변위·G_ROLL/G_ATK 창)로 판단.
func _update_anim() -> void:
	var next: StringName = &"idle"
	# 🔴 몸통 공격 클립은 **콤보 타수가 고른다**(`_attack_anim_base`). 시트에 없으면 빈 이름이 돌아와
	#   run/idle로 떨어진다 = **도입 전과 완전 항등**(궁수·법사 시트가 그 상태다).
	var atk := _attack_anim_base() if _attack_anim_left > 0.0 else StringName()
	if _roll_time_left > 0.0 or _remote_roll_left > 0.0:
		next = &"roll"
	elif not atk.is_empty():
		next = atk
	elif (is_local and velocity.length_squared() > 1.0) or (not is_local and _remote_moving):
		next = &"run"
	_play_dir_anim(next)
	# 🔴 **배율은 `_play_dir_anim`이 실제로 고른 클립에서 유도한다**(`_sprite.animation`) — 방향 접미사
	#   선택 규칙(서=동 flip · 북 폴백)을 여기서 사본으로 다시 쓰면 두 규칙이 갈라진다.
	# 🔴 목표 길이는 **굳힌 창**(`_swing_win_total`)이다 — 살아 있는 `_swing_time`을 쓰면 스윙 도중
	#   무기 교체가 몸 애니 속도만 바꿔 창과 어긋난다(`_tick_swing_motion`과 같은 M-1 방어).
	_anim_scale = 1.0
	if next == atk and not atk.is_empty():
		_anim_scale = _anim_speed_scale_for(_sprite.animation, _swing_win_total)
	_apply_anim_scale()


# 🔴🔴 **콤보 타수 → 몸통 공격 클립** (전사 3종 애니 2026-08-01).
#   · 마무리 타 = `attack3` — 판단은 `_swing_is_finish`, 즉 `_begin_swing`이 **`CombatMath.is_combo_finish`
#     하나에서** 래치한 값이다. 사본을 만들면 "판정은 마무리인데 몸은 평타"가 되고, 그건 §3이 구조로
#     막아 온 표시/판정 갈라짐의 **몸통 판**이다. 래치를 쓰는 것이 재계산보다 강하다 — 스윙 도중
#     무기 교체가 판정 각과 몸 애니를 갈라놓지 못한다(netreview M-1 미러).
#   · 그 외 = **패리티**(`is_combo_swing_reversed`) — true면 `attack2`(되돌려 베기), false면 `attack1`.
#     🔴 **절대 위치(`index == 1`)로 쓰지 마라** — 창(4타)에서 index 0과 2가 같은 방향이 되어 두 타가
#     같은 클립을 쓰게 된다. 그 함수가 존재하는 이유가 여기에도 그대로 걸린다.
#   이 규약이면 **2타(도끼)·3타(대검)·4타(창)가 전부 `attack1~3` 세 클립으로 덮인다** — 타수만큼
#   클립을 그릴 필요가 없다.
# 🔴 **로컬·원격 공용이다** — 원격은 `play_attack_fx(dir, combo)` → `_begin_swing(combo)`로 `_combo_index`·
#   `_swing_is_finish`가 이미 서 있으므로 두 화면이 같은 클립을 재생한다(네트워크 필드 0개).
# 🔴 **폴백 사슬 = 도입 전 항등.** 새 이름이 없는 시트(궁수·법사·옛 `warrior_frames.tres`)에서는
#   ⑴ 있는 콤보 클립 → ⑵ 옛 단일 `attack` → ⑶ 빈 이름(몸통 애니 없이 무기만 도는 현행 동작)으로 떨어진다.
func _attack_anim_base() -> StringName:
	var want := &"attack1"
	if _swing_is_finish:
		want = &"attack3"
	elif CombatMath.is_combo_swing_reversed(_combo_index):
		want = &"attack2"
	if _has_anim_base(want):
		return want
	if _has_anim_base(&"attack1"):
		return &"attack1"  # 3종 중 일부만 있는 시트(작화 중) — 있는 것으로 떨어진다
	if _has_anim_base(&"attack"):
		return &"attack"   # 옛 단일 클립 = 도입 전 동작
	return StringName()    # 몸통 애니 없음 — 무기만 돈다


# `_play_dir_anim`이 실제로 찾는 이름 집합에 이 base가 있는가(방향 접미사판 또는 무접미사판).
# 🔴 **그 함수의 조회 규칙과 미러다** — 한쪽만 고치면 "있다고 판단했는데 아무것도 안 나온다"가 된다.
func _has_anim_base(base: StringName) -> bool:
	var f := _sprite.sprite_frames
	if f == null:
		return false
	if f.has_animation(base):
		return true
	for s: String in DIR_SUFFIX:
		if f.has_animation(StringName(String(base) + "_" + s)):
			return true
	return false


# 목표 길이에 맞춘 speed_scale = 기본 길이 ÷ 목표 길이. 못 구하면 1.0 = 항등 폴백(도입 전 동작).
# 🔴 프레임 수·speed·프레임별 duration을 **전부 시트에서 읽는다** — 상수 미러를 만들지 않으므로
#   아트가 프레임을 4 → 6으로 늘려도 배율이 자동 추종한다(`boss._anim_base_length` 관용구).
func _anim_speed_scale_for(anim: StringName, target_s: float) -> float:
	var f := _sprite.sprite_frames
	if f == null or not f.has_animation(anim) or target_s <= 0.0:
		return 1.0
	var spd := f.get_animation_speed(anim)
	var count := f.get_frame_count(anim)
	if spd <= 0.0 or count <= 0:
		return 1.0
	var total := 0.0
	for i: int in count:
		total += f.get_frame_duration(anim, i)
	return maxf(total / spd / target_s, MIN_ANIM_SPEED_SCALE)


# 원하는 배율을 스프라이트에 심는다 — 🔴 **`speed_scale`의 유일한 대입 지점**(boss `_apply_anim_scale` 미러).
# ⚠ **정지(0.0) 중에는 건드리지 않는다** — 히트스톱이 세워 둔 것을 덮으면 히트스톱 자체가 사라진다.
#   손실은 최대 1프레임이고, 히트스톱이 끝나며 1.0으로 리셋한 것을 다음 프레임에 여기가 되돌린다.
# ⚠ **`hit_stop`을 meta 저장 방식으로 "고치지" 마라 — 더 나빠진다**(그 함수 주석이 근거).
func _apply_anim_scale() -> void:
	if _sprite.speed_scale <= 0.0:
		return
	if not is_equal_approx(_sprite.speed_scale, _anim_scale):
		_sprite.speed_scale = _anim_scale


# 조준각 → 4분면 인덱스 (0=동 1=남 2=서 3=북). Godot는 y+가 아래라 남쪽이 +PI/2다.
# 경계에서 깜빡이지 않게 각을 45° 돌린 뒤 90°로 나눈다(각 사분면의 중앙이 정면이 된다).
func _facing_index(angle: float) -> int:
	if not is_finite(angle):
		return 0
	return int(wrapf(angle + PI / 4.0, 0.0, TAU) / (PI / 2.0)) % 4


# 방향 애니 재생 + flip_h 대입의 **단일 소스**. 4방향 시트가 있으면 그걸, 없으면 기존 2방향으로 폴백한다.
# 🔴 flip_h를 여기 밖에서 대입하지 마라 — 매 프레임 이 함수가 다시 쓰기 때문에 다른 대입은
#   한 프레임만 반영됐다 사라져 "가끔 방향이 튄다"로만 보인다(원인이 화면에 안 드러난다).
func _play_dir_anim(base: StringName) -> void:
	var frames := _sprite.sprite_frames
	if frames == null:
		return
	var idx := _facing_index(_aim_angle)
	# 서(2)는 동(0) 프레임을 뒤집어 쓴다 — 시트 장수를 반으로.
	var mirrored := idx == 2
	var dir_flip := mirrored
	# 🔴 북(3)도 뒤집는다 — 뒷모습 한 장이 "뒤좌/뒤우"를 겸하기 때문이다(사용자 확정 2026-07-28).
	#   여기서 idx를 0으로 접지 **않는** 것이 핵심이다: 접으면 뒤를 보는데 동쪽(앞모습) 시트가 나온다.
	#   그래서 "어느 시트를 쓰나"(mirrored)와 "뒤집나"(dir_flip)를 분리했다 — 둘을 한 변수로 겸하면
	#   북쪽에서 반드시 한쪽이 깨진다.
	if idx == 3:
		dir_flip = cos(_aim_angle) < 0.0
	var want := StringName(String(base) + "_" + DIR_SUFFIX[0 if mirrored else idx])
	if frames.has_animation(want):
		_sprite.flip_h = dir_flip
		if _sprite.animation != want:
			_sprite.play(want)
		return
	# --- 폴백: 4방향 시트가 아직 없다 → 도입 전과 **완전히 같은 동작** ---
	# 기존 규칙은 "왼쪽 반평면이면 뒤집기"였다(4분면 서쪽보다 넓다) — 좁히면 좌상/좌하 조준에서
	# 캐릭터가 오른쪽을 본 채 왼쪽을 때리는 것처럼 보인다.
	_sprite.flip_h = (absf(wrapf(_aim_angle, -PI, PI)) > PI / 2.0) if is_local else _remote_flip
	if frames.has_animation(base) and _sprite.animation != base:
		_sprite.play(base)


# 몸통 공격 애니 보유 여부 — ⚠ **주석이 낡아 있던 자리다**(2026-08-01 정정). 옛 서술 *"현재 어느
# 직업도 없어 항상 false"* 는 전사가 `attack`을 갖게 된 시점에 이미 거짓이었고, 지금은 전사 시트에
# `attack1~3` × 3방향 **9클립**이 있다(궁수·법사 시트는 여전히 없어 false다 = 도입 전 항등).
# 🔴 판단을 `_attack_anim_base()` **하나로 모았다** — 이름 조회 규칙이 둘이면 "있다고 했는데 다른 것을
#   재생한다"가 생긴다. 여기는 그 결과가 비었는지만 본다.
# 🔴 애니 길이 ↔ `_swing_time` 미러(rules §3 부채)는 **미러가 아니라 유도로 갚았다** —
#   `_anim_speed_scale_for()`가 매 스윙 배율을 계산한다(그 함수·`MIN_ANIM_SPEED_SCALE` 주석이 근거).
func _has_attack_anim() -> bool:
	return not _attack_anim_base().is_empty()


# 조준각 갱신 — 몸 방향(4분면 애니·flip)과 무기 표시가 **둘 다** 여기서 파생하는 단일 소스.
# 무기 유무와 무관하게 돈다: 무장 해제 상태에서도 "a"를 실제 값으로 송신해야 무기를 드는 순간
# 원격 표시가 바로 맞고(리뷰 Minor), 몸이 향하는 쪽도 무장 여부와 무관해야 한다.
func _update_aim(delta: float) -> void:
	if is_local:
		_aim_angle = _aim_dir().angle()
	else:
		_aim_angle = lerp_angle(_aim_angle, _remote_aim, minf(1.0, WEAPON_AIM_LERP * delta))


# 무기 표시 — 조준 방향으로 내밀고, 공격 창 동안 호를 그리며 스윙 (전부 표시 전용, 판정은 별개).
func _update_weapon(delta: float) -> void:
	if _weapon.texture == null:
		return
	# 모션(선딜→스윕→후딜)은 `_tick_swing_motion`이 **이미 이 프레임에 계산했다** — 여기선 소비만 한다.
	var swinging := _attack_anim_left > 0.0
	var combo_holding := not swinging and _combo_pose_active
	var swing_off := _motion_off
	var lunge := _motion_lunge
	# 발사 반동(shoot 무기) — 활을 뒤로 당겼다 복귀. shoot는 _attack_anim_left를 안 켜므로 스윙과 상호 배타.
	if not swinging and _recoil_left > 0.0:
		lunge = -RECOIL_DIST * (_recoil_left / RECOIL_TIME)
	# 🔴 **스윙 중에는 클릭 순간 고정된 방향을 쓴다** — 라이브 조준각이 아니다(멤버 `_swing_dir` 주석).
	#   전에는 무기만 `_aim_angle`(라이브)을 따라가고 궤적은 클릭 고정이라, 스윙 중 마우스를
	#   돌리면 **칼과 궤적이 이미 어긋났다**. 선딜이 생기면서 그 창이 길어져 반드시 묶어야 한다.
	var base_ang := _swing_dir.angle() if swinging or combo_holding else _aim_angle
	# 좌향 조준 시 뒤집기 — 안 하면 검이 거꾸로(날이 아래) 보인다. 스윙 중엔 고정각 기준(중간 뒤집힘 방지)
	_weapon.flip_v = absf(wrapf(base_ang, -PI, PI)) > PI / 2.0
	# 평상시 스탠스 — 무기를 살짝 내려 들고 호흡/걸음에 맞춰 흔든다. 표시 전용이라 발사 원점·판정
	# 기하는 이 각을 보지 않는다(그쪽은 _aim_dir). 뒤집힌 쪽에선 부호를 반대로 줘야 양쪽 다 "내려 든" 모습.
	_tick_stance(delta, swinging or combo_holding)
	var ang := base_ang + swing_off + _stance_sway * (-1.0 if _weapon.flip_v else 1.0)
	_weapon_pivot.rotation = ang
	_weapon.position = -_weapon_grip + Vector2(_hold_dist + lunge, 0.0)
	# 위쪽 조준 = 몸 뒤(0), 아래 = 몸 앞(2) — 몸(Sprite z=1) 기준 상대 배치.
	# 🔴 **등에 멘 무기(대검)는 이 규칙이 정반대다** — 정면(아래 조준)이면 검이 등 뒤라 몸에 가리고,
	#   뒤통수(위 조준)면 우리 쪽으로 나온다. 손에 든 무기(활·지팡이)는 손이 앞이라 원래 규칙이 맞으므로
	#   `EquipDef.weapon_on_back`으로 가른다(무기 축이지 직업 축이 아니다).
	# ⚠ 음수 z_index는 배경 타일 밑으로 꺼져 무기가 통째로 사라진다 (실기에서 확인) — 전부 0 이상 유지
	var behind := sin(ang) < 0.0
	if _weapon_on_back:
		behind = not behind
	_weapon_pivot.z_index = 0 if behind else 2
	_weapon_pivot.visible = _alive and _roll_time_left <= 0.0 and _remote_roll_left <= 0.0


# 무기 스탠스 각 갱신 — 평상시엔 내려 들고 흔들리게, 모션 중(스윙·발사 반동·차지)엔 0으로 되돌린다.
# 목표로 lerp하므로 모션이 시작/끝날 때 각이 튀지 않는다. 로컬·원격 모두 자기 상태에서 파생(네트워크 0).
#
# 🔴🔴 **스윙 중에는 lerp가 아니라 선딜 진행도로 끌어내린다** (2026-07-29 "칼과 궤적이 어긋난다").
#   이 각은 **무기에만 더해지고 궤적·판정에는 없다**(`_update_weapon`의 `ang` vs
#   궤적이 쓰는 `_swing_angle_at`) — 의도된 비대칭이다: 판정 기준은 조준각이지 흔들린 각이
#   아니고(위 const 주석), 궤적은 그 판정을 덮어야 해서 조준각에 묶여 있다. 그래서 **스윙 중 이 값이
#   0이 아닌 만큼 칼만 판정 밖으로 밀려난다.**
#   전에는 `target = 0`으로 lerp만 했는데, `STANCE_LERP`(9.0)로는 선딜이 끝날 때까지 다 안 빠진다:
#   실측 60fps에서 궤적이 처음 그려지는 시점(선딜 끝 ≈ 5프레임)에 **정지 6.4° · 이동 8.7°** 잔존 —
#   칼끝 51px에서 6~8px이고, `flip_v`로 부호까지 뒤집혀 좌·우향에서 어긋나는 쪽이 달라진다.
#   🔴 진행도 기반이라 **프레임률과 무관하게 스윕 시작 = 궤적 시작 시점에 정확히 0**이다. lerp 계수를
#     키우는 방식은 저사양(30fps)에서 `minf(1.0, ...)`에 걸려 첫 프레임에 각이 툭 튄다.
#   ⚠ 시작값에서 연속적으로 줄어드므로 스윙 진입 시 점프가 없다(원래 lerp가 지키던 성질 그대로).
#   ⚠ 판정 쪽에 sway를 더해 맞추는 방향은 **금지다** — 호스트가 흔들림 위상을 알아야 해서 신뢰 경계가
#     늘고, 궤적만 sway로 돌리면 부채꼴이 통째로 기울어 반대쪽에 "안 보이는데 맞는" 구역이 생긴다(§3).
func _tick_stance(delta: float, in_attack_pose: bool) -> void:
	if in_attack_pose:
		if _attack_anim_left <= 0.0:
			_stance_sway = 0.0
			return
		# 굳힌 시간 축에서만 파생한다(`_tick_swing_motion`과 같은 근거 — netreview M-1 방어).
		var t := clampf(1.0 - _attack_anim_left / _swing_win_total, 0.0, 1.0)
		var w := maxf(_swing_windup_l, 0.0001)
		_stance_sway = _stance_enter_sway * clampf(1.0 - t / w, 0.0, 1.0)
		return
	var charging := _charging if is_local else _remote_charge >= 0
	var target := 0.0
	if _recoil_left <= 0.0 and not charging:
		var moving := (velocity.length_squared() > 1.0) if is_local else _remote_moving
		var amp := RUN_SWAY_AMP if moving else IDLE_SWAY_AMP
		_sway_phase = fmod(_sway_phase + delta * (RUN_SWAY_SPEED if moving else IDLE_SWAY_SPEED), TAU)
		target = STANCE_DROP + sin(_sway_phase) * amp
	_stance_sway = lerpf(_stance_sway, target, minf(1.0, STANCE_LERP * delta))


# 차지 오브 표시 — 지팡이 끝(= 발사 원점)에서 단계별로 커지는 마법구. 전부 표시 전용(판정 무관).
# 로컬은 내 차지 상태, 원격은 G_POS "c"(차지 중이면 레벨+1, 아니면 0으로 인코딩)에서 온다.
# 사망·구르기·무장 해제·비차지 무기면 숨긴다(유령 오브 방지).
func _update_charge_orb(delta: float) -> void:
	var lv := -1
	if is_local:
		if _charging:
			lv = _charge_level
	else:
		lv = _remote_charge
	if lv < 0 or not _alive or _charge_orb.texture == null \
			or _roll_time_left > 0.0 or _remote_roll_left > 0.0:
		_charge_orb.visible = false
		_charge_orb.scale = Vector2.ONE * 0.1  # 다음 차지는 다시 작게 시작 (자라나는 느낌)
		return
	_charge_orb.visible = true
	_charge_orb.position = Vector2(MUZZLE_OFFSET, 0.0).rotated(_aim_angle)
	var pop := 1.0 + ORB_POP * (_orb_pop_left / ORB_POP_TIME)  # 단계 상승 순간 부풀었다 가라앉음
	var target := CombatMath.CHARGE_ORB_SCALE[CombatMath.clamp_charge_level(lv)] * pop
	_charge_orb.scale = _charge_orb.scale.lerp(Vector2.ONE * target, minf(1.0, ORB_LERP * delta))
	_charge_orb.rotation += 5.0 * delta  # 자전 — 에너지가 도는 느낌


func _local_move(delta: float) -> void:
	if bound:
		# 코옵 속박(소울 케이지) — 파트너가 구출할 때까지 움직임/구르기 불가 (표시 전용 상태, 판정은 호스트)
		velocity = Vector2.ZERO
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if seated:
		# 앉는 동안 무방비·정지 (GDD §5 모닥불) — 몸을 움직이려는 입력이 오면 스스로 일어난다
		# ⚠ 버퍼가 살아 있는 동안 계속 참이지만 **멱등**이다(이미 일어났으면 이 블록에 안 들어온다).
		# 🔴 여기서 읽는 버퍼는 **앉은 뒤에 새로 누른 것뿐**이다 — 앉기 이전의 묵은 클릭은
		#   `set_seated(true)`가 지운다(reviewer C-1). 그게 없으면 F가 씹힌 것처럼 보인다.
		if dir != Vector2.ZERO or Input.is_action_just_pressed("roll") or _attack_buf_left > 0.0:
			set_seated(false)
		else:
			velocity = Vector2.ZERO
			return  # 뒤집기는 _play_dir_anim이 조준각에서 파생한다(단일 소스)
	if _roll_time_left > 0.0:
		_roll_time_left -= delta
		velocity = _roll_dir * _roll_speed()  # 구르기는 늪 슬로우 예외(이속·roll_dist가 거리를 늘린다, GDD §6)
	else:
		if _dash_speed > 0.0 and _swing_hit_armed:
			# 🔴 **마무리 타 돌진** (창 — `EquipDef.combo_dash`, 멤버 주석이 근거).
			#   ⑴ **이동 입력을 대체한다 — 합산하지 마라.** 합산하면 `_max_move_speed`(전사 260px/s)를 넘어
			#      원격 속도·변위 clamp가 **정당한 대시를 깎고**, 그러면 호스트 외삽이 과소평가돼 마무리
			#      타가 게스트에서 무음 거부된다(§3 이동속도 계약).
			#   ⑵ **끝나는 조건이 `_swing_hit_armed`다** — 판정 프레임까지 velocity가 살아 있어야 lead
			#      외삽이 변위를 덮는다(`_physics_process`의 호출 순서가 그것을 보장한다).
			#   ⑶ 늪 배율은 **안 곱한다** — 구르기와 같은 취급이다(커밋한 이동 동작). 곱해도 부호는
			#      안전하지만(속도가 줄 뿐) 대시 거리가 늪에서만 달라져 각 예산이 늪에서만 흔들린다.
			velocity = _dash_dir * _dash_speed
		elif _attack_anim_left > 0.0:
			# 🔴 **공격 중에는 걷지 못한다** (사용자 요청 2026-08-01: "공격하면서 움직이는 거 불가능").
			#   스윙 창(`_attack_anim_left`) 동안만이다 — 쿨다운은 안 묶으므로 휘두름이 끝나면 바로
			#   움직인다(§3 「스윙 창 < attack_cooldown」이 그 여유를 보장한다).
			#   ⚠ 완전 정지가 아니다: 위 분기의 **타별 전진**(`_dash_speed`)이 공격 중 이동을 대신한다.
			#     둘의 순서를 바꾸면 대시가 이 가드에 먹혀 마무리 돌진이 통째로 사라진다.
			#   ⚠ 구르기는 아래 공용 검사가 그대로 받는다 — 스윙 중에도 굴러서 뺄 수 있다
			#     (`_cancel_swing`이 스윙과 대시를 함께 끊는다).
			velocity = Vector2.ZERO
		else:
			# 걷기만 늪 배율 적용. 기 모으는 중(charge 무기)이면 추가로 느려진다 — 모으는 대가(사용자 확정)
			var charge_mult := CHARGE_MOVE_MULT if _charging else 1.0
			velocity = dir * _move_speed() * _swamp_mult() * charge_mult
		# 🔴 **구르기 입력 검사는 대시·걷기 공용이다 — 갈래 안에 두지 마라.** 돌진 중에 구르기가 안 먹으면
		#   "법사는 차지를 빼는데 전사는 돌진을 못 뺀다"가 되고, `_cancel_swing`이 스윙과 돌진을 **함께**
		#   끊는다는 계약이 도달 불가능해진다(그 함수 주석이 근거).
		if _alive and not roll_suppressed and Input.is_action_just_pressed("roll") and _roll_cd_left <= 0.0:
			_roll_dir = dir if dir != Vector2.ZERO else _aim_dir()
			_roll_time_left = CombatMath.ROLL_TIME_S
			_cancel_swing()  # 구르기는 선딜·스윕·후딜 어디서든 스윙을 끊는다 (근거 = _cancel_swing)
			_cancel_skill()  # 스킬 선딜도 **같은 규약** — 아직 호스트로 나간 것이 0이라 대가 없이 뺀다
			# 🔴 로컬 쿨과 호스트 그랜트 검증(is_roll_grant_ok)이 **같은 함수**를 지난다(§3) —
			#   사본을 만들면 "굴러지는데 무적이 안 걸리는" 상태가 되고 화면에 이유가 안 드러난다.
			_roll_cd_left = CombatMath.effective_roll_cooldown(trait_value("roll_cd"))
			EventBus.player_roll.emit(global_position)  # 구르기 SFX (로컬)
			_dash_burst(_roll_dir)  # 잔상 첫 장·먼지 버스트·진행 방향 카메라 반동 (표시 전용)
			# 구르기 선언 — 호스트가 쿨다운 검증 후 i-frame 창 부여 (방향은 연출용)
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ROLL, "dx": _roll_dir.x, "dy": _roll_dir.y})
	move_and_slide()
	# 뒤집기는 _play_dir_anim이 조준각에서 파생한다(단일 소스) — 여기서 대입하면 서로 덮어쓴다


# 공격은 폴링이 아니라 _unhandled_input — UI(Control)가 소비한 클릭은 여기 안 온다 (mouse_filter 존중)
func _unhandled_input(event: InputEvent) -> void:
	if is_local and event.is_action_pressed("attack"):
		# 🔴 대입(갱신)이지 누적이 아니다 — 연타해도 버퍼가 쌓여 여러 타가 몰아 나가지 않는다.
		#   ⚠ 여기는 여전히 **엣지 트리거**다(홀드 반복 없음). 홀드 경로는 `auto_fire`(shoot)·차지뿐이다.
		# 🔴 **쿨다운으로 묶는다** (netreview 보완 C, 2026-08-01). 상수만 쓰면 뜻이 직업마다 갈린다 —
		#   궁수(cd 0.15)는 버퍼 0.25가 쿨다운의 **167%** 라 쿨다운 전 구간이 버퍼 안에 들어가고,
		#   그러면 "리듬 보정"이 아니라 **클릭 오토파이어**가 된다(한 번 누르면 다음 타가 무조건 나간다).
		#   묶어 두면 상수 주석의 "쿨다운의 마지막 일부"가 **전 직업에서 참**이 된다.
		# ⚠ 뜸(`combo_delay`)이 아니라 `effective_cooldown`으로 묶는다 — 둘 중 **작은 쪽**이라 보수적이다.
		var cap := ATTACK_BUFFER_S
		if job != null:
			cap = minf(cap, CombatMath.effective_cooldown(job, _haste()))
		_attack_buf_left = cap
	# 🔴 하위 직업 스킬(Q) — **평타와 같은 입구다.** `_unhandled_input`이라 UI(Control)가 소비한
	#   입력은 여기 안 온다 = 모달 규약을 새 조건 없이 그대로 물려받는다(rules §5 · `_local_combat`의
	#   클릭 경로와 같은 근거). 나머지 게이트(사망·구르기·무장·쿨다운)는 `_try_cast_skill` 한 곳에 있다.
	# ⚠ 버퍼(선입력)를 두지 않는다 — 쿨다운이 8~9s라 "쿨이 열리는 첫 프레임" 경합이 없고, 버퍼를 두면
	#   구르기 중에 누른 Q가 구르기 직후 **의도치 않게** 나간다(평타와 달리 리듬 보정 대상이 아니다).
	elif is_local and event.is_action_pressed("skill"):
		_try_cast_skill()


# 현재 착용 무기의 공격 모션 (EquipDef.motion_type) — 미착용/미지정이면 "swing" 폴백. _do_attack 분기의 단일 소스.
func _weapon_motion() -> String:
	return _weapon_override.motion_type if _weapon_override != null else "swing"


func _local_combat(delta: float) -> void:
	# 🔴🔴 **여기서 버퍼를 비우지 않는다 — 이 한 줄이 이 작업의 전부다** (2026-08-01).
	#   옛 코드는 `var want := _attack_queued` **직후** `_attack_queued = false`로 무조건 비웠다.
	#   그래서 쿨다운·구르기 중에 누른 클릭이 통째로 사라졌고, 콤보가 창 안에 정확히 재클릭할 때만
	#   이어졌다(= "공격마다 무기가 제자리로 돌아간다"의 원인). 소진은 **실제로 발동한 자리**에서만 한다.
	# 🔴 **여유(`_attack_buf_grace`)를 여기 한 곳에서 문다** — `want`를 통해 근접·발사·차지 **세 경로가
	#   전부** 지나므로, 새 모션 타입이 생겨도 여유가 자동으로 따라간다(분기마다 붙이면 반드시 하나 샌다).
	#   ⚠ 홀드 연사는 이 게이트 밖이다 — 그쪽은 `auto_fire_gap_s`가 이미 같은 여유를 갖고 있다.
	var want := _attack_buf_left > 0.0 and _attack_buf_grace <= 0.0
	if not _alive:
		_attack_buf_left = 0.0  # 사망 = 들고 있던 입력도 소멸 (부활 직후 유령 스윙 차단 — 차지·연사와 대칭)
		_attack_buf_grace = 0.0
		_cancel_charge()  # 사망 = 모으던 것 소멸 (고스트가 계속 모으지 않게)
		_stop_auto_fire()  # 사망 = 홀드 연사도 소멸 (고스트가 계속 쏘지 않게 — 차지와 대칭)
		_cancel_skill()  # 사망 = 시전 중이던 스킬도 소멸 (관전 고스트가 발동하지 않게 — 위 둘과 대칭)
		return
	# 무장 해제(무기 미착용) = 공격 불가 — 판정·궤적·소리 전부 안 나간다. 무기가 곧 공격 수단.
	var motion := _weapon_motion()
	if motion == "charge" and _is_armed():
		_tick_charge(delta, want)  # 누르고 있는 동안 모으고, 떼면 발사 (쿨다운 게이트는 안에서)
		return
	# 홀드 연사(속사수 `auto_fire`) — 이미 켜져 있으면 버튼 유지가 곧 다음 발의 입력이다.
	# ⚠ `motion == "shoot"`을 여기서 다시 본다 — 무기 교체가 이미 끄지만(set_weapon_visual), 이 조건이
	#   없으면 그 리셋을 한 곳이라도 놓쳤을 때 **근접 무기가 홀드로 연타되는** 훨씬 나쁜 상태가 된다.
	# ⚠ `seated` 가드 — 앉으면 홀드가 끊긴다(GDD §5 "앉는 동안 무방비"). 클릭 발사는 `_attack_buf_left`가
	#   서서 `_local_move`가 스스로 일어나는데, 홀드는 그 큐를 안 거치므로 **앉은 채로 계속 쏘고
	#   회복까지 받는** 경로가 열려 있었다(2026-07-28 netreview I4). 다시 클릭하면 큐가 서서 일어난다.
	# ⚠ `is_trait_on`을 유지 조건에서도 다시 본다 — 마을에서 속사수를 슬롯에서 빼면 그 즉시 끊긴다.
	#   안 보면 버튼을 놓을 때까지 연사가 이어져 "표시(특성 없음) ≠ 상태(연사 중)"가 된다(판정 차이는
	#   없다 — 호스트는 `auto_fire`를 안 읽는다 — 순수 표시 정합, 2026-07-28 netreview M-3).
	if _auto_firing:
		if (motion == "shoot" and not seated
				and CombatMath.is_trait_on("auto_fire", trait_value("auto_fire"))
				and Input.is_action_pressed("attack")):
			want = true
		else:
			_stop_auto_fire()
	if want and _attack_cd_left <= 0.0 and _roll_time_left <= 0.0 and _is_armed():
		# 🔴 **소진은 발동 프레임에.** 남겨 두면 같은 클릭이 다음 프레임에 한 번 더 나가고, 그러면
		#   발사 간격이 물리 프레임 하나가 되어 호스트 게이트가 정직한 타격을 무음 거부한다.
		#   ⚠ 홀드 연사(`_auto_firing`)로 `want`가 켜진 경우엔 비울 것이 없다(이미 0) — 무해하다.
		_attack_buf_left = 0.0
		_attack_buf_grace = 0.0
		var dir := _aim_dir()
		# 모션 타입 분기 (§2 게이트): shoot = 원거리 발사(화살), charge = 위에서 처리,
		# 🔴 **그 외(= "swing"·"thrust"·미지정)는 전부 근접 경로다** — 찌르기가 베기와 갈리는 것은
		#   **판정이 아니라 무기 스프라이트의 모션 곡선**(_motion_at)뿐이다. 여기에 `elif motion ==
		#   "swing"`을 넣으면 찌르기가 **에러 없이 공격 자체를 못 하게** 된다(호스트 쪽 대칭은
		#   `CombatMath.is_projectile_weapon`이 thrust를 false로 돌려 근접 확정을 받는 것).
		if motion == "shoot":
			if _auto_firing:
				# 🔴 홀드로 나가는 발사는 **콤보를 전진시키지 않는다**(사용자 확정: 홀드 = 균일 연사).
				#   전진시키면 마무리 타(사거리 2배·데미지 2.5배)가 자동으로 무한 반복돼 화력 예산 밖이
				#   되고, "끊어 쳐서 쭉을 쓴다"는 선택 자체가 사라진다.
				#   ⚠ 호스트는 이 결론에 **독립적으로** 도달한다 — G_SHOOT "cb"에 0이 실리고
				#   authoritative_combo가 `min(주장, 자기 계수)`이라 0으로 눌린다(판정 ≤ 표시, §3).
				#   즉 이 줄이 지워져도 호스트 판정은 안 세지고 **내 화면만** 마무리 타로 그려진다
				#   (안전한 방향의 갈라짐 — 그래도 표시가 거짓이 되므로 지우지 마라).
				_shot_combo_index = 0
				_last_shot_msec = Time.get_ticks_msec()
				# 🔴 쿨다운이 아니라 `auto_fire_gap_s` — 호스트 발사율 게이트의 여유가 궁수 0.15초에서
				#   15ms뿐이라, 쿨다운 그대로 쏘면 정직한 화살이 지터로 조용히 거부된다(그 함수 주석).
				_attack_cd_left = CombatMath.auto_fire_gap_s(job, _haste())
			else:
				# 🔴 쿨다운을 콤보가 정한다 — 다음 타에 뜸이 붙어 있으면 그만큼 길어진다("평·평·쭉").
				_attack_cd_left = _advance_shot_combo()
				# 이 클릭부터 홀드 반복을 연다(특성이 있을 때만). **첫 발은 항상 콤보 경로**를 지나므로
				# 딸깍 한 번은 특성 유무와 무관하게 기존과 완전히 같다(항등).
				_auto_firing = CombatMath.is_trait_on("auto_fire", trait_value("auto_fire"))
			_fire_projectile(dir, 0)
		else:
			# 🔴 **쿨다운을 콤보가 정한다 — 원거리(`_advance_shot_combo`)와 같은 자리다**(v2.2).
			#   다음 타에 뜸(`combo_delay`)이 붙어 있으면 그만큼 길어진다. ⚠ 이 반환을 무시하고
			#   `effective_cooldown`으로 되돌리면 **정직한 빠른 클릭이 마무리 타를 영영 못 얻는다**
			#   (호스트 인정 하한이 뜸을 포함하는데 클라 간격이 안 하면 `advance_combo`가 리셋한다).
			#   콤보 배열이 없는 무기는 두 식이 **완전 항등**이다.
			_attack_cd_left = _swing_attack(dir)


# 차지 발사(charge 무기) — 누른 순간 모으기 시작, 단계는 홀드 시간에서 리졸브(CombatMath 단일 소스),
# 떼면 그 단계로 발사. 구르기·사망·무기 교체는 취소. 모으는 동안 이동은 CHARGE_MOVE_MULT로 느려진다.
# ⚠ 시작은 _unhandled_input(UI가 소비한 클릭은 안 옴)이지만 유지·해제는 폴링이다 —
#   UI 위에서 버튼을 떼도 발사가 되도록(안 그러면 영구 차지 상태로 잠긴다).
func _tick_charge(delta: float, want: bool) -> void:
	if _roll_time_left > 0.0:
		_cancel_charge()  # 구르기로 취소 (사용자 확정: 모으는 중 위험하면 굴러서 뺀다)
		return
	if not _charging:
		if want and _attack_cd_left <= 0.0:
			# 🔴 차지도 **같은 버퍼 규약**을 지난다 — 소진은 여기(발동 자리)에서.
			#   왜 차지에도 적용하나: `want`의 의미가 다르긴 해도(누른 **순간**) 버퍼가 여는 것은
			#   여전히 "쿨다운 중에 누른 시작 신호를 살려 준다"뿐이고, 차지 시간·레벨 검증
			#   (`is_charge_time_ok`)은 **발사 시각 기준**이라 아무것도 안 움직인다.
			#   ⚠ 버퍼로 열린 차지에서 이미 버튼을 뗐다면 다음 프레임에 0단계 탭 발사가 된다 —
			#     "쿨다운 중에 누른 딸깍이 쿨다운이 끝나자 나간다"라서 의도한 동작이다. 🔴 그 탭 발사는
			#     간격이 `combo_gap_s`에 붙으므로 **여유가 반드시 필요하다** — `want`가 이미 물고 왔다.
			_attack_buf_left = 0.0
			_attack_buf_grace = 0.0
			_charging = true
			_charge_held = 0.0
			_charge_level = 0
		return
	if Input.is_action_pressed("attack"):
		_charge_held += delta
		var lv := CombatMath.charge_level_for(_charge_held, _charge_step_time)
		if lv > _charge_level:
			_charge_level = lv
			_orb_pop_left = ORB_POP_TIME
			EventBus.player_swing.emit(global_position, _charge_sfx, 1.0)  # 단계 상승 "딸깍" (로컬)
		return
	var level := _charge_level
	_cancel_charge()
	# 차지도 shoot과 **같은 콤보 경로**를 지난다 — 지팡이는 combo_* 배열이 비어 있어 결과가
	# effective_cooldown과 완전 항등이다(법사 동작 무변경). 갈래를 만들지 않으려는 것: 리듬 있는
	# 차지 무기가 생기면 .tres 한 장으로 떨어진다(rules §4).
	_attack_cd_left = _advance_shot_combo()
	_fire_projectile(_aim_dir(), level)


func _cancel_charge() -> void:
	_charging = false
	_charge_held = 0.0
	_charge_level = 0


# 홀드 연사 종료 — **플래그만 끈다. 콤보 상태는 절대 건드리지 않는다.**
# 🔴 첫 판에 여기서 `_shot_combo_index`·`_last_shot_msec`을 지웠다가 **속사수가 3타를 영영 못 내는**
#   상태를 만들었다(2026-07-28 netreview C1). `_auto_firing`은 **첫 클릭에** 켜지므로, 딸깍 한 번만
#   쳐도 다음 프레임에 여기가 불려 콤보가 소거된다 → 다음 클릭의 `elapsed_s`가 1e6초가 되어
#   `advance_combo`가 영원히 0을 돌려준다. 즉 "끊어 쳐서 쭉을 쓴다"는 이 특성의 존재 이유가
#   구현에서 사라졌는데 **cb가 항상 0이라 호스트와 어긋나지도 않아** 에러도 desync도 없었다.
# ⚠ `_last_shot_msec` 소거는 원래 `_on_death`(:528)가 명시적으로 금지한 동작이기도 하다 —
#   호스트는 자기 기록을 사망으로 지우지 않으므로 클라만 지우면 타수가 어긋난다.
# 홀드 뒤 첫 클릭이 "2타"로 이어지는 것은 이미 auto 분기가 막는다(매 발 index 0 · last_shot = now로
# 정규화한다) — 종료 시점에 지울 것이 없다.
func _stop_auto_fire() -> void:
	_auto_firing = false


# 원거리 평타 콤보 전진 — 이번 발사의 타수(_shot_combo_index)를 굳히고, **다음 타의 뜸까지 포함한**
# 쿨다운(s)을 돌려준다. 🔴 전진 규칙은 CombatMath.advance_combo 단일 소스이고 **호스트도 같은 함수**를
# 자기 수신 간격으로 돌린다(§3) — 여기에 사본 조건문을 두면 "내 화면은 3타인데 판정은 평타"가 된다.
# 🔴 뜸을 **다음 발사의 쿨다운에 미리 실어 두는 것**이 "3타 직전에 살짝 뜸"의 구현이다.
#   ⚠ **활은 클릭 1회 = 1발이다** — 발사 입력은 `_unhandled_input`의 `is_action_pressed`(엣지 트리거,
#   echo 없음)라 홀드 연사가 안 된다. 폴링(`Input.is_action_pressed`)은 `_tick_charge`(차지 전용)에만 있다.
#   그래서 뜸은 "버튼을 눌러 두면 알아서 나오는 리듬"이 아니라 **다음 클릭을 그만큼 늦게 받는 것**이다.
# 🔴 이 사실이 호스트 게이트 두 개에 서로 다르게 걸린다 (2026-07-27 netreview M3):
#   **하한(너무 빠름)** — 안전하다. `_attack_cd_left`가 뜸만큼 입력을 막으므로 정직한 클릭은 구조적으로
#     인정 하한보다 빠를 수 없다.
#   🔴 **상한(너무 쉼)** — 그 보호를 **못 받는다.** 사람이 언제 다시 클릭할지는 아무것도 강제하지 않는다.
#     조준하거나 굴렀다가 쏘면 창을 넘겨 콤보가 리셋된다 = "쭉"이 안 나온다. 그래서 창(COMBO_GRACE_S)은
#     전사 근접 콤보와 같은 총 0.95s로 맞춰 두었다 — 좁히면 리듬 자체가 실기에서 사라진다.
func _advance_shot_combo() -> float:
	var now := Time.get_ticks_msec()
	var haste := _haste()
	_shot_combo_index = CombatMath.advance_combo(_shot_combo_index,
		float(now - _last_shot_msec) / 1000.0, job, _weapon_override, haste)
	_last_shot_msec = now
	var nxt := (_shot_combo_index + 1) % CombatMath.combo_len(_weapon_override)
	return CombatMath.combo_gap_s(job, _weapon_override, nxt, haste)


# 이 아바타의 콤보 길이 — **무기 데이터가 정한다**(도끼 2 · 대검 3 · 창 4).
# 🔴 `CombatMath.combo_len` 단일 소스이고 **호스트도 같은 함수**를 지난다(§3) — 여기에 상수를 두면
#   (옛 `COMBO_MAX = 3`) 도끼가 3타로 돌고 창이 4타째를 영영 못 낸다.
func _combo_len() -> int:
	return CombatMath.combo_len(_weapon_override)


# 그 타수가 마무리 타인가 — ✅ **사본을 없앴다: 판단은 `CombatMath.is_combo_finish` 하나다**
#   (2026-07-29 리드 반영). 표시(여기)와 판정(`combat_authority`)이 **같은 함수**를 지나므로
#   "판정만 마무리"(= 판정 각은 넓은데 궤적은 평타 = 안 보이는데 맞는다)가 원리적으로 불가능하다.
#   `n > 1` 가드와 그 근거도 그 함수의 주석이 정본이다 — 여기 복제하지 마라.
func _is_combo_finish(index: int) -> bool:
	return CombatMath.is_combo_finish(_weapon_override, index)


# 콤보가 다음 타로 이어지는 창(s) — 🔴 **호스트와 같은 함수**(`CombatMath.combo_window_s`)를 지난다(§3).
#   인자는 **다음 타의 인덱스**다(그 타의 뜸이 창에 들어간다 — `advance_combo`가 같은 규약으로 잰다).
# ⚠ 우회해 `COMBO_GRACE_S`를 직접 더하지 마라 — 근접 무기는 `combo_grace`로 그 기본값을 덮으므로
#   창이 갈라지고, 갈라지면 `min`이 0을 택해 "내 화면은 마무리인데 판정은 평타"가 된다.
func _combo_window_s(next_index: int) -> float:
	if job == null:
		return 0.0
	return CombatMath.combo_window_s(job, _weapon_override, next_index, _haste())


# 이 아바타의 **근접 콤보 데미지 배율** — 🔴 호스트가 **자기** 근접 타격을 확정할 때 읽는다.
#   Net에 루프백이 없어 호스트는 자기 G_ATK를 받지 않으므로(`combat_authority._melee_combo`에 자기
#   항목이 **영원히** 없다) 자기 콤보의 유일한 소스가 로컬 아바타다 — `_on_player_shoot`이 같은 관용구다.
# 🔴 배율 리졸브는 `CombatMath.combo_damage_mult_at` 단일 소스를 지난다(§3) — 여기서 계산하지 않는다.
func melee_combo_mult() -> float:
	return CombatMath.combo_damage_mult_at(_weapon_override, _combo_index)


# 이번 근접 타의 넉백 입력 두 개 — 🔴 **`melee_combo_mult()`와 같은 관용구·같은 이유**(2026-08-02).
#   호스트는 Net에 루프백이 없어 자기 `G_ATK`를 안 받으므로 `_melee_combo`엔 **자기 항목이 영원히
#   없다** — 자기 무기·타수는 **로컬 아바타가 유일한 소스**다(2026-07-25 공속 Critical 부류).
#   그걸 안 지키면 "남을 때리면 밀리는데 내가 때리면 안 밀린다"가 되고 화면에 이유가 안 드러난다.
# ⚠ 세기 계산은 여기서 하지 않는다 — `CombatMath.knockback_px`/`knock_show_px`가 단일 소스이고,
#   적 저항(`body_radius`)은 확정 지점(CombatAuthority)만 아는 값이다.
func melee_weapon_def() -> EquipDef:
	return _weapon_override


func melee_is_finish() -> bool:
	return _is_combo_finish(_combo_index)


# 이번 스윙의 궤적·마무리 여부를 콤보 타수로 결정한다.
# 🔴 **v2.2부터 연출 전용이 아니다** — 여기서 굳힌 `_swing_is_finish`가 판정 각(`_resolve_swing_hit`)까지
#   고른다. 스윙 창·쿨다운은 여전히 콤보와 무관하다(§3 미러 계약).
# 짝수 타 = 좌→우 · 홀수 타 = 우→좌(되돌려 베기) · 마무리 타 = 더 넓게 + 깊이 내지른다.
# 로컬(입력)과 원격(G_ATK "cb") 공용이라 양쪽 화면이 같은 궤적을 그린다.
func _begin_swing(combo: int, chain_from_previous: bool = false) -> void:
	var n := _combo_len()
	_combo_index = clampi(combo, 0, n - 1)
	_swing_is_finish = _is_combo_finish(_combo_index)
	if is_local:
		_try_spawn_slash(_combo_index)   # 🗡 검성 검격 — 타수별 슬래시를 조준각으로 날림(표시 전용)
	# 🔴 **표시 각은 `melee_show_half_angle` 하나에서 온다 — 배율을 곱하지 마라**(v2.2, 상수 주석이 근거).
	#   판정 각(`melee_half_angle`)보다 `COMBO_FINISH_SHOW_MARGIN`만큼 넓고 그 부호를 **코드가** 쥔다.
	var arc := CombatMath.melee_show_half_angle(_weapon_override, _swing_is_finish)
	# 마무리 내지르기 — 🔴 베기와 찌르기가 **다른 배율**을 쓴다(위 상수 주석이 근거: 베기는 판정
	#   프레임에 0으로 돌아오는 중간 부풀림, 찌르기는 판정 프레임의 칼끝 거리 그 자체다).
	_swing_lunge_mult = 1.0
	if _swing_is_finish:
		_swing_lunge_mult = COMBO_FINISH_THRUST_LUNGE if _weapon_motion() == "thrust" \
			else COMBO_FINISH_LUNGE
	# 🔴 방향은 **패리티**(`index % 2`)다 — 절대 위치(`== 1`)로 두면 타수마다 다르게 깨진다:
	#   2타(도끼)면 반전 타와 마무리 타가 **한 타에 겹치고**, 4타(창)면 index 0과 2가 같은 방향·크기가
	#   되어 **두 타가 같은 궤적**이 된다. 패리티면 타수 무관하게 왕복이 유지된다.
	var reverse := CombatMath.is_combo_swing_reversed(_combo_index)
	_combo_entry_from_previous = chain_from_previous and _combo_pose_active
	_combo_entry_off = _motion_off if _combo_entry_from_previous else 0.0
	_combo_entry_lunge = _motion_lunge if _combo_entry_from_previous else 0.0
	_combo_pose_active = n > 1
	# 🔴 **타별 감각 점증의 단일 진행값**(멤버 주석이 정본). n = 1이면 0 = 도입 전과 항등.
	#   ⚠ 식은 `_combo_ramp_at()`이 쥔다 — 검기 반달이 이 멤버가 심기기 **전에** 스폰되므로 같은
	#     식을 거기서 한 번 더 쓰는데, 사본을 두면 두 램프가 갈라진다(2026-08-02).
	_combo_ramp = _combo_ramp_at(_combo_index)
	# 🔴 **어깨에 걸치기(시작각 젖힘)와 그 상한은 `_swing_entry_angle`이 쥔다** — 마무리 직전 타의
	#   대기 자세(`_combo_hold_pose`)가 **같은 함수**로 "다음 타가 출발하는 각"을 물어야, 젖혔다가
	#   다시 되돌아가는 구간이 원리적으로 안 생긴다(2026-08-01에 그 자리를 함수로 뺐다).
	#   근거(왜 시작각만인가 · 왜 span < 2π인가)는 `SWING_WINDUP_ARC_MULT` 상수 주석이 정본이다.
	_swing_from = _swing_entry_angle(_combo_index)
	_swing_to = -arc if reverse else arc
	if _weapon_motion() == "thrust":
		# 찌르기는 좌우로 훑지 않는다 — 예비에 창끝을 젖혔다가 **겨눈 선(0)으로 모아** 내지른다.
		# (타수마다 젖히는 쪽만 바뀌므로 손이 순간이동해 보이지 않는다 — 위 _swing_from 그대로 쓴다.)
		_swing_to = 0.0
	# 🔴 새 스윙은 젖힘을 물려받지 않는다 — 안 지우면 다음 대기 자세가 **이미 젖혀진 채** 시작한다.
	_windback_t = 0.0
	# 🔴 스윙 창은 콤보와 무관하게 _swing_time 그대로 — §3 미러(swing_time < attack_cooldown) 보존.
	_attack_anim_left = _swing_time
	# 🔴 **시간 축을 여기서 굳힌다**(netreview M-1 — 멤버 주석이 근거). 이후 무기 교체·레벨업이
	#   이 스윙의 판정 시점을 못 움직인다. `_tick_swing_motion`·`_motion_at`은 살아 있는
	#   `_swing_time`/`_swing_windup`을 **읽지 않는다** — 읽으면 이 방어가 통째로 무효다.
	_swing_win_total = maxf(_swing_time, 0.0001)
	_swing_windup_l = _swing_windup
	_swing_strike_l = _swing_strike
	# 🔴 스탠스 각도 **여기서 굳힌다** — `_tick_stance`가 선딜 동안 이 값에서 0까지 끌어내린다.
	#   스윙 중 살아 있는 `_stance_sway`를 기준으로 삼으면 자기 자신을 참조해 0에 도달하지 못한다.
	_stance_enter_sway = _stance_sway
	_swing_hit_at = _swing_win_total * (_swing_windup_l + _swing_strike_l)
	# 🔴🔴 **젖힘 시간을 「그 타의 실제 빈 구간」에서 유도한다** (상수 주석이 정본). 빈 구간 =
	#   `combo_gap_s(다음 타) − 스윕 완료`이고 **타마다 4배 넘게** 벌어지므로(196~488ms) 상수로 두면
	#   짧은 타에서만 젖힘이 덜 진행된 채 다음 타가 나간다 = 칠 때마다 자세가 다르다.
	# 🔴 쿨다운과 **같은 함수**(`combo_gap_s`)를 지난다 — `_swing_attack`의 반환값·`_combo_window_s`와
	#   같은 소스라, 뜸이나 haste를 조여도 젖힘이 자동으로 따라온다(사본을 두면 갈라진다).
	# ⚠ 원격 아바타도 자기 무기·haste로 로컬 리졸브한다(네트워크 0) — 두 화면의 박자가 같아진다.
	if job != null:
		var gap := CombatMath.combo_gap_s(job, _weapon_override, _next_combo_index(), _haste())
		_windback_time = clampf((gap - _swing_hit_at) * COMBO_WINDBACK_FILL,
			COMBO_WINDBACK_MIN_S, COMBO_WINDBACK_MAX_S)
	else:
		_windback_time = COMBO_WINDBACK_MAX_S
	# 새 스윙은 항상 박힘 없이 시작한다 — 안 지우면 이전 스윙의 멎음이 이어져 모션이 굳는다.
	_swing_bite_left = 0.0


# 근접 스윙 **개시** — 여기서 판정하지 않는다(선딜 축 2026-07-28).
# 🔴 **판정은 `_tick_swing_motion`이 스윕 완료 시점(`t = 선딜 + 스윕`)에 `_resolve_swing_hit`으로 낸다.**
#   전에는 클릭한 그 프레임에 판정·G_HIT_REQ·궤적 예약이 전부 끝나서, 판정(0s)·궤적(0.07s)·칼이
#   실제로 그 각을 훑는 구간이 **셋 다 어긋나** 있었다. "칼이 지나갈 때 맞는다"로 정렬한 것이다.
#
# 🔴 **방향은 여기서 고정된다(`_swing_dir`) — 이 선택은 네트워크가 강제한다.**
#   `G_ATK`는 **모션 시작 시점**에 보내야 원격의 선딜 타이밍이 맞는데, 그 메시지에 실린 방향이 곧
#   상대 화면이 그릴 방향이다. 로컬이 나중에 방향을 갱신하면 **내 화면과 상대 화면이 서로 다른 곳을
#   벤다**(화면에 이유가 안 드러나는 부류). 갱신형을 하려면 방향 갱신 메시지가 새로 필요하다 =
#   신규 kind. 대신 커밋의 대가는 **구르기 취소**(`_cancel_swing`)로 돌려준다.
#
# ⚠ 쿨다운(`_attack_cd_left`)은 호출부가 **이 함수의 반환값으로** 클릭 시점에 소비한다 — 판정이
#   늦어져도 발사 간격은 그대로다(DPS 불변). 취소해도 쿨은 돌아간 뒤라 취소 남용 유인이 없다.
#
# 🔴 **반환값 = 다음 타까지의 쿨다운(s) = `combo_gap_s`(뜸 포함)** — `_advance_shot_combo`의 미러다.
#   ⚠ **이게 없으면 정직한 빠른 클릭이 마무리 타를 영영 못 얻는다.** 호스트 인정 하한
#   (`combo_min_gap_s`)은 뜸을 포함하는데 클라 쿨다운이 안 하면 `elapsed < 하한`이 되어
#   `advance_combo`가 리셋한다 — 화면엔 이유가 안 드러나고 "가끔 마무리가 안 나온다"로만 보인다.
#   ⚠ 콤보 배열이 없는 무기는 `combo_gap_s`가 `effective_cooldown`과 **완전 항등**이다(뜸 0).
func _swing_attack(dir: Vector2) -> float:
	# 🔴 **가드가 맨 앞이어야 한다 — 뒤에 두면 쿨다운 0.0을 돌려주는 스팸 경로가 열린다**
	#   (netreview m-4). 전에는 이 검사가 `G_ATK` 송신 **뒤**에 있어서, `job`이 없는 상태가 되면
	#   쿨다운이 0이 되어 클라가 **매 물리 프레임(60Hz) reliable 채널로** G_ATK를 쏘았다. 호스트가
	#   무시하니 판정 영향은 0이지만 릴레이 대역과 로그를 조용히 태운다(옛 코드는 같은 상태에서
	#   시끄럽게 죽어 눈에 띄었다). 0이 아닌 폴백을 돌려 스윙 자체를 시작하지 않는다.
	if job == null:
		return NO_JOB_SWING_CD_S
	_swing_dir = dir
	# 콤보 이어가기 — 창 안이면 다음 타, 아니면 처음부터. 🔴 창은 `CombatMath.combo_window_s`가 정한다
	#   (로컬·호스트 공용 §3). 옛 `_swing_time + COMBO_WINDOW`는 호스트 창과 최대 160ms 어긋나 있었다.
	var n := _combo_len()
	var continues_combo := _combo_left > 0.0
	var idx := ((_combo_index + 1) % n) if continues_combo else 0
	_begin_swing(idx, continues_combo)
	# 다음 타의 창 — 인덱스는 **그 다음 타**다(그 타의 뜸이 창에 들어간다, `advance_combo` 규약).
	_combo_left = _combo_window_s((idx + 1) % n)
	_arm_swing_trail()
	# 🔴🔴 **자기 스로틀 — 판정을 호스트 게이트 아래로 내려보내지 않는다** (netreview M-1의 실제 결과).
	#   호스트는 **판정 도착 간격**을 `쿨다운 × FIRE_RATE_SLACK`로 재는데, 클라의 발사 간격은
	#   쿨다운이라 `간격 = 쿨다운 + t_hit[이번] − t_hit[직전]`이다. `t_hit`가 무기마다 다르므로
	#   **짧은 무기로 바꾸면 간격이 줄어 정직한 타격이 무음 거부**된다(실측 4조합: axe→worn 316ms ·
	#   axe→spear 319 · iron→worn 328 · iron→spear 331 < 요구 360).
	# 🔴 **시간 축 래치(`_begin_swing`)로는 이게 안 닫힌다** — 래치는 비행 중 스윙의 타임라인을
	#   굳힐 뿐 **연속 두 스윙 사이 간격**을 못 건드린다. 그래서 둘 다 필요하다.
	# 🔴 처방이 "**클라가 물러선다**"인 것은 이 프로젝트의 선례 그대로다(`auto_fire_gap_s`,
	#   2026-07-28 netreview C2) — 호스트 게이트를 넓히면 **스팸 상한이 같이 오른다**.
	# ⚠ 미루는 방향은 **안전한 쪽**이다: 궤적은 이미 부채꼴을 다 덮은 뒤라 `표시 ⊇ 판정`이 유지된다
	#   (최대 지연 44ms = 페이드 180ms의 1/4이라 자국이 아직 뚜렷하다).
	# ⚠ 같은 무기를 계속 쓰면 `t_hit`가 같아 `earliest ≤ _swing_hit_at`이므로 **완전 항등**이다.
	# 🔴 **여유가 있어야 한다 — 호스트 임계에 딱 붙이면 여유 0이다** (netreview I-3). 호스트가 재는
	#   것은 클라의 발사 간격이 아니라 **도착 간격**이고, 게스트에선 `도착 = 클라 간격 + (편도₂ − 편도₁)`
	#   이라 음의 지터가 조금만 있어도 거부된다. 선례(`auto_fire_gap_s`)가 반드시 한 프레임을 더한다.
	# 🔴 **그런데 그냥 더하면 발산한다** — 점화식이 `x[n+1] = max(t_hit, x[n] − cd + gate)`라
	#   `gate > cd`면 매 스윙 `(gate − cd)`씩 **누적**된다(최대 haste에서 실제로 +1.3ms/스윙).
	#   그래서 `melee_throttle_gap_s`가 `cd`로 clamp한다 = **같은 무기 항등이 구조적으로 보장**된다.
	var gate_s := 0.0
	if job != null:
		gate_s = CombatMath.melee_throttle_gap_s(job, _haste())
	var earliest_s := float(_last_swing_hit_msec - Time.get_ticks_msec()) / 1000.0 + gate_s
	# 🔴🔴 **한 스윙이 미뤄질 수 있는 양에 상한을 건다 — 안 걸면 래칫이 된다** (netreview 3차 ②).
	#   `melee_throttle_gap_s`의 `minf(..., cd)` clamp는 **haste ≥ 0.2에서 상시 발동**한다
	#   (`cd ≤ 1/3`이 조건 — 상한 0.5의 [0.2, 0.5] 구간, 즉 haste 범위의 **상위 60%**).
	#   그 구간에서 `gate == cd`라 점화식의 감쇠가 **0**이 되어 `x[n+1] = max(t_hit, x[n])` =
	#   **단조 비감소**가 된다: 도끼(t_hit .216) → 낡은 대검(.132)으로 바꾸면 빠른 무기가 느린
	#   무기의 부풀린 지연을 **계속 물고 간다**(에러 0 · 데미지 손실 0 · 양쪽 화면 동일 —
	#   체감만 "무기를 바꿨는데 계속 굼뜨다"). 풀리는 조건이 **헛치기 한 번**이라 보스전에서 오래 간다.
	# 🔴 상한을 두면 `x[n+1]`이 `x[n] + 상수`로 **위에서 막혀** 발산도 무한 래칫도 원리적으로 불가능하다.
	#   유도 = `data/equipment` 전수의 `max(t_hit) − min(t_hit)`(스로틀이 메워야 할 결손의 최대치).
	#   ⚠ 상한 안에서는 여전히 지속된다(감쇠가 0이므로) — 다만 **84ms에서 멈춘다**. 감쇠를 되살리려면
	#     `gate < cd`가 필요한데 그건 여유(`+프레임`)를 포기하는 것이라 I-3 회귀다. 천장
	#     (`cd × (1 − FIRE_RATE_SLACK)`, 상한 haste에서 26.7ms)이 그 트레이드오프를 **구조적으로** 강제한다.
	# ⚠ 상한도 **haste로 줄어든다**(`melee_throttle_max_s`) — 덮는 대상(`t_hit` 결손)이 그렇기 때문이다.
	#   절대값으로 두면 haste ≥ 0.25에서 `t_hit + 상한 > swing_time`이 되어 판정이 **스윙 창 밖**으로
	#   새고(Gap C), 그러면 무기가 평상 자세로 돌아간 뒤에 데미지 숫자만 뜬다.
	_swing_hit_left = clampf(maxf(_swing_hit_at, earliest_s),
		_swing_hit_at, _swing_hit_at + CombatMath.melee_throttle_max_s(_haste()))
	_swing_hit_armed = true
	# 🔴 **마무리 타 돌진** — 「선딜 시작 → 판정」 전 구간에 균일 속도로 흘린다(멤버 주석이 근거).
	#   나누는 값이 `_swing_hit_left`(= 스로틀 반영된 **실제** 판정 시각)이라 스로틀로 미뤄져도
	#   이동 거리는 데이터 그대로다 — `_swing_hit_at`으로 나누면 미뤄진 만큼 더 멀리 간다(각 예산 초과).
	_dash_speed = 0.0
	_dash_dir = dir
	# 🔴 **평타에도 전진이 붙는다** (사용자 요청 2026-08-01). 공격 중 걷기를 막았으므로(`_local_move`)
	#   이 전진이 **공격 중 이동의 전부**다 — 0으로 되돌리면 휘두르는 동안 완전히 못 움직인다.
	#   비율은 `CombatMath.NONFINISH_DASH_RATIO`가 쥔다(무기별 값을 새로 만들지 않는다).
	var dash_px := CombatMath.combo_dash_dist(_weapon_override, _swing_is_finish)
	if dash_px > 0.0:
		_dash_speed = dash_px / maxf(_swing_hit_left, 0.0001)
	# 🔴 "cb" = 콤보 타수. **v2.2부터 판정 입력이다**(데미지 배율·마무리 각) — 호스트가 자기 G_ATK 수신
	#   간격으로 직접 세고 이 주장은 `min` 상한으로만 쓴다(`authoritative_combo`, G_SHOOT "cb"와 같은 규약).
	#   그래서 부풀려 주장해도 **내 화면만** 마무리로 그려지고 판정은 안 따라온다(판정 ≤ 표시, §3).
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ATK, "dx": dir.x, "dy": dir.y, "cb": _combo_index})
	# (`job == null` 가드는 **함수 맨 앞**으로 옮겼다 — netreview m-4. 여기 두면 G_ATK가 이미 나간 뒤라
	#  쿨다운 0.0이 매 프레임 재송신을 만든다.)
	# 다음 타의 뜸까지 포함한 쿨다운 — 함수 주석의 "정직한 빠른 클릭" 논거가 이 한 줄에 걸려 있다.
	return CombatMath.combo_gap_s(job, _weapon_override, (_combo_index + 1) % n, _haste())


# 스윙 취소 — 🔴 **구르기가 선딜·스윕·후딜 어디서든 스윙을 끊는다.**
#   ⑴ 차지가 이미 구르기로 취소된다(`_tick_charge`) — **같은 관용구**를 안 따르면 "법사는 빼는데
#      전사는 못 뺀다"가 된다. ⑵ 선딜이 생기면 "예고를 보고 구르기"의 예산이 그만큼 줄어드는데,
#      취소가 그 손실을 되돌린다(협동 보스전이 핵심 재미인 게임에서 회피를 잠그면 안 된다).
#   ⑶ 쿨다운은 이미 소비됐으므로 **취소가 이득이 아니다** = 남용 유인 없음 = DPS 중립.
# 🔴 **신뢰 경계 변화 0** — 판정이 아직 안 났으니 `G_HIT_REQ`를 안 보냈다(호스트로 나간 것이 없다).
# ⚠ 원격 화면의 취소 신호는 **이미 있는 `G_ROLL`이다** — 새 메시지 0개(`play_roll_fx`가 여기를 부른다).
func _cancel_swing() -> void:
	_attack_anim_left = 0.0
	# 🔴🔴 **하중을 지는 것은 이 플래그 하나다 — 아래 `0.0`은 "해제"가 아니라 "즉시 발화"다.**
	#   (netreview 4차 ③) 발화 조건이 `armed and left <= 0.0`이라, 이 줄을 지우고 카운트다운만 남기면
	#   **취소된 스윙이 다음 프레임에 판정을 낸다** — 구르기로 뺐는데 `G_HIT_REQ`가 나가는 것이라
	#   `_cancel_swing`이 내세우는 "호스트로 나간 것이 0"이라는 근거가 통째로 무너진다(신뢰 경계 회귀).
	#   `0.0`이 직관적으로 "꺼짐"처럼 보여서 더 위험하다 — **둘을 한 줄로 합치지도 마라.**
	_swing_hit_armed = false
	_swing_hit_left = 0.0
	_swing_onset_pending = false
	_swing_fx_armed = false
	_swing_bite_left = 0.0
	# 🔴 돌진도 같이 끊는다 — 구르기가 스윙을 취소하는데 몸이 계속 앞으로 밀리면 구르기 방향과 싸운다.
	#   ⚠ `_swing_hit_armed = false`만으로도 `_local_move`의 대시 조건이 꺼지지만, 여기서 명시로 0을
	#     넣어 **다음 스윙이 이 값을 물려받지 않게** 한다(플래그 하나에 두 하중을 걸지 않는다).
	_dash_speed = 0.0
	_motion_off = 0.0
	_motion_lunge = 0.0
	# 취소된 스윙은 젖힘도 처음부터다 — 콤보가 살아 있으면(`_combo_left > 0`) 대기 자세에서 다시 젖힌다.
	_windback_t = 0.0
	# 이미 그려진 부분 궤적은 지우지 말고 흩어지게 둔다(뚝 끊기면 화면이 튄다).
	# 🔴 **리본도 반드시 이 가드에 포함된다** — 페이드를 태울 유일한 자리라, 빠지면 취소된 스윙의
	#   자국이 `_fx_left = 0`인 채 **영원히 화면에 굳는다**(구르기로 스윙을 끊을 때마다 한 줄씩 쌓인다).
	# ⚠ 분모도 같이 세운다 — `_finalize_swing_sweep`을 안 지났으므로 `_fx_total`엔 **직전** 스윙 값이
	#   남아 있고, 그게 마무리였다면 취소 자국이 알파 0.67에서 시작해 흐릿하게 뜬다.
	if _swing_trail.visible and _fx_left <= 0.0:
		_fx_total = ATTACK_FX_TIME
		_fx_left = ATTACK_FX_TIME


# 스윕 완료 순간의 판정 — 🔴 **로컬만**(원격 아바타는 상태를 만들지 않는다, rules §1).
# 방향·기하는 전부 스윙 개시 때 고정된 `_swing_dir`과 CombatMath 단일 소스에서 온다.
func _resolve_swing_hit() -> void:
	var dir := _swing_dir
	# 판정: 고정된 스윙 방향 **부채꼴** 질의 (Area 노드 대신 즉시 질의)
	# 🔴 **부채꼴 반경 = 도달 거리 그 자체다**(무기 모션 축 2026-07-28). 전에는 "전방 오프셋 원"이
	#   곧 판정이라 등 뒤 적도 원에 걸리면 맞았다 — 창(좁은 각·긴 사거리)이 원리적으로 불가능했던 이유.
	#   물리 질의는 **apex 중심 원으로 넓게 훑고**(적 몸 shape 교차라 반경 여유가 자동), 각은
	#   `is_melee_in_cone`이 거른다 — 호스트 확정과 **같은 함수**다(여유 배율만 다르다).
	# ⚠ 좌표는 **지금(스윕 완료 시점)의 것**이다 — 선딜 동안 나도 적도 움직였으므로 클릭 시점 좌표를
	#   쓰면 화면과 어긋난다. 호스트가 보는 상대적 낡음은 그대로다(요청 송신 시점 기준이라 불변).
	# 🔴 **사거리도 콤보를 본다**(v2.3) — 마무리 타면 `EquipDef.combo_finish_range`로 길어진다.
	#   ⚠ 로컬은 **자기 주장 타수**(`_swing_is_finish`)를 쓰고 호스트는 **센 타수**를 쓰는데, 그래도
	#     거부 띠가 안 생긴다: 호스트 쪽에만 `HIT_REACH_SLACK`(×2.0)이 곱해지고
	#     `effective_attack_range`의 clamp가 `R_f ≤ R_b × 2.0`을 강제하므로 **로컬 ⊆ 호스트**가
	#     구조로 성립한다(증명은 그 함수 주석). 각 축이 `or`를 필요로 했던 것과 다른 이유다.
	var reach_dist := CombatMath.effective_attack_range(
		job, trait_value("reach"), _weapon_override, _swing_is_finish)
	# 🔴 **판정 각도 콤보를 본다**(v2.2) — 마무리 타면 `EquipDef.combo_finish_arc`로 넓어진다.
	#   ⚠ `_swing_is_finish`는 `_begin_swing`이 굳힌 값이라 **표시 각과 같은 판단**이다: 표시는 여기에
	#     `COMBO_FINISH_SHOW_MARGIN`을 더한 값이므로 「표시 ⊇ 판정」이 구조로 유지된다.
	#   🔴 **로컬이 호스트보다 엄격하면 안 된다**(§3) — 로컬 탈락은 `attack_hit` 미emit = G_HIT_REQ
	#     미송신이라 타격이 호스트 검증 **이전에** 사라진다. 호스트는 `min(주장, 자기 계수)`를 쓰므로
	#     확정 타수 ≤ 여기 주장 타수인데, 그것이 "호스트 각 ≤ 로컬 각"으로 넘어가려면
	#     **`combo_finish_arc ≥ swing_arc`** 가 필요하다(마무리를 더 좁게 적으면 부호가 뒤집힌다).
	#     데이터가 그것을 만족하는지는 `test_combat_math_auto`의 「★마무리 각 전수」가 전수로 지킨다.
	var half_arc := CombatMath.melee_half_angle(_weapon_override, _swing_is_finish)
	var facing := dir.angle()
	var center := global_position + CombatMath.attack_center_offset(dir, job, trait_value("reach"),
		_weapon_override)
	var shape := CircleShape2D.new()
	shape.radius = reach_dist
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = ENEMY_BODY_MASK
	params.collide_with_bodies = true
	# 🔴 상한 32 — 질의 원이 "전방 오프셋 원"(반경 range×0.5)에서 "apex 중심 원"(반경 range)으로
	#   **면적 4배 이상**(창이 오면 최대 34배) 커졌는데 상한이 8이면, `intersect_shape`가 순서를
	#   보장하지 않으므로 **각으로 걸러질 적**이 8칸을 먹고 정면의 적이 결과에서 밀려난다.
	#   그러면 `attack_hit`이 emit되지 않아 **G_HIT_REQ 자체가 안 나간다**(호스트 검증 이전에 소멸).
	#   좁은 부채꼴일수록 심하다. 순회 비용은 각 필터가 싸서 무시 가능 (netreview I-2, 2026-07-28).
	var hits := get_world_2d().direct_space_state.intersect_shape(params, 32)
	var connected := false
	for hit: Dictionary in hits:
		var body := hit.get("collider") as Node
		if body == null or not body.is_in_group("enemy"):
			continue
		# 적 몸 반경 — 호스트 확정이 쓰는 것과 같은 소스(EnemyDef.body_radius). 없으면 0(중심 판정).
		var body_def := body.get("def") as EnemyDef
		var body_radius := body_def.body_radius if body_def != null else 0.0
		if not CombatMath.is_melee_in_cone(global_position, (body as Node2D).global_position,
				facing, half_arc, reach_dist, body_radius):
			continue
		EventBus.attack_hit.emit(body, job, dir)
		connected = true
	if connected:
		# 공격자 로컬 예측 타격 손맛 — 무기별 셰이크/타격음(호스트 확정 전 즉발, 표시 전용). 스윙당 1회.
		EventBus.weapon_impact.emit(center, _hit_sfx, _hit_shake)
		# 때린 방향으로 밀림 — 셰이크(무작위)와 다른 축(방향이 읽힌다). 무게 배율은 셰이크와 **같은 소스**.
		EventBus.camera_kick.emit(dir, HIT_KICK * _weapon_weight())
		# 🔴 박힘은 **바로 지금**부터다 — 판정 시점 = 스윕 완료 = 칼이 살에 닿는 순간이라 예약이 필요
		#   없다(선딜 축 도입 전에는 판정이 클릭 프레임이라 한가운데를 따로 겨눠야 했다).
		#   모션 파라미터를 그 자리에 붙들 뿐 **창은 안 늘린다**(§3 미러 계약 보존).
		_swing_bite_t = clampf(_swing_windup_l + _swing_strike_l, 0.0, 1.0)
		# 🔴 후딜 창(실시간, haste 반영된 굳힌 값)에도 묶는다 — 근거는 SWING_BITE_RECOVER_MAX 주석.
		var recover_s := (1.0 - _swing_windup_l - _swing_strike_l) * _swing_win_total
		# ⚠ 타별 점증(`_combo_ramp`)은 **가장 안쪽 항에만** 곱한다 — 바깥 두 clamp
		#   (`SWING_BITE_MAX_S`·후딜 창)는 그대로라 J-3(박힘이 후딜을 먹어 복귀 모션이 스냅) 방어가 산다.
		_swing_bite_left = minf(minf(SWING_BITE_S * _weapon_weight()
				* lerpf(1.0, COMBO_FINISH_BITE_MULT, _combo_ramp), SWING_BITE_MAX_S),
			recover_s * SWING_BITE_RECOVER_MAX)
		# 호스트의 `last_confirm_msec` 로컬 미러 — 그쪽도 **확정 때만** 앵커를 옮기므로
		# (헛치면 안 옮긴다) 여기도 `connected`일 때만 갱신한다. 자기 스로틀의 기준점이다.
		_last_swing_hit_msec = Time.get_ticks_msec()


# ============================================================================
# 하위 직업 스킬 (Q) — 2026-08-02. 메인 자리 하위 직업 하나당 하나(GDD §3 조작 · §11 TBD의 첫 입주)
# ============================================================================
# 🔴 **네트워크로 나가는 것은 방향 두 칸뿐이다**(`G_SKILL {dx, dy}`) — 배율·반경·사거리·쿨다운은
#   호스트가 그 피어의 공지 하위 직업 id로 **자기 data/skills**에서 리졸브한다(`SkillDef` 헤더 ·
#   `peer_weapon_id`·`projectile_params`와 같은 철학, rules §3). 수치를 실으면 그게 곧 스푸핑 표면이다.
# 🔴 **결과 메시지도 새로 안 만든다** — 데미지는 기존 `G_ENEMY_HP`로 흐른다(넉백이 `G_MOB_POS`에
#   얹힌 것과 같은 형태).


# 내 스킬 — 🔴 리졸브는 `GameState.active_skill()` **하나**다(= `main_slot_def` 게이트: 계열 일치 ·
#   공유 하위 직업 배제). 사본 조건문을 만들면 "특성·색은 폐기됐는데 스킬만 켜진" 조합이 열린다.
#   null = 스킬 없는 하위 직업(검사)·미장착 = 도입 전과 완전 항등. **HUD 슬롯도 이 함수를 읽는다.**
func active_skill_def() -> SkillDef:
	return GameState.active_skill() if is_local else null


# 스킬 쿨 남은 비율 0.0~1.0 (1 = 방금 썼다, 0 = 지금 쓸 수 있다). **HUD 표시 전용 읽기 접근자.**
# 🔴 분모는 `clamp_skill_cooldown`을 지난 값이다 — 데이터가 하한(`SKILL_COOLDOWN_MIN`)에 걸리면
#   호스트는 잘린 값으로 재는데 바만 원본으로 그리면 "바는 안 찼는데 쓸 수 있다"가 된다(§3).
func skill_cooldown_ratio() -> float:
	var left := skill_cooldown_left()
	if left <= 0.0:
		return 0.0
	var sk := active_skill_def()
	if sk == null:
		return 0.0
	var total := CombatMath.clamp_skill_cooldown(sk.cooldown_s)
	return 0.0 if total <= 0.0 else clampf(left / total, 0.0, 1.0)


# 남은 쿨(초) — HUD 숫자 표기용. 🔴 **아래 `_try_cast_skill`과 같은 문턱에서 0이 되어야 한다**
#   = `skill_cast_gap_s`(클라 게이트). 안 맞추면 "0초인데 안 나간다"(또는 그 반대)가 되고,
#   표시와 발동이 갈라진 이유가 화면에 안 드러난다.
# ⚠ **호스트 게이트(`is_skill_ready`)를 여기 쓰지 마라** — 그러면 게이지가 호스트 문턱에서 0을
#   찍어 플레이어를 **여유 0인 경계로 유도한다**(그것이 netreview C-1의 증폭기였다).
func skill_cooldown_left() -> float:
	var sk := active_skill_def()
	if sk == null:
		return 0.0
	var gate_s := CombatMath.skill_cast_gap_s(sk.cooldown_s)
	var since := float(Time.get_ticks_msec() - _last_skill_msec) / 1000.0
	return maxf(0.0, gate_s - since)


# Q 입력 — 🔴 **게이트를 새로 발명하지 않는다.** 평타(`_local_combat`)가 보는 조건을 그대로 따라간다:
#   ⑴ 모달 = `_unhandled_input`(UI가 소비한 입력은 안 온다) ⑵ 사망 ⑶ 구르기 중 ⑷ 무장 해제
#   ⑸ 앉는 중(`seated` — 홀드 연사가 이미 같은 가드를 갖는다, GDD §5 "앉는 동안 무방비").
# ⚠ ⑷ 무장 가드는 **호스트보다 엄격하지 않다** — 여기서 탈락하면 `G_SKILL` 자체가 안 나가므로
#   "호스트 검증 이전에 타격이 사라지는" 그 결함(§3 「로컬 ≤ 호스트」)이 성립할 대상이 없다.
#   그 계약이 겨누는 것은 **이미 발동한 공격의 대상 선별**이고, 여기는 발동 여부 자체다.
func _try_cast_skill() -> void:
	if not _alive or seated or bound or _roll_time_left > 0.0 or not _is_armed():
		return
	# 🔴 **시전 중 판별은 `_skill_pending`이 진다 — `_skill_windup_left > 0.0`이 아니다.**
	#   선딜 0(즉발) 스킬이 들어오면 잔여가 처음부터 0이라 그 조건이 **한 프레임도 참이 아니고**,
	#   그러면 같은 프레임에 Q를 두 번 받는 입력(연타·키 리피트 아닌 중복 이벤트)이 이중 발동한다.
	if _skill_pending != null:
		return  # 시전 중 재입력 = 무시. 쿨다운 앵커는 아직 안 섰다(취소해도 손해가 없는 이유).
	var sk := active_skill_def()
	if sk == null:
		return  # 스킬 없는 하위 직업 = 도입 전과 완전 항등
	# 🔴 **클라는 호스트 게이트(`is_skill_ready`)가 아니라 `skill_cast_gap_s`로 스스로 물러선다**
	#   (netreview C-1 2026-08-02 — 그 함수 주석이 유도 전문). 같은 문턱을 쓰면 여유가 정확히 0이라
	#   호스트 **수신 프레임 양자화**(±33ms)만으로 거부되고, 거부돼도 아래에서 앵커가 서기 때문에
	#   **쿨다운 8~9초를 통째로 잃는다.** 두 값은 같은 `clamp_skill_cooldown`을 지나 갈라지지 않는다.
	# ⚠ 부호가 반대인 게이트다 — 스로틀은 `+`(늦는 쪽이 안전: 반대면 정직한 발동이 삭제된다).
	#   rules §3 「관통 규칙: 오차는 누가 대가를 치르는가로 기울인다」의 다섯 번째 사례.
	if Time.get_ticks_msec() - _last_skill_msec < int(CombatMath.skill_cast_gap_s(sk.cooldown_s) * 1000.0):
		return
	_skill_pending = sk
	_skill_dir = _aim_dir()          # 🔴 여기서 **한 번** 고정 (멤버 주석이 근거 — beam은 축이 곧 판정)
	_skill_windup_left = maxf(sk.windup_s, 0.0)
	# 시전 시작 신호 — 새 에셋 0. 무기 스윙음을 낮은 피치로 재활용해 "기를 모은다"로 들리게 한다
	# (rules §2 손맛 계층: 새 훅을 파지 말고 있는 훅에 매단다. `player_swing` 소비자는 Audio뿐이다).
	EventBus.player_swing.emit(global_position, _swing_sfx, SKILL_WINDUP_PITCH)
	# 🔴🔴 **여기서 `_fire_skill()`을 부르지 마라 — 선딜 0이어도.** 이 함수는 `_unhandled_input`
	#   (입력 단계)에서 오는데, 발동은 `direct_space_state` 물리 질의(`_skill_feel`)를 한다.
	#   물리 질의는 `_physics_process` 밖에서 부르면 프레임에 따라 조용히 낡은 스냅샷을 읽거나
	#   경고를 뱉는다 — 근접 판정(`_resolve_swing_hit`)이 물리 프레임 안에서만 도는 것과 같은 이유다.
	#   선딜 0이면 다음 `_tick_skill`(같은 프레임의 `_physics_process`)이 즉시 발동한다 = 최대 1프레임.


# 선딜 진행 — 🔴 **0 이하로 떨어지는 그 프레임에 발동**한다. 판정(호스트)·FX·`G_SKILL`이 전부
#   `_fire_skill` 한 곳에서 같은 순간에 나가므로 「맞는 순간 = 보이는 순간」이 구조로 성립한다
#   (근접이 「선딜+스윕 끝 = 판정」으로 만든 그 정렬의 미러, §3).
# 🔴 **발동의 유일한 자리다** — `_physics_process` 안이라 물리 질의가 항상 물리 프레임에서 돈다.
#   선딜 0(즉발)도 여기를 지난다: `0 - delta < 0`이라 첫 틱에 바로 나간다.
func _tick_skill(delta: float) -> void:
	if _skill_pending == null:
		return
	_skill_windup_left -= delta
	if _skill_windup_left <= 0.0:
		_skill_windup_left = 0.0
		_fire_skill()


# 시전 취소 — 구르기·사망. 🔴 **신뢰 경계 변화 0**: 아직 `G_SKILL`을 안 보냈고 쿨다운 앵커도 안 섰다
#   (= 호스트로 나간 것이 0). `_cancel_swing`과 **같은 근거**이고, 그쪽이 "법사는 차지를 빼는데
#   전사는 못 뺀다"를 피하려 만든 관용구를 여기서도 지킨다.
# ⚠ 쿨다운을 소비하지 않으므로 취소가 손해가 아니다 = 남용 유인도 없다(취소해도 얻는 것이 없다).
func _cancel_skill() -> void:
	_skill_windup_left = 0.0
	_skill_pending = null


# 🔴 **발동 = 이 한 곳.** 여기서 나가는 셋(호스트 자기 판정 · 원격 통지 · 화면 FX)이 같은 프레임의
#   같은 좌표·같은 방향·같은 `SkillDef`에서 파생한다 — 흩으면 "보이는 곳 ≠ 맞는 곳"이 열린다(§3).
func _fire_skill() -> void:
	var sk := _skill_pending
	_skill_pending = null
	if sk == null or not _alive:
		return
	var dir := _skill_dir
	if not dir.is_finite() or dir.length_squared() <= 0.000001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	# 🔴 쿨다운 앵커 = **보내는 시각**(멤버 주석이 근거 — 호스트는 자기 수신 시각으로 잰다).
	_last_skill_msec = Time.get_ticks_msec()
	# ⑴ 원격 통지 — 수치는 한 칸도 안 싣는다(NetSchema.G_SKILL 주석이 계약 전문).
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SKILL, "dx": dir.x, "dy": dir.y})
	# ⑵ 호스트 자기 판정 입구 — 🔴 Net 루프백이 없어 **이 시그널이 유일한 경로**다(멤버 주석).
	#   게스트에서도 emit되지만 `CombatAuthority`가 `is_host()` 가드로 무시한다(권한은 호스트만, §1).
	skill_cast.emit(dir)
	# ⑶ 화면 — 로컬·원격이 **같은 함수**를 지난다(아래). 기하는 SkillDef 그대로다.
	play_skill_fx(dir, sk)
	# ⑷ 로컬 예측 손맛 — 🔴 **표시 전용 질의다. 여기서 `attack_hit`을 emit하지 마라.**
	#   그 시그널은 근접 확정 경로(`_confirm_damage`)로 들어가 ⓐ 스킬 배율이 아니라 **콤보 배율**로
	#   확정되고 ⓑ 근접 쿨다운 게이트(`is_hit_cooldown_ok`)를 먹어 방금 휘두른 평타 때문에 스킬이
	#   조용히 거부되며 ⓒ 호스트에서 **이중 확정**이 된다(이미 skill_cast로 확정했다).
	#   ⚠ 그래서 이 질의는 **어떤 타격도 만들거나 지우지 않는다** — 로컬이 놓쳐도 호스트 판정은 그대로다
	#     (근접의 로컬 질의가 `G_HIT_REQ`를 게이트하던 것과 **다르다**. 그쪽이 「로컬 ≤ 호스트」를
	#     요구한 이유가 여기엔 아예 없다).
	_skill_feel(dir, sk)


# 발동 순간의 로컬 타격 손맛 — 🔴 **표시 전용**(위 ⑷ 주석이 근거). 판정 기하는 호스트와 **같은
#   `CombatMath.is_skill_hit`**을 지나므로, 화면 FX·이 손맛·호스트 확정 셋이 한 함수에서 나온다.
# ⚠ `slack_px`를 넘기지 않는다(0) — 슬랙은 **호스트가 게스트의 낡은 몹 좌표를 보상하는** 값이라
#   자기 화면 손맛에 쓰면 "안 맞았는데 소리가 난다"가 된다(관대한 방향이 여기선 거짓 신호다).
func _skill_feel(dir: Vector2, sk: SkillDef) -> void:
	var origin := global_position
	var half_len := 0.0
	if sk.is_beam():
		half_len = CombatMath.clamp_skill_length(sk.length) * 0.5
	var probe_r := half_len + CombatMath.clamp_skill_radius(sk.radius)
	if probe_r <= 0.0:
		return
	# 🔴 **다단은 한 타의 몫만 흔든다 — 그 몫은 「그 타의 데미지 비중」에서 유도한다**(2026-08-02).
	#   `damage_mult`가 **타당** 배율이고 총합 = `배율 × 타수`이므로(SkillDef 헤더) 한 타의 비중은
	#   정확히 `1 / 타수`다 = 새 손맛 상수를 만들지 않고 데이터에서 나온다.
	# 🔴 나누지 않으면 실제로 깨진다 — `camera_rig.add_shake`/`add_kick`이 **가산**이라(각각
	#   `SHAKE_MAX`·`KICK_MAX`로 포화) 5타 × 1.8배는 0.4초 만에 상한을 치고 화면이 통째로 뭉갠다.
	# ⚠ **소리는 안 나눈다** — `weapon_impact`가 sfx 이름을 따로 싣고 볼륨 인자가 없어서, 5타가
	#   그대로 "다다다닥" 다섯 번 난다. 다단을 귀로 읽게 하는 것이 바로 그 축이다.
	# ⚠ 단발(1타)이면 나눗셈이 1이라 **완전 항등**이다.
	var share := 1.0 / float(CombatMath.clamp_skill_hit_count(sk.hit_count))
	var shape := CircleShape2D.new()
	shape.radius = probe_r
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, origin + dir * half_len)  # 캡슐을 감싸는 원(spin은 half_len = 0)
	params.collision_mask = ENEMY_BODY_MASK
	params.collide_with_bodies = true
	# 상한 32 — 근접 질의와 같은 값(광역이라 원이 더 크다. 각 필터 대신 is_skill_hit이 거른다).
	var hits := get_world_2d().direct_space_state.intersect_shape(params, 32)
	for hit: Dictionary in hits:
		var body := hit.get("collider") as Node
		if body == null or not body.is_in_group("enemy"):
			continue
		var bdef := body.get("def") as EnemyDef
		if not CombatMath.is_skill_hit(sk.shape, (body as Node2D).global_position, origin, dir,
				sk.radius, sk.length, bdef.body_radius if bdef != null else 0.0):
			continue
		EventBus.weapon_impact.emit(origin, _hit_sfx, _hit_shake * SKILL_SHAKE_MULT * share)
		EventBus.camera_kick.emit(dir, HIT_KICK * _weapon_weight() * SKILL_KICK_MULT * share)
		return  # 발동 1회당 손맛 1회 (근접 스윙의 `connected` 규약과 같다 — 마릿수만큼 흔들지 않는다)


# 스킬 FX — 🔴 **로컬·원격 공용 단일 지점.** 원격은 `peer_sync`가 `G_SKILL` 수신 시 그 피어의
#   공지 하위 직업으로 리졸브한 `SkillDef`를 실어 부른다(수치는 여전히 무전송, `peer_main_fx` 미러).
# 🔴 **크기는 `SkillDef` 그대로**다 — 연출 배율이 없다(§3 "맞는 곳 = 보이는 곳"). 색만
#   `_fx_color`를 지나 하위 직업 틴트(검성 하늘 / 광전사 붉음)를 공짜로 받는다.
# ⚠ 스킬이 null(미공지·계열 불일치·스킬 없음)이면 **아무것도 안 그린다** — 호스트도 그 경우 판정을
#   안 하므로(`main_skill_of` 같은 게이트) 표시와 판정이 함께 없어진다 = 갈라지지 않는다.
# 🔴🔴 **이 아바타의 「스킬 판정 원점」 — 호스트가 판정에 쓰는 그 점을 각 클라가 다시 유도한다**
#   (netreview I-2 2026-08-02). FX를 `global_position`에서 띄우면 **판정과 표시가 다른 점에서 태어나**
#   이동형 검기가 비행 내내(1.73초·520px) 그 오차를 평행 이동시킨다 — 관찰자 화면에서는
#   `lead 전액 + lerp 지연`이라 지연 스파이크에서 **115px**(반경 46 원반 두 개 반)까지 벌어져
#   "원반이 몹을 관통하는데 그 몹은 안 죽고 옆에 것이 죽는" 그림이 된다(에러 0).
# ⚠ **로컬 아바타에서는 완전 항등이다** — `net_anchor_lead`가 `global_position`을 돌려준다.
#   그래서 이 함수는 호스트 화면을 한 픽셀도 안 바꾸고, 그것이 이 결함이 안 보였던 이유이기도 하다.
# ⚠ 화살(`G_SHOOT`)은 원점을 **메시지에 실어** 같은 문제를 푼다(`is_shot_origin_ok` 44px 검증).
#   스킬은 원점을 안 실어 스푸핑 표면을 안 여는 대신, 각 클라가 **같은 함수로 다시 유도**한다.
# 🔴 **매번 다시 판다** — 멤버에 얼려 두면 다단 반복 타가 발동 시각 좌표에 못 박히는데,
#   호스트는 타마다 `net_anchor`를 다시 읽으므로 그 순간 두 축이 갈라진다.
func skill_origin() -> Vector2:
	return net_anchor_lead(Net.one_way_ms(peer_id))


func play_skill_fx(dir: Vector2, sk: SkillDef) -> void:
	if sk == null or not _alive:
		return
	var d := dir
	if not d.is_finite() or d.length_squared() <= 0.000001:
		d = Vector2.RIGHT
	d = d.normalized()
	_skill_fx_index = 0                        # 🔴 반달 좌우 교대의 기준점 — **스폰보다 먼저** 되돌린다
	_spawn_skill_fx(d, sk)                     # ①타 — 발동 프레임에 즉시(호스트 `_resolve_skill` 미러)
	# 🔴 **이동형은 반복이 없다** — 한 장이 날아가며 스스로 판정한다(`SkillDef.travel_speed` 계약:
	#   `hit_count`·`hit_interval_s`는 이동형에서 무시된다). 호스트 `_resolve_skill`이 같은 자리에서
	#   같은 판단을 하므로 화면 장수와 판정 모델이 갈라지지 않는다.
	if sk.is_travel():
		_skill_fx_def = null
		_skill_fx_left = 0
		return
	# 🔴 남은 타 예약 — **타수·간격은 이 클라가 자기 `SkillDef`에서 읽는다**(네트워크 0).
	#   단발이면 `left = 0` + `def = null`이라 이 축 도입 전과 **완전 항등**이고, 동시에 진행 중이던
	#   반복이 새 시전으로 **대체**된다(호스트 `_skill_ticks`가 캐스터당 한 칸인 것과 같은 규약).
	var hits := CombatMath.clamp_skill_hit_count(sk.hit_count)
	_skill_fx_def = sk if hits > 1 else null
	_skill_fx_dir = d
	_skill_fx_left = hits - 1
	_skill_fx_timer = CombatMath.clamp_skill_hit_interval(sk.hit_interval_s)


# 다단 표시 진행 — 🔴 **호스트 `_step_skill_ticks`와 같은 따라잡기 규칙**(`while` + 간격 가산)이라
#   프레임이 튀어도 화면 타수와 판정 타수가 갈라지지 않는다.
# 🔴 사망에서 끊는다 — 호스트도 틱마다 `is_alive()`를 보고 끊으므로 **같은 조건**이다.
#   ⚠ 구르기로는 안 끊는다(호스트도 안 끊는다) — 여기서만 끊으면 "안 보이는데 맞는다"가 된다.
func _tick_skill_fx(delta: float) -> void:
	if _skill_fx_def == null or _skill_fx_left <= 0:
		return
	if not _alive:
		_skill_fx_def = null
		_skill_fx_left = 0
		return
	var gap := CombatMath.clamp_skill_hit_interval(_skill_fx_def.hit_interval_s)
	_skill_fx_timer -= delta
	while _skill_fx_timer <= 0.0 and _skill_fx_left > 0:
		_spawn_skill_fx(_skill_fx_dir, _skill_fx_def)
		# 🔴 손맛은 **로컬 아바타에서만** — 원격 아바타가 emit하면 남의 스킬이 내 화면을 흔든다
		#   (단발 시절 `_fire_skill`이 로컬에서만 `_skill_feel`을 부르던 것과 같은 경계).
		if is_local:
			_skill_feel(_skill_fx_dir, _skill_fx_def)
		_skill_fx_left -= 1
		_skill_fx_timer += gap
	if _skill_fx_left <= 0:
		_skill_fx_def = null


# 한 타의 FX 한 장 — 🔴 **좌표를 여기서 읽는다**(`global_position`). 타마다 다시 읽으므로 시전자가
#   걸으면 FX도 따라 나가고, 호스트가 타마다 `net_anchor()`를 다시 읽는 것과 **같은 규칙**이다.
#   ⚠ 태어난 뒤에는 그 자리에 못 박힌다(씬 루트 자식 = 시전자를 안 따라간다, `skill_fx.gd` 헤더).
#     이동형만 예외이고, 그때는 **판정도 같이 나아간다**(그 파일 헤더가 이유의 정본).
# 🔴 **형태는 데이터가 고른다 — 새 필드 0개.** 갈래 셋이 전부 `SkillDef`에서 읽히므로 "이 스킬은
#   무슨 그림인가"가 `.tres` 한 장에 닫힌다:
#     ⑴ 이동형(`travel_speed > 0`) = **날아가는 검기**(`skill_fx` + travel — spin이면 회전 원반)
#     ⑵ 제자리 beam(앞을 벤다)    = **반달 연타**(`slash_fx` — 아래 `_spawn_skill_slash`)
#     ⑶ 그 밖(제자리 spin)        = 회전 광역 원(`skill_fx` — 도입 시점 그대로)
# 🔴🔴 **분기 순서가 계약이다 — 이동형이 형태보다 먼저다.** 뒤집으면 「beam + 이동형」 스킬에서
#   판정은 날아가는데(호스트 `_resolve_skill`도 이동형을 먼저 본다) 화면만 제자리 반달이 되어
#   **"검기가 저기 있는데 여기서 맞는다"** 가 된다. 지금 데이터에 그런 조합이 없다는 것은 근거가
#   못 된다 — `.tres` 두 칸이면 만들어지고, 그때 에러가 안 난다.
func _spawn_skill_fx(dir: Vector2, sk: SkillDef) -> void:
	var parent := get_parent()
	if parent == null:
		return
	if sk.is_beam() and not sk.is_travel():
		_spawn_skill_slash(dir, sk, parent)
		_skill_fx_index += 1
		return
	var fx := SkillFx.new()
	parent.add_child(fx)  # 씬 루트 자식 = 시전자를 따라가지 않는다(그 타의 좌표에 못 박힌다)
	# 🔴 수명의 출처가 갈래마다 다르되 **둘 다 단일 소스 함수**다 — 사본을 만들지 마라:
	#   이동형 = `skill_travel_lifetime_s`(호스트 판정 수명과 **같은 함수**) · 제자리 = 타 간격 유도.
	var life := CombatMath.skill_travel_lifetime_s(sk.travel_speed, sk.travel_dist) if sk.is_travel() \
		else SkillFx.multi_life_s(sk.hit_count, sk.hit_interval_s)
	# 🔴 기하(반경·길이)·속도는 `SkillDef` 그대로다 — 연출 배율 0개(§3 "맞는 곳 = 보이는 곳").
	# 🔴 원점 = `skill_origin()`(= 호스트 판정 원점 `net_anchor_lead`) — `global_position`이 아니다.
	#   로컬 아바타에서는 두 값이 같고, 원격 아바타에서만 갈린다(그 함수 주석이 근거).
	fx.setup(sk.shape, skill_origin(), dir.angle(), _fx_color(1.0), sk.radius, sk.length,
		life, sk.travel_speed)
	_skill_fx_index += 1


# 🔴 **beam 스킬의 한 타 = 반달 한 장** (2026-08-02 사용자 확정: *"환영검무도 검을 와다다다 하는
#   느낌이지 저런게 아님"*). 전에는 판정 캡슐을 그대로 그린 **띠**가 다섯 번 떴는데, 띠는 "여기가
#   범위다"라는 **예고의 언어**라 「검을 매우 빠르게 여러 번 휘두른다」로 안 읽혔다.
#
# 🔴🔴 **덮임 유도 — 여기가 §3 「표시 ⊇ 판정」을 지키는 자리다.**
#   판정 = 시전자에서 `dir`로 뻗은 **캡슐**(축 길이 `length` · 반폭 `radius`)이라 전방 도달이
#   `length + radius`(환영검무 = 95 + 42 = **137px**)다. 그래서
#     ⑴ **반달의 바깥 끝을 정확히 그 137px에 맞춘다** — `SlashFx.mid_r_for_outer`가 두께 유도의
#        역함수라 `mid_r`을 손으로 정하지 않는다(정하는 순간 `.tres`의 `length`를 조여도 그림이
#        안 따라오는 제2의 진실원이 된다).
#     ⑵ **안쪽 변이 캡슐의 시작단 반구까지 내려온다** — 두께 배율(5.6)이 `SlashFx`의 호 길이 상한에
#        포화해 `안쪽/바깥 = (1−x)/(1+x)`, `x = 1.0875/2`가 되므로 안쪽 변 = **40.5px** < `radius`(42).
#        즉 반달의 반경 구간 [40.5, 137]이 판정 캡슐의 반경 구간 [0, 137] **중 42px 밖 전부**를 덮는다
#        (42px 안쪽은 전 방향이 판정이라 아래 ⓐ).
#     ⑶ **반각이 캡슐의 옆폭을 덮는다** — 반경 r(> 42)에서 캡슐의 각 반폭은 `asin(radius / r)`이고
#        r이 작을수록 크다: r=48에서 61.0° · r=60에서 44.4° · r=137에서 17.8°.
#        한 장이 덮는 각은 `1.45 − 0.34` = 1.11rad = **63.6°**(기울인 반대쪽은 102.6°)이므로
#        r ≥ 48에서는 **한 장으로 충분**하다. 남는 것은 r ∈ [42, 48]의 한쪽 옆구리 5px 띠뿐이고,
#        기울기가 **타마다 좌우로 뒤집히므로** 그 띠는 다음 타가 덮는다.
#   ⚠ **덮이지 않고 남는 것 둘 — 리드 판단 대상으로 보고했다:**
#     ⓐ 시전자 반경 40.5px 이내 = **리본 선례로 허용된 공동**(칼이 몸을 지나가는 것으로 읽힌다,
#        `TRAIL_*` 상수 주석). 캡슐은 그 안을 **전 방향** 판정하므로 옛 띠 FX는 그렸다 = 이 축만
#        표시가 줄었다. ⓑ 위 5px 띠의 한쪽(한 타 기준). 둘 다 전방 호로는 원리적으로 못 덮는다.
func _spawn_skill_slash(dir: Vector2, sk: SkillDef, parent: Node) -> void:
	# 🔴 도달의 출처 = **판정 캡슐 그 자체**(clamp도 호스트와 같은 함수를 지난다).
	var reach := CombatMath.clamp_skill_length(sk.length) + CombatMath.clamp_skill_radius(sk.radius)
	if reach <= 0.0:
		return
	var w := _weapon_weight()
	var ha := SKILL_SLASH_HALF_ANGLE
	# 🔴 타마다 좌우 교대 — 이 한 줄이 "와다다다"의 정체다(같은 각이면 한 장이 다섯 번 깜빡인다).
	var side := 1.0 if (_skill_fx_index % 2) == 0 else -1.0
	var angle := dir.angle() + side * SKILL_SLASH_TILT
	var sfx := SlashFx.new()
	parent.add_child(sfx)
	sfx.global_position = skill_origin()  # 호의 곡률 중심 = 판정 캡슐 원점과 **같은 점**(I-2)
	sfx.setup(angle, _fx_color(1.0),
		SlashFx.mid_r_for_outer(reach, ha, w, SKILL_SLASH_THICK_SCALE),
		ha, w, SKILL_SLASH_THICK_SCALE,
		SlashFx.multi_life_s(sk.hit_count, sk.hit_interval_s), SKILL_SLASH_SPEED)
	# 칼 잔상 — 데이터 설명(*"잔상이 남을 만큼 빠르게"*)을 화면에 실제로 만드는 겹.
	# 🔴 장수 상한은 **평타 궤적과 같은 governance**를 지난다(`_subjob_fx_ghost`는 이미
	#   `CombatMath.fx_ghost_mult`로 clamp된 값이다 — 드로우콜 = 웹 프레임 비용, rules §5).
	# ⚠ 무장 해제·원격 미공지면 `spawn_weapon`이 스스로 조용히 빠진다(texture null 가드).
	var ghosts := maxi(1, int(round(float(SKILL_SLASH_GHOSTS) * _subjob_fx_ghost)))
	for i: int in range(ghosts):
		var t := 0.0 if ghosts <= 1 else (float(i) / float(ghosts - 1)) * 2.0 - 1.0
		AfterImage.spawn_weapon(_weapon, _weapon_pivot, self,
			angle + t * ha * SKILL_SLASH_GHOST_SPAN, _fx_color(1.0))


# 원거리 발사(shoot = 활 · charge = 지팡이) — 표시 투사체 스폰(로컬)·G_SHOOT 송신(원격 표시)·(호스트) 권한 투사체 등록.
# 명중·폭발 판정과 데미지는 호스트 CombatAuthority가 투사체를 추적해 확정한다 (근접의 로컬 원형 질의 대신). 여기선 판정 없음.
# charge = 차지 레벨(0~3, 비차지 무기는 0) — 호스트가 clamp + 차지 시간 재검증(§3 신뢰 경계).
func _fire_projectile(dir: Vector2, charge: int) -> void:
	var origin := global_position + dir * MUZZLE_OFFSET
	_shot_seq += 1
	var aid := str(Net.my_id) + ":" + str(_shot_seq)
	_recoil_left = RECOIL_TIME  # 활 반동/지팡이 반동 연출
	# 발사는 **쏜 반대쪽**으로 카메라를 민다(근접 타격과 반대 부호) — 밀려나는 반동이 읽히게.
	# 차지 무기는 모은 단계만큼 더 세게(0단계도 최소 1배는 나가게 +1).
	# 마무리 타는 더 묵직하게 — 배율을 새 상수로 만들지 않고 **그 타의 데미지 배율을 그대로** 반동에
	# 쓴다(연출과 위력이 한 데이터에서 온다. 3타를 2.5배로 조이면 반동도 같이 따라온다).
	var combo_kick := CombatMath.combo_damage_mult_at(_weapon_override, _shot_combo_index)
	EventBus.camera_kick.emit(-dir, SHOOT_KICK * combo_kick
		* (1.0 + 0.45 * float(clampi(charge, 0, CombatMath.MAX_CHARGE_LEVEL))))
	# player_shoot: ArrowField가 표시 투사체 스폰 + (호스트 자신이면) CombatAuthority가 권한 투사체 등록
	EventBus.player_shoot.emit(Net.my_id, origin, dir, aid, _arrow_range, _weapon_id, charge,
		_shot_combo_index)
	EventBus.player_swing.emit(global_position, _swing_sfx, 1.0)  # 발사 SFX (swing_sfx 재활용 = 시위·발사음)
	# "cb" = 콤보 타수. 🔴 G_ATK의 "cb"와 달리 **판정에 영향을 주는 값**이라 호스트가 그대로 믿지 않는다 —
	#   자기 수신 간격으로 직접 세고 이 주장은 상한으로만 쓴다(CombatMath.authoritative_combo, §3).
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SHOOT, "ox": origin.x, "oy": origin.y,
		"dx": dir.x, "dy": dir.y, "aid": aid, "r": _arrow_range,
		"w": _weapon_id, "c": charge, "cb": _shot_combo_index})


func _aim_dir() -> Vector2:
	var d := get_global_mouse_position() - global_position
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


# 궤적 무장 — 실제 표시는 `_tick_swing_motion`이 **스윕 구간에 들어선 뒤** 매 프레임 그린다.
# ⚠ 로컬·원격 공용이라 그 피어의 무기 구간 비율이 그대로 쓰인다(`_swing_time`에 haste도 이미 반영)
#   → 두 화면의 선딜·스윕 타이밍이 자동으로 같다.
# ⚠ 방향 인자를 받지 않는다 — 이 스윙의 방향은 `_swing_dir` **하나**다(m-A). 호출부는 둘 다
#   바로 앞에서 `_swing_dir`을 세팅한다(`_swing_attack` · `play_attack_fx`).
func _arm_swing_trail() -> void:
	_swing_fx_armed = true
	_swing_onset_pending = true
	_fx_left = 0.0
	# 🔴 이전 스윙의 점을 반드시 비운다 — 안 비우면 두 스윙의 자국이 **한 덩어리로 이어져** 칼이 지나간
	#   적 없는 면이 화면을 가로지른다(콤보 2·3타에서 방향이 뒤집히므로 특히 눈에 띈다).
	_trail_clear()
	_trail_last_u = -1.0
	_ghost_next_u = 0.0


# 궤적 한 프레임 — 🔴 **선단각은 무기 각(`_motion_off`) 그 자체다.** 사본을 만들면 "칼이 지나간 각 ≠
#   그려진 궤적"이 되고, 그게 사용자가 신고한 "이펙트가 무기 궤에 안 맞는다"의 정체였다(도입 전에는
#   부채꼴 **전체**를 한 번에 번쩍이고 칼이 그 안을 천천히 지나갔다 — 시간 축이 아예 없었다).
# u = 이징된 타격 진행(호출부가 무기 각과 **공유**하는 값). 찌르기만 이걸 도달 비율로도 쓴다.
#
# 🔴🔴 **선단은 "지나온 최대각"으로 래치한다 — 무기 각의 사본이 아니다** (netreview M-2, 2026-07-28).
#   `p >= 1`인 프레임에는 `_motion_at`이 이미 **복귀 분기**를 타 무기 각이 `_swing_to`에서 물러나
#   있다. 그 값을 그대로 선단으로 쓰면 그 그림이 페이드 0.18s 내내 굳어, **맞는데 안 그려지는
#   구역**이 생긴다 — 실측 최대 약 19°(iron 12.8° · haste 최악 18.6°). 콘 텔레그래프·스워시
#   텍스처와 **같은 결함 클래스**이고, 위 불변식을 거짓으로 만든다.
#   궤적은 "벤 자국"이라 **칼이 회수될 때 같이 물러나면 안 된다.**
#   ⚠ 이 한 줄이 m-4(적중 시 무기와 궤적이 최대 ~17° 벌어지던 것 — 박힘 때문에 하필 가장 잘 보이는
#     순간)도 같이 없앤다: 박힘은 `t`를 `선딜+스윕`에 붙들어 무기를 `_swing_to`에 두는데, 궤적도
#     이제 같은 각에 있다.
func _draw_swing_trail(u: float) -> void:
	# 🔴 **칼밑·칼끝 좌표를 그대로 이어 붙인다 — 이 두 줄이 "포개짐"의 전부다.** 각·반지름·회전중심을
	#   따로 계산하지 않으므로 어긋날 축이 존재하지 않는다(부채꼴 셰이더가 3°/2.8px씩 어긋나던 자리).
	# ⚠ 프레임당 한 점만 찍으면 각진다 — 60fps에서 스윕이 5~7프레임뿐이다(worn 0.084s). 그래서 직전
	#   진행값과의 사이를 `TRAIL_SUBSTEPS`로 나눠 채운다. 첫 프레임은 이을 상대가 없어 한 쌍만 찍는다.
	if _trail_last_u < 0.0:
		_trail_push(u)
	else:
		for i: int in range(1, TRAIL_SUBSTEPS + 1):
			_trail_push(lerpf(_trail_last_u, u, float(i) / float(TRAIL_SUBSTEPS)))
	_trail_last_u = u
	_rebuild_trail_ribbon()
	_swing_trail.modulate = _fx_color(1.0)
	# 칼 잔상 — 리본이 칼날이 **쓸고 간 띠**라면 이쪽은 칼 **한 장 한 장**이다. 같은 `_swing_angle_at`을
	# 쓰므로 리본·실물 칼과 셋 다 같은 호 위에 놓인다.
	# ⚠ 리본이 선(7px) → 면(칼날 폭)이 되면서 셋이 겹치는 면적이 커졌다 — 잔상 알파를
	#   `AfterImage.WEAPON_ALPHA`에서 함께 낮췄다(2026-08-01). 탁하면 그 값과 `GHOST_STEPS`를 조인다.
	# ⚠ `while`인 것은 한 프레임에 여러 칸을 건너뛸 수 있기 때문이다(저프레임·짧은 스윕).
	# ⚠ 마무리 타만 장수를 늘린다 — 각·반경은 그대로이고 **같은 호를 더 촘촘히** 채울 뿐이라
	#   §3(표시 ⊇ 판정)에 손대지 않는다(잔상은 판정을 만들지 않는다).
	# 🔴 메인 하위 직업 배율(`_subjob_fx_ghost`)도 **같은 성질이라 여기 곱해도 안전하다** — 늘어나는
	#   것은 밀도뿐이고 호의 각·반경은 `_swing_angle_at` 하나가 정한다. 광전사가 "몰아친다"로 읽히는
	#   것은 이 밀도이고, 상한은 CombatMath.MAX_FX_GHOST_MULT가 잡는다(드로우콜 = 웹 프레임 비용).
	var ghosts := maxi(1, int(round(
		lerpf(float(GHOST_STEPS), float(COMBO_FINISH_GHOSTS), _combo_ramp) * _subjob_fx_ghost)))
	var ghost_gap := 1.0 / float(ghosts)
	while _ghost_next_u <= u and _ghost_next_u < 1.0:
		AfterImage.spawn_weapon(_weapon, _weapon_pivot, self,
			_swing_dir.angle() + _swing_angle_at(_ghost_next_u), _fx_color(1.0))
		_ghost_next_u += ghost_gap


# 리본에 **한 쌍**(칼밑·칼끝) — `uu`는 이징된 스윕 진행값(0~1).
# 🔴 각은 `_swing_angle_at`을 쓴다 — **무기 각과 같은 함수**라 사본이 아니다(m-6이 지키는 그 자리).
# 🔴 두 점은 **같은 각**으로 뽑는다. 각을 따로 계산하면 리본의 두 변이 서로 다른 호를 그려 면이
#   비틀리고, 그 비틀림이 자기 교차를 만들면 다각형 분할이 실패해 **에러 없이 안 그려진다.**
func _trail_push(uu: float) -> void:
	if _trail_tip.size() >= TRAIL_MAX_POINTS:
		_trail_base.remove_at(0)
		_trail_tip.remove_at(0)
	var ang := _swing_angle_at(uu)
	_trail_base.append(_blade_base_global(ang))
	_trail_tip.append(_blade_tip_global(ang))


# 리본 비우기 — 점·다각형·정점색·표시를 한 자리에서 내린다.
# ⚠ 세 곳이 부른다: 새 스윙 무장(`_arm_swing_trail`) · 페이드 종료 · (간접) 취소 후 페이드 종료.
func _trail_clear() -> void:
	_trail_base.clear()
	_trail_tip.clear()
	_swing_trail.polygon = PackedVector2Array()
	_swing_trail.vertex_colors = PackedColorArray()
	# ⚠ **uv도 같이 내린다** — 정점을 비우면서 uv만 남기면 다음 스윙의 첫 프레임에 낡은 크기의
	#   uv가 새 다각형과 짝지어진다(Godot이 크기 불일치를 무시하므로 **에러 없이** 질감만 안 붙는다).
	_swing_trail.uv = PackedVector2Array()
	_swing_trail.visible = false


# 🔴 **면 리본 조립 — 바깥 변은 칼끝 궤적 "그 자체"다.**
#   고리 순서 = `안쪽[0..n-1]` → `바깥[n-1..0]`. 두 궤적이 동심(베기) 또는 평행(찌르기)이라 서로
#   교차하지 않고, 스윙 총 각도는 `_begin_swing`의 `cap`이 `2π − 0.02` 밑으로 잘라 두므로 고리가
#   한 바퀴를 넘겨 **자기 교차**하는 경우도 없다 — 그 `cap`이 이제 다각형의 단순성까지 지킨다.
# 🔴 꼬리는 **칼끝 쪽으로만** 좁아진다(`lerp(tip → base)`) — 반대로 하면 오래된 자국이 칼끝 밖으로
#   나가 도달 거리를 부풀린다. 선단(`s = 1`)은 항상 칼날 폭 전부라 `_swing_to` 래치가 온전히 남는다.
# ⚠ **비용: 매 프레임 최대 96정점 재삼각분할**(`Polygon2D`가 `polygon` 대입마다 ear-clipping을 돈다).
#   스윙당 7~11프레임뿐이라 지금은 무시 가능으로 판단했다 — 🔴 **웹 실기에서 스윙 프레임만 튀면
#   여기부터 본다**(reviewer m-4). 고치는 방향은 `TRAIL_SUBSTEPS`·`TRAIL_MAX_POINTS`를 줄이거나
#   `polygon` 대입을 실제로 점이 늘어난 프레임으로 한정하는 것이고, **프로파일러 캡처 전에 손대지 마라.**
func _rebuild_trail_ribbon() -> void:
	var n := _trail_tip.size()
	if n < 2:
		_swing_trail.visible = false
		return
	var poly := PackedVector2Array()
	var cols := PackedColorArray()
	poly.resize(n * 2)
	cols.resize(n * 2)
	# --- 리본 질감 (2026-08-01 사용자 요구: *"리본쪽에 특성 넣을 수 있나? 막 피처럼 보이거나"*) ---
	# 🔴 **UV는 정점과 정확히 같은 인덱스로 채운다** — 고리 순서가 `안쪽[0..n-1]` → `바깥[n-1..0]`이라
	#   UV도 그 순서를 따라야 한다. 어긋나면 텍스처가 뒤틀려 붙는데 **에러가 없다**.
	#   가로(u) = 꼬리(0) → 선단(1) = 시간축 · 세로(v) = 칼끝(0) → 칼밑(1) = 날 폭 방향.
	# 🔴 **`Polygon2D.uv`는 정규화가 아니라 텍스처 픽셀 좌표다** — 0~1로 넣으면 텍스처 왼쪽 위
	#   한 픽셀만 늘어나 단색으로 보인다(에러 없음). 그래서 크기를 곱한다.
	# ⚠ 텍스처가 없으면 **uv를 빈 배열로 되돌린다** — 남겨 두면 다음 하위 직업(질감 없음)으로
	#   바꿨을 때 크기만 맞는 낡은 uv가 남는다.
	var tex := _subjob_fx_tex
	var uvs := PackedVector2Array()
	if tex != null:
		uvs.resize(n * 2)
	# ⚠ 마무리 타만 더 진하다 — **기하는 그대로**이고 알파만 오른다(폭을 안쪽으로 넓히는 것은 이
	#   무기들에선 소용이 없다: 대검은 `blade_length` 36이 칼끝 거리 44의 대부분이라 안쪽 변이 이미
	#   `TRAIL_MIN_INNER_DIST`에 붙어 있고, 더 넓히면 07-29에 버린 **부채꼴 띠**로 되돌아간다).
	var amax := lerpf(TRAIL_ALPHA_MAX, COMBO_FINISH_TRAIL_ALPHA, _combo_ramp)
	for i: int in range(n):
		var s := float(i) / float(n - 1)  # 0 = 가장 오래된 꼬리 · 1 = 선단
		var col := Color(1.0, 1.0, 1.0, amax * _trail_tail_alpha(s))
		poly[i] = _trail_tip[i].lerp(_trail_base[i], lerpf(TRAIL_TAIL_WIDTH, 1.0, s))
		poly[n * 2 - 1 - i] = _trail_tip[i]
		cols[i] = col
		cols[n * 2 - 1 - i] = col
		if tex != null:
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			uvs[i] = Vector2(s * tw, th)              # 안쪽 변(칼밑) = 텍스처 아래
			uvs[n * 2 - 1 - i] = Vector2(s * tw, 0.0)  # 바깥 변(칼끝) = 텍스처 위
	# ⚠ **대입 순서가 중요하다** — `polygon`을 먼저 넣으면 그 프레임에 낡은 uv(직전 크기)와 잠깐
	#   짝이 안 맞는다. Godot이 크기 불일치 uv를 무시하므로 치명적이진 않지만, 텍스처를 먼저 세워
	#   두면 그 한 프레임의 깜빡임도 없앤다.
	_swing_trail.texture = tex
	_swing_trail.uv = uvs
	_swing_trail.polygon = poly
	_swing_trail.vertex_colors = cols
	_swing_trail.visible = true


# 꼬리 알파 곡선 — 옛 씬 `Gradient`(0 → 0.45에서 0.55 → 1)와 같은 모양(상수 주석이 정본).
func _trail_tail_alpha(s: float) -> float:
	if s < TRAIL_FADE_MID:
		return TRAIL_FADE_MID_A * (s / maxf(TRAIL_FADE_MID, 0.0001))
	return lerpf(TRAIL_FADE_MID_A, 1.0, (s - TRAIL_FADE_MID) / maxf(1.0 - TRAIL_FADE_MID, 0.0001))


# 🔴 **무기 스프라이트의 로컬 x → 회전 중심 기준 거리** — `_update_weapon`의 배치식
#   (`_weapon.position = -_weapon_grip + Vector2(_hold_dist + lunge, 0)`, `centered = false`)에서
#   **그대로** 유도한다. 칼끝·칼밑이 이 함수 하나를 지나므로 리본의 두 변이 어긋날 축이 없다(사본 금지).
# ⚠ **`_motion_lunge`(현재값)를 쓴다** — 리본은 칼이 **지금** 있는 자리를 찍는다.
func _weapon_local_dist(local_x: float) -> float:
	return local_x - _weapon_grip.x + _hold_dist + _motion_lunge


# 회전 중심 기준 거리 + 각 오프셋 → **월드 좌표**.
#   피벗 = `global_position + WeaponPivot.position` (플레이어는 회전하지 않으므로 회전 없이 더한다)
# ⚠ `SwingTrail`이 `top_level = true`라 여기서 나온 좌표가 곧 다각형 좌표다(씬 주석이 짝).
func _weapon_point_global(dist: float, ang_off: float) -> Vector2:
	return global_position + _weapon_pivot.position \
		+ Vector2(dist, 0.0).rotated(_swing_dir.angle() + ang_off)


# 🔴 **검기 도달 배율 — `reach` 특성이 켜지면 리본이 길어진다** (2026-08-01, 사용자 요구:
#   *"메인직업이 검성일 떄는 무기범위가 길어지는거"* → 2차 *"검기가 날아갔으면 좋겠음 크고 두껍게"*).
# 🔴🔴 **판정 배율보다 일부러 크다 — 이 비대칭이 계약이고, "갈라졌다"고 되돌리지 마라.**
#   판정은 `effective_attack_range` = `base × (1 + clamp_reach)`이고 여기는 그 위에
#   `TRAIL_REACH_SHOW_MULT`를 얹는다(검성 메인 기준 판정 1.3배 vs 표시 **1.6배**).
#   §3이 금지하는 것은 「**표시 < 판정**」(= 안 보이는데 맞는다) 한 방향뿐이고, 표시가 더 큰 것은
#   **허용 방향**이다(netreview 2026-08-01이 `MAX_MELEE_RANGE` 미적용을 두고 같은 판단을 내렸다).
#   판정 각·반경은 여기서 한 픽셀도 안 움직인다 — 이 함수는 리본 좌표에만 쓰인다.
# ⚠ **대가는 손맛이다**: 표시가 판정보다 크면 "휘둘렀는데 안 맞는" 띠가 생긴다(검성 메인에서
#   판정 54.6px · 리본 67.2px = **12.6px**). 계약 위반은 아니지만 실기에서 너무 넓게 느껴지면
#   줄일 자리는 판정이 아니라 **이 상수 하나**다.
# 🔴 **배율식(`1 + reach × k`)을 유지해라 — 절대값으로 바꾸지 마라.** 무기를 바꾸거나
#   `melee_range`를 튜닝할 때 리본이 따라오는 것은 이 식이 판정과 **같은 입력**(`clamp_reach`)에서
#   파생되기 때문이다. 절대값을 적는 순간 두 번째 진실원이 생긴다(§3).
# ⚠ reach 0 = 배율 1.0 = **완전 항등**이다 — 검성이 아닌 모든 경우에 도입 전과 한 픽셀도 다르지 않다.
#   상한도 `clamp_reach`(0.5)가 쥐므로 최댓값은 2.0배로 닫혀 있다(별도 clamp 불필요).
# ⚠ 리본 **전용**이다: 칼 스프라이트와 잔상은 안 늘어난다(칼은 실물이고 검기는 칼이 만든 것).
#   그래서 `_weapon_local_dist`(칼 실물 배치식의 미러)에 곱하지 않고 여기서만 곱한다.
# ⚠ **두께는 저절로 따라온다** — `_blade_base_global`이 같은 배율을 곱해 닮음이라, 길이를 키우면
#   폭도 같은 비율로 커진다("크고 두껍게"가 상수 하나로 떨어지는 이유).
# 🔴 **마무리 사거리(v2.3)도 여기서 곱한다 — 안 곱하면 §3 「표시 ≥ 판정」이 즉시 깨진다.**
#   칼·리본·잔상은 사거리를 **한 번도 안 읽고** 텍스처 폭에서 도달을 만든다(`_weapon_local_dist`).
#   그래서 판정만 늘리면 표시가 한 픽셀도 안 따라오는데, 대검의 현행 여유는 **+2px뿐**이다
#   (판정 프레임 칼끝 44.0 vs 판정 42 — 베기는 `sin(uπ)`라 u=1에 내지르기가 정확히 0이다).
#   42 → 63으로 올리고 이 줄이 없으면 **−19px의 「안 보이는데 맞는다」** 가 그 자리에서 생긴다.
# 🔵 **배율을 판정 비율에서 나눗셈으로 유도하므로 현행 여유가 비율째 보존된다** — 튜닝값이 아니라
#   갈라질 축이 없다. reach 축(`TRAIL_REACH_SHOW_MULT`)과 **곱해지는** 것도 의도다(두 축이 독립).
# ⚠ 표시는 **주장 타수**(`_swing_is_finish`)로 그린다 — 판정(호스트 = 센 타수)과 부호가 다르지만
#   방향이 「표시 ⊇ 판정」이라 §3이 허용하는 쪽이다.
func _trail_reach_mult() -> float:
	var m := 1.0 + CombatMath.clamp_reach(trait_value("reach")) * TRAIL_REACH_SHOW_MULT
	if _swing_is_finish:
		m *= CombatMath.combo_finish_show_mult(job, _weapon_override, trait_value("reach"))
	return m


# 칼끝의 월드 좌표 = 텍스처 오른쪽 끝 (× 검기 배율). 🔴 **리본의 바깥 변이자 상한이다.**
# ⚠ 옛 주석의 *"여기를 넘는 표시는 없다"* 는 검기 도입으로 **칼끝 기준으로는 거짓이 됐다** — 상한은
#   이제 「칼끝 × `_trail_reach_mult()`」다.
# ⚠ **"그 상한이 곧 판정 반경"이라고 읽지 마라** (netreview 정정). 같은 것은 **배율뿐**이고 절대값은
#   서로 다른 양에서 온다: 리본은 텍스처 폭(`_weapon_local_dist`), 판정은 `melee_range`/`attack_range`다.
#   또 `effective_attack_range`에는 `MAX_MELEE_RANGE`(130) clamp가 있는데 여기엔 없다 — 현 데이터는
#   창 80 × 1.5 = 120 < 130이라 도달 불가이고, 물리더라도 방향이 「표시 > 판정」(§3 허용 쪽)이다.
func _blade_tip_global(ang_off: float) -> Vector2:
	if _weapon.texture == null:
		return global_position
	return _weapon_point_global(
		_weapon_local_dist(float(_weapon.texture.get_width())) * _trail_reach_mult(), ang_off)


# 칼밑(날이 시작하는 지점)의 월드 좌표 = 칼끝 − `CombatMath.blade_length(무기)`.
# 🔴 길이의 단일 소스는 `CombatMath`다(→ `EquipDef.blade_length`) — 여기서 텍스처 픽셀로 다시
#   유도하지 마라. 근거·기각한 대안은 그 함수와 `equip_def.gd`의 필드 주석이 정본이다.
# 🔴 **`minf(tip_d, ...)`가 부호를 구조로 닫는다** (reviewer m-2). `maxf` 하한만 두면 한쪽으로만
#   안전하다 — `tip_d < TRAIL_MIN_INNER_DIST`인 순간 **안쪽 변이 바깥 변보다 멀어져** 리본이 뒤집히고,
#   그건 「칼끝 밖으로 안 나간다」 불변식을 **정확히 반대로** 깨는 방향이다(현 최소 54px라 도달
#   불가하지만, 한 겹으로 닫히는 것을 데이터 가정에 맡기지 않는다). 최악이 "두께 0 = 안 보임"이 된다.
# ⚠ 하한 자체가 하는 일은 `TRAIL_MIN_INNER_DIST` 주석이 정본이다 — 퇴화를 막는 것은 전수 트립와이어다.
# 🔴 **검기 배율은 두 변에 똑같이 곱한다 = 닮음이다** (2026-08-01). 바깥 변에만 곱하면 띠 폭이
#   `blade_length + (늘어난 길이)`로 부풀어 「리본 폭 = `EquipDef.blade_length`」 단일 소스가 조용히
#   깨진다 — 검성일 때만 무기 데이터와 화면이 갈라지고, 그건 에러 없이 "검성 리본만 두껍다"로만 보인다.
#   양쪽에 곱하면 폭도 같은 비율로 커져 **검기가 칼의 닮은꼴**이 되고, 폭의 근거는 여전히 데이터 한 곳이다.
# ⚠ `minf(tip_d, ...)` 부호 구조는 그대로 산다 — 배율이 항상 양수(≥ 1.0)라 두 변의 대소가 안 뒤집힌다.
func _blade_base_global(ang_off: float) -> Vector2:
	if _weapon.texture == null:
		return global_position
	var k := _trail_reach_mult()
	var tip_d := _weapon_local_dist(float(_weapon.texture.get_width())) * k
	var base_d := maxf(tip_d - CombatMath.blade_length(_weapon_override) * k, TRAIL_MIN_INNER_DIST)
	return _weapon_point_global(minf(tip_d, base_d), ang_off)


# 네트워크 검증용 좌표 — 원격은 lerp된 표시 좌표가 아니라 (클램프된) 최신 수신 좌표를 쓴다.
# 표시 보간 지연 때문에 호스트의 사거리 검증이 정당한 적중을 거부하는 문제 방지 (실기 진단에서 확인).
# ⚠ 이건 여전히 **과거** 좌표다(편도 지연 + 송신 주기만큼). 피격 판정처럼 "지금 어디 있나"가
#   중요한 곳은 net_anchor_lead()와 짝지어 쓴다 — CombatMath.is_strike_hit_lagged (§3 지연 보상).
func net_anchor() -> Vector2:
	return global_position if is_local else _remote_target


# 지연 보상용 추정 좌표 — 마지막 관측 속도로 외삽한 "지금쯤 여기 있을 것" 위치.
# 로컬 피어는 지연이 없으므로 net_anchor()와 같다(항등 폴백 — 호스트 자신은 보상 대상이 아니다).
# one_way_ms = 그 피어와의 편도 지연 (Net.one_way_ms). 판정은 반드시 net_anchor()와 **둘 다** 통과해야
# 확정된다 — 외삽 오차가 방어자에게 유리한 쪽으로만 떨어지게 하는 규약 (CombatMath 주석 참조).
func net_anchor_lead(one_way_ms: float) -> Vector2:
	if is_local:
		return global_position
	var lead_s := CombatMath.lag_lead_s(_last_remote_msec, Time.get_ticks_msec(), one_way_ms)
	return CombatMath.extrapolate(_remote_target, _remote_vel, lead_s)


# 원격 플레이어의 공격 연출 (peer_sync가 G_ATK 수신 시 호출) — **연출은** 표시 전용, 판정 아님.
# combo = G_ATK "cb"(그 피어의 콤보 타수). 🔴 **v2.2부터 그 타수 자체는 판정 입력이다** — 다만 판정은
#   호스트(`combat_authority`)가 자기 G_ATK 수신 간격으로 따로 세고 주장을 `min` 상한으로만 쓰므로,
#   여기서 그리는 것은 여전히 "주장 그대로"이고 갈라짐은 항상 **표시 ⊇ 판정** 쪽으로만 떨어진다(§3).
func play_attack_fx(dir: Vector2, combo: int = 0) -> void:
	if not _alive or not _is_armed():
		return  # 사망자·무장 해제 피어의 G_ATK로 FX가 뜨는 것 차단 (그 피어 무기 = set_weapon_visual 반영)
	# 조준각을 즉시 그 방향으로 당긴다 — 다음 G_POS를 기다리면 스윙이 옛 방향으로 한 박자 나간다.
	# (뒤집기는 _play_dir_anim이 이 각에서 파생한다 — flip_h를 여기서 대입하면 서로 덮어쓴다)
	if is_finite(dir.x) and is_finite(dir.y) and dir.length_squared() > 0.000001:
		_remote_aim = dir.angle()
		_remote_flip = dir.x < 0.0  # 4방향 시트가 없을 때의 폴백 경로가 읽는 값
	# 🔴 **스팸 게이트는 「마지막 수신 시각 + 유효 쿨다운 × FIRE_RATE_SLACK」이다** (netreview I-1).
	#   전에는 "스윙 창이 아직 열려 있으면 무시"였는데, 궤적 무장이 이 게이트 안으로 들어오면서
	#   삼켜질 때 **궤적·소리·무기 모션이 전부** 사라지게 됐다(도입 전엔 궤적은 떴다) — 상대 화면에서
	#   그 타격이 **없었던 일**이 되는데 HP는 깎인다. 그런데 여유가 `0.4 − 0.36(도끼)` = **40ms**뿐이고
	#   최대 haste에선 더 좁아, G_ATK가 safe 채널이라 재전송 지터 한 번이면 넘는다.
	# 🔴 게이트를 **모션 길이에서 떼어 내 호스트가 쓰는 것과 같은 양**에 묶는다 — 근접 쿨다운·발사율·
	#   차지 시간 세 게이트가 이미 쓰는 관용구(`FIRE_RATE_SLACK`)라 이제 넷이 같은 자리를 본다.
	#   `heavy_axe.swing_time`을 더 늘려도 이 여유가 안 줄어든다(전엔 직접 줄었다).
	# ⚠ 데이터(`swing_time`)를 내리는 쪽은 손맛을 깎으므로 고르지 않았다.
	var now_ms := Time.get_ticks_msec()
	# 🔴 **여유의 부호가 스로틀과 반대다 — 이게 계약이다**(I-3과 한 상수, 같은 프레임 여유).
	#   저쪽은 "호스트가 받아 줄 만큼 **늦게**"(+)라 안전한 쪽이 늦는 것이고, 이쪽은 "호스트가 받아
	#   주는 것은 **반드시 보여야**"(−)라 안전한 쪽이 관대한 것이다. 같은 부호로 통일하려는 변경은
	#   둘 중 하나를 반드시 망가뜨린다(§3 「방어자 우대」와 「각 슬랙」이 반대 부호인 것과 같은 형태).
	var gate_ms := 0
	if job != null:  # 그 피어의 직업·공지 haste 기준 (원격 인스턴스가 자기 값을 들고 있다)
		gate_ms = int(CombatMath.melee_fx_gate_s(job, _haste()) * 1000.0)
	# 🔴🔴 **타수 갱신은 스팸 게이트 *밖*이다** (v2.2). 호스트는 G_ATK를 **하나도 안 떨구고** 세는데
	#   여기서 게이트가 한 통을 삼키면 원격 표시 타수가 그만큼 밀려 **화면 타수 ≠ 판정 타수**가 된다
	#   (마무리 타가 상대 화면에서 평타로 보이거나 그 반대 — 둘 다 「표시 = 판정」 계약 위반이다).
	# ⚠ 게이트의 목적(애니 영구 잠금·진행 중 궤적 방향 갈아엎기 차단)은 안 해친다 — 인덱스 대입은
	#   애니를 재시작하지도, `_swing_from`/`_swing_dir`을 건드리지도 않는다. 그것들은 게이트 안에 남는다.
	# ⚠ 범위 밖 주장은 여기서 clamp한다(`_begin_swing`이 하던 것과 같은 값) — 게이트가 삼킨 통의
	#   주장도 오염되지 않게.
	_combo_index = clampi(combo, 0, _combo_len() - 1)
	if now_ms - _last_atk_fx_msec >= gate_ms:
		_last_atk_fx_msec = now_ms
		# 재수신 무시 — G_ATK 스팸으로 애니를 영구 attack으로 잠그거나 진행 중인 궤적의 방향을
		# 되돌리는 그리핑 차단.
		# 🔴 **궤적 무장도 이 게이트 안이다** — 진행형 궤적이라 창 도중의 재수신이 `_swing_from`/
		#   방향을 갈아엎으면 그리다 만 자국이 튄다(도입 전엔 한 번 번쩍이고 끝이라 무해했다).
		#   방향 갱신(`_remote_aim`)은 게이트 밖에 그대로 둔다.
		# ⚠ 원격도 **같은 선딜·스윕 비율**을 지나므로(그 피어의 무기 데이터) 두 화면의 타이밍이
		#   자동으로 맞는다. 소리·파형은 `_tick_swing_motion`의 스윕 시작 지점에서 난다.
		_swing_dir = dir  # 원격도 이 한 방향으로 무기·궤적을 그린다(로컬의 클릭 고정과 미러)
		# 연계 여부는 **타수 인덱스**에서 읽는다 — 원격엔 로컬의 `_combo_left` 창이 없고, 호스트가
		# 센 인덱스가 0보다 크다는 것 자체가 "직전 타에서 이어졌다"는 뜻이다(그 인덱스는 위에서 clamp됐다).
		_begin_swing(_combo_index, _combo_index > 0)  # 그 피어의 무기 스윙 창 + 같은 콤보 궤적
		# 🔴 **대기 자세 창을 원격에도 연다** (2026-08-01). 전에는 `_combo_left`가 로컬에서만 세워져
		#   `_tick_swing_motion`의 대기 갈래가 원격에서 **한 번도 참이 아니었다** — 그래서 상대 화면의
		#   무기는 매 타 중립으로 돌아갔고, 마무리 직전 타의 젖힘(`_combo_hold_pose`)도 **자기 화면에만**
		#   보였다. 2인 협동에서 절반만 그려지는 연출이 된다.
		# 🔴 **네트워크 0 · 판정 0**: 값은 그 피어의 무기·haste로 **로컬에서** 리졸브하고(`combo_window_s`
		#   — 호스트와 같은 함수), 이 멤버를 읽는 곳은 대기 자세 갈래와 젖힘 게이트뿐이다.
		#   `continues_combo`(`_swing_attack`)는 **로컬 전용 경로**라 원격 값이 흘러들지 않는다.
		# ⚠ 타수는 위에서 호스트가 센 인덱스를 그대로 쓴다 — 창은 "언제 중립으로 돌아가나"만 정한다.
		_combo_left = _combo_window_s((_combo_index + 1) % _combo_len())
		_arm_swing_trail()


# 원격 궁수의 발사 연출 (peer_sync가 G_SHOOT 수신 시 호출) — 활 반동만, 표시 전용. 화살 자체는 ArrowField가 스폰.
func play_shoot_fx() -> void:
	if not _alive or not _is_armed():
		return  # 사망자·무장 해제 피어의 G_SHOOT로 연출이 뜨는 것 차단
	_recoil_left = RECOIL_TIME
	EventBus.player_swing.emit(global_position, _swing_sfx, 1.0)  # 발사 SFX (원격 — swing_sfx 재활용)


# 원격 플레이어의 구르기 연출 (peer_sync가 G_ROLL 수신 시 호출) — 표시 전용.
# i-frame 판정은 호스트 그랜트 창(CombatAuthority)이 별도로 한다 (§3) — 이 창은 애니만 돌린다.
func play_roll_fx(dir: Vector2) -> void:
	# 🔴 그 피어가 스윙을 구르기로 취소했다면 **내 화면에서도 끊겨야 한다.** 취소 전용 메시지를
	#   만들지 않는 이유가 이것이다 — 취소는 항상 구르기이고 G_ROLL이 이미 온다(새 kind 0개).
	# 🔴 **스팸 게이트보다 앞이다** (netreview m-1): 게이트 뒤에 두면 원격 구르기 창 안에 도착한
	#   G_ROLL이 취소를 못 전해 유령 스윙이 남는다. rules §3 「거부 게이트가 먼저, 관대한 폴백이
	#   나중」과 같은 형태이고, **취소는 멱등**이라 앞으로 올려도 스팸 방어가 약해지지 않는다.
	_cancel_swing()
	if _remote_roll_left > 0.0:
		return  # 창 중 재수신 무시 — G_ROLL 스팸으로 애니를 영구 roll로 잠그는 그리핑 차단 (정직한 구르기는 쿨다운 0.8s > 창 0.25s라 안 걸린다)
	_remote_roll_left = CombatMath.ROLL_TIME_S
	EventBus.player_roll.emit(global_position)  # 구르기 SFX (원격 — 스팸 게이트 뒤)
	if absf(dir.x) > 0.001:
		_remote_flip = dir.x < 0.0  # 4방향 시트가 없을 때의 폴백 경로가 읽는 값
	if is_finite(dir.x) and is_finite(dir.y):
		_roll_dir = dir  # 대쉬 종료 되튐 방향 — 원격은 카메라가 없으니 잔상·먼지에만 쓰인다
	_dash_burst(dir)  # 원격도 같은 대쉬 연출(잔상·먼지). 카메라 킥은 _dash_burst 안에서 로컬만


func _send_pos(delta: float) -> void:
	_send_accum += delta
	if _send_accum >= 1.0 / POS_SEND_RATE:
		_send_accum = 0.0
		_pos_seq += 1
		Net.send_game({
			NetSchema.KEY_KIND: NetSchema.G_POS,
			# 송신 시퀀스 — P2P fast 채널이 unordered라 순서 뒤바뀜을 수신부가 걸러야 한다 (§3, CombatMath.is_pos_seq_fresh).
			"n": _pos_seq,
			"s": scene_id,
			"x": global_position.x,
			"y": global_position.y,
			"f": _sprite.flip_h,
			"a": snappedf(_aim_angle, 0.01),  # 조준각 — 원격 무기 표시 전용 (판정 아님)
			# 차지 상태 — 0 = 안 모으는 중, 그 외 = 레벨+1 (0단계 차지와 비차지를 구분하려는 인코딩).
			# 표시 전용이다: 실제 발사 레벨은 G_SHOOT "c"를 호스트가 차지 시간으로 재검증한다 (§3).
			"c": (_charge_level + 1) if _charging else 0,
			# 현재 속도 — 호스트가 "지금 내가 어디 있는지"를 추정하는 재료 (지연 보상, §3).
			# 부풀려 보내도 수신부 clamp + 외삽 거리 상한 + "방어자 우대" 규약 때문에 회피가
			# 관대해질 뿐 남을 때릴 수는 없다 (판정은 여전히 호스트가 자기 계산으로 확정).
			"vx": snappedf(velocity.x, 0.1),
			"vy": snappedf(velocity.y, 0.1),
		})


# 원격 위치 반영 — 메시지 간 변위를 최대 이동 속도로 클램프한다.
# 호스트의 사거리 검증(§3)이 이 표시 좌표를 기준으로 하므로, 클램프 없이는 순간이동 스푸핑으로 검증이 무력화된다.
func apply_remote_pos(pos: Vector2, flip: bool, aim: float, charge_code: int = 0,
		vel: Vector2 = Vector2.ZERO, seq: int = 0) -> void:
	# 🔴 순서 뒤바뀜 폐기 — **속도·조준각·차지까지 포함해 통째로** 버린다(맨 앞에서 return).
	#   옛 패킷의 vel만 새겨도 외삽이 과거 속도로 돌아가 방어자 우대가 무력화된다 (§3).
	if not CombatMath.is_pos_seq_fresh(seq, _last_pos_seq):
		return
	if seq > 0:
		_last_pos_seq = seq
	# Inf/NaN 주입 가드 — JSON은 1e999 같은 오버플로를 Inf로 파싱한다. lerp_angle(유한, INF)=NaN이
	# 한 발로 _aim_angle을 영구 오염시키고, pos 쪽은 net_anchor()를 타 호스트 판정까지 닿는다 (리뷰 Important).
	if is_finite(aim):
		_remote_aim = wrapf(aim, -PI, PI)
	# 원격 차지 표시 — 0 = 안 모으는 중, 그 외 = 레벨+1. clamp로 범위 밖 값은 무해화(표시 전용, 판정 아님).
	var new_charge := clampi(charge_code, 0, CombatMath.MAX_CHARGE_LEVEL + 1) - 1
	if new_charge > _remote_charge and new_charge > 0:
		_orb_pop_left = ORB_POP_TIME
		# 상대가 단계를 올리는 "딸깍". ⚠ "직전보다 높으면"만으로는 못 막는다 — c를 0↔2로 진동시키면
		# 매 G_POS(15Hz)마다 상승으로 보인다 → 최소 간격 게이트로 도배 차단 (play_roll_fx 창-잠금과 같은 이유).
		var now_sfx := Time.get_ticks_msec()
		if now_sfx - _remote_charge_sfx_msec >= REMOTE_CHARGE_SFX_MIN_MS:
			_remote_charge_sfx_msec = now_sfx
			EventBus.player_swing.emit(global_position, _charge_sfx, 1.0)
	_remote_charge = new_charge
	# 속도 반영 — 위치와 같은 신뢰 규율(유한성 + 최고 이동속도 clamp). 외삽 입력이므로 여기서 상한을 건다.
	# ⚠ 무효값이면 0으로 떨어뜨린다(이전 속도 유지 금지) — 정지한 피어를 계속 미끄러뜨리면
	#   추정 좌표가 실제와 벌어져 "방어자 우대"가 과하게 관대해진다.
	if is_finite(vel.x) and is_finite(vel.y):
		var max_speed := _max_roll_speed()  # 🔴 이속·kill_move·roll_dist 반영 — 안 하면 지연 보상이 부분 퇴행한다(§3)
		_remote_vel = vel.limit_length(max_speed)
	else:
		_remote_vel = Vector2.ZERO
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return  # 무효 좌표는 통째로 무시 — 이전 앵커 유지
	var now := Time.get_ticks_msec()
	if _last_remote_msec >= 0:
		var dt := maxf(float(now - _last_remote_msec) / 1000.0, 1.0 / POS_SEND_RATE)
		var max_disp := _max_roll_speed() * REMOTE_MAX_SPEED_MULT * dt  # 속도 상한과 같은 유도식(갈라지면 한쪽만 튜닝된다)
		var delta := pos - _remote_target
		if delta.length() > max_disp:
			pos = _remote_target + delta.normalized() * max_disp
	_last_remote_msec = now
	_remote_target = pos
	_remote_flip = flip
