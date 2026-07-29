extends Node
# 테스트 랩 컨트롤러 — ?test=1일 때 main이 보스 아레나에 붙인다 (TestMode 게이트, 프로덕션 무접촉·rules §5 씬 글루).
# 그림 구조: 아레나[보스 + player1(무적) + NPC 더미(무적, 코옵 2인 채움)] + 우측 패턴/상태 패널.
#  · 보스 자동공격·코옵 자동순환을 끄고(debug_hold) → 버튼으로 특정 패턴만 즉시 발동해 관찰·튜닝.
#  · 체크박스로 현재 상태(무적/보스정지/NPC) 확인·토글. HP 회복 버튼.
#  · 2인 실기: NPC 체크 해제하면 더미 제거 → 실제 2명으로 테스트.

const PlayerScene := preload("res://src/player/player.tscn")
const PlayerActor := preload("res://src/player/player.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")
const UiTheme := preload("res://src/ui/ui_theme.gd")   # UI 톤 단일 소스 (HUD·패널과 같은 팔레트 — class_name 대신 preload, rules §0)
const NetSchema := preload("res://src/core/net_schema.gd")  # SCENE_* id (새 보스 리셋 = 스테이지 재진입)
const Afterimage := preload("res://src/feel/afterimage.gd")  # 카운터 대시 잔상 (손맛 재사용)

var _boss: Node = null
var _coop: Node = null
var _npc: PlayerActor = null
var _boss_rim: AnimatedSprite2D = null   # 보스 뒤 밝은 실루엣(림) — 청록 배경에서 보스를 또렷하게

var _invincible: bool = true
var _npc_on: bool = true

var _cb_invin: CheckBox = null
var _cb_boss: CheckBox = null
var _cb_npc: CheckBox = null
var _hp_label: Label = null

# 2방(젤다식 화면 전환) — 왼쪽 진입 방 + 오른쪽 보스 방. 카메라를 현재 방에 클램프, 경계 넘으면 스냅.
const ROOM_SPLIT_X := 192.0
const ROOM1 := Rect2(-576.0, 100.0, 768.0, 448.0)   # 진입 방(왼쪽)
const ROOM2 := Rect2(192.0, 100.0, 768.0, 448.0)    # 보스 방(오른쪽 = 현 성역)
var _cur_room: int = 0
var _sealed: bool = false
var _panel_layer: CanvasLayer = null   # 패턴 패널(토글) — 기본 숨김이라 맵이 깨끗하게 보임. P로 토글.

# ② 살아있는 조명 — 환경 빛을 참조로 잡아 맥동+깜빡. ③ 노이즈 흔들림·깜빡 표본 공용.
var _env_lights: Array = []
var _env_t: float = 0.0
var _env_noise: FastNoiseLite = null

# ⑤ 페이즈2 환경 오염 — 실제 boss_phase_changed 구독 + 랩 토글. 0→1로 부드럽게 램프.
var _corruption: float = 0.0
var _corruption_target: float = 0.0

# 상단 보스 HP바 (글리치 스타일) — 이름 "Ghost Nos" + 노이즈 채움바. enemy_hp_confirmed 구독.
const BOSS_NAME := "Ghost Nos"
const HPBAR_W := 340.0
const HPBAR_H := 16.0
const HPBAR_TOP_PCT := 0.03   # 상단에서 3% 내려
var _boss_hp_layer: CanvasLayer = null
var _boss_hp_fill: ColorRect = null
var _boss_hp_text: Label = null
var _boss_max_hp: int = 1
var _boss_hp_innerw: float = 0.0

# 시야 콘 — 플레이어 조준(_aim_angle) 방향으로 벌어지는 시야 표시. 어두운 성역에서 방향 가독성.
const VISION_HALF := deg_to_rad(46.0)   # 콘 반각 (넓게 — 시야 느낌 강조)
const VISION_R0 := 16.0                 # 시작 반경(플레이어 몸 바깥)
const VISION_LEN := 170.0               # 시야 길이
var _vision: Node2D = null

# 카운터 — 보스 약점(F 표식)이 뜬 곳 근처에서 F를 눌러 카운터. 테스트: 무조건 플레이어 쪽에 뜬다.
# (실제론 피오라 급소처럼 방향이 랜덤 — 그건 다음 스텝) 성공 = 보스 피해 + 캐릭터가 반대편으로 관통 대시.
const COUNTER_OFFSET := 46.0    # F 표식이 뜨는 보스 중심으로부터 거리
const COUNTER_DAMAGE := 45      # 카운터 1회 피해
const EYE_OFFSET := Vector2(0.0, -6.0)   # 보스 눈 대략 위치(반짝 표시 지점)
# 시퀀스: 5초 → 눈 반짝 → 조준(보스가 바라보며 줄 생김) → 돌진(도중 F=카운터, 아니면 명중).
const COUNTER_INTERVAL := 5.0   # (미사용 — 자동 반복 폐기, 버튼 트리거로 전환)
const MAX_DASHES := 5           # 한 세트 = 보스 돌진 5번
const DASH_GAP := 0.8           # 돌진 후 회복 간격(s) — 그로기가 있으면 그로기가 대신
const FILLER_LEAD := 1.6        # 틈새 공격(장판 게이지/탄막) 시간 — 이게 끝나야 다음 돌진
const COUNTER_GLINT := 0.5      # 눈 반짝(s)
const CHARGE_AIM := 0.5         # 조준: 바라봄 + 줄 생김(s)
const CHARGE_SPEED := 1550.0    # 돌진 속도(px/s) — x2.5 (반응해서 패링 가능한 속도)
const DASH_DECEL := 11000.0     # 지나친 뒤 감속(px/s²) — 팔로스루 ~110px (급정지 끊김 방지)
# 진짜 패링: 돌진 중 보스가 근접하면 받아치기 창이 열리고, 그 안에서만 F 성공. 이른 F는 헛침(잠금).
const PARRY_OPEN_RANGE := 165.0 # 돌진 중 보스가 이 안이면 창 열림(여유 있게 미리)
const PARRY_WINDOW := 0.28      # 창 지속(s) — 이 안에 F. 돌진 끝에 안 잘리고 제 시간 유지
# 🔴 카운터/돌진은 tween으로 위치를 바꿔 벽 충돌을 우회 → 맵 밖으로 나감. 이 안전영역으로 클램프(벽 안쪽).
const ARENA_SAFE := Rect2(-566.0, 170.0, 1472.0, 308.0)
# 룬 자물쇠 3개 — 시야 콘에 들어온 활성 룬만 반짝, 그 원 안에서 패링 성공 시 "파훼".
const RUNE_POS: Array = [Vector2(430.0, 250.0), Vector2(630.0, 440.0), Vector2(830.0, 250.0)]
const RUNE_RADIUS := 50.0       # 이 안에서 패링해야 파훼 (링 크기와 맞춰 넉넉하게 — 가장자리 실패 방지)
var _runes: Array = []          # 각 원소 = {holder, pos}
var _active_rune: int = 0       # 반짝이는 활성 룬 인덱스(0~2)
var _parry_in_rune: bool = false  # 이번 패링이 활성 룬 안이었나 → 파훼 판정
var _groggy_label: Label = null   # 보스 위 "그로기중..." 표시
const CS_IDLE := 0
const CS_GLINT := 1
const CS_AIM := 2
const CS_DASH := 3
var _counter_marker: Node2D = null
var _counter_poly: Polygon2D = null
var _counter_label: Label = null
var _eye_glint: Node2D = null
var _eye_cores: Array = []      # 눈 핫 코어 2개 (충전 램프로 dim→hot)
var _eye_halos: Array = []      # 눈 바깥 헤일로 2개
var _dash_line: Line2D = null   # 돌진 위험선 — AIM/DASH 동안 보스 앞으로 뻗는 영혼 줄
var _soul_mote_last: float = 0.0 # 영혼 모트 마지막 스폰 시각(줄을 따라 흐르는 빛 알갱이 간격)
var _counter_t: float = 0.0     # 마커 맥동 위상
var _cstate: int = CS_IDLE
var _cstate_t: float = 0.0
var _charge_dir: Vector2 = Vector2.RIGHT     # 돌진 방향(조준 시 고정) — 이 방향으로 직진
var _charge_traveled: float = 0.0            # 돌진 이동 거리 안전 상한용
var _dash_speed: float = 0.0                 # 현재 돌진 속도 — 지나치면 감속(팔로스루)
var _parry_open_t: float = -1.0   # >=0 = 받아치기 창 열림 카운트다운, -1 = 아직 안 열림
var _parry_used: bool = false     # 이번 돌진에서 이른 F로 헛치면 잠금(스팸 방지)
var _in_rune_window: bool = false # 받아치기 창이 열린 동안 활성 룬 안에 한 번이라도 있었나 → 파훼 판정을 F 순간 한 프레임이 아니라 창 전체로 넓힌다(가장자리 이탈 방지)
var _break_rune: int = -1         # 이번 파훼로 깰 룬 인덱스(창 동안 올라선 룬을 래치) — 어느 룬이든 플레이어가 간 룬
var _broken_count: int = 0        # 이 패턴에서 깬 룬 수(0~3) — "N번째" 표시 + 3개 소진 판정
var _rune_diamond: Node2D = null  # 현재 타겟 룬 위에 뜨는 금색 다이아몬드 마커
var _dash_count: int = 0          # 이번 5돌진 세트에서 지나간 돌진 수(0~5)
var _next_dash_cd: float = 0.0    # 다음 돌진까지 쿨다운(s) — 그로기 중에도 흐른다(실패/성공 무관 3초 여유)
var _filler_alt: bool = false     # 틈새 공격 번갈아 (장판 유도 ↔ 원형 탄막)
var _filler_pending: bool = false # 다음 돌진 전에 틈새 공격 한 번 (회복 뒤 발동)
var _pattern_active: bool = false # 5돌진 세트 진행 중 (패턴 랩 버튼으로 시작)
var _pattern_label: Label = null  # "돌진 M/5 · 룬 N/3" 상태 표시
var _lock_linger: float = 0.0     # 잠금(빨간 ✕)을 눈에 보이게 잠깐 더 유지
var _clashing: bool = false       # 클래시(성공 연출) 진행 중 — 이때도 구르기 억제(연타 F가 tween과 충돌해 벽 뚫는 것 방지)
var _f_cd: float = 0.0            # 받아치기 F 쿨타임(0.15s) — 연타 방지(창보다 짧게)
# 룬 충전/전도 연출 — 활성 룬 위=오라 차오름(강화), 그 상태로 받아치기=룬→나→보스 기운 방출(전도). 전부 순수 표시.
var _rune_aura: Sprite2D = null   # 로컬 플레이어 자식 — 차오르는 청록 오라
var _rune_charge: float = 0.0     # 0→1 충전량(룬 위=차오름, 밖=사그라듦)
var _charge_particles: GPUParticles2D = null   # 룬→플레이어로 빨려 올라가는 기운 입자


func _ready() -> void:
	if not TestMode.is_active():
		queue_free()
		return
	# peer_sync가 플레이어를 call_deferred로 스폰하므로 한 프레임 뒤 셋업
	_setup.call_deferred()


func _setup() -> void:
	HealthComponent.force_damage_one = true   # 테스트 랩 — 모든 데미지 1 (프로덕션 무영향, 정적 플래그)
	_boss = get_parent().get_node_or_null("Boss")
	_coop = get_parent().get_node_or_null("CoopAuthority")
	if _boss != null:
		_boss.debug_hold = true       # 보스 자동공격 정지 (버튼으로만)
		_boss.speed_mult = 5.0        # 접근(추격) 속도 x5 (테스트) — 보스정지 해제 시 체감
	if _coop != null:
		_coop.debug_hold = true       # 코옵 자동순환 정지 (버튼으로만)
		# 상단 코옵 디버그 상태줄(버전·boss·인원·host next) 숨김 — 랩 화면 정리(마스터 실플레이엔 무접촉).
		var coop_status := _coop.get("_status") as CanvasItem
		if coop_status != null:
			coop_status.visible = false
	_apply_invincible()
	_spawn_npc()
	_reposition()             # 보스·NPC=보스 방, 플레이어=진입 방
	_build_bounds()           # 2방 벽 + 진입 방 바닥 + 바깥 void
	_setup_vision()           # 조준 방향 시야 콘 (로컬 플레이어)
	_setup_counter()          # 카운터 약점(F 표식) — 테스트: 플레이어 쪽에 상시
	_setup_runes()            # 룬 자물쇠 3개 (시야로 활성화, 안에서 패링=파훼)
	_setup_rune_charge()      # 룬 충전 입자 (활성 룬에서 위로 빨려 올라감)
	_setup_camera()           # 방 카메라 (클램프+스냅)
	_setup_lighting()         # 2D 라이팅 — 어두운 성역 + 발광 지점(맵 퀄업)
	_apply_boss_rim()         # 보스 밝은 림(뒤 실루엣) — 청록 배경에서 또렷하게
	_setup_particles()        # 떠다니는 데이터 모트 (공간감)
	_setup_floor_detail()     # 바닥 데이터 글리프 디테일 (가장자리 위주)
	_setup_altar_feature()    # ④ 제단 발광 룬 서클(맥동+회전) — 보스 발밑
	_setup_overlay()          # ① 풀스크린 포스트 오버레이 (비네트+틴트+스캔라인 = "시스템 안")
	EventBus.boss_phase_changed.connect(_on_boss_phase)   # ⑤ 페이즈2 → 환경 오염
	_setup_boss_hpbar()       # 상단 글리치 보스 HP바
	_build_panel()


