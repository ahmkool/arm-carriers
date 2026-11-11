#!/usr/bin/env python3
"""Adds the guard island to world_local_rotor_decks_2.tscn, after the south deck hold.

Run add_rotor_decks_2_south_hold.py first. This adds:
- Two sky bridge platforms across the gap between the hold deck and the gunner deck (cells (11, 5) and (11, 6)).
  They rise once the gunner wave is cleared.
- A grass island south of the gunner deck (cells x 9..14, z 11..14, corners cut), built with the same tiles, deep
  cliffs and grass as the start island, two empty rows past the gunner deck.
- One gun-shielded aviator on the island's north edge, facing the gunner deck. He waits until both carriers stand
  on the gunner deck; then he wakes, and the camera frames the gunner deck and the island, since he can't be walked
  to. A rocket blown up on his shield does nothing: the carriers have to fly it past him and detonate it beside or
  behind him.
- Two more platforms from the gunner deck to the island (cells (11, 9) and (11, 10)), which rise when he dies.
  His death also saves Checkpoint4 on the island and clears the framing.

A death while he lives respawns at Checkpoint3 on the hold deck: the bridge to the gunner deck up, the guard reset
and asleep, the gunner deck trigger armed again.

It edits the level in place and refuses to run twice:
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/level_gen python3 tools/level_gen/add_rotor_decks_2_guard_island.py
The island needs a navmesh, so re-bake and embed it afterwards:
  tools/level_gen/godot.sh bake res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2_nav.json
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_rotor_decks_2_south_hold.py --embed-nav /tmp/rd2_nav.json
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_rotor_decks_2_guard_island.gd res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2_island 300
"""
import re
import sys

from add_rotor_decks_2_south_hold import (
    CHECKPOINT_Y,
    GUNNER_DECK_X,
    GUNNER_DECK_Z,
    LEVEL,
    add_grid_cells,
    centre,
    fix_load_steps,
    insert_before,
    replace_once,
    tf,
    world,
)
from levelgen import Level, _encode_cells, rect

BRIDGE_Y = -3.9928
GUNNER_DECK_BRIDGE = (("BridgePlatform5", (11, 5)), ("BridgePlatform6", (11, 6)))
ISLAND_BRIDGE = (("BridgePlatform7", (11, 9)), ("BridgePlatform8", (11, 10)))
ISLAND_X = (9, 14)
ISLAND_Z = (11, 14)
ISLAND = rect(ISLAND_X[0], ISLAND_X[1], ISLAND_Z[0], ISLAND_Z[1]) - {
    (ISLAND_X[0], ISLAND_Z[0]), (ISLAND_X[1], ISLAND_Z[0]), (ISLAND_X[0], ISLAND_Z[1]), (ISLAND_X[1], ISLAND_Z[1])}
# Flat lips: where the island bridge lands, and the east edge where the barge docks (add_rotor_decks_2_barge_run.py).
MOUTHS = {(11, 11), (14, 12), (14, 13)}
GRASS_COUNT = 6
# On the north edge, beside the mouth, facing north (Godot's -Z) at the gunner deck: about 8 to 11 m from carriers
# on that deck, inside his 13 m firing range. He can't leave the island, since its navmesh is its own.
GUARD_POSITION = (37.5, 0.0, 34.5)
FRAME = (ISLAND_X[0], ISLAND_X[1], ISLAND_Z[1], GUNNER_DECK_Z[0])  # x0, x1, z_south, z_north in cells


def tiles():
    """The start island's generator settings (build_rotor_decks_2.py), for matching tiles and grass."""
    return Level(LEVEL, palette=1, weapon="bazooka", floor_seed=3, deco_seed=7, music="ticking_labyrinth")


def append_raw_cells(text, node_name, encoded):
    pattern = re.compile(r'(\[node name="%s" type="GridMap"[^\n]*\n(?:[^\[][^\n]*\n|\n)*?"cells": PackedInt32Array\()([^)]*)\)' % node_name)
    match = pattern.search(text)
    assert match, f"no GridMap {node_name}"
    return text[:match.start(2)] + match.group(2) + ", " + encoded + text[match.end(2):]


def add_island(text):
    level = tiles()
    text = append_raw_cells(text, "GridMapFloor", _encode_cells(level.build_floor(ISLAND, MOUTHS)))
    text = append_raw_cells(text, "IslandCliffs", _encode_cells(level._deep_cliffs(ISLAND, 2)))
    return append_raw_cells(text, "Decoration", _encode_cells(level.build_decoration(ISLAND, GRASS_COUNT)))


