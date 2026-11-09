"""Builds world_local_level_2_medieval.tscn: world_local_level_2.tscn reskinned as a castle on a moat, played with
the siege bow, with the same gameplay otherwise.

The level is derived from the original file each time, so floor cells, navmesh, enemies, checkpoints, triggers,
bridges and events stay the same. Only these change (see medieval.py):
  - both GridMaps use castle_tiles.tres: stone islands, and stone piers with plank decks for the wooden walkways,
  - the bridges use castle_bridge_platform.tscn, the same bridge dressed as a stone pier with a plank deck,
  - the orange mage pillars are hidden behind stone turrets (their collision stays),
  - the weapon is the siege bow instead of the bazooka,
  - the lighting, fog, water colour and music,
  - a new Level/Medieval node of props with no collision. The level is 260 m long, so they're placed from its
    floor cells rather than by hand: see place_* below.

Run from the project root (it refuses to overwrite the level without --force):
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/level_gen python3 tools/level_gen/build_medieval_level_2.py [--force]
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_medieval_keep.gd res://src/world/levels/world_local_level_2_medieval.tscn /tmp/medieval_shots 300
"""

import math
import random
import re
import sys

from medieval import (CELL, CLIFF_BANNER_SCALE, CLIFF_OUT, CLIFF_TOP_Y, CLIFF_TORCH_Y, WALL_BANNER_DROP, WALL_HEIGHT, WALL_TORCH_DROP,
                      Decoration, Reskin, cell_centre, gridmap_cells, heraldry_params, transform, wall_segments,
                      write_props)

SOURCE = "src/world/levels/world_local_level_2.tscn"
OUT = "src/world/levels/world_local_level_2_medieval.tscn"
WALKWAY_ITEM = 1  # Wooden_Platform_Top: single-cell walkways, not cliffs to hang banners on
SIEGE_BOW = "res://src/weapon/siege_bow.tscn"

# Tall props must stay out of the strip south of any floor: the camera sits about 5 m south of the carriers and
# 10 to 13 m up, and looks north, so anything tall there fills the screen or hides them.
TOWER_SOUTH_CLEAR = (16.0, 10.0)  # (metres south of a floor cell, metres to either side)
WALL_SOUTH_CLEAR = (10.0, 8.0)
TOWER_DISTANCE = (7.0, 11.0)  # from the nearest floor, bridge or pillar
TOWER_SPACING = 24.0
WALL_LENGTH = (12.0, 33.0)
WALL_CLEARANCE = 4.5


class Footprint:
    """Everything players walk on or enemies stand on, as squares (cells, bridges) and circles (pillars, rocks)."""

    def __init__(self):
        self.squares = []  # (x, z, half size)
        self.circles = []  # (x, z, radius)
        self.floor_points = []  # cell centres, for the camera rule

    def distance(self, x, z):
        best = 1e9
        for sx, sz, half in self.squares:
            dx = max(abs(x - sx) - half, 0.0)
            dz = max(abs(z - sz) - half, 0.0)
            best = min(best, math.hypot(dx, dz))
        for cx, cz, radius in self.circles:
            best = min(best, max(math.hypot(x - cx, z - cz) - radius, 0.0))
        return best

    def south_of_floor(self, x, z, clear):
        depth, side = clear
        return any(0.0 < z - fz < depth and abs(x - fx) < side for fx, fz in self.floor_points)


def read_footprint(text):
    footprint = Footprint()
    floor = {}
    for x, y, z, item, _ in gridmap_cells(text, "GridMapFloor"):
        if y == -1:
            floor[(x, z)] = item
            cx, cz = cell_centre(x, z)
            footprint.squares.append((cx, cz, CELL / 2))
            footprint.floor_points.append((cx, cz))
        if y == -5:  # a big hill tile below the surface; keep props off it
            cx, cz = cell_centre(x, z)
            footprint.circles.append((cx, cz, 9.0))
    for m in re.finditer(r'\[node name="[^"]+" parent="Level/Bridges" instance=ExtResource\("[^"]+"\)\]\ntransform = Transform3D\(([^)]*)\)', text):
        values = [float(v) for v in m.group(1).split(",")]
        footprint.squares.append((values[9], values[11], CELL / 2))
        footprint.floor_points.append((values[9], values[11]))
    for x, z in pillar_positions(text):
        footprint.circles.append((x, z, 1.4))
    return footprint, floor


