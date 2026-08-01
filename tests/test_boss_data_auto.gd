extends SceneTree
# 보스 데이터 계약 — `data/enemies/*.tres` 전수 스캔 (신설 2026-07-26).
#
# 왜 데이터만 보나: `src/enemies/boss.gd`는 씬 전용 글루라 `-s`에서 preload가 안 된다
#   (EventBus/Net 전역 식별자 — rules §5). 그래서 코드는 헤드리스로 못 잡지만,
#   **이번에 드러난 함정 대부분은 데이터 쪽**이었고 그건 `.tres`만 읽으면 잡힌다.
#
# 전부 **에러를 안 낸다** — 그게 여기 있는 이유다:
#   ⑴ 패턴 id와 같은 이름의 애니가 없으면 `_play`의 `_has_anim` 가드가 조용히 건너뛴다 → 공격 모션 무.
#   ⑵ 공격 애니가 `loop = true`면 `is_playing()`이 영원히 true라 `_anim_scale` 복귀와 idle 복귀가
#      통째로 멈춘다 → 애니 무한 반복 + 늘려둔 speed_scale이 다음 애니로 굳는다.
#   ⑶ `walk`가 없으면 이동 시 idle로 미끄러지고(옛 결함), 공격 애니 이름이 안 갈려
#      다음 예고가 이전 스윙 마지막 프레임으로 얼어붙는다.
#   ⑷ 애니 길이가 `telegraph_s`와 크게 갈라지면 `speed_scale` 배율이 1에서 멀어져
#      휘두름이 슬로모션/속사처럼 보인다(코드는 길이를 맞춰주지만 배속은 못 숨긴다).
#   ⑸ `telegraph_s = 0`이면 boss.gd의 센티널(`_telegraph_hold_s > 0.0`)이 호스트/게스트에서
#      다르게 읽혀 예고 지속·애니 배율이 갈라진다.
#
# ⚠ 파일명·프레임 수·애니 개수를 박지 않는다 — **새 보스 `.tres`가 자동으로 이 단정에 걸리게**
#   ("새 보스 = 파일 한 장", rules §4). 이 스크립트는 오토로드를 안 쓴다.

const DATA_DIR := "res://data/enemies"
# 애니 기본 길이 ≤ telegraph_s × 이 배수. 정확일치를 요구하지 않는 이유 = boss.gd가 매 회차
# speed_scale로 길이를 맞추기 때문(예고 길이는 지연 보상분 때문에 RTT에 따라 가변이다).
# 즉 이건 "배율이 1에서 너무 멀지 않은가" = 아트와 데이터가 크게 갈라지지 않았나의 트립와이어다.
const LEN_TOLERANCE := 1.5

# 4대각 facing 접미사 — boss.gd `_dir_suffix`가 내놓는 값의 전체 집합. 보스는 어느 facing으로도
# 설 수 있으므로 모든 방향에서 애니가 풀려야 "조용한 무모션"이 안 난다.
const DIRS := ["se", "sw", "nw", "ne"]

var _fail := 0
var _checks := 0


# 🔴 boss.gd `_resolve_dir_anim` **미러** — 이 파일은 boss.gd를 preload 못 하므로(헤더 참조) 유도식을
#   여기 재현한다. 한쪽을 고치면 같이 고쳐라. base가 주어진 facing에서 실제 존재하는 애니로 풀리면
#   그 이름을, 아무것도 안 풀리면 ""(= `_play`의 `_has_anim` 가드가 조용히 건너뛰는 경우)을 돌려준다.
func _resolve(sf: SpriteFrames, base: String, dir: String) -> StringName:
	if base == "idle" or base == "slam" or base == "swing" or base == "spray" or base == "spin":
		var d := StringName(base + "_" + dir)
		if sf.has_animation(d):
			return d
		if base == "swing" or base == "spray" or base == "spin":   # 방향 전용 공격 없으면 slam_<dir> 재사용(플레이스홀더)
			var sd := StringName("slam_" + dir)
			if sf.has_animation(sd):
				return sd
	elif base == "walk":
		var wd := StringName("walk_" + dir)
		if sf.has_animation(wd):
			return wd
		var idle_d := StringName("idle_" + dir)   # walk 없으면 방향 idle로 — 이동 중에도 안 등짐
		if sf.has_animation(idle_d):
			return idle_d
	if sf.has_animation(StringName(base)):   # 단방향 보스 폴백 — base 그대로
		return StringName(base)
	return &""


# base가 **모든** facing에서 재생 가능한 애니로 풀리는가. 단방향 보스는 4방향 모두 bare base로 풀린다.
func _resolves_all(sf: SpriteFrames, base: String) -> bool:
	for d: String in DIRS:
		if _resolve(sf, base, d) == &"":
			return false
	return true


func _init() -> void:
	_run()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s" % label)


