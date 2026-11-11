"""Adds two sections before the skull platform of world_local_02_medieval.tscn: a warm-up and a skeleton horde.

Run add_medieval_02_skull_platform.py first. In play order, the level now starts with:
  1. Warm-up island: the carriers spawn in the middle of a ring of ten harmless skeletons (not offensive, so their
     touch does nothing) and learn to swing the sword. Killing all ten saves CheckpointHorde and raises a bridge north.
  2. Horde island, a bigger one: twenty skeletons wait on its north half. When both carriers step onto the island
     they all charge. Killing them saves CheckpointSkulls and raises a bridge north to the round skull platform.
The skull wave used to start on spawn; now it starts when both carriers step onto the round platform
(SkullArrival), and still on a respawn there.

It edits the level in place, in two steps, because the new islands need a navmesh:
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_medieval_02_warmup_and_horde.py
  FLOOR_GRIDMAP=Level/NavigationRegion3D/FloorGridMap BAKE_CELL_Z_MIN=49 \\
      tools/level_gen/godot.sh bake res://src/world/levels/world_local_02_medieval.tscn /tmp/horde_nav.json
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_medieval_02_warmup_and_horde.py --nav /tmp/horde_nav.json
Each step refuses to run twice. Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_medieval_02_warmup_and_horde.gd res://src/world/levels/world_local_02_medieval.tscn /tmp/horde 300
"""

import math
import re
import sys

import add_medieval_02_mage_section as arena
import add_medieval_02_skull_platform as skulls
from add_medieval_02_labyrinth import add_to_array, merge_nav
from add_medieval_02_mage_section import CENTRE, SIDE_TILES, decode, encode, node, replace_once
from medieval import CLIFF_BANNER_SCALE, CLIFF_OUT, CLIFF_TOP_Y, CLIFF_TORCH_Y, f, heraldry_params, transform

LEVEL = arena.LEVEL
CELL = arena.CELL
STAND_Y = arena.FLOOR_TOP_Y + 0.05
BRIDGE_Y = -3.9927697

# ---------------------------------------------------------------- layout (cells; x east, z south)
# The round skull platform's south edge is at z 140.9, just north of cell row 47.
HORDE = (-9, -2, 49, 54)  # 8 x 6 cells
WARMUP = (-8, -3, 57, 62)  # 6 x 6 cells
HORDE_BRIDGE = [(-5, 47), (-5, 48)]  # to the round platform, on its centre line
WARMUP_BRIDGE = [(-6, 55), (-6, 56)]
HORDE_NORTH_MOUTH = (-5, 49)
HORDE_SOUTH_MOUTH = (-6, 54)
WARMUP_MOUTH = (-6, 57)

WARMUP_RING_RADIUS = 5.0
WARMUP_COUNT = 10
HORDE_COUNT = 20
NAV_MIN_Z = HORDE[2] * CELL - 1.0


def centre_of(rect):
    x0, x1, z0, z1 = rect
    return (x0 + x1 + 1) * 0.5 * CELL, (z0 + z1 + 1) * 0.5 * CELL


def cell_world(cx, cz):
    return (cx + 0.5) * CELL, (cz + 0.5) * CELL


def horde_cells():
    """The north three rows of the horde island, keeping clear of the bridge's landing."""
    x0, x1, z0, _ = HORDE
    keep_clear = {HORDE_NORTH_MOUTH, (-5, 50), (-4, 49), (-6, 49)}
    cells = [(x, z) for z in range(z0, z0 + 3) for x in range(x0, x1 + 1) if (x, z) not in keep_clear]
    assert len(cells) == HORDE_COUNT, len(cells)
    return cells


def warmup_spots():
    cx, cz = centre_of(WARMUP)
    spots = []
    for index in range(WARMUP_COUNT):
        angle = math.radians(index * 360.0 / WARMUP_COUNT)
        x, z = cx + math.sin(angle) * WARMUP_RING_RADIUS, cz + math.cos(angle) * WARMUP_RING_RADIUS
        # Each faces the middle of the ring. Skeletons face their local -z, so yaw = atan2(-dx, -dz).
        yaw = math.degrees(math.atan2(-(cx - x), -(cz - z)))
        spots.append((x, z, yaw))
    return spots


