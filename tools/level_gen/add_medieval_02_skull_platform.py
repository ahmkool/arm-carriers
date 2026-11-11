"""Adds the skull platform before the island labyrinth of world_local_02_medieval.tscn.

Run add_medieval_02_labyrinth.py (both steps) first. This puts a new first section south of the labyrinth's start
island: a round wooden platform about a sword long across, standing in the moat. The carriers spawn on it, and two
seconds later flying skulls start coming at them over the water from all sides for 60 seconds (a survival wave with
the HUD countdown). Once the time is up and the last skulls are dead, CheckpointLabyrinth is saved and a bridge
rises from the platform to the start island.

It edits the level in place and refuses to run twice:
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_medieval_02_skull_platform.py
It also writes src/world/elements/medieval/round_wooden_platform.tscn, which uses wooden_platform.gdshader.
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_medieval_02_skull_platform.gd res://src/world/levels/world_local_02_medieval.tscn /tmp/skulls 300
"""

import math
import re
import sys

import add_medieval_02_mage_section as arena
from add_medieval_02_labyrinth import add_to_array
from add_medieval_02_mage_section import CENTRE, decode, encode, node, replace_once
from medieval import ART, f, transform, write

LEVEL = arena.LEVEL
CELL = arena.CELL
BRIDGE_Y = -3.9927697

# ---------------------------------------------------------------- layout
# The start island is cells x -6..-3, z 38..41. Its south edge cell (-5, 41) becomes the bridge's mouth; two
# platforms cross the moat south of it and meet the round platform's north edge.
START_MOUTH = (-5, 41)
BRIDGE = [(-5, 42), (-5, 43)]
RADIUS = 4.5  # about the sword's length across; the carriers fit, the blade sticks out over the water
DECK_TOP = -1.0
DECK_THICKNESS = 0.6
CENTRE_X = (START_MOUTH[0] + 0.5) * CELL
CENTRE_Z = (BRIDGE[-1][1] + 1) * CELL + RADIUS - 0.1  # the deck's north edge tucks 0.1 m under the last platform

# The wave: skulls come in from a ring around the platform, a metre above the deck.
SPAWN_RING_RADIUS = 14.0
SPAWN_COUNT = 10
SPAWN_HEIGHT = DECK_TOP + 1.0
FIGHT_SECONDS = 60.0
# Seconds between skulls, from the start of the wave to its end: about 28 skulls in all.
SPAWN_INTERVAL = (3.0, 1.5)
START_DELAY = 2.0

# The start island's banner hung where the bridge now lands: it moves to the island's east half.
START_BANNER_X = -9.0


# ---------------------------------------------------------------- scenes
def write_platform_scene():
    """A round deck of planks on a ring of posts and a thick centre post, all in wooden_platform.gdshader."""
    deck_y = DECK_TOP - DECK_THICKNESS / 2
    post_height = 6.0
    lines = [
        "[gd_scene format=3]",
        "",
        '[ext_resource type="Shader" path="res://src/world/elements/wooden_platform.gdshader" id="1_shader"]',
        "",
        '[sub_resource type="ShaderMaterial" id="ShaderMaterial_wood"]',
        "render_priority = 0",
        'shader = ExtResource("1_shader")',
        "",
        '[sub_resource type="CylinderMesh" id="CylinderMesh_deck"]',
        'material = SubResource("ShaderMaterial_wood")',
        "top_radius = %s" % f(RADIUS),
        "bottom_radius = %s" % f(RADIUS - 0.15),
        "height = %s" % f(DECK_THICKNESS),
        "radial_segments = 32",
        "rings = 1",
        "",
        '[sub_resource type="CylinderMesh" id="CylinderMesh_post"]',
        'material = SubResource("ShaderMaterial_wood")',
        "top_radius = 0.28",
        "bottom_radius = 0.34",
        "height = %s" % f(post_height),
        "radial_segments = 8",
        "rings = 1",
        "",
        '[sub_resource type="CylinderMesh" id="CylinderMesh_core"]',
        'material = SubResource("ShaderMaterial_wood")',
        "top_radius = 1.1",
        "bottom_radius = 1.3",
        "height = %s" % f(post_height),
        "radial_segments = 12",
        "rings = 1",
        "",
        '[sub_resource type="CylinderShape3D" id="CylinderShape3D_deck"]',
        "height = %s" % f(DECK_THICKNESS),
        "radius = %s" % f(RADIUS),
        "",
        '[node name="RoundWoodenPlatform" type="Node3D"]',
        "",
        '[node name="Deck" type="MeshInstance3D" parent="."]',
        "transform = " + transform((0, deck_y, 0)),
        'mesh = SubResource("CylinderMesh_deck")',
        "",
        '[node name="Core" type="MeshInstance3D" parent="."]',
        "transform = " + transform((0, DECK_TOP - DECK_THICKNESS - post_height / 2, 0)),
        'mesh = SubResource("CylinderMesh_core")',
        "",
    ]
    for index in range(8):
        angle = math.radians(index * 45.0 + 22.5)
        x, z = math.sin(angle) * (RADIUS - 0.7), math.cos(angle) * (RADIUS - 0.7)
        lines += ['[node name="Post%d" type="MeshInstance3D" parent="."]' % (index + 1),
                  "transform = " + transform((x, DECK_TOP - DECK_THICKNESS - post_height / 2 + 0.1, z), index * 37.0),
                  'mesh = SubResource("CylinderMesh_post")', ""]
    lines += [
        '[node name="Body" type="StaticBody3D" parent="."]',
        "transform = " + transform((0, deck_y, 0)),
        "collision_layer = 4",
        "collision_mask = 0",
        'metadata/footstep_surface = &"wood"',
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="Body"]',
        'shape = SubResource("CylinderShape3D_deck")',
        "",
    ]
    write(ART + "/round_wooden_platform.tscn", "\n".join(lines))


