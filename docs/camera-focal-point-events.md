# Camera focal point events — design spec

This document describes how level events can add and remove **extra framing points** for the follow camera during gameplay.

**Implementation:** `camera_follow_rig.gd`, `checkpoint.gd`, `camera_add_focal_point_event.gd`, `camera_remove_focal_point_event.gd`, `camera_clear_focal_points_event.gd`.

---

## Goal

During certain combat or traversal beats, the camera should frame **both players and a specific world location** (e.g. a platform with enemies) so players can see threats they might otherwise miss off-screen.

This is **sustained gameplay framing**: players keep moving and fighting; the camera continues its normal smooth follow. It is **not** a cutscene that locks input or temporarily abandons player tracking.

**In scope (v1)**

- Three `LevelEvent` types: add a focal point, remove one focal point, clear all focal points.
- Focal points are `Node3D` references (typically `Marker3D`) placed in the level.
- `CameraFollowRig` folds those positions into the same midpoint / spread math used for players (and weapon aim markers).
- Checkpoint restore via `_complete_event()` so respawns match authored world state.

**Out of scope (v1)**

- Weighted or per-point zoom tuning (optional follow-up).
- Animated camera moves, hold timers, or input lock (use existing `run_focus_on_point()` for that).
- Tracking moving enemies directly (use a marker parented to the platform instead).
- Multiple independent “camera modes” beyond a simple list of extra nodes.

---

## How the camera works today (relevant pieces)

### Normal follow (`CameraFollowRig`)

Each frame, `_process` lerps the rig toward `compute_desired_follow_position()` unless `_cutscene_active` is true.

`compute_desired_follow_position()`:

1. Collects player `global_position` values from `../Players`.
2. If both players jointly carry the big weapon, appends aim marker positions from `WeaponSpecifics/CameraAddons`.
3. Computes `_get_midpoint(positions)` — arithmetic mean of all points.
4. Computes spread as max distance from that midpoint.
5. Applies `follow_offset` plus zoom from spread (`zoom_per_unit`, capped by `max_zoom_out`).

### Cutscene focus (`run_focus_on_point`)

Used by `OpenBridgeEvent` when `use_camera_focus` is true:

- Sets `_cutscene_active` (normal follow stops).
- Tweens to a fixed world point, holds, then lerps back.
- Paired with `GameplayInput.lock()` / `unlock()`.

### Level events

- Base class: `LevelEvent` — `trigger()` → `_trigger_event()` → `completed` → `next_event.trigger()`.
- Examples: `change_enemies_behavior.gd` (instant state flip), `toggle_bridge_event.gd` (async bridge + optional cutscene).
- Checkpoints call `_complete_event()` on `events_completed` when restoring world state after respawn or load.

### Existing precedent

Weapon aim markers are already extra positions appended before midpoint calculation when carrying. Level-driven focal points should follow the same integration point in `compute_desired_follow_position()`, not duplicate framing math in events.

---

## Problem this solves

Example beat in a level:

1. Players reach an area trigger.
2. Enemies on a **side platform** become active.
3. Without an extra focal point, the camera only frames the players; the platform may sit at the edge of or outside the view.
4. An **add** event pulls the camera midpoint toward the platform and increases spread (zoom out) so both players and the platform stay visible.
5. After the fight, a **remove** event returns framing to players-only.

This must work **during combat**, unlike bridge open sequences that pause gameplay for a camera beat.

---

## Design principles

1. **State lives on `CameraFollowRig`; events only toggle it** — Same separation as weapon camera addons vs weapon code.
2. **Node references, not stored `Vector3`** — Markers on moving platforms stay correct; invalid nodes are skipped each frame.
3. **Reuse midpoint + spread** — No second camera system; extra points join the same array as players before `_get_midpoint()`.
4. **Do not mix with cutscene focus** — `run_focus_on_point()` and `_cutscene_active` stay for one-shot cinematics; focal points apply only when cutscene mode is off.
5. **Checkpoint-safe** — On world restore, **clear** rig focal points first, then replay `events_completed` via `_complete_event()` so death respawn matches authored checkpoint state (not stale session memory).
6. **Find rig robustly** — Walk up to `WorldLocal` and resolve `CameraFollowRig` (same pattern as `level_finished_event.gd`), not fragile relative paths like `../../../CameraFollowRig`.

