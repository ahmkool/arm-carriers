#!/usr/bin/env python3
"""Adds the barge run to world_local_rotor_decks_2.tscn, after the guard island.

Run add_rotor_decks_2_south_hold.py and add_rotor_decks_2_guard_island.py first. This adds:
- A 3 x 4 cell barge (rotor_barge_small.tscn, 9 x 12 m) docked against the guard island's east edge. Killing the
  guard starts BargeRun (a BargeVoyageEvent): once both carriers are aboard, it flies east in three 18 m legs.
- Wave 1, on the first leg: an enemy barge flies in from the north with one gun-shielded aviator and three aviator
  gunners aboard, hovers 8 m north of the carriers' barge and sways 4.5 m left and right every 6 s, so rockets
  (5 m/s) have to lead it. Once the crew is dead it stops and hovers there, empty.
- Wave 2, on the second leg: the same from the south, with two gun-shielded aviators.
- The last leg docks against a new grass island to the east (cells x 36..41, z 11..14, corners cut). Both carriers
  stepping onto it saves Checkpoint5.
The camera frames both barges while each wave is fought, since the enemies can't be walked to.

A death during the run respawns at Checkpoint4 on the gunner deck: the barge back at its dock waiting for the
carriers, both waves back at their hidden parking spots with fresh crews.

It edits the level in place and refuses to run twice:
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/level_gen python3 tools/level_gen/add_rotor_decks_2_barge_run.py
The new island needs a navmesh, so re-bake and embed it afterwards:
  tools/level_gen/godot.sh bake res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2_nav.json
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/add_rotor_decks_2_south_hold.py --embed-nav /tmp/rd2_nav.json
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_rotor_decks_2_barge_run.gd res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2_barge 400
"""
import sys

from add_rotor_decks_2_guard_island import append_raw_cells, tiles
from add_rotor_decks_2_south_hold import (
    CELL,
    CHECKPOINT_Y,
    LEVEL,
    centre,
    fix_load_steps,
    insert_before,
    replace_once,
    tf,
)
from levelgen import _encode_cells, rect

BARGE_Y = -0.9927697  # deck top level with the islands' grass
BARGE_W, BARGE_D = 8.99, 11.99
# The guard island spans cells x 9..14, z 11..14; the barge docks against its east edge, centred on it.
DOCK = (15 * CELL + BARGE_W / 2, 13 * CELL)
LEG = 18.0
# The final island: same shape as the guard island, its west edge where the barge's east edge stops.
FINAL_X = (36, 41)
FINAL_Z = (11, 14)
FINAL_ISLAND = rect(FINAL_X[0], FINAL_X[1], FINAL_Z[0], FINAL_Z[1]) - {
    (FINAL_X[0], FINAL_Z[0]), (FINAL_X[1], FINAL_Z[0]), (FINAL_X[0], FINAL_Z[1]), (FINAL_X[1], FINAL_Z[1])}
FINAL_MOUTHS = {(FINAL_X[0], 12), (FINAL_X[0], 13)}  # flat lips where the barge docks
FINAL_STOP = FINAL_X[0] * CELL - BARGE_W / 2 - DOCK[0]
STOPS = (0.0, 0.0, LEG, 2 * LEG, FINAL_STOP)  # parked = dock, dock, wave 1, wave 2, final dock (x offsets)

GAP = 8.0  # between the carriers' barge and an enemy barge, edge to edge
APPROACH = 25.0  # how far each enemy barge flies in from
SWAY_AMPLITUDE = 4.5
SWAY_PERIOD = 6.0
ENEMY_BARGE_SPEED = 8.0

