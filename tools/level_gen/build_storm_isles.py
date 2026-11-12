#!/usr/bin/env python3
"""Storm Isles: world_local_storm_isles.tscn, a saw level on stone islands in a rainy sea. Being built section by section.

(1) Warm-up: the start island, a walled stone yard like the dungeon's, with nine idle skeletons in a 3 x 3 grid.
    Their columns are 6 m apart, the saw's carry distance, so one pass with the carriers between two columns
    cuts down the column between them. Clearing them sets Checkpoint2 and raises a bridge to the second island.
(2) Horde: stepping onto the second island (both carriers) lowers the bridge behind them and starts a 60 s survival
    wave, one skeleton every 2 s, spawning on the island's far edges and running at the carriers. Clearing it sets
    Checkpoint3 and raises a bridge off the island's east side to a third island.
    The carriers cross it facing east, so Checkpoint3's markers put them one north of the other.
(3) Mages: both carriers stepping onto the third island lowers the bridge behind them, and six stationary mages appear
    in a puff, one in each corner and one at each of the north and south ends, and start shooting. Killing them sets
    Checkpoint4 and raises a bridge east to the fourth island.
(4) Grid horde: the fourth island is a lattice, like the trailer level's multi-bridge: walkways one cell wide with a
    one-cell hole every other tile, so the carriers walk two parallel walkways with the disc over the holes between.
    Landing lowers bridge 3 and starts a 60 s survival wave, one skeleton every 3 s, from the island's far side.
    Clearing it sets Checkpoint5 and raises a bridge south to the fifth island.
(5) Grid mages: the fifth island is the same lattice. Landing lowers bridge 4 and eight stationary mages appear,
    scattered over it. Killing them sets Checkpoint6 and raises a bridge east to a stone pad.
(6) Twin tracks: from the pad, two wooden tracks half a tile wide run east 84 m, one per carrier, 6 m apart (the saw's
    carry distance), with open sea between them. A wooden platform leads onto each, and sinks as soon as a carrier has
    crossed it, so the two can't take the same track in single file. Four mages stand on stone pillars in the sea
    between the tracks, 18 m apart, idle until both carriers are on the tracks; the disc, over the gap, cuts them as
    the pair walks past. The first is out of sight from the pad and comes into view a few steps onto the tracks.
    Killing them sets Checkpoint7 on the pad at the far end and raises a bridge east to the north pad.
(7) Winding tracks: from the north pad, twin tracks run north with turns: straight, diagonal north-west, straight,
    diagonal north-east, straight. Both are exact parallel offsets of one centre line, 6 m apart, so the carriers
    can always stay on them: the gap across is 6 m on every stretch and 6.5 m between the two corners of a turn,
    inside the saw's 5.5 to 7 m (the generator checks it). Sinking platforms and idle mages on pillars between the
    tracks, as in (6). Killing them sets Checkpoint8 on the pad at the far end and raises a bridge north.
(8) Three tracks (the final challenge): bridge 11 lands straight on three tracks running 72 m north, 3 m apart
    centre to centre. The carriers walk the outer two, 6 m apart, so the disc runs right over the middle one.
    Stepping onto them lowers the bridge behind and starts a 60 s survival wave, one skeleton every 10 s, spawning
    at either end of any of the three tracks, at random, and chasing the nearer carrier. Three short crossings join each outer track to the middle one, staggered
    so no two line up: a skeleton can use them to get round the disc and at a carrier, and on an outer track it
    can't be cut. So this wave clears on its timer: skeletons still alive at 60 s crumble. The tracks and crossings
    are in the navmesh. Clearing the wave sets Checkpoint9 at the tracks' far end and raises a bridge to the last pad,
    which holds the end area.

Run from the project root; see docs/level-creation-for-agents.md:
    PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/level_gen python3 tools/level_gen/build_storm_isles.py [baked.json] [--force]
The stone tiles are built by build_isle_tiles.gd; the rain is src/world/elements/storm_isles/rain.tscn.
The scene's uid is uid://0flshs2p1kdo: a re-bake writes a new one into its JSON, so put this one back before regenerating.
"""
import math
import sys

from levelgen import (AREAS, CELL, EVENTS, GROUPS, TRIGGER as T, WATER_Y, Level, fmt, node_paths, rect, tf, triple_bridge,
                      world)


def chamfered(x0, x1, z0, z1):
    """A rectangle with its corners cut, so an island doesn't read as a box."""
    cells = rect(x0, x1, z0, z1)
    for x, dx in ((x0, 1), (x1, -1)):
        for z, dz in ((z0, 1), (z1, -1)):
            cells -= {(x, z), (x + dx, z), (x, z + dz)}
    return cells


def lattice(x0, x1, z0, z1):
    """A grid of one-cell walkways: every other cell of every other row is a hole, starting one in from (x0, z0), so
    the outer ring is solid and holes sit one walkway apart in both directions."""
    return {(x, z) for x, z in rect(x0, x1, z0, z1) if (x - x0) % 2 == 0 or (z - z0) % 2 == 0}


def checkpoint(name, cx, cz, opened=(), reset=(), defeated=(), react=(), done=()):
    """One checkpoint's restore state: the bridges open, the groups reset or dead, the triggers live or spent."""
    arrays = {}
    for key, prefix, names in (("events_completed", "../../Level/Events/", opened), ("enemy_groups_reset", "../../Enemies/", reset),
                               ("enemy_groups_defeated", "../../Enemies/", defeated), ("areas_to_reactivate", "../../Level/Areas/", react),
                               ("areas_already_activated", "../../Level/Areas/", done)):
        if names:
            arrays[key] = [prefix + n for n in names]
    return (name, cx, cz, arrays)


