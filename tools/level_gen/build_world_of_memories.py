#!/usr/bin/env python3
"""World of Memories level prototype: world_local_world_of_memories.tscn ("World of Memories", in the Dev tab).

Prototypes the opening of the final level, inspired by Final Fantasy X's Inside Sin ("Sea of Sorrow"):
- Sweeping rose-blush, peach-ivory, and lavender-slate fantasy clouds drifting in four parallax layers directly
  beneath a semi-transparent rippled dark-teal water-glass sanctuary floor.
- Crisp obsidian-teal stone sanctuary rims with luminous aqua-silver bevels framing every outer drop-off and the
  central Cloud Well in the Court of Reflections.
- Sweeping curved spectral rune/glyph ribbons arching out of the cloud sea over the sanctuaries, rising pyrefly
  memory motes, and bobbing ruined temple echoes of past worlds suspended out in the clouds.
- Three escalating cross-world "Memory Echo" encounters across 9 m wide crystallized rune-glass bridges, ending at
  the Portal Dais leading deeper into the World of Memories:
  1. Threshold of Sorrow: dormant skeletal & dark-armored mech echoes wake as the carriers advance; clearing them
     saves Checkpoint2 and crystallizes Bridge 1.
  2. Court of Reflections: landing closes Bridge 1 and manifests Orc, Tiefling, and stationary Mage echoes around
     a 9 m x 6 m central Cloud Well; clearing them saves Checkpoint3 and crystallizes Bridge 2.
  3. Sanctum of Remembrance: landing closes Bridge 2 and triggers both the Sanctum Guardians (armored mechs and
     space robots) and a 28 s survival convergence wave; clearing both via GroupsDefeatedGate saves Checkpoint4 and
     opens Bridge 3 to the Portal Dais (EndLevelArea -> LevelSucceeded).

Run from the project root:
  python3 tools/level_gen/build_world_of_memories.py
  BAKE_PLATFORMS_UNDER=Level/Bridges BAKE_PLATFORM_ITEM=0 tools/level_gen/godot.sh bake \\
      res://src/world/levels/world_local_world_of_memories.tscn /tmp/world_of_memories_nav.json
  python3 tools/level_gen/build_world_of_memories.py /tmp/world_of_memories_nav.json --force
"""
import math
import sys

from levelgen import (AREAS, EVENTS, FACE_SOUTH, GROUPS, Level, fmt, node_paths, rect, tf, triple_bridge, world)

OUT = "src/world/levels/world_local_world_of_memories.tscn"
FLOOR_Y = -1.0


def rounded(x0, x1, z0, z1):
    """Rectangle with its four corner cells chamfered so platforms read as octagonal sanctuaries."""
    corners = {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}
    return rect(x0, x1, z0, z1) - corners


def yaw_basis(degrees, scale=1.0):
    """Row-major Transform3D basis rotated around Y by `degrees` with uniform `scale`."""
    rad = math.radians(degrees)
    c = math.cos(rad) * scale
    s = math.sin(rad) * scale
    return f"{fmt(c)}, 0, {fmt(s)}, 0, {fmt(scale)}, 0, {fmt(-s)}, 0, {fmt(c)}"


# ---- Sanctuary footprints (grid cells; forward is -z; cell x=0 centres on world x=1.5 m). ----
START_SANCTUM = rounded(-4, 4, -6, 3)
CLOUD_WELL = rect(-1, 1, -17, -16)
ECHO_COURT = rounded(-5, 5, -23, -9) - CLOUD_WELL
SANCTUM_GATE = rounded(-5, 5, -39, -26)
PORTAL_DAIS = rounded(-3, 3, -47, -42)
FLOOR = START_SANCTUM | ECHO_COURT | SANCTUM_GATE | PORTAL_DAIS

BRIDGES = {
    1: triple_bridge(-7, -8),
    2: triple_bridge(-24, -25),
    3: triple_bridge(-40, -41),
}

OPEN_RIM_EDGES = (
    {(cx, -6, "N") for cx in (-1, 0, 1)}
    | {(cx, -9, "S") for cx in (-1, 0, 1)}
    | {(cx, -23, "N") for cx in (-1, 0, 1)}
    | {(cx, -26, "S") for cx in (-1, 0, 1)}
    | {(cx, -39, "N") for cx in (-1, 0, 1)}
    | {(cx, -42, "S") for cx in (-1, 0, 1)}
)

# ---- Spawn & Checkpoints (cell coordinates). ----
SPAWN = (0, 1)
CP2_CELL = (0, -4)
CP3_CELL = (0, -21)
CP4_CELL = (0, -37)
END_CELL = (0, -45)