# ---------------------------------------------------------------- floor
def rect_cells(rect, mouths):
    x0, x1, z0, z1 = rect
    cells = []
    for cx in range(x0, x1 + 1):
        for cz in range(z0, z1 + 1):
            role = ("N" if cz == z0 else "S" if cz == z1 else "") + ("W" if cx == x0 else "E" if cx == x1 else "")
            top, cliff = SIDE_TILES.get(role, (CENTRE, None))
            if (cx, cz) in mouths:
                assert role in ("N", "S", "E", "W"), "a mouth must be on a side, not a corner: %s" % ((cx, cz),)
                top = CENTRE
            cells.append(((cx, -1, cz), top))
            if cliff:
                cells.append(((cx, -3, cz), cliff))
    return cells


def patch_floor(text):
    pattern = re.compile(r'(\[node name="FloorGridMap" type="GridMap"[\s\S]*?"cells": PackedInt32Array\()([^)]*)(\))')
    match = pattern.search(text)
    cells = decode([int(v) for v in match.group(2).split(",")])
    existing = {(k[0], k[2]) for k, _ in cells}
    new = rect_cells(HORDE, {HORDE_NORTH_MOUTH, HORDE_SOUTH_MOUTH}) + rect_cells(WARMUP, {WARMUP_MOUTH})
    taken = {(k[0], k[2]) for k, _ in new}
    assert not taken & existing, "the new islands overlap existing floor"
    assert not (set(HORDE_BRIDGE) | set(WARMUP_BRIDGE)) & (taken | existing), "a bridge crosses floor"
    return text[:match.start(2)] + encode(cells + new) + text[match.end(2):]


# ---------------------------------------------------------------- nodes
def enemy_nodes():
    blocks = [node("Warmup", "Enemies", "Node3D", props=[("script", 'ExtResource("nm_group")')]),
              node("InstancedEnemies", "Enemies/Warmup", "Node3D")]
    for index, (x, z, yaw) in enumerate(warmup_spots(), 1):
        blocks.append(node("WarmupSkeleton%d" % index, "Enemies/Warmup/InstancedEnemies", instance="lb_skeleton", props=[
            ("transform", transform((x, STAND_Y, z), yaw)), ("is_offensive", "false")]))
    blocks += [node("Horde", "Enemies", "Node3D", props=[("script", 'ExtResource("nm_group")'), ("spawn_on_trigger", "true")]),
               node("InstancedEnemies", "Enemies/Horde", "Node3D")]
    for index, (cx, cz) in enumerate(horde_cells(), 1):
        x, z = cell_world(cx, cz)
        blocks.append(node("HordeSkeleton%d" % index, "Enemies/Horde/InstancedEnemies", instance="lb_skeleton", props=[
            ("transform", transform((x, STAND_Y, z), 180.0)), ("is_offensive", "false")]))
    return "".join(blocks)


LATER_GROUPS = ["SkullSurvival", "LabyrinthMages", "LabyrinthSkeletons", "MageTurretGroup"]


def paths(prefix, names):
    return "[%s]" % ", ".join('NodePath("%s%s")' % (prefix, n) for n in names)


def checkpoint_nodes():
    wx, wz = centre_of(WARMUP)
    # The horde's checkpoint is on the warm-up island's north side, so after a death the carriers walk over the
    # bridge into HordeArrival again: a trigger they were placed inside might not fire.
    horde_spawn_z = WARMUP[2] * CELL + 4.0
    blocks = []
    for name, (x, z), events, defeated, reset, react in (
            ("CheckpointWarmup", (wx, wz - 0.8), ["RaiseWalkways"], [], ["Warmup", "Horde"] + LATER_GROUPS,
             ["HordeArrival", "SkullArrival", "ArenaArrival"]),
            ("CheckpointHorde", (cell_world(*WARMUP_MOUTH)[0], horde_spawn_z), ["RaiseWalkways", "OpenWarmupBridge"], ["Warmup"],
             ["Horde"] + LATER_GROUPS, ["HordeArrival", "SkullArrival", "ArenaArrival"])):
        props = [("transform", transform((x, 4.0, z))), ("script", 'ExtResource("14_lj4gk")'),
                 ("events_completed", paths("../../Level/Events/", events))]
        keys = ["events_completed"]
        if defeated:
            props.append(("enemy_groups_defeated", paths("../../Enemies/", defeated)))
            keys.append("enemy_groups_defeated")
        props += [("enemy_groups_reset", paths("../../Enemies/", reset)),
                  ("areas_to_reactivate", paths("../../Level/", react))]
        keys += ["enemy_groups_reset", "areas_to_reactivate"]
        blocks += [node(name, "CheckpointManager", "Node3D", paths=keys, props=props),
                   node("PositionDirectionSetter", "CheckpointManager/" + name, "Marker3D", props=[("transform", transform(arena.SETTER_MARKER))]),
                   node("PositionShooter", "CheckpointManager/" + name, "Marker3D", props=[("transform", transform(arena.SHOOTER_MARKER))])]
    return "".join(blocks)