# ---- Layout, in grid cells. Forward is -z. ----
START_ISLAND = chamfered(-5, 5, -6, 6)
SECOND_ISLAND = chamfered(-6, 6, -20, -9)
THIRD_ISLAND = chamfered(9, 17, -20, -10)  # east of the second, centred on the east rows
# The grids, 15 x 15 cells. The fourth's walkway rows are the even ones, so the carriers arriving from bridge 3 on
# rows -16 and -14 walk straight on along walkways, the disc over row -15's holes. The fifth's walkway columns are the
# even ones, so carriers arriving from the north on columns 26 and 28 do the same over column 27.
GRID_ISLAND = lattice(20, 34, -22, -8)
MAGE_GRID = lattice(20, 34, -5, 9)  # south of the fourth
# The twin tracks, east of bridge 5: a stone pad, a sinking platform per track, the tracks, and a pad at the far end.
TRACK_PAD = rect(37, 38, 0, 4)
TRACK_ROWS = (1, 3)  # one per carrier, two cells apart; the disc runs over row 2
TRACK_X = range(40, 68)  # 28 cells, 84 m: room for the mages 18 m apart and a first one out of sight from the pad
TRACK_END = rect(68, 70, 0, 4)
# The winding tracks, north of the north pad. Centre line in cells (x, z) at cell edges, so the start lines up with the
# sinking platforms on columns 75 and 77: 5 cells north, 5 x 5 north-west, 5 north, 5 x 5 north-east, 5 north.
NORTH_PAD = chamfered(73, 79, -2, 5)
NORTH_LINE = ((76.5, -3), (76.5, -8), (71.5, -13), (71.5, -18), (76.5, -23), (76.5, -28))
NORTH_END = rect(73, 79, -32, -29)
# The three tracks, straight off bridge 11, on columns 75, 76 and 77 (3 m apart, so the outer two sit at the saw's
# 6 m and the disc over the middle one), and the last pad beyond bridge 12. No pad before them: it would join all
# three at the south end, a free crossing for skeletons spawning there.
TRI_COLUMNS = (75, 76, 77)  # left, middle, right
TRI_Z = (-35, -58)  # the tracks' first and last cell
TRI_END = rect(72, 80, -65, -61)
# Crossings, as the cell row each sits on: three between left and middle, three between middle and right, no two on
# the same row or the next one, so they never line up across the middle. None in the first or last five rows, by
# the spawns: with crossings there, every skeleton stepped off the middle track at once, before the carriers could
# meet it. With every crossing on one side of them, carriers parked at the far end cut down the whole wave; with
# spawns at both ends, there is no such spot.
TRI_CROSSINGS = {"left": (-41, -46, -50), "right": (-43, -48, -52)}
FLOOR = (START_ISLAND | SECOND_ISLAND | THIRD_ISLAND | GRID_ISLAND | MAGE_GRID | TRACK_PAD | TRACK_END | NORTH_PAD | NORTH_END
         | TRI_END)
EAST_ROWS = (-16, -15, -14)  # where the east bridges cross: three platforms wide, like the first
SOUTH_COLUMNS = (26, 27, 28)  # bridge 4, from the fourth island down to the fifth
EXIT_ROWS = (1, 2, 3)  # bridge 5, east off the fifth island
BRIDGES = {1: triple_bridge(-7, -8), 2: [(x, z) for x in (7, 8) for z in EAST_ROWS],
           3: [(x, z) for x in (18, 19) for z in EAST_ROWS], 4: [(x, z) for x in SOUTH_COLUMNS for z in (-7, -6)],
           5: [(x, z) for x in (35, 36) for z in EXIT_ROWS],
           6: [(39, TRACK_ROWS[0])], 7: [(39, TRACK_ROWS[1])],  # the sinking platforms, one onto each track
           8: [(x, z) for x in (71, 72) for z in EXIT_ROWS],  # to the north pad
           9: [(75, -3)], 10: [(77, -3)],  # the north tracks' sinking platforms
           11: [(x, z) for x in (75, 76, 77) for z in (-33, -34)],  # onto the three tracks
           12: [(x, z) for x in TRI_COLUMNS for z in (-59, -60)]}  # from the tracks' far end to the last pad
assert [x for x, _ in BRIDGES[11][::2]] == list(TRI_COLUMNS) and min(z for _, z in BRIDGES[11]) == TRI_Z[0] + 1, "bridge 11 meets the tracks"
assert all((x, -61) in TRI_END for x in TRI_COLUMNS), "bridge 12 lands on the last pad"
crossing_rows = sorted(TRI_CROSSINGS["left"] + TRI_CROSSINGS["right"])
assert all(b - a >= 2 for a, b in zip(crossing_rows, crossing_rows[1:])), "crossings scattered, never side by side"
assert all(TRI_Z[1] < z < TRI_Z[0] for z in crossing_rows), "crossings along the tracks, not at their ends"
assert min(crossing_rows) - TRI_Z[1] >= 5 and TRI_Z[0] - max(crossing_rows) >= 5, "plain middle track by both spawns"
assert all((72, z) in BRIDGES[8] and (73, z) in NORTH_PAD for z in EXIT_ROWS), "bridge 8 lands on the north pad"
assert all((x, -2) in NORTH_PAD for x in (75, 77)), "the north sinking platforms leave the north pad"
assert all((x, -32) in NORTH_END for x in (75, 76, 77)), "bridge 11 leaves the north end pad"
assert all((36, z) in BRIDGES[5] and (37, z) in TRACK_PAD for z in EXIT_ROWS), "bridge 5 lands on the track pad"
assert all((38, z) in TRACK_PAD and (TRACK_X[-1] + 1, z) in TRACK_END for z in TRACK_ROWS), "the tracks join both pads"
assert all((70, z) in TRACK_END for z in EXIT_ROWS), "bridge 8 leaves the far pad"
assert all((17, z) in THIRD_ISLAND and (20, z) in GRID_ISLAND for z in EAST_ROWS), "bridge 3 lands on both islands"
assert all((x, -8) in GRID_ISLAND and (x, -5) in MAGE_GRID for x in SOUTH_COLUMNS), "bridge 4 lands on both grids"
assert all((34, z) in MAGE_GRID for z in EXIT_ROWS), "bridge 5 leaves the fifth island"
assert all((x, z) in GRID_ISLAND for x in range(20, 35) for z in (-16, -14)), "the carriers' walkways across the fourth"
assert all((x, z) in MAGE_GRID for x in (26, 28) for z in range(-5, 10)), "the carriers' walkways down the fifth"
assert not FLOOR & {c for cells in BRIDGES.values() for c in cells}, "bridges cross open sea"
assert all((x, -6) in FLOOR and (x, -9) in FLOOR for x in (-1, 0, 1)), "the first bridge lands on both islands"
assert all((6, z) in FLOOR and (9, z) in FLOOR for z in EAST_ROWS), "the east bridge lands on both islands"

