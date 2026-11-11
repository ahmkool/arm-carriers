"""Adds the mage-turret arena before the courtyard of world_local_02_medieval.tscn.

The level used to start in the courtyard and end after the survival hold. This script puts a new first section
south of the courtyard: a 6 x 5 cell island with nine stationary mages on stone turrets standing in the moat,
three west, three north and three east of it. The sword just reaches them from the island's edge. Clearing them
saves Checkpoint (the courtyard) and raises a four-platform bridge from the island's north edge to the courtyard.

It edits the level in place, so run it once. It refuses to run again (it looks for Level/MageTurrets) and refuses
if the courtyard has been changed in a way it does not expect. Do not re-run build_medieval_02.py with --force
afterwards: that rebuilds the level from world_local_02.tscn and drops this section.

Run from the project root:
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_medieval_02_mage_section.py
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_medieval_02_mage_section.gd res://src/world/levels/world_local_02_medieval.tscn /tmp/mage_section
"""

import re
import sys

from medieval import (CLIFF_BANNER_SCALE, CLIFF_OUT, CLIFF_TOP_Y, CLIFF_TORCH_Y, ART, heraldry_params, transform, write)

LEVEL = "src/world/levels/world_local_02_medieval.tscn"
CELL = 2.999
WATER_Y = -5.0
FLOOR_TOP_Y = -1.0

# ---------------------------------------------------------------- layout (cells; z grows south, towards the camera)
# The courtyard's south edge is cell row z = 5. Four platforms cross the moat (rows 6 to 9) to the arena's north row.
ARENA_X = (-6, -1)
ARENA_Z = (10, 14)
BRIDGE_X = -2
BRIDGE_Z = (6, 7, 8, 9)
COURTYARD_MOUTH = (BRIDGE_X, 5)
ARENA_MOUTH = (BRIDGE_X, ARENA_Z[0])

# How far past the arena's edge the turrets stand (m). Measured: a carried sword's hit box spans 2.2 to 9.3 m ahead
# of the front carrier (carriers 2.6 m apart), 2.4 m wide, and only hurts what it sweeps into: the carriers dash
# along the island's edge, since a dash toward the moat would drop them in. So the carriers point the blade at a
# mage and swing it sideways across. A front carrier 1 m inside the edge has a mage this far out about 8.8 m
# ahead, at the blade's far end: reachable from within 1 to 2 m of the edge and no further back.
TURRET_GAP = 7.8
TURRET_SPACING = 4.5
# The turret's top is this high above the floor top. Mages stand on it, and the blade is about shoulder height.
TURRET_TOP_ABOVE_FLOOR = 0.2
TURRET_TOP_IN_SCENE = 0.85  # y of the top, relative to the origin of mage_turret.tscn
STAND_HEIGHT = FLOOR_TOP_Y + TURRET_TOP_ABOVE_FLOOR
TURRET_ORIGIN_Y = STAND_HEIGHT - TURRET_TOP_IN_SCENE

# Per side, the three mages' cast cooldowns (s). Staggered, so the volleys do not land together.
COOLDOWNS = {"West": (7.0, 6.0, 8.0), "North": (6.0, 8.0, 7.0), "East": (8.0, 7.0, 6.0)}
CAST_MAX_DISTANCE = 14.0

START_CHECKPOINT = (-9.0, 4.0, 40.0)  # arena, south of the middle; the carriers' markers sit on its z axis
SETTER_MARKER = (0.0, 0.0, -0.5082588)
SHOOTER_MARKER = (0.0, 0.0, 2.1002235)

# Camera: far corners of the turrets, so the whole arena and every turret stay in view while the mages live.
FOCUS_MARGIN = 3.0


def cell_world(cx, cz):
    return (cx + 0.5) * CELL, (cz + 0.5) * CELL


def arena_edges():
    west = ARENA_X[0] * CELL
    east = (ARENA_X[1] + 1) * CELL
    north = ARENA_Z[0] * CELL
    south = (ARENA_Z[1] + 1) * CELL
    return west, east, north, south


