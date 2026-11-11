"""Adds the island labyrinth before the mage-turret arena of world_local_02_medieval.tscn.

Run add_medieval_02_mage_section.py first. This puts a new first section south of that arena: nine islands joined
by ten walkways of castle bridge platforms that bend (S-bends, a hairpin, a U around an island), so the two carriers
have to steer one sword round corners one platform wide. Each island has one stationary mage; ten skeletons stand
on the islands. The navmesh runs over the walkways too, so skeletons come after the carriers across the labyrinth
(the bridges into and out of it are not walkways, so they stay out of the navmesh). Killing all nine mages saves CheckpointStart and raises a bridge from the exit island to the arena.
The arena's camera framing now starts when both carriers step onto the arena.

The walkways are bridge platforms raised when the level starts (CheckpointLabyrinth lists their event as done).

It edits the level in place, in two steps, because the new islands need a navmesh:
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_medieval_02_labyrinth.py
  FLOOR_GRIDMAP=Level/NavigationRegion3D/FloorGridMap BAKE_CELL_Z_MIN=17 \\
      tools/level_gen/godot.sh bake res://src/world/levels/world_local_02_medieval.tscn /tmp/labyrinth_nav.json
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_medieval_02_labyrinth.py --nav /tmp/labyrinth_nav.json
The bake covers only the labyrinth's cells (z >= 17); --nav appends those polygons to the existing navmesh, so the
rest of the level's navmesh stays as it was. Each step refuses to run twice.
That first bake left the walkways out. To bake them in, which the level now has, re-bake with the walkway platforms
counted as floor and swap the labyrinth's part of the navmesh (this changes nothing else in the scene, so it is safe
after the level has been edited in Godot):
  FLOOR_GRIDMAP=Level/NavigationRegion3D/FloorGridMap BAKE_CELL_Z_MIN=17 BAKE_CELL_Z_MAX=44 \\
      BAKE_PLATFORMS_UNDER=Level/Bridges/Labyrinth \\
      tools/level_gen/godot.sh bake res://src/world/levels/world_local_02_medieval.tscn /tmp/labyrinth_walk_nav.json
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_medieval_02_labyrinth.py --replace-nav /tmp/labyrinth_walk_nav.json
Re-run those two after moving, adding or removing walkway platforms or islands.
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_medieval_02_labyrinth.gd res://src/world/levels/world_local_02_medieval.tscn /tmp/labyrinth 400
"""

import json
import re
import sys

import add_medieval_02_mage_section as arena
from add_medieval_02_mage_section import CENTRE, SIDE_TILES, decode, encode, node, replace_once
from medieval import CLIFF_BANNER_SCALE, CLIFF_OUT, CLIFF_TOP_Y, CLIFF_TORCH_Y, heraldry_params, transform

LEVEL = arena.LEVEL
CELL = arena.CELL
WATER_Y = arena.WATER_Y
STAND_Y = arena.FLOOR_TOP_Y + 0.05
BRIDGE_Y = -3.9927697

# ---------------------------------------------------------------- layout (cells; x east, z south)
# Islands as inclusive rectangles (x0, x1, z0, z1). The arena is x -6..-1, z 10..14, just north of the exit.
ISLANDS = {
    "Exit": (-6, -3, 17, 19),
    "NorthWest": (-15, -12, 19, 21),
    "NorthEast": (1, 4, 20, 22),
    "West": (-17, -15, 27, 29),
    "Centre": (-8, -5, 26, 29),
    "East": (4, 7, 27, 29),
    "SouthWest": (-14, -11, 35, 37),
    "SouthEast": (1, 4, 35, 37),
    "Start": (-6, -3, 38, 41),
}
# Arena exit: two platforms from the exit island's north edge to the arena's south edge.
ARENA_MOUTH = (-4, 14)
EXIT_BRIDGE = [(-4, 15), (-4, 16)]


def path(*corners):
    """Cells along straight runs between corner cells, corners included."""
    cells = [corners[0]]
    for (x0, z0), (x1, z1) in zip(corners, corners[1:]):
        assert x0 == x1 or z0 == z1, "walkway runs must be straight"
        dx, dz = (x1 > x0) - (x1 < x0), (z1 > z0) - (z1 < z0)
        x, z = x0, z0
        while (x, z) != (x1, z1):
            x, z = x + dx, z + dz
            cells.append((x, z))
    return cells