# Ruins, like the dungeon's: pillars at the yard's corners, a broken parapet on the camera side (low, so it hides
# nothing) and stubs of wall on the flanks. All clear of the skeleton grid and the carriers' lanes.
PILLARS = {(-4, 4): "Pillar", (4, 4): "PillarBroken", (-4, -4): "PillarBroken", (4, -4): "Pillar",
           (-5, -12): "PillarBroken", (5, -11): "Pillar", (-4, -18): "Pillar", (4, -18): "PillarBroken",
           (17, -12): "Pillar", (17, -18): "PillarBroken"}
WALLS = {(-3, 6), (-2, 6), (2, 6), (3, 6), (-5, 0), (-5, 1), (5, -1), (5, -2)}
BRAZIERS = ((-4, 2), (4, 2), (-4, -2), (4, -2), (-2, -10), (2, -10), (10, -17), (10, -13))  # the last two flank the third island's landing
SEA_ROCKS = ((-30, 6, "Rock_5_A", 0), (31, -6, "Rock_6_A", 10), (-32, -34, "Rock_4_A", 16), (40, -88, "Rock_1_A", 22),
             (-26, -58, "Rock_5_C", 0), (34, 14, "Rock_1_C", 10))

# The warm-up grid: columns one carry distance (2 cells) apart, rows 1.5 cells apart, starting 7.5 m ahead of the spawn.
GRID_COLUMNS = (-2, 0, 2)
GRID_ROWS = (1.5, 0, -1.5)
SPAWN = (0, 4)

# The horde: skeletons appear on the second island's far edges, away from where the carriers land.
HORDE_SPAWNS = ((-5, -15), (-2, -19), (2, -19), (5, -17))
HORDE_SECONDS = 60
SPAWN_INTERVAL = 2.0
assert all(c in SECOND_ISLAND and c not in PILLARS for c in HORDE_SPAWNS)

# The mages: the third island's four corner cells (beside the cut corners) and the middle of its north and south
# edges. From the island's middle each is 15 m away, so a 16 m range lets all six reach it; at the landing the east
# corners are out of range. At normal zoom none shows from the middle: they fire from off screen, which is intended.
# Each edge mage can be straddled along its edge; the corner ones along the diagonal, past the cut corner.
MAGES = ((10, -19), (16, -19), (10, -11), (16, -11), (13, -20), (13, -10))
MAGE_RANGE = 16.0
assert all(c in THIRD_ISLAND and c not in PILLARS and c not in BRAZIERS for c in MAGES)

# The grid horde: skeletons appear on the fourth island's far (east) column and its far corners.
GRID_HORDE_SPAWNS = ((34, -22), (34, -15), (34, -8), (28, -22), (28, -8))
GRID_HORDE_SECONDS = 60
GRID_SPAWN_INTERVAL = 3.0
assert all(c in GRID_ISLAND for c in GRID_HORDE_SPAWNS)

# The grid mages: scattered on the fifth island's walkways. Where the landing trigger fires (two rows in), four of
# the eight can reach the carriers; walking in, five at once did in testing. 14 m range, 3 ± 1 s between casts. Each stands on a walkway the disc can
# run down, with the carriers in single file on it, or between two walkways the carriers can straddle.
GRID_MAGES = ((21, -3), (31, -3), (24, 2), (30, 0), (22, 5), (27, 5), (34, 6), (26, 8))
GRID_MAGE_RANGE = 14.0

# The final survival: 60 s, one skeleton every 10 s, from either end of any of the three tracks, picked at random.
# The outer tracks' four were added by hand in the editor, to make it harder: a skeleton spawned there starts on a
# carrier's track, out of the disc's reach. Kept in that order, so the nodes keep their names (Node3D1 to Node3D6).
TRI_SURVIVAL_SPAWNS = ((76, -58), (76, -35), (75, -58), (77, -58), (77, -35), (75, -35))
TRI_SURVIVAL_SECONDS = 60
TRI_SPAWN_INTERVAL = 10.0
assert all(c in MAGE_GRID for c in GRID_MAGES)

# The track mages, on pillars in the gap between the tracks, one every six cells (18 m), so their 12 m range never
# reaches past the next: idle until both carriers are on the tracks, 3 ± 1 s between casts. The saw's camera shows
# about 17 m ahead (measured): from the pad's east edge it reaches cell 44, so the first mage, at 46, comes into view
# a cell or so onto the tracks.
TRACK_MAGES = ((46, 2), (52, 2), (58, 2), (64, 2))
CAMERA_REACH_FROM_PAD = 44
TRACK_MAGE_RANGE = 12.0
assert all(x in TRACK_X and z == 2 for x, z in TRACK_MAGES)
assert TRACK_MAGES[0][0] - 1 > CAMERA_REACH_FROM_PAD, "the first track mage is out of sight from the pad"
assert all(b[0] - a[0] >= 6 for a, b in zip(TRACK_MAGES, TRACK_MAGES[1:])), "track mages 18 m apart or more"
assert TRACK_X[-1] - TRACK_MAGES[-1][0] >= 3, "track room past the last mage"


# ---- The winding tracks' geometry, in metres (x, z). ----
def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def _unit(v):
    n = math.hypot(*v)
    return (v[0] / n, v[1] / n)


def _right(direction):
    """The normal on the right of a heading: east when heading north (-z)."""
    return (-direction[1], direction[0])


def offset_line(points, d):
    """A parallel offset of a polyline, d metres to its right (negative: left), mitred at every turn so each
    stretch stays exactly d from the centre line's matching stretch."""
    out = []
    for i, p in enumerate(points):
        normals = [_right(_unit(_sub(points[j + 1], points[j]))) for j in (i - 1, i) if 0 <= j < len(points) - 1]
        mitre = _unit((sum(n[0] for n in normals), sum(n[1] for n in normals)))
        scale = d / (mitre[0] * normals[0][0] + mitre[1] * normals[0][1])
        out.append((p[0] + mitre[0] * scale, p[1] + mitre[1] * scale))
    return out


def distance_to_line(p, points):
    best = math.inf
    for a, b in zip(points, points[1:]):
        ab, ap = _sub(b, a), _sub(p, a)
        t = max(0.0, min(1.0, (ap[0] * ab[0] + ap[1] * ab[1]) / (ab[0] ** 2 + ab[1] ** 2)))
        best = min(best, math.hypot(ap[0] - ab[0] * t, ap[1] - ab[1] * t))
    return best


