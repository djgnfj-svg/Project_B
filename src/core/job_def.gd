class_name JobDef
extends Resource
# 직업 정의 스키마 (core — 리드 전용). 수치는 data/jobs/*.tres가 쥔다 (projectb-rules §4).

@export var id: String = ""              # data/jobs/<id>.tres 파일명과 일치 — 네트워크 직업 공지의 키
@export var display_name: String = ""
@export var sprite: Texture2D            # 캐릭터 단일 컷 (UI 미리보기용 — 인게임 표시는 frames)
@export var frames: SpriteFrames         # idle/run/roll 애니 (assets/sprites/player/<id>_frames.tres, 2방향 좌/우 플립 — GDD §5)
@export var weapon_texture: Texture2D    # (레거시/폴백 데이터) 무기 스프라이트 — 겉모습은 이제 착용 무기(EquipDef)에서 그린다(무기 = 장비). 미착용 = 무장 해제
@export var weapon_grip: Vector2 = Vector2(4.0, 8.0)  # 무기 텍스처 안 그립(손잡이) 픽셀 좌표 — 회전축 정렬용 (EquipDef.weapon_grip이 우선)
@export var starting_weapon_id: String = ""  # 새 게임 시 기본 지급·착용할 무기 EquipDef id (data/equipment/<id>). 비면 무장 없이 시작

# 계열 = 이 직업(GDD §5 v1.8) — 하위 직업(SubJobDef.series_id == 이 id)들이 5스탯 성장을 담당한다.
@export var starting_sub_job_id: String = ""  # 새 판에 지급할 첫 하위 직업 SubJobDef id (starting_weapon_id 미러). 비면 성장축 없음
@export var exp_curve: PackedInt32Array = PackedInt32Array()  # 레벨 n 도달에 필요한 **누적** EXP(인덱스 = 레벨). 비면 CombatMath.DEFAULT_EXP_CURVE 폴백 — 계열별 페이싱을 데이터로 조인다 (rules §4)
@export var max_hp: int = 100            # 임시값 — 사용자가 플레이하며 조인다
@export var move_speed: float = 100.0
@export var attack_damage: int = 10
@export var attack_range: float = 24.0   # 공격 판정 중심까지의 거리 스케일 (판정 반경도 이 값에서 파생)
@export var attack_cooldown: float = 0.4