---

## Components to add or extend

### 1. `CameraFollowRig` — focal point list

Add internal state and a small public API:

| Method | Behavior |
|--------|----------|
| `add_focal_point(node: Node3D)` | Append if valid and not already present. |
| `remove_focal_point(node: Node3D)` | Remove one node from the list. |
| `clear_focal_points()` | Remove all. **Required** on checkpoint world restore before replaying `events_completed`. |

Private helper `_get_extra_focal_positions() -> Array[Vector3]`:

- Iterate stored nodes.
- Skip invalid instances.
- Append `global_position` for each `Node3D`.

**Integration in `compute_desired_follow_position()`** — after player positions (and weapon aim markers):

```gdscript
player_positions.append_array(_get_extra_focal_positions())
var midpoint := _get_midpoint(player_positions)
# ... spread and offset unchanged
```

No change to `_process` lerping or `run_focus_on_point()`.

### 2. `CameraAddFocalPointEvent` — new `LevelEvent`

| Field | Type | Purpose |
|-------|------|---------|
| `focal_point` | `Node3D` | Usually a `Marker3D` at platform center or enemy cluster. |

| Method | Behavior |
|--------|----------|
| `_trigger_event()` | Resolve rig → `add_focal_point(focal_point)`. Instant; no `await`. |
| `_complete_event()` | Same as trigger (restore after checkpoint). |

### 3. `CameraRemoveFocalPointEvent` — new `LevelEvent`

| Field | Type | Purpose |
|-------|------|---------|
| `focal_point` | `Node3D` | Same marker reference used by the paired add event. |

| Method | Behavior |
|--------|----------|
| `_trigger_event()` | Resolve rig → `remove_focal_point(focal_point)`. |
| `_complete_event()` | Same as trigger. |

### 4. `CameraClearFocalPointsEvent` — new `LevelEvent`

No exports. Clears every level-driven focal point on the rig (e.g. after a multi-marker beat or when remove-by-marker is awkward).

| Method | Behavior |
|--------|----------|
| `_trigger_event()` | Resolve rig → `clear_focal_points()`. |
| `_complete_event()` | Same as trigger. |

On checkpoint restore, `Checkpoint` already clears focal points before replaying `events_completed`; listing this event on a checkpoint still documents intent and re-clears if earlier entries in the list re-added markers.

### 5. Shared helper (camera events)

```gdscript
func _find_camera_rig() -> CameraFollowRig:
    var world := _find_world_local()  # walk parents for WorldLocal
    if world == null:
        return null
    return world.get_node_or_null("CameraFollowRig") as CameraFollowRig
```

Log a warning if rig or `focal_point` is missing; do not crash.

---

## Level authoring workflow

### Setup

1. Place a **`Marker3D`** (or any `Node3D`) at the focal location — e.g. child of the platform node so it moves with the platform.
2. Under `Level/Events`, add:
   - `CameraAddFocalPoint` — assign `focal_point` to the marker.
   - `CameraRemoveFocalPoint` — assign the **same** marker.
3. Wire triggers:
   - Area trigger or `next_event` chain → **add** before enemies activate.
   - `enemies_defeated`, next area, or `next_event` → **remove** when framing should end.
4. Checkpoint `events_completed`:
   - Include the **add** event on checkpoints where players can respawn **while** the focal point should still be active.
   - Include the **remove** event on later checkpoints once that beat is permanently done.

### Example chain (`world_local_level_2` style)

```text
AllPlayersAreaTrigger4.all_players_inside
  → CameraAddFocalPoint (platform marker)
  → MakeEnemiesGroup4Offensive

EnemyGroup4.enemies_defeated
  → CameraRemoveFocalPoint
  → Checkpoint7._trigger_checkpoint()
```

With `next_event` instead of parallel signal connections:

```text
AllPlayersAreaTrigger4 → CameraAddFocalPoint
  next_event → MakeEnemiesGroup4Offensive
```