def samples(points, step=0.25):
    for a, b in zip(points, points[1:]):
        n = max(1, int(math.hypot(*_sub(b, a)) / step))
        for k in range(n + 1):
            yield (a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n)


def point_along(points, distance):
    """The point that far along a polyline, and the heading there."""
    for a, b in zip(points, points[1:]):
        length = math.hypot(*_sub(b, a))
        if distance <= length:
            u = _unit(_sub(b, a))
            return (a[0] + u[0] * distance, a[1] + u[1] * distance), u
        distance -= length
    raise ValueError("past the end of the line")


TRACK_GAP = 6.0  # centre to centre, the saw's middle carry distance
TRACK_HALF_WIDTH = 0.75
NORTH_CENTRE = [(x * CELL, z * CELL) for x, z in NORTH_LINE]
NORTH_WEST = offset_line(NORTH_CENTRE, -TRACK_GAP / 2)
NORTH_EAST = offset_line(NORTH_CENTRE, TRACK_GAP / 2)
# Every spot on one track has a spot on the other within the saw's carry range, so both carriers can always stand on
# their own track. 5.5 and 7 are the saw's min_carrier_distance and max_carrier_distance (src/weapon/saw.tscn).
SAW_CARRY = (5.5, 7.0)
for track, other in ((NORTH_WEST, NORTH_EAST), (NORTH_EAST, NORTH_WEST)):
    gaps = [distance_to_line(p, other) for p in samples(track)]
    assert SAW_CARRY[0] <= min(gaps) and max(gaps) <= SAW_CARRY[1], ("tracks out of the saw's reach", min(gaps), max(gaps))
corner_gaps = [math.hypot(*_sub(w, e)) for w, e in zip(NORTH_WEST, NORTH_EAST)]
assert max(corner_gaps) <= SAW_CARRY[1], ("a turn's corners are too far apart", corner_gaps)
assert math.hypot(*_sub(NORTH_WEST[0], (world(75, 0)[0], -3 * CELL))) < 0.01, "the west track starts at its sinking platform"
# The north mages, on pillars on the centre line, 18 m apart along it: mid first diagonal, mid second straight, mid
# second diagonal, mid last straight. The first is 25 m north of the pad, out of sight from it.
NORTH_MAGE_DISTANCES = (25.6, 43.7, 61.8, 79.9)
NORTH_MAGES = [point_along(NORTH_CENTRE, d) for d in NORTH_MAGE_DISTANCES]
NORTH_MAGE_RANGE = 12.0
PILLAR_HALF = 0.9
for (x, z), _heading in NORTH_MAGES:
    for track in (NORTH_WEST, NORTH_EAST):
        assert distance_to_line((x, z), track) - TRACK_HALF_WIDTH - PILLAR_HALF > 0.9, "a pillar crowds a track"
assert not any(c in PILLARS for c in BRIDGES[2]) and all((x, z) not in PILLARS for x in (5, 6, 9, 10) for z in EAST_ROWS)

level = Level("src/world/levels/world_local_storm_isles.tscn", palette="isles", weapon="saw", floor_seed=1, deco_seed=1,
              hint="[color=#ff8888]Saw usage[/color]\n\nThe saw is always spinning : steer it into enemies together !",
              follow_offset="Vector3(0, 11, 4.714)", music="dark_fairies")  # the saw's raised camera, as in world_local_saw
level.use_storm_isles()
level.curve = (SPAWN_INTERVAL, SPAWN_INTERVAL)  # seconds between survival spawns, start to end
level.boxes = {"fall": (500, 1, 420), "horde": (36, 3, 6), "isle3": (6, 3, 15), "isle5": (15, 3, 6), "track": (2, 3, 2),
               "tracks": (6, 3, 12), "north_tracks": (12, 3, 3), "end": (12, 3, 6)}
level.extra_sub_resources.append(f"""[sub_resource type="Curve" id="Curve_survival_tri"]
_limits = [0.0, {TRI_SPAWN_INTERVAL:.1f}, 0.0, 1.0]
_data = [Vector2(0, {TRI_SPAWN_INTERVAL:.1f}), 0.0, 0.0, 0, 0, Vector2(1, {TRI_SPAWN_INTERVAL:.1f}), 0.0, 0.0, 0, 0]
point_count = 2""")
level.extra_sub_resources.append(f"""[sub_resource type="Curve" id="Curve_survival_grid"]
_limits = [0.0, {GRID_SPAWN_INTERVAL:.1f}, 0.0, 1.0]
_data = [Vector2(0, {GRID_SPAWN_INTERVAL:.1f}), 0.0, 0.0, 0, 0, Vector2(1, {GRID_SPAWN_INTERVAL:.1f}), 0.0, 0.0, 0, 0]
point_count = 2""")
level.add_shell()

# ---- Enemies. ----
level.enemy_group("EnemyGroup")  # idle warm-up targets, never triggered
for i, (cx, cz) in enumerate(((cx, cz) for cz in GRID_ROWS for cx in GRID_COLUMNS), 1):
    level.melee("EnemyGroup", f"EnemyLocal{i}", cx, cz)
level.survival_group(HORDE_SPAWNS, duration=HORDE_SECONDS)
level.enemy_group("MageGroup", spawn_on_trigger=True)  # out of the level until the carriers land on the third island
for i, (cx, cz) in enumerate(MAGES, 1):
    level.mage("MageGroup", f"EnemyMage{i}", cx, cz, cast_max=MAGE_RANGE, cooldown=3.0, cooldown_jitter=1.0)
# The later survival waves, built here because levelgen's survival_group() only makes the one named SurvivalEnemyGroup.
def survival(name, curve, seconds, spawns, clears_on_timer=False):
    """clears_on_timer: survivors crumble when the time is up, so the players only have to last it."""
    props = {"script": 'ExtResource("survival_group")', "spawn_interval_curve": f'SubResource("{curve}")', "fight_duration": f"{seconds:.1f}"}
    if clears_on_timer:
        props["clears_on_timer"] = "true"
    level.node(name, "Enemies", "Node3D", props=props)
    level.node("Enemies", f"Enemies/{name}", "Node3D")
    level.node("SpawnPoints", f"Enemies/{name}", "Node3D")
    for i, (cx, cz) in enumerate(spawns, 1):
        sx, sz = world(cx, cz)
        level.node(f"Node3D{i}", f"Enemies/{name}/SpawnPoints", "Node3D", props={"transform": tf(sx, 0, sz)})


