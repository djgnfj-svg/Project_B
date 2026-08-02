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
const DIRS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

# 🔴 **덩치 ↔ 판정 반경 미러** (2026-08-02, 보스 1.5배 확대) — CLAUDE.md·`EnemyDef.sprite_scale`이
#   명시한 계약: *"`sprite_scale`을 바꾸면 `body_radius`도 같이 바꿔라."* 판정은 `body_radius`가
#   정하므로 그림만 키우면 **"몸통에 맞췄는데 안 맞는다"** 가 되고 **화면에 이유가 안 드러난다**.
#   여기서 잡지 않으면 자동 방어가 0이다(`boss.gd`는 씬 글루라 `-s`가 preload를 못 한다).
#
#   검사량 = **판정 지름 ÷ 화면에 그려지는 프레임 폭**:
#     화면 프레임 폭(월드 px) = 시트 프레임 폭 × ACTOR_NODE_SCALE × sprite_scale
#     판정 지름(월드 px)      = 2 × body_radius
#   현행 미노 = 2×63 ÷ (64 × 2 × 1.5) = **0.656**. 실루엣(알파 실측 24~31 tex px)보다 판정이
#   1.35배 넓은데, 그 비는 둘 다 sprite_scale에 비례하므로 **배율을 같이 올리면 보존된다**.
#
#   ⚠ 이 단정이 잡는 것: `sprite_scale` 1.5 → 3.0인데 `body_radius`가 63 그대로면 0.328 → FAIL.
#      반대로 `body_radius`만 42로 되돌리면 0.438 → FAIL. **둘 중 하나만 움직이면 반드시 빨개진다.**
# 🔴 `ACTOR_NODE_SCALE`은 `src/enemies/boss.tscn`의 `Sprite` node scale(2, 2)과 **미러**다 — 그 씬을
#   다시 authoring하면 여기도 같이 고쳐야 한다. 미러를 없애려면 씬 scale을 1로 내리고 그 배수를
#   `sprite_scale`에 합치면 되지만(그러면 데이터가 덩치의 단일 소스가 된다) 그건 별도 결정이다.
#   ⚠ 이 파일은 `boss.tscn`을 load하지 않는다 — 그 씬은 `boss.gd`를 물고 있고 그 스크립트가
#     `EventBus`/`Net` 전역을 써서 `-s`에서 **컴파일이 통째로 실패**한다(rules §5).
const ACTOR_NODE_SCALE := 2.0
const BODY_FRAC_MIN := 0.50
const BODY_FRAC_MAX := 0.95

# 🔴 **접지 그림자 실측** (2026-08-02, 사용자 신고 *"보스 뭔가 땅에 안 붙어 있는데"*) —
#   `boss.gd _fit_shadow()`가 시트 알파에서 발밑·중심·폭을 재서 그림자를 붙인다. 그 실측이
#   **실패하면 씬 authoring 값으로 조용히 폴백**하는데, 그 값은 옛 망령 시트 기준이라 곧
#   이번 신고 상태로 되돌아간다 — 에러도 경고도 없다. 그래서 "실측이 되는가"를 여기서 잡는다.
#   ⚠ `sprite_ground.gd`는 오토로드를 안 써서 `-s`가 preload할 수 있다(그러라고 그 파일에 뒀다).
const SpriteGround := preload("res://src/enemies/sprite_ground.gd")
# 실루엣 폭 / 프레임 폭의 허용 범위 — 너무 좁으면(빈 프레임 근처) 그림자가 실처럼 되고,
# 1.0을 넘을 수는 없다(바운딩 박스가 프레임 안이므로). 하한은 "캐릭터가 프레임을 거의 안 채운다"
# = 시트 배치가 잘못됐다는 신호다.
const GROUND_WIDTH_FRAC_MIN := 0.25
# 몸 중심이 프레임 중심에서 벗어나도 되는 한계(프레임 폭 대비). 그림자는 실측을 따라가므로
# 벗어나도 "그림자만" 어긋나지는 않지만, 크게 벗어났다면 **시트가 셀 안에서 치우쳐 있다**는 뜻이고
# 그건 `centered = true` 전제(판정 원점 = 셀 중심)와 그림이 갈라졌다는 신호다.
const GROUND_CX_FRAC_MAX := 0.15

