class_name JobDef
extends Resource
# 직업 정의 스키마 (core — 리드 전용). 수치는 data/jobs/*.tres가 쥔다 (projectb-rules §4).

@export var id: String = ""              # data/jobs/<id>.tres 파일명과 일치 — 네트워크 직업 공지의 키
@export var display_name: String = ""
@export var sprite: Texture2D            # 캐릭터 단일 컷 (UI 미리보기용 — 인게임 표시는 frames)
@export var frames: SpriteFrames         # idle/run/roll 애니 (assets/sprites/player/<id>_frames.tres, 2방향 좌/우 플립 — GDD §5)
@export var max_hp: int = 100            # 임시값 — 사용자가 플레이하며 조인다
@export var move_speed: float = 100.0
@export var attack_damage: int = 10
@export var attack_range: float = 24.0   # 공격 판정 중심까지의 거리 스케일 (판정 반경도 이 값에서 파생)
@export var attack_cooldown: float = 0.4