survival("SurvivalEnemyGroup2", "Curve_survival_grid", GRID_HORDE_SECONDS, GRID_HORDE_SPAWNS)
# A skeleton that takes a crossing to an outer track can't be cut there, so this wave clears on its timer: whatever
# is still alive at 60 s crumbles.
survival("SurvivalEnemyGroup3", "Curve_survival_tri", TRI_SURVIVAL_SECONDS, TRI_SURVIVAL_SPAWNS, clears_on_timer=True)
level.enemy_group("MageGroup2", spawn_on_trigger=True)  # out of the level until the carriers land on the fifth island
for i, (cx, cz) in enumerate(GRID_MAGES, 1):
    level.mage("MageGroup2", f"EnemyMage{i}", cx, cz, cast_max=GRID_MAGE_RANGE, cooldown=3.0, cooldown_jitter=1.0)
level.enemy_group("NorthMages")  # the winding tracks' mages, idle until the carriers are on those tracks
for i, ((x, z), _heading) in enumerate(NORTH_MAGES, 1):
    level.mage("NorthMages", f"EnemyMage{i}", x / CELL - 0.5, z / CELL - 0.5, cast_max=NORTH_MAGE_RANGE, cooldown=3.0, cooldown_jitter=1.0)
level.enemy_group("TrackMages")  # on their pillars from the start, idle until the carriers are on the tracks
for i, (cx, cz) in enumerate(TRACK_MAGES, 1):
    level.mage("TrackMages", f"EnemyMage{i}", cx, cz, cast_max=TRACK_MAGE_RANGE, cooldown=3.0, cooldown_jitter=1.0)

# ---- Decoration on the grids: the medieval level's wall torches and banners, and its reeds and lily pads. All
# visual, with no collision, outside the navigation region. The camera looks north from just south of the carriers,
# so it only sees walls facing south when they're in the top half of the screen: an island's outer south wall is
# behind it (it showed only banner rods), but each hole's north wall faces it. So banners and most torches hang inside
# the holes on that wall, and the outer walls get torches, whose flames stick out far enough to show from above. ----
TORCH_Y = -1.9  # a little below the rim (the floor's top is at -1), like the medieval cliffs' torches
BANNER_Y = -1.05  # the rod just under the rim; the 3 m cloth hangs to 0.5 m above the sea
# (field, charge colour, charge): storm blues and a sea green, gold charges.
BANNER_COLOURS = (((0.12, 0.2, 0.5), (0.95, 0.85, 0.45), 1), ((0.1, 0.32, 0.3), (0.95, 0.76, 0.25), 3),
                  ((0.12, 0.2, 0.5), (0.95, 0.85, 0.45), 2), ((0.1, 0.32, 0.3), (0.95, 0.76, 0.25), 0))
FACING = {"south": 0, "north": 180, "east": 90, "west": -90}  # degrees about y that turn a torch's +z out of that face


def yaw(degrees):
    r = math.radians(degrees)
    c, s_ = math.cos(r), math.sin(r)
    return f"{fmt(c)}, 0, {fmt(s_)}, 0, 1, 0, {fmt(-s_)}, 0, {fmt(c)}"


def outer_face(x0, x1, z0, z1, side, cell):
    """The point on a lattice's outer wall at that cell along the given side."""
    if side == "south":
        return ((cell + 0.5) * CELL, (z1 + 1) * CELL)
    if side == "north":
        return ((cell + 0.5) * CELL, z0 * CELL)
    if side == "east":
        return ((x1 + 1) * CELL, (cell + 0.5) * CELL)
    return (x0 * CELL, (cell + 0.5) * CELL)


def lattice_decor(name, x0, x1, z0, z1, torches):
    """torches: {side: cells along it} on the outer walls. The holes, on diagonals four apart, get in turn a torch,
    then a banner or reeds or lily pads; the rest stay bare."""
    level.node(name, "Level/Decor", "Node3D")
    torch_count = banner_count = plant_count = 0
    for side, cells in torches.items():
        for cell in cells:
            torch_count += 1
            wx, wz = outer_face(x0, x1, z0, z1, side, cell)
            level.node(f"Torch{torch_count}", f"Level/Decor/{name}", instance="wall_torch", props={"transform": tf(wx, TORCH_Y, wz, yaw(FACING[side]))})
    for hx in range(x0 + 1, x1, 2):
        for hz in range(z0 + 1, z1, 2):
            i, j = (hx - x0) // 2, (hz - z0) // 2
            wx, wz = world(hx, hz)
            north_wall = hz * CELL
            if (i + j) % 4 == 0:
                torch_count += 1
                level.node(f"Torch{torch_count}", f"Level/Decor/{name}", instance="wall_torch", props={"transform": tf(wx, TORCH_Y, north_wall)})
            elif (i + j) % 4 == 2 and i % 2 == 1:
                field, charge_colour, charge = BANNER_COLOURS[banner_count % len(BANNER_COLOURS)]
                banner_count += 1
                level.node(f"Banner{banner_count}", f"Level/Decor/{name}", instance="wall_banner", props={"transform": tf(wx, BANNER_Y, north_wall)})
                # The colours are per-instance shader parameters, so they go on the cloth mesh: on the banner's root
                # (a plain Node3D) they do nothing.
                level.node("Cloth", f"Level/Decor/{name}/Banner{banner_count}", props={
                    "instance_shader_parameters/charge": str(charge),
                    "instance_shader_parameters/charge_color": "Color(%s, %s, %s, 1)" % charge_colour,
                    "instance_shader_parameters/field_color": "Color(%s, %s, %s, 1)" % field})
            elif (i + j) % 4 == 2:
                plant_count += 1
                level.node(f"Plants{plant_count}", f"Level/Decor/{name}", instance=("reeds", "lily_pads")[plant_count % 2],
                           props={"transform": tf(wx, WATER_Y, wz, yaw(plant_count * 71.0))})
    return torch_count, banner_count, plant_count