# 🔴 `boss.gd`의 `ATTACK_ANIMS` **미러** — 이 파일은 그 스크립트를 preload 못 한다(헤더).
#   그 배열은 §2가 등재한 「패턴 id의 하드코딩 미러」이고, **덮이지 않는 패턴 id는 에러 없이
#   깨진다**: `_is_attack_anim_playing()`이 false를 돌려 `_update_move_anim`이 **다음 프레임에
#   공격 애니를 idle/walk로 덮는다** = 공격 모션이 아예 안 보인다.
#   ⚠ 한쪽을 고치면 같이 고쳐라. 이 단정이 게이트의 절반을 규율에서 구조로 옮긴다.
const ATTACK_ANIMS := ["swing", "slam", "spray", "spin",
	"charge_windup", "charge_dash", "charge_hit", "charge_recover"]

# 회피 여유 배수 — 최단 예고(회차 단축이 하한까지 간 경우)가 구르기의 이 배수 이상이어야 한다.
# 🔴 구르기 한 번으로 "겨우" 되는 것은 회피가 아니다(반응 시간이 0이 된다).
const ROLL_MARGIN := 1.5

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


# 🔴 덩치 ↔ 판정 반경 — 상단 `ACTOR_NODE_SCALE` 주석이 유도의 정본이다.
func _check_body_scale(file: String, def: BossDef, sf: SpriteFrames) -> void:
	_check(def.sprite_scale > 0.0,
		"%s: sprite_scale > 0 (%.2f) — 0/음수면 `boss.gd` 가드가 배율을 통째로 건너뛴다"
		% [file, def.sprite_scale])
	_check(def.body_radius > 0.0,
		"%s: body_radius > 0 (%.1f) — 0이면 근접이 중심 판정이 되어 몸통에 맞춰도 안 맞는다"
		% [file, def.body_radius])
	# 프레임 폭은 시트에서 읽는다 — 숫자를 박으면 아트가 캔버스를 바꿀 때 이 검사가 조용히 틀려진다.
	var anim := _resolve(sf, "idle", "se")
	if anim == &"" or sf.get_frame_count(anim) <= 0:
		_check(false, "%s: idle 프레임을 못 읽어 덩치↔판정 검사를 못 한다 [%s]" % [file, anim])
		return
	var tex := sf.get_frame_texture(anim, 0)
	var frame_w := float(tex.get_width()) if tex != null else 0.0
	if frame_w <= 0.0:
		_check(false, "%s: idle 프레임 폭이 0 — 덩치↔판정 검사를 못 한다" % file)
		return
	var drawn_w := frame_w * ACTOR_NODE_SCALE * def.sprite_scale   # 화면에 그려지는 폭(월드 px)
	var frac := (2.0 * def.body_radius) / drawn_w                  # 판정 지름 ÷ 그려지는 폭
	_check(frac >= BODY_FRAC_MIN and frac <= BODY_FRAC_MAX,
		"★%s: 판정 지름 ÷ 그려지는 폭 = %.3f ∈ [%.2f, %.2f] (body_radius %.1f · sprite_scale %.2f · 프레임 %.0fpx) — 벗어나면 둘 중 하나만 움직인 것이다"
		% [file, frac, BODY_FRAC_MIN, BODY_FRAC_MAX, def.body_radius, def.sprite_scale, frame_w])


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
	_check_body_scale(file, def, sf)
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
		_check_pattern_common(label, p)
		# 돌진(P3)은 pat.id 애니가 아니라 상태머신이 placeholder 클립(windup=slam·dash=walk)을 직접 몬다
		# → id 애니 존재 계약에서 제외. 대신 돌진 전용 파라미터가 유효한지 본다(0이면 안 움직이거나 못 맞힌다).
		if p.is_charge:
			_check(p.charge_speed > 0.0, "%s: charge_speed > 0 (%.1f)" % [label, p.charge_speed])
			_check(p.charge_sweep_radius > 0.0,
				"%s: charge_sweep_radius > 0 (%.1f) — 0이면 스윕이 아무도 못 맞힌다" % [label, p.charge_sweep_radius])
			_check(p.charge_travel_max > 0.0, "%s: charge_travel_max > 0 (%.1f)" % [label, p.charge_travel_max])
			_check_charge_pattern(label, p)
			continue
		# 패턴 id가 **모든 facing**에서 재생 가능한 애니로 풀려야 (방향 변형·slam_<dir> 폴백 포함).
		_check(_resolves_all(sf, p.id),
			"%s: 패턴 id가 모든 facing에서 애니로 풀린다 (없으면 공격 모션이 조용히 안 나온다)" % label)
		_check_attack_anim_coverage(label, sf, p)
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