# ③ 공기 채우기 — 3겹: ⑴ 부유 모트(공간감) ⑵ 표류 코드 조각(데이터 질감) ⑶ 데이터 레인(세로 흐름).
const PARTICLE_RECT := Rect2(-620.0, 60.0, 1640.0, 520.0)   # 세 레이어 공용 가시 영역(두 방 아우름)
func _setup_particles() -> void:
	# ⑴ 부유 데이터 모트 — 청록 입자가 느리게 위로 부유.
	var p := GPUParticles2D.new()
	p.amount = 90
	p.lifetime = 7.0
	p.preprocess = 4.0
	p.texture = _light_tex()
	p.z_index = 6
	p.modulate = Color(0.45, 0.62, 0.8, 0.38)   # 청록 완화 → 배경 부유 입자가 보스와 안 겹침
	p.visibility_rect = PARTICLE_RECT
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(768.0, 224.0, 1.0)
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 50.0
	m.gravity = Vector3(0.0, -5.0, 0.0)
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 9.0
	m.scale_min = 0.015
	m.scale_max = 0.05
	p.process_material = m
	get_parent().add_child(p)
	p.global_position = Vector2(192.0, 324.0)
	_add_code_fragments()
	_add_data_rain()


# ⑵ 표류 코드 조각 — 작은 사각 비트가 천천히 옆으로 흐른다(데이터가 공간을 떠도는 질감).
func _add_code_fragments() -> void:
	var p := GPUParticles2D.new()
	p.amount = 48
	p.lifetime = 9.0
	p.preprocess = 5.0
	p.texture = _square_tex()
	p.z_index = 5
	p.modulate = Color(0.4, 0.85, 0.7, 0.5)
	p.visibility_rect = PARTICLE_RECT
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(768.0, 224.0, 1.0)
	m.direction = Vector3(1.0, 0.0, 0.0)      # 옆으로 표류
	m.spread = 30.0
	m.gravity = Vector3(3.0, -1.0, 0.0)       # 살짝 오른쪽·아주 살짝 위
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 12.0
	m.scale_min = 1.0
	m.scale_max = 2.5
	m.angle_min = 0.0
	m.angle_max = 360.0
	p.process_material = m
	get_parent().add_child(p)
	p.global_position = Vector2(192.0, 324.0)


# ⑶ 데이터 레인 — 가는 세로 줄기가 위에서 아래로 빠르게 흐른다(간헐적, 손상 시스템의 데이터 낙하).
func _add_data_rain() -> void:
	var p := GPUParticles2D.new()
	p.amount = 34
	p.lifetime = 2.6
	p.preprocess = 2.0
	p.texture = _streak_tex()
	p.z_index = 5
	p.modulate = Color(0.5, 0.95, 0.8, 0.32)
	p.visibility_rect = PARTICLE_RECT
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(768.0, 20.0, 1.0)
	m.direction = Vector3(0.0, 1.0, 0.0)      # 아래로
	m.spread = 4.0
	m.gravity = Vector3(0.0, 60.0, 0.0)
	m.initial_velocity_min = 90.0
	m.initial_velocity_max = 160.0
	m.scale_min = 0.7
	m.scale_max = 1.6
	p.process_material = m
	get_parent().add_child(p)
	p.global_position = Vector2(192.0, 90.0)   # 위쪽에서 방출


# ③ 바닥 데이터 글리프 — 작은 룬/코드 조각을 방 가장자리·중간 링에 산재(중앙 전장은 비움 = FX 안 묻힘).
# 데칼 시트 8칸(24×24 그리드) — floor_decals.png
const DECAL_REGIONS := [
	Rect2(0, 0, 24, 24), Rect2(24, 0, 24, 24), Rect2(48, 0, 24, 24), Rect2(72, 0, 24, 24),
	Rect2(0, 24, 24, 24), Rect2(24, 24, 24, 24), Rect2(48, 24, 24, 24), Rect2(72, 24, 24, 24),
]

# 선택된 4종만 어울리게 배치 (1 코드룬A · 2 코드룬B · 5 균열 · 10 큰룬사인). 중앙 전장은 비움.
func _setup_floor_detail() -> void:
	var decals: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/stage/floor_decals.png"):
		decals = load("res://assets/sprites/stage/floor_decals.png")
	var objects: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/stage/floor_objects.png"):
		objects = load("res://assets/sprites/stage/floor_objects.png")
	# 10 큰룬사인 (feature) — 각 방 바닥에 크게, 중앙 피함
	if objects != null:
		for p: Vector2 in [Vector2(-390, 320), Vector2(120, 205), Vector2(430, 445), Vector2(770, 300)]:
			_scatter(objects, Rect2(48, 0, 48, 48), p, 1.5, false)
	if decals != null:
		# 1 코드룬A
		for p: Vector2 in [Vector2(-500, 180), Vector2(-250, 460), Vector2(40, 190), Vector2(330, 175), Vector2(650, 465), Vector2(900, 200)]:
			_scatter(decals, Rect2(0, 0, 24, 24), p, 2.0, true)
		# 2 코드룬B
		for p: Vector2 in [Vector2(-420, 455), Vector2(-120, 165), Vector2(-540, 320), Vector2(470, 480), Vector2(560, 155), Vector2(940, 440)]:
			_scatter(decals, Rect2(24, 0, 24, 24), p, 2.0, true)
		# 5 균열
		for p: Vector2 in [Vector2(-330, 485), Vector2(-90, 470), Vector2(230, 450), Vector2(700, 165), Vector2(820, 480), Vector2(280, 160)]:
			_scatter(decals, Rect2(0, 24, 24, 24), p, 2.3, true)


func _scatter(sheet: Texture2D, region: Rect2, pos: Vector2, sc: float, rot: bool) -> void:
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = region
	var sp := Sprite2D.new()
	sp.texture = at
	if rot:
		sp.rotation = randf() * TAU
	sp.scale = Vector2.ONE * (sc * (0.85 + randf() * 0.35))
	# 어둡고 남색기 도는 저채도 → 청록 보스와 경쟁하지 않음
	sp.modulate = Color(0.55, 0.68, 0.78, 0.4 + randf() * 0.2)
	sp.z_index = -8
	get_parent().add_child(sp)
	sp.global_position = pos


# ① 풀스크린 포스트 오버레이 — "손상된 시스템 안" 룩(비네트+옅은 틴트+움직이는 스캔라인).
# ColorRect 한 장 + 셰이더. HUD(별도 CanvasLayer) 위로 살짝 덮이지만 텍스트는 외곽선이 있어 읽힌다.
var _overlay_mat: ShaderMaterial = null   # ⑤ 페이즈2 오염에서 corruption uniform을 올릴 핸들
func _setup_overlay() -> void:
	if not ResourceLoader.exists("res://assets/shaders/system_overlay.gdshader"):
		return
	var layer := CanvasLayer.new()
	layer.layer = 2   # 월드(0) 위, 패널(20)/힌트(19) 아래
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 입력 안 막음
	rect.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/system_overlay.gdshader")
	# 🔴 uniform 전부 명시 심기 (기본값 의존 금지 — 웹 Compatibility 검정 렌더 함정, boss/hit_flash 규율)
	mat.set_shader_parameter(&"vignette_strength", 0.38)
	mat.set_shader_parameter(&"vignette_start", 0.35)
	mat.set_shader_parameter(&"vignette_end", 0.95)
	mat.set_shader_parameter(&"vignette_color", Color(0.02, 0.03, 0.05))
	mat.set_shader_parameter(&"tint_color", Color(0.10, 0.25, 0.28))
	mat.set_shader_parameter(&"tint_amount", 0.06)
	mat.set_shader_parameter(&"scan_amount", 0.05)
	mat.set_shader_parameter(&"scan_count", 220.0)
	mat.set_shader_parameter(&"scan_speed", 8.0)
	mat.set_shader_parameter(&"corruption", 0.0)
	rect.material = mat
	layer.add_child(rect)
	_overlay_mat = mat


