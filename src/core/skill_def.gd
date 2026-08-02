class_name SkillDef
extends Resource
# 하위 직업 스킬 정의 스키마 (core — 리드 전용). 개체는 data/skills/*.tres (rules §4).
# 하위 직업 하나당 스킬 하나. GDD §3이 조작을 확정해 뒀고(스킬 = 우클릭 + Q/E/R) §11이
# 「직업별 스킬 구성」을 TBD로 남겨 둔 자리다 — 2026-08-02 사용자 확정으로 **공격형 2개**부터 연다.
#
# 🔴 **네트워크로 오가는 것은 스킬 수치가 아니다.** 발동 메시지(G_SKILL)에는 방향만 싣고,
#   배율·반경·사거리·쿨다운은 **호스트가 그 피어의 공지 하위 직업 id(G_STATS "ms")로
#   자기 data/subjobs → data/skills에서 리졸브**한다. `peer_weapon_id`·`projectile_params`와 같은
#   철학이다(rules §3) — 수치를 실으면 그게 곧 "내 데미지는 ×99"라고 주장하는 표면이 된다.
#
# 🔴 **판정 기하 = 표시 기하다.** 아래 radius/length가 곧 FX 크기이고, 호스트 판정도 같은 값을
#   쓴다("맞는 곳 = 보이는 곳", rules §3). FX를 키우고 싶으면 여기를 키워라 —
#   연출 상수로 그림만 키우면 보스 콘 텔레그래프가 두 번 값을 치른 그 실패로 되돌아간다.
#
# 🔒 축 경계 — 여기 있는 것은 **스킬 한 방의 기하와 배율뿐**이다. 공격력·체력(장비 축)도,
#   치명·공속(5스탯 축)도 넣지 마라. 스킬이 그 축을 밀면 화력 예산 트립와이어가 겨누는 대상이
#   둘로 갈라져 무엇이 예산을 넘겼는지 못 읽게 된다.

@export var id: String = ""              # data/skills/<id>.tres 파일명과 일치
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D              # 스킬 슬롯 표시 (도형 금지, rules §0)

# --- 형태 ---
# 🔴 판정 함수를 고르는 축이다 — `BossPatternDef.shape` 규약의 미러(원/부채꼴 → 여기선 원/캡슐).
#   모르는 문자열은 `CombatMath.is_skill_hit`이 **false로 떨어뜨린다**(안 맞는 쪽 = 안전한 폴백).
const SHAPE_SPIN := "spin"   # 자기 중심 원 광역(360°) — 판정 = CombatMath.is_strike_hit
const SHAPE_BEAM := "beam"   # 전방 직선 관통 — 판정 = CombatMath.capsule_depth (보스 횡단 돌진과 같은 함수)

@export var shape: String = SHAPE_SPIN

# --- 수치 (상한은 여기가 아니라 CombatMath가 쥔다 — 데이터에 큰 값을 써도 그 위로는 안 올라간다) ---
# 평타 대비 데미지 배율. 🔴 `confirm_damage`의 `combo_mult` 자리에 들어간다(새 곱셈 축을 만들지 않는다).
@export var damage_mult: float = 1.0
# spin = 판정 원 반경 / beam = 관통 띠의 **반폭**. 둘 다 월드 px.
@export var radius: float = 0.0
# beam 전용 = 관통 사거리(px). spin에서는 무시된다.
@export var length: float = 0.0
# 재사용 대기(초). 🔴 호스트가 이 값으로 발동률을 검증한다(`is_fire_rate_ok` 규약 미러) —
#   클라 주장이 아니라 **호스트가 리졸브한 자기 데이터**가 게이트다.
@export var cooldown_s: float = 10.0
# 선딜(초) — 0이면 즉발. 예고가 필요한 스킬은 여기를 키운다(적에게 반응할 틈을 주는 축).
@export var windup_s: float = 0.0