# 🔴 횡단 돌진 데이터 계약 (2026-08-02) — **전부 에러 없이 깨진다.**
#   `boss.gd`는 씬 글루라 `-s`가 preload를 못 한다 = 그 경로는 스위트의 구조적 사각이다.
#   그래서 규칙을 **데이터 축**으로 밀어 여기서 잡는다(리뷰 J-1·J-2와 같은 규율).
func _check_charge_pattern(label: String, p: BossPatternDef) -> void:
	# ⑴ 🔴 **속도 상한** — 이산 판정(원)과 연속 표시(캡슐) 사이 가리비 예산에서 역산한 값.
	#    속도를 올릴 때 **유일한 자동 방어**다. 반경이 데이터라 상수가 아니라 함수로 유도한다.
	var lim := CombatMath.max_charge_speed(p.charge_sweep_radius)
	_check(p.charge_speed <= lim,
		"★%s: charge_speed %.0f ≤ 상한 %.0f (스윕 반경 %.0f · 가리비 예산 %.1fpx에서 역산)"
		% [label, p.charge_speed, lim, p.charge_sweep_radius, CombatMath.SWEEP_SCALLOP_MAX_PX])
	# ⑵ **값을 찍는다**(실패 조건이 아니다) — 속도를 바꾼 사람이 숫자를 보게 만드는 것이 목적이다.
	print("       가리비 %.2fpx (프레임당 전진 %.1fpx · 반경 %.0f)"
		% [CombatMath.sweep_scallop_px(p.charge_sweep_radius, p.charge_speed),
		p.charge_speed / CombatMath.SWEEP_STEP_FPS, p.charge_sweep_radius])
	# ⑶ 🔴 **완주 불변식** — 지속이 이동시간 + 여유 이상인가. 고정 상수로 되돌리면(옛 1.0s)
	#    이동거리를 늘리거나 속도를 낮추는 순간 **에러 없이 미완주**다(예고 띠는 끝까지 그려져 있다).
	var travel_s := CombatMath.charge_travel_s(p)
	var dur := CombatMath.charge_dash_duration_s(p)
	_check(dur >= travel_s + CombatMath.CHARGE_TIMEOUT_MARGIN - 0.000001,
		"★%s: 돌진 지속 %.3fs ≥ 이동 %.3fs + 여유 %.2fs — 미달이면 아레나 중간에 선다"
		% [label, dur, travel_s, CombatMath.CHARGE_TIMEOUT_MARGIN])
	# ⑷ 회전 잔여가 있는 패턴(P3)은 도달이 그 안에 끝나야 **도입 전 상수 동작과 항등**이다.
	if p.charge_spin_s > 0.0:
		_check(is_equal_approx(dur, p.charge_spin_s),
			"★%s: 회전 잔여 %.2fs가 지속을 정한다(도달 %.3fs) — 옛 CHARGE_SPIN_TIME 동작 유지"
			% [label, p.charge_spin_s, travel_s])
	_check(p.charge_repeat >= 1,
		"%s: charge_repeat %d ≥ 1 — 0/음수면 패턴이 한 번도 안 돈다" % [label, p.charge_repeat])
	# ⑸ 캡슐 예고는 `charge_sweep_radius`·`charge_travel_max`를 읽는다(`range`가 아니다).
	if p.shape == "capsule":
		_check(p.charge_travel_max > 0.0,
			"★%s: 캡슐 예고는 charge_travel_max로 띠 길이를 만든다 (%.0f)" % [label, p.charge_travel_max])
		_check(p.charge_approach_speed > 0.0,
			"%s: 캡슐(횡단)은 가장자리 접근이 필요하다 — charge_approach_speed %.0f > 0"
			% [label, p.charge_approach_speed])