# 애니 기본 재생 길이(초) = Σ프레임 duration / speed. `boss.gd _anim_base_length`와 같은 유도식을
# 여기서 재현한다 — 그 파일을 preload할 수 없기 때문이다(위 헤더). 프레임 duration은 프레임별로
# 다를 수 있어 개수로 가정하지 않고 합산한다.
func _anim_len(sf: SpriteFrames, anim: StringName) -> float:
	if not sf.has_animation(anim):
		return 0.0
	var speed := sf.get_animation_speed(anim)
	var count := sf.get_frame_count(anim)
	if speed <= 0.0 or count <= 0:
		return 0.0
	var total := 0.0
	for i in count:
		total += sf.get_frame_duration(anim, i)
	return total / speed


# data/enemies 전수 스캔 → BossDef만. 스캔 규약은 GameState._scan_ids 미러(.remap = 익스포트 빌드).
func _boss_defs() -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(DATA_DIR):
		var base := f.trim_suffix(".remap")
		if base.get_extension() != "tres" and base.get_extension() != "res":
			continue
		var res: Resource = load("%s/%s" % [DATA_DIR, base])
		if res is BossDef:
			out.append([base, res as BossDef])
	return out


func _check_boss(file: String, def: BossDef) -> void:
	var sf := def.frames
	if sf == null:
		# frames가 없으면 boss.gd가 sprite 1장을 idle로 감싼다 → 공격 애니가 통째로 없다
		_check(false, "%s: frames(SpriteFrames)가 없다 — 공격 애니가 통째로 안 나온다" % file)
		return
	# 방향 인지 — idle/walk가 4방향 모두에서 풀려야(방향 변형 또는 단방향 bare). boss.gd `_resolve_dir_anim` 미러.
	_check(_resolves_all(sf, "idle"), "%s: idle 애니가 모든 facing에서 풀린다(방향 변형 포함)" % file)
	_check(_resolves_all(sf, "walk"),
		"%s: walk 애니가 모든 facing에서 풀린다 (없으면 이동 미끄러짐 + 다음 공격 애니가 얼어붙는다)" % file)
	if sf.has_animation(&"death"):
		# 시체 남김이 loop=false 전제 — 반복되면 시체가 계속 죽는 모션을 반복한다
		_check(not sf.get_animation_loop(&"death"), "%s: death loop=false (시체 남김 전제)" % file)
	_check(not def.patterns.is_empty(), "%s: patterns가 1개 이상 (%d개)" % [file, def.patterns.size()])
	for p: BossPatternDef in def.patterns:
		if p == null:
			_check(false, "%s: patterns에 null 항목" % file)
			continue
		var label := "%s/%s" % [file, p.id]
		_check(not p.id.is_empty(), "%s: 패턴 id가 비어 있지 않다" % label)
		_check(p.telegraph_s > 0.0,
			"%s: telegraph_s > 0 (%.2f) — 0이면 호스트/게스트 예고 지속이 갈라진다"
			% [label, p.telegraph_s])
		# range = 판정 반경(원)/사거리(콘)이자 셰이더가 그리는 반지름. 0이면 판정은 사실상 안 맞는데
		# 예고는 픽셀 격자+여유 때문에 작은 블롭으로 **보인다** — 이 계약에서 유일하게 "보이는데 안
		# 맞는" 방향의 이탈이라(나머지는 전부 과예고 = 안전) 데이터로 못 들어오게 막는다.
		_check(p.range > 0.0,
			"%s: range > 0 (%.1f) — 0이면 예고만 보이고 판정이 없다"
			% [label, p.range])
		# 돌진(P3)은 pat.id 애니가 아니라 상태머신이 placeholder 클립(windup=slam·dash=walk)을 직접 몬다
		# → id 애니 존재 계약에서 제외. 대신 돌진 전용 파라미터가 유효한지 본다(0이면 안 움직이거나 못 맞힌다).
		if p.is_charge:
			_check(p.charge_speed > 0.0, "%s: charge_speed > 0 (%.1f)" % [label, p.charge_speed])
			_check(p.charge_sweep_radius > 0.0,
				"%s: charge_sweep_radius > 0 (%.1f) — 0이면 스윕이 아무도 못 맞힌다" % [label, p.charge_sweep_radius])
			_check(p.charge_travel_max > 0.0, "%s: charge_travel_max > 0 (%.1f)" % [label, p.charge_travel_max])
			continue
		# 패턴 id가 **모든 facing**에서 재생 가능한 애니로 풀려야 (방향 변형·slam_<dir> 폴백 포함).
		_check(_resolves_all(sf, p.id),
			"%s: 패턴 id가 모든 facing에서 애니로 풀린다 (없으면 공격 모션이 조용히 안 나온다)" % label)
		# loop·길이 검사는 실제 풀린 애니로 한다 — front(se) 방향 대표값. 안 풀리면 건너뛴다.
		var anim := _resolve(sf, p.id, "se")
		if anim == &"":
			continue
		_check(not sf.get_animation_loop(anim),
			"%s: loop=false (true면 무한 반복 + speed_scale 굳음) [%s]" % [label, anim])
		var base := _anim_len(sf, anim)
		_check(base > 0.0, "%s: 애니 길이 > 0 (프레임 %d · speed %.2f) [%s]"
			% [label, sf.get_frame_count(anim), sf.get_animation_speed(anim), anim])
		var ratio := (base / p.telegraph_s) if p.telegraph_s > 0.0 else INF
		_check(ratio <= LEN_TOLERANCE,
			"%s: 애니 %.3fs ≤ telegraph_s %.2fs × %.1f (speed_scale %.3f 필요)"
			% [label, base, p.telegraph_s, LEN_TOLERANCE, ratio])


