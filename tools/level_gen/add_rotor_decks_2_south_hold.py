#!/usr/bin/env python3
"""Adds the south deck hold to world_local_rotor_decks_2.tscn.

The carriers reach the small hold deck (floor cells x 10..13, z 3..4, painted by hand, where Rotor10 is) over
BridgePlatform2..4 from the right-hand deck. Once both stand on it (cells x 11..13), those bridges sink behind them,
the camera frames the hold and the gunner deck, and a 40 s survival wave starts: an aviator gunner (6 HP) appears
every 5 s, eight in all, with the HUD countdown, on the gunner deck. That is a new, separate deck of the same size
parallel to the hold, two empty rows further south (cells x 10..13, z 7..8), joined to nothing, so the gunners shoot
across the gap. Once the time is up and every gunner is dead, Checkpoint3 is saved on the hold deck and the framing
clears.

A death during the wave respawns at Checkpoint2 on the start island: the bridges back up (OpenBridge1), the wave
reset, the trigger armed again.

It edits the level in place and refuses to run twice:
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_rotor_decks_2_south_hold.py
The gunner deck needs a navmesh, so re-bake and embed it afterwards:
  tools/level_gen/godot.sh bake res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2_nav.json
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_rotor_decks_2_south_hold.py --embed-nav /tmp/rd2_nav.json
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_rotor_decks_2_south_hold.gd res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2 300
"""
import json
import re
import sys

LEVEL = "src/world/levels/world_local_rotor_decks_2.tscn"
CELL = 2.999
CHECKPOINT_Y = 1.8026

HOLD_X = (10, 13)
HOLD_Z = (3, 4)
# Both carriers inside these cells means both are off the last bridge (cell x 9).
TRIGGER_X = (11, 13)
GUNNER_DECK_X = (10, 13)
GUNNER_DECK_Z = (7, 8)
# Rotors on the gunner deck's west and east sides: (cell x, cell z, side). The north side faces the hold, and the
# south side is where the bridge to the guard island leaves (add_rotor_decks_2_guard_island.py).
GUNNER_DECK_ROTORS = ((10, 7, "W"), (13, 8, "E"))
BRIDGES_BEHIND = ("BridgePlatform2", "BridgePlatform3", "BridgePlatform4")

FIGHT_SECONDS = 40.0
SPAWN_EVERY_SECONDS = 5.0
GUNNER_HP = 6
# Spawn spots on the gunner deck's north half, staggered along it. The gunners can't walk toward the hold (no path),
# so they shoot from where they appear: from the south half they stood 16 m off, at the edge of their range.
SPAWN_SPOTS = ((31.2, 22.2), (34.4, 23.6), (37.6, 22.2), (40.8, 23.6))

# Deck tile items in deck_tiles.tres, and the GridMap layer each edge beam sits on (as in build_rotor_decks_2.py).
DECK, JOISTS = 0, 1
EDGES = (("N", 2, 0, -1, 2), ("S", 3, 0, 1, 3), ("W", 4, -1, 0, 4), ("E", 5, 1, 0, 5))
ROTOR_BASIS = {"E": "1, 0, 0, 0, 1, 0, 0, 0, 1", "W": "-1, 0, 0, 0, 1, 0, 0, 0, -1",
               "N": "0, 0, 1, 0, 1, 0, -1, 0, 0", "S": "0, 0, -1, 0, 1, 0, 1, 0, 0"}


def world(cx, cz):
    return (cx + 0.5) * CELL, (cz + 0.5) * CELL


def tf(x, y, z, basis="1, 0, 0, 0, 1, 0, 0, 0, 1"):
    return f"Transform3D({basis}, {x:g}, {y:g}, {z:g})"


def cells_in(xs, zs):
    return {(x, z) for x in range(xs[0], xs[1] + 1) for z in range(zs[0], zs[1] + 1)}


def centre(xs, zs):
    return (xs[0] + xs[1] + 1) / 2 * CELL, (zs[0] + zs[1] + 1) / 2 * CELL


def replace_once(text, old, new):
    assert text.count(old) == 1, f"expected one match for: {old[:80]}"
    return text.replace(old, new)