# 🔴 패턴 공통 계약 (돌진 여부 무관) — 회피 가능성·조준 모드·형태 전제.
func _check_pattern_common(label: String, p: BossPatternDef) -> void:
	# ⑴ 🔴 **회피 가능성** — 회차 단축이 하한까지 갔을 때의 **최단** 예고가 구르기보다 충분히 긴가.
	#    근거는 손맛이 아니라 `ROLL_TIME_S`다: 예고가 구르기보다 짧으면 「예고를 읽고 구른다」
	#    (GDD §5 기믹 원칙)가 **원리적으로** 불가능해진다.
	var worst := p.telegraph_s * CombatMath.charge_telegraph_scale(p, 100000)
	_check(worst >= CombatMath.ROLL_TIME_S * ROLL_MARGIN,
		"★%s: 최단 예고 %.3fs ≥ 구르기 %.2fs × %.1f (회차 단축 하한 %.2f 적용)"
		% [label, worst, CombatMath.ROLL_TIME_S, ROLL_MARGIN, CombatMath.CHARGE_TELEGRAPH_MIN])
	# ⑵ 🔴 **조준 모드 allowlist** — 모르는 값은 `_select_target`이 조용히 nearest로 떨어뜨린다.
	#    폴백이 계약이라 게임은 안 깨지지만 **적은 대로 안 먹는다** = 데이터 축에서 막는다.
	_check(CombatMath.TARGET_MODES.has(p.target_mode),
		"★%s: target_mode \"%s\" ∈ %s — 그 밖은 nearest로 조용히 떨어진다"
		% [label, p.target_mode, str(CombatMath.TARGET_MODES)])
	# ⑶ 캡슐·바위 파괴는 돌진 전용 축이다. 아니면 코드가 아예 안 읽어 **적어도 아무 일이 안 난다.**
	_check(p.shape != "capsule" or p.is_charge,
		"★%s: shape=capsule은 is_charge 전용 — 아니면 띠만 그려지고 돌진이 없다" % label)
	_check(not p.breaks_rock or p.is_charge,
		"%s: breaks_rock은 is_charge 전용 — 아니면 아무 분기도 안 탄다" % label)
	# ⑷ 🔴 **P3 항등 확인** — 돌진인데 확장 필드를 안 쓴 패턴은 도입 전과 완전히 같아야 한다.
	if p.is_charge and p.charge_approach_speed <= 0.0:
		_check(p.charge_repeat == 1 and p.shape != "capsule" and is_equal_approx(p.charge_speedup, 0.0),
			"★%s: 접근 없는 돌진(P3 계열)은 왕복·캡슐·회차 단축을 안 쓴다 = 도입 전과 항등" % label)


# 🔴 `ATTACK_ANIMS` 커버리지 — 패턴 id가 푸는 애니가 그 접두 규칙에 덮이는가.
#   안 덮이면 `_update_move_anim`이 공격 모션을 **다음 프레임에 idle/walk로 덮는다**(에러 없음).
#   ⚠ 돌진(`is_charge`)은 제외다 — 그쪽은 상태기계가 클립을 직접 몰고, 자세 보존은
#     `_on_hp_changed`의 `_in_charge_states()` 가드가 **애니 이름이 아니라 상태로** 한다.
func _check_attack_anim_coverage(label: String, sf: SpriteFrames, p: BossPatternDef) -> void:
	for d: String in DIRS:
		var anim := String(_resolve(sf, p.id, d))
		if anim.is_empty():
			continue   # 애니가 아예 안 풀리는 것은 _check_boss가 이미 잡는다
		var covered := false
		for a: String in ATTACK_ANIMS:
			if anim == a or anim.begins_with(a + "_"):
				covered = true
				break
		_check(covered,
			"★%s[%s]: 애니 \"%s\"가 ATTACK_ANIMS 접두에 덮인다 — 안 덮이면 공격 모션이 다음 프레임에 지워진다"
			% [label, d, anim])


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


