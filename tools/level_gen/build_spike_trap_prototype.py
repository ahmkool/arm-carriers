#!/usr/bin/env python3
"""world_spike_trap_prototype.tscn: one survival section, built to try out the closing spike walls.

Two spiked walls close in from north and south. Two wooden pressure plates sit side by side between them:
one held slows the walls, both held stops them. Skeletons come from the east while the carriers hold the plates.
When the wave is cleared, the walls pull back. Not a real level: no save slot, no end area. Dev tab only.

Run from the project root; see docs/level-creation-for-agents.md for the bake / regenerate steps.
"""
import sys

from levelgen import AREAS, EVENTS, GROUPS, Level, checkpoint, fmt, fmt_decimal, rect, tf, world

# ---- Layout, in grid cells. Enemies come from the east (+x). ----
FLOOR = rect(-3, 7, -3, 3)  # 33 x 21 m
TRAP = (0, 0)  # the plates' centre; the walls start 7.4 m north and south of it
SPAWN = (-2, 0)  # west of the plates, so the pair walks into the wake trigger
HORDE_SPAWNS = ((5, 0), (6, 0), (7, 0))  # on the trap's centre line, so a wall never closes over one

FLOOR_TOP_Y = -1.0
START_HALF_GAP = 7.4
WALL_WIDTH = 35.0  # the floor's 33 m plus an overhang at each end, so nothing slips round
FIGHT_SECONDS = 45.0

level = Level("src/world/levels/world_spike_trap_prototype.tscn", palette=1, weapon="bazooka", floor_seed=5, deco_seed=13,
              hint="[color=#ffcc66]Spike trap[/color]\n\nStand on the wooden plates to slow the walls.\nBoth plates held stops them.",
              music="rising_tension")
level.curve = (2.6, 1.1)  # seconds between skeletons, from the start of the wave to its end
level.boxes = {"fall": (240, 1, 240), "wake": (7, 3, 8)}
level.extra_ext += [("Script", None, "res://src/world/elements/trap/spike_trap.gd", "spike_trap"),
                    ("Script", None, "res://src/events/spike_trap_event.gd", "spike_trap_event")]
level.add_shell()
level.nodes[0] += '\nskip_save = true'

# ---- Enemies: a timed wave of skeletons from the east. ----
level.survival_group(HORDE_SPAWNS, FIGHT_SECONDS)

# ---- Checkpoint: respawning resets the wave and re-arms the wake trigger. The trap resets itself. ----
assert SPAWN in FLOOR and all(cell in FLOOR for cell in HORDE_SPAWNS)
level.checkpoints([checkpoint("Checkpoint", *SPAWN, reset="SurvivalEnemyGroup", react="WakeTrigger")],
                  setter_marker=(1.0, 0), shooter_marker=(-1.9, 0))  # in line east-west: the bazooka fires east

# ---- Terrain, trap and events. ----
level.add_terrain(FLOOR, set(), decoration_count=10, fall_z=0, water_x=0, water_z=0)
tx, tz = world(*TRAP)
floor_x0, floor_x1 = world(-3, 0)[0] - 1.5, world(7, 0)[0] + 1.5
level.node("SpikeTrap", "Level", "Node3D", props={
    "transform": tf(tx, FLOOR_TOP_Y, tz), "script": 'ExtResource("spike_trap")',
    "start_half_gap": fmt_decimal(START_HALF_GAP), "wall_width": fmt_decimal(WALL_WIDTH),
    "wall_offset_x": fmt((floor_x0 + floor_x1) / 2 - tx)})
level.node("StartTrap", "Level/Events", "Node", paths=["trap", "next_event"], props={
    "script": 'ExtResource("spike_trap_event")', "trap": 'NodePath("../../SpikeTrap")', "next_event": 'NodePath("../WakeHorde")'})
level.offensive_event("WakeHorde", "SurvivalEnemyGroup")
level.node("RetractTrap", "Level/Events", "Node", paths=["trap"], props={
    "script": 'ExtResource("spike_trap_event")', "trap": 'NodePath("../../SpikeTrap")', "action": "1"})
level.add_triggers((("WakeTrigger", *TRAP, "wake"),))  # covers the plates; the spawn is outside it
wx, wz = world(*SPAWN)
level.add_weapon("Bazooka", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
level.connect("all_players_inside", AREAS + "WakeTrigger", EVENTS + "StartTrap")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup", EVENTS + "RetractTrap")

level.write(sys.argv[1:])