def pillar_positions(text):
    """World (x, z) of each mage pillar's column: its root's position plus its mesh's offset."""
    out = []
    pattern = (r'\[node name="(enemy_pillar\d*)" type="Node3D" parent="Level/Pillars"\]\ntransform = Transform3D\(([^)]*)\)\n\n'
               r'\[node name="enemy_pillar" type="MeshInstance3D" parent="Level/Pillars/\1"\]\ntransform = Transform3D\(([^)]*)\)')
    for m in re.finditer(pattern, text):
        root = [float(v) for v in m.group(2).split(",")]
        offset = [float(v) for v in m.group(3).split(",")]
        assert root[:9] == [1, 0, 0, 0, 1, 0, 0, 0, 1] and offset[:9] == [1, 0, 0, 0, 1, 0, 0, 0, 1], m.group(1)
        out.append((root[9] + offset[9], root[11] + offset[11], root[10] + offset[10]))
    assert len(out) == 10, len(out)
    return [(x, z) for x, z, _ in out]


def pillar_turret_origins(text):
    pattern = (r'\[node name="(enemy_pillar\d*)" type="Node3D" parent="Level/Pillars"\]\ntransform = Transform3D\(([^)]*)\)\n\n'
               r'\[node name="enemy_pillar" type="MeshInstance3D" parent="Level/Pillars/\1"\]\ntransform = Transform3D\(([^)]*)\)')
    out = []
    for m in re.finditer(pattern, text):
        root = [float(v) for v in m.group(2).split(",")]
        offset = [float(v) for v in m.group(3).split(",")]
        out.append((root[9] + offset[9], root[10] + offset[10], root[11] + offset[11]))
    return out


def bounds(footprint, margin):
    xs = [p[0] for p in footprint.floor_points]
    zs = [p[1] for p in footprint.floor_points]
    return min(xs) - margin, max(xs) + margin, min(zs) - margin, max(zs) + margin


def jitter(x, z):
    return (math.sin(x * 12.9898 + z * 78.233) * 43758.5453) % 1.0


# ---------------------------------------------------------------- placement

def place_gatehouse(footprint):
    """A gatehouse past the finish, flanked by two towers: the goal the carriers fight towards."""
    north = min(p[1] for p in footprint.floor_points)
    row = [p[0] for p in footprint.floor_points if abs(p[1] - north) < 0.1]
    x = (min(row) + max(row)) / 2
    z = north - CELL / 2 - 7.5
    return (x, z), [(x - 6.0, z), (x + 6.0, z)]


def place_towers(footprint, fixed):
    x0, x1, z0, z1 = bounds(footprint, 14.0)
    candidates = []
    x = x0
    while x <= x1:
        z = z0
        while z <= z1:
            d = footprint.distance(x, z)
            if TOWER_DISTANCE[0] <= d <= TOWER_DISTANCE[1] and not footprint.south_of_floor(x, z, TOWER_SOUTH_CLEAR):
                candidates.append((abs(d - 8.5) + jitter(x, z) * 1.5, x, z))
            z += 1.5
        x += 1.5
    towers = list(fixed)
    for _, x, z in sorted(candidates):
        if all(math.hypot(x - tx, z - tz) >= TOWER_SPACING for tx, tz in towers):
            towers.append((x, z))
    return towers


def place_walls(footprint, towers, gate_towers):
    """Joins nearby towers with curtain walls where the whole run keeps clear of the floor and the camera."""
    pairs = []
    for i, a in enumerate(towers):
        for b in towers[i + 1:]:
            length = math.hypot(b[0] - a[0], b[1] - a[1])
            # Only runs within about 15 degrees of north-south or east-west: diagonal ones looked haphazard.
            straight = min(abs(b[0] - a[0]), abs(b[1] - a[1])) / length < 0.26
            if WALL_LENGTH[0] <= length <= WALL_LENGTH[1] and straight:
                pairs.append((length, a, b))
    degree = {t: 0 for t in towers}
    runs = []
    for length, a, b in sorted(pairs):
        if degree[a] >= 2 or degree[b] >= 2:
            continue
        if a in gate_towers and b in gate_towers:  # the gatehouse stands between them
            continue
        if not _wall_fits(footprint, towers, runs, a, b):
            continue
        runs.append((a, b))
        degree[a] += 1
        degree[b] += 1
    return runs