---

## Lifecycle diagrams

### Add focal point during play

```
AreaTrigger / signal / previous event
  → CameraAddFocalPointEvent.trigger()
       → _trigger_event()
            → rig.add_focal_point(marker)
  → next_event.trigger() (if chained)

Each frame (cutscene inactive):
  CameraFollowRig._process
    → compute_desired_follow_position()
         → players + weapon markers + extra focal positions
         → midpoint + spread → lerp rig
```

### Remove focal point

```
enemies_defeated / area / next_event
  → CameraRemoveFocalPointEvent.trigger()
       → rig.remove_focal_point(marker)
  → camera returns to players-only framing over existing smooth speed
```

### Death respawn (`ResettingCheckpoint`)

On death or pause “Last checkpoint”, `resetting_checkpoint.gd` eventually calls `current_checkpoint.set_world_at_checkpoint_state()`:

```37:40:src/game/states/local/resetting_checkpoint.gd
func _apply_world_reset() -> void:
	var current_checkpoint = world.checkpoint_manager.current_checkpoint
	if current_checkpoint != null:
		current_checkpoint.set_world_at_checkpoint_state()
```

Focal points live in **session memory** on `CameraFollowRig` (`_extra_focal_nodes`). That list is **not** cleared automatically when players respawn. Replaying `_complete_event()` alone is not enough: if the player died mid-beat (add fired via trigger but that add event is **not** on the current checkpoint’s `events_completed`), the rig would still hold the focal point.

**Required restore sequence** — at the start of `set_world_at_checkpoint_state()` (or equivalent single entry point):

```
1. CameraFollowRig.clear_focal_points()   # drop all session-only state
2. for event in events_completed:
       event._complete_event()            # re-apply authored permanent state
```

Full pipeline:

```
ResettingCheckpoint._apply_world_reset()
  → Checkpoint.set_world_at_checkpoint_state()
       → rig.clear_focal_points()
       → for event in events_completed:
            event._complete_event()
                 → add / remove focal points per checkpoint authoring
       → enemy groups, area triggers, weapon rules (existing)
```

**Authoring rule:** `events_completed` on each checkpoint is the **source of truth** for whether a focal point should be active after respawn at that checkpoint. Same model as bridge animations and enemy group flags.

| Situation | `events_completed` at current CP | Result after respawn |
|-----------|-----------------------------------|----------------------|
| Died mid-beat; add triggered this run but not on CP yet | No add event | Normal camera (cleared, nothing re-added) |
| Respawn at CP where beat is still active | Add event listed | Focal point restored |
| Respawn at CP after beat finished | Remove event listed (or add absent) | Normal camera |

**Mid-session remove before checkpoint advance:** If remove fires during play but the next checkpoint (whose `events_completed` omits the add) has not been reached yet, death still uses the **current** checkpoint’s list — the add may re-apply. Align checkpoint boundaries with the beat (same as bridges and enemy groups), or chain remove before `_trigger_checkpoint()` on the next CP.

---

## Comparison: focal points vs cutscene focus

| | **Extra focal points (this design)** | **`run_focus_on_point` (bridges)** |
|---|--------------------------------------|-------------------------------------|
| Gameplay | Continues | Locked via `GameplayInput` |
| Camera target | Blend of players + marker(s) | Fixed world point |
| Duration | Until remove event / checkpoint | Timed hold + move out |
| `_cutscene_active` | Unchanged (false) | true during sequence |
| Best for | Ongoing combat visibility | Showcase bridge animation |

Do **not** call `run_focus_on_point()` for the platform-enemy use case.

---

## Tuning and feel

Adding a distant platform affects both **midpoint** (camera shifts toward platform) and **spread** (more zoom out). That is usually desired so players and threats stay in frame.

If framing feels too wide after implementation:

| Option | Effect |
|--------|--------|
| Move marker closer to typical player line | Less spread |
| **v2:** weight &lt; 1.0 on extra points | Softer midpoint pull |
| **v2:** use extra points for midpoint only, not spread | Tighter zoom, still shifted center |
| **v2:** cap spread contribution from focal points | Limit max zoom from off-screen markers |