# ---------------------------------------------------------------- level
NEW_RESOURCES = [
    # The flying skull of world_enemy_test_2, flying at blade height (aim_height 1 m) so the sword can hit it.
    ('PackedScene', 'res://src/enemy/enemy_flying_skull_high.tscn', None, 'sk_skull'),
    ('PackedScene', 'res://%s/round_wooden_platform.tscn' % ART, None, 'sk_platform'),
    ('Script', 'res://src/events/start_enemy_group_event.gd', None, 'sk_start'),
]


def resource_lines():
    out = ""
    for kind, path, uid, ident in NEW_RESOURCES:
        uid_part = ' uid="%s"' % uid if uid else ""
        out += '[ext_resource type="%s"%s path="%s" id="%s"]\n' % (kind, uid_part, path, ident)
    return out


CURVE = """[sub_resource type="Curve" id="Curve_skulls"]
_limits = [0.0, 5.0, 0.0, 1.0]
_data = [Vector2(0, %s), 0.0, 0.0, 0, 0, Vector2(1, %s), 0.0, 0.0, 0, 0]
point_count = 2

""" % (f(SPAWN_INTERVAL[0]), f(SPAWN_INTERVAL[1]))


def enemy_nodes():
    blocks = [node("SkullSurvival", "Enemies", "Node3D", props=[
        ("transform", transform((CENTRE_X, 0, CENTRE_Z))), ("script", 'ExtResource("9_nixuq")'),
        ("enemy_scene", 'ExtResource("sk_skull")'), ("spawn_interval_curve", 'SubResource("Curve_skulls")'),
        ("fight_duration", f(FIGHT_SECONDS))]),
        node("Enemies", "Enemies/SkullSurvival", "Node3D"),
        node("SpawnPoints", "Enemies/SkullSurvival", "Node3D")]
    for index in range(SPAWN_COUNT):
        angle = math.radians(index * 360.0 / SPAWN_COUNT + 18.0)
        x, z = math.sin(angle) * SPAWN_RING_RADIUS, math.cos(angle) * SPAWN_RING_RADIUS
        blocks.append(node("Skull%d" % (index + 1), "Enemies/SkullSurvival/SpawnPoints", "Node3D",
                           props=[("transform", transform((x, SPAWN_HEIGHT, z)))]))
    return "".join(blocks)


def checkpoint_node():
    groups = ", ".join('NodePath("../../Enemies/%s")' % g for g in ("SkullSurvival", "LabyrinthMages", "LabyrinthSkeletons", "MageTurretGroup"))
    return "".join([
        node("CheckpointSkulls", "CheckpointManager", "Node3D",
             paths=("events_completed", "enemy_groups_reset", "areas_to_reactivate"), props=[
                 ("transform", transform((CENTRE_X, 4.0, CENTRE_Z - 0.8))), ("script", 'ExtResource("14_lj4gk")'),
                 ("events_completed", '[NodePath("../../Level/Events/RaiseWalkways"), NodePath("../../Level/Events/StartSkullWave")]'),
                 ("enemy_groups_reset", "[%s]" % groups),
                 ("areas_to_reactivate", '[NodePath("../../Level/ArenaArrival")]')]),
        node("PositionDirectionSetter", "CheckpointManager/CheckpointSkulls", "Marker3D",
             props=[("transform", transform(arena.SETTER_MARKER))]),
        node("PositionShooter", "CheckpointManager/CheckpointSkulls", "Marker3D",
             props=[("transform", transform(arena.SHOOTER_MARKER))]),
    ])