# 상단 글리치 보스 HP바 — 이름 "Ghost Nos"(크로매틱 글리치) + 노이즈 채움바. 상단 10% 중앙정렬.
# enemy_hp_confirmed(eid, hp) 구독으로 채움 갱신. 전체를 CanvasLayer.offset로 미세 노이즈 진동.
func _setup_boss_hpbar() -> void:
	_boss_hp_layer = CanvasLayer.new()
	_boss_hp_layer.layer = 6   # 오버레이(2) 위, 힌트(19)/패널(20) 아래
	add_child(_boss_hp_layer)
	if _boss != null:
		_boss_max_hp = maxi(1, int(_boss.get("_max_hp")))
	# 이름 — 3중 라벨(시안/마젠타 뒤 + 흰 앞 = 크로매틱 글리치)
	var name_holder := Control.new()
	name_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_holder.anchor_left = 0.5
	name_holder.anchor_right = 0.5
	name_holder.anchor_top = HPBAR_TOP_PCT
	name_holder.anchor_bottom = HPBAR_TOP_PCT
	name_holder.offset_left = -HPBAR_W * 0.5
	name_holder.offset_right = HPBAR_W * 0.5
	name_holder.offset_top = 0.0
	name_holder.offset_bottom = 26.0
	_boss_hp_layer.add_child(name_holder)
	# 🔴 시안/마젠타 색수차는 이 게임 팔레트(차가운 청록 뮤트)에 없어 튄다 — 뺐다(projectb-art 팔레트 규율).
	# 대신 은은한 어두운 오프셋 하나 = 살짝 어긋난 글리치 느낌만 남긴다.
	_add_name_label(name_holder, Vector2(1.5, 1.5), Color(0.05, 0.02, 0.03, 0.6))   # 어두운 오프셋
	_add_name_label(name_holder, Vector2(0, 0), Color(0.9, 0.94, 0.96, 1.0))        # 흰 앞

	# HP바 — 어두운 테두리 패널 + 글리치 채움 + 수치 텍스트
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = HPBAR_TOP_PCT
	panel.anchor_bottom = HPBAR_TOP_PCT
	panel.offset_left = -HPBAR_W * 0.5
	panel.offset_right = HPBAR_W * 0.5
	panel.offset_top = 28.0
	panel.offset_bottom = 28.0 + HPBAR_H
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.BAR_BG                    # HUD 바탕과 동일 (정본 팔레트)
	sb.border_color = Color(0.5, 0.2, 0.22, 0.75)  # 뮤트 어두운 빨강 테두리
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	_boss_hp_layer.add_child(panel)

	_boss_hp_innerw = HPBAR_W - 4.0
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2(2, 2)
	fill.size = Vector2(_boss_hp_innerw, HPBAR_H - 4.0)
	if ResourceLoader.exists("res://assets/shaders/glitch_bar.gdshader"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/glitch_bar.gdshader")
		# 넓은 바라 정본 빨강도 화면상 공격적 → 살짝 어둡게 + 번쩍임 제거해 평평하고 차분하게.
		mat.set_shader_parameter(&"base_color", Color(0.62, 0.13, 0.13))  # HP_FILL보다 조금 어두운 빨강(눈에 덜 쏜다)
		mat.set_shader_parameter(&"hi_color", UiTheme.HP_FILL)            # 셰이딩 상단만 정본 빨강까지 (밝게 안 튐)
		mat.set_shader_parameter(&"rows", 6.0)
		mat.set_shader_parameter(&"scan_speed", 2.5)
		mat.set_shader_parameter(&"noise_amt", 0.06)   # 노이즈 흔적만
		mat.set_shader_parameter(&"glitch_amt", 0.0)   # 번쩍이는 다크밴드 제거 (불쾌감의 주범)
		fill.material = mat
	panel.add_child(fill)
	_boss_hp_fill = fill

	var hp_text := Label.new()
	hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_text.add_theme_font_size_override("font_size", 10)
	hp_text.add_theme_color_override("font_color", Color(0.95, 1.0, 0.98))
	hp_text.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	hp_text.add_theme_constant_override("outline_size", 3)
	panel.add_child(hp_text)
	_boss_hp_text = hp_text

	EventBus.enemy_hp_confirmed.connect(_on_boss_hp)
	_set_boss_hp(_boss_max_hp)   # 초기 = 풀


func _add_name_label(holder: Control, shift: Vector2, col: Color) -> void:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = BOSS_NAME
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = shift.x
	l.offset_right = shift.x
	l.offset_top = shift.y
	l.offset_bottom = shift.y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", col)
	if col.a >= 1.0:   # 앞(흰) 라벨만 외곽선 — 뒤 오프셋은 번지게 둔다
		l.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
		l.add_theme_constant_override("outline_size", 4)
	holder.add_child(l)


# enemy_hp_confirmed(eid, hp) — 이 보스면 채움/수치 갱신.
func _on_boss_hp(eid: String, hp: int) -> void:
	if _boss == null or eid != String(_boss.get("eid")):
		return
	_set_boss_hp(hp)


func _set_boss_hp(hp: int) -> void:
	var ratio := clampf(float(hp) / float(maxi(1, _boss_max_hp)), 0.0, 1.0)
	if _boss_hp_fill != null:
		_boss_hp_fill.size.x = _boss_hp_innerw * ratio
	if _boss_hp_text != null:
		_boss_hp_text.text = "%d / %d" % [maxi(hp, 0), _boss_max_hp]


# 2D 라이팅 — CanvasModulate로 씬을 어둡게 하고, 룬·제단·대문·균열이 빛나게(PointLight2D 가산).
# 배경(아레나 Sprite2D)이 조명을 받는다(2d-essentials §4·§10). Compatibility에서 작동.
func _light_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


# ④ 제단 발광 룬 서클 — 보스 발밑(852,324)에 발광 고리. 천천히 돌고 맥동한다(제단에 강림한 무게감).
var _altar_ring: Sprite2D = null
var _altar_ring2: Sprite2D = null   # 반대로 도는 안쪽 고리 (이중 링 = 마법진)
func _setup_altar_feature() -> void:
	_altar_ring = _make_ring(Vector2(852.0, 324.0), 260.0, Color(0.35, 0.85, 0.72, 0.5))
	_altar_ring2 = _make_ring(Vector2(852.0, 324.0), 150.0, Color(0.5, 0.95, 0.8, 0.45))


func _make_ring(pos: Vector2, diameter: float, col: Color) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = _ring_tex()
	sp.z_index = -7                     # 바닥(-10) 위, 데칼(-8) 위, 몸(0) 아래
	sp.modulate = col
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = mat
	sp.scale = Vector2.ONE * (diameter / 128.0)   # 링 텍스처 128px 기준
	get_parent().add_child(sp)
	sp.global_position = pos
	return sp


# 발광 고리(밴드) 텍스처 — 방사 그라디언트: 중심 투명 → 바깥쪽에서 밝은 밴드 → 가장자리 투명.
func _ring_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.78, 0.92, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


# 코드 조각용 작은 사각 텍스처(4×4 흰색) — GPUParticles가 스케일로 키운다.
func _square_tex() -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


# 데이터 레인용 가는 세로 줄기(1×10 흰색, 위 옅고 아래 진하게).
func _streak_tex() -> ImageTexture:
	var img := Image.create(1, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		img.set_pixel(0, y, Color(1, 1, 1, 0.2 + 0.8 * (float(y) / 9.0)))
	return ImageTexture.create_from_image(img)


func _add_light(pos: Vector2, col: Color, energy: float, scale: float, parent: Node = null) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _light_tex()
	l.color = col
	l.energy = energy
	l.texture_scale = scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	if parent != null:
		parent.add_child(l)
		l.position = pos
	else:
		get_parent().add_child(l)
		l.global_position = pos
	return l


# ④ 제단 룬 서클 — 두 고리가 반대로 천천히 돌고 알파가 맥동한다(마법진 강림).
func _animate_altar(delta: float) -> void:
	if _altar_ring != null and is_instance_valid(_altar_ring):
		_altar_ring.rotation += delta * 0.25
		_altar_ring.modulate.a = 0.5 + 0.14 * sin(_env_t * TAU * 0.4)
	if _altar_ring2 != null and is_instance_valid(_altar_ring2):
		_altar_ring2.rotation -= delta * 0.4
		_altar_ring2.modulate.a = 0.45 + 0.16 * sin(_env_t * TAU * 0.55 + 1.5)


# ② 환경 빛 맥동+깜빡 — base_energy에 느린 사인(숨쉬기) + 노이즈 깜빡(손상 전력). 라이트마다 위상 다름.
func _animate_lights(delta: float) -> void:
	if _env_lights.is_empty():
		return
	if _env_noise == null:
		_env_noise = FastNoiseLite.new()
		_env_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_env_noise.frequency = 1.0
	for i in _env_lights.size():
		var e: Dictionary = _env_lights[i]
		var l := e["l"] as PointLight2D
		if not is_instance_valid(l):
			continue
		var base: float = e["base"]
		var breathe := 1.0 + float(e["amp"]) * sin(_env_t * TAU * float(e["hz"]) + float(e["phase"]))
		# 깜빡 — 빠른 노이즈가 음수 문턱 아래로 떨어질 때만 살짝 꺼진다(손상 전력). 라이트별 표본 좌표 분리.
		var n := _env_noise.get_noise_1d(_env_t * 9.0 + float(i) * 100.0)
		var flick := 1.0 - maxf(0.0, -n - 0.35) * float(e["flick"]) * 3.0
		# 페이즈2에도 조명은 청록 유지 (붉은 적화 제거 — 화면 빨개짐 없앰, 사용자 요청)
		l.color = e["col"]
		l.energy = base * breathe * maxf(flick, 0.2)


func _setup_lighting() -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.18, 0.18, 0.23)   # 살짝 밝게 (공격 가독성 — 너무 어두우면 FX가 묻힌다)
	get_parent().add_child(cm)
	# 성역 발광 지점 — 청록이 아니라 차분한 남색으로(에너지↓) → 보스의 청록만 유일하게 밝은 청록이 됨.
	# ② 각 빛을 참조로 잡아 숨쉬게(맥동)+깜빡이게(_animate_lights). base_energy·위상·주기를 달리해 제각각 뛴다.
	var altar := _add_light(Vector2(852.0, 324.0), Color(0.28, 0.46, 0.62), 1.1, 2.1)   # 제단/룬
	var gate := _add_light(Vector2(150.0, 324.0), Color(0.3, 0.48, 0.66), 1.0, 1.7)     # 대문 빛
	var rift := _add_light(Vector2(-500.0, 300.0), Color(0.32, 0.48, 0.6), 1.0, 1.3)    # 진입 균열
	_env_lights = [
		{"l": altar, "base": 1.1, "hz": 0.45, "amp": 0.16, "phase": 0.0, "flick": 0.10, "col": Color(0.28, 0.46, 0.62)},
		{"l": gate, "base": 1.0, "hz": 0.7, "amp": 0.12, "phase": 2.1, "flick": 0.22, "col": Color(0.3, 0.48, 0.66)},    # 대문은 더 불안정
		{"l": rift, "base": 1.0, "hz": 0.55, "amp": 0.2, "phase": 4.0, "flick": 0.30, "col": Color(0.32, 0.48, 0.6)},    # 균열은 가장 손상
	]
	# 플레이어 따라다니는 빛 (시야 확보 — 은은하게, 캐릭터가 하얗게 뜨지 않게)
	var lp := _local_player()
	if lp != null:
		_add_light(Vector2.ZERO, Color(0.8, 0.84, 0.95), 1.0, 1.3, lp)
	# 보스 으스스한 빛 — 배경 청록을 죽였으니 여기가 가장 밝은 청록이 되어 보스가 튄다 (은은하게)
	if _boss != null:
		_add_light(Vector2.ZERO, Color(0.5, 0.9, 0.78), 1.2, 1.15, _boss)


# A. 보스 밝은 림 — 같은 SpriteFrames를 공유하는 뒤쪽 실루엣을 살짝 키워 발광시킨다.
#    아틀라스 시트라 아웃라인 셰이더는 이웃 프레임을 샘플해 번지므로, 복제 실루엣 + _process 프레임 동기화로.
func _apply_boss_rim() -> void:
	if _boss == null:
		return
	var spr := _boss.get_node_or_null("Sprite") as AnimatedSprite2D
	if spr == null or spr.sprite_frames == null:
		return
	spr.z_index = 2                     # 실제 스프라이트를 림 위로
	var rim := AnimatedSprite2D.new()
	rim.sprite_frames = spr.sprite_frames
	rim.scale = spr.scale * 1.08        # 살짝 크게 → 테두리만 삐져나옴 (은은하게)
	rim.z_index = 1                     # 실루엣은 보스 바로 뒤 (그림자 -2 · 텔레그래프 -1 위)
	rim.modulate = Color(0.4, 0.8, 0.66, 0.5)   # 은은한 청록 발광 (반투명)
	rim.material = CanvasItemMaterial.new()
	(rim.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.add_sibling(rim)
	rim.position = spr.position
	_boss_rim = rim


# 시야 콘 — 로컬 플레이어 자식으로 붙여 조준각(_aim_angle)만큼 돌린다(_process). 스케치처럼 V자 경계선 +
# 어두운 바닥에서 방향이 읽히게 은은한 가산 발광 채움(부채꼴). 입력 안 먹음(Line2D/Polygon2D는 무해).
func _setup_vision() -> void:
	_ensure_vision(_local_player())


# 시야 콘이 현재 로컬 플레이어에 없으면 만든다 — 부활/재스폰으로 몸이 새 노드로 갈려도 자동 복구.
func _ensure_vision(lp: Node) -> void:
	if lp == null:
		return
	var existing := lp.get_node_or_null("VisionCone")
	if existing != null:
		_vision = existing as Node2D
		return
	var holder := Node2D.new()
	holder.name = "VisionCone"
	holder.z_index = -1   # 바닥(-8) 위, 플레이어 몸(0) 아래 — 캐릭터를 안 가림
	lp.add_child(holder)
	# 부채꼴 채움 (가산 발광) — 시야 안을 은은하게 밝힌다
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	pts.append(Vector2(VISION_R0, 0.0).rotated(-VISION_HALF))
	var steps := 12
	for i in steps + 1:
		var a: float = lerpf(-VISION_HALF, VISION_HALF, float(i) / float(steps))
		pts.append(Vector2(VISION_LEN, 0.0).rotated(a))
	pts.append(Vector2(VISION_R0, 0.0).rotated(VISION_HALF))
	poly.polygon = pts
	poly.color = Color(1, 1, 1, 1)
	# apex(플레이어 쪽)는 밝고 바깥 호는 페이드 = 손전등 같은 시야 빔. 가산 블렌드라 알파가 곧 밝기.
	var vcols := PackedColorArray()
	var inner := Color(0.55, 0.78, 0.95, 0.30)
	var outer := Color(0.45, 0.66, 0.85, 0.015)
	vcols.append(inner)                       # inner-left
	for _i in steps + 1:
		vcols.append(outer)                   # outer arc
	vcols.append(inner)                       # inner-right
	poly.vertex_colors = vcols
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	poly.material = pm
	holder.add_child(poly)
	# 경계선 두 개 (스케치의 V) — 시작은 밝고 끝으로 갈수록 페이드(시야 광선 느낌)
	var lg := Gradient.new()
	lg.set_color(0, Color(0.6, 0.85, 1.0, 0.5))
	lg.set_color(1, Color(0.6, 0.85, 1.0, 0.0))
	for s: float in [-1.0, 1.0]:
		var ln := Line2D.new()
		ln.points = PackedVector2Array([
			Vector2(VISION_R0, 0.0).rotated(s * VISION_HALF),
			Vector2(VISION_LEN, 0.0).rotated(s * VISION_HALF),
		])
		ln.width = 2.0
		ln.gradient = lg
		ln.material = pm
		holder.add_child(ln)
	_vision = holder


# 룬 자물쇠 3개 — 원(링) + 자물쇠 글리프. 활성 1개는 시야 콘에 들어오면 반짝, 그 안 패링=파훼.
func _setup_runes() -> void:
	# 보스 위 "그로기중..." 라벨 (그로기 동안만 보임)
	_groggy_label = Label.new()
	_groggy_label.add_theme_font_size_override("font_size", 15)
	_groggy_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_groggy_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_groggy_label.add_theme_constant_override("outline_size", 4)
	_groggy_label.z_index = 12
	_groggy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_groggy_label.visible = false
	get_parent().add_child(_groggy_label)
	_runes.clear()
	for i in RUNE_POS.size():
		var made := _make_rune_lock(RUNE_POS[i])
		_runes.append({"holder": made["holder"], "label": made["label"], "pos": RUNE_POS[i], "num": i + 1,
			"shackle": made["shackle"], "shackle_pos0": (made["shackle"] as Node2D).position, "unlocking": false})
	_active_rune = -1        # 활성 룬 = 플레이어가 올라선 룬(동적) — 매 프레임 _update_runes가 갱신
	_broken_count = 0
	_setup_rune_diamond()


func _make_rune_lock(pos: Vector2) -> Dictionary:
	var holder := Node2D.new()
	holder.z_index = -6
	get_parent().add_child(holder)
	holder.global_position = pos
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 링(원)
	var ring := Sprite2D.new()
	ring.texture = _ring_tex()
	ring.scale = Vector2.ONE * (100.0 / 128.0)   # 링 지름 ~100px = 판정 반경(50)과 맞춤
	ring.modulate = Color(0.3, 0.7, 0.6, 0.4)
	ring.material = add
	holder.add_child(ring)
	# 자물쇠 몸통(사각)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-6, -1), Vector2(6, -1), Vector2(6, 9), Vector2(-6, 9)])
	body.color = Color(0.4, 0.85, 0.7, 0.55)
	body.material = add
	holder.add_child(body)
	# 자물쇠 고리(shackle, 반원)
	var shackle := Line2D.new()
	var pts := PackedVector2Array()
	for i in 9:
		var a: float = PI * float(i) / 8.0
		pts.append(Vector2(cos(a) * 4.5, -sin(a) * 5.0 - 1.0))
	shackle.points = pts
	shackle.width = 2.0
	shackle.default_color = Color(0.4, 0.85, 0.7, 0.55)
	shackle.material = add
	holder.add_child(shackle)
	# 라벨 — 룬 구분/타겟 표시용. holder 밖(스테이지 직속)에 붙여 회색/금색 modulate에 안 눌리고 항상 읽히게.
	var lbl := Label.new()
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.z_index = 10
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(lbl)
	lbl.global_position = pos + Vector2(-18.0, -44.0)
	return {"holder": holder, "label": lbl, "shackle": shackle}


# 매 프레임 — 활성 룬이 시야 콘 안이면 강렬한 금색 "격파!", 나머지·시야밖은 회색 "룬 N". (호출: _process)
func _update_runes(lp: PlayerActor) -> void:
	_active_rune = _current_rune(lp)   # 활성 = 플레이어가 올라선 룬(동적)
	for i in _runes.size():
		if _runes[i].get("unlocking", false):
			continue   # 깨진(사라진) 룬 — 덮지 않는다
		var holder := _runes[i]["holder"] as Node2D
		var lbl := _runes[i]["label"] as Label
		if holder == null or not is_instance_valid(holder):
			continue
		if i == _active_rune:
			holder.scale = Vector2.ONE * (1.15 + 0.08 * sin(_counter_t * TAU * 1.5))
			holder.modulate = Color(2.2, 1.9, 0.5, 1.0)   # 올라선 룬 = 타겟 금색
			lbl.text = ""   # "N번째"는 위의 다이아몬드가 표시 (중복 방지)
		else:
			holder.scale = Vector2.ONE
			holder.modulate = Color(0.5, 0.55, 0.55, 0.45)   # 안 깨진 대기 룬(회색)
			lbl.text = "룬"
			lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.8))
			lbl.add_theme_font_size_override("font_size", 11)


