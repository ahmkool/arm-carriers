# Checkpoint save system — implementation plan

This document describes how persistent checkpoint progress will be added to **Arm Carriers**. It is a design spec only; no implementation code yet.

---

## Goal

For each playable level (e.g. `world_local.tscn`), remember the **furthest checkpoint** the players have reached. When they return to that level (from the menu or a future “Continue” flow), spawn and world state should match that checkpoint—using the same pipeline as an in-session “restart at checkpoint.”

**In scope (v1)**

- One save file per machine / user profile (local co-op shares one progress record).
- Per-level mapping: level identifier → checkpoint identifier.
- Restore on level load before the first checkpoint reset runs.
- Save when the player earns a new checkpoint during gameplay.

**Out of scope (v1)**

- Cloud saves, multiple save slots, per-player progress.
- Serializing individual enemies, bridges, or transforms (checkpoint nodes already encode that via `set_world_at_checkpoint_state()`).
- Saving mid-combat state, inventory, or weapon choice beyond what checkpoints already define.

---

## How the game works today (relevant pieces)

### Checkpoints

- Each level scene that uses this system has a **`CheckpointManager`** with multiple **`Checkpoint`** children.
- `CheckpointManager.current_checkpoint` is the active respawn point.
- Progress advances through **`CheckpointManager.set_current_checkpoint()`**, which emits **`checkpoint_changed`**.
- Checkpoints are triggered from level wiring (e.g. enemy group defeated → `_trigger_checkpoint()`, or trigger volumes).
- Each **`Checkpoint`** can carry authored world state: completed events, defeated/reset enemy groups, area trigger flags, weapon-carry rules. Applying that state is **`Checkpoint.set_world_at_checkpoint_state()`**.

### Level load and respawn

- Levels are **`WorldLocal`** scenes loaded with **`change_scene_to_file()`** (e.g. from `level_button.gd`).
- On load, **`GameStateMachine`** runs: **`AwaitWorldLocalReady`** → **`ResettingCheckpoint`** → **`Playing`**.
- **`ResettingCheckpoint`** reads `world.checkpoint_manager.current_checkpoint`, moves players and weapon to spawn markers, then calls **`set_world_at_checkpoint_state()`** on that checkpoint.
- **`Players`** also reads the manager’s spawn transform when adding or resetting players.

### Implication for saves

Whatever checkpoint should be used on “continue” must already be set on **`CheckpointManager.current_checkpoint`** before **`ResettingCheckpoint.enter()`** runs. No separate spawn path is needed if restore happens early enough in the level boot sequence.

---

## Design principles

1. **Stable string IDs, not node references** — Scene instances and object IDs change every load; only level id and checkpoint id are stored on disk.
2. **Gameplay stays in checkpoint code; persistence stays in one autoload** — `CheckpointManager` does not read or write files.
3. **Reuse existing reset logic** — Load save → set `current_checkpoint` → existing FSM and `ResettingCheckpoint` do the rest.
4. **Furthest progress, not session rewind** — Disk save advances when the player reaches a checkpoint that is **ahead** of what was saved; dying and using pause “Last checkpoint” does not rewrite the save file.
5. **Small, debuggable v1** — A single JSON file under `user://` is enough until requirements grow.

---

## Components to add or extend

### 1. `GameSave` autoload

A singleton (same pattern as `ScreenFade`, `GameplayInput`) responsible for:

| Task | Detail |
|------|--------|
| Load on startup | Read `user://save.json` (or create empty structure if missing). |
| In-memory cache | Hold level → checkpoint map while the game runs. |
| Query | `get_saved_checkpoint(level_id) -> String` |
| Write | `set_saved_checkpoint(level_id, checkpoint_id)` then persist |
| Apply to level | `apply_to_manager(manager, level_id)` — resolve id and set manager’s current checkpoint |
| Clear | `clear_all()` or `clear_level(level_id)` for “New game” / debug |

The autoload does **not** need to know about `WorldLocal` internals beyond receiving a level id string and a `CheckpointManager` reference.

### 2. Level identity — `WorldLocal`

Add an optional exported **`level_id`** string on **`WorldLocal`** (e.g. `"world_local"`, `"world_local_03"`).

- **Preferred id:** explicit `level_id` (stable if scene files are renamed).
- **Fallback:** `scene_file_path` from the running scene (matches what `level_button.gd` already uses via `level_scene_path`).

`CheckpointManager` (or `WorldLocal` in `_ready`) passes this id into `GameSave` when applying progress.