FACE_NORTH = "1, 0, 0, 0, 1, 0, 0, 0, 1"
FACE_SOUTH = "-1, 0, 0, 0, 1, 0, 0, 0, -1"
# (name, side, crew): side -1 is north of the carriers, +1 south. Crew spots are (scene id, x, z) from the deck's
# centre; the shields stand on the side facing the carriers, the gunners behind.
WAVES = (
    ("BargeWave1", -1, (("gun_shield_aviator", 0.0, 3.5), ("aviator_gunner", -3.0, -2.5), ("aviator_gunner", 0.0, -3.8),
                        ("aviator_gunner", 3.0, -2.5))),
    ("BargeWave2", 1, (("gun_shield_aviator", -2.2, -3.5), ("gun_shield_aviator", 2.2, -3.5))),
)


def wave_fight_centre(index, side):
    x = DOCK[0] + STOPS[index + 2]
    z = DOCK[1] + side * (BARGE_D + GAP)
    return x, z


def add_final_island(text):
    level = tiles()
    text = append_raw_cells(text, "GridMapFloor", _encode_cells(level.build_floor(FINAL_ISLAND, FINAL_MOUTHS)))
    text = append_raw_cells(text, "IslandCliffs", _encode_cells(level._deep_cliffs(FINAL_ISLAND, 2)))
    return append_raw_cells(text, "Decoration", _encode_cells(level.build_decoration(FINAL_ISLAND, 6)))


def add_resources(text):
    ext = (
        '[ext_resource type="PackedScene" path="res://src/world/elements/sky_decks/rotor_barge_small.tscn" id="barge_small"]\n'
        '[ext_resource type="Script" uid="uid://el5p0jngj2vj" path="res://src/events/barge_voyage_event.gd" id="barge_voyage"]\n'
        '[ext_resource type="Script" path="res://src/enemy/barge_crew_group.gd" id="barge_crew"]\n'
    )
    text = insert_before(text, '[ext_resource type="Script" uid="uid://dm0qyuvkt2r20"', ext)
    w = (FINAL_X[1] - FINAL_X[0]) * CELL
    d = (FINAL_Z[1] + 1 - FINAL_Z[0]) * CELL
    sub = f'[sub_resource type="BoxShape3D" id="BoxShape3D_final_island"]\nsize = Vector3({w:g}, 3, {d:g})\n\n'
    return insert_before(text, '[node name="WorldLocal"', sub)


def vec3_array(xs):
    return "PackedVector3Array(" + ", ".join(f"{x:g}, 0, 0" for x in xs) + ")"


def add_barges(text):
    block = (
        '[node name="Barges" type="Node3D" parent="Level"]\n\n'
        '[node name="PlayerBarge" parent="Level/Barges" instance=ExtResource("barge_small")]\n'
        f"transform = {tf(DOCK[0], BARGE_Y, DOCK[1])}\n"
        f"stops = {vec3_array(STOPS)}\n\n"
    )
    for index, (name, side, _) in enumerate(WAVES):
        x, z = wave_fight_centre(index, side)
        block += (
            f'[node name="{name}Barge" parent="Level/Barges" instance=ExtResource("barge_small")]\n'
            f"transform = {tf(x, BARGE_Y, z + side * APPROACH)}\n"
            f"stops = PackedVector3Array(0, 0, 0, 0, 0, {-side * APPROACH:g})\n"
            f"speed = {ENEMY_BARGE_SPEED:g}\n\n"
        )
    return insert_before(text, '[node name="Weapon" type="Node3D" parent="."]', block)


def add_waves(text):
    block = ""
    for index, (name, side, crew) in enumerate(WAVES):
        x, z = wave_fight_centre(index, side)
        parked_z = z + side * APPROACH
        face = FACE_SOUTH if side < 0 else FACE_NORTH
        block += (
            f'[node name="{name}" type="Node3D" parent="Enemies" node_paths=PackedStringArray("barge")]\n'
            'script = ExtResource("barge_crew")\n'
            f'barge = NodePath("../../Level/Barges/{name}Barge")\n'
            f"sway_amplitude = {SWAY_AMPLITUDE:g}\n"
            f"sway_period_seconds = {SWAY_PERIOD:g}\n\n"
            f'[node name="InstancedEnemies" type="Node3D" parent="Enemies/{name}"]\n\n'
        )
        counts = {}
        for scene, dx, dz in crew:
            counts[scene] = counts.get(scene, 0) + 1
            label = "Shield" if scene == "gun_shield_aviator" else "Gunner"
            block += (
                f'[node name="{label}{counts[scene]}" parent="Enemies/{name}/InstancedEnemies" instance=ExtResource("{scene}")]\n'
                f"transform = Transform3D({face}, {x + dx:g}, 0, {parked_z + dz:g})\n"
                "is_offensive = false\n\n"
            )
    return insert_before(text, '[node name="CheckpointManager"', block)