# Walkways: (from island, to island, cells). The first and last cells touch their island's edge (the mouths).
WALKWAYS = {
    # A staircase west and north from the start.
    "StartSouthWest": ("Start", "SouthWest", path((-7, 40), (-8, 40), (-8, 38), (-9, 38), (-9, 36), (-10, 36))),
    # East along the start's flank, past the south-east island, then north and back west: a U onto its far side.
    "StartSouthEast": ("Start", "SouthEast", path((-2, 40), (6, 40), (6, 36), (5, 36))),
    # A double S up the middle.
    "StartCentre": ("Start", "Centre", path((-5, 37), (-5, 33), (-3, 33), (-3, 31), (-6, 31), (-6, 30))),
    "SouthWestWest": ("SouthWest", "West", path((-12, 34), (-12, 32), (-16, 32), (-16, 30))),
    "WestNorthWest": ("West", "NorthWest", path((-16, 26), (-16, 23), (-13, 23), (-13, 22))),
    "NorthWestExit": ("NorthWest", "Exit", path((-11, 20), (-9, 20), (-9, 18), (-7, 18))),
    "SouthEastEast": ("SouthEast", "East", path((3, 34), (3, 31), (5, 31), (5, 30))),
    # A hairpin: north past the north-east island, then west and back south onto its north edge.
    "EastNorthEast": ("East", "NorthEast", path((6, 26), (6, 18), (3, 18), (3, 19))),
    "NorthEastExit": ("NorthEast", "Exit", path((0, 21), (-1, 21), (-1, 18), (-2, 18))),
    # Over a hump: east, north, east, south, east.
    "CentreEast": ("Centre", "East", path((-4, 28), (-3, 28), (-3, 25), (1, 25), (1, 28), (3, 28))),
}

# One stationary mage per island (a cell away from every mouth), and skeletons (ten in all).
MAGES = {
    "Start": (-3, 38), "SouthWest": (-14, 37), "SouthEast": (1, 37), "Centre": (-8, 26), "West": (-15, 28),
    "East": (7, 29), "NorthWest": (-15, 19), "NorthEast": (4, 22), "Exit": (-5, 19),
}
MAGE_COOLDOWNS = [6.5, 5.0, 5.5, 4.5, 5.0, 5.5, 4.5, 5.0, 4.5]
MAGE_CAST_MAX = 14.0
SKELETONS = [
    ("SouthWest", (-13, 36)), ("West", (-17, 28)), ("West", (-17, 27)), ("NorthWest", (-14, 20)),
    ("Exit", (-4, 18)), ("SouthEast", (2, 36)), ("East", (5, 28)), ("East", (7, 27)),
    ("NorthEast", (2, 21)), ("Centre", (-7, 28)),
]

START_CHECKPOINT = (-12.0, 4.0, 120.5)  # on the start island, south of its middle
ARENA_ARRIVAL = ((-9.0, 0.0, 37.5), (14.0, 4.0, 11.0))  # inside the arena's edges, so the bridge doesn't count
BAKE_CELL_Z_MIN = 17  # the labyrinth's cells, for the navmesh bake
NAV_MIN_Z_WORLD = 48.0  # navmesh vertices this far south can only come from a labyrinth bake


def cell_world(cx, cz):
    return (cx + 0.5) * CELL, (cz + 0.5) * CELL


def island_cells(name):
    x0, x1, z0, z1 = ISLANDS[name]
    return {(x, z) for x in range(x0, x1 + 1) for z in range(z0, z1 + 1)}


def neighbours(cell):
    x, z = cell
    return [(x + 1, z), (x - 1, z), (x, z + 1), (x, z - 1)]