def level_nodes():
    blocks = [node("SkullPlatform", "Level", instance="sk_platform", props=[("transform", transform((CENTRE_X, 0, CENTRE_Z)))])]
    names = []
    for index, (cx, cz) in enumerate(BRIDGE, 1):
        name = "SkullBridgePlatform%d" % index
        names.append(name)
        blocks.append(node(name, "Level/Bridges", instance="nm_bridge",
                           props=[("transform", transform(((cx + 0.5) * CELL, BRIDGE_Y, (cz + 0.5) * CELL)))]))
    blocks.append(node("OpenSkullBridge", "Level/Events", "Node", paths=("platforms",), props=[
        ("script", 'ExtResource("22_jq7lx")'),
        ("platforms", "[%s]" % ", ".join('NodePath("../../Bridges/%s")' % n for n in names)),
        ("platform_animation_stagger_seconds", "0.5")]))
    blocks.append(node("StartSkullWave", "Level/Events", "Node", paths=("enemy_group",), props=[
        ("script", 'ExtResource("sk_start")'), ("enemy_group", 'NodePath("../../../Enemies/SkullSurvival")'),
        ("delay_seconds", f(START_DELAY))]))
    return "".join(blocks)


CONNECTIONS = "\n".join([
    '[connection signal="enemies_defeated" from="Enemies/SkullSurvival" to="CheckpointManager/CheckpointLabyrinth" method="_trigger_checkpoint"]',
    '[connection signal="enemies_defeated" from="Enemies/SkullSurvival" to="Level/Events/OpenSkullBridge" method="trigger"]',
]) + "\n"


def patch_floor(text):
    pattern = re.compile(r'(\[node name="FloorGridMap" type="GridMap"[\s\S]*?"cells": PackedInt32Array\()([^)]*)(\))')
    match = pattern.search(text)
    cells = decode([int(v) for v in match.group(2).split(",")])
    mouth = (START_MOUTH[0], -1, START_MOUTH[1])
    assert any(key == mouth for key, _ in cells), "the start island's south edge is not where this script expects it"
    assert not any((k[0], k[2]) in BRIDGE for k, _ in cells), "the bridge crosses floor"
    cells = [(key, CENTRE if key == mouth else tile) for key, tile in cells]
    return text[:match.start(2)] + encode(cells) + text[match.end(2):]


def patch_checkpoints(text):
    for name in ("CheckpointLabyrinth", "CheckpointStart", "Checkpoint"):
        text = add_to_array(text, name, "events_completed", ["../../Level/Events/OpenSkullBridge"])
        text = add_to_array(text, name, "enemy_groups_defeated", ["../../Enemies/SkullSurvival"])
    return text


def patch_reach(text):
    """The fall area and the moat's water have to reach past the platform and the skulls' spawn ring (z 150)."""
    text = replace_once(text, '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 200)',
                        '[sub_resource type="BoxShape3D" id="BoxShape3D_65eof"]\nsize = Vector3(105, 1, 220)')
    text = replace_once(text, "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, 46)",
                        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -18.650024, -0.69485664, 56)")
    return replace_once(text, '[node name="Water" parent="Level" instance=ExtResource("18_iifxy")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -10, -5, 40)',
                        '[node name="Water" parent="Level" instance=ExtResource("18_iifxy")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -10, -5, 60)')


def move_start_banner(text):
    match = re.search(r'(\[node name="LabyrinthStartBanner"[^\n]*\]\ntransform = Transform3D\((?:[^,]*, ){9})([^,]*)(,)', text)
    assert match, "the start island's banner is not where this script expects it"
    return text[:match.start(2)] + f(START_BANNER_X) + text[match.end(2):]


def main():
    text = open(LEVEL).read()
    if "LabyrinthMages" not in text:
        sys.exit("Run add_medieval_02_labyrinth.py first.")
    if "SkullSurvival" in text:
        sys.exit("The skull platform is already in %s" % LEVEL)
    write_platform_scene()
    text = replace_once(text, "\n[sub_resource type=\"PanoramaSkyMaterial\"", "\n" + resource_lines() + "\n" + CURVE.rstrip("\n") + "\n\n[sub_resource type=\"PanoramaSkyMaterial\"")
    text = patch_floor(text)
    text = patch_checkpoints(text)
    text = patch_reach(text)
    text = move_start_banner(text)
    marker = '[node name="CheckpointLabyrinth" type="Node3D" parent="CheckpointManager"'
    text = replace_once(text, marker, checkpoint_node() + "\n" + marker)
    text = replace_once(text, 'current_checkpoint = NodePath("CheckpointLabyrinth")', 'current_checkpoint = NodePath("CheckpointSkulls")')
    anchor = '[node name="CheckpointManager" type="Node"'
    text = replace_once(text, anchor, enemy_nodes() + "\n" + anchor)
    anchor = '[node name="Weapon" type="Node" parent="."]'
    text = replace_once(text, anchor, level_nodes() + "\n" + anchor)
    text = text.rstrip("\n") + "\n" + CONNECTIONS
    open(LEVEL, "w").write(text)
    print("wrote", LEVEL, "- platform centre (%.2f, %.2f)" % (CENTRE_X, CENTRE_Z))


if __name__ == "__main__":
    main()
