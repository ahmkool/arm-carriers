#!/usr/bin/env python3
"""Prototype of a dark dungeon: world_local_dark_dungeon.tscn. Walled rooms, gates, pits and firelight.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (AREAS, EVENTS, GROUPS, TRIGGER as T, Level, checkpoint, rect, tf, world)

# ---- Layout, in grid cells. Forward is -z. Walls are generated around whatever is open. ----
ENTRY = rect(-4, 4, -7, 3)
HALL_PIT = rect(-2, 2, -18, -15)
HALL = rect(-7, 7, -22, -11) - HALL_PIT
CRYPT_PILLARS = {(-3, -31), (3, -31), (-3, -35), (3, -35)}
CRYPT = rect(-6, 6, -38, -26) - CRYPT_PILLARS
END_ROOM = rect(-3, 3, -47, -42)
CORRIDORS = rect(-1, 1, -10, -8) | rect(-1, 1, -25, -23) | rect(-1, 1, -41, -39)
FLOOR = ENTRY | HALL | CRYPT | END_ROOM | CORRIDORS

GATES = {1: [(x, -9) for x in (-1, 0, 1)], 2: [(x, -24) for x in (-1, 0, 1)], 3: [(x, -40) for x in (-1, 0, 1)]}
BRAZIERS = ((-3, -6), (3, -6), (-4, 2), (4, 2),
            (-6, -12), (6, -12), (-6, -21), (6, -21), (-3, -14), (3, -14), (-3, -19), (3, -19),
            (-5, -35), (5, -35), (-6, -30), (6, -30), (1, -32), (-3, -27), (3, -27),
            (-2, -46), (2, -46))

level = Level("src/world/levels/world_local_dark_dungeon.tscn", palette="dungeon", weapon="sword", floor_seed=1, deco_seed=1,
              hint="[color=#ff8888]Sword usage[/color]\n\nUse dash to swing and attack with the sword !")
level.use_dark_environment()
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "hall": (45, 3, 9), "crypt": (39, 3, 9), "end": (21, 3, 9)}
level.add_shell()

# ---- Enemies. ----
level.enemy_group("EnemyGroup")  # idle targets to learn the swing on
for i, (cx, cz) in enumerate(((-3, 0), (3, 0), (-3, -3), (0, -3), (3, -3)), 1):
    level.melee("EnemyGroup", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup2")  # they come around both sides of the pit
for i, (cx, cz) in enumerate(((-6, -19), (-4, -21), (-1, -20), (1, -20), (4, -21), (6, -19), (-5, -16), (5, -16), (-5, -14), (5, -14), (-3, -20), (3, -20)), 1):
    level.melee("EnemyGroup2", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup3")  # stationary mages by the firelight, with a short range
for i, (cx, cz) in enumerate(((-5, -29), (5, -29), (0, -32), (-4, -36), (4, -36)), 1):
    level.mage("EnemyGroup3", f"EnemyMage{i}", cx, cz, cast_max=12.0, cooldown=4.0)
for i, (cx, cz) in enumerate(((-1, -37), (1, -37), (0, -36)), 1):
    level.melee("EnemyGroup3", f"EnemyLocal{i}", cx, cz)

level.checkpoints([
    checkpoint("Checkpoint", 0, 2),
    checkpoint("Checkpoint2", 0, -5, "OpenBridge1", "EnemyGroup2", "EnemyGroup", T),
    checkpoint("Checkpoint3", 0, -20, "OpenBridge2", "EnemyGroup3", "EnemyGroup2", T + "2", T),
    checkpoint("Checkpoint4", 0, -36, "OpenBridge3", None, "EnemyGroup3", None, T + "2"),
], setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and light. ----
level.add_dungeon_terrain(FLOOR, HALL_PIT, CRYPT_PILLARS, fall_z=-30)
level.add_braziers(BRAZIERS)

# ---- Events. A gate reuses the bridge events: "open" sinks it into the floor, "close" raises it. ----
level.set_bridges(GATES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "MakeEnemiesGroup2Offensive")
level.offensive_event("MakeEnemiesGroup2Offensive", "EnemyGroup2")
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "MakeEnemiesGroup3Offensive")
level.offensive_event("MakeEnemiesGroup3Offensive", "EnemyGroup3")
level.bridge_event("OpenBridge3", 3)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_focus({"Hall": (-7, 7, -11, -22), "Crypt": (-6, 6, -26, -38)})
level.add_end_area(0, -45)
level.add_bridge_nodes()
level.add_triggers(((T, 0, -13, "hall"), (T + "2", 0, -28, "crypt")))
wx, wz = world(0, 2)
level.add_weapon("Sword", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
for group, number, cp_name in (("EnemyGroup", 1, "Checkpoint2"), ("EnemyGroup2", 2, "Checkpoint3"), ("EnemyGroup3", 3, "Checkpoint4")):
    level.connect("enemies_defeated", GROUPS + group, "CheckpointManager/" + cp_name, "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + f"OpenBridge{number}")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + "UnfocusCamera")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("all_players_inside", AREAS + T + "2", EVENTS + "CloseBridge2")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + T, EVENTS + f"FocusHall{corner}")
    level.connect("all_players_inside", AREAS + T + "2", EVENTS + f"FocusCrypt{corner}")

level.write(sys.argv[1:])
