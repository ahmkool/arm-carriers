#!/usr/bin/env python3
"""world_playground.tscn: a small open arena for prototyping enemies and mechanics.

Not a real level: it never saves progress (skip_save) and has no end area. Drop new enemies into
Enemies/Prototype/InstancedEnemies (keep is_offensive = false so they wait for the wake trigger),
then play the scene directly from the editor (F6). Pause -> last checkpoint respawns the group.

Run from the project root; see docs/level-creation-for-agents.md for the bake / regenerate steps.
"""
import sys

from levelgen import AREAS, EVENTS, Level, checkpoint, rect, tf, world

# ---- Layout, in grid cells. Forward is -z. ----
ARENA = rect(-6, 6, -10, 3)  # about 39 x 42 m of flat ground
PIT = rect(3, 4, -8, -7)  # one small pit, to test enemies near edges, knockback and falling
FLOOR = ARENA - PIT
SPAWN = (0, 1)

level = Level("src/world/levels/world_playground.tscn", palette=1, weapon="bazooka", floor_seed=3, deco_seed=11,
              hint="[color=#88ff88]Playground[/color]\n\nStep forward together to wake the enemies.\nPause > last checkpoint brings them back.",
              music="overworld_orchestra")
level.curve = (2.0, 1.0)  # no survival group, but the scene format expects the curve
level.boxes = {"fall": (240, 1, 240), "wake": (39, 3, 9)}
level.add_shell()
# A sandbox: no save slot. level_id stays empty so the key matches the menu's (the scene path).
level.nodes[0] += '\nskip_save = true'

# ---- Enemies: the prototype group. Replace or add to these. ----
level.enemy_group("Prototype")
for i, (cx, cz) in enumerate(((-2, -7), (0, -8), (2, -6)), 1):
    level.melee("Prototype", f"EnemyLocal{i}", cx, cz)
level.mage("Prototype", "EnemyMage1", -4, -9, cast_max=14.0, cooldown=3.0)

# ---- Checkpoint: respawning resets the group and re-arms the wake trigger. ----
assert all((SPAWN[0] + d, SPAWN[1]) in FLOOR for d in (-1, 0, 1))
level.checkpoints([checkpoint("Checkpoint", *SPAWN, reset="Prototype", react="WakeTrigger")],
                  setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and events. ----
level.add_terrain(FLOOR, set(), decoration_count=25, fall_z=-4, water_x=0, water_z=-4)
level.offensive_event("WakePrototype", "Prototype")
level.add_triggers((("WakeTrigger", 0, -2, "wake"),))  # starts about 4 m ahead of the spawn, so it fires as the pair walks in
wx, wz = world(*SPAWN)
level.add_weapon("Bazooka", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
level.connect("all_players_inside", AREAS + "WakeTrigger", EVENTS + "WakePrototype")

level.write(sys.argv[1:])
