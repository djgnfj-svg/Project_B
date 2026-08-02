# 전투 스테이지 씬 생성기 (재실행 가능한 생성 도구 — 관행 = scripts/gen_tileset.gd·gen_sfx.py).
#
# 실행:  python scripts/gen_stage.py
#
# 🔴 왜 파이썬인가 — Godot `-s` 헤드리스는 오토로드 전역 식별자(`Net`·`EventBus`)를 컴파일하지 못해
#   `stage.gd`·`stage_hud.gd` 같은 **씬 글루 스크립트를 load()할 수 없다**(rules §5). 엔진으로
#   PackedScene을 만들면 그 노드들이 스크립트 없이 저장돼 런타임에 조용히 죽는다. 그래서 씬은
#   텍스트로 조립하고, 사람이 쓸 수 없는 `tile_map_data`(헤더 2바이트 + 셀당 12바이트 리틀엔디안
#   int16 × 6 = x, y, source_id, atlas_x, atlas_y, alternative)만 여기서 바이트로 찍는다.
#
# 🔴 통행 불가 = TileSet의 물리 레이어에서 온다 — 씬에 StaticBody2D를 놓지 않는다.
#   stage_water.tres / stage_cliff.tres 가 코너 단위 콜리전을 이미 들고 있고(gen_tileset --solid),
#   플레이어·잔몹은 collision_mask = 1(world)이라 코드 변경 없이 막힌다(rules §5 배정표).
#
# ⚠ 맵 가장자리는 반드시 통행 불가로 닫는다 — 전투 씬에는 카메라 제한도 벽도 없다(마을만 4벽을 갖는다).
# ⚠ 잔몹은 이제 길찾기로 우회한다(`src/enemies/nav_grid.gd`, 2026-08-01) — 그래도 통행 불가 영역은
#   볼록하게 두는 편이 낫다. 좁은 목은 경로가 있어도 여러 마리가 동시에 끼어 밀린다.
#
# 🔴 보스방(`boss`)만 만드는 방식이 다르다 — **씬을 조립하지 않고 Ground 노드만 갈아 끼운다.**
#   근거는 `build_boss()` 머리말.
import json
import math
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CELL = 32
COLS, ROWS = 40, 24          # 전투 칸 기본 크기 — 1280 × 768 px (보스방은 spec["size"]로 덮어쓴다)

LAYOUTS = {
    "water": {
        "out": "src/stage/stage_1.tscn",
        "meta": "assets/sprites/stage/ground/water_tiles_meta.json",
        "tileset": "res://assets/tilesets/stage_water.tres",
        "edge": 2,
        # (중심셀x, 중심셀y, 반지름셀) — ⚠ 가장자리 테두리(edge)에 닿게 두지 마라.
        #   그 사이에 한두 칸짜리 목이 생기고, 여러 마리가 동시에 끼면 밀린다.
        "patches": [(13, 7, 3), (27, 15, 4), (22, 9, 2)],
        "spawn": (200.0, 380.0),
        "seed": 1101,
        # 2026-08-01: 4 → 8마리 (사용자 요청 *"몬스터 좀더 많이 나줘봐"*).
        # ⚠ 어그로가 전 맵이라 **전원이 동시에 온다** — 수를 늘리면 난이도가 선형이 아니라 급하게
        #   오른다. 완충은 거리뿐이니 추가분은 스폰(200,380) 반대쪽에 몰아 뒀다.
        "mobs": [
            ("mino_sword", (620.0, 330.0)),
            ("mino_sword", (620.0, 500.0)),
            ("ox",         (980.0, 330.0)),
            ("mino_bow",   (864.0, 672.0)),   # 큰 웅덩이 남쪽 — 돌아 들어가야 닿는다
            ("mino_sword", (780.0, 180.0)),
            ("mino_sword", (900.0, 200.0)),
            ("ox",         (1050.0, 560.0)),
            ("mino_bow",   (1120.0, 250.0)),  # 북동 구석 — 근접이 붙는 사이 사선을 낸다
        ],
    },
    "cliff": {
        "out": "src/stage/stage_2.tscn",
        "meta": "assets/sprites/stage/ground/cliff_tiles_meta.json",
        "tileset": "res://assets/tilesets/stage_cliff.tres",
        "edge": 2,
        "patches": [(16, 12, 4), (30, 6, 3), (9, 17, 2)],
        "spawn": (200.0, 200.0),
        "seed": 2201,
        "mobs": [
            ("mino_sword", (560.0, 140.0)),
            ("mino_sword", (640.0, 560.0)),
            ("ox",         (1120.0, 400.0)),
            ("ox",         (1010.0, 600.0)),
            # ⚠ 어그로는 이제 전 맵이다 — 완충은 **거리**뿐이다. 궁수는 스폰에서 멀리 둔다
            #   (여기까지 424px이라 붙기 전에 근접이 먼저 도착한다).
            ("mino_bow",   (620.0, 260.0)),
            ("mino_bow",   (880.0, 600.0)),   # 큰 협곡 건너 — 근접이 돌아오는 사이 쏜다
            # 2026-08-01: 6 → 10마리 (같은 요청). 보스 직전 칸이라 여기가 더 빽빽하다.
            ("mino_sword", (820.0, 300.0)),
            ("ox",         (760.0, 660.0)),
            ("mino_sword", (1150.0, 500.0)),
            ("mino_bow",   (400.0, 660.0)),   # 남서 — 스폰에서 멀어 초반엔 사거리 밖이다
        ],
    },
}