**Convention:** Menu buttons and save keys must use the **same** string. If buttons use `res://src/world/levels/world_local.tscn`, either save with that path or set `level_id` on the scene and use that everywhere.

### 3. Checkpoint identity — `Checkpoint`

Add an optional exported **`checkpoint_id`** string on each **`Checkpoint`** (e.g. `"start"`, `"after_bridge_1"`).

- **Preferred id:** explicit `checkpoint_id` (stable if node names like `Checkpoint4` change in the editor).
- **Fallback for unmigrated scenes:** use the node **`name`** (`Checkpoint`, `Checkpoint2`, …) so existing levels work without immediate scene edits.

`CheckpointManager` gains a resolver: given a string id, return the matching `Checkpoint` from its internal `_checkpoints` list (match `checkpoint_id` first, then `name` during migration).

### 4. Checkpoint ordering — furthest-only saves

To avoid overwriting progress when a checkpoint is set “backward” (unlikely today, but possible with triggers or debug), only persist when the new checkpoint is **ahead** of the saved one.

**Recommended v1 approach:** `@export var order: int` on each `Checkpoint` (0 = start, higher = further in the level). Compare numeric order when handling `checkpoint_changed`.

**Alternatives (documented, not chosen for v1):**

- Order = child index under `CheckpointManager` (fragile if nodes are reordered in the scene tree).
- Explicit `@export var checkpoint_sequence: Array[Checkpoint]` on the manager (verbose but very clear in the editor).

If order is equal or the new checkpoint is behind the saved one, skip the disk write.

### 5. `CheckpointManager` extensions

Minimal API additions:

- **`get_checkpoint_by_id(id: String) -> Checkpoint`** — lookup for restore.
- **`apply_saved_checkpoint(id: String) -> void`** — resolve id, set `current_checkpoint` (see silent apply below).
- Optional: expose read-only access to checkpoint list or order for `GameSave` comparisons.

**Restore vs gameplay set**

When loading from disk at level start, we should **not** treat restore as “player reached a new checkpoint” (no save write, and optionally no `checkpoint_changed` side effects if anything listens later).

Options (pick one during implementation):

- **A.** `set_current_checkpoint_silent(checkpoint)` — assigns `current_checkpoint` only.
- **B.** `GameSave` sets `current_checkpoint` directly with a `_loading` flag on the autoload so `checkpoint_changed` handlers ignore the event.
- **C.** Emit `checkpoint_changed` on restore anyway, but autoload ignores saves while `_applying_save` is true.

Recommendation: **A or B** — clearest separation between boot restore and gameplay progression.

### 6. Wiring `checkpoint_changed` → disk

When a level is active:

1. After `CheckpointManager` is ready and save has been applied, connect **`checkpoint_changed`** to a `GameSave` handler (connection owned by autoload or by manager calling into autoload—avoid duplicate connections on reload).
2. On signal: compute level id from parent `WorldLocal`, compare order of new vs previously saved checkpoint, update map and **`save_to_disk()`** if ahead.

On level exit (`tree_exiting` on manager or world): disconnect to avoid stale references.

**Do not save** when:

- Applying save on level load (silent restore).
- Player uses pause **“Last checkpoint”** / death restart within the same session (uses in-memory `current_checkpoint` only).
- Checkpoint id cannot be resolved (log warning, keep previous save).

---

## On-disk format (v1)

**Path:** `user://save.json`

**Shape (conceptual):**

```json
{
  "version": 1,
  "levels": {
    "<level_id>": "<checkpoint_id>"
  }
}
```

Examples of `level_id`:

- `"res://src/world/levels/world_local.tscn"`
- or `"world_local"` if using exported `level_id`

Examples of `checkpoint_id`:

- `"after_survival_2"` (explicit)
- or `"Checkpoint6"` (fallback from node name)

**Version field** allows future migrations if the schema changes (e.g. adding settings or multiple slots).

**Write policy:** save immediately on each qualifying checkpoint advance (simple, fine for small JSON). Debouncing is optional if writes become frequent later.

---

## Lifecycle diagrams

### Cold start (game launch)

```
GameSave._ready()
  → load user://save.json into memory (or empty dict)
```

### Enter level from menu

```
change_scene_to_file(level.tscn)
  → WorldLocal + subtree _ready()
  → CheckpointManager._ready()
       → _refresh_checkpoints()
       → GameSave.apply_to_manager(manager, level_id)
            → read saved checkpoint_id (if any)
            → manager.apply_saved_checkpoint(id)  [silent]
       → existing fallback: if current_checkpoint still null, first checkpoint
  → GameStateMachine: AwaitWorldLocalReady
  → ResettingCheckpoint (uses restored current_checkpoint)
  → Playing
  → GameSave connects to checkpoint_changed
```