# 🔴 접지 그림자 실측 계약 — 넷 다 어기면 **에러 없이** 그림자가 발에서 떨어진다.
#   실패하면 `boss.gd _fit_shadow()`가 씬 authoring 값(= 옛 시트의 발밑)으로 폴백하기 때문이다.
func _check_ground(file: String, def: BossDef) -> void:
	var sf := def.frames
	if sf == null:
		return   # frames 없는 def는 sprite 1장 폴백 — 별도 단정(_check_boss)이 이미 본다
	# ⑴ **서 있는 포즈가 지면선을 정의한다.** `idle*`이 하나도 없으면 `SpriteGround`가 각 애니
	#    0프레임으로 떨어지고, 거기엔 도끼가 바닥을 치는 `slam` 컷이 섞인다 — 미노 실측으로
	#    발밑이 52 → 60 tex px(화면 24 월드px)까지 내려가 그림자가 **도끼 끝**에 붙는다.
	var has_idle := false
	for n: StringName in sf.get_animation_names():
		if String(n).begins_with(SpriteGround.IDLE_PREFIX):
			has_idle = true
			break
	_check(has_idle, "%s: `idle*` 애니 존재 — 없으면 그림자가 공격 컷(도끼 끝)에 맞춰진다" % file)

	var g := SpriteGround.measure(sf)
	# ⑵ 실측 자체가 되는가. 시트를 VRAM 압축으로 재import하거나 프레임이 전부 비면 여기서 걸린다.
	_check(bool(g.get("ok", false)),
		"%s: 시트 실측 성공 — 실패하면 씬 authoring 값(옛 시트 발밑)으로 조용히 폴백한다" % file)
	if not bool(g.get("ok", false)):
		return
	_check(int(g.get("samples", 0)) >= 1,
		"%s: 실측 표본 %d개 ≥ 1" % [file, int(g.get("samples", 0))])

	# 프레임 크기 — 첫 idle 프레임에서 읽는다(셀 규격은 시트가 정본이므로 상수로 안 박는다).
	var cell := Vector2.ZERO
	for n: StringName in sf.get_animation_names():
		if String(n).begins_with(SpriteGround.IDLE_PREFIX) and sf.get_frame_count(n) > 0:
			var t := sf.get_frame_texture(n, 0)
			if t != null:
				cell = t.get_size()
			break
	if cell.x <= 0.0 or cell.y <= 0.0:
		return
	var foot := float(g.get("foot", 0.0))
	var cx := float(g.get("cx", 0.0))
	var w := float(g.get("width", 0.0))
	# ⑶ 발밑은 셀 **아래쪽 절반** 안에 있어야 한다. 0 이하면 그림자가 몸 한가운데(또는 위)에 붙고,
	#    셀 반높이를 넘는 것은 원리적으로 불가능하다(바운딩 박스가 셀 안이므로) = 유도식이 깨진 신호.
	_check(foot > 0.0 and foot <= cell.y * 0.5,
		"%s: 발밑 %.1f ∈ (0, %.1f] — 벗어나면 그림자가 발이 아닌 곳에 붙는다" % [file, foot, cell.y * 0.5])
	# ⑷ 실루엣 폭이 그림자 폭을 정한다 — 지나치게 좁으면 그림자가 실선이 된다.
	_check(w >= cell.x * GROUND_WIDTH_FRAC_MIN,
		"%s: 실루엣 폭 %.1f ≥ 프레임 %.0f × %.2f — 좁으면 그림자가 실처럼 얇아진다"
		% [file, w, cell.x, GROUND_WIDTH_FRAC_MIN])
	# ⑸ 몸이 셀 안에서 크게 치우치면 그림·판정 원점(셀 중심)이 갈라졌다는 신호다.
	_check(absf(cx) <= cell.x * GROUND_CX_FRAC_MAX,
		"%s: 몸 중심 편차 %.1f ≤ 프레임 %.0f × %.2f" % [file, cx, cell.x, GROUND_CX_FRAC_MAX])

	# ⑹ 🔴 **결과가 idle 포즈만으로 결정되는가** — 이 파일에서 유일하게 검출력이 있는 단정이다.
	#    위 ⑴은 "idle이 존재한다"만 보므로 `SpriteGround`가 표본 필터를 잃어도 통과한다(발밑이
	#    20 → 28 tex px로 내려가도 ⑶의 범위 안이라 조용하다 = 그림자가 도끼 끝에 붙는데 초록불).
	#    여기서는 **idle만 담은 시트를 새로 만들어** 같은 답이 나오는지 본다 — 스캔을 재구현하지
	#    않으므로 모델을 미러하지 않고(§3 N-1), 필터가 사라지면 두 값이 갈라져 반드시 빨개진다.
	var idle_only := SpriteFrames.new()
	for n: StringName in sf.get_animation_names():
		if not String(n).begins_with(SpriteGround.IDLE_PREFIX):
			continue
		idle_only.add_animation(n)
		for i in range(sf.get_frame_count(n)):
			idle_only.add_frame(n, sf.get_frame_texture(n, i), sf.get_frame_duration(n, i))
	var gi := SpriteGround.measure(idle_only)
	_check(bool(gi.get("ok", false))
			and is_equal_approx(float(gi.get("foot", -99999.0)), foot)
			and is_equal_approx(float(gi.get("cx", -99999.0)), cx)
			and is_equal_approx(float(gi.get("width", -99999.0)), w),
		"%s: 실측이 idle 포즈만으로 결정된다 (idle전용 %.1f/%.1f/%.1f == 전체 %.1f/%.1f/%.1f)"
		% [file, float(gi.get("foot", 0.0)), float(gi.get("cx", 0.0)), float(gi.get("width", 0.0)), foot, cx, w])


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
		_check_ground(file, def)

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