AREAS = {
    # Both carriers on the horde island wakes the horde. The box keeps 1 m inside its edges.
    "HordeArrival": (centre_of(HORDE), ((HORDE[1] - HORDE[0] + 1) * CELL - 2.0, 4.0, (HORDE[3] - HORDE[2] + 1) * CELL - 2.0)),
    # Both carriers on the round platform starts the skull wave.
    "SkullArrival": ((skulls.CENTRE_X, skulls.CENTRE_Z), (6.0, 4.0, 6.0)),
}


def level_nodes():
    blocks = []
    for event, cells in (("OpenWarmupBridge", WARMUP_BRIDGE), ("OpenHordeBridge", HORDE_BRIDGE)):
        names = []
        for index, (cx, cz) in enumerate(cells, 1):
            name = "%sPlatform%d" % (event[4:], index)
            names.append(name)
            x, z = cell_world(cx, cz)
            blocks.append(node(name, "Level/Bridges", instance="nm_bridge", props=[("transform", transform((x, BRIDGE_Y, z)))]))
        blocks.append(node(event, "Level/Events", "Node", paths=("platforms",), props=[
            ("script", 'ExtResource("22_jq7lx")'), ("platforms", paths("../../Bridges/", names)),
            ("platform_animation_stagger_seconds", "0.5")]))
    blocks.append(node("WakeHorde", "Level/Events", "Node", paths=("enemy_group",), props=[
        ("script", 'ExtResource("18_khskr")'), ("enemy_group", 'NodePath("../../../Enemies/Horde")')]))
    for name, ((x, z), _) in AREAS.items():
        blocks.append(node(name, "Level", "Area3D", props=[("transform", transform((x, 0.0, z))), ("script", 'ExtResource("19_g7rls")')]))
        blocks.append(node("CollisionShape3D", "Level/" + name, "CollisionShape3D", props=[("shape", 'SubResource("BoxShape3D_%s")' % name)]))
    return "".join(blocks)


def decoration_nodes():
    """Banners and torches on both islands' south cliffs, clear of the bridge between them."""
    blocks = []
    for island, rect, banners, torches in (
            ("Warmup", WARMUP, [-16.5], [-22.5, -10.5]),
            ("Horde", HORDE, [-22.5, -10.5], [-25.5, -7.5])):
        south = (rect[3] + 1) * CELL + CLIFF_OUT
        for index, x in enumerate(banners):
            blocks.append(node("%sBanner%d" % (island, index + 1), "Level/Medieval/Banners", instance="m_banner", props=[
                ("transform", transform((x, CLIFF_TOP_Y, south), 0.0, CLIFF_BANNER_SCALE))] + list(heraldry_params(index + 1).items())))
        for index, x in enumerate(torches):
            blocks.append(node("%sTorch%d" % (island, index + 1), "Level/Medieval/Torches", instance="m_torch",
                               props=[("transform", transform((x, CLIFF_TORCH_Y, south)))]))
    for index, (x, z) in enumerate(((-33.0, 160.0), (3.0, 172.0), (-30.0, 185.0), (2.0, 150.0))):
        kind, scene = ("Reeds", "m_reeds") if index % 2 == 0 else ("LilyPads", "m_lilies")
        blocks.append(node("Horde%s%d" % (kind, index + 1), "Level/Medieval/Moat", instance=scene,
                           props=[("transform", transform((x, arena.WATER_Y, z), index * 71.0))]))
    return "".join(blocks)


