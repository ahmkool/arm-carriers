#!/usr/bin/env python3
"""Boss fight against the Frost Golem on a frozen shore: world_local_frost_golem_boss.tscn.

The carriers bring the sword across a bridge onto an arena over the icy sea. The bridge sinks behind them and the
golem wakes. It sweeps its axe up close, slams the deck (which freezes the ground around the impact for a while,
see FrostGround), and sends lines of ice spikes at carriers who keep away. Below half health it enrages.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import AREAS, EVENTS, FACE_SOUTH, GROUPS, TRIGGER as T, Level, checkpoint, double_bridge, rect, tf, world


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. ----
SHORE = rounded(-4, 4, -4, 3)
ARENA = rounded(-6, 6, -19, -7)
FLOOR = SHORE | ARENA
BRIDGES = {1: double_bridge(-5, -6)}
MOUTHS = {(x, z) for x in (-1, 0, 1) for z in (-4, -7)}
assert MOUTHS <= FLOOR
# Two patches of ice at the arena's edges; the golem's slams freeze more.
ICE = (rect(-6, -4, -17, -14) | rect(4, 6, -12, -9)) & ARENA
# Pines to put between the carriers and a line of spikes.
PROPS = {(-3, 1): ("PineA", 0), (3, 1): ("PineB", 10), (-3, -10): ("PineB", 0), (3, -16): ("PineA", 16), (-2, -18): ("Boulder", 0)}
ISLES = (
    ("IsleA", (-40, -1.6, -20), rounded(-2, 2, -2, 2), {(0, 0): ("IslePine", 0), (-1, 1): ("IsleRock", 10)}),
    ("IsleB", (44, -1.8, -40), rounded(-3, 2, -2, 3), {(0, 0): ("IslePineB", 0), (1, 1): ("IslePine", 16), (-2, 0): ("IsleBareTree", 0)}),
    ("IsleC", (38, -1.6, 8), rounded(-2, 2, -2, 2), {(0, 0): ("IsleBareTree", 0), (1, -1): ("IsleRock", 0)}),
)

level = Level("src/world/levels/world_local_frost_golem_boss.tscn", palette="snow", weapon="sword", floor_seed=11, deco_seed=11,
              hint="[color=#88ccff]Frost Golem[/color]\n\nDash to strike. Step out of the blue rings, and watch\nyour footing : its slam freezes the ground !",
              music="rising_tension")
level.use_snow()
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "arena": (33, 3, 6)}
level.extra_ext += [
    ("PackedScene", None, "res://src/enemy/enemy_frost_golem.tscn", "frost_golem"),
    ("Script", "uid://cmsv7oeu5se3x", "res://src/world/ui/show_boss_health_bar.gd", "show_boss_bar"),
    ("Texture2D", None, "res://assets/sprites/ui/icons/frost_golem_boss_icon.png", "boss_icon"),
]
level.add_shell()

# ---- The boss waits at the far end of the arena, facing the bridge. ----
level.enemy_group("BossGroup")
boss_x, boss_z = world(0, -15)
level.node("EnemyFrostGolem", "Enemies/BossGroup/InstancedEnemies", instance="frost_golem", props={
    "transform": tf(boss_x, 0, boss_z, FACE_SOUTH)})

level.checkpoints([checkpoint("Checkpoint", 0, 1, "OpenBridge1", "BossGroup", None, T)],
                  setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_snow_terrain(FLOOR, MOUTHS, ICE, PROPS, fall_z=-8, water_z=-8)
level.add_snow_isles(ISLES)

# ---- Events. The bridge starts up and sinks behind the carriers, which wakes the golem. ----
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "WakeBoss")
level.offensive_event("WakeBoss", "BossGroup")
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_bridge_nodes()
level.add_triggers(((T, 0, -9, "arena"),))
wx, wz = world(0, 1)
level.add_weapon("Sword", tf(wx, 0.593, wz))
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
