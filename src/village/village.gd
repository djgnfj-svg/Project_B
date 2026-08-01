extends Node2D
# 마을 씬 — 걸어 다니는 거점 (GDD §3). 지금은 스폰 + 출발 게이트만; 제작·강화·창고는 이후 확장.
# 씬 전환 확정 권한 = 호스트 (rules §1·§3): 호스트가 게이트 앞에서 상호작용(interact)하면
# 자식 SceneFlow가 G_SCENE 브로드캐스트 + 수신 검증을 담당 (rules §2 — 복사 금지, 스테이지와 공용).
# 피어 동기화는 자식 PeerSync가 담당 — 여기서 스폰/G_POS를 다루지 않는다.

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerActor := preload("res://src/player/player.gd")
const SceneFlowNode := preload("res://src/net/scene_flow.gd")
const UiTheme := preload("res://src/ui/ui_theme.gd")  # UI 톤 단일 소스 (HUD·패널과 같은 테마)

# 훈련소 스프라이트 — 씬이 이 경로를 ext_resource로 직접 물고, 여기서 한 번 더 런타임 로드해
# **offset을 텍스처 크기에서 유도**한다(아트를 갈아도 씬을 안 만지게 — 발밑 원점 규약).
# ⚠ .tscn에 없는 경로를 ext_resource로 박으면 씬 로드가 깨지므로 반드시 런타임 검사로 문다.
const TRAIN_TEX_PATH := "res://assets/sprites/village/train_station.png"

var _local_in_gate: bool = false  # 로컬 플레이어가 게이트 영역 안 — 상호작용 게이트 + 안내 표시
var _local_in_craft: bool = false  # 로컬 플레이어가 제작대 영역 안 — F로 제작/강화 패널 오픈
var _local_in_train: bool = false  # 로컬 플레이어가 훈련소 영역 안 — F로 하위 직업 패널 오픈

# 마을 맵 크기 = $Ground(TileMapLayer)에 깐 셀 범위 — 30×18셀 × 32px (미러).
# ⚠ 에디터에서 바닥을 넓히면 여기도 같이 늘려야 카메라가 새 영역을 보여준다. 안 늘리면
#   에러 없이 "걸어갔는데 화면이 안 따라오는" 상태가 된다.
const MAP_RECT := Rect2(0, 0, 960, 576)

# 빌드 버전 — 배포할 때마다 갱신. 마을 우상단에 표시(캐시=구버전 판별 + 인원수 체크용)
const BUILD_VERSION := "v0731a-forest"

var _info_label: Label = null
var _info_left: float = 0.0

@onready var _gate: Area2D = $Gate
@onready var _hint: Label = $Gate/Hint
@onready var _scene_flow: SceneFlowNode = $SceneFlow
@onready var _craft_station: Area2D = $CraftStation
@onready var _craft_hint: Label = $CraftStation/Hint
@onready var _craft_panel: CanvasLayer = $CraftPanel
@onready var _train_station: Area2D = $TrainStation
@onready var _train_hint: Label = $TrainStation/Hint
@onready var _train_sprite: Sprite2D = $TrainStation/Sprite
@onready var _subjob_panel: CanvasLayer = $SubJobPanel


func _ready() -> void:
	add_to_group("village")  # 설정 패널이 "마을인지" 판별 (직업 변경 활성·마을로 가기 숨김)
	_gate.body_entered.connect(_on_gate_body_entered)
	_gate.body_exited.connect(_on_gate_body_exited)
	_hint.visible = false
	_craft_station.body_entered.connect(_on_craft_body_entered)
	_craft_station.body_exited.connect(_on_craft_body_exited)
	_craft_hint.visible = false
	# 훈련소 — 제작대 블록의 복제(같은 규약: 로컬 각자 열기·interact 레이어 7·안내 라벨)
	_train_station.body_entered.connect(_on_train_body_entered)
	_train_station.body_exited.connect(_on_train_body_exited)
	_train_hint.visible = false
	_apply_train_texture()
	set_meta("map_rect", MAP_RECT)  # 카메라 맵 클램프 — camera_rig가 스폰 시 읽는다
	_style_world_hints()
	_build_info_overlay()