Start with equal weight for all points (v1); tune in playtests.

---

## Error and edge cases

| Situation | Behavior |
|-----------|----------|
| `focal_point` unset or freed | Skip in rig; event logs warning. |
| Add same marker twice | Idempotent add (ignore duplicate). |
| Remove unknown marker | No-op. |
| Multiple add events, different markers | All active until each is removed. |
| Cutscene active (`run_focus_on_point`) | Focal list unchanged; normal follow paused anyway. |
| Player dies mid-beat (add fired, not on CP `events_completed`) | `clear_focal_points()` then replay → normal camera. |
| Player dies during active beat at CP that lists add | Clear then `_complete_event` on add → focal point restored. |
| Player dies after beat; CP lists remove (or omits add) | Clear then replay → normal camera. |
| Marker on moving platform | Works — position read each frame from node. |

---

## Testing checklist (manual)

- [ ] Add event only: camera shifts toward marker while players move; spread increases when marker is far.
- [ ] Remove event: framing returns to players-only without snap (smooth lerp).
- [ ] Add → combat → remove: full beat feels readable; enemies on platform visible.
- [ ] Die **mid-beat** (add triggered, not on current CP `events_completed`): respawn returns to normal camera.
- [ ] Die and respawn at checkpoint **with** add in `events_completed`: focal point still active.
- [ ] Respawn at checkpoint **after** remove in `events_completed`: focal point gone.
- [ ] Invalid / missing marker: no crash; console warning.
- [ ] Bridge cutscene on same level: cutscene and focal points do not conflict (cutscene ignores follow; focal list unchanged).
- [ ] Joint weapon carry + active focal point: both aim markers and level focal point contribute to midpoint.

---

## Implementation order (when coding starts)

1. **`camera_follow_rig.gd`** — `_extra_focal_nodes`, API, `_get_extra_focal_positions()`, hook in `compute_desired_follow_position()`.
2. **`checkpoint.gd`** (or shared restore helper) — `clear_focal_points()` at start of `set_world_at_checkpoint_state()` before the `events_completed` loop.
3. **`camera_add_focal_point_event.gd`** — `_find_world_local` / `_find_camera_rig`, trigger + complete.
4. **`camera_remove_focal_point_event.gd`** — same rig lookup, remove + complete.
5. **Pilot level** — one marker, add/remove events, signals, checkpoint `events_completed` aligned with beat boundaries.
6. **Playtest** — death during beat, death after beat, marker placement; note if v2 weighting is needed.

---

## Possible follow-ups (not v1)

- Per-point weight for midpoint vs spread.
- `@export var affect_spread: bool` on add event.
- Single event with `ADD` / `REMOVE` enum (designer preference).
- `CameraFollowRig` signal `focal_points_changed` for debug UI.
- Auto-remove when linked `EnemyGroup` is defeated (convenience wrapper event).

---

## Open decisions (resolve during implementation)

1. **Class names:** `CameraAddFocalPointEvent` / `CameraRemoveFocalPointEvent` vs shorter `AddCameraFocalPointEvent` — match existing `OpenBridgeEvent` / `ChangeEnemiesBehavior` naming in repo.
2. **Where to call `clear_focal_points()`:** start of `Checkpoint.set_world_at_checkpoint_state()` (recommended) so level-load restore stays consistent with death respawn.
3. **Whether remove event should use `next_event` to chain checkpoint** — follow existing level patterns (parallel signals vs chains).

---

## Files expected to touch (reference)

| Area | Files |
|------|--------|
| Camera | `src/world/camera_follow_rig.gd` |
| Checkpoints | `src/world/checkpoints/checkpoint.gd` — `clear_focal_points()` before `events_completed` loop |
| Events | `src/events/camera_add_focal_point_event.gd`, `src/events/camera_remove_focal_point_event.gd`, `src/events/camera_clear_focal_points_event.gd` |
| Levels | Scene-specific: `Marker3D`, event nodes under `Level/Events`, checkpoint `events_completed`, signal/`next_event` wiring |
| Docs | this file |

No changes required to `level_event.gd` base class.
