#!/usr/bin/env python3
"""Prototype of a lava level: world_local_lava.tscn. Basalt over a molten surface, with erupting vents.
Played with the catapult, which lobs bombs over the vents and pits onto the enemies beyond.
Magma pockets are dormant vents that burst when a bomb or rocket lands near them, and set off their neighbours.
They run in chains under where enemies wait, so one well-placed shot clears a line, and a careless one near the
carriers burns them too.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (AREAS, CELL, EVENTS, GROUPS, TRIGGER as T, Level, checkpoint, rect, tf, triple_bridge, twin_rails, world)


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut, so the rock doesn't read as a box."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. ----
YARD = rounded(-6, 6, -6, 4)
VENT_FIELD = rounded(-5, 5, -24, -9)
CALDERA_PIT = rect(-3, 3, -37, -32)
CALDERA = rounded(-8, 8, -42, -27) - CALDERA_PIT
FORGE_POOLS = rect(-5, -4, -56, -55) | rect(4, 5, -56, -55) | rect(-5, -4, -51, -50) | rect(4, 5, -51, -50)
FORGE = rounded(-8, 8, -60, -45) - FORGE_POOLS
END_PAD = rounded(-4, 4, -70, -63)
FLOOR = YARD | VENT_FIELD | CALDERA | FORGE | END_PAD

BRIDGES = {1: triple_bridge(-7, -8), 2: twin_rails(-25, -26), 3: triple_bridge(-43, -44), 4: triple_bridge(-61, -62)}
MOUTHS = {(x, z) for x in (-1, 0, 1) for z in (-6, -9, -24, -27, -42, -45, -60, -63)}
assert MOUTHS <= FLOOR

# (cx, cz, phase). A vent erupts when its cycle reaches 1.3 s of 4 s, so its phase sets when in the 4 s it fires.
VENTS = (
    # Field. First row: out to the sides, so the first eruption is seen from safety.
    (-3, -12, 0.0), (3, -12, 0.5),
    # A centre vent in the way, to walk around or wait out.
    (0, -15, 0.0), (-4, -15, 0.5), (4, -15, 0.5),
    # Blocks the straight path: wait for a gap, or go around.
    (-1, -18, 0.25), (1, -18, 0.25), (-4, -18, 0.75), (4, -18, 0.75),
    # A wave from the middle outward.
    (0, -21, 0.0), (-3, -21, 0.25), (3, -21, 0.25),
    # Caldera ring, where chasers come through them too.
    (-6, -34, 0.0), (6, -34, 0.5), (-5, -29, 0.25), (5, -29, 0.75), (-6, -40, 0.5), (6, -40, 0.0),
    # Forge, between the mages.
    (0, -48, 0.0), (-7, -53, 0.25), (7, -53, 0.75), (0, -53, 0.5),
)
# Magma pockets, two cells apart so each chains to the next. Enemies may wait on them: they only burn when set off.
POCKETS = (
    # Under the guards at the end of the field, far from the carriers: the lesson. Split around the checkpoint there.
    (-4, -23), (-2, -23), (2, -23), (4, -23),
    # The caldera's far rim, where the chasers wait, and one on each flank they run past.
    (-4, -39), (-2, -39), (0, -39), (2, -39), (4, -39), (-6, -37), (6, -37),
    # The back of the forge, under two mages and beside the chasers, split around the last checkpoint.
    (-6, -58), (-4, -58), (-2, -58), (2, -58), (4, -58), (6, -58),
)
POCKET_RADIUS = 2.4
SPOUTS = ((0, -34.5, 0.0), (-11, -18, 0.3), (11, -13, 0.7), (-12, -50, 0.5), (12, -38, 0.15))
OUTCROPS = ((-11, -2, "Rock_3_A", 0), (11, 1, "Rock_5_A", 10), (-10, -11, "Rock_3_C", 16), (10, -22, "Rock_6_A", 0),
            (-11, -24, "Rock_5_C", 22), (13, -33, "Rock_3_F", 0), (-13, -36, "Rock_3_A", 10), (-13, -46, "Rock_6_A", 16),
            (13, -49, "Rock_5_A", 0), (-8, -66, "Rock_3_C", 0), (9, -68, "Rock_3_F", 22))

level = Level("src/world/levels/world_local_lava.tscn", palette="lava", weapon="catapult", floor_seed=11, deco_seed=11,
              hint="[color=#ff8888]Catapult usage[/color]\n\nFront carrier: walk further ahead to throw further, closer for a short lob.\nBack carrier: press shoot when the ring is on the enemies !\nGlowing circles are about to erupt. They burn enemies too.\nPale pulsing cracks are magma pockets: bomb one and it bursts, setting off its neighbours.",
              music="relentless")  # the catapult's camera marker follows its landing ring, so the default camera fits
level.use_lava_environment()
level.melee_scene = "tiefling"  # tieflings instead of skeletons
level.extra_ext.append(("PackedScene", None, "res://src/enemy/enemy_tiefling.tscn", "tiefling"))
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "field": (33, 3, 6), "caldera": (51, 3, 9), "forge": (51, 3, 9), "end": (27, 3, 9)}
level.add_shell()

# ---- Enemies. ----
GUARDS = ((-3, -24), (0, -24), (3, -24), (-4, -23), (-2, -23), (2, -23), (4, -23))
CHASERS = ((-6, -39), (-3, -39), (0, -39), (3, -39), (6, -39), (-7, -36), (7, -36), (-6, -32), (6, -32), (-2, -40), (2, -40), (-7, -37), (7, -37))
MAGES = ((-3, -49), (3, -49), (0, -55), (-6, -58), (6, -58))
FORGE_CHASERS = ((-1, -58), (1, -58), (0, -57))
level.enemy_group("EnemyGroup")  # idle practice targets, close enough to see from spawn
for i, (cx, cz) in enumerate(((0, 0), (-3, 0), (3, 0), (-5, -1), (-2, -1), (2, -1), (5, -1)), 1):
    level.melee("EnemyGroup", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup2")  # wait past the vents, then charge through the last row of them
for i, (cx, cz) in enumerate(GUARDS, 1):
    level.melee("EnemyGroup2", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup3")  # come around both sides of the pit
for i, (cx, cz) in enumerate(CHASERS, 1):
    level.melee("EnemyGroup3", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup4")
for i, (cx, cz) in enumerate(MAGES, 1):
    level.mage("EnemyGroup4", f"EnemyMage{i}", cx, cz, cast_max=13.0, cooldown=4.0)
for i, (cx, cz) in enumerate(FORGE_CHASERS, 1):
    level.melee("EnemyGroup4", f"EnemyLocal{i}", cx, cz)

# ---- Checkpoints. ----
CHECKPOINTS = [
    checkpoint("Checkpoint", 0, 2),
    checkpoint("Checkpoint2", 0, -4, "OpenBridge1", "EnemyGroup2", "EnemyGroup", T),
    checkpoint("Checkpoint3", 0, -23, "OpenBridge2", "EnemyGroup3", "EnemyGroup2", T + "2", T),
    checkpoint("Checkpoint4", 0, -41, "OpenBridge3", "EnemyGroup4", "EnemyGroup3", T + "3", T + "2"),
    checkpoint("Checkpoint5", 0, -59, "OpenBridge4", None, "EnemyGroup4", None, T + "3"),
]
SETTER, SHOOTER = (0, -2.25), (0, 2.25)  # in line, the front carrier ahead, 4.5 m apart (the catapult takes 4 to 7.5)


def too_close_to_a_vent(wx, wz, margin):
    for cx, cz, _phase in VENTS:
        vx, vz = world(cx, cz)
        if ((vx - wx) ** 2 + (vz - wz) ** 2) ** 0.5 < 1.45 + margin:
            return True
    return False


for _, cx, cz, _arrays in CHECKPOINTS:
    assert all((cx, cz + d) in FLOOR for d in (-1, 0, 1)), (cx, cz)
    wx, wz = world(cx, cz)
    for dx, dz in (SETTER, SHOOTER):
        assert not too_close_to_a_vent(wx + dx, wz + dz, 1.0), ("spawn on a vent", cx, cz)
for cx, cz in MAGES + GUARDS + CHASERS + FORGE_CHASERS:
    assert not too_close_to_a_vent(*world(cx, cz), 1.0), ("waiting enemy on a vent", cx, cz)
assert {(cx, cz) for cx, cz, _phase in VENTS} <= FLOOR - MOUTHS
assert set(POCKETS) <= FLOOR - MOUTHS
for cx, cz in POCKETS:
    assert not too_close_to_a_vent(*world(cx, cz), POCKET_RADIUS), ("pocket overlaps a vent", cx, cz)
    for _, ccx, ccz, _arrays in CHECKPOINTS:
        wx, wz = world(ccx, ccz)
        px, pz = world(cx, cz)
        for dx, dz in (SETTER, SHOOTER):
            assert ((wx + dx - px) ** 2 + (wz + dz - pz) ** 2) ** 0.5 > POCKET_RADIUS + 1.0, ("spawn on a pocket", cx, cz)
assert CELL > 1.45 * 2, "vents in neighbouring cells would overlap"
level.checkpoints(CHECKPOINTS, setter_marker=SETTER, shooter_marker=SHOOTER)

# ---- Terrain and events. ----
level.add_lava_terrain(FLOOR, MOUTHS, fall_z=-40, outcrops=OUTCROPS)
level.add_vents(VENTS)
level.add_magma_pockets(POCKETS, POCKET_RADIUS)
level.add_lava_spouts(SPOUTS)
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
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_end_area(0, -67)
level.add_bridge_nodes()
level.add_triggers(((T, 0, -19, "field"), (T + "2", 0, -29, "caldera"), (T + "3", 0, -47, "forge")))
wx, wz = world(0, 2)
# Turned to throw towards -z, with its back handles (local z = -2.7) over the shooter's marker.
level.add_weapon("Catapult", tf(wx, 1.8726845, wz + SHOOTER[1] - 2.7, "-1, 0, 0, 0, 1, 0, 0, 0, -1"))
level.add_audio_and_hint()

# ---- Signals. ----
# No camera framing: every enemy here can be walked to, so the normal zoom is enough.
PROGRESSION = (("EnemyGroup", 1, "Checkpoint2"), ("EnemyGroup2", 2, "Checkpoint3"),
               ("EnemyGroup3", 3, "Checkpoint4"), ("EnemyGroup4", 4, "Checkpoint5"))
for group, number, cp_name in PROGRESSION:
    level.connect("enemies_defeated", GROUPS + group, "CheckpointManager/" + cp_name, "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + f"OpenBridge{number}")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
for number, name in ((1, T), (2, T + "2"), (3, T + "3")):
    level.connect("all_players_inside", AREAS + name, EVENTS + f"CloseBridge{number}")

level.write(sys.argv[1:])