def corner_atlas_map(meta_path):
    """(NW, NE, SW, SE) → (atlas_x, atlas_y). 좌표는 gen_tileset.gd와 같은 유도(bounding_box ÷ 타일크기)."""
    meta = json.load(open(os.path.join(ROOT, meta_path), encoding="utf-8"))
    out = {}
    for t in meta["tileset_data"]["tiles"]:
        c, bb = t["corners"], t["bounding_box"]
        key = tuple(c[k] == "lower" for k in ("NW", "NE", "SW", "SE"))
        out[key] = (bb["x"] // CELL, bb["y"] // CELL)
    if len(out) != 16:
        sys.exit(f"ERROR: 코너 조합이 16개가 아니다 ({len(out)}) — {meta_path}")
    return out


def dims(spec):
    """(cols, rows, ox, oy) — ox/oy = 좌상단 셀 인덱스. 보스방은 좌표계 중심이 (576, 324)라
    전투 칸처럼 원점 (0,0)에서 시작할 수 없다(보스·스폰·아레나 표지가 전부 그 좌표에 맞춰져 있다)."""
    cols, rows = spec.get("size", (COLS, ROWS))
    ox, oy = spec.get("origin", (0, 0))
    return cols, rows, ox, oy


def edges(spec):
    """(좌, 상, 우, 하) 테두리 셀 두께. int 하나면 네 변 같은 두께 · 2-튜플이면 (가로, 세로).
    ⚠ 4-튜플은 **비대칭 테두리**다 — 보스방이 서쪽에만 진입 복도만큼 두께를 더하려고 쓴다."""
    e = spec["edge"]
    if not isinstance(e, tuple):
        return (e, e, e, e)
    return e if len(e) == 4 else (e[0], e[1], e[0], e[1])


def vertex_grid(spec):
    """정점 격자 (cols+1)×(rows+1). True = 통행 불가(lower). Wang은 정점이 지형을 정한다."""
    cols, rows, _, _ = dims(spec)
    el, et, er, eb = edges(spec)
    v = [[False] * (cols + 1) for _ in range(rows + 1)]
    for y in range(rows + 1):
        for x in range(cols + 1):
            if x < el or y < et or x > cols - er or y > rows - eb:
                v[y][x] = True
    for cx, cy, r in spec["patches"]:
        for y in range(rows + 1):
            for x in range(cols + 1):
                if math.hypot(x - cx, y - cy) <= r:
                    v[y][x] = True
    # 🔴 **맨 마지막**에 뚫는다 — 테두리·패치를 관통하는 진입 복도(보스방)를 만드는 유일한 수단이고,
    #   순서가 계약이다(앞에 두면 테두리가 도로 덮는다). 정점 인덱스 사각 (x0, x1, y0, y1), 끝 포함.
    #   ⚠ 이 키가 없는 스펙(물가·낭떠러지)에는 루프가 0회라 **완전 항등**이다.
    for x0, x1, y0, y1 in spec.get("open", []):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                v[y][x] = False
    return v


def solid_at(v, spec, px, py):
    """월드 좌표가 통행 불가 사분면 위인가. 콜리전은 lower 코너의 16×16 사각에 붙는다."""
    cols, rows, ox, oy = dims(spec)
    cx, cy = int(px // CELL) - ox, int(py // CELL) - oy
    if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
        return True
    east = (px - (cx + ox) * CELL) >= CELL / 2
    south = (py - (cy + oy) * CELL) >= CELL / 2
    return v[cy + (1 if south else 0)][cx + (1 if east else 0)]


def passable_bounds(v, spec):
    """통행 가능한 사분면 전체를 감싸는 (x0, y0, x1, y1) 월드 사각.
    카메라 공허(void) 여유를 유도할 때 쓴다 — 플레이어가 갈 수 있는 최대 범위가 곧 화면의 최대 범위다."""
    cols, rows, ox, oy = dims(spec)
    x0 = y0 = float("inf")
    x1 = y1 = float("-inf")
    for gy in range(rows):
        for gx in range(cols):
            for sx in (0, 1):
                for sy in (0, 1):
                    if v[gy + sy][gx + sx]:
                        continue
                    qx = (gx + ox) * CELL + sx * (CELL / 2)
                    qy = (gy + oy) * CELL + sy * (CELL / 2)
                    x0, y0 = min(x0, qx), min(y0, qy)
                    x1, y1 = max(x1, qx + CELL / 2), max(y1, qy + CELL / 2)
    return x0, y0, x1, y1


def aggro_of(mob_name):
    """data/enemies/<name>.tres에서 aggro_range를 읽는다(값을 여기 복제하지 않는다)."""
    path = os.path.join(ROOT, "data", "enemies", mob_name + ".tres")
    for line in open(path, encoding="utf-8"):
        if line.startswith("aggro_range"):
            return float(line.split("=", 1)[1])
    return 0.0


def clear_check(v, spec, pts):
    """[(이름, (x, y), 반경)] 각 지점이 반경만큼 통행 가능한가. 통행 불가 위에 놓으면 낀 채로 시작하고
    에러가 안 난다 — 그래서 배치 검증은 여기가 유일한 방어다."""
    bad = []
    for name, (px, py), r in pts:
        for dx, dy in ((0, 0), (-r, 0), (r, 0), (0, -r), (0, r), (-r, -r), (r, -r), (-r, r), (r, r)):
            if solid_at(v, spec, px + dx, py + dy):
                bad.append(f"{name} ({px:.0f},{py:.0f}) 통행 불가 위(반경 {r:.0f})")
                break
    return bad


def verify(v, spec):
    """배치가 성립하는지 — 둘 다 에러 없이 조용히 나빠지는 종류라 여기서 막는다."""
    bad = []
    # ⑴ 통행 가능한 칸 위인가. 물·낭떠러지 안에 놓으면 낀 채로 시작하고 에러가 안 난다.
    pts = [("스폰", spec["spawn"], 22.0)] + [(n, p, 22.0) for n, p in spec["mobs"]]
    bad += clear_check(v, spec, pts)
    # ⚠ 「스폰이 적 어그로 밖인가」 검증은 2026-08-01에 **뺐다** — 사용자 요청으로 잔몹의
    #    `aggro_range`를 맵 전체보다 크게 잡아 **시작하자마자 전원이 가장 가까운 플레이어에게
    #    온다**. 그 설계에서는 이 검증이 항상 위반이라 의미가 없다.
    #    🔴 대신 **거리로 완충하는 책임이 배치로 옮겨왔다** — 스폰 바로 옆에 두면 들어서는 순간
    #    붙는다. 궁수(사거리 200)는 특히 멀리 둬라.
    return bad


def tile_map_data(v, spec, amap):
    """헤더(uint16 format=0) + 셀마다 int16 × 6. 셀 좌표는 음수도 된다(int16 = 부호 있음)."""
    cols, rows, ox, oy = dims(spec)
    buf = bytearray(struct.pack("<H", 0))
    for y in range(rows):
        for x in range(cols):
            key = (v[y][x], v[y][x + 1], v[y + 1][x], v[y + 1][x + 1])
            ax, ay = amap[key]
            buf += struct.pack("<hhhhhh", x + ox, y + oy, 0, ax, ay, 0)
    return buf


def byte_array_str(data):
    return "PackedByteArray(" + ", ".join(str(b) for b in data) + ")"


def rects_for_patches(spec, pad_cells=1):
    _, _, ox, oy = dims(spec)
    out = []
    for cx, cy, r in spec["patches"]:
        rr = (r + pad_cells) * CELL
        out.append(((cx + ox) * CELL - rr, (cy + oy) * CELL - rr, rr * 2, rr * 2))
    return out


def rect_str(r):
    return "Rect2(%g, %g, %g, %g)" % r


def build(kind, spec):
    amap = corner_atlas_map(spec["meta"])
    v = vertex_grid(spec)
    bad = verify(v, spec)
    if bad:
        sys.exit("ERROR: 통행 불가 위에 놓인 배치 — " + ", ".join(bad))

    data = tile_map_data(v, spec, amap)
    edge = spec["edge"]
    inner = (edge * CELL + 16.0, edge * CELL + 16.0,
             (COLS - 2 * edge) * CELL - 32.0, (ROWS - 2 * edge) * CELL - 32.0)
    ex = rects_for_patches(spec)
    sx, sy = spec["spawn"]
    fol_ex = ex + [(sx - 90.0, sy - 90.0, 180.0, 180.0)]     # 스폰 지점 시야 확보

    ext = [
        ('Script', 'res://src/stage/stage.gd'),                       # 1
        ('TileSet', spec["tileset"]),                                 # 2
        ('PackedScene', 'res://src/enemies/mob_melee.tscn'),          # 3
        ('Script', 'res://src/net/peer_sync.gd'),                     # 4
        ('Script', 'res://src/stage/combat_authority.gd'),            # 5
        ('Script', 'res://src/stage/mob_sync.gd'),                    # 6
        ('Script', 'res://src/net/scene_flow.gd'),                    # 7
        ('Script', 'res://src/stage/chapter_flow.gd'),                # 8
        ('PackedScene', 'res://src/hud/stage_hud.tscn'),              # 9
        ('Script', 'res://src/stage/drop_authority.gd'),              # 10
        ('Script', 'res://src/stage/drop_field.gd'),                  # 11
        ('Script', 'res://src/stage/arrow_field.gd'),                 # 12
        ('Script', 'res://src/stage/exp_authority.gd'),               # 13
        ('Script', 'res://src/stage/ground_detail.gd'),               # 14
        ('Script', 'res://src/stage/foliage_field.gd'),               # 15
        ('PackedScene', 'res://src/stage/foliage.tscn'),              # 16
        ('Texture2D', 'res://assets/sprites/stage/detail_grass.png'), # 17
        ('Texture2D', 'res://assets/sprites/stage/detail_pebble.png'),# 18
        ('Texture2D', 'res://assets/sprites/stage/detail_crack.png'), # 19
        ('Texture2D', 'res://assets/sprites/stage/detail_flower.png'),# 20
        ('Texture2D', 'res://assets/sprites/stage/foliage_grass.png'),# 21
        ('Texture2D', 'res://assets/sprites/stage/foliage_bush.png'), # 22
    ]
    mob_defs = sorted({n for n, _ in spec["mobs"]})
    for i, n in enumerate(mob_defs):
        ext.append(('Resource', f'res://data/enemies/{n}.tres'))
    def_id = {n: str(23 + i) for i, n in enumerate(mob_defs)}

    L = [f'[gd_scene load_steps={len(ext) + 1} format=3]', '']
    for i, (typ, path) in enumerate(ext, 1):
        L.append(f'[ext_resource type="{typ}" path="{path}" id="{i}"]')
    L += ['', '[node name="Stage" type="Node2D"]', 'script = ExtResource("1")', '']

    # 바닥 — 프로젝트에서 스테이지 최초의 TileMapLayer. z는 rules §5 표(잔몹 텔레그래프 −1을 안 가리게).
    L += ['[node name="Ground" type="TileMapLayer" parent="."]', 'z_index = -10',
          'tile_set = ExtResource("2")',
          'tile_map_data = ' + byte_array_str(data), '']

    L += ['[node name="GroundDetail" type="Node2D" parent="."]', 'script = ExtResource("14")',
          f'area = {rect_str(inner)}',
          'textures = Array[Texture2D]([ExtResource("17"), ExtResource("18"), ExtResource("19"), ExtResource("20")])',
          'count = 160', f'rng_seed = {spec["seed"]}',
          'exclude = Array[Rect2]([' + ", ".join(rect_str(r) for r in ex) + '])', '']

    L += ['[node name="FoliageField" type="Node2D" parent="."]', 'script = ExtResource("15")',
          'foliage_scene = ExtResource("16")', f'area = {rect_str(inner)}',
          # 나무는 뺀다(사용자 요청 2026-08-01) — 전투 칸은 시야가 트여야 한다.
          'textures = Array[Texture2D]([ExtResource("21"), ExtResource("22")])',
          'count = 26', f'rng_seed = {spec["seed"] + 1}',
          'exclude = Array[Rect2]([' + ", ".join(rect_str(r) for r in fol_ex) + '])', '']

    # 잔몹 — 씬 배치다(CombatAuthority·MobSync의 _ready 일회 스캔 전제, rules §2 게이트).
    # eid는 칸 접두를 단다 — 충돌하면 동기화가 조용히 어긋난다.
    for i, (n, (mx, my)) in enumerate(spec["mobs"], 1):
        L += [f'[node name="Mob{i}" parent="." instance=ExtResource("3")]',
              f'position = Vector2({mx:g}, {my:g})', f'eid = "{kind}_m{i}"',
              f'def = ExtResource("{def_id[n]}")', '']

    # 조합 컴포넌트 — rules §2 「챕터1 진행 골격」. 이 조합을 문다, 복사 금지.
    L += ['[node name="PeerSync" type="Node" parent="."]', 'script = ExtResource("4")',
          'scene_id = "stage"', f'spawn_base = Vector2({sx:g}, {sy:g})', '',
          '[node name="CombatAuthority" type="Node" parent="."]', 'script = ExtResource("5")',
          'peer_sync_path = NodePath("../PeerSync")', '',
          '[node name="DropAuthority" type="Node" parent="."]', 'script = ExtResource("10")', '',
          '[node name="DropField" type="Node" parent="."]', 'script = ExtResource("11")',
          'drop_authority_path = NodePath("../DropAuthority")', '',
          '[node name="ArrowField" type="Node" parent="."]', 'script = ExtResource("12")',
          'peer_sync_path = NodePath("../PeerSync")', '',
          '[node name="MobSync" type="Node" parent="."]', 'script = ExtResource("6")', '',
          '[node name="SceneFlow" type="Node" parent="."]', 'script = ExtResource("7")', '',
          '[node name="ChapterFlow" type="Node" parent="."]', 'script = ExtResource("8")',
          'scene_flow_path = NodePath("../SceneFlow")', '',
          '[node name="HUD" parent="." instance=ExtResource("9")]', '',
          '[node name="ExpAuthority" type="Node" parent="."]', 'script = ExtResource("13")', '']

    path = os.path.join(ROOT, spec["out"])
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(L))
    solid = sum(1 for y in range(ROWS) for x in range(COLS)
                if all((v[y][x], v[y][x + 1], v[y + 1][x], v[y + 1][x + 1])))
    print(f"STAGE_OK {spec['out']} kind={kind} {COLS}x{ROWS}셀 · 완전 통행불가 {solid}칸"
          f"({100.0 * solid / (COLS * ROWS):.0f}%) · 잔몹 {len(spec['mobs'])}")


# =====================================================================================
# 보스방 — 기존 씬을 읽어 Ground 노드 하나만 갈아 끼운다 (전투 칸처럼 조립하지 않는다)
# =====================================================================================
#
# 🔴 보스방에는 전투 칸에 없는 노드가 있다 — `Boss` 인스턴스 · `RockField` · `CoopAuthority`
#   (`boss_eid`·`stele_only`) · `BossArena`. 전투 칸 템플릿을 그대로 찍으면 이것들이 통째로
#   사라지고 **보스전이 죽는다**. 그래서 여기서는 씬을 조립하지 않고 **원문을 읽어 Ground 블록만**
#   교체한다 — 나머지 노드·프로퍼티·메타는 글자 그대로 남고, 나중에 누가 노드를 더해도(예:
#   횡단 돌진의 `metadata/arena_rect`) 이 생성기를 다시 돌릴 수 있다(멱등).
#
# ⚠ 좌표계가 전투 칸과 다르다 — 보스방 중심은 (576, 324)이고 `Boss`(760, 340)·
#   `PeerSync.spawn_base`(240, 340)·아레나 표지(768×416)가 전부 거기에 맞춰져 있다.
#   그래서 원점 (0,0)에서 시작하는 40×24 격자를 쓸 수 없다 → `origin`으로 셀 인덱스를 음수까지 민다.
#
# ⚠ **아레나 안에는 통행 불가를 한 칸도 넣지 않는다.** `stage_cliff.tres`는 코너 단위 콜리전을
#   쥐고 있어 깔면 자동으로 막히는데(전투 칸에선 장점), 보스는 `collision_mask = 1`이라 여기서는
#   그것이 곧 결함이다 — 돌진(`boss.gd` CHARGE_DASH)이 이동 거리로 종료를 판정하므로 중간에
#   끼면 헛돈다. 가장자리만 닫고 내부는 전부 통행 가능하다.
#
# 🔴 **진입 복도** (2026-08-02 · docs/plans/active/2026-08-02-boss-gate.md) — "걸어 들어가야
#   보스방이 된다". 맵을 서쪽으로 **12칸(384px) 통째로 밀고** 그 두꺼워진 테두리를 `open`으로
#   뚫었다. **맵과 통행 가능을 같은 양만큼 밀었기 때문에 카메라 공허 여유가 한 픽셀도 안 변하고**
#   (verify_boss ⑶이 검산한다) **동·북·남 경계와 아레나는 무접촉**이다 = 횡단 돌진 기하 불변.
#   ⚠ 복도 길이를 바꾸려면 `size`·`origin`·`edge`·`open`·`spawn`을 **한 묶음으로** 옮겨라 —
#     하나만 고치면 공허가 보이거나(⑶이 잡는다) 스폰이 낭떠러지에 박힌다(⑴이 잡는다).
BOSS = {
    "out": "src/stage/stage_boss.tscn",
    "meta": "assets/sprites/stage/ground/cliff_tiles_meta.json",
    # 낭떠러지(lower = "deep rocky chasm in shadow") 고리 + 흙바닥(upper) 아레나.
    # 챕터1 순서가 물가 → 낭떠러지 → 보스라 마지막 칸이 낭떠러지에서 이어진다.
    "tileset": "res://assets/tilesets/stage_cliff.tres",
    "size": (72, 36),        # 2304 × 1152 px  (60 → 72: 서쪽 진입 복도 12칸)
    "origin": (-24, -8),     # 좌상단 셀 → 월드 (-768, -256) · 우하단 (1536, 896)
    # 테두리 두께 = **카메라 공허 여유에서 유도**했다(verify_boss ⑶이 검산한다 — 눈으로 맞춘 값이
    # 아니다). 가로가 두꺼운 것은 화면이 가로로 넓기 때문(640×360)이다.
    # 🔴 좌(27)만 우(15)보다 12칸 두껍다 = 복도가 지나갈 자리. 아레나 쪽 통행 경계는 **불변**이다.
    "edge": (27, 9, 15, 9),  # (좌, 상, 우, 하) — 아레나 통행 가능 = 월드 (80, 16) ~ (1072, 624)
    "patches": [],           # 🔴 내부는 전부 통행 가능 — 아레나 안에 장애물을 넣지 마라(위 ⚠).
    # 진입 복도 = 정점 인덱스 사각 (x0, x1, y0, y1). → 월드 x [-304, 80] · y [272, 400] (높이 128px).
    "open": [(15, 27, 17, 20)],
    "ground_z": -11,         # 🔴 현행 유지 — `BossArena`(z=-10)가 바닥 위·늪(z=-9) 아래에 남아야 한다
    # 스폰 = 복도 서쪽 끝. `PeerSync.spawn_base`에 **생성기가 찍는다**(씬에 손으로 적지 마라).
    # 걷는 거리 = 여기 → trigger_x = 480px ≈ 4.8초(전사 이속 100). docs/TUNING.md 대상.
    "spawn": (-256.0, 340.0),
    # 게이트(낙석 벽) 중심 x · 트리거선 x. y·개수는 **복도 단면을 재서** 유도한다(gate_geometry).
    "gate_x": 60.0,
    "trigger_x": 224.0,      # 아레나 표지 서단(192)에서 32px 안쪽
}


def png_size(rel_path):
    """PNG IHDR에서 (폭, 높이). 아레나 표지 크기를 여기 숫자로 복제하지 않으려고 원본을 읽는다."""
    with open(os.path.join(ROOT, rel_path), "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"ERROR: PNG가 아니다 — {rel_path}")
    return struct.unpack(">II", head[16:24])


def grep1(rel_path, pattern, label):
    """파일에서 정규식 첫 그룹 하나. 못 찾으면 죽는다 — 미러가 조용히 낡는 것보다 낫다."""
    text = open(os.path.join(ROOT, rel_path), encoding="utf-8").read()
    m = re.search(pattern, text)
    if m is None:
        sys.exit(f"ERROR: {label}을 {rel_path}에서 못 찾았다 (패턴 {pattern})")
    return m.group(1)


def parse_scene(text):
    """.tscn을 [헤더 줄, [프로퍼티 줄…]] 블록 목록으로 자른다. 빈 줄은 버리고 재출력에서 복원한다."""
    blocks = []
    for line in text.split("\n"):
        if line.startswith("["):
            blocks.append([line, []])
        elif line.strip() and blocks:
            blocks[-1][1].append(line)
    if not blocks or not blocks[0][0].startswith("[gd_scene"):
        sys.exit("ERROR: [gd_scene] 헤더로 시작하지 않는다")
    return blocks


def render_scene(blocks):
    """Godot 관례대로 다시 찍는다 — ext_resource는 붙여 쓰고, 나머지 블록은 빈 줄로 나눈다."""
    ext = [b for b in blocks[1:] if b[0].startswith("[ext_resource")]
    rest = [b for b in blocks[1:] if not b[0].startswith("[ext_resource")]
    sub = sum(1 for b in rest if b[0].startswith("[sub_resource"))
    out = [re.sub(r"load_steps=\d+", "load_steps=%d" % (len(ext) + sub + 1), blocks[0][0]), ""]
    out += [b[0] for b in ext]
    for b in rest:
        out += [""] + [b[0]] + b[1]
    return "\n".join(out) + "\n"


def find_node(blocks, name):
    for b in blocks:
        if b[0].startswith("[node ") and ('name="%s"' % name) in b[0]:
            return b
    return None


def prop(block, key, default=None):
    for line in block[1]:
        if line.startswith(key + " "):
            return line.split("=", 1)[1].strip()
    return default


def set_prop(block, key, value):
    """노드 블록의 프로퍼티 한 줄을 덮어쓴다(없으면 끝에 추가). 나머지 줄은 글자 그대로 남는다
    — 그래야 재실행 diff가 «생성기가 소유한 값»에만 뜬다(build_boss 머리말의 멱등 규약)."""
    if block is None:
        sys.exit("ERROR: set_prop 대상 노드가 없다 (%s)" % key)
    line = "%s = %s" % (key, value)
    for i, existing in enumerate(block[1]):
        if existing.startswith(key + " "):
            block[1][i] = line
            return
    block[1].append(line)


def fnum(x):
    """Godot이 float export를 직렬화하는 모양(`224.0`)으로 찍는다 — 정수처럼 찍으면 재저장 때
    에디터가 형식을 되돌려 diff가 계속 튄다."""
    return repr(float(x))


def vec2(text):
    m = re.match(r"Vector2\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)", text or "")
    if m is None:
        sys.exit(f"ERROR: Vector2를 못 읽었다 — {text!r}")
    return float(m.group(1)), float(m.group(2))


def corridor_span(v, spec, px):
    """월드 x = px 에서 통행 가능한 **첫** y 구간 (y0, y1). 못 찾으면 (None, None).
    🔴 게이트 길이를 스펙에 두 번 적는 대신 격자에서 **잰다** — 복도를 옮기면 게이트가 저절로
    따라온다(사람이 맞춰 드는 미러가 아예 안 생긴다)."""
    _, rows, _, oy = dims(spec)
    step = CELL / 2.0
    y = float(oy * CELL)
    top = bot = None
    while y < (oy + rows) * CELL:
        if not solid_at(v, spec, px, y):
            if top is None:
                top = y
            bot = y + step
        elif top is not None:
            break
        y += step
    return top, bot


def max_player_speed():
    """플레이어가 낼 수 있는 최대 속도(px/s). 유도식은 `player._max_roll_speed()`와 같고
    항(項)은 전부 원본에서 읽는다 — 여기 숫자를 적으면 튜닝 때 조용히 갈라진다."""
    mult = float(grep1("src/core/combat_math.gd",
                       r"const ROLL_SPEED_MULT := ([\d.]+)", "ROLL_SPEED_MULT"))
    move_max = float(grep1("src/core/combat_math.gd",
                           r"LEVEL_STAT_MAX: Dictionary = \{[^}]*\"move\":\s*([\d.]+)",
                           "LEVEL_STAT_MAX[move]"))
    roll_dist = float(grep1("src/core/combat_math.gd",
                            r"TRAIT_MAX: Dictionary = \{[^}]*\"roll_dist\":\s*([\d.]+)",
                            "TRAIT_MAX[roll_dist]"))
    base = 0.0
    jobs = os.path.join(ROOT, "data", "jobs")
    for name in sorted(os.listdir(jobs)):
        if not name.endswith(".tres"):
            continue
        for line in open(os.path.join(jobs, name), encoding="utf-8"):
            if line.startswith("move_speed"):
                base = max(base, float(line.split("=", 1)[1]))
    if base <= 0.0:
        sys.exit("ERROR: data/jobs에서 move_speed를 못 읽었다")
    return base * mult * (1.0 + move_max) * (1.0 + roll_dist)


def gate_geometry(v, spec):
    """게이트 낙석 배치 {y0, y1, n, r, step, band, need}.
    🔴 **개수를 손으로 세지 않는다** — "틈 없이 막는다"는 부등식에서 유도한다. 인접한 두 원
    (중심거리 s, 반경 r)이 만드는 **최소 띠 두께** = 2·√(r² − (s/2)²) 가 필요치 이상이어야 한다.
    필요치 = 플레이어 몸 폭 + 2 × 최대 프레임 변위. 그래서 s ≤ 2·√(r² − (필요치/2)²)."""
    y0, y1 = corridor_span(v, spec, spec["gate_x"])
    if y0 is None:
        sys.exit("ERROR: 게이트 x=%g 에 통행 가능한 복도가 없다" % spec["gate_x"])
    r = float(grep1("src/stage/boss_rock.tscn", r"radius = ([\d.]+)", "바위 콜리전 반경"))
    pw = float(grep1("src/player/player.tscn", r"size = Vector2\(([\d.]+),", "플레이어 몸 폭"))
    need = pw + 2.0 * (max_player_speed() / 60.0)
    if need >= 2.0 * r:
        sys.exit("ERROR: 바위 반경 %g로는 어떤 간격으로도 못 막는다 (필요 두께 %.1f)" % (r, need))
    s_max = 2.0 * math.sqrt(r * r - (need / 2.0) ** 2)
    n = max(2, int(math.ceil((y1 - y0) / s_max)) + 1)
    step = (y1 - y0) / float(n - 1)
    band = 2.0 * math.sqrt(max(0.0, r * r - (step / 2.0) ** 2))
    return {"y0": y0, "y1": y1, "n": n, "r": r, "step": step, "band": band, "need": need}


def verify_boss(v, spec, blocks, gate):
    """🔴 헤드리스 스위트가 못 잡는 것을 여기서 막는다 — 전부 에러 없이 조용히 나빠지는 종류다.
    앵커 값은 씬·데이터 원본에서 읽는다(여기 숫자로 복제하면 그게 곧 갈라질 미러다)."""
    bad = []

    # ⑴ 보스·스폰이 통행 가능한가. 보스 반경은 boss.tscn의 CircleShape2D에서 읽는다.
    boss_r = float(grep1("src/enemies/boss.tscn", r"radius = ([\d.]+)", "보스 충돌 반경"))
    boss_node = find_node(blocks, "Boss")
    peer = find_node(blocks, "PeerSync")
    if boss_node is None or peer is None:
        sys.exit("ERROR: Boss / PeerSync 노드가 없다 — 씬이 이미 망가졌다")
    boss_pos = vec2(prop(boss_node, "position"))
    # 🔴 스폰은 **스펙**이 정본이다(build_boss가 씬에 찍는다) — 씬 값을 읽으면 「쓰기 전」 값을
    #   검사하게 되어 트립와이어가 한 세대 늦는다.
    spawn = spec["spawn"]
    # 🔵 P2 스폰도 검사한다 — `peer_sync`가 `spawn_base + (spawn_gap × 순번, 0)`으로 스폰하는데
    #   지금까지 아무도 안 봤다(선재 사각: 두 번째 피어가 낭떠러지에서 태어나도 에러가 안 난다).
    gap_txt = prop(peer, "spawn_gap")
    gap = float(gap_txt) if gap_txt is not None else float(
        grep1("src/net/peer_sync.gd", r"spawn_gap: float = ([\d.]+)", "spawn_gap 기본값"))
    bad += clear_check(v, spec, [("보스", boss_pos, boss_r), ("스폰P1", spawn, 22.0),
                                 ("스폰P2", (spawn[0] + gap, spawn[1]), 22.0)])

    # ⑵ 🔴 아레나 표지 위는 **전부** 통행 가능해야 하고, 보스가 그 위 어디에도 설 수 있어야 한다
    #    (= 아레나를 보스 반경만큼 부풀린 영역이 통행 가능). 안 그러면 횡단 돌진이 안 보이는 벽에
    #    막혀 끝나지 않고, 화면에는 이유가 안 드러난다.
    arena = find_node(blocks, "BossArena")
    if arena is None:
        sys.exit("ERROR: BossArena 노드가 없다")
    ax, ay = vec2(prop(arena, "position"))
    aw, ah = png_size("assets/sprites/stage/meadow_arena.png")
    ar = (ax - aw / 2.0 - boss_r, ay - ah / 2.0 - boss_r, aw + boss_r * 2, ah + boss_r * 2)
    step = CELL / 2.0                       # 콜리전 격자와 같은 해상도(16px 사분면)
    nx = int(math.ceil(ar[2] / step)) + 1
    ny = int(math.ceil(ar[3] / step)) + 1
    for iy in range(ny):
        for ix in range(nx):
            px = min(ar[0] + ix * step, ar[0] + ar[2])
            py = min(ar[1] + iy * step, ar[1] + ar[3])
            if solid_at(v, spec, px, py):
                bad.append(f"아레나+보스반경 안에 통행 불가 ({px:.0f},{py:.0f})")
                break
        if bad and bad[-1].startswith("아레나"):
            break

    # ⑶ 🔴 공허(void) 여유 — 보스방엔 카메라 제한이 없다(`stage.gd`가 안 건다). 플레이어가 갈 수
    #    있는 끝에서 화면 절반만큼 밖까지 바닥이 있어야 맵 밖 빈 공간이 안 보인다.
    #    ⚠ 배율은 **보스 패턴 줌아웃**(`camera_rig.ZOOM_WIDE`)이 기준이다 — 평상시 줌(1.5)보다
    #      화면이 넓어지므로 그쪽으로 유도하지 않으면 "특정 패턴에서만" 공허가 보인다.
    zoom = float(grep1("src/feel/camera_rig.gd", r"const ZOOM_WIDE := ([\d.]+)", "ZOOM_WIDE"))
    vw = float(grep1("project.godot", r"window/size/viewport_width=(\d+)", "뷰포트 폭"))
    vh = float(grep1("project.godot", r"window/size/viewport_height=(\d+)", "뷰포트 높이"))
    half = float(grep1("src/player/player.tscn", r"size = Vector2\(([\d.]+),", "플레이어 몸 폭")) / 2.0
    # 셰이크 + 반동은 offset이라 월드 단위로 화면을 더 민다.
    slack = (float(grep1("src/feel/camera_rig.gd", r"const SHAKE_MAX := ([\d.]+)", "SHAKE_MAX"))
             + float(grep1("src/feel/camera_rig.gd", r"const KICK_MAX := ([\d.]+)", "KICK_MAX")))
    px0, py0, px1, py1 = passable_bounds(v, spec)
    cols, rows, ox, oy = dims(spec)
    map_r = (ox * CELL, oy * CELL, (ox + cols) * CELL, (oy + rows) * CELL)
    need = ((px0 + half) - vw / 2.0 / zoom - slack, (py0 + half) - vh / 2.0 / zoom - slack,
            (px1 - half) + vw / 2.0 / zoom + slack, (py1 - half) + vh / 2.0 / zoom + slack)
    for i, (label, ok) in enumerate((("서", map_r[0] <= need[0]), ("북", map_r[1] <= need[1]),
                                     ("동", map_r[2] >= need[2]), ("남", map_r[3] >= need[3]))):
        if not ok:
            bad.append("%s쪽 공허 — 바닥 %g, 화면이 닿는 곳 %g" % (label, map_r[i], need[i]))

    # --- 진입 게이트 (2026-08-02 · docs/plans/active/2026-08-02-boss-gate.md) ---
    # 🔴 아래 넷은 전부 **에러 없이 조용히 나빠지는** 종류다: 틈이 열리면 파티가 보스방을 빠져나가고,
    #    여유가 모자라면 닫히는 순간 게이트 위에 선 피어가 생기며, 트리거선이 잘못 놓이면
    #    게이트가 화면 밖에서 닫힌다. 어느 것도 헤드리스 스위트가 못 잡는다.
    gx, tx = spec["gate_x"], spec["trigger_x"]

    # ⑷ 게이트가 복도 단면을 **틈 없이** 막는가 (유도는 gate_geometry 머리말).
    if gate["band"] < gate["need"]:
        bad.append("게이트 띠 두께 %.1f < 필요 %.1f (바위 %d개·간격 %.1f·반경 %g)"
                   % (gate["band"], gate["need"], gate["n"], gate["step"], gate["r"]))

    # ⑸ 트리거선 ↔ 게이트 여유 ≥ 외삽 상한. 호스트는 낡은 좌표(net_anchor)로 판정하므로,
    #    앵커가 트리거선에 닿은 순간의 실제 위치는 최악 이만큼 서쪽일 수 있다.
    lead = float(grep1("src/core/combat_math.gd",
                       r"const LAG_MAX_LEAD_DIST := ([\d.]+)", "LAG_MAX_LEAD_DIST"))
    slack_px = tx - (gx + gate["r"])
    if slack_px < lead:
        bad.append("트리거 여유 %.0fpx < LAG_MAX_LEAD_DIST %.0f — 닫히는 순간 게이트 위에 설 수 있다"
                   % (slack_px, lead))

    # ⑹ **아레나에 묶인** 돌진이 게이트에 닿을 수 없는가 — 그런 패턴의 돌진선은 `_cross_segment`가
    #    아레나 안에서만 잡고 보스 몸의 서쪽 끝은 `arena.x`다(중심 = arena.x + body_radius).
    #    ⚠ **지금 그런 패턴은 없다** — 유일했던 횡단 돌진(`cross`)이 2026-08-02 `07b5b8c`에서 빠졌다.
    #      앞으로를 위한 가드로 남긴다(아레나 경계에서 유도하므로 데이터가 다시 생겨도 따라온다).
    # 🔴 **지금 실제로 게이트를 지키는 것은 이 부등식이 아니다.** 살아 있는 `charge`(P3)는
    #    **플레이어를 향해** 돌진하므로(`use_max_dist` 420) 게이트 앞까지 온다 — 그쪽은
    #    `boss_rock.gd`가 영구 바위를 "boss_rock" 그룹에서 빼는 것으로 막는다(거기 주석이 정본).
    arena_x0 = ax - aw / 2.0
    if arena_x0 <= gx + gate["r"]:
        bad.append("횡단 돌진 서단 %.0f ≤ 게이트 동쪽끝 %.0f" % (arena_x0, gx + gate["r"]))

    # ⑺ 배치 순서: 스폰 < 게이트 < 트리거선 ≤ 아레나 안. 그리고 게이트·트리거선 둘 다 통행 가능 위.
    if not (spawn[0] < gx < tx):
        bad.append("배치 순서 어긋남 — 스폰 %.0f < 게이트 %.0f < 트리거 %.0f 여야 한다"
                   % (spawn[0], gx, tx))
    if tx < arena_x0:
        bad.append("트리거선 %.0f 이 아레나 서단 %.0f 밖 — 「아레나에 들어섰다」가 성립 안 한다" % (tx, arena_x0))
    if solid_at(v, spec, tx, spawn[1]):
        bad.append("트리거선 (%.0f,%.0f) 이 통행 불가 위" % (tx, spawn[1]))

    # ⑻ 닫히는 게이트가 **화면 안에서 보이는가** — 평상시 줌 기준. 안 보이면 연출이 성립 안 한다.
    zoom_base = float(grep1("src/feel/camera_rig.gd", r"const ZOOM := ([\d.]+)", "ZOOM"))
    if tx - gx > vw / 2.0 / zoom_base:
        bad.append("트리거선에서 게이트까지 %.0fpx > 화면 반폭 %.0f — 닫히는 게 안 보인다"
                   % (tx - gx, vw / 2.0 / zoom_base))

    return bad, (px0, py0, px1, py1), map_r


def build_boss(spec):
    amap = corner_atlas_map(spec["meta"])
    v = vertex_grid(spec)
    path = os.path.join(ROOT, spec["out"])
    blocks = parse_scene(open(path, encoding="utf-8").read())

    gate = gate_geometry(v, spec)
    bad, pb, map_r = verify_boss(v, spec, blocks, gate)
    if bad:
        sys.exit("ERROR: 보스방 배치가 성립하지 않는다 — " + ", ".join(bad))

    # 🔴 진입 기하는 **생성기가 씬에 찍는다** — 스폰·게이트·트리거선을 씬에서 손으로 들면 복도를
    #   옮길 때 반드시 갈라진다(rules 「미러를 만들지 마라」). 값의 정본은 위 BOSS 스펙 + 격자 실측.
    peer_node = find_node(blocks, "PeerSync")
    set_prop(peer_node, "spawn_base", "Vector2(%g, %g)" % spec["spawn"])
    bg = find_node(blocks, "BossGate")
    if bg is None:
        sys.exit("ERROR: BossGate 노드가 없다 — 씬에 한 번 넣어 두면 이후는 생성기가 값을 소유한다")
    for key, val in (("trigger_x", fnum(spec["trigger_x"])), ("gate_x", fnum(spec["gate_x"])),
                     ("gate_y0", fnum(gate["y0"])), ("gate_y1", fnum(gate["y1"])),
                     ("gate_count", "%d" % gate["n"]), ("gate_radius", fnum(gate["r"]))):
        set_prop(bg, key, val)

    ground = find_node(blocks, "Ground")
    if ground is None:
        sys.exit("ERROR: Ground 노드가 없다 — 이 생성기는 조립이 아니라 교체다")
    old_ids = set(re.findall(r'ExtResource\("([^"]+)"\)', "\n".join(ground[1])))

    # 타일셋 ext_resource — 이미 있으면 그 id를 쓴다(재실행 멱등). 없으면 안 쓰인 번호를 새로 딴다.
    # 🔴 기존 id는 절대 다시 매기지 않는다 — 다른 노드 블록이 글자 그대로 남아야 diff가 Ground뿐이다.
    ts_id, last_ext, used = None, -1, []
    for i, b in enumerate(blocks):
        if not b[0].startswith("[ext_resource"):
            continue
        last_ext = i
        if ('path="%s"' % spec["tileset"]) in b[0]:
            ts_id = re.search(r'id="([^"]+)"', b[0]).group(1)
        m = re.search(r'id="(\d+)"', b[0])
        if m is not None:
            used.append(int(m.group(1)))
    if ts_id is None:
        ts_id = str(max(used or [0]) + 1)
        blocks.insert(last_ext + 1,
                      ['[ext_resource type="TileSet" path="%s" id="%s"]' % (spec["tileset"], ts_id), []])

    ground[0] = '[node name="Ground" type="TileMapLayer" parent="."]'
    ground[1] = ['z_index = %d' % spec["ground_z"],
                 'tile_set = ExtResource("%s")' % ts_id,
                 'tile_map_data = ' + byte_array_str(tile_map_data(v, spec, amap))]

    # Ground가 유일한 사용처였던 ext_resource(옛 바닥 텍스처)는 버린다 — 남기면 웹 빌드에 안 쓰는
    # 에셋이 실린다. **다른 노드가 아직 참조하면 절대 안 지운다**(그래서 세어 본다).
    body = "\n".join(b[0] + "\n" + "\n".join(b[1]) for b in blocks if not b[0].startswith("[ext_resource"))
    dropped = []
    for b in list(blocks):
        if not b[0].startswith("[ext_resource"):
            continue
        rid = re.search(r'id="([^"]+)"', b[0]).group(1)
        if rid in old_ids and rid != ts_id and ('ExtResource("%s")' % rid) not in body:
            dropped.append(re.search(r'path="([^"]+)"', b[0]).group(1))
            blocks.remove(b)

    open(path, "w", encoding="utf-8", newline="\n").write(render_scene(blocks))
    cols, rows, _, _ = dims(spec)
    print("STAGE_OK %s kind=boss %dx%d셀 · 바닥 (%g,%g)~(%g,%g) · 통행가능 (%g,%g)~(%g,%g)%s"
          % (spec["out"], cols, rows, map_r[0], map_r[1], map_r[2], map_r[3],
             pb[0], pb[1], pb[2], pb[3],
             (" · 뗀 ext " + ", ".join(dropped)) if dropped else ""))
    print("           게이트 x=%g y=%g~%g · 바위 %d개(반경 %g·간격 %.1f·띠 %.1f≥%.1f) · 트리거 x=%g"
          " · 스폰 (%g,%g) → 도보 %.0fpx"
          % (spec["gate_x"], gate["y0"], gate["y1"], gate["n"], gate["r"], gate["step"],
             gate["band"], gate["need"], spec["trigger_x"],
             spec["spawn"][0], spec["spawn"][1], spec["trigger_x"] - spec["spawn"][0]))


if __name__ == "__main__":
    for k in (sys.argv[1:] or (list(LAYOUTS) + ["boss"])):
        if k == "boss":
            build_boss(BOSS)
        else:
            build(k, LAYOUTS[k])