def turret_positions():
    """{side: [(x, z), ...]}"""
    west, east, north, south = arena_edges()
    middle_z = (north + south) / 2
    bridge_x = cell_world(BRIDGE_X, 0)[0]
    rows = [middle_z - TURRET_SPACING, middle_z, middle_z + TURRET_SPACING]
    return {
        "West": [(west - TURRET_GAP, z) for z in rows],
        "North": [(bridge_x - TURRET_SPACING * step, north - TURRET_GAP) for step in (1, 2, 3)],
        "East": [(east + TURRET_GAP, z) for z in rows],
    }


# ---------------------------------------------------------------- floor
def decode(values):
    cells = []
    for index in range(0, len(values), 3):
        packed, z, item = values[index:index + 3]
        x = packed & 0xFFFF
        y = (packed >> 16) & 0xFFFF
        cells.append(((sign16(x), sign16(y), sign16(z & 0xFFFF)), (item & 0xFFFF, item >> 16)))
    return cells


def sign16(v):
    return v - 65536 if v >= 32768 else v


def encode(cells):
    out = []
    for (x, y, z), (item, rotation) in cells:
        packed = (x & 0xFFFF) | ((y & 0xFFFF) << 16)
        out += [packed - (1 << 32) if packed >= (1 << 31) else packed, z & 0xFFFF, item | (rotation << 16)]
    return ", ".join(map(str, out))


# Tiles of the courtyard's own edges (castle_tiles.tres keeps the pink palette's item ids): (top, cliff).
SIDE_TILES = {
    "N": ((43, 16), (57, 10)), "S": ((43, 22), (57, 0)), "E": ((43, 0), (57, 16)), "W": ((43, 10), (57, 22)),
    "NE": ((44, 10), (37, 10)), "NW": ((44, 22), (37, 22)), "SE": ((44, 16), (37, 16)), "SW": ((44, 0), (37, 0)),
}
CENTRE = (62, 0)


def arena_cells():
    cells = []
    for cx in range(ARENA_X[0], ARENA_X[1] + 1):
        for cz in range(ARENA_Z[0], ARENA_Z[1] + 1):
            role = ("N" if cz == ARENA_Z[0] else "S" if cz == ARENA_Z[1] else "") + \
                   ("W" if cx == ARENA_X[0] else "E" if cx == ARENA_X[1] else "")
            top, cliff = SIDE_TILES.get(role, (CENTRE, None))
            if (cx, cz) == ARENA_MOUTH:
                top = CENTRE
            cells.append(((cx, -1, cz), top))
            if cliff:
                cells.append(((cx, -3, cz), cliff))
    return cells


def patch_floor(text):
    pattern = re.compile(r'(\[node name="FloorGridMap" type="GridMap"[\s\S]*?"cells": PackedInt32Array\()([^)]*)(\))')
    match = pattern.search(text)
    assert match, "FloorGridMap not found"
    cells = decode([int(v) for v in match.group(2).split(",")])
    existing = {key for key, _ in cells}
    mouth_key = (COURTYARD_MOUTH[0], -1, COURTYARD_MOUTH[1])
    assert mouth_key in existing, "the courtyard's south edge is not where this script expects it"
    cells = [(key, CENTRE if key == mouth_key else tile) for key, tile in cells]
    new = arena_cells()
    assert not any(key in existing for key, _ in new), "the arena overlaps existing floor"
    return text[:match.start(2)] + encode(cells + new) + text[match.end(2):]


# ---------------------------------------------------------------- scenes
def write_post_scene():
    """The turret prop with a column of collision under it: the mage stands on it. Mages are not meant to be walked to."""
    text = "\n".join([
        "[gd_scene format=3]",
        "",
        '[ext_resource type="PackedScene" path="res://%s/mage_turret.tscn" id="1_turret"]' % ART,
        "",
        '[sub_resource type="CylinderShape3D" id="CylinderShape3D_post"]',
        "height = 7.8",
        "radius = 0.9",
        "",
        '[node name="MageTurretPost" instance=ExtResource("1_turret")]',
        "",
        '[node name="Body" type="StaticBody3D" parent="."]',
        "transform = " + transform((0, TURRET_TOP_IN_SCENE - 3.9, 0)),
        "collision_layer = 4",
        "collision_mask = 0",
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="Body"]',
        'shape = SubResource("CylinderShape3D_post")',
        "",
    ])
    write(ART + "/mage_turret_post.tscn", text)