# ---- Checkpoints. Each one's arrays describe the world once the fight before it is won: what is open, which groups
# stay dead, which group the next fight resets, and which landing trigger re-arms. ----
# Facing east, the setter's side (left) is north: the carriers respawn one north of the other, facing the bridge.
EAST_MARKERS = ((0, -3), (0, 3))
T3, T4, T5 = T + "3", T + "4", T + "5"
GROUP_ORDER = ["EnemyGroup", "SurvivalEnemyGroup", "MageGroup", "SurvivalEnemyGroup2", "MageGroup2", "TrackMages", "NorthMages",
               "SurvivalEnemyGroup3"]
T6, TRACK_TRIGGERS = T + "6", ["SinglePlayerTrackTrigger1", "SinglePlayerTrackTrigger2"]
T7, NORTH_TRIGGERS = T + "7", ["SinglePlayerNorthTrigger1", "SinglePlayerNorthTrigger2"]
T8 = T + "8"
TRIGGER_ORDER = [T, T3, T4, T5, T6, T7, T8]
CHECKPOINTS = [checkpoint("Checkpoint", *SPAWN)]
# (name, cell, bridge opened, island, markers): the checkpoint each fight earns, in order.
EARNED = [("Checkpoint2", (0, -4), "OpenBridge1", START_ISLAND, None),
          ("Checkpoint3", (3, -15), "OpenBridge2", SECOND_ISLAND, EAST_MARKERS),
          ("Checkpoint4", (13, -15), "OpenBridge3", THIRD_ISLAND, EAST_MARKERS),
          ("Checkpoint5", (27, -12), "OpenBridge4", GRID_ISLAND, None),  # side by side over column 27, facing bridge 4
          ("Checkpoint6", (32, 2), "OpenBridge5", MAGE_GRID, EAST_MARKERS),
          ("Checkpoint7", (69, 2), "OpenBridge8", TRACK_END, EAST_MARKERS),
          ("Checkpoint8", (76, -30), "OpenBridge11", NORTH_END, None),  # side by side, facing bridge 11
          ("Checkpoint9", (76, -57), "OpenBridge12", None, None)]  # the tracks' far end: one carrier on each outer track
# Checkpoints 6 and 7 also raise the next tracks' sinking platforms and re-arm their triggers; past them, those
# triggers are spent.
EXTRA_OPENED = {"Checkpoint6": ["OpenTrackPlatforms"], "Checkpoint7": ["OpenNorthPlatforms"]}
EXTRA_REACT = {"Checkpoint6": TRACK_TRIGGERS, "Checkpoint7": NORTH_TRIGGERS}
EXTRA_DONE = {"Checkpoint7": TRACK_TRIGGERS, "Checkpoint8": TRACK_TRIGGERS + NORTH_TRIGGERS,
              "Checkpoint9": TRACK_TRIGGERS + NORTH_TRIGGERS}
# Where a checkpoint's carriers stand: island cells, or for Checkpoint9 the outer tracks (checked below).
TRI_TRACK_CELLS = {(x, z) for x in TRI_COLUMNS for z in range(TRI_Z[1], TRI_Z[0] + 1)}
ISLAND_OF = {"Checkpoint": START_ISLAND}
for n, (name, (cx, cz), opened, island, markers) in enumerate(EARNED, 1):
    entry = checkpoint(name, cx, cz, [opened] + EXTRA_OPENED.get(name, []), GROUP_ORDER[n:n + 1], GROUP_ORDER[:n],
                       TRIGGER_ORDER[n - 1:n] + EXTRA_REACT.get(name, []), TRIGGER_ORDER[:n - 1] + EXTRA_DONE.get(name, []))
    CHECKPOINTS.append(entry + ((markers,) if markers else ()))
    ISLAND_OF[name] = island if island is not None else TRI_TRACK_CELLS
for name, cx, cz, _arrays, *markers in CHECKPOINTS:
    island = ISLAND_OF[name]
    feet = [(cx, cz + d) for d in (-1, 0, 1)] if markers else [(cx + d, cz) for d in (-1, 0, 1)]
    assert all(c in island and c not in PILLARS for c in feet), (name, cx, cz)
level.checkpoints(CHECKPOINTS, setter_marker=(-3, 0), shooter_marker=(3, 0))  # side by side, saw across the path

# ---- Terrain and events. ----
# The sea and the fall area reach from west of the start island to well past the north pad (x -18 m to 240 m):
# the sea spans x -100 to 300 m, the fall area -150 to 350 m; north-south, the sea runs from 110 m south to 230 m
# north and the fall area from 150 m to 270 m, past the last pad (about 200 m north).
level.add_isle_terrain(FLOOR, PILLARS, WALLS, fall_z=-60, water_z=-60, rocks=SEA_ROCKS, fall_x=100, water_x=100)
level.add_braziers(BRAZIERS)
level.extra_ext += [("PackedScene", None, f"res://src/world/elements/medieval/{scene}.tscn", scene) for scene in ("wall_torch", "wall_banner", "reeds", "lily_pads")]
level.node("Decor", "Level", "Node3D")
# Torches every four cells or so round the outer walls, clear of each bridge's landing.
lattice_decor("GridIsland", 20, 34, -22, -8, torches={
    "south": (21, 24, 30, 33), "east": (-21, -17, -13, -9), "west": (-21, -18, -11, -8), "north": (21, 25, 29, 33)})
lattice_decor("MageGrid", 20, 34, -5, 9, torches={
    "south": (21, 25, 29, 33), "east": (-4, -1, 6, 9), "west": (-4, 0, 4, 8), "north": (21, 23, 31, 33)})
assert not {21, 24, 30, 33, 23, 31} & set(SOUTH_COLUMNS) and not {-21, -18, -11, -8} & set(EAST_ROWS) \
    and not {-4, -1, 6, 9} & set(EXIT_ROWS), "no torch hangs where a bridge meets a wall"
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "MakeSurvivalGroupOffensive")
level.offensive_event("MakeSurvivalGroupOffensive", "SurvivalEnemyGroup")
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "MakeMagesOffensive")
level.offensive_event("MakeMagesOffensive", "MageGroup")  # spawns them, in a puff, already shooting
level.bridge_event("OpenBridge3", 3)
level.bridge_event("CloseBridge3", 3, True, "MakeGridHordeOffensive")
level.offensive_event("MakeGridHordeOffensive", "SurvivalEnemyGroup2")
level.bridge_event("OpenBridge4", 4)
level.bridge_event("CloseBridge4", 4, True, "MakeGridMagesOffensive")
level.offensive_event("MakeGridMagesOffensive", "MageGroup2")
level.bridge_event("OpenBridge5", 5, next_event="OpenTrackPlatforms")
# Both sinking platforms rise with bridge 5; each sinks alone once a carrier is past it.
level.node("OpenTrackPlatforms", "Level/Events", "Node", paths=["platforms"], props={
    "script": 'ExtResource("toggle_bridge")', "use_camera_focus": "false", "platform_animation_stagger_seconds": "0.0",
    "platforms": node_paths(["../../Bridges/" + p for p in level.platforms[6] + level.platforms[7]])})
