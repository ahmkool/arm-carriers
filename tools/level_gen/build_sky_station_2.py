#!/usr/bin/env python3
"""A second sky station level, in the same biome as world_local_sky_station.tscn: world_local_sky_station_2.tscn.

1. The range. The carriers start on a floating station; across open air, on the next station island, nine melee
   mechs stand idle in three tight packs. A firing line on the station's neck frames them (as in the Sky Islands
   opening). Clearing them sets Checkpoint2 and projects a hard-light bridge north.
2. The flyer. Stepping onto island 2 switches that bridge off and wakes a winged mech with 30 HP. Downing it sets
   Checkpoint3 and projects a bridge east.
3. The hold. Stepping onto island 3 switches that bridge off and starts a 60 s survival wave of melee mechs, with two
   grenadier mechs (15 HP each) at the back of the island. Once the wave is over and both grenadiers are down
   (`GroupsDefeatedGate`), Checkpoint4 is set and a hover barge is called to the island's south edge; the camera
   frames its dock until the carriers stand on it.
4. The crossing. Once both carriers are aboard, the barge flies them south to island 4, which sets Checkpoint5.
5. The voyage east. A second barge waits at island 4's east edge. Once both carriers are aboard it flies east and
   holds twice: first for a 60 s survival wave of mech gunners spawning on an island just north of it (framed while
   it lasts), then for a winged mech (30 HP) that flies in and fights over the deck. Then it docks at the end island.
6. The last flight. A third barge waits at the end island's north edge. Once both carriers are aboard it flies north
   and holds once, for two winged mechs (30 HP each) that fly in from both flanks and fight over the deck. Then it
   docks at the final island, where the level ends.

Played with the fork cannon, like the first sky station level.
Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (AREAS, BRIDGE_Y, ENVIRONMENT_SKY, EVENTS, FACE_SOUTH, GROUPS, SKY_PANORAMA, TRIGGER as T, Level,
                      fmt, node_paths, rect, single_bridge, tf, world)

T2 = T + "2"


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z, east is +x. ----
START = rounded(-4, 4, -2, 4) | rect(-1, 1, -4, -3)  # the station, with a neck out to the firing line
ISLAND2 = rounded(-5, 5, -17, -7)  # the range's island, then the winged mech's
ISLAND3 = rounded(8, 18, -17, -7)  # east of island 2: the survival hold
ISLAND4 = rounded(9, 17, 3, 8)  # south of island 3, reached by the first barge; the second leaves from its east edge
GUNNER_ISLAND = rounded(26, 34, -3, 2)  # north of the second barge's first hold, out of reach: gunners only
END_ISLAND = rounded(51, 58, 3, 8)  # east, where the second barge docks and the third waits
FINAL_ISLAND = rounded(51, 58, -29, -22)  # north of the end island, where the third barge docks: the level's end
DECKS = [START, ISLAND2, ISLAND3, ISLAND4, GUNNER_ISLAND, END_ISLAND, FINAL_ISLAND]
FLOOR = set().union(*DECKS)

BRIDGES = {1: single_bridge(-5, -6), 2: [(6, -12), (7, -12)]}
EAST_WEST_BRIDGES = {2}  # turned a quarter: the hard-light surface stretches along its own z
assert all(cell not in FLOOR for cells in BRIDGES.values() for cell in cells)

# Props stand on a plate and block movement. (item, GridMap orientation: 0, 10, 16 or 22.)
PROPS = {
    # Start station: parked craft and cargo along the sides, beacons at the neck.
    (-4, 3): ("Dropship", 16), (4, 3): ("Lander", 0), (-4, 0): ("CargoA", 0), (4, 0): ("CargoDepot", 22),
    (-3, -2): ("Antenna", 0), (3, -2): ("StructureTall", 0), (-2, 4): ("Lights", 0), (2, 4): ("Lights", 0),
    # Island 2: modules on the west flank and at the back, beacons beside both bridge landings. The east edge's
    # middle row stays clear for the east bridge.
    (-5, -12): ("BaseModuleA", 0), (-4, -16): ("CargoA", 0), (4, -16): ("CargoB", 10), (0, -17): ("Antenna", 0),
    (-2, -7): ("Lights", 0), (2, -7): ("Lights", 0), (5, -10): ("Lights", 0), (5, -14): ("Lights", 0),
    # Island 3: cover in the corners of the arena, out of the walk from the bridge and the barge's dock.
    (11, -15): ("CargoA", 0), (15, -15): ("CargoB", 10), (16, -10): ("CargoDepot", 22), (18, -12): ("Command", 22),
    (8, -10): ("Lights", 0), (8, -14): ("Lights", 0),
    # Island 4: parked craft along the south side, clear of both docks.
    (13, 8): ("Dropship", 0), (10, 7): ("CargoA", 0),
    # Gunner island: masts at the back, the south rows clear for the gunners.
    (30, -3): ("StructureTall", 0), (28, -2): ("Antenna", 0), (32, -2): ("Dome", 0),
    # End island: the way out, beyond the end area.
    (58, 5): ("Dropship", 16), (57, 4): ("CargoA", 0), (57, 7): ("CargoB", 10),
    # Final island: cargo and beacons at the sides and back, clear of the dock and the end area.
    (52, -28): ("CargoA", 0), (57, -28): ("CargoB", 10), (52, -24): ("Lights", 0), (57, -24): ("Lights", 0),
    (51, -26): ("Antenna", 0), (58, -26): ("StructureTall", 0), (55, -29): ("Dropship", 16),
}
LANDINGS = {(0, -7), (0, -8), (5, -12), (4, -12), (8, -12), (9, -12), (17, 5), (17, 6), (51, 5), (51, 6),
            (54, 3), (55, 3), (54, -22), (55, -22)}
assert not set(PROPS) & LANDINGS, "keep the bridge landings clear"
assert set(PROPS) <= FLOOR, sorted(set(PROPS) - FLOOR)

# The range: three packs of three, 1 m apart inside each pack, so one missile blast (3.5 m) takes a pack.
PACKS = ((-3, -9), (0, -9), (3, -9))  # two rows in from the island edge: further back leaves them at the top of the view
WINGED_SPOT = (0, -12)  # it hovers here until it wakes: close enough to be on screen soon after the landing
WINGED_HP = 30
GRENADIER_SPOTS = ((10, -16), (16, -16))  # the back corners of island 3
GRENADIER_HP = 15
SURVIVAL_SPAWNS = ((11, -16), (15, -16), (17, -14), (17, -9), (13, -8), (12, -12))
SURVIVAL_SECONDS = 60

# The barges, in world metres. A deck is 15 m along x and 12 m along z, so its centre sits 6 m off a north or south
# dock edge and 7.5 m off an east or west one.
# The first waits at island 4 (stop 0), is called to island 3's south edge (stop 1), and flies the carriers back
# to island 4 (stop 2).
BARGE_X = world(13, 0)[0]
ISLAND3_SOUTH_EDGE = -6 * 2.999  # row -7's south edge
ISLAND4_NORTH_EDGE = 3 * 2.999  # row 3's north edge
BARGE_DOCK = (BARGE_X, ISLAND3_SOUTH_EDGE + 6.0)
BARGE_END = (BARGE_X, ISLAND4_NORTH_EDGE - 6.0)
BARGE_SPEED = 4.5
# The second is placed at island 4's east edge and waits there (stops 0 and 1), then holds for the gunners (stop 2)
# beside their island, holds for the winged mech (stop 3), and docks at the end island's west edge (stop 4).
BARGE2_Z = 6 * 2.999  # between island 4's rows 5 and 6
BARGE2_DOCK_X = 18 * 2.999 + 7.5  # island 4's east edge (column 17)
BARGE2_GUNNERS_X = world(30, 0)[0]  # beside the gunner island, whose south edge is 3 m off the deck's north edge
BARGE2_WINGED_X = BARGE2_GUNNERS_X + 30.0
BARGE2_END_X = 51 * 2.999 - 7.5  # the end island's west edge (column 51)
GUNNER_SPAWNS = ((28, 2), (30, 2), (32, 2), (29, 1), (31, 1), (30, 0))  # near the south edge, in range of the deck
GUNNER_SECONDS = 60
WAVE2_WINGED_SPOT = (0.0, 1.6, -3.0)  # where it comes to a hover, in metres from the deck's centre
# The third barge waits at the end island's north edge (stops 0 and 1), holds for the winged pair (stop 2) over open
# air, and docks at the final island's south edge (stop 3). Its deck centre sits 6 m off a north or south dock edge.
BARGE3_X = 55 * 2.999  # the end island's centre column line
BARGE3_DOCK_Z = 3 * 2.999 - 6.0  # the end island's north edge
BARGE3_END_Z = -21 * 2.999 + 6.0  # the final island's south edge (row -22's)
BARGE3_FIGHT_Z = (BARGE3_DOCK_Z + BARGE3_END_Z) / 2.0
PAIR_SPOTS = ((-4.0, 1.6, -3.0), (4.0, 1.6, -3.0))  # one on each half of the deck, so they arrive from both flanks
PAIR_HP = 30

DISTANT_STATIONS = (
    ("StationA", (-58, -32, 4), rounded(-3, 3, -2, 2), {(0, 0): ("Dome", 0), (-2, 0): ("BaseModuleB", 0), (2, 0): ("SolarRoof", 0)}),
    ("StationB", (120, -44, -64), rounded(-4, 4, -3, 3), {(0, 0): ("LandingPad", 0), (-3, 1): ("Garage", 0), (3, -1): ("EcoModule", 0)}),
    ("StationC", (-66, -44, -78), rounded(-3, 4, -4, 3), {(1, 0): ("Command", 0), (-1, -2): ("StructureTall", 0), (2, 2): ("Antenna", 0)}),
    ("StationD", (58, -30, -104), rounded(-2, 2, -2, 2), {(0, 0): ("BaseModuleE", 0)}),
    ("StationE", (96, -36, 46), rounded(-3, 3, -3, 3), {(0, 0): ("Dome", 0), (2, -1): ("Antenna", 0)}),
)

level = Level("src/world/levels/world_local_sky_station_2.tscn", palette="space", weapon="fork_cannon", floor_seed=11, deco_seed=11,
              music="cyber_noir", hint="[color=#88ddff]Sky Station II[/color]\n\nClear the mechs on the next island\nto bring the bridge across.")
# The sky station biome: the panorama and cloud sheets, with glow for the station's lit trims (as in build_sky_station.py).
level.environment = ENVIRONMENT_SKY + "\ntonemap_mode = 3\nglow_enabled = true\nglow_intensity = 0.45\nglow_hdr_threshold = 1.1"
level.sky_material = SKY_PANORAMA
level.sun_extra = {"light_color": "Color(1, 0.98, 0.94, 1)", "light_energy": "1.1"}
level.bridge_scene = (None, "res://src/world/elements/space/hard_light_bridge_platform.tscn")
level.melee_scene = "melee_mech"
level.survival_scene = "melee_mech"
level.extra_ext += [
    ("PackedScene", None, "res://src/world/elements/sky/cloud_layers.tscn", "clouds"),
    ("Script", None, "res://src/world/elements/sky/floating_bob.gd", "bob"),
    ("PackedScene", None, "res://src/enemy/enemy_melee_mech.tscn", "melee_mech"),
    ("PackedScene", None, "res://src/enemy/enemy_winged_mech.tscn", "winged_mech"),
    ("PackedScene", None, "res://src/enemy/enemy_grenadier_mech.tscn", "grenadier_mech"),
    ("PackedScene", None, "res://src/enemy/enemy_ground_mech.tscn", "ground_mech"),
    ("Script", None, "res://src/enemy/boarding_enemy_group.gd", "boarding_group"),
    ("PackedScene", None, "res://src/world/elements/space/hover_barge.tscn", "hover_barge"),
    ("Script", None, "res://src/events/barge_voyage_event.gd", "barge_voyage"),
    ("Script", None, "res://src/events/groups_defeated_gate.gd", "groups_gate"),
]
level.curve = (3.0, 1.6)  # survival: a melee mech every 3 s at the start, every 1.6 s by the end
level.boxes = {"fall": (400, 1, 400), "firing": (21, 3, 10), "island": (27, 3, 6), "island3": (6, 3, 27), "dock": (15, 3, 12),
               "end": (9, 3, 15)}
# The gunners' survival wave spawns slower than the island 3 hold: every one of them shoots.
level.extra_sub_resources.append('''[sub_resource type="Curve" id="Curve_gunners"]
_limits = [0.0, 8.0, 0.0, 1.0]
_data = [Vector2(0, 6.0), 0.0, 0.0, 0, 0, Vector2(1, 4.0), 0.0, 0.0, 0, 0]
point_count = 2''')
level.add_shell()


# ---- Enemies. ----
def mech_with_hp(group, name, instance, position, hp):
    """A waiting mech from `instance` at world `position`, with its Health's max_hp raised to `hp`."""
    path = f"Enemies/{group}/InstancedEnemies"
    level.node(name, path, instance=instance, props={"transform": tf(*position, FACE_SOUTH), "is_offensive": "false"})
    level.node("Health", f"{path}/{name}", props={"max_hp": str(hp)})


