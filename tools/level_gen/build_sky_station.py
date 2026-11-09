#!/usr/bin/env python3
"""A short futuristic sky level: world_local_sky_station.tscn.

The carriers start on a floating station whose dock holds a hover barge. Once both carriers are aboard, it flies
out over the clouds, two winged mechs swoop in from either side, and it holds in mid-air until both are down.
Then it carries the carriers to the second island, where the level ends.

Station plating and props come from the space station level, the barge fight from the rotor decks, and the sky
(panorama and drifting cloud sheets) from the sky levels. Played with the fork cannon: its bolts lock on to a
flyer, and the front carrier's missile steers to the lock.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (BRIDGE_Y, ENVIRONMENT_SKY, EVENTS, FACE_SOUTH, SKY_PANORAMA, Level, checkpoint, fmt,
                      node_paths, rect, tf, world)


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. ----
STATION = rounded(-4, 4, -3, 4)  # the start: its north edge (row -3) is the barge's dock
END_ISLAND = rounded(-3, 3, -26, -20)  # its south edge (row -20) is the barge's final dock
DECKS = [STATION, END_ISLAND]
FLOOR = set().union(*DECKS)

# Props stand on a plate and block movement. (item, GridMap orientation: 0, 10, 16 or 22.)
# The middle three columns stay clear, so the carriers walk straight from the spawn to the dock.
PROPS = {
    # Start station: parked craft and cargo along the sides, beacons either side of the dock.
    (-4, 3): ("Dropship", 16), (4, 3): ("Lander", 0), (-4, 0): ("CargoA", 0), (4, 0): ("CargoDepot", 22),
    (-4, -2): ("Antenna", 0), (4, -2): ("StructureTall", 0), (-2, 4): ("Lights", 0), (2, 4): ("Lights", 0),
    (-3, -3): ("Lights", 0), (3, -3): ("Lights", 0),
    # End island: the way off, behind the landing.
    (0, -25): ("Dropship", 0), (-3, -24): ("CargoA", 0), (3, -24): ("CargoB", 10),
    (-2, -20): ("Lights", 0), (2, -20): ("Lights", 0),
}

# The barge, in world metres. Its deck is 15 x 12 m, so its centre sits 6 m off a dock edge.
# It is placed at its dock (stops 0 and 1 are the same), flies out to hold for the fight, then docks at the end.
STATION_NORTH_EDGE = -3 * 2.999
END_SOUTH_EDGE = -19 * 2.999
BARGE_DOCK = (1.5, STATION_NORTH_EDGE - 6.0)
BARGE_FIGHT = (4.5, (STATION_NORTH_EDGE + END_SOUTH_EDGE) / 2.0)
BARGE_FINAL = (1.5, END_SOUTH_EDGE + 6.0)
BARGE_SPEED = 4.5
# Where each mech comes to a hover when it arrives, in metres from the barge deck's centre (y is above the deck).
MECH_SPOTS = ((-4.5, 1.6, -3.0), (4.5, 1.6, -3.0))

level = Level("src/world/levels/world_local_sky_station.tscn", palette="space", weapon="fork_cannon", floor_seed=7, deco_seed=7,
              music="cyber_noir", hint="[color=#88ddff]Sky Station[/color]\n\nBoard the barge together.\nWinged mechs guard the crossing.")
# A daytime sky for the station: the panorama and cloud sheets, with glow for the station's lit trims.
level.environment = ENVIRONMENT_SKY + "\ntonemap_mode = 3\nglow_enabled = true\nglow_intensity = 0.45\nglow_hdr_threshold = 1.1"
level.sky_material = SKY_PANORAMA
level.sun_extra = {"light_color": "Color(1, 0.98, 0.94, 1)", "light_energy": "1.1"}
level.extra_ext += [
    ("PackedScene", None, "res://src/world/elements/sky/cloud_layers.tscn", "clouds"),
    ("Script", None, "res://src/world/elements/sky/floating_bob.gd", "bob"),
    ("PackedScene", None, "res://src/world/elements/space/hover_barge.tscn", "hover_barge"),
    ("PackedScene", None, "res://src/enemy/enemy_winged_mech.tscn", "winged_mech"),
    ("Script", None, "res://src/enemy/boarding_enemy_group.gd", "boarding_group"),
    ("Script", None, "res://src/events/barge_voyage_event.gd", "barge_voyage"),
]
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "end": (15, 3, 9)}
level.add_shell()

# ---- Enemies: the mechs fly in from both flanks once the barge has left the dock. ----
level.node("MechWave", "Enemies", "Node3D", paths=["deck"], props={
    "script": 'ExtResource("boarding_group")', "deck": 'NodePath("../../Level/Barge/AnimatableBody3D/MovingFloor")',
    "drop_stagger_seconds": "0.6", "entry": "1", "fly_in_offset": "Vector3(18, 7, -12)", "fly_in_seconds": "1.8"})
level.node("InstancedEnemies", "Enemies/MechWave", "Node3D")
for index, (x, y, z) in enumerate(MECH_SPOTS, 1):
    level.node(f"EnemyWingedMech{index}", "Enemies/MechWave/InstancedEnemies", instance="winged_mech", props={
        "transform": tf(x, y, z, FACE_SOUTH), "is_offensive": "false"})

# ---- Checkpoint: one. Its restore docks the barge and waits for the carriers, with the mechs stowed again. ----
level.checkpoints([checkpoint("Checkpoint", 0, 2, "BargeVoyage", "MechWave")],
                  setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_station_terrain(DECKS, PROPS, fall_z=-30)
level.node("CloudLayers", "Level", instance="clouds")
level.node("DistantStations", "Level", "Node")
for name, position, shape, props in (
        ("StationA", (-58, -32, 4), rounded(-3, 3, -2, 2), {(0, 0): ("Dome", 0), (-2, 0): ("BaseModuleB", 0), (2, 0): ("SolarRoof", 0)}),
        ("StationB", (64, -38, -30), rounded(-4, 4, -3, 3), {(0, 0): ("LandingPad", 0), (-3, 1): ("Garage", 0), (3, -1): ("EcoModule", 0)}),
        ("StationC", (-66, -44, -78), rounded(-3, 4, -4, 3), {(1, 0): ("Command", 0), (-1, -2): ("StructureTall", 0), (2, 2): ("Antenna", 0)}),
        ("StationD", (58, -30, -104), rounded(-2, 2, -2, 2), {(0, 0): ("BaseModuleE", 0)}),
):
    level.add_distant_station(name, position, shape, props)

# ---- The barge and its voyage. ----
stops = [(0.0, 0.0), (0.0, 0.0)] + [(x - BARGE_DOCK[0], z - BARGE_DOCK[1]) for x, z in (BARGE_FIGHT, BARGE_FINAL)]
level.node("Barge", "Level", instance="hover_barge", props={
    "transform": tf(BARGE_DOCK[0], BRIDGE_Y + 3.0, BARGE_DOCK[1]),
    "stops": "PackedVector3Array(" + ", ".join(f"{fmt(x)}, 0, {fmt(z)}" for x, z in stops) + ")",
    "speed": fmt(BARGE_SPEED)})
level.node("BargeVoyage", "Level/Events", "Node", paths=["barge", "waves"], props={
    "script": 'ExtResource("barge_voyage")', "barge": 'NodePath("../../Barge")',
    "waves": node_paths(["../../../Enemies/MechWave"]), "board_delay_seconds": "1.5"})
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_end_area(0, -22)
wx, wz = world(0, 2)
level.add_weapon("ForkCannon", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
