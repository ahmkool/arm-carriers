#!/usr/bin/env python3
"""Beginning of Rotor Decks II: world_local_rotor_decks_2.tscn.

Players start on a grass sky island with a bazooka, flanked by two rotor deck
platforms on the left and right, each holding three inoffensive aviator enemies.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (
    AREAS,
    EVENTS,
    GROUPS,
    Level,
    _encode_cells,
    _rotor_spots,
    checkpoint,
    rect,
    tf,
    world,
)


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells (3 m each). Forward is -z. ----
START_ISLAND = rounded(-3, 3, -3, 3)
DECK_LEFT = rounded(-8, -5, -2, 2)
DECK_RIGHT = rounded(5, 8, -2, 2)
ROTOR_DECKS = DECK_LEFT | DECK_RIGHT

# Symmetrical outer rotor placements on the left and right rotor decks (no cut-corner overlap).
DECK_ROTORS = [
    (*(world(cx, cz)[0] + dx * 1.5, world(cx, cz)[1] + dz * 1.5), side)
    for cx, cz, side, dx, dz in (
        (-8, -1, "W", -1, 0),
        (-8, 1, "W", -1, 0),
        (-7, -2, "N", 0, -1),
        (-7, 2, "S", 0, 1),
        (8, -1, "E", 1, 0),
        (8, 1, "E", 1, 0),
        (7, -2, "N", 0, -1),
        (7, 2, "S", 0, 1),
    )
]

DISTANT = (
    ("DeckA", (-58, -26, 10), rounded(-3, 3, -2, 2)),
    ("DeckB", (64, -32, -16), rounded(-4, 4, -3, 3)),
    ("DeckC", (-70, -34, -46), rounded(-3, 4, -4, 3)),
    ("DeckD", (60, -26, -70), rounded(-2, 2, -2, 2)),
)

DECK_ITEMS = {"Deck": 0, "Joists": 1, "EdgeN": 2, "EdgeS": 3, "EdgeW": 4, "EdgeE": 5}


def deck_frame_cells(floor):
    """Dark joists under each rotor deck cell and edge beams around outer borders."""
    cells = {(x, -1, z): (DECK_ITEMS["Joists"], 0) for x, z in floor}
    edges = (("EdgeN", 0, -1), ("EdgeS", 0, 1), ("EdgeW", -1, 0), ("EdgeE", 1, 0))
    for layer, (name, dx, dz) in enumerate(edges, 2):
        for x, z in floor:
            if (x + dx, z + dz) not in floor:
                cells[(x, -layer, z)] = (DECK_ITEMS[name], 0)
    return cells


def deck_grid_map(name, parent, cells, collision=False):
    layer = 4 if collision else 0
    return (
        f'[node name="{name}" type="GridMap" parent="{parent}"]\n'
        'mesh_library = ExtResource("deck_tiles")\n'
        f"cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = {layer}\ncollision_mask = 0\n"
        'data = {\n"cells": PackedInt32Array(' + _encode_cells(cells) + ")\n}\n"
        "metadata/_editor_floor_ = Vector3(0, -1, 0)"
    )


level = Level(
    "src/world/levels/world_local_rotor_decks_2.tscn",
    palette=1,
    weapon="bazooka",
    floor_seed=3,
    deco_seed=7,
    music="ticking_labyrinth",
)
level.curve = (3.0, 3.0)
level.boxes = {"fall": (400, 1, 400), "island": (21, 3, 21)}
level.melee_scene = "aviator"
level.extra_ext += [
    ("MeshLibrary", "uid://naqh6to77nue", "res://src/world/elements/sky_decks/deck_tiles.tres", "deck_tiles"),
    ("PackedScene", None, "res://src/world/elements/sky_decks/deck_rotor.tscn", "rotor"),
    ("PackedScene", None, "res://src/enemy/enemy_aviator.tscn", "aviator"),
]
level.add_shell()
level.nodes[0] += "\nskip_save = true"

# ---- Enemies: 3 inoffensive aviator enemies on each rotor deck platform. ----
level.enemy_group("EnemyGroup")
AVIATORS = (
    (-6.1, -0.5),
    (-6.9, 0.0),
    (-6.1, 0.5),
    (6.1, -0.5),
    (6.9, 0.0),
    (6.1, 0.5),
)
for i, (cx, cz) in enumerate(AVIATORS, 1):
    level.melee("EnemyGroup", f"EnemyAviator{i}", cx, cz)

# ---- Checkpoints. ----
CHECKPOINTS = [
    checkpoint("Checkpoint", 0, 1, react="FiringLineTrigger"),
    checkpoint("Checkpoint2", 0, -1, None, None, "EnemyGroup", None, "FiringLineTrigger"),
]
for corner in ("SW", "SE", "NW", "NE"):
    CHECKPOINTS[0][3].setdefault("events_completed", []).append(f"../../Level/Events/FocusDecks{corner}")
level.checkpoints(CHECKPOINTS, setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain: grass sky island + left & right rotor deck platforms. ----
level.add_terrain(START_ISLAND, set(), decoration_count=25, fall_z=-40, fall_y=-17)
deck_floor = {(x, -1, z): (DECK_ITEMS["Deck"], 0) for x, z in ROTOR_DECKS}
level.nodes.append(deck_grid_map("GridMapDecks", "Level/NavigationRegion3D", deck_floor, collision=True))
level.add_sky(START_ISLAND)
level.nodes.append(deck_grid_map("DeckFrame", "Level", deck_frame_cells(ROTOR_DECKS), collision=False))
level.node("Rotors", "Level", "Node3D")
level._add_rotors("Level/Rotors", DECK_ROTORS, 0)

level.node("DistantDecks", "Level", "Node")
for name, (dx, dy, dz), shape in DISTANT:
    path = f"Level/DistantDecks/{name}"
    level.node(name, "Level/DistantDecks", "Node3D", props={"transform": tf(dx, dy, dz), "script": 'ExtResource("bob")'})
    cells = {(cx, -1, cz): (DECK_ITEMS["Deck"], 0) for cx, cz in shape}
    level.nodes.append(deck_grid_map("Deck", path, cells, collision=False))
    level.nodes.append(deck_grid_map("Frame", path, deck_frame_cells(shape), collision=False))
    level._add_rotors(path, _rotor_spots(shape, set(), every=2, origin=(0, 0)), 0)

# ---- Events, triggers, weapon, and audio. ----
level.add_focus({"Decks": (-7, 7, 2, -2)})
level.add_triggers((("FiringLineTrigger", 0, 0, "island"),))
level.add_weapon("Bazooka", tf(1.5, 0.593, 4.5))
level.add_audio_and_hint()

# ---- Signals. ----
level.connect("enemies_defeated", GROUPS + "EnemyGroup", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "EnemyGroup", EVENTS + "UnfocusCamera")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + "FiringLineTrigger", EVENTS + f"FocusDecks{corner}")

level.write(sys.argv[1:])