NEW_RESOURCES = [
    ('Script', 'res://src/enemy/normal_enemy_group.gd', 'uid://bk8xqm3nw2h4r', 'nm_group'),
    ('PackedScene', 'res://src/enemy/enemy_mage_no_behavior.tscn', 'uid://cj1jiphwktvpn', 'nm_mage'),
    ('Script', 'res://src/enemy/behavior/mage_behavior.gd', 'uid://s3p4luca33c7', 'nm_behavior'),
    ('Script', 'res://src/events/camera_add_focal_point_event.gd', 'uid://b330nc18vwhrr', 'nm_focus'),
    ('Script', 'res://src/events/camera_clear_focal_points_event.gd', 'uid://caypfr8giu78a', 'nm_clear'),
    ('PackedScene', 'res://%s/castle_bridge_platform.tscn' % ART, None, 'nm_bridge'),
    ('PackedScene', 'res://%s/mage_turret_post.tscn' % ART, None, 'nm_post'),
]


def resource_lines():
    lines = []
    for kind, path, uid, ident in NEW_RESOURCES:
        uid_part = ' uid="%s"' % uid if uid else ""
        lines.append('[ext_resource type="%s"%s path="%s" id="%s"]' % (kind, uid_part, path, ident))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- nodes
def node(name, parent, type_=None, instance=None, props=(), paths=()):
    head = '[node name="%s"' % name
    if type_:
        head += ' type="%s"' % type_
    if parent:
        head += ' parent="%s"' % parent
    if paths:
        head += ' node_paths=PackedStringArray(%s)' % ", ".join('"%s"' % p for p in paths)
    if instance:
        head += ' instance=ExtResource("%s")' % instance
    lines = [head + "]"] + ["%s = %s" % pair for pair in props]
    return "\n".join(lines) + "\n"


def focus_points():
    west, east, north, south = arena_edges()
    spots = turret_positions()
    min_x = min(x for group in spots.values() for x, _ in group) - FOCUS_MARGIN
    max_x = max(x for group in spots.values() for x, _ in group) + FOCUS_MARGIN
    min_z = min(z for group in spots.values() for _, z in group) - FOCUS_MARGIN
    max_z = south + FOCUS_MARGIN
    return {"NW": (min_x, min_z), "NE": (max_x, min_z), "SW": (min_x, max_z), "SE": (max_x, max_z)}


def enemy_nodes():
    blocks = [node("MageTurretGroup", "Enemies", "Node3D", props=[("script", 'ExtResource("nm_group")')]),
              node("InstancedEnemies", "Enemies/MageTurretGroup", "Node3D")]
    parent = "Enemies/MageTurretGroup/InstancedEnemies"
    for side, spots in turret_positions().items():
        for index, (x, z) in enumerate(spots, 1):
            name = "%sMage%d" % (side, index)
            blocks.append(node(name, parent, instance="nm_mage",
                               props=[("transform", transform((x, STAND_HEIGHT + 0.05, z)))]))
            blocks.append(node("MageBehavior", "%s/%s" % (parent, name), "Node", props=[
                ("script", 'ExtResource("nm_behavior")'), ("mobility", "1"),
                ("cast_max_distance", "%.1f" % CAST_MAX_DISTANCE), ("cast_cooldown", "%.1f" % COOLDOWNS[side][index - 1])]))
    return "".join(blocks)