func _rune_in_vision(lp: PlayerActor, rune_pos: Vector2) -> bool:
	var to_r: Vector2 = rune_pos - lp.global_position
	if to_r.length() > VISION_LEN:
		return false
	var aim: float = float(lp.get("_aim_angle"))
	return absf(wrapf(to_r.angle() - aim, -PI, PI)) <= VISION_HALF


# 보스가 플레이어 시야 콘(~90°) 안에 있나 — 받아치기 성공의 전제(보스를 조준해야 카운터가 먹힌다).
func _boss_in_vision(lp: PlayerActor) -> bool:
	if _boss == null:
		return false
	var to_b: Vector2 = _boss.global_position - lp.global_position
	var aim: float = float(lp.get("_aim_angle"))
	return absf(wrapf(to_b.angle() - aim, -PI, PI)) <= VISION_HALF


# 플레이어가 올라선 '안 깨진' 룬의 인덱스 (없으면 -1). 어느 룬이든 가면 그게 활성이 된다.
func _current_rune(lp: PlayerActor) -> int:
	var best := -1
	var best_d := RUNE_RADIUS
	for i in _runes.size():
		if _runes[i].get("unlocking", false):
			continue   # 이미 깨진(사라진) 룬 제외
		var d := lp.global_position.distance_to(_runes[i]["pos"])
		if d <= best_d:
			best_d = d
			best = i
	return best


func _player_in_active_rune(lp: PlayerActor) -> bool:
	return _current_rune(lp) >= 0


# 현재 타겟 룬 위에 뜨는 금색 다이아몬드 마커 + "N번째". 플레이어가 올라선 룬을 따라 이동.
func _setup_rune_diamond() -> void:
	var d := Node2D.new()
	d.name = "RuneDiamond"
	d.z_index = 9
	d.visible = false
	get_parent().add_child(d)
	var poly := Polygon2D.new()
	var s := 11.0
	poly.polygon = PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)])
	poly.color = Color(1.0, 0.85, 0.35, 0.9)
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	poly.material = pm
	d.add_child(poly)
	var lbl := Label.new()
	lbl.name = "Ord"
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(-16.0, -32.0)
	d.add_child(lbl)
	_rune_diamond = d
	# 패턴 상태 라벨 (월드) — "돌진 M/5 · 룬 N/3"
	var pl := Label.new()
	pl.add_theme_font_size_override("font_size", 13)
	pl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	pl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	pl.add_theme_constant_override("outline_size", 4)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pl.z_index = 12
	pl.visible = false
	get_parent().add_child(pl)
	_pattern_label = pl


# 다이아몬드를 현재 타겟 룬 위로 옮기고 "N번째" 표시. 보스 그로기/패턴 소진 시 숨김. (호출: _process)
func _update_rune_diamond() -> void:
	if _rune_diamond == null or not is_instance_valid(_rune_diamond):
		return
	var groggy: bool = _boss != null and float(_boss.get("groggy_left")) > 0.0
	var vis: bool = _active_rune >= 0 and _active_rune < _runes.size() and not groggy and not _runes[_active_rune].get("unlocking", false)
	_rune_diamond.visible = vis
	if vis:
		_rune_diamond.global_position = _runes[_active_rune]["pos"] + Vector2(0.0, -30.0)
		_rune_diamond.scale = Vector2.ONE * (1.0 + 0.14 * sin(_counter_t * TAU * 1.2))
		var lbl := _rune_diamond.get_node_or_null("Ord") as Label
		if lbl != null:
			lbl.text = "격파"   # 순서 무관 — "이 룬 깨라" 표식
	# 패턴 상태 — "돌진 M/5 · 룬 N/3" (세트 진행 중만)
	if _pattern_label != null and is_instance_valid(_pattern_label):
		_pattern_label.visible = _pattern_active
		if _pattern_active and _boss != null:
			_pattern_label.text = "놓침 %d/%d · 룬 %d/3" % [_dash_count, MAX_DASHES, _broken_count]
			_pattern_label.global_position = _boss.global_position + Vector2(-56.0, -104.0)


func _setup_rune_charge() -> void:
	# 룬 충전 입자 — 활성 룬에서 위로 빨려 올라가는 기운. 활성+플레이어 근접일 때만 방출.
	var p := GPUParticles2D.new()
	p.amount = 16
	p.lifetime = 1.3
	p.texture = _light_tex()
	p.z_index = 7
	p.emitting = false
	p.modulate = Color(1.0, 0.85, 0.4, 0.42)   # 옅게
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = RUNE_RADIUS * 0.8
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 12.0
	m.gravity = Vector3(0.0, -28.0, 0.0)   # 위로 천천히
	m.initial_velocity_min = 12.0
	m.initial_velocity_max = 30.0
	m.scale_min = 0.02
	m.scale_max = 0.07
	p.process_material = m
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	get_parent().add_child(p)
	_charge_particles = p


# 충전 오라 — 로컬 플레이어 자식으로 붙는 청록 발광. 부활/재스폰으로 몸이 갈려도 자동 복구(시야 콘과 같은 패턴).
func _ensure_rune_aura(lp: Node) -> void:
	if lp == null:
		return
	var existing := lp.get_node_or_null("RuneAura")
	if existing != null:
		_rune_aura = existing as Sprite2D
		return
	var s := Sprite2D.new()
	s.name = "RuneAura"
	s.texture = _light_tex()
	s.z_index = -1   # 몸(0) 뒤 — 캐릭터를 감싸는 발광
	s.modulate = Color(1.0, 0.82, 0.35, 0.0)   # 금색 — 활성 룬(★격파★)과 같은 색 언어(보스 청록과 분리)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = cm
	s.scale = Vector2.ONE * 0.5
	lp.add_child(s)
	_rune_aura = s


# 활성 룬 위에서 오라가 차오르고(강화 affordance), 밖으로 나가면 사그라든다. 순수 표시(판정 무영향).
# 호출: _process(_update_runes 다음 — 발밑 룬 강조를 반짝 위에 덧대기 위해).
func _update_rune_charge(lp: PlayerActor, delta: float) -> void:
	_ensure_rune_aura(lp)
	var in_rune: bool = _player_in_active_rune(lp)
	_rune_charge = move_toward(_rune_charge, 1.0 if in_rune else 0.0, delta / 0.45)   # 천천히 차오르고 사그라듦
	# 오라 — 충전량에 비례해 밝고 크게 + 아주 느린 숨쉬기(요란하지 않게)
	if _rune_aura != null and is_instance_valid(_rune_aura):
		var pulse := 1.0 + 0.05 * sin(_counter_t * TAU * 0.8)
		_rune_aura.modulate.a = _rune_charge * 0.55
		_rune_aura.scale = Vector2.ONE * (0.30 + 0.28 * _rune_charge) * pulse
	# 무기 발광 — 충전 시 청백으로 달아오름(무기 노드 있으면)
	var wpn := lp.get_node_or_null("WeaponPivot/Weapon") as CanvasItem
	if wpn != null:
		wpn.self_modulate = Color(1, 1, 1).lerp(Color(2.1, 1.8, 1.1), _rune_charge)   # 금백으로 달아오름
	# 룬 입자 — 활성 룬 위로, 서 있을 때만 방출
	if _charge_particles != null and is_instance_valid(_charge_particles):
		if _active_rune >= 0 and _active_rune < _runes.size():
			_charge_particles.global_position = _runes[_active_rune]["pos"]
		_charge_particles.emitting = in_rune
	# 발밑 활성 룬을 충전 중 더 밝게 (반짝 연출 위에 덧댐)
	if in_rune and _active_rune >= 0 and _active_rune < _runes.size() and not _runes[_active_rune].get("unlocking", false):
		var holder := _runes[_active_rune]["holder"] as Node2D
		if holder != null and is_instance_valid(holder):
			holder.scale = Vector2.ONE * (1.15 + 0.08 * sin(_counter_t * TAU * 1.2))   # 느리고 작은 맥동
			holder.modulate = Color(2.6, 2.2, 0.7, 1.0)


# 파훼 방출 — 활성 룬에서 금색 봉인 기둥이 솟구치고 확산 링이 퍼진다(+ 보스로 짧은 방향 볼트).
# 🔴 파훼 순간엔 룬·플레이어·보스가 한 곳에 뭉쳐 있어 "룬→보스 빔"은 짧아 안 읽힌다 →
#    룬 중심의 방출(기둥+링)로 "이 자리가 힘을 터뜨렸다 → 보스 그로기"를 보여준다.
func _conduit_beam(idx: int) -> void:
	if _boss == null or idx < 0 or idx >= _runes.size():
		return
	var from: Vector2 = _runes[idx]["pos"]
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 은은한 금색 봉인 해제 파문 — 룬에서 천천히 부드럽게 퍼진다(요란하지 않게). 주역은 자물쇠 풀림 애니.
	var ring := Sprite2D.new()
	ring.texture = _ring_tex()
	ring.modulate = Color(1.0, 0.85, 0.45, 0.5)
	ring.material = cm
	ring.z_index = 12
	ring.scale = Vector2.ONE * 0.4
	get_parent().add_child(ring)
	ring.global_position = from
	var rt := create_tween()
	rt.parallel().tween_property(ring, "scale", Vector2.ONE * 1.7, 0.7).set_ease(Tween.EASE_OUT)
	rt.parallel().tween_property(ring, "modulate:a", 0.0, 0.7)
	rt.chain().tween_callback(ring.queue_free)