CONNECTIONS = "\n".join([
    '[connection signal="enemies_defeated" from="Enemies/Warmup" to="CheckpointManager/CheckpointHorde" method="_trigger_checkpoint"]',
    '[connection signal="enemies_defeated" from="Enemies/Warmup" to="Level/Events/OpenWarmupBridge" method="trigger"]',
    '[connection signal="all_players_inside" from="Level/HordeArrival" to="Level/Events/WakeHorde" method="trigger"]',
    '[connection signal="enemies_defeated" from="Enemies/Horde" to="CheckpointManager/CheckpointSkulls" method="_trigger_checkpoint"]',
    '[connection signal="enemies_defeated" from="Enemies/Horde" to="Level/Events/OpenHordeBridge" method="trigger"]',
    '[connection signal="all_players_inside" from="Level/SkullArrival" to="Level/Events/StartSkullWave" method="trigger"]',
]) + "\n"


# ---------------------------------------------------------------- patching
def patch_checkpoints(text):
    text = add_to_array(text, "CheckpointSkulls", "events_completed", ["../../Level/Events/OpenWarmupBridge", "../../Level/Events/OpenHordeBridge"])
    text = add_to_array(text, "CheckpointSkulls", "enemy_groups_defeated", ["../../Enemies/Warmup", "../../Enemies/Horde"])
    text = add_to_array(text, "CheckpointSkulls", "areas_already_activated", ["../../Level/SkullArrival"])
    for name in ("CheckpointLabyrinth", "CheckpointStart", "Checkpoint"):
        text = add_to_array(text, name, "events_completed", ["../../Level/Events/OpenWarmupBridge", "../../Level/Events/OpenHordeBridge"])
        text = add_to_array(text, name, "enemy_groups_defeated", ["../../Enemies/Warmup", "../../Enemies/Horde"])
        text = add_to_array(text, name, "areas_already_activated", ["../../Level/SkullArrival"])
    return text


def patch_reach(text):
    """The fall area and the moat's water have to reach the warm-up island, which ends at z = 189."""
    text = replace_once(text, '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 220)',
                        '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 260)')
    text = replace_once(text, "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, 56)",
                        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, 76)")
    # The water's shader works in world space, so stretching its 200 m plane to 300 m keeps the waves the same size.
    return replace_once(text, '[node name="Water" parent="Level" instance=ExtResource("18_iifxy")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -10, -5, 60)',
                        '[node name="Water" parent="Level" instance=ExtResource("18_iifxy")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1.5, -10, -5, 75)')


def build():
    text = open(LEVEL).read()
    if "SkullSurvival" not in text:
        sys.exit("Run add_medieval_02_skull_platform.py first.")
    if "HordeArrival" in text:
        sys.exit("The warm-up and horde islands are already in %s" % LEVEL)
    boxes = "".join('[sub_resource type="BoxShape3D" id="BoxShape3D_%s"]\nsize = Vector3(%s, %s, %s)\n\n' % ((name,) + tuple(f(v) for v in size))
                    for name, (_, size) in AREAS.items())
    text = replace_once(text, '[sub_resource type="BoxShape3D" id="BoxShape3D_h2fuj"]', boxes + '[sub_resource type="BoxShape3D" id="BoxShape3D_h2fuj"]')
    text = patch_floor(text)
    text = patch_checkpoints(text)
    text = patch_reach(text)
    marker = '[node name="CheckpointSkulls" type="Node3D" parent="CheckpointManager"'
    text = replace_once(text, marker, checkpoint_nodes() + "\n" + marker)
    text = replace_once(text, 'current_checkpoint = NodePath("CheckpointSkulls")', 'current_checkpoint = NodePath("CheckpointWarmup")')
    anchor = '[node name="CheckpointManager" type="Node"'
    text = replace_once(text, anchor, enemy_nodes() + "\n" + anchor)
    anchor = '[node name="Weapon" type="Node" parent="."]'
    text = replace_once(text, anchor, level_nodes() + "\n" + decoration_nodes() + "\n" + anchor)
    text = text.rstrip("\n") + "\n" + CONNECTIONS
    open(LEVEL, "w").write(text)
    print("wrote", LEVEL, "- now bake the navmesh and run again with --nav")


if __name__ == "__main__":
    if "--nav" in sys.argv:
        merge_nav(sys.argv[sys.argv.index("--nav") + 1], NAV_MIN_Z)
    else:
        build()