def validate():
    """Islands apart, walkways only over water, touching nothing but their own two mouths and never each other."""
    land = {}
    for name in ISLANDS:
        for cell in island_cells(name):
            assert cell not in land, "islands %s and %s overlap" % (name, land[cell])
            land[cell] = name
    for name in ISLANDS:
        for cell in island_cells(name):
            for n in neighbours(cell):
                assert land.get(n, name) == name, "islands %s and %s touch" % (name, land[n])
    walked = {}
    mouths = {}
    for walk, (a, b, cells) in WALKWAYS.items():
        assert len(set(cells)) == len(cells), walk
        for index, cell in enumerate(cells):
            assert cell not in land, "%s crosses island %s at %s" % (walk, land.get(cell), cell)
            assert cell not in walked, "%s crosses %s at %s" % (walk, walked.get(cell), cell)
            walked[cell] = walk
            touching = {land[n] for n in neighbours(cell) if n in land}
            allowed = ({a} if index == 0 else set()) | ({b} if index == len(cells) - 1 else set())
            assert touching <= allowed, "%s touches %s at %s" % (walk, touching, cell)
        start = [n for n in neighbours(cells[0]) if land.get(n) == a]
        end = [n for n in neighbours(cells[-1]) if land.get(n) == b]
        assert len(start) == 1 and len(end) == 1, "%s needs one mouth at each end" % walk
        mouths[walk] = (start[0], end[0])
    for cell, walk in walked.items():
        for n in neighbours(cell):
            assert walked.get(n, walk) == walk, "walkways %s and %s touch at %s" % (walk, walked[n], cell)
    for walk, (start, end) in mouths.items():
        for mouth in (start, end):
            x0, x1, z0, z1 = ISLANDS[land[mouth]]
            assert mouth[0] not in (x0, x1) or mouth[1] not in (z0, z1), "%s lands on a corner at %s" % (walk, mouth)
    all_mouths = {m for pair in mouths.values() for m in pair} | {(-4, 17)}
    for island, cell in MAGES.items():
        assert land.get(cell) == island, "mage of %s is off its island" % island
        assert all(n not in all_mouths for n in neighbours(cell) + [cell]), "mage of %s sits on a mouth" % island
    for island, cell in SKELETONS:
        assert land.get(cell) == island, "skeleton of %s is off its island" % island
    assert len(SKELETONS) == 10 and len(MAGES) == len(ISLANDS) == 9
    return land, walked, all_mouths


def ascii_map(land, walked):
    rows = []
    for z in range(8, 43):
        row = ""
        for x in range(-18, 9):
            if (x, z) in walked:
                row += "="
            elif (x, z) in land:
                row += "M" if MAGES.get(land[(x, z)]) == (x, z) else "s" if (land[(x, z)], (x, z)) in SKELETONS else "#"
            elif -6 <= x <= -1 and 10 <= z <= 14:
                row += "A"
            elif (x, z) in EXIT_BRIDGE:
                row += "|"
            else:
                row += "."
        rows.append("%4d %s" % (z, row))
    return "\n".join(rows)


# ---------------------------------------------------------------- floor
def labyrinth_cells(mouths):
    cells = []
    for name in ISLANDS:
        x0, x1, z0, z1 = ISLANDS[name]
        for cx in range(x0, x1 + 1):
            for cz in range(z0, z1 + 1):
                role = ("N" if cz == z0 else "S" if cz == z1 else "") + ("W" if cx == x0 else "E" if cx == x1 else "")
                top, cliff = SIDE_TILES.get(role, (CENTRE, None))
                if (cx, cz) in mouths:
                    top = CENTRE
                cells.append(((cx, -1, cz), top))
                if cliff:
                    cells.append(((cx, -3, cz), cliff))
    return cells


def patch_floor(text, mouths):
    pattern = re.compile(r'(\[node name="FloorGridMap" type="GridMap"[\s\S]*?"cells": PackedInt32Array\()([^)]*)(\))')
    match = pattern.search(text)
    cells = decode([int(v) for v in match.group(2).split(",")])
    existing = {key for key, _ in cells}
    arena_mouth = (ARENA_MOUTH[0], -1, ARENA_MOUTH[1])
    assert arena_mouth in existing, "the arena's south edge is not where this script expects it"
    cells = [(key, CENTRE if key == arena_mouth else tile) for key, tile in cells]
    new = labyrinth_cells(mouths)
    assert not any(key in existing for key, _ in new), "the labyrinth overlaps existing floor"
    return text[:match.start(2)] + encode(cells + new) + text[match.end(2):]


# ---------------------------------------------------------------- nodes
NEW_RESOURCES = [
    ('PackedScene', 'res://src/enemy/enemy_local.tscn', 'uid://cif7328pvepge', 'lb_skeleton'),
]