# 파훼 성공 — 봉인(룬)이 깨진다: 금빛으로 확 밝아졌다가 커지며 사라지고, 금색 조각 6개가 사방으로 튄다.
# 자물쇠 글리프가 작아 "고리가 열림"은 안 읽혀서(어색) → "봉인이 깨짐"(파훼)으로. 그로기 동안 사라졌다 재생성.
func _unlock_rune(idx: int) -> void:
	if idx < 0 or idx >= _runes.size():
		return
	var r: Dictionary = _runes[idx]
	var holder := r["holder"] as Node2D
	if holder == null or not is_instance_valid(holder):
		return
	r["unlocking"] = true   # _update_runes/_update_rune_charge가 이 룬을 덮지 않게
	var center: Vector2 = r["pos"]
	# 봉인이 확 밝아졌다가 커지며 흩어져 사라짐
	holder.scale = Vector2.ONE * 1.4
	holder.modulate = Color(3.0, 2.8, 1.7, 1.0)
	var ht := create_tween()
	ht.parallel().tween_property(holder, "scale", Vector2.ONE * 2.0, 0.35).set_ease(Tween.EASE_OUT)
	ht.parallel().tween_property(holder, "modulate:a", 0.0, 0.4)
	# 금빛 조각 6개 — 방사 방향 짧은 섬광이 튀며 흩어짐
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for k in 6:
		var ang: float = TAU * float(k) / 6.0 + 0.35
		var dir := Vector2(cos(ang), sin(ang))
		var shard := Line2D.new()
		shard.points = PackedVector2Array([Vector2(4.0, 0.0), Vector2(16.0, 0.0)])
		shard.rotation = ang
		shard.width = 3.0
		shard.default_color = Color(1.0, 0.9, 0.5, 0.95)
		shard.z_index = 12
		shard.material = cm
		get_parent().add_child(shard)
		shard.global_position = center
		var dist: float = 36.0 + float(k % 3) * 9.0   # 살짝 불규칙
		var stw := create_tween()
		stw.parallel().tween_property(shard, "global_position", center + dir * dist, 0.5).set_ease(Tween.EASE_OUT)
		stw.parallel().tween_property(shard, "modulate:a", 0.0, 0.5)
		stw.chain().tween_callback(shard.queue_free)


# 패턴 소진(3개 다 깸) 후 재설정 — 전부 재잠금 + 카운트 0. 테스트 랩에서 반복 테스트용.
func _reset_runes() -> void:
	for i in _runes.size():
		_runes[i]["unlocking"] = false
		var h := _runes[i]["holder"] as Node2D
		if h != null and is_instance_valid(h):
			h.scale = Vector2.ONE
			h.modulate = Color(0.5, 0.55, 0.55, 0.45)
	_broken_count = 0


# 5돌진 세트 시작 (패턴 랩 버튼) — 룬 3개 재생성 + 첫 돌진. 진행 중이거나 그로기 중이면 무시.
func _start_pattern() -> void:
	if _pattern_active:
		return
	if _boss != null and float(_boss.get("groggy_left")) > 0.0:
		return
	_reset_runes()          # 룬 3개 재생성 + broken_count 0
	_dash_count = 0
	_next_dash_cd = 0.0
	_filler_pending = false
	_pattern_active = true
	_cstate = CS_GLINT      # 첫 돌진
	_cstate_t = 0.0
	_spawn_glint_converge()


# 룬 파훼 등록(동기) — 그 룬 사라짐 + 카운트. 3/3이면 15초 그로기+성공, 아니면 3초 그로기(다음 룬 찾을 시간).
func _register_break(idx: int) -> void:
	if idx < 0 or idx >= _runes.size() or _runes[idx].get("unlocking", false):
		return
	_runes[idx]["unlocking"] = true   # 깨짐(사라짐)
	_broken_count += 1
	if _broken_count >= _runes.size():
		# 3/3 성공! → 8초 그로기 + 세트 종료
		if _boss != null:
			_popup_text(_boss.global_position + Vector2(0.0, -80.0), "성공! 3/3 격파", Color(0.4, 1.0, 0.6))
			if _boss.has_method("enter_groggy"):
				_boss.enter_groggy(8.0)
		_end_pattern(true)
	elif _boss != null and _boss.has_method("enter_groggy"):
		_boss.enter_groggy(3.0)   # 다음 룬 찾을 시간 = 3초 그로기


# 한 돌진 종료(파훼/일반/실패 공통) — 돌진 수 +1, 5번 다 썼는데 <3이면 세트 종료. 다음 돌진은 CS_IDLE이 자동.
func _dash_ended(consumed: bool) -> void:
	if not _pattern_active:
		return
	if consumed:
		_dash_count += 1   # 놓침만 5회 예산을 깎는다 (성공은 공짜)
	if _broken_count >= _runes.size():
		return   # 이미 3/3 성공 처리됨
	if _dash_count >= MAX_DASHES:
		_end_pattern(false)   # 5번 놓쳤는데 <3 → 종료
	else:
		_filler_pending = true   # 회복 뒤 틈새 공격 한 번 → 그다음 돌진 (CS_IDLE이 순서대로)
		_next_dash_cd = DASH_GAP


# 세트 종료 — 잠시 후 리셋(반복 테스트).
func _end_pattern(success: bool) -> void:
	_pattern_active = false
	var t := create_tween()
	t.tween_interval(4.0 if success else 1.5)
	t.tween_callback(_reset_pattern)


func _reset_pattern() -> void:
	_reset_runes()
	_dash_count = 0


# 틈새 공격 — 번갈아: 장판 유도(룬 피해서) ↔ 원형 탄막. 돌진 실패 후 3초 틈에 발동해 룬으로 갈 시간을 준다.
func _do_filler() -> void:
	if _filler_alt:
		_filler_zones()
	else:
		_filler_spray()
	_filler_alt = not _filler_alt


# 위험 장판 3개 — 룬을 피한 지점에 붉은 예고 원이 커졌다가 터진다. 안전지대가 곧 룬 근처 → 자연스럽게 룬으로.
func _filler_zones() -> void:
	for sp: Vector2 in _pick_zone_spots(3):
		_spawn_danger_zone(sp, 62.0)


func _pick_zone_spots(n: int) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < 40:
		tries += 1
		var p := Vector2(randf_range(ROOM2.position.x + 80.0, ROOM2.end.x - 80.0),
			randf_range(ROOM2.position.y + 60.0, ROOM2.end.y - 60.0))
		var ok := true
		for r: Vector2 in RUNE_POS:
			if p.distance_to(r) < 95.0:   # 룬 근처는 안전지대로 비운다
				ok = false
				break
		if ok:
			for q: Vector2 in out:
				if p.distance_to(q) < 110.0:
					ok = false
					break
		if ok:
			out.append(p)
	return out


# 위험 장판 — ① 위치 링(즉시 예고) ② 안쪽 게이지가 0→가득 차오름 ③ 위에서 떨어지는 착탄(피해).
func _spawn_danger_zone(pos: Vector2, radius: float) -> void:
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# ① 위치 링 — 어디에 떨어질지 미리 보여준다
	var ring := Sprite2D.new()
	ring.texture = _ring_tex()
	ring.modulate = Color(1.0, 0.35, 0.28, 0.95)   # 또렷한 붉은 테두리
	ring.material = cm
	ring.z_index = 10
	ring.scale = Vector2.ONE * (radius * 2.0 / 128.0)
	get_parent().add_child(ring)
	ring.global_position = pos
	# ② 게이지 — 안쪽 붉은 원이 차오른다(위험 임박)
	var fill := Sprite2D.new()
	fill.texture = _light_tex()
	fill.modulate = Color(1.0, 0.3, 0.22, 0.8)   # 진한 붉은 게이지
	fill.material = cm
	fill.z_index = 10
	fill.scale = Vector2.ZERO
	get_parent().add_child(fill)
	fill.global_position = pos
	var gt := create_tween()
	gt.tween_property(fill, "scale", Vector2.ONE * (radius / 128.0), 1.2).set_ease(Tween.EASE_IN)
	gt.tween_callback(_zone_drop.bind(pos, radius, ring, fill))


# 게이지 다 참 → 위에서 무언가 떨어지는 모션.
func _zone_drop(pos: Vector2, radius: float, ring: Sprite2D, fill: Sprite2D) -> void:
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var drop := Sprite2D.new()
	drop.texture = _light_tex()
	drop.modulate = Color(1.0, 0.55, 0.45, 0.95)
	drop.material = cm
	drop.z_index = 11
	drop.scale = Vector2.ONE * (radius * 0.7 / 128.0)
	get_parent().add_child(drop)
	drop.global_position = pos + Vector2(0.0, -130.0)
	var dt := create_tween()
	dt.tween_property(drop, "global_position", pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dt.tween_callback(_zone_impact.bind(pos, radius, ring, fill, drop))


# 착탄 — 플래시 + (플레이어가 안이면) 피해(무적 존중). 예고물 정리.
func _zone_impact(pos: Vector2, radius: float, ring: Sprite2D, fill: Sprite2D, drop: Sprite2D) -> void:
	_clash_fx(pos)
	var lp := _local_player()
	if lp != null and lp.global_position.distance_to(pos) <= radius:
		var ph := lp.get_node_or_null("Health") as HealthComponent
		if ph != null:
			ph.apply_damage(5, false)   # 무적이면 무시
	for nd: Node in [ring, fill, drop]:
		if is_instance_valid(nd):
			var ft := create_tween()
			ft.tween_property(nd, "modulate:a", 0.0, 0.2)
			ft.tween_callback(nd.queue_free)


# 원형 탄막 — 보스에서 사방으로 느린 보라 탄. 위빙하며 룬으로 이동(테스트 랩 = 표시 위주).
func _filler_spray() -> void:
	if _boss == null:
		return
	var origin: Vector2 = _boss.global_position
	var count := 10
	for k in count:
		var ang: float = TAU * float(k) / float(count)
		var dir := Vector2(cos(ang), sin(ang))
		var orb := Sprite2D.new()
		orb.texture = _light_tex()
		orb.modulate = Color(0.9, 0.5, 1.0, 0.95)   # 보라 탄
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		orb.material = cm
		orb.scale = Vector2.ONE * 0.17
		orb.z_index = 10
		get_parent().add_child(orb)
		orb.global_position = origin
		var tw := create_tween()
		tw.parallel().tween_property(orb, "global_position", origin + dir * 260.0, 2.0)
		tw.tween_property(orb, "modulate:a", 0.0, 0.5)
		tw.tween_callback(orb.queue_free)


# 카운터 약점(F 표식) — 다이아몬드(가산 청록 맥동) + "F". _process가 플레이어 쪽 보스 가장자리로 옮긴다.
func _setup_counter() -> void:
	var holder := Node2D.new()
	holder.name = "CounterMarker"
	holder.z_index = 8
	get_parent().add_child(holder)
	var poly := Polygon2D.new()
	var s := 15.0
	poly.polygon = PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)])
	poly.color = Color(0.4, 1.0, 0.8, 0.85)
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	poly.material = pm
	holder.add_child(poly)
	_counter_poly = poly
	var lbl := Label.new()
	lbl.text = "F"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.95, 1.0, 0.98))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(-5.0, -12.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lbl)
	_counter_label = lbl
	_counter_marker = holder
	# 눈 예고 — 각 눈 = 헤일로(바깥 글로우) + 핫 코어(중심). GLINT 동안 dim→hot 램프 + 입자 수렴 + 끝 스냅.
	var glint := Node2D.new()
	glint.name = "EyeGlint"
	glint.z_index = 8
	glint.visible = false
	get_parent().add_child(glint)
	_eye_cores.clear()
	_eye_halos.clear()
	for dx: float in [-8.0, 8.0]:
		var halo := Sprite2D.new()
		halo.texture = _light_tex()
		halo.material = _add_mat()
		halo.position = Vector2(dx, 0.0)
		glint.add_child(halo)
		_eye_halos.append(halo)
		var core := Sprite2D.new()
		core.texture = _light_tex()
		core.material = _add_mat()
		core.position = Vector2(dx, 0.0)
		glint.add_child(core)
		_eye_cores.append(core)
	_eye_glint = glint
	# 돌진 위험선 — 보스에서 돌진 방향으로 뻗다가 끝으로 갈수록 가늘어지며 투명해지는(자연스러운) 경로.
	# 튀지 않게: 바닥 텔레그래프 층(z=-1, 캐릭터 아래) · 폭 테이퍼 · 색 페이드아웃 · 뮤트 주황 · 느린 맥동.
	var dl := Line2D.new()
	dl.name = "DashLine"
	dl.width = 7.0
	dl.z_index = -1   # UI처럼 안 튀고 '바닥에 그은 길'로 읽힘 (캐릭터 아래)
	dl.visible = false
	dl.begin_cap_mode = Line2D.LINE_CAP_ROUND
	dl.end_cap_mode = Line2D.LINE_CAP_ROUND
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 1.0))
	wc.add_point(Vector2(1.0, 0.12))   # 끝으로 갈수록 가늘게
	dl.width_curve = wc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.45, 0.25, 0.7))
	g.set_color(1, Color(1.0, 0.4, 0.2, 0.0))   # 끝은 투명 → 자연스럽게 흩어짐
	dl.gradient = g
	var dm := CanvasItemMaterial.new()
	dm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	dl.material = dm
	get_parent().add_child(dl)
	_dash_line = dl


func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