level.bridge_event("SinkTrackPlatform1", 6, True)
level.bridge_event("SinkTrackPlatform2", 7, True)
level.offensive_event("MakeTrackMagesOffensive", "TrackMages")
level.bridge_event("OpenBridge8", 8, next_event="OpenNorthPlatforms")
level.node("OpenNorthPlatforms", "Level/Events", "Node", paths=["platforms"], props={
    "script": 'ExtResource("toggle_bridge")', "use_camera_focus": "false", "platform_animation_stagger_seconds": "0.0",
    "platforms": node_paths(["../../Bridges/" + p for p in level.platforms[9] + level.platforms[10]])})
level.bridge_event("SinkNorthPlatform1", 9, True)
level.bridge_event("SinkNorthPlatform2", 10, True)
level.offensive_event("MakeNorthMagesOffensive", "NorthMages")
level.bridge_event("OpenBridge11", 11)
level.bridge_event("CloseBridge11", 11, True, "MakeTriSurvivalOffensive")
level.offensive_event("MakeTriSurvivalOffensive", "SurvivalEnemyGroup3")
level.bridge_event("OpenBridge12", 12)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_end_area(76, -63)  # on the last pad
level.add_bridge_nodes()
# Both carriers a step past each landing. Boxes run north-south where the carriers arrive one north of the other
# (from the west), east-west where they arrive side by side (from the north).
level.add_triggers(((T, 0, -11, "horde"), (T3, 11, -15, "isle3"), (T4, 21, -15, "isle3"), (T5, 27, -3, "isle5"),
                    (T6, 41, 2, "tracks"), (T7, 76, -5, "north_tracks"), (T8, 76, -36, "north_tracks")))
# A single-player trigger at the start of each track, just past its platform: the first carrier off the platform
# sinks it behind them. It lies before the mages' trigger, so the platforms sink before the mages wake.
level.extra_ext.append(("Script", None, "res://src/world/elements/single_player_area_trigger.gd", "single_player"))
for trigger, (cx, cz) in zip(TRACK_TRIGGERS + NORTH_TRIGGERS, [(TRACK_X[0], row) for row in TRACK_ROWS] + [(75, -4), (77, -4)]):
    tx, tz = world(cx, cz)
    level.node(trigger, "Level/Areas", "Area3D", props={"transform": tf(tx, 0, tz), "script": 'ExtResource("single_player")'})
    level.node("CollisionShape3D", f"Level/Areas/{trigger}", "CollisionShape3D", props={"shape": 'SubResource("BoxShape3D_track")'})
# The tracks and the mages' pillars: scenery with collision, outside the navigation region (nothing walks them but
# the carriers, and the mages stand still).
level.extra_ext += [("PackedScene", None, f"res://src/world/elements/storm_isles/{scene}.tscn", scene) for scene in ("wooden_track", "sea_pillar")]
level.node("Tracks", "Level", "Node3D")
for i, (x, row) in enumerate(((x, row) for row in TRACK_ROWS for x in TRACK_X), 1):
    wx, wz = world(x, row)
    level.node(f"Track{i}", "Level/Tracks", instance="wooden_track", props={"transform": tf(wx, 0, wz)})
for i, (x, z) in enumerate(TRACK_MAGES, 1):
    wx, wz = world(x, z)
    level.node(f"Pillar{i}", "Level/Tracks", instance="sea_pillar", props={"transform": tf(wx, 0, wz)})


def yaw_along(direction):
    """A basis turning local +x to this heading (x, z)."""
    return yaw(math.degrees(math.atan2(-direction[1], direction[0])))


def packed(points):
    return "PackedVector3Array(" + ", ".join(f"{fmt(x)}, 0, {fmt(z)}" for x, z in points) + ")"


# The winding tracks: one deck of the exact length per stretch (the 3 m track pieces can't run diagonally), posts
# under it about every 3 m, and a round deck at each turn, a touch higher, covering the joint. The node keeps the
# lines as metadata for the test driver.
level.extra_ext.append(("Shader", None, "res://src/world/elements/wooden_platform.gdshader", "wood_shader"))
level.extra_sub_resources.append("""[sub_resource type="ShaderMaterial" id="ShaderMaterial_track_wood"]
render_priority = 0
shader = ExtResource("wood_shader")
shader_parameter/plank_width = 0.375
shader_parameter/plank_length = 3.0

[sub_resource type="BoxMesh" id="BoxMesh_track_post"]
material = SubResource("ShaderMaterial_track_wood")
size = Vector3(0.3, 4.4, 0.3)

[sub_resource type="BoxMesh" id="BoxMesh_track_beam"]
material = SubResource("ShaderMaterial_track_wood")
size = Vector3(0.22, 0.22, 1.7)

[sub_resource type="CylinderMesh" id="CylinderMesh_track_joint"]
material = SubResource("ShaderMaterial_track_wood")
top_radius = 0.85
bottom_radius = 0.85
height = 0.3

[sub_resource type="CylinderShape3D" id="CylinderShape3D_track_joint"]
height = 0.3
radius = 0.85""")
level.node("NorthTracks", "Level", "Node3D", props={"metadata/centre": packed(NORTH_CENTRE), "metadata/west": packed(NORTH_WEST),
                                                     "metadata/east": packed(NORTH_EAST)})