def _wall_fits(footprint, towers, runs, a, b):
    samples = max(2, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 1.5))
    for step in range(samples + 1):
        t = step / samples
        x, z = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        if footprint.distance(x, z) < WALL_CLEARANCE or footprint.south_of_floor(x, z, WALL_SOUTH_CLEAR):
            return False
    for tower in towers:
        if tower in (a, b):
            continue
        if _point_segment_distance(tower, a, b) < 4.0:
            return False
    return not any(_segments_cross(a, b, c, d) for c, d in runs if len({a, b, c, d}) == 4)


def _point_segment_distance(p, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / (dx * dx + dz * dz)))
    return math.hypot(p[0] - ax - dx * t, p[1] - az - dz * t)


def _segments_cross(a, b, c, d):
    def side(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    return side(a, b, c) * side(a, b, d) < 0 and side(c, d, a) * side(c, d, b) < 0


def wall_face(footprint, a, b):
    """Unit normal of a wall run pointing at the play space, and the yaw that turns +Z onto it."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz)
    nx, nz = -dz / length, dx / length
    mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    if footprint.distance(mx - nx * 4, mz - nz * 4) < footprint.distance(mx + nx * 4, mz + nz * 4):
        nx, nz = -nx, -nz
    return nx, nz, math.degrees(math.atan2(nx, nz))


def south_cliff_runs(floor, footprint):
    """Runs of island cells along x whose south face is open water: where banners and torches hang.
    Walkway piers are skipped, and so are cells beside a walkway or bridge landing on that face."""
    landing = {(round(x / CELL - 0.5), round(z / CELL - 0.5)) for x, z in footprint.floor_points}
    edge = []
    for (cx, cz), item in floor.items():
        if item == WALKWAY_ITEM:
            continue
        if any((cx + dx, cz + 1) in landing for dx in (-1, 0, 1)):
            continue
        edge.append((cz, cx))
    runs = []
    for cz, cx in sorted(edge):
        if runs and runs[-1][0] == cz and runs[-1][-1] == cx - 1:
            runs[-1].append(cx)
            continue
        runs.append([cz, cx])
    return [(run[0], run[1:]) for run in runs]


def scatter(footprint, rng, count, distance_range, spacing, avoid, x_range, z_range):
    """Random points on the water a given distance from the floor, spaced apart and clear of other props."""
    points = []
    for _ in range(count * 60):
        if len(points) >= count:
            break
        x, z = rng.uniform(*x_range), rng.uniform(*z_range)
        d = footprint.distance(x, z)
        if not distance_range[0] <= d <= distance_range[1]:
            continue
        if any(math.hypot(x - px, z - pz) < spacing for px, pz in points):
            continue
        if any(math.hypot(x - ax, z - az) < radius for ax, az, radius in avoid):
            continue
        points.append((x, z))
    return points


def decoration(refs, text, water_y):
    footprint, floor = read_footprint(text)
    wall_top = water_y + WALL_HEIGHT
    d = Decoration(refs, ["Towers", "Walls", "Banners", "Torches", "Turrets", "Moat"])

    gate, gate_towers = place_gatehouse(footprint)
    towers = place_towers(footprint, gate_towers)
    runs = place_walls(footprint, towers, gate_towers)
    d.add("Towers", "gatehouse", transform((gate[0], water_y, gate[1])))
    for index, (x, z) in enumerate(towers):
        d.add("Towers", "tower", transform((x, water_y, z), index * 23.0))
    avoid = [(x, z, 4.0) for x, z in towers] + [(gate[0], gate[1], 7.0)]

    banners = 0
    for a, b in runs:
        for x, z, yaw, stretch in wall_segments(a[0], a[1], b[0], b[1]):
            d.add("Walls", "wall", transform((x, water_y, z), yaw, (stretch, 1, 1)))
            avoid.append((x, z, 3.5))
        nx, nz, face_yaw = wall_face(footprint, a, b)
        mx, mz = (a[0] + b[0]) / 2 + nx * 0.8, (a[1] + b[1]) / 2 + nz * 0.8
        d.add("Banners", "banner", transform((mx, wall_top - WALL_BANNER_DROP, mz), face_yaw), heraldry_params(banners))
        banners += 1
        tx, tz = (b[0] - a[0]), (b[1] - a[1])
        length = math.hypot(tx, tz)
        for offset in (-0.27, 0.27):
            x, z = mx + tx * offset, mz + tz * offset
            if length * abs(offset) > 3.0:
                d.add("Torches", "torch", transform((x, wall_top - WALL_TORCH_DROP, z), face_yaw))

    for cz, cells in south_cliff_runs(floor, footprint):
        interior = cells[1:-1]
        for k, cx in enumerate(interior):
            if k % 2:
                continue
            x, z = cell_centre(cx, cz)
            face_z = z + CELL / 2 + CLIFF_OUT
            d.add("Banners", "banner", transform((x, CLIFF_TOP_Y, face_z), 0.0, CLIFF_BANNER_SCALE), heraldry_params(banners))
            banners += 1
            if k % 4 == 0:
                for side in (-1.6, 1.6):
                    d.add("Torches", "torch", transform((x + side, CLIFF_TORCH_Y, face_z)))

    for x, y, z in pillar_turret_origins(text):
        d.add("Turrets", "turret", transform((x, y, z)))

    rng = random.Random(11)
    x0, x1, z0, z1 = bounds(footprint, 10.0)
    for x, z in scatter(footprint, rng, 12, (3.5, 9.0), 26.0, avoid, (x0, x1), (z0, z1)):
        d.add("Moat", "boat", transform((x, water_y, z), rng.uniform(0, 360)))
    for x, z in scatter(footprint, rng, 34, (1.8, 6.0), 9.0, avoid, (x0, x1), (z0, z1)):
        d.add("Moat", "reeds", transform((x, water_y, z), rng.uniform(0, 360)))
    for x, z in scatter(footprint, rng, 30, (3.0, 10.0), 10.0, avoid, (x0, x1), (z0, z1)):
        d.add("Moat", "lilies", transform((x, water_y, z), rng.uniform(0, 360)))
    print("towers=%d walls=%d banners=%d" % (len(towers), len(runs), banners))
    return d


# ---------------------------------------------------------------- level scene

def swap_weapon(level):
    """The scene's weapon becomes the siege bow, placed where the bazooka was and facing the same way as in
    world_local_siege_bow.tscn. The checkpoint markers' 2.6 m gap is the bow's minimum carry distance."""
    level.swap_ext("res://src/weapon/bazooka.tscn", SIEGE_BOW)
    weapon = level.find(r'\[node name="Bazooka" parent="Weapon" instance=(ExtResource\("[^"]+"\))\]\ntransform = Transform3D\(([^)]*)\)')
    values = [float(v) for v in weapon.group(2).split(",")]
    level.replace(weapon.group(0), '[node name="SiegeBow" parent="Weapon" instance=%s]\ntransform = %s' % (
        weapon.group(1), transform((values[9], values[10] + 1.0, values[11]), 180.0)))


def hide_pillars(level):
    """The mage pillars' own meshes are hidden; their StaticBody3D children still collide (visibility doesn't
    affect physics), and a turret prop is drawn in their place."""
    pattern = (r'(\[node name="enemy_pillar" type="MeshInstance3D" parent="Level/Pillars/enemy_pillar\d*"\]\n'
               r'transform = [^\n]*\nmesh = [^\n]*\nskeleton = [^\n]*\n)')
    level.text, count = re.subn(pattern, r'\1visible = false\n', level.text)
    assert count == 10, count


def main():
    force = "--force" in sys.argv[1:]
    write_props()
    level = Reskin(SOURCE)
    water_y = level.water_y()
    level.castle_tiles()
    level.swap_ext("res://src/world/elements/bridge_platform.tscn", "res://src/world/elements/medieval/castle_bridge_platform.tscn")
    swap_weapon(level)
    hide_pillars(level)
    level.castle_music()
    level.castle_arrow_colors()
    level.castle_environment()
    level.castle_light()
    level.moat()
    level.add_props()
    level.insert_decoration(decoration(level.refs, level.text, water_y))
    level.write(OUT, force)


if __name__ == "__main__":
    main()
