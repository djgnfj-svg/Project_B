extends Node
# 테스트 랩 컨트롤러 — ?test=1일 때 main이 보스 아레나에 붙인다 (TestMode 게이트, 프로덕션 무접촉·rules §5 씬 글루).
# 그림 구조: 아레나[보스 + player1(무적) + NPC 더미(무적, 코옵 2인 채움)] + 우측 패턴/상태 패널.
#  · 보스 자동공격·코옵 자동순환을 끄고(debug_hold) → 버튼으로 특정 패턴만 즉시 발동해 관찰·튜닝.
#  · 체크박스로 현재 상태(무적/보스정지/코옵정지/NPC) 확인·토글. HP 회복 버튼.
#  · 2인 실기: NPC 체크 해제하면 더미 제거 → 실제 2명으로 테스트.

const PlayerScene := preload("res://src/player/player.tscn")
const PlayerActor := preload("res://src/player/player.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")
const UiTheme := preload("res://src/ui/ui_theme.gd")   # UI 톤 단일 소스 (HUD·패널과 같은 팔레트 — class_name 대신 preload, rules §0)
const NetSchema := preload("res://src/core/net_schema.gd")  # SCENE_* id (새 보스 리셋 = 스테이지 재진입)
const Afterimage := preload("res://src/feel/afterimage.gd")  # 카운터 대시 잔상 (손맛 재사용)

# 코옵 파훼 버튼 (인덱스 = coop_authority MECHS 순서)
const COOP_BTNS: Array = [["케이지", 0], ["별낙하", 1], ["봉인진", 2], ["분산", 3], ["뭉치기", 4], ["직면", 5]]

var _boss: Node = null
var _coop: Node = null
var _npc: PlayerActor = null
var _boss_rim: AnimatedSprite2D = null   # 보스 뒤 밝은 실루엣(림) — 청록 배경에서 보스를 또렷하게

var _invincible: bool = true
var _npc_on: bool = true

var _cb_invin: CheckBox = null
var _cb_boss: CheckBox = null
var _cb_coop: CheckBox = null
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
const COUNTER_INTERVAL := 5.0   # IDLE 대기(s)
const COUNTER_GLINT := 0.5      # 눈 반짝(s)
const CHARGE_AIM := 0.5         # 조준: 바라봄 + 줄 생김(s)
const CHARGE_SPEED := 1550.0    # 돌진 속도(px/s) — x2.5 (반응해서 패링 가능한 속도)
# 진짜 패링: 돌진 중 보스가 근접하면 받아치기 창이 열리고, 그 안에서만 F 성공. 이른 F는 헛침(잠금).
const PARRY_OPEN_RANGE := 165.0 # 돌진 중 보스가 이 안이면 창 열림(여유 있게 미리)
const PARRY_WINDOW := 0.28      # 창 지속(s) — 이 안에 F. 돌진 끝에 안 잘리고 제 시간 유지
# 🔴 카운터/돌진은 tween으로 위치를 바꿔 벽 충돌을 우회 → 맵 밖으로 나감. 이 안전영역으로 클램프(벽 안쪽).
const ARENA_SAFE := Rect2(-566.0, 170.0, 1472.0, 308.0)
const CS_IDLE := 0
const CS_GLINT := 1
const CS_AIM := 2
const CS_DASH := 3
var _counter_marker: Node2D = null
var _counter_poly: Polygon2D = null
var _counter_label: Label = null
var _eye_glint: Node2D = null
var _counter_t: float = 0.0     # 마커 맥동 위상
var _cstate: int = CS_IDLE
var _cstate_t: float = 0.0
var _charge_dir: Vector2 = Vector2.RIGHT     # 돌진 방향(조준 시 고정) — 이 방향으로 직진
var _charge_traveled: float = 0.0            # 돌진 이동 거리 안전 상한용
var _parry_open_t: float = -1.0   # >=0 = 받아치기 창 열림 카운트다운, -1 = 아직 안 열림
var _parry_used: bool = false     # 이번 돌진에서 이른 F로 헛치면 잠금(스팸 방지)
var _lock_linger: float = 0.0     # 잠금(빨간 ✕)을 눈에 보이게 잠깐 더 유지
var _clashing: bool = false       # 클래시(성공 연출) 진행 중 — 이때도 구르기 억제(연타 F가 tween과 충돌해 벽 뚫는 것 방지)
var _f_cd: float = 0.0            # 받아치기 F 쿨타임(0.5s) — 연타 방지


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
	mat.set_shader_parameter(&"vignette_strength", 0.55)
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
	cm.color = Color(0.10, 0.10, 0.15)   # 씬 더 어둡게 → 집중광이 튄다
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
	# 눈 반짝(예고) — 보스 눈 위치에 밝은 두 점. GLINT 국면에만 보임.
	var glint := Node2D.new()
	glint.name = "EyeGlint"
	glint.z_index = 8
	glint.visible = false
	get_parent().add_child(glint)
	for dx: float in [-8.0, 8.0]:
		var eye := Sprite2D.new()
		eye.texture = _light_tex()
		eye.scale = Vector2.ONE * 0.12
		eye.modulate = Color(0.85, 1.0, 0.95, 1.0)
		var em := CanvasItemMaterial.new()
		em.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		eye.material = em
		eye.position = Vector2(dx, 0.0)
		glint.add_child(eye)
	_eye_glint = glint