def walk_platform_names():
    return ["Walk%s%d" % (walk, i + 1) for walk, (_, _, cells) in WALKWAYS.items() for i in range(len(cells))]


def enemy_nodes():
    blocks = [node("LabyrinthMages", "Enemies", "Node3D", props=[("script", 'ExtResource("nm_group")')]),
              node("InstancedEnemies", "Enemies/LabyrinthMages", "Node3D")]
    for index, (island, (cx, cz)) in enumerate(MAGES.items()):
        name = "%sMage" % island
        x, z = cell_world(cx, cz)
        parent = "Enemies/LabyrinthMages/InstancedEnemies"
        blocks.append(node(name, parent, instance="nm_mage", props=[("transform", transform((x, STAND_Y, z)))]))
        blocks.append(node("MageBehavior", "%s/%s" % (parent, name), "Node", props=[
            ("script", 'ExtResource("nm_behavior")'), ("mobility", "1"),
            ("cast_max_distance", "%.1f" % MAGE_CAST_MAX), ("cast_cooldown", "%.1f" % MAGE_COOLDOWNS[index])]))
    blocks += [node("LabyrinthSkeletons", "Enemies", "Node3D", props=[("script", 'ExtResource("nm_group")')]),
               node("InstancedEnemies", "Enemies/LabyrinthSkeletons", "Node3D")]
    for index, (island, (cx, cz)) in enumerate(SKELETONS, 1):
        x, z = cell_world(cx, cz)
        blocks.append(node("%sSkeleton%d" % (island, index), "Enemies/LabyrinthSkeletons/InstancedEnemies",
                           instance="lb_skeleton",
                           props=[("transform", transform((x, STAND_Y, z), 180.0))]))
    return "".join(blocks)


def checkpoint_node():
    x, y, z = START_CHECKPOINT
    groups = '[NodePath("../../Enemies/LabyrinthMages"), NodePath("../../Enemies/LabyrinthSkeletons"), NodePath("../../Enemies/MageTurretGroup")]'
    return "".join([
        node("CheckpointLabyrinth", "CheckpointManager", "Node3D",
             paths=("events_completed", "enemy_groups_reset", "areas_to_reactivate"), props=[
                 ("transform", transform((x, y, z))), ("script", 'ExtResource("14_lj4gk")'),
                 ("events_completed", '[NodePath("../../Level/Events/RaiseWalkways")]'),
                 ("enemy_groups_reset", groups),
                 ("areas_to_reactivate", '[NodePath("../../Level/ArenaArrival")]')]),
        node("PositionDirectionSetter", "CheckpointManager/CheckpointLabyrinth", "Marker3D",
             props=[("transform", transform(arena.SETTER_MARKER))]),
        node("PositionShooter", "CheckpointManager/CheckpointLabyrinth", "Marker3D",
             props=[("transform", transform(arena.SHOOTER_MARKER))]),
    ])


def level_nodes():
    blocks = [node("Labyrinth", "Level/Bridges", "Node")]
    names = []
    for walk, (_, _, cells) in WALKWAYS.items():
        for index, (cx, cz) in enumerate(cells, 1):
            x, z = cell_world(cx, cz)
            name = "Walk%s%d" % (walk, index)
            names.append(name)
            blocks.append(node(name, "Level/Bridges/Labyrinth", instance="nm_bridge",
                               props=[("transform", transform((x, BRIDGE_Y, z)))]))
    exit_names = []
    for index, (cx, cz) in enumerate(EXIT_BRIDGE, 1):
        x, z = cell_world(cx, cz)
        name = "LabyrinthExitPlatform%d" % index
        exit_names.append(name)
        blocks.append(node(name, "Level/Bridges", instance="nm_bridge", props=[("transform", transform((x, BRIDGE_Y, z)))]))
    blocks.append(node("RaiseWalkways", "Level/Events", "Node", paths=("platforms",), props=[
        ("script", 'ExtResource("22_jq7lx")'),
        ("platforms", "[%s]" % ", ".join('NodePath("../../Bridges/Labyrinth/%s")' % n for n in names)),
        ("use_camera_focus", "false"), ("platform_animation_stagger_seconds", "0.05")]))
    blocks.append(node("OpenLabyrinthExit", "Level/Events", "Node", paths=("platforms",), props=[
        ("script", 'ExtResource("22_jq7lx")'),
        ("platforms", "[%s]" % ", ".join('NodePath("../../Bridges/%s")' % n for n in exit_names)),
        ("platform_animation_stagger_seconds", "0.5")]))
    (ax, ay, az), size = ARENA_ARRIVAL
    blocks.append(node("ArenaArrival", "Level", "Area3D", props=[
        ("transform", transform((ax, ay, az))), ("script", 'ExtResource("19_g7rls")')]))
    blocks.append(node("CollisionShape3D", "Level/ArenaArrival", "CollisionShape3D",
                       props=[("shape", 'SubResource("BoxShape3D_arena_arrival")')]))
    return "".join(blocks)