def track_body(parent, name, a, b):
    """A wooden deck from a to b (metres, x z), 1.5 m wide, its top level with the floor, on posts about every 3 m."""
    length = math.hypot(*_sub(b, a))
    level.extra_sub_resources.append(f"""[sub_resource type="BoxMesh" id="BoxMesh_track_{name}"]
material = SubResource("ShaderMaterial_track_wood")
size = Vector3({fmt(length)}, 0.3, {fmt(TRACK_HALF_WIDTH * 2)})

[sub_resource type="BoxShape3D" id="BoxShape3D_track_{name}"]
size = Vector3({fmt(length)}, 0.3, {fmt(TRACK_HALF_WIDTH * 2)})""")
    mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    level.node(name, parent, "StaticBody3D", props={
        "transform": tf(mx, 0, mz, yaw_along(_unit(_sub(b, a)))), "collision_layer": "4", "collision_mask": "0"})
    level.node("Deck", f"{parent}/{name}", "MeshInstance3D", props={"transform": tf(0, -1.15, 0), "mesh": f'SubResource("BoxMesh_track_{name}")'})
    level.node("CollisionShape3D", f"{parent}/{name}", "CollisionShape3D", props={
        "transform": tf(0, -1.15, 0), "shape": f'SubResource("BoxShape3D_track_{name}")'})
    slots = max(1, round(length / CELL))
    for k in range(slots):
        px = -length / 2 + (k + 0.5) * length / slots
        level.node(f"Beam{k + 1}", f"{parent}/{name}", "MeshInstance3D", props={"transform": tf(px, -1.41, 0), "mesh": 'SubResource("BoxMesh_track_beam")'})
        for letter, pz in (("A", -0.55), ("B", 0.55)):
            level.node(f"Post{k + 1}{letter}", f"{parent}/{name}", "MeshInstance3D", props={
                "transform": tf(px, -3.5, pz), "mesh": 'SubResource("BoxMesh_track_post")'})


for side, line in (("West", NORTH_WEST), ("East", NORTH_EAST)):
    for i, (a, b) in enumerate(zip(line, line[1:]), 1):
        track_body("Level/NorthTracks", f"{side}{i}", a, b)
    for i, (x, z) in enumerate(line[1:-1], 1):
        level.node(f"{side}Joint{i}", "Level/NorthTracks", "StaticBody3D", props={"transform": tf(x, 0, z), "collision_layer": "4", "collision_mask": "0"})
        level.node("Deck", f"Level/NorthTracks/{side}Joint{i}", "MeshInstance3D", props={"transform": tf(0, -1.13, 0), "mesh": 'SubResource("CylinderMesh_track_joint")'})
        level.node("CollisionShape3D", f"Level/NorthTracks/{side}Joint{i}", "CollisionShape3D", props={
            "transform": tf(0, -1.13, 0), "shape": 'SubResource("CylinderShape3D_track_joint")'})
for i, ((x, z), heading) in enumerate(NORTH_MAGES, 1):
    level.node(f"Pillar{i}", "Level/NorthTracks", instance="sea_pillar", props={"transform": tf(x, 0, z, yaw_along(heading))})

# The three tracks and their crossings, inside the navigation region and marked for the bake (bake_nav.gd), so the
# skeletons can chase along them. Each crossing spans just the 1.5 m gap between two decks, so nothing overlaps.
TRI = "Level/NavigationRegion3D/TriTracks"
tri_x = [world(x, 0)[0] for x in TRI_COLUMNS]
tri_south, tri_north = TRI_Z[0] * CELL + CELL, TRI_Z[1] * CELL  # bridge 11's north edge and bridge 12's south edge
level.node("TriTracks", "Level/NavigationRegion3D", "Node3D", props={"metadata/bake_walkways": "true"})
for name, x in zip(("Left", "Middle", "Right"), tri_x):
    track_body(TRI, f"Tri{name}", (x, tri_south), (x, tri_north))
for side, (x0, x1) in (("left", (tri_x[0], tri_x[1])), ("right", (tri_x[1], tri_x[2]))):
    for i, row in enumerate(TRI_CROSSINGS[side], 1):
        z = (row + 0.5) * CELL
        track_body(TRI, f"TriCrossing{side.title()}{i}", (x0 + TRACK_HALF_WIDTH, z), (x1 - TRACK_HALF_WIDTH, z))
wx, wz = world(*SPAWN)
level.add_weapon("Saw", tf(wx, 1.8726845, wz, "-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08"))
level.add_audio_and_hint()

# ---- Signals. ----
# No camera framing: every enemy here can be walked to, so the normal zoom is enough.
level.connect("enemies_defeated", GROUPS + "EnemyGroup", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "EnemyGroup", EVENTS + "OpenBridge1")
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup", "CheckpointManager/Checkpoint3", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup", EVENTS + "OpenBridge2")
level.connect("all_players_inside", AREAS + T3, EVENTS + "CloseBridge2")
level.connect("enemies_defeated", GROUPS + "MageGroup", "CheckpointManager/Checkpoint4", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "MageGroup", EVENTS + "OpenBridge3")
level.connect("all_players_inside", AREAS + T4, EVENTS + "CloseBridge3")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup2", "CheckpointManager/Checkpoint5", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup2", EVENTS + "OpenBridge4")
level.connect("all_players_inside", AREAS + T5, EVENTS + "CloseBridge4")
level.connect("enemies_defeated", GROUPS + "MageGroup2", "CheckpointManager/Checkpoint6", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "MageGroup2", EVENTS + "OpenBridge5")
level.connect("player_inside", AREAS + TRACK_TRIGGERS[0], EVENTS + "SinkTrackPlatform1")
level.connect("player_inside", AREAS + TRACK_TRIGGERS[1], EVENTS + "SinkTrackPlatform2")
level.connect("all_players_inside", AREAS + T6, EVENTS + "MakeTrackMagesOffensive")
level.connect("enemies_defeated", GROUPS + "TrackMages", "CheckpointManager/Checkpoint7", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "TrackMages", EVENTS + "OpenBridge8")
level.connect("player_inside", AREAS + NORTH_TRIGGERS[0], EVENTS + "SinkNorthPlatform1")
level.connect("player_inside", AREAS + NORTH_TRIGGERS[1], EVENTS + "SinkNorthPlatform2")
level.connect("all_players_inside", AREAS + T7, EVENTS + "MakeNorthMagesOffensive")
level.connect("enemies_defeated", GROUPS + "NorthMages", "CheckpointManager/Checkpoint8", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "NorthMages", EVENTS + "OpenBridge11")
level.connect("all_players_inside", AREAS + T8, EVENTS + "CloseBridge11")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup3", "CheckpointManager/Checkpoint9", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup3", EVENTS + "OpenBridge12")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
