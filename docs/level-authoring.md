# Level authoring guide

This document explains how Arm Carriers levels are built, using `world_local.tscn` (level 1) and `world_local_level_2.tscn` (level 2) as reference implementations. Use it when creating or extending levels.

**Related docs**

- [checkpoint-save-system.md](checkpoint-save-system.md) — how checkpoint progress is saved and restored
- [camera-focal-point-events.md](camera-focal-point-events.md) — sustained camera framing during combat
- [level-completion-save-system.md](level-completion-save-system.md) — marking levels as completed

---

## What a level is

A level is a Godot scene whose root is a **`WorldLocal`** node (`src/world/world_local.gd`). It is a self-contained local co-op play space: camera, UI, players, enemies, checkpoints, terrain, scripted events, and optional weapon/music.

Levels are loaded with `change_scene_to_file()` (e.g. from the main menu). On load, `GameStateMachine` runs:

`AwaitWorldLocalReady` → `ResettingCheckpoint` → `Playing`

`ResettingCheckpoint` spawns both players and the weapon at the current checkpoint, then calls `Checkpoint.set_world_at_checkpoint_state()` to restore bridges, enemies, and trigger volumes.

---

## Scene hierarchy (required shell)

Every playable level should keep this top-level structure. Only the **`Level`** subtree and **`Enemies`** content change per level.

```
WorldLocal                          # script: world_local.gd
├── CameraFollowRig                 # script: camera_follow_rig.gd
│   └── ShakePivot                  # script: camera_shake_pivot.gd
│       └── Camera3D
├── UI                              # instance: src/world/ui/ui.tscn
├── WorldEnvironment                # sky + ambient (PanoramaSkyMaterial)
├── DirectionalLight3D
├── GameStateMachine                # instance: src/game/states/game_state_machine.tscn
├── Players                         # instance: src/world/levels/players.tscn
├── Enemies                         # Node — enemy groups go here
├── CheckpointManager               # script: checkpoint_manager.gd
│   ├── Checkpoint                  # first spawn; set as current_checkpoint
│   ├── Checkpoint2
│   └── …
├── Level                           # Node — all authored level content
│   ├── FallArea
│   ├── NavigationRegion3D
│   │   └── GridMapFloor
│   ├── Decoration / GridMapDecoration   # optional visual-only tiles
│   ├── Water                            # optional
│   ├── Events
│   ├── Bridges / bridge instances       # see “Bridges”
│   ├── Areas / area triggers            # see “Area triggers”
│   ├── EndLevelArea
│   └── Signs / Pillars / props          # optional
├── Weapon                          # optional; child is a BigWeapon scene
└── AudioStreamPlayer               # music, bus = "Music", autoplay
```

### `WorldLocal` exports

| Property | Purpose |
|----------|---------|
| `level_id` | Stable save key (e.g. scene path or short name). If empty, `scene_file_path` is used. |
| `skip_save` | When `true`, disables checkpoint save/load for test or trailer scenes. |

### What not to remove

- **`Players`** — two `PlayerLocal` instances (player 0 = shooter, player 1 = direction setter).
- **`GameStateMachine`** — drives spawn, game over, level complete, checkpoint reset.
- **`CheckpointManager`** — at least one `Checkpoint`; `current_checkpoint` must point to the start checkpoint.
- **`FallArea`** — large `Area3D` under the playable void; falling in triggers game over.

---

## Level geometry

### Walkable floor (`GridMapFloor`)

- Parent: `Level/NavigationRegion3D/GridMapFloor`
- **Mesh library:** `assets/mesh_library/tiles_Color1.tres` (level 1) or `tiles_Color7.tres` (level 2) — pick one palette per level.
- **`cell_size`:** `Vector3(2.999, 2, 2.999)` on the floor GridMap.
- **`collision_layer`:** `4`, **`collision_mask`:** `0`.
- Paint tiles in the editor; floor tiles provide player/enemy collision.

After editing the floor, **bake the navigation mesh** on `NavigationRegion3D` so enemies can pathfind. Navigation data is stored in the scene file.

### Decoration (`GridMapDecoration` or `Decoration`)

- Same mesh library as the floor.
- No collision requirement; used for props, trim, and vertical detail.
- Level 1 uses `GridMapDecoration` as a sibling of `NavigationRegion3D`; level 2 uses `Decoration`.

### Water

- Instance `src/world/elements/water.tscn` under `Level`.
- Position/scale to cover pits or rivers.

### Fall area

- `Level/FallArea` — `Area3D` with `fall_area.gd`.
- Large `BoxShape3D` under the entire playable region (below the lowest walkable surface).
- Any `PlayerLocal` entering it causes instant game over.