# ---- Colliding perimeter obelisks (cell coordinates on outer flanks, clear of central lanes & camera south). ----
OBELISK_CELLS = (
    (-4, -2), (4, -2),
    (-5, -13), (5, -13), (-5, -20), (5, -20),
    (-5, -30), (5, -30), (-5, -36), (5, -36),
    (-2, -46), (2, -46),
)

# ---- Sweeping FFX-inspired spectral glyph ribbons (name, world x, world y, world z, yaw_deg, scale). ----
GLYPH_ARCS = (
    ("ThresholdArcPrimary", 1.5, -4.6, -7.2, 14.0, 0.90),
    ("ThresholdArcCounter", 1.5, -5.2, -13.5, -18.0, 0.82),
    ("CourtArcPrimary", 1.5, -4.4, -44.0, -12.0, 1.06),
    ("CourtArcCounter", 1.5, -5.0, -52.5, 19.0, 0.90),
    ("SanctumArcPrimary", 1.5, -4.2, -94.0, 11.0, 1.10),
    ("SanctumArcCounter", 1.5, -4.8, -103.0, -16.0, 0.94),
    ("PortalCrownOuter", 1.5, -3.2, -138.0, 0.0, 0.68),
    ("PortalCrownInner", 1.5, -2.6, -139.5, 8.0, 0.50),
)

# ---- Distant floating ruin echoes suspended in the cloud sea (name, wx, wy, wz, yaw_deg, scale). ----
RUIN_ECHOES = (
    ("EchoWest1", -34.0, -10.5, -10.0, 22.0, 1.15),
    ("EchoEast1", 38.0, -12.0, -24.0, -28.0, 1.25),
    ("EchoWest2", -40.0, -13.5, -52.0, -16.0, 1.35),
    ("EchoEast2", 42.0, -9.8, -68.0, 31.0, 1.10),
    ("EchoWest3", -38.0, -11.5, -96.0, 18.0, 1.30),
    ("EchoEast3", 40.0, -13.0, -112.0, -24.0, 1.25),
    ("EchoNorthWest", -28.0, -9.5, -142.0, 34.0, 1.05),
    ("EchoNorthEast", 31.0, -9.5, -142.0, -34.0, 1.05),
)


def spawn_custom_melee(level, group, name, ext_id, cx, cz):
    wx, wz = world(cx, cz)
    level.node(name, f"Enemies/{group}/InstancedEnemies", instance=ext_id, props={
        "transform": tf(wx, 0, wz, FACE_SOUTH),
        "is_offensive": "false",
    })


def add_enemies(level):
    level.extra_ext += [
        ("PackedScene", None, "res://src/enemy/enemy_melee_mech.tscn", "melee_mech"),
        ("PackedScene", "uid://clbp8g3yu3kq5", "res://src/enemy/enemy_orc.tscn", "orc"),
        ("PackedScene", None, "res://src/enemy/enemy_tiefling.tscn", "tiefling"),
        ("PackedScene", None, "res://src/enemy/enemy_robot.tscn", "robot"),
        ("Script", None, "res://src/events/groups_defeated_gate.gd", "groups_gate"),
    ]

    # Section 1: Threshold of Sorrow — twin dark-armored golems/mechs + 3 skeletal echoes.
    level.enemy_group("ThresholdEchoes")
    spawn_custom_melee(level, "ThresholdEchoes", "ThresholdMechWest", "melee_mech", -2, -4)
    spawn_custom_melee(level, "ThresholdEchoes", "ThresholdMechEast", "melee_mech", 2, -4)
    for idx, (cx, cz) in enumerate(((-3, -3), (0, -4), (3, -3)), 1):
        level.melee("ThresholdEchoes", f"ThresholdSkeleton{idx}", cx, cz)

    # Section 2: Court of Reflections — cross-world Orc, Tiefling & stationary Mage echoes around the Cloud Well.
    level.enemy_group("CourtEchoes", spawn_on_trigger=True)
    for idx, (cx, cz) in enumerate(((-3, -15), (3, -15), (0, -19)), 1):
        spawn_custom_melee(level, "CourtEchoes", f"CourtOrc{idx}", "orc", cx, cz)
    for idx, (cx, cz) in enumerate(((-4, -18), (4, -18), (0, -21)), 1):
        spawn_custom_melee(level, "CourtEchoes", f"CourtTiefling{idx}", "tiefling", cx, cz)
    level.mage("CourtEchoes", "CourtMageWest", -3, -20, cast_max=15.0, cooldown=3.2, holds_position=True, cooldown_jitter=0.4)
    level.mage("CourtEchoes", "CourtMageEast", 3, -20, cast_max=15.0, cooldown=3.2, holds_position=True, cooldown_jitter=0.4)

    # Section 3: Sanctum of Remembrance — armored Guardians + 28 s survival convergence wave.
    level.enemy_group("SanctumGuardians", spawn_on_trigger=True)
    spawn_custom_melee(level, "SanctumGuardians", "GuardianMechWest", "melee_mech", -3, -34)
    spawn_custom_melee(level, "SanctumGuardians", "GuardianMechEast", "melee_mech", 3, -34)
    spawn_custom_melee(level, "SanctumGuardians", "GuardianRobotWest", "robot", -2, -32)
    spawn_custom_melee(level, "SanctumGuardians", "GuardianRobotEast", "robot", 2, -32)

    spawn_points = ((-4, -37), (4, -37), (0, -38), (-4, -32), (4, -32))
    level.survival_group(spawn_points, duration=28.0)
    level.nodes[-1 - len(spawn_points) - 2] += "\nmax_alive = 8"