def frame(index, side):
    """Corners spanning both barges and the enemy barge's sway, in world x and z."""
    x, z = wave_fight_centre(index, side)
    half_x = BARGE_W / 2 + SWAY_AMPLITUDE
    far = z + side * BARGE_D / 2
    near = DOCK[1] - side * BARGE_D / 2
    z_north, z_south = (far, near) if side < 0 else (near, far)
    return (("SW", x - half_x, z_south), ("SE", x + half_x, z_south), ("NW", x - half_x, z_north), ("NE", x + half_x, z_north))


def add_events(text):
    names = [name for name, _, _ in WAVES]
    focus_events = [f"Focus{name}{corner}" for index, (name, side, _) in enumerate(WAVES) for corner, _, _ in frame(index, side)]
    legs = [index for index, (name, side, _) in enumerate(WAVES) for _ in frame(index, side)]
    block = (
        '[node name="BargeRun" type="Node" parent="Level/Events" node_paths=PackedStringArray("barge", "waves", "leg_events")]\n'
        'script = ExtResource("barge_voyage")\n'
        'barge = NodePath("../../Barges/PlayerBarge")\n'
        "waves = [" + ", ".join(f'NodePath("../../../Enemies/{n}")' for n in names) + "]\n"
        "leg_events = [" + ", ".join(f'NodePath("../{e}")' for e in focus_events) + "]\n"
        "leg_event_legs = PackedInt32Array(" + ", ".join(map(str, legs)) + ")\n\n"
    )
    for event in focus_events:
        block += (
            f'[node name="{event}" type="Node" parent="Level/Events" node_paths=PackedStringArray("focal_point")]\n'
            'script = ExtResource("camera_focus")\n'
            f'focal_point = NodePath("../../FocusPoints/{event}")\n\n'
        )
    block += '[node name="UnfocusBargeWave" type="Node" parent="Level/Events"]\nscript = ExtResource("camera_clear")\n\n'
    return insert_before(text, '[node name="CloudLayers"', block)


def add_focus_points(text):
    block = ""
    for index, (name, side, _) in enumerate(WAVES):
        for corner, x, z in frame(index, side):
            block += f'[node name="Focus{name}{corner}" type="Node3D" parent="Level/FocusPoints"]\ntransform = {tf(x, 0, z)}\n\n'
    return insert_before(text, '[node name="Areas" type="Node" parent="Level"]', block)


def add_trigger(text):
    # Cells x 37..41: both carriers past the island's west column means both are off the barge.
    x = (FINAL_X[0] + 1 + FINAL_X[1] + 1) / 2 * CELL
    z = (FINAL_Z[0] + FINAL_Z[1] + 1) / 2 * CELL
    block = (
        '[node name="FinalIslandTrigger" type="Area3D" parent="Level/Areas"]\n'
        f"transform = {tf(x, 0, z)}\n"
        'script = ExtResource("all_players")\n\n'
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="Level/Areas/FinalIslandTrigger"]\n'
        'shape = SubResource("BoxShape3D_final_island")\n\n'
    )
    return insert_before(text, '[node name="Bridges"', block)