def add_bridges(text):
    block = ""
    for name, (cx, cz) in GUNNER_DECK_BRIDGE + ISLAND_BRIDGE:
        x, z = world(cx, cz)
        block += f'[node name="{name}" parent="Level/Bridges" instance=ExtResource("bridge")]\ntransform = {tf(x, BRIDGE_Y, z)}\n\n'
    return insert_before(text, '[node name="Weapon" type="Node3D" parent="."]', block)


def add_guard(text):
    ext = '[ext_resource type="PackedScene" path="res://src/enemy/enemy_aviator_gun_shield.tscn" id="gun_shield_aviator"]\n'
    text = insert_before(text, '[ext_resource type="Script" uid="uid://dm0qyuvkt2r20"', ext)
    x, y, z = GUARD_POSITION
    block = (
        '[node name="IslandGuard" type="Node3D" parent="Enemies"]\n'
        'script = ExtResource("normal_group")\n'
        'spawn_on_trigger = true\n\n'
        '[node name="InstancedEnemies" type="Node3D" parent="Enemies/IslandGuard"]\n\n'
        '[node name="EnemyAviatorGunShield" parent="Enemies/IslandGuard/InstancedEnemies" instance=ExtResource("gun_shield_aviator")]\n'
        f"transform = {tf(x, y, z)}\n"
        "is_offensive = false\n\n"
    )
    return insert_before(text, '[node name="CheckpointManager"', block)


def gunner_deck_box():
    w = (GUNNER_DECK_X[1] + 1 - GUNNER_DECK_X[0]) * 2.999
    d = (GUNNER_DECK_Z[1] + 1 - GUNNER_DECK_Z[0]) * 2.999
    sub = f'[sub_resource type="BoxShape3D" id="BoxShape3D_gunner_deck"]\nsize = Vector3({w:g}, 3, {d:g})\n\n'
    return sub


def add_trigger(text):
    text = insert_before(text, '[node name="WorldLocal"', gunner_deck_box())
    x, z = centre(GUNNER_DECK_X, GUNNER_DECK_Z)
    block = (
        '[node name="GunnerDeckTrigger" type="Area3D" parent="Level/Areas"]\n'
        f"transform = {tf(x, 0, z)}\n"
        'script = ExtResource("all_players")\n\n'
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="Level/Areas/GunnerDeckTrigger"]\n'
        'shape = SubResource("BoxShape3D_gunner_deck")\n\n'
    )
    return insert_before(text, '[node name="Bridges"', block)


def frame_corners():
    x0, x1, z_south, z_north = FRAME
    return (("SW", x0, z_south), ("SE", x1, z_south), ("NW", x0, z_north), ("NE", x1, z_north))


def bridge_paths(entries):
    return ", ".join(f'NodePath("../../Bridges/{name}")' for name, _ in entries)


def add_events(text):
    block = (
        '[node name="OpenGunnerDeckBridge" type="Node" parent="Level/Events" node_paths=PackedStringArray("platforms")]\n'
        'script = ExtResource("17_2xwjt")\n'
        f"platforms = [{bridge_paths(GUNNER_DECK_BRIDGE)}]\n"
        "platform_animation_stagger_seconds = 0.5\n\n"
        '[node name="WakeIslandGuard" type="Node" parent="Level/Events" node_paths=PackedStringArray("enemy_group")]\n'
        'script = ExtResource("change_behavior")\n'
        'enemy_group = NodePath("../../../Enemies/IslandGuard")\n\n'
    )
    for corner, _, _ in frame_corners():
        block += (
            f'[node name="FocusIsland{corner}" type="Node" parent="Level/Events" node_paths=PackedStringArray("focal_point")]\n'
            'script = ExtResource("camera_focus")\n'
            f'focal_point = NodePath("../../FocusPoints/FocusIsland{corner}")\n\n'
        )
    block += (
        '[node name="UnfocusIsland" type="Node" parent="Level/Events"]\nscript = ExtResource("camera_clear")\n\n'
        '[node name="OpenIslandBridge" type="Node" parent="Level/Events" node_paths=PackedStringArray("platforms")]\n'
        'script = ExtResource("17_2xwjt")\n'
        f"platforms = [{bridge_paths(ISLAND_BRIDGE)}]\n"
        "platform_animation_stagger_seconds = 0.5\n\n"
    )
    return insert_before(text, '[node name="CloudLayers"', block)


def add_focus_points(text):
    block = ""
    for corner, cx, cz in frame_corners():
        x, z = world(cx, cz)
        block += f'[node name="FocusIsland{corner}" type="Node3D" parent="Level/FocusPoints"]\ntransform = {tf(x, 0, z)}\n\n'
    return insert_before(text, '[node name="Areas" type="Node" parent="Level"]', block)


