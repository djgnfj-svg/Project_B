extends Node2D
# 마을 씬 — 걸어 다니는 거점 (GDD §3). 지금은 스폰 + 출발 게이트만; 제작·강화·창고는 이후 확장.
# 씬 전환 확정 권한 = 호스트 (rules §1·§3): 호스트가 게이트 앞에서 상호작용(interact)하면
# 자식 SceneFlow가 G_SCENE 브로드캐스트 + 수신 검증을 담당 (rules §2 — 복사 금지, 스테이지와 공용).
# 피어 동기화는 자식 PeerSync가 담당 — 여기서 스폰/G_POS를 다루지 않는다.

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
@onready var _train_dummy: Area2D = $TrainDummy
@onready var _job_select_panel: CanvasLayer = $JobSelectPanel


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
	# 훈련소 허수아비 — 좌클릭하면 직업 선택 카드 창을 연다(클릭 전용, 전투 판정 없음).
	#   각 클라 로컬 오버레이라 호스트 제한이 없다(제작대·훈련소 패널과 같은 규약).
	_train_dummy.clicked.connect(_on_train_dummy_clicked)
	set_meta("map_rect", MAP_RECT)  # 카메라 맵 클램프 — camera_rig가 스폰 시 읽는다
	_style_world_hints()
	# 🔴 **우상단 버전·인원 배지는 2026-08-02에 화면에서 뺐다** — ESC 메뉴로 갔다(사용자 요구:
	#   *"ui 줄이기(너무 많음 ESC에 다 들어가게 하자), 글자를 줄이고"*). 잃은 것은 없다:
	#   빌드 버전은 `SettingsPanel`이 `BUILD_VERSION`을 읽어 띄우고, 인원은 방 줄에 `n/m명`으로 붙는다.
	#   ⚠ **상수는 여기 남겨 둔다** — 배포할 때마다 갱신하는 값이고, 그 절차가 이 파일에 묶여 있다.


# 월드 위에 떠 있는 안내 라벨(게이트·제작대·훈련소) 정리.
# 🔴 **mouse_filter** — Label 기본값은 STOP이라, Node2D 밑에 있어도 그 사각형(가로 160~200px)이
#   그 아래 게임 클릭을 통째로 먹는다(에러·경고 없음, 헤드리스 검출 불가 — rules §5 1번 함정).
#   안내는 장식이므로 전부 IGNORE. 톤은 HUD 라벨과 같은 등급(외곽선 = 밝은 바닥 위에서도 읽힘).
func _style_world_hints() -> void:
	for lbl: Label in [_hint, _craft_hint, _train_hint]:
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.theme = UiTheme.get_theme()  # 월드 라벨은 Control 조상이 없어 상속이 안 온다
		lbl.theme_type_variation = &"HudLabel"


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
	# 직업 선택(직업 변경) — H 키로 어디서든 토글. 허수아비 좌클릭이 불안정해 키 진입을 보탠 것(사용자 요청).
	#   로컬 오버레이라 호스트 제한 없음 — 패널이 판 도중 잠금·거부를 GameState 기준으로 처리한다.
	if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (event as InputEventKey).keycode == KEY_H:
		if _job_select_panel.visible:
			_job_select_panel.call("close")
		else:
			_job_select_panel.call("open")
		get_viewport().set_input_as_handled()
		return
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


# 허수아비 좌클릭 → 직업 선택 카드 창(로컬 오버레이). 마우스 클릭이므로 게이트 진입(F)과 무관하게
# 어디서든 클릭으로 연다. 패널 자신이 판 도중 잠금·거부를 GameState 기준으로 처리한다.
func _on_train_dummy_clicked() -> void:
	_job_select_panel.call("open")