def insert_before(text, anchor, block):
    return replace_once(text, anchor, block + anchor)


def bridge_paths(names):
    return ", ".join(f'NodePath("../../Bridges/{name}")' for name in names)


# ---------------------------------------------------------------- the gunner deck
def encode(cells):
    def s32(value):
        return value - (1 << 32) if value >= (1 << 31) else value

    out = []
    for (x, y, z), item in sorted(cells.items()):
        out += [s32((x & 0xFFFF) | ((y & 0xFFFF) << 16)), z & 0xFFFF, item]
    return ", ".join(map(str, out))


def add_grid_cells(text, node_name, cells):
    """Appends cells to a GridMap's data. Existing cells are left as they are."""
    pattern = re.compile(r'(\[node name="%s" type="GridMap"[^\n]*\n(?:[^\[][^\n]*\n|\n)*?"cells": PackedInt32Array\()([^)]*)\)' % node_name)
    match = pattern.search(text)
    assert match, f"no GridMap {node_name}"
    joined = match.group(2) + ", " + encode(cells)
    return text[:match.start(2)] + joined + text[match.end(2):]


def add_gunner_deck(text):
    floor = cells_in(GUNNER_DECK_X, GUNNER_DECK_Z)
    text = add_grid_cells(text, "GridMapDecks", {(x, -1, z): DECK for x, z in floor})
    frame = {(x, -1, z): JOISTS for x, z in floor}
    for _, item, dx, dz, layer in EDGES:
        for x, z in floor:
            if (x + dx, z + dz) not in floor:
                frame[(x, -layer, z)] = item
    text = add_grid_cells(text, "DeckFrame", frame)
    count = len(re.findall(r'^\[node name="Rotor\d+" parent="Level/Rotors"', text, re.M))
    block = ""
    for index, (cx, cz, side) in enumerate(GUNNER_DECK_ROTORS, count + 1):
        wx, wz = world(cx, cz)
        dx, dz = {"E": (1, 0), "W": (-1, 0), "N": (0, -1), "S": (0, 1)}[side]
        block += (
            f'[node name="Rotor{index}" parent="Level/Rotors" instance=ExtResource("rotor")]\n'
            f"transform = {tf(wx + dx * 1.5, -1, wz + dz * 1.5, ROTOR_BASIS[side])}\n\n"
        )
    return insert_before(text, '[node name="DistantDecks"', block)


# ---------------------------------------------------------------- the wave and its wiring
def add_resources(text):
    ext = (
        '[ext_resource type="Script" uid="uid://bvpjcgrdkl4we" path="res://src/enemy/survival_enemy_group.gd" id="survival_group"]\n'
        '[ext_resource type="Script" uid="uid://d2pnle1sbun8v" path="res://src/events/change_enemies_behavior.gd" id="change_behavior"]\n'
        '[ext_resource type="PackedScene" path="res://src/enemy/enemy_aviator_gunner.tscn" id="aviator_gunner"]\n'
    )
    text = insert_before(text, '[ext_resource type="Script" uid="uid://dm0qyuvkt2r20"', ext)
    trigger_w = (TRIGGER_X[1] + 1 - TRIGGER_X[0]) * CELL
    trigger_d = (HOLD_Z[1] + 1 - HOLD_Z[0]) * CELL
    sub = (
        '[sub_resource type="Curve" id="Curve_south_hold"]\n'
        "_limits = [0.0, 10.0, 0.0, 1.0]\n"
        f"_data = [Vector2(0, {SPAWN_EVERY_SECONDS:g}), 0.0, 0.0, 0, 0, Vector2(1, {SPAWN_EVERY_SECONDS:g}), 0.0, 0.0, 0, 0]\n"
        "point_count = 2\n\n"
        '[sub_resource type="BoxShape3D" id="BoxShape3D_south_hold"]\n'
        f"size = Vector3({trigger_w:g}, 3, {trigger_d:g})\n\n"
    )
    return insert_before(text, '[node name="WorldLocal"', sub)