# --- 다단 히트 (2026-08-02 — 광전사 「환영검무」가 첫 입주) ---
# 🔴 **`damage_mult`는 「타당」 배율이고 총합은 `damage_mult × hit_count`다.** 예산 트립와이어가
#   그 곱을 재므로 타수를 늘리면 타당 배율을 그만큼 내려야 통과한다 — 이 관계를 뒤집지 마라
#   (총합을 여기 적고 코드가 나누게 하면, 타수를 바꿀 때 타당 데미지가 조용히 달라진다).
# 🔴 **한 번의 `G_SKILL`로 호스트가 N회 판정한다 — 클라가 N번 보내지 않는다.** 클라 발신을 타수만큼
#   늘리면 그게 곧 발동률 게이트를 N배로 넓히는 스팸 표면이 된다(`is_skill_ready`가 첫 통만 본다).
# ⚠ 같은 적이 여러 번 맞는 것이 의도다(단일 대상 연타). 회피할 틈은 `hit_interval_s`가 준다.
# 1 = 단발 = 이 축 도입 전과 **완전 항등**.
# ⚠ **이동형(`travel_speed > 0`)에서는 무시된다** — 그쪽은 프레임마다 전진하며 적별 1회 때린다.
@export var hit_count: int = 1
# 타와 타 사이(초). 총 시전 길이 = `hit_count × hit_interval_s`.
# ⚠ 상한·하한은 `CombatMath.clamp_skill_hit_interval`이 쥔다 — 0에 가까우면 N타가 한 프레임에
#   몰려 "다단"이 아니라 그냥 큰 한 방이 되고, 적이 반응할 틈이 사라진다.
@export var hit_interval_s: float = 0.08

# --- 이동형 (2026-08-02 — 검성 「월륜」이 첫 입주) ---
# 🔴 **`travel_speed > 0`이면 스킬이 「제자리 다단」에서 「날아가는 검기」로 성격이 바뀐다.**
#   호스트가 매 물리 프레임 판정 지점을 앞으로 밀며 닿는 적을 때린다 — 화살(`is_arrow_hit`)과 같은
#   구조다. 그래야 **"아직 검기가 안 왔는데 맞는다"가 시간 축에서 원천 불가**해진다(§3: 근접이
#   판정을 「선딜+스윕 끝」에 둔 것과 같은 이유).
# 🔴 **이동형은 적별 1회다 — 별도 플래그를 만들지 마라.** 날아가는 것이 같은 적을 프레임마다
#   때리면 「관통」이 아니라 「접촉 지속 피해」가 되고, 그건 `damage_mult` 한 칸으로 예산을 못 잡는다.
#   `travel_speed` 한 축이 「이동한다」와 「적별 1회」를 **함께** 정한다(보스방 게이트 바위가
#   `ttl` 하나로 「영구」와 「돌진 표적 제외」를 함께 정하는 것과 같은 관용구, rules §3).
# 🔴 이동형에서는 `hit_count`·`hit_interval_s`가 **무시된다**(두 모델이 겹치면 "5타짜리 날아가는
#   검기"라는 어긋난 조합이 생기고, 그때 예산 계산이 어느 쪽인지 아무도 모른다).
# 0 = 제자리 = 이 축 도입 전과 **완전 항등**.
@export var travel_speed: float = 0.0
# 이동형의 총 사거리(px). `travel_speed`가 0이면 무시된다.
# ⚠ 상한은 `CombatMath.SKILL_TRAVEL_DIST_MAX`가 쥔다 — "맵 끝까지"가 목표라 `SKILL_LENGTH_MAX`
#   (beam 축, 260)보다 큰 별도 상한이다. 근거는 화면이 아니라 **아레나**다(그 상수 주석이 정본).
@export var travel_dist: float = 0.0


func is_travel() -> bool:
	return travel_speed > 0.0 and travel_dist > 0.0


func is_beam() -> bool:
	return shape == SHAPE_BEAM