level.enemy_group("EnemyGroup")  # 1: idle across the gap until the carriers come to them, which they can't before the bridge
for pack, (cx, cz) in enumerate(PACKS, 1):
    level.melee("EnemyGroup", f"EnemyMeleeMech{pack}a", cx, cz)
    level.melee("EnemyGroup", f"EnemyMeleeMech{pack}b", cx - 0.35, cz - 0.35)
    level.melee("EnemyGroup", f"EnemyMeleeMech{pack}c", cx + 0.35, cz - 0.35)
level.enemy_group("WingedGroup", spawn_on_trigger=True)  # 2: hovers over island 2 until the carriers land
wx, wz = world(*WINGED_SPOT)
mech_with_hp("WingedGroup", "EnemyWingedMech", "winged_mech", (wx, 0.6, wz), WINGED_HP)  # 1.6 m above the deck
level.survival_group(SURVIVAL_SPAWNS, duration=SURVIVAL_SECONDS)  # 3: the hold on island 3
level.enemy_group("Grenadiers", spawn_on_trigger=True)
for index, (cx, cz) in enumerate(GRENADIER_SPOTS, 1):
    gx, gz = world(cx, cz)
    mech_with_hp("Grenadiers", f"EnemyGrenadierMech{index}", "grenadier_mech", (gx, 0, gz), GRENADIER_HP)