def decoration_nodes(land, walked):
    """Banners and torches on the south cliffs of the bigger islands, reeds and lily pads in open water."""
    blocks = []
    for index, name in enumerate(("Start", "SouthWest", "SouthEast", "Centre")):
        x0, x1, z0, z1 = ISLANDS[name]
        south = (z1 + 1) * CELL
        left, right = x0 * CELL, (x1 + 1) * CELL
        blocks.append(node("Labyrinth%sBanner" % name, "Level/Medieval/Banners", instance="m_banner", props=[
            ("transform", transform(((left + right) / 2, CLIFF_TOP_Y, south + CLIFF_OUT), 0.0, CLIFF_BANNER_SCALE))] +
            list(heraldry_params(index).items())))
        for side, x in (("W", left + 1.5), ("E", right - 1.5)):
            blocks.append(node("Labyrinth%sTorch%s" % (name, side), "Level/Medieval/Torches", instance="m_torch",
                               props=[("transform", transform((x, CLIFF_TORCH_Y, south + CLIFF_OUT)))]))
    # Open water at least two cells from any island or walkway.
    taken = set(land) | set(walked)
    spots = [(-10, 24), (-12, 30), (-1, 35), (8, 33), (-1, 29), (-18, 34), (8, 22), (-9, 42)]
    for index, (cx, cz) in enumerate(spots):
        near = {(cx + dx, cz + dz) for dx in range(-1, 2) for dz in range(-1, 2)}
        assert not near & taken, "decoration at %s is too close to the play space" % ((cx, cz),)
        x, z = cell_world(cx, cz)
        kind, scene = ("Reeds", "m_reeds") if index % 2 == 0 else ("LilyPads", "m_lilies")
        blocks.append(node("Labyrinth%s%d" % (kind, index + 1), "Level/Medieval/Moat", instance=scene,
                           props=[("transform", transform((x, WATER_Y, z), index * 53.0))]))
    return "".join(blocks)


CONNECTIONS = "\n".join([
    '[connection signal="enemies_defeated" from="Enemies/LabyrinthMages" to="CheckpointManager/CheckpointStart" method="_trigger_checkpoint"]',
    '[connection signal="enemies_defeated" from="Enemies/LabyrinthMages" to="Level/Events/OpenLabyrinthExit" method="trigger"]',
] + ['[connection signal="all_players_inside" from="Level/ArenaArrival" to="Level/Events/FocusMages%s" method="trigger"]' % c
     for c in ("NW", "NE", "SW", "SE")]) + "\n"


# ---------------------------------------------------------------- patching
def add_to_array(text, node_name, key, paths):
    """Adds NodePaths to an exported array on a checkpoint node, creating the property if it isn't there."""
    header = re.search(r'\[node name="%s" type="Node3D" parent="CheckpointManager"[^\n]*\]\n' % node_name, text)
    assert header, node_name
    end = text.index("\n\n", header.end())
    block = text[header.start():end]
    items = ", ".join('NodePath("%s")' % p for p in paths)
    existing = re.search(r"^%s = \[(.*)\]$" % key, block, re.M)
    if existing:
        new_block = block.replace(existing.group(0), "%s = [%s, %s]" % (key, existing.group(1), items))
    else:
        new_block = block + "\n%s = [%s]" % (key, items)
    paths_match = re.search(r"node_paths=PackedStringArray\(([^)]*)\)", new_block)
    if paths_match and '"%s"' % key not in paths_match.group(1):
        new_block = new_block.replace(paths_match.group(0), 'node_paths=PackedStringArray(%s, "%s")' % (paths_match.group(1), key))
    return text[:header.start()] + new_block + text[end:]


