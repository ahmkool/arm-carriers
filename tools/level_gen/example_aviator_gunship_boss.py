#!/usr/bin/env python3
"""Boss fight against the aviator's gunship, on a sky station deck: world_local_aviator_gunship_boss.tscn.

A first prototype of the fight's base attacks; the platforming part (tiles, a separate barge) comes later.
The carriers start on the south rows of a square deck. Walking north wakes the gunship, which hovers off one edge of
the deck facing across it. It drifts along that edge to stay level with the carriers and fires gatling bursts,
rocket salvos (red rings mark where they land) and its nose laser, a beam straight across the deck that slides
slowly towards the carriers while it fires. Every 10 to 20 s it flies round to another edge.

Played with the fork cannon, like the sky station levels: its missiles home in on the bolts' lock.
Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (CELL, ENVIRONMENT_SKY, EVENTS, FACE_SOUTH, GROUPS, SKY_PANORAMA, TRIGGER as T, AREAS, Level,
                      checkpoint, fmt, rect, tf, world)


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z, east is +x. ----
ARENA = rounded(-3, 3, -10, -4)  # 7 x 7 cells: 21 m across
CENTRE_CELL = (0, -7)
HALF_EXTENT = 3.5 * CELL  # centre to edge
SPAWN_CELL = (0, -5)  # one row in from the south edge, outside the wake trigger
TRIGGER_CELL = (0, -8)  # the trigger covers rows -10 to -6
STANDOFF = 5.5  # how far past the edge the gunship hovers
BOSS_HP = 150
assert SPAWN_CELL in ARENA and TRIGGER_CELL in ARENA

DISTANT_STATIONS = (
    ("StationA", (-58, -32, -10), rounded(-3, 3, -2, 2), {(0, 0): ("Dome", 0), (-2, 0): ("BaseModuleB", 0), (2, 0): ("SolarRoof", 0)}),
    ("StationB", (70, -44, -64), rounded(-4, 4, -3, 3), {(0, 0): ("LandingPad", 0), (-3, 1): ("Garage", 0), (3, -1): ("EcoModule", 0)}),
    ("StationC", (-66, -44, -78), rounded(-3, 4, -4, 3), {(1, 0): ("Command", 0), (-1, -2): ("StructureTall", 0), (2, 2): ("Antenna", 0)}),
    ("StationE", (60, -36, 26), rounded(-3, 3, -3, 3), {(0, 0): ("Dome", 0), (2, -1): ("Antenna", 0)}),
)

level = Level("src/world/levels/world_local_aviator_gunship_boss.tscn", palette="space", weapon="fork_cannon",
              floor_seed=13, deco_seed=13, music="cyber_noir",
              hint="[color=#88ddff]The Aviator's Gunship[/color]\n\nWhen the red line appears, get out of its path:\n"
                   "the laser sweeps straight across the deck.\nRed rings show where rockets will land.")
# The sky station biome, as in build_sky_station_2.py.
level.environment = ENVIRONMENT_SKY + "\ntonemap_mode = 3\nglow_enabled = true\nglow_intensity = 0.45\nglow_hdr_threshold = 1.1"
level.sky_material = SKY_PANORAMA
level.sun_extra = {"light_color": "Color(1, 0.98, 0.94, 1)", "light_energy": "1.1"}
level.bridge_scene = (None, "res://src/world/elements/space/hard_light_bridge_platform.tscn")
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "arena": (21, 3, 15)}
level.extra_ext += [
    ("PackedScene", None, "res://src/world/elements/sky/cloud_layers.tscn", "clouds"),
    ("Script", None, "res://src/world/elements/sky/floating_bob.gd", "bob"),
    ("PackedScene", None, "res://src/enemy/enemy_aviator_gunship.tscn", "gunship"),
    ("Script", "uid://cmsv7oeu5se3x", "res://src/world/ui/show_boss_health_bar.gd", "show_boss_bar"),
    ("Texture2D", None, "res://assets/sprites/ui/icons/aviator_gunship_boss_icon.png", "boss_icon"),
]
level.add_shell()

# ---- The gunship waits off the north edge, facing across the deck. ----
cx, cz = world(*CENTRE_CELL)
boss_path = "Enemies/BossGroup/InstancedEnemies"
level.enemy_group("BossGroup")
level.node("EnemyAviatorGunship", boss_path, instance="gunship", props={
    "transform": tf(cx, 0, cz - HALF_EXTENT - STANDOFF, FACE_SOUTH), "is_offensive": "false"})
level.node("AviatorGunshipBehavior", f"{boss_path}/EnemyAviatorGunship", props={
    "arena_center": f"Vector3({fmt(cx)}, 0, {fmt(cz)})", "arena_half_extent": fmt(HALF_EXTENT), "standoff": fmt(STANDOFF)})
level.node("Health", f"{boss_path}/EnemyAviatorGunship", props={"max_hp": str(BOSS_HP)})

level.checkpoints([checkpoint("Checkpoint", *SPAWN_CELL, None, "BossGroup", None, T)],
                  setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_station_terrain([ARENA], {}, fall_z=cz)
level.node("CloudLayers", "Level", instance="clouds")
level.node("DistantStations", "Level", "Node")
for name, position, shape, props in DISTANT_STATIONS:
    level.add_distant_station(name, position, shape, props)

# ---- Events: walking north wakes the gunship; downing it ends the level. ----
level.offensive_event("WakeBoss", "BossGroup")
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_triggers(((T, *TRIGGER_CELL, "arena"),))
wx, wz = world(*SPAWN_CELL)
level.add_weapon("ForkCannon", tf(wx, 0.593, wz))
level.add_audio_and_hint()
level.node("ShowBossHealthBar", ".", "Node", paths=["fight_trigger", "enemy_group"], props={
    "script": 'ExtResource("show_boss_bar")',
    "fight_trigger": f'NodePath("../{AREAS}{T}")',
    "enemy_group": 'NodePath("../Enemies/BossGroup")',
    "boss_icon": 'ExtResource("boss_icon")',
    "boss_name": '"The Aviator"'})

# ---- Signals. The camera frames the gunship itself (AviatorGunshipBehavior adds it as a focal point). ----
level.connect("all_players_inside", AREAS + T, EVENTS + "WakeBoss")
level.connect("enemies_defeated", GROUPS + "BossGroup", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