# 5: the second barge's waves. The gunners spawn on their island; the winged mech flies in over the deck.
level.node("GunnerWave", "Enemies", "Node3D", props={
    "script": 'ExtResource("survival_group")', "spawn_interval_curve": 'SubResource("Curve_gunners")',
    "fight_duration": f"{GUNNER_SECONDS:.1f}", "enemy_scene": 'ExtResource("ground_mech")'})
level.node("Enemies", "Enemies/GunnerWave", "Node3D")
level.node("SpawnPoints", "Enemies/GunnerWave", "Node3D")
for index, (cx, cz) in enumerate(GUNNER_SPAWNS, 1):
    sx, sz = world(cx, cz)
    level.node(f"Node3D{index}", "Enemies/GunnerWave/SpawnPoints", "Node3D", props={"transform": tf(sx, 0, sz, FACE_SOUTH)})
level.node("WingedWave", "Enemies", "Node3D", paths=["deck"], props={
    "script": 'ExtResource("boarding_group")', "deck": 'NodePath("../../Level/Barge2/AnimatableBody3D/MovingFloor")',
    "entry": "1", "fly_in_offset": "Vector3(18, 7, -12)", "fly_in_seconds": "1.8"})
level.node("InstancedEnemies", "Enemies/WingedWave", "Node3D")
mech_with_hp("WingedWave", "EnemyWingedMech", "winged_mech", WAVE2_WINGED_SPOT, WINGED_HP)
# 6: the third barge's wave: two winged mechs, flying in from both flanks.
level.node("WingedPair", "Enemies", "Node3D", paths=["deck"], props={
    "script": 'ExtResource("boarding_group")', "deck": 'NodePath("../../Level/Barge3/AnimatableBody3D/MovingFloor")',
    "entry": "1", "fly_in_offset": "Vector3(18, 7, -12)", "fly_in_seconds": "1.8"})