### Optional static props

Level 2 adds **`Level/Pillars`** — mesh + `StaticBody3D` with `collision_layer = 4` for blocking geometry. Reuse this pattern for custom obstacles.

---

## Checkpoints

Each checkpoint is a `Node3D` with `checkpoint.gd`, placed as a child of `CheckpointManager`.

### Required children

| Node | Type | Role |
|------|------|------|
| `PositionShooter` | `Marker3D` | Spawn for **player 0** (shooter / front carrier). |
| `PositionDirectionSetter` | `Marker3D` | Spawn for **player 1** (direction setter / rear carrier). |

Place markers on the ground where feet should stand. The weapon pose is derived from shoulder height (~1.35 m) between these two points on respawn.

### Checkpoint exports (world state on respawn)

When a checkpoint becomes current (or when loading saved progress), `set_world_at_checkpoint_state()` runs:

| Export | Effect |
|--------|--------|
| `events_completed` | Calls `_complete_event()` on each — bridges stay open/closed, camera focal points restored. |
| `enemy_groups_defeated` | `mark_as_defeated()` — clears enemies, marks group done. |
| `enemy_groups_reset` | `reset()` — respawns pre-placed enemies from editor snapshots. |
| `areas_to_reactivate` | `_reset()` — trigger can fire again after respawn. |
| `areas_already_activated` | `_mark_area_as_inactive()` — trigger stays spent. |
| `is_carrying_weapon` | If `false`, both players spawn without the big weapon. |

### Checkpoint progression

1. Place checkpoints along the level route (Z progression is typical).
2. Set `CheckpointManager.current_checkpoint` to the first checkpoint in the inspector.
3. Wire gameplay signals to `Checkpoint._trigger_checkpoint()` when the player earns that checkpoint (usually when an enemy group is defeated).
4. For checkpoint 2+, fill the exports above so respawning matches “everything the player already finished.”

**Rule of thumb:** each checkpoint’s exports describe the world **as if the player had just cleared the previous encounter**, not the state before it.

---

## Enemies

All groups live under `Enemies`.

### Normal enemy group (`normal_enemy_group.gd`)

Fixed set of enemies placed in the editor.

```
EnemyGroup                    # NormalEnemyGroup script
└── InstancedEnemies          # required child name
    ├── EnemyLocal            # or EnemyMage, etc.
    └── …
```

- Set **`is_offensive = false`** on enemies that should wait until triggered.
- Group **`transform`** positions the whole encounter in world space.
- Emits **`enemies_defeated`** when every `EnemyLocal` in `InstancedEnemies` is dead.
- **`trigger(true)`** sets all enemies offensive (via `change_enemies_behavior` event or direct call).
- **`reset()`** / **`mark_as_defeated()`** used by checkpoints.

### Survival enemy group (`survival_enemy_group.gd`)

Timed horde: spawns enemies for `fight_duration` seconds (default 60), then emits **`enemies_defeated`** when the timer ends and all spawned enemies are dead.

```
SurvivalEnemyGroup            # SurvivalEnemyGroup script
├── Enemies                   # spawned instances parent
├── SpawnPoints               # optional: Node3D children = point spawns
│   └── Node3D, Node3D2, …
└── SpawnPolygons             # optional: polygon spawns (see below)
    └── Node3D                # 4 child Node3D vertices = quad
```

| Export | Purpose |
|--------|---------|
| `enemy_scene` | Prefab to spawn (default `enemy_local.tscn`; level 2 uses `enemy_mage_static.tscn`). |
| `spawn_interval_curve` | Y = seconds between spawns, X = 0…1 over `fight_duration`. |
| `fight_duration` | Length of the wave in seconds. |

**Spawn polygons:** each polygon node has ≥3 child `Node3D` markers as vertices. Enemies spawn at a random point inside the quad.

Survival groups start only when **`trigger(true)`** is called (not on level load).

---

## Events (`Level/Events`)

Events are `Node` children with scripts extending **`LevelEvent`** (`src/events/level_event.gd`).

- **`trigger()`** runs `_trigger_event()`, emits `completed`, then runs **`next_event.trigger()`** if set.
- Checkpoints call **`_complete_event()`** on events listed in `events_completed` when restoring state.

### Common event types