# 충전 수렴 — GLINT 진입 시 1회. 붉은 입자가 링에서 눈(핵)으로 빨려 들어온다(예비동작).
func _spawn_glint_converge() -> void:
	if _boss == null:
		return
	var center: Vector2 = _boss.global_position + EYE_OFFSET
	for k in 12:
		var ang: float = TAU * float(k) / 12.0 + randf() * 0.4
		var r: float = 34.0 + randf() * 18.0
		var mote := Sprite2D.new()
		mote.texture = _light_tex()
		mote.scale = Vector2.ONE * (0.035 + randf() * 0.025)
		mote.modulate = Color(1.0, 0.35, 0.25, 0.0)
		mote.material = _add_mat()
		mote.z_index = 8
		get_parent().add_child(mote)
		mote.global_position = center + Vector2(cos(ang), sin(ang)) * r
		var dur: float = 0.3 + randf() * 0.16
		var tw := create_tween()
		tw.parallel().tween_property(mote, "global_position", center, dur).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mote, "modulate:a", 0.9, dur * 0.5)
		tw.parallel().tween_property(mote, "scale", Vector2.ONE * 0.012, dur)
		tw.chain().tween_callback(mote.queue_free)


# 충전 완료 스냅 — 밝은 코어 플래시 + 작은 확산 링(눈 번쩍).
func _glint_snap() -> void:
	if _boss == null:
		return
	var center: Vector2 = _boss.global_position + EYE_OFFSET
	var flash := Sprite2D.new()
	flash.texture = _light_tex()
	flash.scale = Vector2.ONE * 0.05
	flash.modulate = Color(1.9, 1.5, 1.2, 1.0)
	flash.material = _add_mat()
	flash.z_index = 9
	get_parent().add_child(flash)
	flash.global_position = center
	var tw := create_tween()
	tw.parallel().tween_property(flash, "scale", Vector2.ONE * 0.5, 0.18).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flash, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(flash.queue_free)


# 돌진 위험선 — 보스에서 돌진 방향으로 뻗는 굵고 밝은 경고선. AIM/DASH 동안만.
func _show_dash_line() -> void:
	if _dash_line == null or not is_instance_valid(_dash_line) or _boss == null:
		return
	_dash_line.visible = true
	var from: Vector2 = _boss.global_position
	var dir: Vector2 = _charge_dir
	# 🔴 예고선 = 실제 돌진 경로 = 직선("맞는 곳=보이는 곳"). 파동 안 넣음.
	#    길이 = 보스→플레이어(돌진 대상) + 약간의 팔로스루 — 대상까지만 뻗게(너무 길지 않게).
	var length: float = 200.0
	var lp := _local_player()
	if lp != null:
		length = clampf(from.distance_to(lp.global_position) + 70.0, 70.0, 280.0)
	_dash_line.points = PackedVector2Array([from, from + dir * length])
	_dash_line.modulate.a = 0.26 + 0.1 * absf(sin(_counter_t * TAU * 2.2))   # 줄 자체는 옅게 — 흐르는 모트가 주역
	# 흐르는 느낌 — 줄을 따라 빛 알갱이가 촘촘히 흘러간다(경로는 직선 유지)
	if _counter_t - _soul_mote_last > 0.045:
		_soul_mote_last = _counter_t
		_spawn_soul_mote(from, dir, length)


# 영혼 모트 — 줄을 따라 보스에서 앞으로 흐르는 빛 알갱이(밝아졌다 사라짐). "영혼이 줄을 타고 흐르는" 느낌.
func _spawn_soul_mote(from: Vector2, dir: Vector2, length: float) -> void:
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var drift: Vector2 = perp * randf_range(-7.0, 7.0)   # 살짝 옆으로(영혼) — 코어 경로는 직선
	var mote := Sprite2D.new()
	mote.texture = _light_tex()
	mote.scale = Vector2.ONE * (0.035 + randf() * 0.03)
	mote.modulate = Color(1.0, 0.6, 0.32, 0.0)
	mote.material = _add_mat()
	mote.z_index = 0
	get_parent().add_child(mote)
	mote.global_position = from + drift * 0.4
	var travel: float = 0.4 + randf() * 0.25
	var tw := create_tween()
	tw.tween_property(mote, "modulate:a", 0.8, 0.1)
	tw.parallel().tween_property(mote, "global_position", from + dir * maxf(length - 20.0, 20.0) + drift, travel).set_ease(Tween.EASE_IN)
	tw.chain().tween_property(mote, "modulate:a", 0.0, 0.14)
	tw.tween_callback(mote.queue_free)


# 카운터 상태머신(호출: _process): IDLE → GLINT(눈 반짝) → AIM(위험선) → DASH(돌진, 도중 F=카운터).
func _update_counter(lp: PlayerActor, delta: float) -> void:
	if _counter_marker == null or not is_instance_valid(_counter_marker) or _boss == null:
		return
	_counter_t += delta
	if _next_dash_cd > 0.0:
		_next_dash_cd -= delta   # 그로기 중에도 흐른다 → 성공 3초 그로기와 겹쳐 총 3초, 실패도 3초
	lp.roll_suppressed = (_cstate != CS_IDLE) or _clashing   # 카운터 시퀀스+클래시 내내 구르기 억제(연타 F 튀어나감 방지)
	var h := _boss.get_node_or_null("Health") as HealthComponent
	if h == null or h.hp <= 0:   # 죽으면 전부 끔
		_reset_counter()
		return
	if float(_boss.get("groggy_left")) > 0.0:   # 그로기(격파) 중 = 카운터 시퀀스 정지
		if _cstate != CS_IDLE:
			_reset_counter()
		return
	_cstate_t += delta
	if _dash_line != null and is_instance_valid(_dash_line):
		_dash_line.visible = false   # 기본 숨김 — AIM/DASH만 켠다
	match _cstate:
		CS_IDLE:
			# 버튼으로 5돌진 세트 시작. 세트 진행 중이면 (그로기 끝난 뒤) 간격 두고 다음 돌진 자동.
			_counter_marker.visible = false
			_eye_glint.visible = false
			_boss.counter_ready = false
			if _pattern_active and _dash_count < MAX_DASHES and _broken_count < _runes.size() and _next_dash_cd <= 0.0:
				if _filler_pending:
					_do_filler()               # 회복 끝 → 틈새 공격 한 번
					_filler_pending = false
					_next_dash_cd = FILLER_LEAD   # 틈새 공격이 끝나야 다음 돌진
				else:
					_cstate = CS_GLINT         # 틈새 공격 끝 → 다음 돌진
					_cstate_t = 0.0
					_spawn_glint_converge()
		CS_GLINT:
			# 눈 반짝(예고). 아직 조준·돌진 전.
			_counter_marker.visible = false
			_boss.counter_ready = false
			_eye_glint.visible = true
			_eye_glint.global_position = _boss.global_position + EYE_OFFSET
			_eye_glint.scale = Vector2.ONE
			var ct: float = clampf(_cstate_t / COUNTER_GLINT, 0.0, 1.0)   # 충전 진행 0→1
			var hot: Color = Color(0.9, 0.2, 0.15).lerp(Color(1.8, 1.5, 1.3), ct)   # 어두운 빨강 → 뜨거운 백색
			for hnode: Sprite2D in _eye_halos:
				hnode.modulate = Color(hot.r, hot.g * 0.55 + 0.1, hot.b * 0.45 + 0.1, 0.25 + 0.55 * ct)
				hnode.scale = Vector2.ONE * (0.20 + 0.16 * ct)
			for cnode: Sprite2D in _eye_cores:
				cnode.modulate = Color(hot.r, hot.g, hot.b, 0.45 + 0.55 * ct)
				cnode.scale = Vector2.ONE * (0.06 + 0.06 * ct)
			if _cstate_t >= COUNTER_GLINT:
				_glint_snap()   # 충전 완료 스냅 플래시(눈 번쩍)
				# 조준 개시 — 돌진 방향 고정(현재 플레이어 향) + 보스가 바라봄
				_cstate = CS_AIM
				_cstate_t = 0.0
				var d: Vector2 = lp.global_position - _boss.global_position
				d = d.normalized() if d.length() > 1.0 else Vector2.RIGHT
				_charge_dir = d
				_charge_traveled = 0.0
				var bspr := _boss.get_node_or_null("Sprite") as AnimatedSprite2D
				if bspr != null:
					bspr.flip_h = d.x < 0.0
		CS_AIM:
			# 보스가 바라보며 줄 생김(플레이어까지 연결) + 몸색 앰버. 돌진 직전 조준.
			_eye_glint.visible = false
			_boss.counter_ready = true
			_show_counter_marker_on_boss(lp)
			_show_dash_line()        # 돌진 방향 경고선(굵고 밝게)
			if _cstate_t >= CHARGE_AIM:
				_cstate = CS_DASH
				_cstate_t = 0.0
				_parry_open_t = -1.0     # 받아치기 창 초기화
				_parry_used = false
				_in_rune_window = false  # 새 돌진 시작 — 룬 창 래치 초기화
				_break_rune = -1
				_dash_speed = CHARGE_SPEED
				EventBus.screen_shake.emit(4.0)
		CS_DASH:
			# 돌진 — 고정 방향으로 직진. 근접(내 앞)하면 창 열림, 그 안 F만 성공.
			# 🔴 종료 = "보스가 내 캐릭터 뒤를 지나간 순간"(고정 지점 아님). 성공 시엔 클래시가 앞에서 멈춤.
			_boss.counter_ready = true
			# 앞에 있나(이동 전) — 창은 앞에서만 열림
			var in_front: bool = (_boss.global_position - lp.global_position).dot(_charge_dir) <= 0.0   # _boss Node 타입 명시
			var pd: float = _boss.global_position.distance_to(lp.global_position)
			if not _parry_used and _parry_open_t < 0.0 and pd <= PARRY_OPEN_RANGE and in_front:
				_parry_open_t = PARRY_WINDOW   # 앞에서 근접 → 창 열림
			if _parry_open_t >= 0.0:
				_parry_open_t -= delta
				var cr_win := _current_rune(lp)
				if cr_win >= 0:
					_in_rune_window = true   # 창이 열린 동안 룬 위 → F 순간 살짝 벗어나도 파훼 인정
					_break_rune = cr_win     # 어느 룬이든 그 룬을 깬다
			_show_counter_marker_on_boss(lp)
			_show_dash_line()        # 돌진 중에도 경로 표시
			# 🔴 이동 — 지나치기 전엔 풀스피드, 플레이어를 지나치면 감속(팔로스루)해 스르륵 멈춘다.
			#    (급정지=끊김 / 무한이동=오버슈트, 둘 다 피함. 창은 지나쳐도 유지 → 늦은 F도 성공.)
			var passed: bool = (_boss.global_position - lp.global_position).dot(_charge_dir) > 0.0
			if passed:
				_dash_speed = move_toward(_dash_speed, 0.0, DASH_DECEL * delta)
			if _dash_speed > 1.0 and _charge_traveled <= 640.0:
				var step := _dash_speed * delta
				_boss.global_position = _clamp_arena(_boss.global_position + _charge_dir * step)
				_charge_traveled += step
			# 종료 — 창 닫힌 뒤 + (거의 멈춤 or 상한)
			if _parry_open_t < 0.0 and (_dash_speed <= 1.0 or _charge_traveled > 640.0):
				if _parry_used and _lock_linger > 0.0:
					_lock_linger -= delta   # 이른 F 잠금 = ✕ 잠깐 더 (보스는 감속해 멈춤)
				else:
					_charge_hit(lp)        # 지나침 = 실패
					_reset_counter()
					_dash_ended(true)      # 놓침 = 돌진 예산 −1 (5회)


# F 표식을 보스 앞(대상 쪽)에 배치 + 맥동. 받아치기 창이 열리면 "지금!" 강조(흰노랑·크게).
func _show_counter_marker_on_boss(lp: PlayerActor) -> void:
	_counter_marker.visible = true
	var to_p: Vector2 = lp.global_position - _boss.global_position
	to_p = to_p.normalized() if to_p.length() > 1.0 else Vector2.RIGHT
	_counter_marker.global_position = _boss.global_position + to_p * COUNTER_OFFSET
	var open := _parry_open_t >= 0.0
	# 3-상태: 잠김(빨간 ✕) / 지금!(노랑, 크게) / 대기(청록)
	if _parry_used:
		_counter_marker.scale = Vector2.ONE * 0.9
		if _counter_poly != null:
			_counter_poly.color = Color(0.9, 0.2, 0.2, 0.92)
		if _counter_label != null:
			_counter_label.text = "✕"
			_counter_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	else:
		_counter_marker.scale = Vector2.ONE * ((1.35 if open else 0.9) + 0.18 * sin(_counter_t * TAU * 8.0))
		if _counter_poly != null:
			_counter_poly.color = Color(1.0, 1.0, 0.45, 0.98) if open else Color(0.35, 0.85, 0.7, 0.7)
		if _counter_label != null:
			_counter_label.text = "F"
			_counter_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.98))