def add_checkpoints(level):
    entries = [
        ("Checkpoint", SPAWN[0], SPAWN[1], {
            "enemy_groups_reset": [
                "../../Enemies/ThresholdEchoes",
                "../../Enemies/CourtEchoes",
                "../../Enemies/SanctumGuardians",
                "../../Enemies/SurvivalEnemyGroup",
            ],
            "areas_to_reactivate": [
                "../../Level/Areas/ThresholdTrigger",
                "../../Level/Areas/CourtLanding",
                "../../Level/Areas/SanctumLanding",
            ],
        }),
        ("Checkpoint2", CP2_CELL[0], CP2_CELL[1], {
            "events_completed": ["../../Level/Events/OpenBridge1"],
            "enemy_groups_reset": [
                "../../Enemies/CourtEchoes",
                "../../Enemies/SanctumGuardians",
                "../../Enemies/SurvivalEnemyGroup",
            ],
            "enemy_groups_defeated": ["../../Enemies/ThresholdEchoes"],
            "areas_to_reactivate": [
                "../../Level/Areas/CourtLanding",
                "../../Level/Areas/SanctumLanding",
            ],
            "areas_already_activated": ["../../Level/Areas/ThresholdTrigger"],
        }),
        ("Checkpoint3", CP3_CELL[0], CP3_CELL[1], {
            "events_completed": ["../../Level/Events/OpenBridge2"],
            "enemy_groups_reset": [
                "../../Enemies/SanctumGuardians",
                "../../Enemies/SurvivalEnemyGroup",
            ],
            "enemy_groups_defeated": [
                "../../Enemies/ThresholdEchoes",
                "../../Enemies/CourtEchoes",
            ],
            "areas_to_reactivate": ["../../Level/Areas/SanctumLanding"],
            "areas_already_activated": [
                "../../Level/Areas/ThresholdTrigger",
                "../../Level/Areas/CourtLanding",
            ],
        }),
        ("Checkpoint4", CP4_CELL[0], CP4_CELL[1], {
            "events_completed": ["../../Level/Events/OpenBridge3"],
            "enemy_groups_defeated": [
                "../../Enemies/ThresholdEchoes",
                "../../Enemies/CourtEchoes",
                "../../Enemies/SanctumGuardians",
                "../../Enemies/SurvivalEnemyGroup",
            ],
            "areas_already_activated": [
                "../../Level/Areas/ThresholdTrigger",
                "../../Level/Areas/CourtLanding",
                "../../Level/Areas/SanctumLanding",
            ],
        }),
    ]
    level.checkpoints(entries, setter_marker=(0, -0.5083), shooter_marker=(0, 2.1002))


