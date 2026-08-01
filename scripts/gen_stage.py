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
# ⚠ 잔몹은 길찾기가 없다(mob_melee._host_ai가 직진 + move_and_slide). 통행 불가 영역은 볼록하게,
#   서로 떨어뜨려 놓는다 — 오목한 만이나 좁은 통로를 만들면 잔몹이 벽에 붙어 멈추고 화면에 이유가 안 드러난다.
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CELL = 32
COLS, ROWS = 40, 24          # 1280 × 768 px

LAYOUTS = {
    "water": {
        "out": "src/stage/stage_1.tscn",
        "meta": "assets/sprites/stage/ground/water_tiles_meta.json",
        "tileset": "res://assets/tilesets/stage_water.tres",
        "edge": 2,
        # (중심셀x, 중심셀y, 반지름셀) — ⚠ 가장자리 테두리(edge)에 닿게 두지 마라. 둘이 만나면
        # 그 사이에 한두 칸짜리 목이 생기고, 길찾기 없는 잔몹이 거기 끼면 화면에 이유가 안 드러난다.
        "patches": [(13, 7, 3), (27, 15, 4), (22, 9, 2)],
        "spawn": (200.0, 380.0),
        "seed": 1101,
        "mobs": [
            ("mino_sword", (620.0, 330.0)),
            ("mino_sword", (620.0, 500.0)),
            ("ox",         (980.0, 330.0)),
            ("mino_bow",   (864.0, 672.0)),   # 큰 웅덩이 남쪽 — 돌아 들어가야 닿는다
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
            # ⚠ 궁수는 스폰에서 `aggro_range`(260) 밖에 둔다 — 안쪽이면 들어서자마자 예고 없이
            #   교전이 시작돼 첫 화살을 무방비로 맞는다(스폰↔여기 거리 424).
            ("mino_bow",   (620.0, 260.0)),
            ("mino_bow",   (880.0, 600.0)),   # 큰 협곡 건너 — 근접이 돌아오는 사이 쏜다
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


def vertex_grid(spec):
    """정점 격자 (COLS+1)×(ROWS+1). True = 통행 불가(lower). Wang은 정점이 지형을 정한다."""
    edge = spec["edge"]
    v = [[False] * (COLS + 1) for _ in range(ROWS + 1)]
    for y in range(ROWS + 1):
        for x in range(COLS + 1):
            if x < edge or y < edge or x > COLS - edge or y > ROWS - edge:
                v[y][x] = True
    for cx, cy, r in spec["patches"]:
        for y in range(ROWS + 1):
            for x in range(COLS + 1):
                if math.hypot(x - cx, y - cy) <= r:
                    v[y][x] = True
    return v


def solid_at(v, px, py):
    """월드 좌표가 통행 불가 사분면 위인가. 콜리전은 lower 코너의 16×16 사각에 붙는다."""
    cx, cy = int(px // CELL), int(py // CELL)
    if cx < 0 or cy < 0 or cx >= COLS or cy >= ROWS:
        return True
    east = (px - cx * CELL) >= CELL / 2
    south = (py - cy * CELL) >= CELL / 2
    return v[cy + (1 if south else 0)][cx + (1 if east else 0)]


def aggro_of(mob_name):
    """data/enemies/<name>.tres에서 aggro_range를 읽는다(값을 여기 복제하지 않는다)."""
    path = os.path.join(ROOT, "data", "enemies", mob_name + ".tres")
    for line in open(path, encoding="utf-8"):
        if line.startswith("aggro_range"):
            return float(line.split("=", 1)[1])
    return 0.0


def verify(v, spec):
    """배치가 성립하는지 — 둘 다 에러 없이 조용히 나빠지는 종류라 여기서 막는다."""
    bad = []
    # ⑴ 통행 가능한 칸 위인가. 물·낭떠러지 안에 놓으면 낀 채로 시작하고 에러가 안 난다.
    pts = [("스폰", spec["spawn"], 22.0)] + [(n, p, 22.0) for n, p in spec["mobs"]]
    for name, (px, py), r in pts:
        for dx, dy in ((0, 0), (-r, 0), (r, 0), (0, -r), (0, r), (-r, -r), (r, -r), (-r, r), (r, r)):
            if solid_at(v, px + dx, py + dy):
                bad.append(f"{name} ({px:.0f},{py:.0f}) 통행 불가 위")
                break
    # ⑵ 🔴 스폰이 어느 적의 `aggro_range` 안에 있으면 안 된다 — 칸에 들어서는 순간 교전이
    #    시작돼 첫 예고를 무방비로 맞는다. 궁수(사거리 200)에서 특히 나쁘다.
    sx, sy = spec["spawn"]
    for n, (mx, my) in spec["mobs"]:
        d = math.hypot(mx - sx, my - sy)
        a = aggro_of(n)
        if d <= a:
            bad.append(f"{n} ({mx:.0f},{my:.0f}) 스폰까지 {d:.0f}px ≤ aggro {a:.0f}")
    return bad


def tile_map_data(v, amap):
    """헤더(uint16 format=0) + 셀마다 int16 × 6."""
    buf = bytearray(struct.pack("<H", 0))
    for y in range(ROWS):
        for x in range(COLS):
            key = (v[y][x], v[y][x + 1], v[y + 1][x], v[y + 1][x + 1])
            ax, ay = amap[key]
            buf += struct.pack("<hhhhhh", x, y, 0, ax, ay, 0)
    return buf


def rects_for_patches(spec, pad_cells=1):
    out = []
    for cx, cy, r in spec["patches"]:
        rr = (r + pad_cells) * CELL
        out.append((cx * CELL - rr, cy * CELL - rr, rr * 2, rr * 2))
    return out


def rect_str(r):
    return "Rect2(%g, %g, %g, %g)" % r


def build(kind, spec):
    amap = corner_atlas_map(spec["meta"])
    v = vertex_grid(spec)
    bad = verify(v, spec)
    if bad:
        sys.exit("ERROR: 통행 불가 위에 놓인 배치 — " + ", ".join(bad))

    data = tile_map_data(v, amap)
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
        ('Texture2D', 'res://assets/sprites/stage/foliage_tree_s.png'),# 23
    ]
    mob_defs = sorted({n for n, _ in spec["mobs"]})
    for i, n in enumerate(mob_defs):
        ext.append(('Resource', f'res://data/enemies/{n}.tres'))
    def_id = {n: str(24 + i) for i, n in enumerate(mob_defs)}

    L = [f'[gd_scene load_steps={len(ext) + 1} format=3]', '']
    for i, (typ, path) in enumerate(ext, 1):
        L.append(f'[ext_resource type="{typ}" path="{path}" id="{i}"]')
    L += ['', '[node name="Stage" type="Node2D"]', 'script = ExtResource("1")', '']

    # 바닥 — 프로젝트에서 스테이지 최초의 TileMapLayer. z는 rules §5 표(잔몹 텔레그래프 −1을 안 가리게).
    L += ['[node name="Ground" type="TileMapLayer" parent="."]', 'z_index = -10',
          'tile_set = ExtResource("2")',
          'tile_map_data = PackedByteArray(' + ", ".join(str(b) for b in data) + ')', '']

    L += ['[node name="GroundDetail" type="Node2D" parent="."]', 'script = ExtResource("14")',
          f'area = {rect_str(inner)}',
          'textures = Array[Texture2D]([ExtResource("17"), ExtResource("18"), ExtResource("19"), ExtResource("20")])',
          'count = 160', f'rng_seed = {spec["seed"]}',
          'exclude = Array[Rect2]([' + ", ".join(rect_str(r) for r in ex) + '])', '']

    L += ['[node name="FoliageField" type="Node2D" parent="."]', 'script = ExtResource("15")',
          'foliage_scene = ExtResource("16")', f'area = {rect_str(inner)}',
          'textures = Array[Texture2D]([ExtResource("21"), ExtResource("22"), ExtResource("23")])',
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


if __name__ == "__main__":
    for k in (sys.argv[1:] or LAYOUTS):
        build(k, LAYOUTS[k])