# 카운터 국면 끝 — 전부 끄고 IDLE(다음 기회 5초 뒤).
func _reset_counter() -> void:
	_cstate = CS_IDLE
	_cstate_t = 0.0
	_parry_open_t = -1.0
	_parry_used = false
	_in_rune_window = false
	_lock_linger = 0.0
	if _counter_marker != null:
		_counter_marker.visible = false
	if _eye_glint != null:
		_eye_glint.visible = false
	if _dash_line != null:
		_dash_line.visible = false
	if _boss != null:
		_boss.counter_ready = false
	var lp := _local_player()
	if lp != null:
		lp.roll_suppressed = false   # 카운터 끝 = 구르기 복구


# F 입력 → 돌진 중에만. 받아치기 창(_parry_open_t≥0)이면 성공, 이르게 누르면 헛침(이번 돌진 잠금).
func _try_counter() -> void:
	if _cstate != CS_DASH or _boss == null or _parry_used:
		return
	var lp := _local_player()
	if lp == null:
		return
	if _parry_open_t >= 0.0:
		if not _boss_in_vision(lp):
			# 🔴 보스를 시야 콘(~90°)에 두지 않고 받아침 = 실패(이번 돌진 잠금, 빨간 ✕)
			_parry_used = true
			_lock_linger = 0.5
			return
		# 파훼 판정 = 창 동안 룬 위 OR F 순간 룬 위. 깰 룬 = 그 룬(래치 우선, 없으면 지금 룬).
		var cr := _current_rune(lp)
		if cr >= 0:
			_break_rune = cr
		_parry_in_rune = _break_rune >= 0 and (_in_rune_window or cr >= 0)
		_reset_counter()      # 창 안 + 보스 조준 — 카운터 성공
		_counter_strike(lp)
		if _parry_in_rune:
			_register_break(_break_rune)   # 그 룬 깸 + 그로기(3초, 3/3이면 15초)
		_dash_ended(false)     # 파훼/일반 성공 = 돌진 예산 소진 안 함
	else:
		_parry_used = true    # 이른 F — 헛침, 이번 돌진은 더 못 받아침(빨간 ✕)
		_lock_linger = 0.5


# 맵 밖 방지 — 카운터/돌진 tween 목표를 벽 안쪽으로 클램프.
func _clamp_arena(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, ARENA_SAFE.position.x, ARENA_SAFE.end.x),
		clampf(p.y, ARENA_SAFE.position.y, ARENA_SAFE.end.y))


# 카운터 성공 = 클래시 — 둘이 서로 마주 달려 부딪히고(스파크+프리즈) 서로 반대로 튕겨난다. 좌표 전부 맵 클램프.
func _counter_strike(lp: PlayerActor) -> void:
	var spr := lp.get_node_or_null("Sprite") as AnimatedSprite2D
	var p0: Vector2 = lp.global_position
	var b0: Vector2 = _boss.global_position
	var to_boss: Vector2 = b0 - p0
	to_boss = to_boss.normalized() if to_boss.length() > 0.5 else Vector2.RIGHT
	var clash: Vector2 = _clamp_arena((p0 + b0) * 0.5)
	var p_clash: Vector2 = _clamp_arena(clash - to_boss * 16.0)
	var b_clash: Vector2 = _clamp_arena(clash + to_boss * 16.0)
	var p_recoil: Vector2 = _clamp_arena(clash - to_boss * 48.0)
	var b_recoil: Vector2 = _clamp_arena(clash + to_boss * 60.0)
	_clashing = true          # 클래시 동안 구르기 억제(연타 F가 tween과 안 싸우게)
	lp.roll_suppressed = true
	lp.velocity = Vector2.ZERO
	var bspr := _boss.get_node_or_null("Sprite") as AnimatedSprite2D
	if bspr != null:
		bspr.flip_h = p0.x < b0.x   # 보스가 플레이어 향함
	var tw := create_tween()
	# 1) 서로 클래시 지점으로 확 달려듦 (부딪힘)
	tw.tween_property(lp, "global_position", p_clash, 0.06).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_boss, "global_position", b_clash, 0.06).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	# 2) 부딪힘 — 스파크·프리즈·피해·스태거·흔들림·성공 표시
	tw.chain().tween_callback(_clash_impact.bind(clash))
	tw.tween_interval(0.1)
	# 3) 서로 반대로 튕겨남
	tw.tween_property(lp, "global_position", p_recoil, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_boss, "global_position", b_recoil, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void: _clashing = false)   # 클래시 끝 → 구르기 복구
	# 잔상 (달려들 때)
	if spr != null:
		var at := create_tween()
		for _i in 5:
			at.tween_callback(Afterimage.spawn.bind(spr, lp))
			at.tween_interval(0.015)


# 부딪힘 순간: 보스 피해 + 꿇음 + 스파크 + 카메라 흔들림 + "성공!" 표시.
func _clash_impact(pos: Vector2) -> void:
	if _boss == null:
		return
	var h := _boss.get_node_or_null("Health") as HealthComponent
	if h != null:
		h.apply_damage(COUNTER_DAMAGE, true)
	if _boss.has_method("counter_stagger"):
		_boss.counter_stagger()
	_clash_fx(pos)
	if _parry_in_rune:
		# 격파 — 화려하게: 추가 스파크 + 큰 흔들림 (그로기는 _register_break가 3초/15초로 처리)
		EventBus.screen_shake.emit(13.0)
		_clash_fx(_boss.global_position)
		_popup_text(pos + Vector2(0.0, -50.0), "파훼!", Color(1.0, 0.95, 0.4))
		_conduit_beam(_break_rune)   # 깬 룬에서 은은한 봉인 해제 파문
		_unlock_rune(_break_rune)    # 그 룬이 금색 조각으로 깨짐(봉인 파쇄)
	else:
		EventBus.screen_shake.emit(7.0)
		_popup_text(pos + Vector2(0.0, -42.0), "성공!", Color(0.65, 1.0, 0.72))   # 룬 아닌 일반 부딪힘 = 그로기 없음


# 돌진 명중(안 침/잠금) = 실패 — 흔들림 + "실패" 표시 + 플레이어 피해(무적 무시, 실패에 대가) + 넉백.
func _charge_hit(lp: PlayerActor) -> void:
	if lp == null or _boss == null:
		return
	EventBus.screen_shake.emit(6.0)
	_popup_text(lp.global_position + Vector2(0.0, -42.0), "실패", Color(1.0, 0.45, 0.42))
	# 실패 = 돌진에 맞음 → 무적을 뚫고 피해(force_damage_one이 1로 캡). 실패에 실제 대가.
	var ph := lp.get_node_or_null("Health") as HealthComponent
	if ph != null:
		ph.apply_damage(9, false, true)
	_player_hit_fx(lp.global_position)   # 붉은 피격 FX (플레이어가 돌진에 맞음)
	# 🔴 텔포(렉처럼 튐) 대신 — 유령답게 빨려들어가듯 사라졌다가 새 위치에 다시 생긴다.
	var back: Vector2 = _clamp_arena(lp.global_position - _charge_dir * 72.0)
	_boss_vanish_reappear(back)


# 붉은 피격 FX — 실패(돌진에 맞음) 시 플레이어 위치에 충격 플래시 + 확산 링.
func _player_hit_fx(pos: Vector2) -> void:
	var cm := _add_mat()
	var flash := Sprite2D.new()
	flash.texture = _light_tex()
	flash.modulate = Color(1.7, 0.45, 0.4, 0.95)
	flash.material = cm
	flash.z_index = 11
	flash.scale = Vector2.ONE * 0.1
	get_parent().add_child(flash)
	flash.global_position = pos
	var ft := create_tween()
	ft.parallel().tween_property(flash, "scale", Vector2.ONE * 0.42, 0.18).set_ease(Tween.EASE_OUT)
	ft.parallel().tween_property(flash, "modulate:a", 0.0, 0.18)
	ft.chain().tween_callback(flash.queue_free)
	var ring := Sprite2D.new()
	ring.texture = _ring_tex()
	ring.modulate = Color(1.5, 0.4, 0.35, 0.9)
	ring.material = cm
	ring.z_index = 11
	ring.scale = Vector2.ONE * 0.15
	get_parent().add_child(ring)
	ring.global_position = pos
	var rt := create_tween()
	rt.parallel().tween_property(ring, "scale", Vector2.ONE * 0.7, 0.22).set_ease(Tween.EASE_OUT)
	rt.parallel().tween_property(ring, "modulate:a", 0.0, 0.22)
	rt.chain().tween_callback(ring.queue_free)


# 유령 순간이동 — 빨려들어가듯 작아지며 사라졌다가(현 위치) 새 위치에서 커지며 다시 생긴다.
func _boss_vanish_reappear(dest: Vector2) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var base_scale: Vector2 = _boss.scale
	_boss_implode_fx(_boss.global_position)   # 흡입 링(청록)
	var tw := create_tween()
	tw.tween_property(_boss, "modulate:a", 0.0, 0.1).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_boss, "scale", base_scale * 0.25, 0.1).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(_boss_reappear_at.bind(dest, base_scale))


func _boss_reappear_at(dest: Vector2, base_scale: Vector2) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_boss.global_position = dest
	_boss_materialize_fx(dest)   # 나타남 버스트
	var tw := create_tween()
	tw.tween_property(_boss, "modulate:a", 1.0, 0.14).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_boss, "scale", base_scale, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 흡입 링 — 청록 링이 점으로 수축(빨려들어감).
func _boss_implode_fx(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = _ring_tex()
	s.modulate = Color(0.5, 1.0, 0.85, 0.9)
	s.material = _add_mat()
	s.z_index = 6
	s.scale = Vector2.ONE * 1.4
	get_parent().add_child(s)
	s.global_position = pos
	var tw := create_tween()
	tw.parallel().tween_property(s, "scale", Vector2.ONE * 0.05, 0.13).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.13)
	tw.chain().tween_callback(s.queue_free)