# 월드 위에 떠 있는 안내 라벨(게이트·제작대·훈련소) 정리.
# 🔴 **mouse_filter** — Label 기본값은 STOP이라, Node2D 밑에 있어도 그 사각형(가로 160~200px)이
#   그 아래 게임 클릭을 통째로 먹는다(에러·경고 없음, 헤드리스 검출 불가 — rules §5 1번 함정).
#   안내는 장식이므로 전부 IGNORE. 톤은 HUD 라벨과 같은 등급(외곽선 = 밝은 바닥 위에서도 읽힘).
func _style_world_hints() -> void:
	for lbl: Label in [_hint, _craft_hint, _train_hint]:
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.theme = UiTheme.get_theme()  # 월드 라벨은 Control 조상이 없어 상속이 안 온다
		lbl.theme_type_variation = &"HudLabel"


# 버전·인원 표시 (캐시 판별 + 2인 접속 확인). 표시 전용 오버레이.
# ⚠ **우상단**이다 — 좌상단은 HUD 방 코드 줄(핑·경로·fps) 자리라, 여기 있던 시절엔 마을에서 두 줄이
#   같은 픽셀에 겹쳐 찍혔다(이 오버레이가 layer 9 = HUD보다 위). 겹치는 코너를 나눠 갖는다.
func _build_info_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	_info_label = Label.new()
	_info_label.theme = UiTheme.get_theme()
	_info_label.theme_type_variation = &"HudLabel"
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 — 아래 게임 클릭을 먹지 않게(§5)
	_info_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_info_label.offset_left = -240.0
	_info_label.offset_top = 4.0
	_info_label.offset_right = -6.0
	_info_label.offset_bottom = 20.0
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(_info_label)
	_refresh_info()


func _refresh_info() -> void:
	if _info_label != null:
		_info_label.text = "%s · 인원 %d/%d" % [BUILD_VERSION, Net.peer_ids.size() + 1, NetSchema.MAX_ROOM_PEERS]


func _process(delta: float) -> void:
	# 인원수는 피어 합류/이탈로 변하므로 주기적 갱신 (1초)
	_info_left -= delta
	if _info_left <= 0.0:
		_info_left = 1.0
		_refresh_info()


# 훈련소 텍스처 — 전용 아트가 임포트돼 있으면 쓰고, 없으면 씬의 폴백을 유지한다.
# 어떤 크기가 와도 발밑(하단 중앙)이 노드 좌표에 오게 offset을 유도한다 — 아트 교체 시 씬을 안 만지게.
func _apply_train_texture() -> void:
	if ResourceLoader.exists(TRAIN_TEX_PATH):
		var tex := load(TRAIN_TEX_PATH) as Texture2D
		if tex != null:
			_train_sprite.texture = tex
	var t := _train_sprite.texture
	if t != null:
		_train_sprite.offset = Vector2(-t.get_width() * 0.5, -float(t.get_height()))


# 출발 확인은 폴링이 아니라 _unhandled_input — UI(Control)가 소비한 입력은 여기 안 온다
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	# 제작대 — 로컬 각자 열기(제작/강화는 로컬, 호스트 제한 없음). 패널 열고 입력 소비(같은 F가 패널 닫기에 안 걸리게).
	if _local_in_craft:
		_craft_panel.call("open")
		get_viewport().set_input_as_handled()
		return
	# 훈련소 — 하위 직업 조회 + 메인 지정(로컬 각자, 마을 전용 GDD §5). 제작대와 같은 규약.
	if _local_in_train:
		_subjob_panel.call("open")
		get_viewport().set_input_as_handled()
		return
	# 출발 게이트 — 게스트의 F는 SceneFlow가 무시(출발 권한은 호스트만). 챕터 선택은 후속(GDD §6).
	if _local_in_gate:
		_scene_flow.request_stage(GameState.DEFAULT_CHAPTER_ID, 0)


func _on_gate_body_entered(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return  # 원격 아바타의 진입은 무시 — 안내·상호작용은 각자 자기 로컬만
	_local_in_gate = true
	if Net.is_host():
		_hint.text = "F — %s 출발" % GameState.chapter_def(GameState.DEFAULT_CHAPTER_ID).display_name
	else:
		_hint.text = "방장이 출발할 수 있어요"
	_hint.visible = true


func _on_gate_body_exited(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return
	_local_in_gate = false
	_hint.visible = false


func _on_craft_body_entered(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return
	_local_in_craft = true
	_craft_hint.text = "F — 제작 / 강화"
	_craft_hint.visible = true


func _on_craft_body_exited(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return
	_local_in_craft = false
	_craft_hint.visible = false


func _on_train_body_entered(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return  # 원격 아바타의 진입은 무시 — 안내·상호작용은 각자 자기 로컬만
	_local_in_train = true
	_train_hint.text = "F — 훈련소 (하위 직업)"
	_train_hint.visible = true


func _on_train_body_exited(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return
	_local_in_train = false
	_train_hint.visible = false