| Script | Class / role | Notes |
|--------|----------------|-------|
| `toggle_bridge_event.gd` | `OpenBridgeEvent` | Opens or closes `BridgePlatform` instances. |
| `change_enemies_behavior.gd` | — | Calls `enemy_group.trigger(true)`. |
| `level_finished_event.gd` | `LevelFinishedEvent` | Transitions FSM to `LevelFinished`. |
| `camera_add_focal_point_event.gd` | — | Adds sustained camera focal point (see camera doc). |
| `camera_clear_focal_points_event.gd` | — | Clears focal points. |

### Bridge events (`OpenBridgeEvent`)

| Export | Typical value |
|--------|----------------|
| `platforms` | Array of `BridgePlatform` nodes to animate. |
| `event_type` | `OPEN_BRIDGE` (0) or `CLOSE_BRIDGE` (1). |
| `use_camera_focus` | `true` for first bridge of a section; `false` for closes (keeps gameplay flowing). |
| `platform_animation_stagger_seconds` | Delay between platforms (0.5 s in reference levels). |
| `next_event` | Chain another event (e.g. make next enemy group offensive). |

Open plays animation `"animate"`; close plays it backwards. `_complete_event()` snaps to `"complete"` (open) or `"bottom"` (closed).

---

## Area triggers

All extend **`EventAreaTrigger`** (`event_area_trigger.gd`). Add a `CollisionShape3D` sized to the gameplay space you want to detect.

### `AllPlayersAreaTrigger` (`all_players_area_trigger.gd`)

- Signal: **`all_players_inside`**
- Fires once when **both** players (ids 0 and 1) overlap, then disables until someone leaves and both re-enter.
- Use for: closing bridges behind the party, starting ambushes when the pair advances together.

### `SinglePlayerAreaTrigger` (`single_player_area_trigger.gd`)

- Signal: **`player_inside`**
- Fires when **any one** player enters.
- Use for: **parallel bridge** sections in level 2 — each player closes their own bridge when they cross.

### Checkpoint integration

- **`areas_to_reactivate`** — trigger can fire again after checkpoint respawn.
- **`areas_already_activated`** — trigger stays disabled after respawn (player already passed).

Level 2 groups triggers under `Level/Areas`; level 1 places them directly under `Level`. Either works; prefer `Level/Areas` for clarity.

---

## Bridges

- Instance `src/world/elements/bridge_platform.tscn` for each segment.
- Group under `Level/Bridges` (level 2) or directly under `Level` (level 1).
- Platforms start in the **closed** pose; open events animate them into place.
- Space platforms ~3 units apart along the crossing axis (see existing transforms).
- Reference **`platforms`** arrays in open/close events to the correct instances.

**Parallel bridges (co-op split path):** two bridge instances side by side (e.g. `ParallelBridge1_1` / `ParallelBridge1_2`), each with its own `SinglePlayerAreaTrigger` to close when that player crosses.

---

## Weapons

- Add a `Weapon` node at the world root.
- Instance a weapon scene (reference levels use `src/weapon/bazooka.tscn`).
- Default start position near player spawn (e.g. `(-7.89, 0.59, 0)`).
- `WorldLocal.get_active_weapon()` returns the first `BigWeapon` child.

On checkpoint reset, the weapon is placed between the two checkpoint markers with both players forced into carry state (unless `is_carrying_weapon` is false on the checkpoint).

---

## End condition

1. Place **`EndLevelArea`** (`AllPlayersAreaTrigger`) at the finish.
2. Add `Level/Events/LevelSucceeded` with `level_finished_event.gd`.
3. Connect: `EndLevelArea.all_players_inside` → `LevelSucceeded.trigger`.

`LevelFinishedEvent` only runs while the FSM is in `Playing`.

---

## Progression wiring (signal connections)

Levels are **data-driven through editor signal connections**, not hard-coded scripts. Pattern from the reference levels:

### When an enemy group is cleared

Connect **`enemies_defeated`** on the group to **both**:

1. **`CheckpointN._trigger_checkpoint`** — save progress.
2. **`OpenBridgeN.trigger`** (or other reward event) — open the path forward.

### When all players enter a forward zone

Connect **`all_players_inside`** on an area trigger to **`CloseBridgeN.trigger`** (often with `next_event` → make the *next* enemy group offensive).

### Survival / camera chains

- Close bridge → `next_event` → `MakeSurvivalGroupOffensive` (`change_enemies_behavior.gd`).
- Survival cleared → open next bridge or `FocusCamera` → `UnfocusCamera` (level 2 finale).

### Example flow (simplified level 1)

```
EnemyGroup defeated → Checkpoint2 + OpenBridge1
AllPlayersAreaTrigger entered → CloseBridge1 → MakeEnemiesGroup2Offensive
EnemyGroup2 defeated → Checkpoint3 + OpenBridge2
…
EndLevelArea → LevelSucceeded
```