# 나타남 버스트 — 청록 링이 퍼지며 재생성.
func _boss_materialize_fx(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = _ring_tex()
	s.modulate = Color(0.5, 1.0, 0.85, 0.85)
	s.material = _add_mat()
	s.z_index = 6
	s.scale = Vector2.ONE * 0.2
	get_parent().add_child(s)
	s.global_position = pos
	var tw := create_tween()
	tw.parallel().tween_property(s, "scale", Vector2.ONE * 1.5, 0.3).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(s.queue_free)


# 클래시 스파크 — 밝은 흰 확산 링 + 방사 스파크 선.
func _clash_fx(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = _ring_tex()
	s.modulate = Color(1.0, 1.0, 0.9, 1.0)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	s.z_index = 11
	get_parent().add_child(s)
	s.global_position = pos
	s.scale = Vector2.ONE * 0.2
	var tw := create_tween()
	tw.parallel().tween_property(s, "scale", Vector2.ONE * 2.1, 0.26)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.26)
	tw.chain().tween_callback(s.queue_free)
	for i in 6:
		var ang: float = TAU * float(i) / 6.0
		var d := Vector2(cos(ang), sin(ang))
		var ln := Line2D.new()
		ln.points = PackedVector2Array([pos + d * 7.0, pos + d * 28.0])
		ln.width = 3.0
		ln.default_color = Color(1.0, 0.96, 0.7, 0.95)
		ln.z_index = 11
		var lm := CanvasItemMaterial.new()
		lm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ln.material = lm
		get_parent().add_child(ln)
		var lt := create_tween()
		lt.tween_property(ln, "modulate:a", 0.0, 0.16)
		lt.tween_callback(ln.queue_free)


# 성공/실패 월드 텍스트 팝 — 살짝 떠오르며 사라짐.
func _popup_text(pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.z_index = 12
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(lbl)
	lbl.global_position = pos
	var tw := create_tween()
	tw.parallel().tween_property(lbl, "global_position", pos + Vector2(0.0, -26.0), 0.6)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(lbl.queue_free)


# 방 카메라 = 플레이어 카메라를 현재 방 경계에 클램프(따라가되 방 안에만). 경계 넘으면 리밋 스왑 = 스냅.
func _setup_camera() -> void:
	_apply_room_camera(1)   # 진입 방부터


func _player_cam() -> Camera2D:
	var lp := _local_player()
	if lp == null:
		return null
	for c: Node in lp.get_children():
		if c is Camera2D:
			return c as Camera2D
	return null


func _apply_room_camera(room: int) -> void:
	var cam := _player_cam()
	if cam == null:
		return
	var rc: Rect2 = ROOM2 if room == 2 else ROOM1
	cam.limit_left = int(rc.position.x)
	cam.limit_top = int(rc.position.y)
	cam.limit_right = int(rc.position.x + rc.size.x)
	cam.limit_bottom = int(rc.position.y + rc.size.y)
	cam.reset_smoothing()   # 방 전환 스냅


# 보스 방 진입 시 뒤 통로 봉쇄 — 못 돌아감(물리 벽).
func _seal_threshold() -> void:
	if _sealed:
		return
	_sealed = true
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	get_parent().add_child(wall)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(40.0, 460.0)
	cs.shape = r
	cs.position = Vector2(ROOM_SPLIT_X, 324.0)
	wall.add_child(cs)


# 좌→우 배치: 보스는 오른쪽 제단, 플레이어·NPC는 왼쪽 진입 지점. (아레나 필드 월드 좌표 기준)
func _reposition() -> void:
	# 보스·NPC = 오른쪽 보스 방, 플레이어 = 왼쪽 진입 방에서 시작
	if _boss != null:
		_boss.global_position = Vector2(852.0, 324.0)    # 보스 방 제단
	if _npc != null and is_instance_valid(_npc):
		_npc.global_position = Vector2(700.0, 372.0)     # 보스 방 (코옵 파트너 대기)
	var lp := _local_player()
	if lp != null:
		lp.global_position = Vector2(-300.0, 324.0)      # 진입 방 왼쪽 시작


# 아레나 필드 경계 = 충돌 벽으로 플레이어를 가둔다 + 바깥 바닥을 어둡게 해 "맵 밖"을 확실히 구분.
# 아레나 스프라이트 = 768×448 중심 (576,324) → 월드 필드 대략 x[192,960] y[100,548], 안쪽 벽 면.
func _build_bounds() -> void:
	# 바깥(주변 타일)을 거의 검정 void로 → 방 밖이 확실히 구분
	var ground := get_parent().get_node_or_null("Ground") as CanvasItem
	if ground != null:
		ground.modulate = Color(0.07, 0.07, 0.1)
	# 진입 방 바닥 스프라이트 (보스 방 왼쪽에). 아트 없으면 스킵.
	if ResourceLoader.exists("res://assets/sprites/stage/approach_room.png"):
		var s := Sprite2D.new()
		s.texture = load("res://assets/sprites/stage/approach_room.png")
		s.position = Vector2(-192.0, 324.0)   # 보스 방(576) 왼쪽으로 768
		s.z_index = -10
		get_parent().add_child(s)
	# 충돌 벽 — 두 방을 아우르는 바깥 경계 (world x[-576,960]). 방 사이 통로는 열림.
	var walls := StaticBody2D.new()
	walls.collision_layer = 1   # world (플레이어 mask=1)
	walls.collision_mask = 0
	get_parent().add_child(walls)
	var segs := [
		[Vector2(-606.0, 324.0), Vector2(60.0, 500.0)],   # 진입 방 왼쪽 끝
		[Vector2(946.0, 324.0), Vector2(60.0, 500.0)],    # 보스 방 오른쪽 끝
		[Vector2(192.0, 130.0), Vector2(1600.0, 60.0)],   # 위 (두 방 가로지름)
		[Vector2(192.0, 518.0), Vector2(1600.0, 60.0)],   # 아래
	]
	for s2: Array in segs:
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = s2[1]
		cs.shape = r
		cs.position = s2[0]
		walls.add_child(cs)


# ── 참가자 ──
func _local_player() -> PlayerActor:
	for n: Node in get_tree().get_nodes_in_group("player"):
		var p := n as PlayerActor
		if p != null and p.is_local:
			return p
	return null


func _real_player_count() -> int:
	var c := 0
	for n: Node in get_tree().get_nodes_in_group("player"):
		var p := n as PlayerActor
		if p != null and p.peer_id != TestMode.NPC_PEER_ID:
			c += 1
	return c


func _apply_invincible() -> void:
	var lp := _local_player()
	if lp == null:
		return
	var h := lp.get_node_or_null("Health") as HealthComponent
	if h != null:
		h.invincible = _invincible


func _heal_full() -> void:
	var lp := _local_player()
	if lp == null:
		return
	var h := lp.get_node_or_null("Health") as HealthComponent
	if h != null:
		h.confirm_hp(h.max_hp)     # 권한 경로 회복 (솔로 = 나는 호스트)


func _spawn_npc() -> void:
	if _npc != null and is_instance_valid(_npc):
		return
	if _real_player_count() >= 2:
		return   # 2인 실기 — 더미 불필요
	var lp := _local_player()
	var base: Vector2 = lp.global_position if lp != null else Vector2(320.0, 200.0)
	var scene_id: String = lp.scene_id if lp != null else ""
	var p := PlayerScene.instantiate() as PlayerActor
	get_parent().add_child(p)
	p.setup(TestMode.NPC_PEER_ID, false, base + Vector2(-90.0, 0.0), scene_id)
	p.set_job(GameState.job_def("warrior"))
	var h := p.get_node_or_null("Health") as HealthComponent
	if h != null:
		h.invincible = true          # NPC 더미도 무적 (코옵 판정에서 자동 통과 = coop_authority 처리)
	_npc = p


func _despawn_npc() -> void:
	if _npc != null and is_instance_valid(_npc):
		_npc.queue_free()
	_npc = null


# ── 패널 UI (우측 세로 바 — 아레나는 왼쪽, 클릭 안 막음) ──
func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.visible = false          # 기본 숨김 → 맵이 깨끗하게 풀로 보임. P로 토글.
	add_child(layer)
	_panel_layer = layer
	# 항상 보이는 작은 힌트 (우상단)
	var hint_layer := CanvasLayer.new()
	hint_layer.layer = 19
	add_child(hint_layer)
	var hint := Label.new()
	hint.text = "[P] 패턴 랩"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.9, 0.7))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.add_theme_constant_override("outline_size", 3)
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -84.0
	hint.offset_top = 2.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_layer.add_child(hint)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -156.0
	panel.offset_top = 4.0
	panel.offset_right = -4.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	_add_title(vb, "◆ 패턴 랩")
	_add_title(vb, "· 카운터")
	var g_cnt := _grid(vb, 2)
	_add_btn(g_cnt, "눈반짝", _on_force_glint)   # 전체: 눈 반짝 → 조준 → 돌진
	_add_btn(g_cnt, "돌진", _on_force_charge)     # 눈 반짝 건너뛰고 바로 조준→돌진

	vb.add_child(HSeparator.new())
	var g_chk := _grid(vb, 2)
	_cb_invin = _add_check(g_chk, "무적", _invincible, _on_invin)
	_cb_boss = _add_check(g_chk, "보스정지", true, _on_boss_hold)
	_cb_npc = _add_check(g_chk, "NPC", _npc_on, _on_npc_toggle)
	_add_check(g_chk, "오염P2", false, _on_corrupt_toggle)   # ⑤ 페이즈2 환경 오염 미리보기
	_add_btn(vb, "새 보스", _on_new_boss)   # 스테이지 재진입 = 새 보스 (마을 안 감, main의 TestMode 게이트)
	_add_btn(vb, "HP 회복", _heal_full)
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 11)
	vb.add_child(_hp_label)


func _grid(parent: Node, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	parent.add_child(g)
	return g


func _add_title(vb: VBoxContainer, txt: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	vb.add_child(l)


func _add_btn(parent: Node, txt: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE   # 버튼 포커스가 이후 게임 입력을 먹지 않게
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(48.0, 22.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _add_check(parent: Node, txt: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = txt
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 11)
	c.toggled.connect(cb)
	parent.add_child(c)
	return c


# ── 버튼 핸들러 ──
func _on_force_glint() -> void:
	_start_pattern()   # 버튼 1번 = 보스 5돌진 세트 시작 (그 안에 룬 3개 깨면 성공)


func _on_force_charge() -> void:
	_start_pattern()


func _on_invin(on: bool) -> void:
	_invincible = on
	_apply_invincible()


func _on_corrupt_toggle(on: bool) -> void:
	_corruption_target = 1.0 if on else 0.0


# 새 보스 = 스테이지 재진입. main._on_scene_change가 TestMode에서 SCENE_VILLAGE를 _to_boss_test로 되돌린다
# (마을 안 감). 죽이지 않고도 풀 HP·페이즈1 새 보스로 리셋하는 가장 견고한 방법(전체 재구성).
func _on_new_boss() -> void:
	EventBus.scene_change.emit(NetSchema.SCENE_VILLAGE)


func _on_boss_hold(on: bool) -> void:
	if _boss != null:
		_boss.debug_hold = on


func _on_npc_toggle(on: bool) -> void:
	_npc_on = on
	if on:
		_spawn_npc()
	else:
		_despawn_npc()


# ⑤ 보스 페이즈2 → 환경 오염 램프 목표를 1로 (실제 boss_phase_changed 경로 · 랩 토글 공용).
func _on_boss_phase(phase: int) -> void:
	_corruption_target = 1.0 if phase >= 2 else 0.0


func _process(_delta: float) -> void:
	_env_t += _delta          # 환경 연출 공용 시간 (② 조명 · ④ 제단이 같이 읽음)
	if _f_cd > 0.0:
		_f_cd -= _delta       # 받아치기 F 쿨타임
	# ⑤ 오염을 목표로 부드럽게 램프 → 오버레이 셰이더 corruption uniform에 반영
	_corruption = move_toward(_corruption, _corruption_target, _delta * 0.6)
	if _overlay_mat != null:
		_overlay_mat.set_shader_parameter(&"corruption", _corruption)
	_animate_lights(_delta)   # ② 환경 빛 맥동+깜빡
	_animate_altar(_delta)    # ④ 제단 룬 서클 회전+맥동
	# 상단 HP바 전체를 미세 노이즈로 진동(노이즈 강조) — 아주 느리고 작게, 오염 시만 조금 더
	if _boss_hp_layer != null and _env_noise != null:
		var jit := 0.3 + 1.0 * _corruption
		var jx := _env_noise.get_noise_1d(_env_t * 4.0)
		var jy := _env_noise.get_noise_1d(_env_t * 4.0 + 500.0)
		_boss_hp_layer.offset = Vector2(jx, jy) * jit
	# 보스 림 실루엣을 실제 스프라이트와 프레임/방향 동기화
	if _boss_rim != null and is_instance_valid(_boss_rim) and _boss != null:
		var bspr := _boss.get_node_or_null("Sprite") as AnimatedSprite2D
		if bspr != null and bspr.sprite_frames != null:
			if bspr.animation != _boss_rim.animation and bspr.sprite_frames.has_animation(bspr.animation):
				_boss_rim.animation = bspr.animation
			_boss_rim.frame = bspr.frame
			_boss_rim.flip_h = bspr.flip_h
	var lp := _local_player()
	if lp == null:
		return
	# 시야 콘: 부활/재스폰으로 잃으면 재생성 + 조준각으로 회전 (플레이어 자식이라 위치는 자동으로 따라옴)
	_ensure_vision(lp)
	if _vision != null and is_instance_valid(_vision):
		_vision.rotation = float(lp.get("_aim_angle"))
	_update_counter(lp, _delta)   # 카운터 약점 배치·맥동·재무장
	_update_runes(lp)             # 룬 — 플레이어가 올라선 룬 = 타겟(금색), 나머지 회색, 깨진 것 숨김
	_update_rune_diamond()        # 타겟 룬 위 다이아몬드 + "N번째"
	_update_rune_charge(lp, _delta)   # 룬 위 충전 오라/입자/무기 발광 (강화 affordance)
	# 보스 그로기 라벨 — "그로기중... N"
	if _groggy_label != null and _boss != null:
		var g: float = float(_boss.get("groggy_left"))
		if g > 0.0:
			_groggy_label.visible = true
			_groggy_label.text = "그로기중... %d" % int(ceil(g))
			_groggy_label.global_position = _boss.global_position + Vector2(-42.0, -72.0)
		else:
			_groggy_label.visible = false
	# 방 전환(젤다식): 경계 넘으면 카메라 스냅 + 보스 방 진입 시 뒤 통로 봉쇄
	var room := 2 if lp.global_position.x >= ROOM_SPLIT_X else 1
	if room != _cur_room:
		_cur_room = room
		_apply_room_camera(room)
		if room == 2:
			_seal_threshold()
	if _hp_label != null:
		var h := lp.get_node_or_null("Health") as HealthComponent
		if h != null:
			_hp_label.text = "HP %d/%d %s" % [h.hp, h.max_hp, "🛡" if h.invincible else ""]


# P = 패턴 패널 토글 (기본 숨김 → 맵 깨끗). 게임 입력과 안 겹치는 키.
func _unhandled_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	if ke.physical_keycode == KEY_P:
		if _panel_layer != null:
			_panel_layer.visible = not _panel_layer.visible
		get_viewport().set_input_as_handled()
	elif ke.physical_keycode == KEY_F:
		if _f_cd <= 0.0:      # 0.15s 쿨타임 — 창(0.28s)보다 짧게 → 창 직전 탭이 창 F를 안 씹게
			_f_cd = 0.15
			_try_counter()
		get_viewport().set_input_as_handled()
