extends Area2D
# 드랍 아이템 표시 엔티티 — DropField가 런타임에 스폰·필드 설정·텍스처를 물린다.
# 물리 레이어 6=pickup, mask 2=player_body (rules §5 배정표). 로컬 플레이어와 겹치면 스폰한
# DropField에 픽업 요청(중복 가드) — Net을 직접 부르지 않는다, DropField 경유 (rules §0·§2).
# 비주얼=Sprite2D + 텍스처(도형 금지 rules §0). 텍스처는 스폰 시 DropField가 리졸브해 넘긴다.
# 살짝 위아래 bobbing = 표시 전용 연출값(스크립트 const 허용). 착지 팝·등급 반짝임은 feel(item_dropped)이 맡는다.

const BOB_AMPLITUDE := 2.0   # 위아래 흔들림 폭(px) — 연출값
const BOB_PERIOD := 1.2      # 흔들림 주기(s)
const POP_TIME := 0.26       # 등장 스케일 팝 시간(s) — 튀어오르며 등장
const GLOW_PERIOD := 0.9     # 등급 반짝임 펄스 주기(s)
# 등급별 반짝임 색조(흰↔틴트 lerp) — 0=일반(반짝임 없음)·1=희귀 청·2=핵심 금 (MaterialDef.rarity 미러)
const RARITY_TINT := {1: Color(0.72, 0.85, 1.0), 2: Color(1.0, 0.9, 0.55)}

# DropField가 setup으로 채운다 — 픽업 확정 시 DropField가 이 값들을 읽어 collect_drop한다.
var did: String = ""
var kind: String = ""
var item_id: String = ""
var qty: int = 0
var rarity: int = 0

var _field: Node = null        # 스폰한 DropField (픽업 요청 경유) — Net 직접 호출 회피
var _texture: Texture2D = null # setup 시점(@onready 전)엔 보관만, _ready에서 스프라이트에 물린다
var _requested: bool = false   # 중복 픽업 요청 차단
var _t: float = 0.0

@onready var _sprite: Sprite2D = $Sprite


# DropField._spawn이 add_child 전에 부른다 — 노드 접근 없이 값만 보관 (@onready 미해결 시점)
func setup(p_did: String, p_kind: String, p_item_id: String, p_qty: int,
		p_rarity: int, tex: Texture2D, field: Node) -> void:
	did = p_did
	kind = p_kind
	item_id = p_item_id
	qty = p_qty
	rarity = p_rarity
	_texture = tex
	_field = field


func _ready() -> void:
	_sprite.texture = _texture  # null이어도 안전 — 안 보일 뿐
	body_entered.connect(_on_body_entered)
	# 등장 스케일 팝 — 작게 시작해 오버슛하며 튀어오른다(표시 전용). 트윈은 노드에 바인딩 →
	# 즉시 픽업으로 queue_free돼도 자동 정리(freed 접근 없음).
	_sprite.scale = Vector2.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", Vector2.ONE, POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 표시 전용 bobbing + 등급 반짝임 — 스프라이트 자식만 건드려 Area2D 판정/좌표는 그대로.
func _process(delta: float) -> void:
	_t += delta
	_sprite.position.y = sin(_t / BOB_PERIOD * TAU) * BOB_AMPLITUDE
	if rarity > 0:  # 희귀/핵심만 은은한 색 펄스 — 색조 유지, 밝기만 왕복
		var pulse := 0.5 + 0.5 * sin(_t / GLOW_PERIOD * TAU)
		_sprite.modulate = Color.WHITE.lerp(RARITY_TINT.get(rarity, Color.WHITE), 0.35 + 0.4 * pulse)


# 로컬 플레이어만 픽업 요청 — 원격 아바타/적은 무시. _requested로 중복 차단.
func _on_body_entered(body: Node2D) -> void:
	if _requested or _field == null:
		return
	if not body.is_in_group("player"):
		return
	if body.get("is_local") != true:
		return  # 원격 플레이어 겹침은 픽업 아님 (선착은 각자 로컬 플레이어 기준)
	_requested = true
	_field.call("request_pickup", did)
