#!/usr/bin/env python3
"""Boss fight against 4GTN, a robot samurai, on a space station: world_local_katana_robot_boss.tscn.

The carriers bring the pulse rifle across a hard-light bridge onto a duelling deck. The bridge
switches off behind them and 4GTN wakes. Cargo stacks break up its lunges.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import AREAS, EVENTS, FACE_SOUTH, GROUPS, TRIGGER as T, Level, checkpoint, rect, single_bridge, tf, world


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. ----
DOCK = rounded(-4, 4, -3, 4)
ARENA = rounded(-5, 5, -17, -6)
DECKS = [DOCK, ARENA]
FLOOR = set().union(*DECKS)
BRIDGES = {1: single_bridge(-4, -5)}
assert all(cell not in FLOOR for cells in BRIDGES.values() for cell in cells)

# Props stand on a plate and block movement, and the lunge stops at them. (item, orientation)
PROPS = {
    # Dock: parked craft, clear down the middle.
    (-3, 3): ("Lander", 0), (3, 3): ("LandingPadSmall", 0), (-3, -1): ("CargoA", 0), (3, -1): ("CargoB", 10),
    # Arena: four cargo stacks to put between the carriers and a lunge, and lights on the rim.
    (-3, -9): ("CargoA", 0), (3, -9): ("CargoB", 10), (-3, -14): ("CargoB", 16), (3, -14): ("CargoA", 22),
    (-5, -7): ("Lights", 0), (5, -7): ("Lights", 0), (-5, -16): ("Lights", 0), (5, -16): ("Lights", 0),
}

level = Level("src/world/levels/world_local_katana_robot_boss.tscn", palette="space", weapon="pulse_rifle", floor_seed=7, deco_seed=7,
              hint="[color=#ff8888]4GTN[/color]\n\nHold shoot to keep firing. Step out of the red lane\nbefore it lunges, and shoot down its plasma waves !", music="rituale_machina")
level.use_space_station()
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "arena": (33, 3, 6)}
level.extra_ext += [
    ("PackedScene", None, "res://src/enemy/enemy_katana_robot.tscn", "katana_robot"),
    ("Script", "uid://cmsv7oeu5se3x", "res://src/world/ui/show_boss_health_bar.gd", "show_boss_bar"),
    ("Texture2D", None, "res://assets/sprites/ui/icons/katana_robot_boss_icon.png", "boss_icon"),
]
level.add_shell()

# ---- The boss. Stands at the far end of the arena, facing the bridge. ----
level.enemy_group("BossGroup")
boss_x, boss_z = world(0, -13)
level.node("EnemyKatanaRobot", "Enemies/BossGroup/InstancedEnemies", instance="katana_robot", props={
    "transform": tf(boss_x, 0, boss_z, FACE_SOUTH)})

level.checkpoints([checkpoint("Checkpoint", 0, 1, "OpenBridge1", "BossGroup", None, T)],
                  setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_station_terrain(DECKS, PROPS, fall_z=-8)
level.add_planet((-260, -480, -260), 280)
level.node("DistantStations", "Level", "Node")
for name, position, shape, props in (
        ("StationA", (58, -38, -12), rounded(-3, 3, -2, 2), {(0, 0): ("Command", 0), (-2, 0): ("SolarRoof", 0), (2, 0): ("Antenna", 0)}),
        ("StationB", (-62, -44, -70), rounded(-4, 4, -3, 3), {(0, 0): ("LandingPad", 0), (-3, 1): ("Garage", 0), (3, -1): ("Dome", 0)}),
):
    level.add_distant_station(name, position, shape, props)
level.add_asteroids((
    (-40, -26, -8, 5), (42, -30, -40, 7), (-48, -36, -40, 9), (36, -24, -72, 4), (-24, -50, -90, 11), (46, -66, 18, 13),
))

# ---- Events. The bridge starts on and switches off behind the carriers, which wakes the boss. ----
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "WakeBoss")
level.offensive_event("WakeBoss", "BossGroup")
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_bridge_nodes()
level.add_triggers(((T, 0, -8, "arena"),))
wx, wz = world(0, 1)
level.add_weapon("PulseRifle", tf(wx, 0.593, wz))
level.add_audio_and_hint()
level.node("ShowBossHealthBar", ".", "Node", paths=["fight_trigger", "enemy_group"], props={
    "script": 'ExtResource("show_boss_bar")',
    "fight_trigger": f'NodePath("../{AREAS}{T}")',
    "enemy_group": 'NodePath("../Enemies/BossGroup")',
    "boss_icon": 'ExtResource("boss_icon")'})

# ---- Signals. ----
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("enemies_defeated", GROUPS + "BossGroup", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