# 원거리 잔몹 = `CombatMath.is_ranged_enemy(def)`(BossDef 제외). data/enemies 전수.
# 🔴 판별을 여기서 다시 쓰지 않고 **그 함수를 지난다** — 사본을 두면 배우 분기와 이 검사가 갈라져,
#   "코드는 근접으로 도는데 테스트는 원거리 계약으로 통과"가 된다.
func _ranged_defs() -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(DATA_DIR):
		var base := f.trim_suffix(".remap")
		if base.get_extension() != "tres" and base.get_extension() != "res":
			continue
		var res: Resource = load("%s/%s" % [DATA_DIR, base])
		if res is EnemyDef and not (res is BossDef) and CombatMath.is_ranged_enemy(res as EnemyDef):
			out.append([base, res as EnemyDef])
	return out


# 🔴 원거리 잔몹 데이터 계약 — 넷 다 어기면 **에러 없이** 깨진다.
#   배우(`mob_melee.gd`)·판정(`combat_authority.gd`)이 씬 글루라 `-s`가 preload를 못 한다 =
#   그 경로는 스위트의 구조적 사각이다. 그래서 규칙을 데이터 축으로 밀어 여기서 잡는다(리뷰 J-1·J-2).
func _check_ranged(file: String, def: EnemyDef) -> void:
	# ⑴ 사거리 안에서 쏴도 화살이 먼저 만료되면 한 발도 안 닿는다.
	_check(def.proj_range >= def.attack_range,
		"%s: proj_range %.0f ≥ attack_range %.0f — 작으면 발사 지점에서 만료돼 영원히 못 맞힌다"
		% [file, def.proj_range, def.attack_range])
	# ⑵ 명중 반경 0 = 영원히 안 맞음. `swing_arc > 0` 트립와이어의 정확한 미러.
	_check(def.strike_radius > 0.0,
		"%s: strike_radius > 0 (%.1f) — 0이면 화살이 통과만 한다" % [file, def.strike_radius])
	# ⑶ 카이팅 거리가 사거리 이상이면 자기 사거리 밖으로 물러나 영구 진동하며 한 발도 못 쏜다.
	_check(def.keep_dist < def.attack_range,
		"%s: keep_dist %.0f < attack_range %.0f — 크면 물러나기만 하고 못 쏜다"
		% [file, def.keep_dist, def.attack_range])
	# ⑷ 터널링 불변식(§5·§3 화살 계약의 몹 버전) — 프레임당 전진이 명중 지름보다 크면 통과한다.
	var step := def.proj_speed / 60.0
	_check(step < def.strike_radius * 2.0,
		"%s: 프레임당 전진 %.1fpx < 명중 지름 %.1fpx — 넘으면 플레이어를 관통한다"
		% [file, step, def.strike_radius * 2.0])
	# ⑸ 카이팅 후퇴도 move_speed라 몹 좌표 지연 슬랙 유도(MOB_LAG_SLACK_SPEED)에 포함된다.
	_check(def.move_speed <= CombatMath.MOB_LAG_SLACK_SPEED,
		"%s: move_speed %.0f ≤ MOB_LAG_SLACK_SPEED %.0f"
		% [file, def.move_speed, CombatMath.MOB_LAG_SLACK_SPEED])
	_check(def.proj_texture != null,
		"%s: proj_texture 지정(§0 — 도형·폴백으로 때우지 않는다)" % file)


func _run() -> void:
	var bosses := _boss_defs()
	# 스캔이 0건이면 아래 단정이 전부 건너뛰어져 **조용히 통과**한다 (verify §3 침묵 통과 방지)
	_check(not bosses.is_empty(),
		"%s 스캔: BossDef가 1개 이상 (%d개)" % [DATA_DIR, bosses.size()])
	for entry: Variant in bosses:
		var arr := entry as Array
		var file := str(arr[0])
		var def := arr[1] as BossDef
		print("[%s] %s" % [file, def.display_name])
		_check_boss(file, def)

	var ranged := _ranged_defs()
	# 스캔 0건이면 아래 단정이 통째로 건너뛰어져 **조용히 통과**한다(verify §3 침묵 통과 방지)
	_check(not ranged.is_empty(),
		"%s 스캔: 원거리 잔몹이 1개 이상 (%d개)" % [DATA_DIR, ranged.size()])
	for entry: Variant in ranged:
		var arr := entry as Array
		var file := str(arr[0])
		var def := arr[1] as EnemyDef
		print("[%s] %s (원거리)" % [file, def.display_name])
		_check_ranged(file, def)

	print("검사 %d건" % _checks)
	if _fail == 0:
		print("TEST_OK boss_data")
	else:
		print("TEST_FAIL boss_data failures=%d" % _fail)
	quit(1 if _fail > 0 else 0)