level.node("InstancedEnemies", "Enemies/WingedPair", "Node3D")
for index, spot in enumerate(PAIR_SPOTS, 1):
    mech_with_hp("WingedPair", f"EnemyWingedMech{index}", "winged_mech", spot, PAIR_HP)


# ---- Checkpoints. Each one's arrays describe the world as it is once the previous fight is won. ----
def checkpoint(name, cx, cz, opened=(), reset=(), defeated=(), react=(), done=()):
    arrays = {}
    for key, prefix, names in (("events_completed", "../../Level/Events/", opened), ("enemy_groups_reset", "../../Enemies/", reset),
                               ("enemy_groups_defeated", "../../Enemies/", defeated), ("areas_to_reactivate", "../../Level/Areas/", react),
                               ("areas_already_activated", "../../Level/Areas/", done)):
        if names:
            arrays[key] = [prefix + n for n in names]
    return (name, cx, cz, arrays)


# Checkpoint2 is on the start station, outside every trigger, so walking over the bridge still switches it off.
# Checkpoints 3 and 4 stand clear of the island triggers for the same reason.
level.checkpoints([
    checkpoint("Checkpoint", 0, 2, react=["FiringLineTrigger"]),
    checkpoint("Checkpoint2", 0, 1, ["OpenBridge1"], ["WingedGroup"], ["EnemyGroup"], [T], ["FiringLineTrigger"]),
    checkpoint("Checkpoint3", 0, -14, ["CloseBridge1", "OpenBridge2"], ["SurvivalEnemyGroup", "Grenadiers"],
               ["EnemyGroup", "WingedGroup"], [T2], [T, "FiringLineTrigger"]),
    checkpoint("Checkpoint4", 13, -11, ["CloseBridge1", "CloseBridge2", "BargeVoyage"], [],
               ["EnemyGroup", "WingedGroup", "SurvivalEnemyGroup", "Grenadiers"], ["DockTrigger"], [T, T2, "FiringLineTrigger"]),
    # On island 4. The first barge stays where the scene places it, which is here; the second waits at its dock.
    checkpoint("Checkpoint5", 13, 5, ["CloseBridge1", "CloseBridge2", "BargeVoyage2"], ["GunnerWave", "WingedWave"],
               ["EnemyGroup", "WingedGroup", "SurvivalEnemyGroup", "Grenadiers"], [], [T, T2, "FiringLineTrigger", "DockTrigger"]),
    # On the end island, clear of the dock. The second barge stays at its final stop; the third waits at its dock.
    checkpoint("Checkpoint6", 54, 6, ["CloseBridge1", "CloseBridge2", "BargeVoyage3"], ["WingedPair"],
               ["EnemyGroup", "WingedGroup", "SurvivalEnemyGroup", "Grenadiers", "GunnerWave", "WingedWave"], [],
               [T, T2, "FiringLineTrigger", "DockTrigger"]),
], setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_station_terrain(DECKS, PROPS, fall_z=-30)
level.node("CloudLayers", "Level", instance="clouds")
level.node("DistantStations", "Level", "Node")
for name, position, shape, props in DISTANT_STATIONS:
    level.add_distant_station(name, position, shape, props)


# ---- Events. ----
def offensive(name, group, next_event=None):
    props = {"script": 'ExtResource("change_behavior")', "enemy_group": f'NodePath("../../../Enemies/{group}")'}
    paths = ["enemy_group"]
    if next_event:
        props["next_event"] = f'NodePath("../{next_event}")'
        paths.append("next_event")
    level.node(name, "Level/Events", "Node", paths=paths, props=props)


level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "MakeWingedOffensive")
offensive("MakeWingedOffensive", "WingedGroup")
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "StartSurvival")
offensive("StartSurvival", "SurvivalEnemyGroup", "MakeGrenadiersOffensive")
offensive("MakeGrenadiersOffensive", "Grenadiers")
CORNERS = ("SW", "SE", "NW", "NE")
# The barge is called from out of sight, so the camera frames its dock until the carriers stand on it.
level.node("HoldCleared", "Level/Events", "Node", paths=["next_event", "groups", "checkpoint", "also_trigger"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../BargeVoyage")',
    "groups": node_paths(["../../../Enemies/SurvivalEnemyGroup", "../../../Enemies/Grenadiers"]),
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint4")',
    "also_trigger": node_paths([f"../FocusDock{c}" for c in CORNERS])})