# 카운터 상태머신(호출: _process): IDLE(5초) → GLINT(눈 반짝) → AIM(바라봄+줄) → DASH(돌진, 도중 F=카운터).
func _update_counter(lp: PlayerActor, delta: float) -> void:
	if _counter_marker == null or not is_instance_valid(_counter_marker) or _boss == null:
		return
	_counter_t += delta
	lp.roll_suppressed = (_cstate != CS_IDLE) or _clashing   # 카운터 시퀀스+클래시 내내 구르기 억제(연타 F 튀어나감 방지)
	var h := _boss.get_node_or_null("Health") as HealthComponent
	if h == null or h.hp <= 0:   # 죽으면 전부 끔
		_reset_counter()
		return
	_cstate_t += delta
	match _cstate:
		CS_IDLE:
			_counter_marker.visible = false
			_eye_glint.visible = false
			_boss.counter_ready = false
			if _cstate_t >= COUNTER_INTERVAL:
				_cstate = CS_GLINT
				_cstate_t = 0.0
		CS_GLINT:
			# 눈 반짝(예고). 아직 조준·돌진 전.
			_counter_marker.visible = false
			_boss.counter_ready = false
			_eye_glint.visible = true
			_eye_glint.global_position = _boss.global_position + EYE_OFFSET
			_eye_glint.scale = Vector2.ONE * (0.5 + 0.7 * absf(sin(_cstate_t * TAU * 5.0)))
			if _cstate_t >= COUNTER_GLINT:
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
			if _cstate_t >= CHARGE_AIM:
				_cstate = CS_DASH
				_cstate_t = 0.0
				_parry_open_t = -1.0     # 받아치기 창 초기화
				_parry_used = false
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
			_show_counter_marker_on_boss(lp)
			# 이동(고정 방향 직진, 🔴 맵 클램프 — 벽 뚫고 날아가지 않게)
			var step := CHARGE_SPEED * delta
			_boss.global_position = _clamp_arena(_boss.global_position + _charge_dir * step)
			_charge_traveled += step
			# 종료: 뒤를 지나간 순간(이동 후 재판정) = 실패(잠금이면 빨간 ✕ 잠깐 유지) · 안전 상한도
			var passed: bool = (_boss.global_position - lp.global_position).dot(_charge_dir) > 0.0
			if passed or _charge_traveled > 550.0:
				if _parry_used and _lock_linger > 0.0:
					_lock_linger -= delta
				else:
					_charge_hit(lp)        # 내 뒤를 지나감 = 실패
					_reset_counter()


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
	_lock_linger = 0.0
	if _counter_marker != null:
		_counter_marker.visible = false
	if _eye_glint != null:
		_eye_glint.visible = false
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
		_reset_counter()      # 창 안 — 카운터 성공
		_counter_strike(lp)
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
	EventBus.screen_shake.emit(7.0)
	_popup_text(pos + Vector2(0.0, -42.0), "성공!", Color(0.65, 1.0, 0.72))


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
	# 🔴 플레이어 넉백 제거 — 위치 고정(사용자 요청). 대신 실패 후 보스를 플레이어 근처(±1m)로 텔포한다
	#    (뒤로 스쳐 지나간 보스가 다음 사이클을 위해 다시 근접 위치로).
	var ang: float = randf() * TAU
	var dist: float = 40.0 + randf() * 18.0   # ~1m 내외
	_boss.global_position = _clamp_arena(lp.global_position + Vector2(cos(ang), sin(ang)) * dist)


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
	_add_title(vb, "· 코옵")
	var g_coop := _grid(vb, 2)
	for e: Array in COOP_BTNS:
		_add_btn(g_coop, str(e[0]), _on_coop.bind(int(e[1])))

	vb.add_child(HSeparator.new())
	var g_chk := _grid(vb, 2)
	_cb_invin = _add_check(g_chk, "무적", _invincible, _on_invin)
	_cb_boss = _add_check(g_chk, "보스정지", true, _on_boss_hold)
	_cb_coop = _add_check(g_chk, "코옵정지", true, _on_coop_hold)
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
	_cstate = CS_GLINT      # 전체 시퀀스: 눈 반짝 → 조준 → 돌진
	_cstate_t = 0.0


func _on_force_charge() -> void:
	_cstate = CS_GLINT      # 눈 반짝 건너뛰고 즉시 조준(AIM)으로
	_cstate_t = COUNTER_GLINT


func _on_coop(idx: int) -> void:
	if _coop != null and _coop.has_method("debug_force_mech"):
		_coop.debug_force_mech(idx)


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


func _on_coop_hold(on: bool) -> void:
	if _coop != null:
		_coop.debug_hold = on


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
		if _f_cd <= 0.0:      # 0.5s 쿨타임 — 연타 방지
			_f_cd = 0.5
			_try_counter()
		get_viewport().set_input_as_handled()