def checkpoint_node():
    west, east, north, south = arena_edges()
    x, y, z = START_CHECKPOINT
    focus = ", ".join('NodePath("../../Level/Events/FocusMages%s")' % corner for corner in focus_points())
    return "".join([
        node("CheckpointStart", "CheckpointManager", "Node3D", paths=("events_completed", "enemy_groups_reset"), props=[
            ("transform", transform((x, y, z))), ("script", 'ExtResource("14_lj4gk")'),
            ("events_completed", "[%s]" % focus),
            ("enemy_groups_reset", '[NodePath("../../Enemies/MageTurretGroup")]')]),
        node("PositionDirectionSetter", "CheckpointManager/CheckpointStart", "Marker3D",
             props=[("transform", transform(SETTER_MARKER))]),
        node("PositionShooter", "CheckpointManager/CheckpointStart", "Marker3D",
             props=[("transform", transform(SHOOTER_MARKER))]),
    ])


def level_nodes():
    blocks = []
    # Turrets with collision, one group so the mage scene is easy to find.
    blocks.append(node("MageTurrets", "Level", "Node3D"))
    for side, spots in turret_positions().items():
        for index, (x, z) in enumerate(spots, 1):
            blocks.append(node("%sTurret%d" % (side, index), "Level/MageTurrets", instance="nm_post",
                               props=[("transform", transform((x, TURRET_ORIGIN_Y, z)))]))
    # Bridge across the moat.
    bridge_x = cell_world(BRIDGE_X, 0)[0]
    names = []
    for index, cz in enumerate(BRIDGE_Z, 1):
        name = "MageBridgePlatform%d" % index
        names.append(name)
        blocks.append(node(name, "Level/Bridges", instance="nm_bridge",
                           props=[("transform", transform((bridge_x, -3.9927697, cell_world(0, cz)[1])))]))
    blocks.append(node("OpenMageBridge", "Level/Events", "Node", paths=("platforms",), props=[
        ("script", 'ExtResource("22_jq7lx")'),
        ("platforms", "[%s]" % ", ".join('NodePath("../../Bridges/%s")' % n for n in names)),
        ("platform_animation_stagger_seconds", "0.5")]))
    # Camera framing while the mages live.
    blocks.append(node("FocusPoints", "Level", "Node3D"))
    for corner, (x, z) in focus_points().items():
        blocks.append(node("FocusMages" + corner, "Level/FocusPoints", "Node3D", props=[("transform", transform((x, 0, z)))]))
        blocks.append(node("FocusMages" + corner, "Level/Events", "Node", paths=("focal_point",), props=[
            ("script", 'ExtResource("nm_focus")'),
            ("focal_point", 'NodePath("../../FocusPoints/FocusMages%s")' % corner)]))
    blocks.append(node("UnfocusMages", "Level/Events", "Node", props=[("script", 'ExtResource("nm_clear")')]))
    return "".join(blocks)


def decoration_nodes():
    """Banners and torches on the arena's south cliff, two towers beside it, reeds and lily pads."""
    west, east, north, south = arena_edges()
    blocks = []
    for index, x in enumerate((west + 4.5, east - 4.5)):
        blocks.append(node("MageBanner%d" % (index + 1), "Level/Medieval/Banners", instance="m_banner", props=[
            ("transform", transform((x, CLIFF_TOP_Y, south + CLIFF_OUT), 0.0, CLIFF_BANNER_SCALE))] +
            list(heraldry_params(index + 2).items())))
    for index, x in enumerate((west + 1.5, west + 7.5, east - 7.5, east - 1.5)):
        blocks.append(node("MageTorch%d" % (index + 1), "Level/Medieval/Torches", instance="m_torch",
                           props=[("transform", transform((x, CLIFF_TORCH_Y, south + CLIFF_OUT)))]))
    for index, (x, z) in enumerate(((west - 20.0, 37.5), (east + 16.0, 37.5))):
        blocks.append(node("MageTower%d" % (index + 1), "Level/Medieval/Towers", instance="m_tower",
                           props=[("transform", transform((x, WATER_Y, z), 40.0 + index * 70.0))]))
    for index, (x, z) in enumerate(((west - 9.0, south + 4.0), (east + 8.0, south + 3.0), (west - 7.0, 25.0))):
        blocks.append(node("MageReeds%d" % (index + 1), "Level/Medieval/Moat", instance="m_reeds",
                           props=[("transform", transform((x, WATER_Y, z), index * 47.0 + 20.0))]))
    for index, (x, z) in enumerate(((west - 12.0, 26.0), (east + 9.0, 40.0), (-3.0, south + 6.0))):
        blocks.append(node("MageLilyPads%d" % (index + 1), "Level/Medieval/Moat", instance="m_lilies",
                           props=[("transform", transform((x, WATER_Y, z), index * 61.0 + 10.0))]))
    blocks.append(node("MageRowboat", "Level/Medieval/Moat", instance="m_boat",
                       props=[("transform", transform((east + 10.0, WATER_Y, 27.0), 75.0))]))
    return "".join(blocks)


