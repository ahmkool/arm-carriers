#!/usr/bin/env python3
"""The full description of world_local_saw.tscn. Copy this file to start a new level.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (AREAS, EVENTS, GROUPS, TRIGGER as T, Level, checkpoint, rect, tf, triple_bridge, twin_rails, world)

# ---- Layout, in grid cells. Forward is -z. ----
YARD = rect(-6, 6, -6, 4)
ARENA = rect(-7, 7, -20, -9)
FUNNEL = rect(-7, 7, -30, -23) | rect(-2, 2, -33, -31) | rect(-7, 7, -43, -34)
LANE = rect(-5, 5, -62, -46)
FINALE = rect(-8, 8, -79, -65)
for pit_x in ((-5, -4), (4, 5)):
    for pit_z in ((-75, -74), (-70, -69)):
        FINALE -= rect(pit_x[0], pit_x[1], pit_z[0], pit_z[1])
END_PAD = rect(-4, 4, -88, -82)
FLOOR = YARD | ARENA | FUNNEL | LANE | FINALE | END_PAD

BRIDGES = {1: triple_bridge(-7, -8), 2: twin_rails(-21, -22), 3: triple_bridge(-44, -45),
           4: twin_rails(-63, -64), 5: triple_bridge(-80, -81)}
MOUTHS = {(x, z) for x in (-1, 0, 1) for z in (-6, -9, -20, -23, -43, -46, -62, -65, -79, -82)}
assert MOUTHS <= FLOOR

level = Level("src/world/levels/world_local_saw.tscn", palette=7, weapon="saw", floor_seed=5, deco_seed=42,
              hint="[color=#ff8888]Saw usage[/color]\n\nThe saw is always spinning : steer it into enemies together !",
              follow_offset="Vector3(0, 11, 4.714)")  # the saw has no camera-forward marker, so raise the camera
level.curve = (2.5, 1.25)  # seconds between survival spawns, start to end
level.boxes = {"fall": (340, 1, 360), "arena": (45, 3, 9), "funnel": (45, 3, 9), "lane": (33, 3, 9), "finale": (51, 3, 9), "end": (27, 3, 9)}
level.add_shell()

# ---- Enemies. ----
level.enemy_group("EnemyGroup")  # idle practice targets, close enough to see from spawn
for i, (cx, cz) in enumerate(((0, 0), (-3, 0), (3, 0), (-5, -1), (-2, -1), (2, -1), (5, -1)), 1):
    level.melee("EnemyGroup", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup2")  # chasers all around the open arena
for i, (cx, cz) in enumerate(((-6, -18), (-3, -19), (0, -18), (3, -19), (6, -18), (-5, -15), (-2, -16), (2, -16), (5, -15), (-6, -13), (6, -13), (-3, -14), (3, -14), (0, -15)), 1):
    level.melee("EnemyGroup2", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup3")  # a crowd that must squeeze through the funnel's neck
crowd = [(cx, cz) for cz in (-36, -39) for cx in (-5, -3, -1, 1, 3, 5)]
for i, (cx, cz) in enumerate(crowd, 1):
    level.melee("EnemyGroup3", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup4")  # stationary mages down the lane, chasers at the far end
for i, (cx, cz) in enumerate(((-3, -51), (3, -51), (0, -54), (-4, -57), (4, -57), (0, -59)), 1):
    level.mage("EnemyGroup4", f"EnemyMage{i}", cx, cz, cast_max=10.0, cooldown=3.0)
for i, (cx, cz) in enumerate(((-1, -61), (1, -61), (0, -60)), 1):
    level.melee("EnemyGroup4", f"EnemyLocal{i}", cx, cz)
level.survival_group(((-7, -78), (7, -78), (0, -78), (-7, -72), (7, -72)), duration=60)

# ---- Checkpoints. Each entry describes the world after the encounter before it is cleared. ----
CHECKPOINTS = [
    checkpoint("Checkpoint", 0, 2),
    checkpoint("Checkpoint2", 0, -4, "OpenBridge1", "EnemyGroup2", "EnemyGroup", T),
    checkpoint("Checkpoint3", 0, -18, "OpenBridge2", "EnemyGroup3", "EnemyGroup2", T + "2", T),
    checkpoint("Checkpoint4", 0, -41, "OpenBridge3", "EnemyGroup4", "EnemyGroup3", T + "3", T + "2"),
    checkpoint("Checkpoint5", 0, -60, "OpenBridge4", "SurvivalEnemyGroup", "EnemyGroup4", T + "4", T + "3"),
    checkpoint("Checkpoint6", 0, -77, "OpenBridge5", None, "SurvivalEnemyGroup", None, T + "4"),
]
for _, cx, cz, _arrays in CHECKPOINTS:
    assert all((cx + d, cz) in FLOOR for d in (-1, 0, 1)), (cx, cz)
level.checkpoints(CHECKPOINTS, setter_marker=(-3, 0), shooter_marker=(3, 0))  # side by side, saw across the path

# ---- Terrain and events. ----
level.add_terrain(FLOOR, MOUTHS, decoration_count=130, fall_z=-120, water_x=0, water_z=-120)
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "MakeEnemiesGroup2Offensive")
level.offensive_event("MakeEnemiesGroup2Offensive", "EnemyGroup2")
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "MakeEnemiesGroup3Offensive")
level.offensive_event("MakeEnemiesGroup3Offensive", "EnemyGroup3")
level.bridge_event("OpenBridge3", 3)
level.bridge_event("CloseBridge3", 3, True, "MakeEnemiesGroup4Offensive")
level.offensive_event("MakeEnemiesGroup4Offensive", "EnemyGroup4")
level.bridge_event("OpenBridge4", 4)
level.bridge_event("CloseBridge4", 4, True, "MakeSurvivalGroupOffensive")
level.offensive_event("MakeSurvivalGroupOffensive", "SurvivalEnemyGroup")
level.bridge_event("OpenBridge5", 5)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_focus({"Arena": (-7, 7, -9, -20), "Funnel": (-7, 7, -23, -38), "Finale": (-8, 8, -65, -79)})
level.add_end_area(0, -85)
level.add_bridge_nodes()
level.add_triggers(((T, 0, -11, "arena"), (T + "2", 0, -25, "funnel"), (T + "3", 0, -48, "lane"), (T + "4", 0, -67, "finale")))
wx, wz = world(0, 2)
level.add_weapon("Saw", tf(wx, 1.8726845, wz, "-4.371139e-08, 0, 1, 0, 1, 0, -1, 0, -4.371139e-08"))
level.add_audio_and_hint()

# ---- Signals. ----
PROGRESSION = (("EnemyGroup", 1, "Checkpoint2", False), ("EnemyGroup2", 2, "Checkpoint3", True), ("EnemyGroup3", 3, "Checkpoint4", True),
               ("EnemyGroup4", 4, "Checkpoint5", False), ("SurvivalEnemyGroup", 5, "Checkpoint6", True))
for group, number, cp_name, unfocus in PROGRESSION:
    level.connect("enemies_defeated", GROUPS + group, "CheckpointManager/" + cp_name, "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + f"OpenBridge{number}")
    if unfocus:
        level.connect("enemies_defeated", GROUPS + group, EVENTS + "UnfocusCamera")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
for number, name in ((1, T), (2, T + "2"), (3, T + "3"), (4, T + "4")):
    level.connect("all_players_inside", AREAS + name, EVENTS + f"CloseBridge{number}")
for label, name in (("Arena", T), ("Funnel", T + "2"), ("Finale", T + "4")):
    for corner in ("SW", "SE", "NW", "NE"):
        level.connect("all_players_inside", AREAS + name, EVENTS + f"Focus{label}{corner}")

level.write(sys.argv[1:])