def patch_checkpoints(text):
    groups = ["../../Enemies/LabyrinthMages", "../../Enemies/LabyrinthSkeletons"]
    events = ["../../Level/Events/RaiseWalkways", "../../Level/Events/OpenLabyrinthExit"]
    for name in ("CheckpointStart", "Checkpoint"):
        text = add_to_array(text, name, "events_completed", events)
        text = add_to_array(text, name, "enemy_groups_defeated", groups)
        text = add_to_array(text, name, "areas_already_activated", ["../../Level/ArenaArrival"])
    return text


def patch_fall_area_and_water(text):
    """Both have to reach the labyrinth, which runs to z = 126."""
    text = replace_once(text, '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 112)',
                        '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 200)')
    text = replace_once(text, "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, 2)",
                        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, 46)")
    # The moat's plane is 200 m square; centred here it covers z -60 to 140.
    return replace_once(text, '[node name="Water" parent="Level" instance=ExtResource("18_iifxy")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -5, 0)',
                        '[node name="Water" parent="Level" instance=ExtResource("18_iifxy")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -10, -5, 40)')


def build():
    land, walked, mouths = validate()
    print(ascii_map(land, walked))
    text = open(LEVEL).read()
    if "MageTurrets" not in text:
        sys.exit("Run add_medieval_02_mage_section.py first.")
    if "LabyrinthMages" in text:
        sys.exit("The labyrinth is already in %s" % LEVEL)
    lines = "".join('[ext_resource type="%s" uid="%s" path="%s" id="%s"]\n' % (k, u, p, i) for k, p, u, i in NEW_RESOURCES)
    text = replace_once(text, "\n[sub_resource type=\"PanoramaSkyMaterial\"", "\n" + lines + "\n[sub_resource type=\"PanoramaSkyMaterial\"")
    size = ARENA_ARRIVAL[1]
    box = '[sub_resource type="BoxShape3D" id="BoxShape3D_arena_arrival"]\nsize = Vector3(%s, %s, %s)\n\n' % size
    text = replace_once(text, '[sub_resource type="BoxShape3D" id="BoxShape3D_h2fuj"]', box + '[sub_resource type="BoxShape3D" id="BoxShape3D_h2fuj"]')
    text = patch_floor(text, mouths)
    text = patch_checkpoints(text)
    text = patch_fall_area_and_water(text)
    marker = '[node name="CheckpointStart" type="Node3D" parent="CheckpointManager"'
    text = replace_once(text, marker, checkpoint_node() + "\n" + marker)
    text = replace_once(text, 'current_checkpoint = NodePath("CheckpointStart")', 'current_checkpoint = NodePath("CheckpointLabyrinth")')
    anchor = '[node name="CheckpointManager" type="Node"'
    text = replace_once(text, anchor, enemy_nodes() + "\n" + anchor)
    anchor = '[node name="Weapon" type="Node" parent="."]'
    text = replace_once(text, anchor, level_nodes() + "\n" + decoration_nodes(land, walked) + "\n" + anchor)
    text = text.rstrip("\n") + "\n" + CONNECTIONS
    open(LEVEL, "w").write(text)
    print("wrote", LEVEL, "- now bake the navmesh and run again with --nav")