### Earn checkpoint during play

```
_trigger_checkpoint() / set_current_checkpoint()
  → checkpoint_changed emitted
  → GameSave: if new order > saved order for this level
       → update memory + write save.json
```

### Pause “Last checkpoint” / fall death (same session)

```
restart_game() → ResettingCheckpoint
  → uses in-memory current_checkpoint only
  → does NOT update save file
```

### New game / clear progress (future menu)

```
GameSave.clear_level(level_id) or clear_all()
  → rewrite save.json
  → next level load starts from default / first checkpoint
```

---

## Scene and content work (after code exists)

1. Set **`level_id`** on each shippable `WorldLocal` scene (or standardize on scene path in menu + save).
2. Gradually add **`checkpoint_id`** and **`order`** on checkpoints in priority levels (`world_local`, `world_local_03`, etc.).
3. Until migration is done, saves will use node **names** and implicit order exports defaulting from editor order or manual `order` values.

**Editor defaults:** Scenes currently set `current_checkpoint` in the `.tscn` (e.g. `Checkpoint4` for dev). After save exists, that value is only a fallback when **no** save entry exists for the level—not the continue point for returning players.

---

## Error and edge cases

| Situation | Behavior |
|-----------|----------|
| No save file | Treat all levels as never played; manager uses first checkpoint / scene default. |
| Unknown `checkpoint_id` in save | Log warning; ignore entry; use first checkpoint or scene default. |
| Renamed checkpoint in level | Old save id misses lookup until content migration or alias map (out of v1). |
| Renamed level scene | Same as unknown level unless `level_id` export is stable. |
| Test / debug scenes | Optional: empty `level_id` or flag to skip save apply and save writes. |
| Corrupt JSON | Log error; start with empty progress (do not crash). |

---

## Testing checklist (manual)

- [ ] Fresh install: level starts at first checkpoint; no save file errors.
- [ ] Reach checkpoint 3, quit game, reload level: spawn and world state match checkpoint 3 (events/enemies as authored on that checkpoint).
- [ ] Reach checkpoint 5, die, “Last checkpoint”: respawn at 5 in-session; save still 5.
- [ ] Reach checkpoint 5, do not advance, quit, reload: still 5.
- [ ] Two levels: progress in level A does not affect level B.
- [ ] Clear save / new game: level starts from beginning.
- [ ] Missing checkpoint id in save after level edit: graceful fallback + warning in console.

---

## Implementation order (when coding starts)

1. **`GameSave` autoload** — load/save JSON, in-memory map, clear API.
2. **`Checkpoint.get_checkpoint_id()`** helper (export + name fallback) and **`Checkpoint.order`**.
3. **`CheckpointManager`** — `get_checkpoint_by_id`, silent apply, apply save in `_ready` after refresh.
4. **`WorldLocal.level_id`** + pass into apply.
5. **Connect `checkpoint_changed`** with furthest-only logic and disconnect on exit.
6. **Menu / debug** — optional clear save; document which `level_id` each level button uses.
7. **Content pass** — explicit ids and order on main levels.

---

## Possible follow-ups (not v1)

- Multiple save slots.
- “Continue” button that picks last played level from save metadata (`last_level_id`, `last_played_at`).
- Encrypt or checksum save file (only if needed).
- Steam / platform cloud via wrapper around the same `GameSave` API.
- Save slot UI and autosave debounce.

---

## Open decisions (resolve during implementation)

1. **Canonical level key:** scene path vs short `level_id` string — recommend **`level_id` export** with menu buttons updated to match.
2. **Silent restore mechanism:** `set_current_checkpoint_silent` vs autoload `_applying_save` flag.
3. **Whether restore should emit `checkpoint_changed`** for systems that might subscribe later (default: no, unless something needs it).

---

## Files expected to touch (reference)

| Area | Files |
|------|--------|
| Autoload | `src/autoload/game_save.gd`, `project.godot` |
| Checkpoints | `checkpoint.gd`, `checkpoint_manager.gd` |
| World | `world_local.gd` |
| Menu (later) | `level_button.gd`, main menu scenes |
| Docs | this file |

No changes required to `resetting_checkpoint.gd` for v1 if restore runs before its first `enter()`.
