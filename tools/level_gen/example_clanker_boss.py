#!/usr/bin/env python3
"""Boss fight against the Clanker in a lava forge: world_local_clanker_boss.tscn.

The carriers bring the catapult across a basalt bridge onto an arena over the lava. The bridge sinks behind them and
the Clanker wakes. It punches up close, smashes the floor at mid range, and lobs slag from its exhausts at carriers who
keep away. The smash sends a shockwave rolling outward that sets off every magma pocket it reaches, so the floor
erupts in a wave. Pockets the carriers set off under the Clanker burn it for a big chunk of health (pockets it sets
off itself spare it). Below half health it overheats: its roar sets off every pocket in the arena.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import AREAS, EVENTS, FACE_SOUTH, GROUPS, TRIGGER as T, Level, checkpoint, rect, tf, triple_bridge, world


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut, so the rock doesn't read as a box."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. ----
PAD = rounded(-4, 4, -4, 4)
FORGE_POOL = rect(-1, 1, -15, -13)  # lava in the middle: the Clanker walks around it, bombs fly over it
ARENA = rounded(-7, 7, -21, -7) - FORGE_POOL
FLOOR = PAD | ARENA
BRIDGES = {1: triple_bridge(-5, -6)}
MOUTHS = {(x, z) for x in (-1, 0, 1) for z in (-4, -7)}
assert MOUTHS <= FLOOR

# Magma pockets in short chains (two cells apart chain). Lure the Clanker onto one, then bomb it.
POCKETS = (
    (-4, -10), (-2, -10), (2, -10), (4, -10),  # near the entrance: the smash's wave reaches these first
    (-5, -15), (-5, -17), (5, -15), (5, -17),  # the flanks around the forge pool
    (-2, -19), (0, -19), (2, -19),  # behind the pool, where the Clanker starts
)
POCKET_RADIUS = 2.4
# (cx, cz, phase). Erupting vents in the corners; they burn the Clanker too.
VENTS = ((-6, -11, 0.0), (6, -11, 0.5), (-6, -19, 0.25), (6, -19, 0.75))
SPOUTS = ((-11, -9, 0.0), (11, -16, 0.4), (-11, -20, 0.7), (0, -24, 0.2))
OUTCROPS = ((-11, -2, "Rock_3_A", 0), (11, 1, "Rock_5_A", 10), (-12, -14, "Rock_6_A", 16), (12, -10, "Rock_3_C", 0),
            (11, -22, "Rock_5_C", 22), (-10, -25, "Rock_3_F", 0))

SETTER, SHOOTER = (0, -2.25), (0, 2.25)  # in line, 4.5 m apart (the catapult takes 4 to 7.5)
BOSS_CELL = (0, -17)

level = Level("src/world/levels/world_local_clanker_boss.tscn", palette="lava", weapon="catapult", floor_seed=5, deco_seed=5,
              hint="[color=#ff9944]The Clanker[/color]\n\nWhen it smashes, a shockwave sets off the pale magma pockets.\nStep off them !\n"
                   "Bomb a pocket while it stands on one: the burst burns it badly.",
              music="rituale_machina")
level.use_lava_environment()
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "arena": (39, 3, 6)}
level.extra_ext += [
    ("PackedScene", None, "res://src/enemy/enemy_clanker.tscn", "clanker"),
    ("Script", "uid://cmsv7oeu5se3x", "res://src/world/ui/show_boss_health_bar.gd", "show_boss_bar"),
    ("Texture2D", None, "res://assets/sprites/ui/icons/clanker_boss_icon.png", "boss_icon"),
]
level.add_shell()

# ---- The boss waits behind the forge pool, facing the bridge. ----
level.enemy_group("BossGroup")
boss_x, boss_z = world(*BOSS_CELL)
level.node("EnemyClanker", "Enemies/BossGroup/InstancedEnemies", instance="clanker", props={
    "transform": tf(boss_x, 0, boss_z, FACE_SOUTH)})

CHECKPOINTS = [checkpoint("Checkpoint", 0, 1, "OpenBridge1", "BossGroup", None, T)]


def distance(a, b):
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5


assert set(POCKETS) <= FLOOR - MOUTHS
assert {(cx, cz) for cx, cz, _phase in VENTS} <= FLOOR - MOUTHS
assert BOSS_CELL in FLOOR
for cx, cz in POCKETS:
    for vx, vz, _phase in VENTS:
        assert distance(world(cx, cz), world(vx, vz)) > 1.45 + POCKET_RADIUS, ("pocket overlaps a vent", cx, cz)
    # The boss mustn't start inside a pocket or a vent's reach.
    assert distance(world(cx, cz), world(*BOSS_CELL)) > POCKET_RADIUS + 0.5, ("boss on a pocket", cx, cz)
for vx, vz, _phase in VENTS:
    assert distance(world(vx, vz), world(*BOSS_CELL)) > 1.45 + 1.0, ("boss on a vent", vx, vz)
level.checkpoints(CHECKPOINTS, setter_marker=SETTER, shooter_marker=SHOOTER)

# ---- Terrain and scenery. ----
level.add_lava_terrain(FLOOR, MOUTHS, fall_z=-8, outcrops=OUTCROPS)
level.add_vents(VENTS)
level.add_magma_pockets(POCKETS, POCKET_RADIUS)
level.add_lava_spouts(SPOUTS)

# ---- Events. The bridge starts up and sinks behind the carriers, which wakes the Clanker. ----
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "WakeBoss")
level.offensive_event("WakeBoss", "BossGroup")
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_bridge_nodes()
level.add_triggers(((T, 0, -9, "arena"),))
wx, wz = world(0, 1)
# Turned to throw towards -z, with its back handles (local z = -2.7) over the shooter's marker.
level.add_weapon("Catapult", tf(wx, 1.8726845, wz + SHOOTER[1] - 2.7, "-1, 0, 0, 0, 1, 0, 0, 0, -1"))
level.add_audio_and_hint()
level.node("ShowBossHealthBar", ".", "Node", paths=["fight_trigger", "enemy_group"], props={
    "script": 'ExtResource("show_boss_bar")',
    "fight_trigger": f'NodePath("../{AREAS}{T}")',
    "enemy_group": 'NodePath("../Enemies/BossGroup")',
    "boss_icon": 'ExtResource("boss_icon")'})

# ---- Signals. No camera framing: the Clanker comes to the carriers. ----
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("enemies_defeated", GROUPS + "BossGroup", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