CONNECTIONS = "\n".join([
    '[connection signal="enemies_defeated" from="Enemies/MageTurretGroup" to="Level/Events/UnfocusMages" method="trigger"]',
    '[connection signal="enemies_defeated" from="Enemies/MageTurretGroup" to="CheckpointManager/Checkpoint" method="_trigger_checkpoint"]',
    '[connection signal="enemies_defeated" from="Enemies/MageTurretGroup" to="Level/Events/OpenMageBridge" method="trigger"]',
]) + "\n"


# ---------------------------------------------------------------- patching
def replace_once(text, old, new):
    assert text.count(old) == 1, "expected exactly one: %r" % old[:80]
    return text.replace(old, new)


def patch_courtyard_checkpoint(text):
    """After the mages, the courtyard checkpoint remembers the bridge as open and the mages as dead."""
    old = ('[node name="Checkpoint" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("enemy_groups_reset", "areas_to_reactivate")]')
    new = ('[node name="Checkpoint" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray('
           '"events_completed", "enemy_groups_defeated", "enemy_groups_reset", "areas_to_reactivate")]')
    text = replace_once(text, old, new)
    old = 'enemy_groups_reset = [NodePath("../../Enemies/SurvivalEnemyGroup")]'
    new = ('events_completed = [NodePath("../../Level/Events/OpenMageBridge")]\n'
           'enemy_groups_defeated = [NodePath("../../Enemies/MageTurretGroup")]\n' + old)
    return replace_once(text, old, new)


def patch_fall_area(text):
    """The fall area has to reach the new island: it used to end at z = 40."""
    text = replace_once(text, '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 94)',
                        '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 112)')
    return replace_once(text, "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, -7.3463745)",
                        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, 2)")


def main():
    text = open(LEVEL).read()
    if "MageTurrets" in text:
        sys.exit("The mage section is already in %s" % LEVEL)
    write_post_scene()
    # Resources go after the last ext_resource that is not a medieval prop, before the first sub_resource.
    text = replace_once(text, "\n[sub_resource type=\"PanoramaSkyMaterial\"", "\n" + resource_lines() + "\n[sub_resource type=\"PanoramaSkyMaterial\"")
    text = patch_floor(text)
    text = patch_courtyard_checkpoint(text)
    text = patch_fall_area(text)
    # The start checkpoint goes first among the checkpoints, so it has the lowest progress order.
    marker = '[node name="Checkpoint" type="Node3D" parent="CheckpointManager"'
    text = replace_once(text, marker, checkpoint_node() + "\n" + marker)
    text = replace_once(text, 'current_checkpoint = NodePath("Checkpoint")', 'current_checkpoint = NodePath("CheckpointStart")')
    # Enemies after the survival group's last node, so the mage group is the second child of Enemies.
    anchor = '[node name="CheckpointManager" type="Node"'
    text = replace_once(text, anchor, enemy_nodes() + "\n" + anchor)
    # Level nodes and decoration go just before the Weapon node, after Bridges/Events exist.
    anchor = '[node name="Weapon" type="Node" parent="."]'
    text = replace_once(text, anchor, level_nodes() + "\n" + decoration_nodes() + "\n" + anchor)
    text = text.rstrip("\n") + "\n" + CONNECTIONS
    open(LEVEL, "w").write(text)
    print("wrote", LEVEL)


if __name__ == "__main__":
    main()