def update_checkpoint4(text):
    old_header = '[node name="Checkpoint4" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_defeated", "areas_already_activated")]'
    new_header = '[node name="Checkpoint4" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_reset", "enemy_groups_defeated", "areas_already_activated")]'
    text = replace_once(text, old_header, new_header)
    old = 'NodePath("../../Level/Events/OpenIslandBridge")]\nenemy_groups_defeated = [NodePath("../../Enemies/EnemyGroup"), NodePath("../../Enemies/SouthHold"), NodePath("../../Enemies/IslandGuard")]\n'
    new = (
        'NodePath("../../Level/Events/OpenIslandBridge"), NodePath("../../Level/Events/BargeRun")]\n'
        "enemy_groups_reset = [" + ", ".join(f'NodePath("../../Enemies/{name}")' for name, _, _ in WAVES) + "]\n"
        'enemy_groups_defeated = [NodePath("../../Enemies/EnemyGroup"), NodePath("../../Enemies/SouthHold"), NodePath("../../Enemies/IslandGuard")]\n'
    )
    return replace_once(text, old, new)


def add_checkpoint5(text):
    x = (FINAL_X[0] + 3) * CELL
    _, z = centre(FINAL_X, FINAL_Z)
    events = ("OpenBridge1", "CloseHoldBridges", "OpenGunnerDeckBridge", "OpenIslandBridge")
    groups = ("EnemyGroup", "SouthHold", "IslandGuard") + tuple(name for name, _, _ in WAVES)
    areas = ("FiringLineTrigger", "SouthHoldTrigger", "GunnerDeckTrigger", "FinalIslandTrigger")
    block = (
        '[node name="Checkpoint5" type="Node3D" parent="CheckpointManager" node_paths=PackedStringArray("events_completed", "enemy_groups_defeated", "areas_already_activated")]\n'
        f"transform = {tf(x, CHECKPOINT_Y, z - 0.8)}\n"
        'script = ExtResource("checkpoint")\n'
        "events_completed = [" + ", ".join(f'NodePath("../../Level/Events/{e}")' for e in events) + "]\n"
        "enemy_groups_defeated = [" + ", ".join(f'NodePath("../../Enemies/{g}")' for g in groups) + "]\n"
        "areas_already_activated = [" + ", ".join(f'NodePath("../../Level/Areas/{a}")' for a in areas) + "]\n\n"
        '[node name="PositionDirectionSetter" type="Marker3D" parent="CheckpointManager/Checkpoint5"]\n'
        f"transform = {tf(0, 0, -0.5083)}\n\n"
        '[node name="PositionShooter" type="Marker3D" parent="CheckpointManager/Checkpoint5"]\n'
        f"transform = {tf(0, 0, 2.1002)}\n\n"
    )
    return insert_before(text, '[node name="Level" type="Node" parent="."]', block)


def add_connections(text):
    lines = ['[connection signal="enemies_defeated" from="Enemies/IslandGuard" to="Level/Events/BargeRun" method="trigger"]']
    lines += [f'[connection signal="enemies_defeated" from="Enemies/{name}" to="Level/Events/UnfocusBargeWave" method="trigger"]'
              for name, _, _ in WAVES]
    lines.append('[connection signal="all_players_inside" from="Level/Areas/FinalIslandTrigger" to="CheckpointManager/Checkpoint5" method="_trigger_checkpoint"]')
    return text.rstrip("\n") + "\n" + "\n".join(lines) + "\n"


def main():
    text = open(LEVEL).read()
    if 'name="IslandGuard"' not in text:
        sys.exit("Run add_rotor_decks_2_guard_island.py first.")
    if 'name="BargeRun"' in text:
        sys.exit("The barge run is already in the level; nothing to do.")
    assert abs(FINAL_STOP - 3 * LEG) < 0.5, f"the final leg is {FINAL_STOP - 2 * LEG:.2f} m, not about {LEG} m"
    steps = (add_final_island, add_resources, add_barges, add_waves, add_events, add_focus_points, add_trigger,
             update_checkpoint4, add_checkpoint5, add_connections, fix_load_steps)
    for step in steps:
        text = step(text)
    open(LEVEL, "w").write(text)
    print("added the barge run to", LEVEL)


if __name__ == "__main__":
    main()
