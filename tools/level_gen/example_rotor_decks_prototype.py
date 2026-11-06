#!/usr/bin/env python3
"""Prototype of a sky level on wooden decks held up by rotors: world_local_rotor_decks.tscn.

Ferries replace bridges. Each is a bridge platform whose animation flies: "open" brings it to the carriers,
"close" (when both step on) carries them across.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import AREAS, EVENTS, GROUPS, TRIGGER as T, Level, checkpoint, rect, tf


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. Every gap is 7 cells, because a ferry flies a fixed 4 cells. ----
START = rounded(-5, 5, -3, 10)  # long enough that the first targets are on screen from the firing line
RING = rounded(-6, 6, -20, -11) - rect(-1, 1, -17, -14)  # looks straight down through the clouds
CAUSEWAY = rect(-3, 3, -37, -28)
PERCH_W, PERCH_E = rounded(-9, -6, -36, -28), rounded(6, 9, -36, -28)  # out of reach, rockets only
END_PAD = rounded(-4, 4, -52, -45)
DECKS = [START, RING, CAUSEWAY, PERCH_W, PERCH_E, END_PAD]
FLOOR = set().union(*DECKS)

# A ferry waits at its far dock (these cells) until called. Its near dock is 4 cells closer to the start.
FERRIES = {1: [(0, -9)], 2: [(0, -26)], 3: [(0, -43)]}
NEAR_DOCKS = {1: (0, -5), 2: (0, -22), 3: (0, -39)}
# Edge cells beside a ferry's lane get no rotor, or it would fly through them.
LANES = {(x, z) for x in range(-6, 7) for z in (-3, -11, -20, -28, -37, -45)}
LANES |= {(x, z) for x in (-6, 6) for z in range(-37, -27)}  # the gaps beside the causeway only fit its own rotors
LANES |= rect(-2, 2, -18, -13)  # nothing inside the ring's hole
assert all(cell not in FLOOR for cells in FERRIES.values() for cell in cells)

DISTANT = (
    ("DeckA", (-58, -26, 10), rounded(-3, 3, -2, 2)),
    ("DeckB", (64, -32, -16), rounded(-4, 4, -3, 3)),
    ("DeckC", (-70, -34, -46), rounded(-3, 4, -4, 3)),
    ("DeckD", (60, -26, -70), rounded(-2, 2, -2, 2)),
    ("DeckE", (-62, -30, -98), rounded(-4, 3, -3, 3)),
    ("DeckF", (72, -34, -122), rounded(-5, 5, -4, 4)),
)

level = Level("src/world/levels/world_local_rotor_decks.tscn", palette="decks", weapon="bazooka", floor_seed=3, deco_seed=3, music="ticking_labyrinth")
level.use_rotor_decks()
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "ride": (7.5, 3, 7.5), "end": (21, 3, 9)}
level.add_shell()

# ---- Enemies. ----
level.enemy_group("EnemyGroup")  # idle packs at the far end of the start deck, for the first shots
pack = 0
for cx, cz in ((-3, -1), (0, -1), (3, -1)):
    pack += 1
    level.melee("EnemyGroup", f"EnemyLocal{pack}a", cx, cz)
    level.melee("EnemyGroup", f"EnemyLocal{pack}b", cx - 0.35, cz - 0.35)
    level.melee("EnemyGroup", f"EnemyLocal{pack}c", cx + 0.35, cz - 0.35)
level.enemy_group("EnemyGroup2")  # wake as the ferry leaves, and crowd the far dock: shoot them from the ferry
for i, (cx, cz) in enumerate(((-4, -19), (-2, -19), (0, -19), (2, -19), (4, -19), (-5, -16), (5, -16), (-4, -14), (4, -14), (-3, -18), (3, -18)), 1):
    level.melee("EnemyGroup2", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup3")  # mages on their own decks, in range as the ferry lands
for i, (cx, cz) in enumerate(((-7, -30), (-7, -33), (7, -33), (7, -30)), 1):
    level.mage("EnemyGroup3", f"EnemyMage{i}", cx, cz, cast_max=26.0, cooldown=4.0)
for i, (cx, cz) in enumerate(((-1, -35), (1, -35), (0, -34)), 1):
    level.melee("EnemyGroup3", f"EnemyLocal{i}", cx, cz)

level.checkpoints([
    checkpoint("Checkpoint", 0, 7),
    checkpoint("Checkpoint2", 0, 1, "CallFerry1", "EnemyGroup2", "EnemyGroup", T),
    checkpoint("Checkpoint3", 0, -19, "CallFerry2", "EnemyGroup3", "EnemyGroup2", T + "2", T),
    checkpoint("Checkpoint4", 0, -35, "CallFerry3", None, "EnemyGroup3", T + "3", T + "2"),
], setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_deck_terrain(DECKS, LANES, fall_z=-40)
level.node("DistantDecks", "Level", "Node")
for name, position, shape in DISTANT:
    level.add_distant_deck(name, position, shape)

# ---- Events. "Call" brings a ferry to the carriers; "Ride" flies it back with them aboard. ----
level.set_bridges(FERRIES)
level.bridge_event("CallFerry1", 1)
level.bridge_event("RideFerry1", 1, True, "MakeEnemiesGroup2Offensive")
level.offensive_event("MakeEnemiesGroup2Offensive", "EnemyGroup2")
level.bridge_event("CallFerry2", 2)
level.bridge_event("RideFerry2", 2, True, "MakeEnemiesGroup3Offensive")
level.offensive_event("MakeEnemiesGroup3Offensive", "EnemyGroup3")
level.bridge_event("CallFerry3", 3)
level.bridge_event("RideFerry3", 3, True)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
# Framing only for the mages, on decks that can't be walked to. Every other enemy comes within reach.
level.add_focus({"Mages": (-10, 10, -21, -37)})
level.add_end_area(0, -49)
level.add_bridge_nodes()
level.add_triggers(((T, *NEAR_DOCKS[1], "ride"), (T + "2", *NEAR_DOCKS[2], "ride"), (T + "3", *NEAR_DOCKS[3], "ride")))
level.add_weapon("Bazooka", tf(1.5, 0.593, 22.5))
level.add_audio_and_hint()

# ---- Signals. ----
for group, number, cp_name in (("EnemyGroup", 1, "Checkpoint2"), ("EnemyGroup2", 2, "Checkpoint3"), ("EnemyGroup3", 3, "Checkpoint4")):
    level.connect("enemies_defeated", GROUPS + group, "CheckpointManager/" + cp_name, "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + f"CallFerry{number}")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + "UnfocusCamera")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
for number, name in ((1, T), (2, T + "2"), (3, T + "3")):
    level.connect("all_players_inside", AREAS + name, EVENTS + f"RideFerry{number}")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + T + "2", EVENTS + f"FocusMages{corner}")

level.write(sys.argv[1:])