### Example additions in level 2

- Parallel bridges with per-player close triggers.
- Mage enemies with `MageBehavior` child nodes under each instance.
- `FocusPoint` marker + `FocusCamera` / `UnfocusCamera` events.
- Checkpoint6 triggered by `AllPlayersAreaAfterParallelBridge1` instead of an enemy defeat.

---

## Audio and environment

Copy from a reference level:

- **Music:** `AudioStreamPlayer`, `bus = "Music"`, `autoplay = true`, volume ~`-20 dB`.
- **Sky:** `PanoramaSkyMaterial` using `assets/material/sky/panorama_image.png`.
- **Sun:** `DirectionalLight3D` with shadows enabled.

---

## Creating a new level (step by step)

1. **Duplicate** `world_local.tscn` or `world_local_level_2.tscn` → `world_local_XX.tscn` in `src/world/levels/`.
2. Set **`level_id`** on the root `WorldLocal` (use the scene path or a stable short id).
3. **Paint terrain** on `GridMapFloor`; add decoration; bake **navigation mesh**.
4. Position **FallArea** collision under the whole play space.
5. Place **checkpoints** along the route; wire `CheckpointManager.current_checkpoint` to the start.
6. Build **enemy groups** at encounter sites; set `is_offensive` appropriately.
7. Place **bridge platforms** for gaps; keep them closed by default.
8. Add **area triggers** for “party advanced” beats.
9. Author **`Level/Events`** nodes and set `platforms`, `enemy_group`, `next_event` exports.
10. **Connect signals** in the editor (see patterns above). Verify every checkpoint trigger has matching `events_completed` / enemy / area exports.
11. Place **EndLevelArea** and wire to **LevelSucceeded**.
12. Add **weapon** and **music** if needed.
13. **Playtest** from the editor: confirm spawn, checkpoint reset (pause → last checkpoint), and level complete.
14. **Register** the scene in `src/menu/menu.tscn` (level button `level_id` / `level_scene_path`).

---

## Checklist before shipping a level

- [ ] Root script is `world_local.gd`; `level_id` set.
- [ ] `CheckpointManager.current_checkpoint` points to start.
- [ ] Every checkpoint after the first has correct `events_completed`, `enemy_groups_*`, and `areas_*` exports.
- [ ] Floor GridMap has `collision_layer = 4`; navigation mesh baked.
- [ ] Fall area covers all out-of-bounds drops.
- [ ] All `NormalEnemyGroup` nodes have an `InstancedEnemies` child.
- [ ] Survival groups have `Enemies` container + spawn points or polygons + `spawn_interval_curve`.
- [ ] Bridge `platforms` arrays match real node paths.
- [ ] Close-bridge events that should chain use `next_event`.
- [ ] `EndLevelArea` → `LevelSucceeded` connected.
- [ ] Enemy defeat signals also trigger the matching checkpoint.
- [ ] Menu entry added with the correct scene path.

---

## Reference level comparison

| Aspect | `world_local.tscn` | `world_local_level_2.tscn` |
|--------|--------------------|----------------------------|
| Tile set | `tiles_Color1.tres` | `tiles_Color7.tres` |
| Enemies | `enemy_local.tscn` grunts | `enemy_mage_no_behavior.tscn` + `MageBehavior` |
| Survival spawns | `SpawnPoints` only | `SpawnPoints` + `SpawnPolygons` |
| Bridges | Sequential single path | + parallel two-lane bridges |
| Area triggers | `AllPlayersAreaTrigger` only | + `SinglePlayerAreaTrigger` for parallel lanes |
| Organization | Bridges under `Level` | `Level/Bridges`, `Level/Areas`, `Level/Pillars` |
| Camera | Bridge focus only | + `FocusCamera` / `UnfocusCamera` on finale |
| Signs | Wooden signs with `Label3D` hints | — |

Prefer the **level 2** folder layout (`Bridges`, `Areas`, `Events`) for new work; it scales better.

---

## Tips for co-op pacing

Arm Carriers is built around **two players carrying a big weapon together**. When designing encounters:

- Gate forward progress with **`AllPlayersAreaTrigger`** so both players must advance together before bridges close or hordes start.
- Use **`SinglePlayerAreaTrigger`** only when the level intentionally splits the pair (parallel bridges).
- Set early enemy groups non-offensive; flip them with **`change_enemies_behavior`** after the players commit to the arena (bridge close).
- Survival waves work well as “hold the line” moments after a bridge opens.
- Place checkpoint markers facing the next challenge; shooter marker leads, direction setter trails ~2 m behind.