def spawn_spots():
    floor = cells_in(GUNNER_DECK_X, GUNNER_DECK_Z)
    for x, z in SPAWN_SPOTS:
        assert (int(x // CELL), int(z // CELL)) in floor, f"spawn ({x}, {z}) is off the gunner deck"
    return SPAWN_SPOTS


def add_wave(text):
    group = "Enemies/SouthHold"
    block = (
        '[node name="SouthHold" type="Node3D" parent="Enemies"]\n'
        'script = ExtResource("survival_group")\n'
        'enemy_scene = ExtResource("aviator_gunner")\n'
        'spawn_interval_curve = SubResource("Curve_south_hold")\n'
        f"fight_duration = {FIGHT_SECONDS:g}\n"
        f"enemy_max_hp = {GUNNER_HP}\n\n"
        f'[node name="Enemies" type="Node3D" parent="{group}"]\n\n'
        f'[node name="SpawnPoints" type="Node3D" parent="{group}"]\n\n'
    )
    # Facing north, toward the hold.
    for index, (x, z) in enumerate(spawn_spots(), 1):
        block += f'[node name="Spawn{index}" type="Node3D" parent="{group}/SpawnPoints"]\ntransform = {tf(x, 0, z)}\n\n'
    return insert_before(text, '[node name="CheckpointManager"', block)


def add_to_checkpoint2(text):
    old_header = '[node name="Checkpoint2" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_defeated", "areas_already_activated")]'
    new_header = '[node name="Checkpoint2" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_reset", "enemy_groups_defeated", "areas_to_reactivate", "areas_already_activated")]'
    text = replace_once(text, old_header, new_header)
    old = 'enemy_groups_defeated = [NodePath("../../Enemies/EnemyGroup")]\nareas_already_activated'
    new = (
        'enemy_groups_reset = [NodePath("../../Enemies/SouthHold")]\n'
        'enemy_groups_defeated = [NodePath("../../Enemies/EnemyGroup")]\n'
        'areas_to_reactivate = [NodePath("../../Level/Areas/SouthHoldTrigger")]\n'
        "areas_already_activated"
    )
    return replace_once(text, old, new)


def add_checkpoint3(text):
    x, z = centre(HOLD_X, HOLD_Z)
    block = (
        '[node name="Checkpoint3" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_defeated", "areas_already_activated")]\n'
        f"transform = {tf(x, CHECKPOINT_Y, z - 0.8)}\n"
        'script = ExtResource("checkpoint")\n'
        # In play order: the bridges rise, then the ones behind the hold sink again.
        'events_completed = [NodePath("../../Level/Events/OpenBridge1"), NodePath("../../Level/Events/CloseHoldBridges")]\n'
        'enemy_groups_defeated = [NodePath("../../Enemies/EnemyGroup"), NodePath("../../Enemies/SouthHold")]\n'
        'areas_already_activated = [NodePath("../../Level/Areas/FiringLineTrigger"), NodePath("../../Level/Areas/SouthHoldTrigger")]\n\n'
        '[node name="PositionDirectionSetter" type="Marker3D" parent="CheckpointManager/Checkpoint3"]\n'
        f"transform = {tf(0, 0, -0.5083)}\n\n"
        '[node name="PositionShooter" type="Marker3D" parent="CheckpointManager/Checkpoint3"]\n'
        f"transform = {tf(0, 0, 2.1002)}\n\n"
    )
    return insert_before(text, '[node name="Level" type="Node" parent="."]', block)


def frame_corners():
    x0, x1 = HOLD_X[0], HOLD_X[1]
    z_north, z_south = HOLD_Z[0], GUNNER_DECK_Z[1]
    return (("SW", x0, z_south), ("SE", x1, z_south), ("NW", x0, z_north), ("NE", x1, z_north))


def add_events(text):
    block = (
        '[node name="CloseHoldBridges" type="Node" parent="Level/Events" node_paths=PackedStringArray("platforms", "next_event")]\n'
        'script = ExtResource("17_2xwjt")\n'
        f"platforms = [{bridge_paths(BRIDGES_BEHIND)}]\n"
        "platform_animation_stagger_seconds = 0.3\n"
        "use_camera_focus = false\n"
        "event_type = 1\n"
        'next_event = NodePath("../StartSouthHold")\n\n'
        '[node name="StartSouthHold" type="Node" parent="Level/Events" node_paths=PackedStringArray("enemy_group")]\n'
        'script = ExtResource("change_behavior")\n'
        'enemy_group = NodePath("../../../Enemies/SouthHold")\n\n'
    )
    for corner, _, _ in frame_corners():
        block += (
            f'[node name="FocusSouthHold{corner}" type="Node" parent="Level/Events" node_paths=PackedStringArray("focal_point")]\n'
            'script = ExtResource("camera_focus")\n'
            f'focal_point = NodePath("../../FocusPoints/FocusSouthHold{corner}")\n\n'
        )
    block += '[node name="UnfocusSouthHold" type="Node" parent="Level/Events"]\nscript = ExtResource("camera_clear")\n\n'
    return insert_before(text, '[node name="CloudLayers"', block)


def add_focus_points(text):
    block = ""
    for corner, cx, cz in frame_corners():
        x, z = world(cx, cz)
        block += f'[node name="FocusSouthHold{corner}" type="Node3D" parent="Level/FocusPoints"]\ntransform = {tf(x, 0, z)}\n\n'
    return insert_before(text, '[node name="Areas" type="Node" parent="Level"]', block)


def add_trigger(text):
    x, z = centre(TRIGGER_X, HOLD_Z)
    block = (
        '[node name="SouthHoldTrigger" type="Area3D" parent="Level/Areas"]\n'
        f"transform = {tf(x, 0, z)}\n"
        'script = ExtResource("all_players")\n\n'
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="Level/Areas/SouthHoldTrigger"]\n'
        'shape = SubResource("BoxShape3D_south_hold")\n\n'
    )
    return insert_before(text, '[node name="Bridges"', block)


def add_connections(text):
    trigger = "Level/Areas/SouthHoldTrigger"
    lines = [f'[connection signal="all_players_inside" from="{trigger}" to="Level/Events/CloseHoldBridges" method="trigger"]']
    lines += [
        f'[connection signal="all_players_inside" from="{trigger}" to="Level/Events/FocusSouthHold{corner}" method="trigger"]'
        for corner, _, _ in frame_corners()
    ]
    lines += [
        '[connection signal="enemies_defeated" from="Enemies/SouthHold" to="CheckpointManager/Checkpoint3" method="_trigger_checkpoint"]',
        '[connection signal="enemies_defeated" from="Enemies/SouthHold" to="Level/Events/UnfocusSouthHold" method="trigger"]',
    ]
    return text.rstrip("\n") + "\n" + "\n".join(lines) + "\n"


def fix_load_steps(text):
    count = len(re.findall(r"^\[(ext_resource|sub_resource)", text, re.M))
    return re.sub(r"load_steps=\d+", f"load_steps={count + 1}", text, count=1)


def embed_nav(text, nav_path):
    baked = json.load(open(nav_path))
    block = (
        '[sub_resource type="NavigationMesh" id="NavigationMesh_level"]\n'
        f'vertices = {baked["vertices"]}\npolygons = {baked["polygons"]}\n'
    )
    pattern = re.compile(r'\[sub_resource type="NavigationMesh" id="NavigationMesh_level"\]\n(?:[^\[\n][^\n]*\n)*')
    assert len(pattern.findall(text)) == 1, "expected one NavigationMesh_level"
    return pattern.sub(block, text, count=1)


def main(args):
    text = open(LEVEL).read()
    if args[:1] == ["--embed-nav"]:
        open(LEVEL, "w").write(embed_nav(text, args[1]))
        print("embedded navmesh from", args[1])
        return
    if 'name="SouthHold"' in text:
        sys.exit("The south hold is already in the level; nothing to do.")
    steps = (add_gunner_deck, add_resources, add_wave, add_to_checkpoint2, add_checkpoint3, add_events,
             add_focus_points, add_trigger, add_connections, fix_load_steps)
    for step in steps:
        text = step(text)
    open(LEVEL, "w").write(text)
    print("added the south deck hold to", LEVEL)


if __name__ == "__main__":
    main(sys.argv[1:])
