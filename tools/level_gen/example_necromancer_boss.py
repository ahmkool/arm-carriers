#!/usr/bin/env python3
"""Boss fight against the necromancer in a dark dungeon: world_local_necromancer_boss.tscn.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (AREAS, EVENTS, GROUPS, TRIGGER as T, Level, checkpoint, rect, tf, world)

# ---- Layout, in grid cells. Forward is -z. Walls are generated around whatever is open. ----
ANTECHAMBER = rect(-4, 4, -5, 3)
CORRIDOR = rect(-1, 1, -9, -6)
PITS = rect(-4, -3, -17, -14) | rect(3, 4, -17, -14)
PILLARS = {(-2, -12), (2, -12), (-2, -19), (2, -19)}
ARENA = rect(-5, 5, -20, -10) - PITS - PILLARS
FLOOR = ANTECHAMBER | CORRIDOR | ARENA

GATES = {1: [(x, -8) for x in (-1, 0, 1)]}
BRAZIERS = ((-3, -4), (3, -4), (-4, 2), (4, 2),
            (-5, -11), (5, -11), (-5, -19), (5, -19), (-5, -13), (5, -13),
            (-1, -13), (1, -13), (-1, -18), (1, -18))

level = Level("src/world/levels/world_local_necromancer_boss.tscn", palette="dungeon", weapon="sword", floor_seed=1, deco_seed=1,
              hint="[color=#ff8888]The Necromancer[/color]\n\nDash to swing. Chase the necromancer down, and keep moving when the floor glows !", music="dark_fairies")
level.use_dark_environment()
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "arena": (33, 3, 6)}
level.extra_ext += [
    ("PackedScene", None, "res://src/enemy/enemy_necromancer.tscn", "necromancer"),
    ("Script", "uid://cmsv7oeu5se3x", "res://src/world/ui/show_boss_health_bar.gd", "show_boss_bar"),
    ("Texture2D", None, "res://assets/sprites/ui/icons/necromancer_boss_icon.png", "boss_icon"),
]
level.extra_ext += [
    ("PackedScene", None, "res://src/enemy/boss/necromancer/soul_bolt.tscn", "soul_bolt"),
    ("PackedScene", None, "res://src/enemy/boss/necromancer/grave_eruption.tscn", "grave"),
]
level.add_shell()
level.nodes[0] += '\nvfx_warmup_scenes = Array[PackedScene]([ExtResource("soul_bolt"), ExtResource("grave")])'

# ---- The boss. Stands at the far end, facing the gate. ----
level.enemy_group("NecromancerGroup")
boss_x, boss_z = world(0, -17)
level.node("EnemyNecromancer", "Enemies/NecromancerGroup/InstancedEnemies", instance="necromancer", props={
    "transform": tf(boss_x, 0, boss_z)})

level.checkpoints([checkpoint("Checkpoint", 0, 0, "OpenBridge1", "NecromancerGroup", None, T)],
                  setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and light. ----
level.add_dungeon_terrain(FLOOR, PITS, PILLARS, fall_z=-12)
level.add_braziers(BRAZIERS)

# ---- Events. The gate starts open and shuts behind the carriers, which wakes the boss. ----
level.set_bridges(GATES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "WakeNecromancer")
level.offensive_event("WakeNecromancer", "NecromancerGroup")
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_focus({"Arena": (-5, 5, -10, -20)})
level.add_bridge_nodes()
level.add_triggers(((T, 0, -11, "arena"),))
wx, wz = world(0, 0)
level.add_weapon("Sword", tf(wx, 0.593, wz))
level.add_audio_and_hint()
level.node("ShowBossHealthBar", ".", "Node", paths=["fight_trigger", "enemy_group"], props={
    "script": 'ExtResource("show_boss_bar")',
    "fight_trigger": f'NodePath("../{AREAS}{T}")',
    "enemy_group": 'NodePath("../Enemies/NecromancerGroup")',
    "boss_icon": 'ExtResource("boss_icon")'})

# ---- Signals. ----
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + T, EVENTS + f"FocusArena{corner}")
level.connect("enemies_defeated", GROUPS + "NecromancerGroup", EVENTS + "UnfocusCamera")
level.connect("enemies_defeated", GROUPS + "NecromancerGroup", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