level.node("BargeVoyage", "Level/Events", "Node", paths=["barge", "next_event"], props={
    "script": 'ExtResource("barge_voyage")', "barge": 'NodePath("../../Barge")', "next_event": 'NodePath("../ReachedIsland4")'})
# Landing on island 4: a gate with no groups, so it just sets Checkpoint5, clears any framing left over, and lets the
# second barge wait for the carriers.
level.node("ReachedIsland4", "Level/Events", "Node", paths=["next_event", "checkpoint", "also_trigger"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../BargeVoyage2")',
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint5")', "also_trigger": node_paths(["../UnfocusCamera"])})
# The gunners stand on an island the carriers can't reach, so their wave is framed: from the first leg's start
# until the second leg's.
level.node("BargeVoyage2", "Level/Events", "Node", paths=["barge", "waves", "leg_events", "next_event"], props={
    "script": 'ExtResource("barge_voyage")', "barge": 'NodePath("../../Barge2")',
    "waves": node_paths(["../../../Enemies/GunnerWave", "../../../Enemies/WingedWave"]), "board_delay_seconds": "1.5",
    "leg_events": node_paths([f"../FocusGunners{c}" for c in CORNERS] + ["../UnfocusCamera"]),
    "leg_event_legs": "PackedInt32Array(0, 0, 0, 0, 1)",
    "next_event": 'NodePath("../ReachedEndIsland")'})
# Landing on the end island: sets Checkpoint6 and lets the third barge wait for the carriers.
level.node("ReachedEndIsland", "Level/Events", "Node", paths=["next_event", "checkpoint"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../BargeVoyage3")',
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint6")'})
level.node("BargeVoyage3", "Level/Events", "Node", paths=["barge", "waves"], props={
    "script": 'ExtResource("barge_voyage")', "barge": 'NodePath("../../Barge3")',
    "waves": node_paths(["../../../Enemies/WingedPair"]), "board_delay_seconds": "1.5"})
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
# The range's mechs can't be walked to before the bridge, so the firing line frames them. Everything later comes
# to the carriers, so it gets no framing.
level.add_focus({"Range": (-5, 5, -4, -11), "Dock": (10, 16, -2, -6), "Gunners": (26, 34, 7, -3)})
level.add_end_area(55, -26)
level.add_bridge_nodes()
# Bridge 2 runs east-west: turn its platforms a quarter so the projected surface spans the gap.
EAST_WEST = "0, 0, 1, 0, 1, 0, -1, 0, 0"
for number in EAST_WEST_BRIDGES:
    for name, (cx, cz) in zip(level.platforms[number], BRIDGES[number]):
        bx, bz = world(cx, cz)
        head = f'[node name="{name}" parent="Level/Bridges" instance=ExtResource("bridge")]'
        index = next(i for i, n in enumerate(level.nodes) if n.startswith(head))
        level.nodes[index] = head + "\ntransform = " + tf(bx, BRIDGE_Y, bz, EAST_WEST)
stops = [(0.0, 0.0), (BARGE_DOCK[0] - BARGE_END[0], BARGE_DOCK[1] - BARGE_END[1]), (0.0, 0.0)]
level.node("Barge", "Level", instance="hover_barge", props={
    "transform": tf(BARGE_END[0], BRIDGE_Y + 3.0, BARGE_END[1]),
    "stops": "PackedVector3Array(" + ", ".join(f"{fmt(x)}, 0, {fmt(z)}" for x, z in stops) + ")",
    "speed": fmt(BARGE_SPEED)})
stops2 = [0.0, 0.0] + [x - BARGE2_DOCK_X for x in (BARGE2_GUNNERS_X, BARGE2_WINGED_X, BARGE2_END_X)]
level.node("Barge2", "Level", instance="hover_barge", props={
    "transform": tf(BARGE2_DOCK_X, BRIDGE_Y + 3.0, BARGE2_Z),
    "stops": "PackedVector3Array(" + ", ".join(f"{fmt(x)}, 0, 0" for x in stops2) + ")",
    "speed": fmt(BARGE_SPEED)})
stops3 = [0.0, 0.0, BARGE3_FIGHT_Z - BARGE3_DOCK_Z, BARGE3_END_Z - BARGE3_DOCK_Z]
level.node("Barge3", "Level", instance="hover_barge", props={
    "transform": tf(BARGE3_X, BRIDGE_Y + 3.0, BARGE3_DOCK_Z),
    "stops": "PackedVector3Array(" + ", ".join(f"0, 0, {fmt(z)}" for z in stops3) + ")",
    "speed": fmt(BARGE_SPEED)})
level.add_triggers((("FiringLineTrigger", 0, -2, "firing"), (T, 0, -9, "island"), (T2, 10, -12, "island3"), ("DockTrigger", 13, -5, "dock")))
wx, wz = world(0, 2)
level.add_weapon("ForkCannon", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
level.connect("enemies_defeated", GROUPS + "EnemyGroup", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "EnemyGroup", EVENTS + "OpenBridge1")
level.connect("enemies_defeated", GROUPS + "EnemyGroup", EVENTS + "UnfocusCamera")
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("enemies_defeated", GROUPS + "WingedGroup", "CheckpointManager/Checkpoint3", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "WingedGroup", EVENTS + "OpenBridge2")
level.connect("all_players_inside", AREAS + T2, EVENTS + "CloseBridge2")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup", EVENTS + "HoldCleared")
level.connect("enemies_defeated", GROUPS + "Grenadiers", EVENTS + "HoldCleared")
level.connect("all_players_inside", AREAS + "DockTrigger", EVENTS + "UnfocusCamera")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + "FiringLineTrigger", EVENTS + f"FocusRange{corner}")

level.write(sys.argv[1:])