# ---------------------------------------------------------------- navmesh
def merge_nav(json_path, min_z=NAV_MIN_Z_WORLD, level=None):
    """Appends a bake of new cells to the level's navmesh. Every baked vertex must lie at z >= min_z, and none of the
    level's may yet (that would mean this bake is already merged)."""
    level = level or LEVEL
    baked = json.load(open(json_path))
    new_vertices = [float(v) for v in re.findall(r"-?[\d.]+(?:e-?\d+)?", baked["vertices"].split("(", 1)[1])]
    new_polygons = [[int(v) for v in p.split(",") if v.strip()] for p in re.findall(r"PackedInt32Array\(([^)]*)\)", baked["polygons"])]
    assert new_polygons and all(z >= min_z for z in new_vertices[2::3]), "the bake has cells outside the new section"
    text = open(level).read()
    match = re.search(r'(\[sub_resource type="NavigationMesh" id="NavigationMesh_dvkoh"\]\nvertices = PackedVector3Array\()([^)]*)(\)\npolygons = \[)(.*)(\]\n)', text)
    assert match, "navmesh not found"
    old_vertices = [float(v) for v in match.group(2).split(",")]
    if any(z >= min_z for z in old_vertices[2::3]):
        sys.exit("This navmesh is already merged.")
    offset = len(old_vertices) // 3
    vertices = match.group(2) + ", " + ", ".join(repr(v) for v in new_vertices)
    polygons = match.group(4) + ", " + ", ".join("PackedInt32Array(%s)" % ", ".join(str(i + offset) for i in p) for p in new_polygons)
    text = text[:match.start(2)] + vertices + match.group(3) + polygons + match.group(5) + text[match.end(5):]
    open(level, "w").write(text)
    print("merged %d vertices and %d polygons into the navmesh" % (len(new_vertices) // 3, len(new_polygons)))


# The labyrinth's navmesh lies between these z (m): north of it is the arena (z < 45), south the horde (z > 146).
LABYRINTH_NAV_Z = (48.0, 130.0)


def replace_nav(json_path, level=None):
    """Swaps the labyrinth's part of the level's navmesh for a new bake of it (vertices inside LABYRINTH_NAV_Z).
    Only the NavigationMesh sub-resource changes, so it is safe on a scene the editor has saved since."""
    level = level or LEVEL
    z_min, z_max = LABYRINTH_NAV_Z
    baked = json.load(open(json_path))
    new_vertices = [float(v) for v in re.findall(r"-?[\d.]+(?:e-?\d+)?", baked["vertices"].split("(", 1)[1])]
    new_polygons = [[int(v) for v in p.split(",") if v.strip()] for p in re.findall(r"PackedInt32Array\(([^)]*)\)", baked["polygons"])]
    assert new_polygons and all(z_min <= z <= z_max for z in new_vertices[2::3]), "the bake has cells outside the labyrinth"
    text = open(level).read()
    match = re.search(r'(\[sub_resource type="NavigationMesh" id="NavigationMesh_dvkoh"\]\nvertices = PackedVector3Array\()([^)]*)(\)\npolygons = \[)(.*)(\]\n)', text)
    assert match, "navmesh not found"
    values = [float(v) for v in match.group(2).split(",")]
    old_vertices = [tuple(values[i:i + 3]) for i in range(0, len(values), 3)]
    old_polygons = [[int(v) for v in p.split(",")] for p in re.findall(r"PackedInt32Array\(([^)]*)\)", match.group(4))]
    inside = [z_min <= v[2] <= z_max for v in old_vertices]
    for polygon in old_polygons:
        assert len({inside[i] for i in polygon}) == 1, "a navmesh polygon straddles the labyrinth's edge"
    kept_polygons = [p for p in old_polygons if not inside[p[0]]]
    used = sorted({i for p in kept_polygons for i in p})
    remap = {old: new for new, old in enumerate(used)}
    vertices = [old_vertices[i] for i in used] + [tuple(new_vertices[i:i + 3]) for i in range(0, len(new_vertices), 3)]
    polygons = [[remap[i] for i in p] for p in kept_polygons] + [[i + len(used) for i in p] for p in new_polygons]
    vertex_text = ", ".join(repr(c) for v in vertices for c in v)
    polygon_text = ", ".join("PackedInt32Array(%s)" % ", ".join(map(str, p)) for p in polygons)
    text = text[:match.start(2)] + vertex_text + match.group(3) + polygon_text + match.group(5) + text[match.end(5):]
    open(level, "w").write(text)
    print("replaced %d labyrinth polygons with %d" % (len(old_polygons) - len(kept_polygons), len(new_polygons)))


if __name__ == "__main__":
    if "--replace-nav" in sys.argv:
        replace_nav(sys.argv[sys.argv.index("--replace-nav") + 1])
        sys.exit(0)
    if "--nav" in sys.argv:
        merge_nav(sys.argv[sys.argv.index("--nav") + 1])
    elif "--map" in sys.argv:
        print(ascii_map(*validate()[:2]))
    else:
        build()
