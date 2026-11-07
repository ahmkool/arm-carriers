#!/usr/bin/env python3
"""Prototype of a space level: world_local_space_station.tscn. An orbital station above a gas giant,
held by robots. Decks of metal plating, hard-light bridges across open space, and KayKit Space Base props
that block movement.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import AREAS, EVENTS, GROUPS, TRIGGER as T, Level, checkpoint, rect, single_bridge, tf, world


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. ----
DOCK = rounded(-5, 5, -6, 6)
YARD = rounded(-6, 6, -22, -9)
CAUSEWAY = rect(-2, 2, -38, -25)
PERCH_W, PERCH_E = rounded(-9, -4, -36, -28), rounded(4, 9, -36, -28)  # one cell of open space from the causeway
REACTOR_CORE = rect(-1, 1, -50, -46)  # a hole down to the planet
RING = rounded(-7, 7, -55, -41) - REACTOR_CORE
ESCAPE_PAD = rounded(-4, 4, -66, -58)
DECKS = [DOCK, YARD, CAUSEWAY, PERCH_W, PERCH_E, RING, ESCAPE_PAD]
FLOOR = set().union(*DECKS)

BRIDGES = {1: single_bridge(-7, -8), 2: single_bridge(-23, -24), 3: single_bridge(-39, -40), 4: single_bridge(-56, -57)}
assert all(cell not in FLOOR for cells in BRIDGES.values() for cell in cells)

# Props stand on a plate and block movement. (item, GridMap orientation: 0, 10, 16 or 22.)
PROPS = {
    # Dock: a landing pad and parked craft along the sides, clear down the middle.
    (-4, 4): ("Dropship", 16), (-4, 1): ("LandingPadSmall", 0), (4, 4): ("Lander", 0), (4, 1): ("CargoDepot", 22),
    (-4, -3): ("CargoA", 0), (4, -3): ("CargoB", 10), (-2, 5): ("Lights", 0), (2, 5): ("Lights", 0),
    # Yard: cargo stacks the robots have to come around.
    (-3, -12): ("CargoA", 0), (3, -12): ("CargoB", 0), (0, -15): ("CargoDepot", 0), (-4, -16): ("CargoB", 10),
    (4, -16): ("CargoA", 16), (-2, -19): ("CargoA", 22), (2, -19): ("CargoB", 0),
    (-6, -12): ("BaseModuleA", 0), (6, -12): ("BaseModuleC", 10), (-6, -19): ("WaterStorage", 0), (6, -19): ("Garage", 16),
    # Perches: sensor gear behind the gunners.
    (-8, -30): ("Antenna", 0), (-8, -34): ("StructureTall", 0), (-7, -32): ("SolarRoof", 0),
    (8, -30): ("StructureTall", 0), (8, -34): ("Antenna", 10), (7, -32): ("Dome", 0),
    # Reactor ring: pylons at the corners and modules on the outer edge.
    (-6, -42): ("StructureTall", 0), (6, -42): ("StructureTall", 0), (-6, -54): ("StructureTall", 0), (6, -54): ("StructureTall", 0),
    (-7, -48): ("EcoModule", 0), (7, -48): ("Command", 22), (-4, -44): ("Lights", 0), (4, -52): ("Lights", 0),
    # Escape pad: the way out.
    (0, -64): ("Dropship", 0), (-3, -65): ("CargoA", 0), (3, -65): ("CargoB", 0), (-3, -59): ("Lights", 0), (3, -59): ("Lights", 0),
}

level = Level("src/world/levels/world_local_space_station.tscn", palette="space", weapon="pulse_rifle", floor_seed=5, deco_seed=5, music="cyber_noir")
level.use_space_station()
level.curve = (3.0, 1.6)  # survival: one robot every 3 s at the start, every 1.6 s by the end
level.boxes = {"fall": (400, 1, 400), "yard": (27, 3, 6), "causeway": (15, 3, 6), "ring": (21, 3, 6), "end": (21, 3, 9)}
level.add_shell()

# ---- Enemies. ----
level.enemy_group("EnemyGroup")  # idle packs ahead of the spawn, for the first shots
for pack, (cx, cz) in enumerate(((-2.5, 0), (0, -0.5), (2.5, 0)), 1):
    level.melee("EnemyGroup", f"EnemyRobot{pack}a", cx, cz)
    level.melee("EnemyGroup", f"EnemyRobot{pack}b", cx - 0.35, cz - 0.35)
    level.melee("EnemyGroup", f"EnemyRobot{pack}c", cx + 0.35, cz - 0.35)
YARD_ROBOTS = ((-4, -21), (-2, -21), (0, -21), (2, -21), (4, -21), (-5, -18), (5, -18), (-1, -17), (1, -17), (0, -20))
# The two at the front of the yard reach the carriers first, so they are where the vent is
# learned: bolts bounce off their shields, and heat the barrel for the vent that pops them.
SHIELDED_YARD_ROBOTS = {(-1, -17), (1, -17)}
level.enemy_group("EnemyGroup2")  # wake once the bridge behind the carriers switches off
for i, (cx, cz) in enumerate(YARD_ROBOTS, 1):
    level.melee("EnemyGroup2", f"EnemyRobot{i}", cx, cz, shielded=(cx, cz) in SHIELDED_YARD_ROBOTS)
GUNNERS = ((-5, -29), (-5, -35), (5, -29), (5, -35))
level.enemy_group("EnemyGroup3")  # gunners on the perches can only be shot; the rest charge down the causeway
for i, (cx, cz) in enumerate(GUNNERS, 1):
    level.mage("EnemyGroup3", f"EnemyRobotGunner{i}", cx, cz, cast_max=16.0, cooldown=3.5)
for i, (cx, cz) in enumerate(((-1, -37), (1, -37), (0, -36), (-1, -35), (1, -35)), 1):
    level.melee("EnemyGroup3", f"EnemyRobot{i}", cx, cz, shielded=(cx, cz) == (0, -36))
level.survival_group(((-5, -53), (5, -53), (-5, -43), (5, -43), (-5, -48), (5, -48)), duration=40)

# ---- Checkpoints. ----
level.checkpoints([
    checkpoint("Checkpoint", 0, 3),
    checkpoint("Checkpoint2", 0, -4, "OpenBridge1", "EnemyGroup2", "EnemyGroup", T),
    checkpoint("Checkpoint3", 0, -20, "OpenBridge2", "EnemyGroup3", "EnemyGroup2", T + "2", T),
    checkpoint("Checkpoint4", 0, -36, "OpenBridge3", "SurvivalEnemyGroup", "EnemyGroup3", T + "3", T + "2"),
    checkpoint("Checkpoint5", 0, -53, "OpenBridge4", None, "SurvivalEnemyGroup", None, T + "3"),
], setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_station_terrain(DECKS, PROPS, fall_z=-30)
level.add_planet((230, -520, -150), 300)
level.node("DistantStations", "Level", "Node")
for name, position, shape, props in (
        ("StationA", (-62, -34, 6), rounded(-3, 3, -2, 2), {(0, 0): ("Dome", 0), (-2, 0): ("BaseModuleB", 0), (2, 0): ("SolarRoof", 0)}),
        ("StationB", (66, -40, -40), rounded(-4, 4, -3, 3), {(0, 0): ("LandingPad", 0), (-3, 1): ("Garage", 0), (3, -1): ("EcoModule", 0)}),
        ("StationC", (-70, -46, -92), rounded(-3, 4, -4, 3), {(1, 0): ("Command", 0), (-1, -2): ("StructureTall", 0), (2, 2): ("Antenna", 0)}),
        ("StationD", (62, -36, -130), rounded(-2, 2, -2, 2), {(0, 0): ("BaseModuleE", 0)}),
):
    level.add_distant_station(name, position, shape, props)
level.add_asteroids((
    (-40, -28, -10, 5), (44, -32, -20, 7), (-52, -40, -62, 9), (38, -26, -78, 4), (-36, -30, -128, 6),
    (50, -44, -110, 8), (-30, -60, -40, 12), (28, -52, -170, 10), (-8, -70, -100, 14),
))

# ---- Events. ----
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "MakeEnemiesGroup2Offensive")
level.offensive_event("MakeEnemiesGroup2Offensive", "EnemyGroup2")
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "MakeEnemiesGroup3Offensive")
level.offensive_event("MakeEnemiesGroup3Offensive", "EnemyGroup3")
level.bridge_event("OpenBridge3", 3)
level.bridge_event("CloseBridge3", 3, True, "MakeSurvivalGroupOffensive")
level.offensive_event("MakeSurvivalGroupOffensive", "SurvivalEnemyGroup")
level.bridge_event("OpenBridge4", 4)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
# Framing only for the gunners, on perches that can't be walked to. Every other robot comes within reach.
level.add_focus({"Gunners": (-6, 6, -26, -36)})
level.add_end_area(0, -61)
level.add_bridge_nodes()
level.add_triggers(((T, 0, -11, "yard"), (T + "2", 0, -27, "causeway"), (T + "3", 0, -43, "ring")))
wx, wz = world(0, 3)
level.add_weapon("PulseRifle", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
PROGRESSION = (("EnemyGroup", 1, "Checkpoint2"), ("EnemyGroup2", 2, "Checkpoint3"),
               ("EnemyGroup3", 3, "Checkpoint4"), ("SurvivalEnemyGroup", 4, "Checkpoint5"))
for group, number, cp_name in PROGRESSION:
    level.connect("enemies_defeated", GROUPS + group, "CheckpointManager/" + cp_name, "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + f"OpenBridge{number}")
level.connect("enemies_defeated", GROUPS + "EnemyGroup3", EVENTS + "UnfocusCamera")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
for number, name in ((1, T), (2, T + "2"), (3, T + "3")):
    level.connect("all_players_inside", AREAS + name, EVENTS + f"CloseBridge{number}")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + T + "2", EVENTS + f"FocusGunners{corner}")

level.write(sys.argv[1:])