def update_checkpoint3(text):
    old_header = '[node name="Checkpoint3" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_defeated", "areas_already_activated")]'
    new_header = '[node name="Checkpoint3" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_reset", "enemy_groups_defeated", "areas_to_reactivate", "areas_already_activated")]'
    text = replace_once(text, old_header, new_header)
    old = 'NodePath("../../Level/Events/CloseHoldBridges")]\nenemy_groups_defeated = [NodePath("../../Enemies/EnemyGroup"), NodePath("../../Enemies/SouthHold")]\n'
    new = (
        'NodePath("../../Level/Events/CloseHoldBridges"), NodePath("../../Level/Events/OpenGunnerDeckBridge")]\n'
        'enemy_groups_reset = [NodePath("../../Enemies/IslandGuard")]\n'
        'enemy_groups_defeated = [NodePath("../../Enemies/EnemyGroup"), NodePath("../../Enemies/SouthHold")]\n'
        'areas_to_reactivate = [NodePath("../../Level/Areas/GunnerDeckTrigger")]\n'
    )
    return replace_once(text, old, new)


def add_checkpoint4(text):
    # On the island itself, beside the barge's dock (moved there by hand in the editor, kept here to match).
    x, z = centre(GUNNER_DECK_X, ISLAND_Z)
    events = ("OpenBridge1", "CloseHoldBridges", "OpenGunnerDeckBridge", "OpenIslandBridge")
    groups = ("EnemyGroup", "SouthHold", "IslandGuard")
    areas = ("FiringLineTrigger", "SouthHoldTrigger", "GunnerDeckTrigger")
    block = (
        '[node name="Checkpoint4" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_defeated", "areas_already_activated")]\n'
        f"transform = {tf(x, CHECKPOINT_Y, z - 0.8)}\n"
        'script = ExtResource("checkpoint")\n'
        "events_completed = [" + ", ".join(f'NodePath("../../Level/Events/{e}")' for e in events) + "]\n"
        "enemy_groups_defeated = [" + ", ".join(f'NodePath("../../Enemies/{g}")' for g in groups) + "]\n"
        "areas_already_activated = [" + ", ".join(f'NodePath("../../Level/Areas/{a}")' for a in areas) + "]\n\n"
        '[node name="PositionDirectionSetter" type="Marker3D" parent="CheckpointManager/Checkpoint4"]\n'
        f"transform = {tf(0, 0, -0.5083)}\n\n"
        '[node name="PositionShooter" type="Marker3D" parent="CheckpointManager/Checkpoint4"]\n'
        f"transform = {tf(0, 0, 2.1002)}\n\n"
    )
    return insert_before(text, '[node name="Level" type="Node" parent="."]', block)


def add_connections(text):
    trigger = "Level/Areas/GunnerDeckTrigger"
    lines = ['[connection signal="enemies_defeated" from="Enemies/SouthHold" to="Level/Events/OpenGunnerDeckBridge" method="trigger"]',
             f'[connection signal="all_players_inside" from="{trigger}" to="Level/Events/WakeIslandGuard" method="trigger"]']
    lines += [f'[connection signal="all_players_inside" from="{trigger}" to="Level/Events/FocusIsland{corner}" method="trigger"]'
              for corner, _, _ in frame_corners()]
    for target, method in (("CheckpointManager/Checkpoint4", "_trigger_checkpoint"), ("Level/Events/UnfocusIsland", "trigger"),
                           ("Level/Events/OpenIslandBridge", "trigger")):
        lines.append(f'[connection signal="enemies_defeated" from="Enemies/IslandGuard" to="{target}" method="{method}"]')
    return text.rstrip("\n") + "\n" + "\n".join(lines) + "\n"


def main():
    text = open(LEVEL).read()
    if 'name="SouthHold"' not in text:
        sys.exit("Run add_rotor_decks_2_south_hold.py first.")
    if 'name="IslandGuard"' in text:
        sys.exit("The guard island is already in the level; nothing to do.")
    for name, _ in GUNNER_DECK_BRIDGE + ISLAND_BRIDGE:
        assert f'name="{name}"' not in text, f"{name} is taken"
    steps = (add_island, add_bridges, add_guard, add_trigger, add_events, add_focus_points, update_checkpoint3,
             add_checkpoint4, add_connections, fix_load_steps)
    for step in steps:
        text = step(text)
    open(LEVEL, "w").write(text)
    print("added the guard island to", LEVEL)


if __name__ == "__main__":
    main()
