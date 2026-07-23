extends Node
# 드랍 결정 권한 컴포넌트 — 호스트 전용 (rules §1·§3). 전투 스테이지가 CombatAuthority 형제로 문다.
# 결정만 한다 — 표시/스폰은 DropField, 이 둘의 책임을 나눈다 (rules §2, MobSync/CombatAuthority 미러).
#
# 드랍 롤(호스트만): enemy_killed → drop_table.roll → 호스트 고유 did 배정·킬 좌표 둘레 산개·rarity 계산
#   → 권한 레지스트리 _drops(드랍 존재의 단일 진실) 등록 → G_DROP 브로드캐스트 + drop_spawn_local(로컬 스폰).
# 선착 픽업 확정(호스트만): G_PICK_REQ(게스트발)/host_pickup(호스트 로컬발) → 존재 확인·erase → G_PICK_OK.
#   먼저 도착한 요청이 이긴다 — erase 후엔 나머지 요청이 _drops.has=false로 조용히 무시된다.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")

const SCATTER_MIN := 8.0   # 킬 좌표 둘레 산개 반경 하한(px) — 여러 드랍이 겹치지 않게
const SCATTER_MAX := 14.0  # 상한(px). 연출값(표시 배치) — 스크립트 const 허용 (rules §0 예외)

var _rng := RandomNumberGenerator.new()
var _drops: Dictionary = {}  # did -> {kind, item_id, qty, rarity, pos} — 호스트 권한 레지스트리(드랍 존재의 단일 진실)
var _did_counter: int = 0    # 단조 증가 — 호스트 고유 did "d%d" 배정


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.net_msg.connect(_on_net_msg)
	if Net.is_host():
		_rng.randomize()  # 롤은 호스트만 — 게스트는 rng를 쓰지 않는다


# 호스트 전용 — 킬 좌표에서 drop_table 롤 → did 배정·산개·rarity → 브로드캐스트 + 호스트 로컬 스폰
func _on_enemy_killed(_eid: String, def: EnemyDef, world_pos: Vector2) -> void:
	if not Net.is_host() or def == null or def.drop_table == null:
		return
	var rolled: Array = def.drop_table.roll(_rng)
	if rolled.is_empty():
		return
	var total := rolled.size()
	var wire: Array = []   # G_DROP "d" 페이로드 — [[did, kind, id, qty, x, y, rarity], …]
	var local: Array = []  # drop_spawn_local — [{did, kind, item_id, qty, rarity, pos}]
	for i in range(total):
		var r := rolled[i] as Dictionary
		var kind := str(r.get("kind", ""))
		var item_id := str(r.get("id", ""))
		var qty := int(r.get("qty", 0))
		var pos := _scatter(world_pos, i, total)
		var rarity := _rarity_of(kind, item_id)
		_did_counter += 1
		var did := "d%d" % _did_counter
		_drops[did] = {"kind": kind, "item_id": item_id, "qty": qty, "rarity": rarity, "pos": pos}
		wire.append([did, kind, item_id, qty, pos.x, pos.y, rarity])
		local.append({
			"did": did, "kind": kind, "item_id": item_id,
			"qty": qty, "rarity": rarity, "pos": pos,
		})
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_DROP, "s": GameState.stage_token(), "d": wire})
	EventBus.drop_spawn_local.emit(local)  # 호스트는 자기 G_DROP를 못 받으므로 로컬 스폰 경로


# 드랍 등급(feel 연출 등급 반짝임용) — gold=0, blueprint=2(핵심급), material=MaterialDef.rarity(없으면 0)
func _rarity_of(kind: String, item_id: String) -> int:
	match kind:
		"gold":
			return 0
		"blueprint":
			return 2
		"material":
			var m := GameState.material_def(item_id)
			return m.rarity if m != null else 0
		_:
			return 0


# 킬 좌표 둘레로 겹치지 않게 산개(반경 8~14px). 1개면 중심 그대로.
func _scatter(center: Vector2, index: int, total: int) -> Vector2:
	if total <= 1:
		return center
	var ang := TAU * float(index) / float(total)
	var r := _rng.randf_range(SCATTER_MIN, SCATTER_MAX)
	return center + Vector2(cos(ang), sin(ang)) * r


# DropField(호스트)가 로컬 플레이어 픽업 시 직접 부른다 — G_PICK_REQ와 동일 경로(존재 확인→erase→G_PICK_OK).
func host_pickup(did: String, pid: int) -> void:
	_confirm_pickup(did, pid)


# 호스트 전용 — 선착 확정. 존재하면 erase 후 G_PICK_OK 브로드캐스트, 없으면 이미 선착됨(무시).
func _confirm_pickup(did: String, pid: int) -> void:
	if not Net.is_host():
		return
	if not _drops.has(did):
		return  # 이미 다른 클라가 선착 — 무시 (선착 경합의 유일 판정점)
	_drops.erase(did)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_PICK_OK, "did": did, "pid": pid})
	EventBus.drop_pick_local.emit(did, pid)  # 호스트 로컬 반영 — 자기 G_PICK_OK 미수신(릴레이 에코 없음), 스폰의 drop_spawn_local과 대칭


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_PICK_REQ:
			# 게스트발 픽업 요청 — 호스트만 확정(내부 is_host 가드). from_id = 요청 피어 = pid.
			_confirm_pickup(str(data.get("did", "")), from_id)