def add_memories_scenery(level):
    """Colliding flank obelisks (baked into the navmesh), arching glyph ribbons, and cloud-sea ruin echoes."""
    level.node("Obelisks", "Level/NavigationRegion3D", "Node3D", props={"metadata/bake_walkways": "true"})
    for idx, (cx, cz) in enumerate(OBELISK_CELLS, 1):
        wx, wz = world(cx, cz)
        level.node(f"Obelisk{idx}", "Level/NavigationRegion3D/Obelisks", instance="obelisk", props={
            "transform": tf(wx, FLOOR_Y, wz),
        })

    level.node("GlyphArcs", "Level", "Node3D")
    for name, wx, wy, wz, yaw, sc in GLYPH_ARCS:
        level.node(name, "Level/GlyphArcs", instance="glyph_arc", props={
            "transform": tf(wx, wy, wz, yaw_basis(yaw, sc)),
        })

    level.node("RuinEchoes", "Level", "Node3D")
    for name, wx, wy, wz, yaw, sc in RUIN_ECHOES:
        level.node(name, "Level/RuinEchoes", instance="ruin_echo", props={
            "transform": tf(wx, wy, wz, yaw_basis(yaw, sc)),
        })

    portal_x, portal_z = world(*END_CELL)
    level.node("PortalLight", "Level", "OmniLight3D", props={
        "transform": tf(portal_x, 2.2, portal_z - 1.5),
        "light_color": "Color(0.68, 0.92, 1, 1)",
        "light_energy": "1.6",
        "omni_range": "11.0",
    })


def main():
    level = Level(
        OUT,
        palette="memories",
        weapon="sword",
        deco_seed=11,
        floor_seed=7,
        hint="[color=#b8ecff]World of Memories[/color]\n\nEchoes of fallen worlds stir above the Sea of Sorrow.",
        follow_offset="Vector3(0, 8.6, 3.8)",
        music="broken",
    )
    level.use_memories()
    level.curve = (2.8, 1.8)
    level.boxes = {
        "fall": (340, 1, 380),
        "threshold": (27, 3, 12),
        "court_landing": (33, 3, 11),
        "sanctum_landing": (33, 3, 11),
        "end": (21, 3, 9),
    }

    level.add_shell()
    level.nodes[0] += "\nskip_save = true"

    add_enemies(level)
    add_checkpoints(level)

    level.add_memories_terrain(FLOOR, OPEN_RIM_EDGES, fall_z=-68, fall_y=-17)
    add_memories_scenery(level)

    level.set_bridges(BRIDGES)
    level.offensive_event("WakeThresholdEchoes", "ThresholdEchoes")
    level.bridge_event("OpenBridge1", 1, camera_focus=False)
    level.bridge_event("CloseBridge1", 1, close=True, next_event="WakeCourtEchoes")
    level.offensive_event("WakeCourtEchoes", "CourtEchoes")

    level.bridge_event("OpenBridge2", 2, camera_focus=False)
    level.bridge_event("CloseBridge2", 2, close=True, next_event="WakeSanctumGuardians")
    level.offensive_event("WakeSanctumGuardians", "SanctumGuardians")
    level.offensive_event("WakeSurvivalWave", "SurvivalEnemyGroup")

    level.bridge_event("OpenBridge3", 3, camera_focus=False)
    level.node("SanctumClearedGate", "Level/Events", "Node", paths=["groups", "checkpoint", "next_event"], props={
        "script": 'ExtResource("groups_gate")',
        "groups": node_paths(["../../../Enemies/SanctumGuardians", "../../../Enemies/SurvivalEnemyGroup"]),
        "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint4")',
        "next_event": 'NodePath("../OpenBridge3")',
    })
    level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})

    level.add_end_area(*END_CELL)
    level.add_bridge_nodes()
    level.add_triggers((
        ("ThresholdTrigger", 0, -1, "threshold"),
        ("CourtLanding", 0, -11.5, "court_landing"),
        ("SanctumLanding", 0, -28.5, "sanctum_landing"),
    ))

    wx, wz = world(*SPAWN)
    level.add_weapon("Sword", tf(wx, 0.593, wz))
    level.add_audio_and_hint()

    # ---- Signal connections. ----
    level.connect("all_players_inside", AREAS + "ThresholdTrigger", EVENTS + "WakeThresholdEchoes")
    level.connect("enemies_defeated", GROUPS + "ThresholdEchoes", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + "ThresholdEchoes", EVENTS + "OpenBridge1")

    level.connect("all_players_inside", AREAS + "CourtLanding", EVENTS + "CloseBridge1")
    level.connect("enemies_defeated", GROUPS + "CourtEchoes", "CheckpointManager/Checkpoint3", "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + "CourtEchoes", EVENTS + "OpenBridge2")

    level.connect("all_players_inside", AREAS + "SanctumLanding", EVENTS + "CloseBridge2")
    level.connect("all_players_inside", AREAS + "SanctumLanding", EVENTS + "WakeSurvivalWave")
    level.connect("enemies_defeated", GROUPS + "SanctumGuardians", EVENTS + "SanctumClearedGate")
    level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup", EVENTS + "SanctumClearedGate")

    level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")

    level.write(sys.argv[1:])


if __name__ == "__main__":
    main()
