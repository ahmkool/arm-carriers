# Level completion save system — implementation plan

This document describes how persistent **level completion** markers will be added to **Arm Carriers**. It is a design spec only; no implementation code yet.

Completion is separate from checkpoint progress (see [checkpoint-save-system.md](checkpoint-save-system.md)): checkpoints remember *furthest reached*; completion remembers *level beaten*.

---

## Goal

When players finish a level (win condition fires → return to menu), remember that the level was **completed**. On the main menu level picker (`menu.tscn` / `level_button.gd`), completed levels show a visible mark (e.g. checkmark suffix or icon).

**In scope (v1)**

- One save file per machine / user profile (local co-op shares one progress record — same as checkpoints).
- Per-level boolean: level identifier → completed.
- Persist when the **`LevelFinished`** game state is entered.
- Read on menu level button setup and show completion indicator.
- Reuse the existing **`GameSave`** autoload and **`user://save.json`** file (extend schema, do not add a second save file).

**Out of scope (v1)**

- Cloud saves, multiple save slots, per-player completion.
- Inferring completion from “reached last checkpoint” (checkpoint ≠ win).
- Completion time, score, rank, or star ratings.
- Unlocking levels based on completion (menu shows all levels; mark is cosmetic only).
- Clearing completion when replaying “from beginning” (completion is sticky once earned).

---

## How the game works today (relevant pieces)

### Level win flow

- Levels wire a win trigger to **`LevelFinishedEvent`** (scene nodes are often named `LevelSucceeded` or `LevelFinishedEvent`; all use the same script).
- **`LevelFinishedEvent._trigger_event()`** transitions **`GameStateMachine`** to **`"levelfinished"`** only while the current state is **`Playing`**.
- **`level_finished.gd`** (`LevelFinished` state) shows “Level Complete”, waits, fades to black, and calls **`SessionFlow.go_to_main_menu()`**.

### Menu level picker

- **`level_button.gd`** is attached to each level row in **`menu.tscn`**.
- Each button has **`level_scene_path`** (scene or UID) and optional **`level_id`**.
- On press, **`SessionFlow.request_level(level_scene_path, level_id)`** resolves the level id (explicit `level_id`, else `level_scene_path`) and loads the level.

### Existing checkpoint saves

- **`GameSave`** autoload already loads/writes **`user://save.json`** with a **`levels`** map (level id → checkpoint id).
- **`WorldLocal.get_level_id()`** returns exported **`level_id`** or falls back to **`scene_file_path`**.
- **`WorldLocal.skip_save`** skips checkpoint apply and checkpoint tracking for test scenes.

### Implication for completion

- Completion must use the **same canonical `level_id` string** as checkpoint saves and menu buttons, or the menu mark will not match what was saved during play.
- The write point should be **`level_finished.gd`**, not individual level event nodes — one central hook for all levels that use the standard win FSM state.

---

## Design principles

1. **Stable string IDs, not node references** — Same convention as checkpoints; only `level_id` strings are stored on disk.
2. **Persistence stays in `GameSave`; gameplay stays elsewhere** — `LevelFinished` calls into the autoload; `level_button.gd` only queries and renders.
3. **Completion ≠ checkpoint progress** — Reaching a late checkpoint without beating the level does not mark complete. Beating the level marks complete regardless of which checkpoint the player continued from.
4. **Idempotent writes** — Calling `mark_level_completed` when already completed is a no-op (no redundant disk writes).
5. **Extend one save file** — Add a `completed` section to the existing JSON; bump `version` when the schema changes.
6. **Respect `skip_save`** — Test/debug levels with `WorldLocal.skip_save` do not write completion.

---

## Components to add or extend

### 1. `GameSave` autoload — completion API

Extend the existing singleton (checkpoint code stays unchanged):

| Task | Detail |
|------|--------|
| In-memory cache | Hold `level_id → bool` completion map alongside `_levels`. |
| Load on startup | Read `completed` section from `user://save.json` (default `{}` if missing — backward compatible with v1 saves). |
| Query | `is_level_completed(level_id: String) -> bool` |
| Write | `mark_level_completed(level_id: String) -> void` then `save_to_disk()` if newly completed |
| Clear | `clear_level_completion(level_id: String)`; extend `clear_all()` to clear both `_levels` and `_completed` |
| Optional | `clear_level(level_id)` could also clear completion for that level (decide during implementation; useful for debug) |

`save_to_disk()` must persist both `levels` and `completed`. `SAVE_VERSION` bumps to **2** when `completed` is added.

The autoload does **not** need to listen to signals for completion — a single explicit call from `LevelFinished.enter()` is enough.

### 2. Level identity — shared with checkpoints

Use the same rules documented in [checkpoint-save-system.md](checkpoint-save-system.md):

- **Preferred:** explicit `@export var level_id` on **`WorldLocal`** and matching **`level_id`** on each **`LevelButton`** in `menu.tscn`.
- **Fallback at runtime:** `WorldLocal.scene_file_path`.
- **Fallback in menu:** `level_scene_path` when `level_id` is empty (`SessionFlow.request_level` already does this).

**Convention:** Menu buttons, `WorldLocal`, and save keys must use the **same** string. Example: `"res://src/world/levels/world_local.tscn"`.

**Known gap today:** Some menu buttons use UID-only `level_scene_path` and leave `level_id` empty. Runtime completion will be saved under `scene_file_path`, which will **not** match a UID key. Content pass: set explicit `level_id` on every shippable button and matching `WorldLocal` scene.

**Optional helper (recommended):** small shared resolver used by `SessionFlow`, `level_button.gd`, and docs:

```gdscript
static func resolve_level_id(level_scene_path: String, level_id: String) -> String:
	if not level_id.is_empty():
		return level_id
	return level_scene_path
```

### 3. Write completion — `level_finished.gd`

In **`LevelFinished.enter()`**, before the message/fade sequence:

1. Cast `world` to **`WorldLocal`**.
2. If `skip_save`, return.
3. Call `world.get_level_id()`; if empty, log warning and return.
4. Call **`GameSave.mark_level_completed(level_id)`**.

**Why here, not `LevelFinishedEvent`:**

- All levels funnel through one FSM state regardless of scene node naming.
- `world` is already available on **`GameState`**.
- Save happens immediately on win, not after fade or menu reload (safe if the player force-quits during the congratulations screen).

**Do not write** when:

- `WorldLocal.skip_save` is true.
- `level_id` resolves to empty.
- Game state is not actually `LevelFinished` (event already guards `Playing` before transition).

### 4. Display completion — `level_button.gd`

Extend the button script:

| Task | Detail |
|------|--------|
| Store base label | Save `text` in `_ready()` as `_base_text` before appending indicators. |
| Resolve id | Same logic as `SessionFlow` / shared helper. |
| Query | `GameSave.is_level_completed(resolved_id)` |
| Render v1 | Append suffix to text (e.g. `" ✓"`) or toggle a child `Label` / `TextureRect` if added in `menu.tscn` |

Call refresh from **`_ready()`** — sufficient because returning from a level reloads `menu.tscn` via `change_scene_to_file`. If the menu scene is ever kept alive across level loads, also refresh from **`MainMenuState.enter()`**.

**v1 UI recommendation:** text suffix (`completed_indicator` export, default `" ✓"`) — no scene changes required. Icon/badge can be a follow-up polish pass.

### 5. Menu content — `menu.tscn`

No structural changes required for v1 text suffix.

**Content pass:** ensure every visible level button has a correct **`level_id`** matching its `WorldLocal` scene (see checkpoint doc). Buttons without `level_id` today:

| Button | Notes |
|--------|--------|
| `TestSwordLevelButton` | Falls back to scene path — OK if path matches runtime `scene_file_path`. |
| `SawCarryButton` | UID-only path — **set explicit `level_id`**. |
| `TrailerSceneButton` | No `level_id` — set explicit `level_id`. |
| Hidden test levels | Lower priority; still set ids if they should show completion in dev builds. |

---

## On-disk format (v2)

**Path:** `user://save.json` (same file as checkpoints)

**Shape (conceptual):**

```json
{
  "version": 2,
  "levels": {
    "<level_id>": "<checkpoint_id>"
  },
  "completed": {
    "<level_id>": true
  }
}
```

Examples of `level_id`:

- `"res://src/world/levels/world_local.tscn"`
- or a short stable id if `WorldLocal.level_id` and menu buttons are configured to use it

**Migration from v1:**

- If `completed` key is missing, treat as empty dict.
- Existing `levels` data is preserved unchanged.

**Write policy:** save immediately when a level is newly marked complete (single write per first clear; idempotent thereafter).

---

## Lifecycle diagrams

### Cold start (game launch)

```
GameSave._ready()
  → load user://save.json
  → populate _levels and _completed (or empty defaults)
```

### Beat level

```
LevelFinishedEvent.trigger()  [end area / survival clear / etc.]
  → GameStateMachine.transition_to("levelfinished")
  → LevelFinished.enter()
       → GameSave.mark_level_completed(world.get_level_id())
       → show message, fade, SessionFlow.go_to_main_menu()
```

### Menu shows completion mark

```
menu.tscn loads (or MainMenuState.enter)
  → each LevelButton._ready()
       → resolve level_id
       → GameSave.is_level_completed(level_id)
       → update text / icon
```

### Replay level (checkpoint continue or from beginning)

```
Player picks level again
  → checkpoint restore may apply (unchanged)
  → completion flag unchanged (still true)
  → menu still shows mark after next win or on return
```

### Clear progress (debug / future “New game”)

```
GameSave.clear_all()
  → clear _levels and _completed
  → rewrite save.json
  → menu shows no completion marks
```

---

## Relationship to checkpoint saves

| Concern | Checkpoint save | Completion save |
|---------|-----------------|-----------------|
| Meaning | Furthest checkpoint reached | Level beaten (win) |
| Write trigger | `checkpoint_changed` (ahead only) | `LevelFinished.enter()` |
| Read trigger | `CheckpointManager._ready` | `level_button.gd` on menu |
| Affected by death / pause restart | No disk write | N/A |
| Affected by “from beginning” | Skips apply for that load only | No change to completion flag |
| `skip_save` levels | Skipped | Skipped |

A player can have checkpoint progress **without** completion (quit mid-level) or completion **with** any checkpoint state (beat level, replay from start).

---

## Error and edge cases

| Situation | Behavior |
|-----------|----------|
| No save file | All levels show as not completed. |
| v1 save file (no `completed` key) | Treat as no completions; load `levels` as today. |
| `level_id` mismatch (menu UID vs runtime scene path) | Menu never shows mark; fix ids in content pass. |
| Empty `level_id` at win time | Log warning; do not write completion. |
| `skip_save` test level | No completion written. |
| Beat level, force-quit during fade | Completion already written in `enter()` — mark persists. |
| Beat same level again | Idempotent; no extra writes. |
| Corrupt JSON | Log error; start with empty progress (do not crash). |
| `clear_level` checkpoint only | Completion may remain unless `clear_level` is extended to clear both (decide in implementation). |

---

## Testing checklist (manual)

- [ ] Fresh install: no completion marks on menu.
- [ ] Beat Level 1: mark appears after return to menu.
- [ ] Quit and relaunch game: mark still present.
- [ ] Reach mid-level checkpoint, quit without winning: no mark.
- [ ] Beat level, replay “from beginning”: mark remains.
- [ ] Beat level, die, “Last checkpoint”, finish again: mark still present (no duplicate write errors).
- [ ] Two levels: completing A does not mark B.
- [ ] `skip_save` test scene: no completion written; no mark after fake win (if win is reachable).
- [ ] v1 save file upgrades cleanly (checkpoint data preserved, `completed` defaults empty).
- [ ] `clear_all()`: marks and checkpoints both cleared.

---

## Implementation order (when coding starts)

1. **`GameSave`** — `_completed` map, load/save `completed` section, bump version, query/mark/clear API, update `clear_all()`.
2. **`level_finished.gd`** — call `mark_level_completed` in `enter()` with `skip_save` guard.
3. **`level_button.gd`** — resolve id, refresh completion visual in `_ready()`.
4. **Content pass** — set matching `level_id` on menu buttons and `WorldLocal` scenes (priority: visible shippable levels).
5. **Optional polish** — checkmark icon node in `menu.tscn`, refresh from `MainMenuState.enter()` if needed.

---

## Possible follow-ups (not v1)

- Unlock levels sequentially based on completion of previous level.
- Separate “best time” or rating per level in save file.
- Completion percentage on main menu header.
- Per-slot completion when multiple save slots exist.
- Clear completion independently of checkpoint progress in a debug menu.

---

## Open decisions (resolve during implementation)

1. **`clear_level` behavior** — Should erasing checkpoint progress for one level also erase its completion flag? Recommend **yes** for debug symmetry; menu “new game” uses `clear_all()` only.
2. **Menu visual** — Text suffix vs icon child node (v1: suffix; icon as polish).
3. **Shared `resolve_level_id` helper** — New static on `GameSave`, small util script, or duplicate one-liner in `level_button` and `SessionFlow` (recommend centralizing to avoid drift).
4. **Whether to emit a signal** — e.g. `GameSave.level_completed(level_id)` for future achievements UI (optional; not required for v1).

---

## Files expected to touch (reference)

| Area | Files |
|------|--------|
| Autoload | `src/autoload/game_save.gd` |
| Win state | `src/game/states/local/level_finished.gd` |
| Menu | `src/menu/level/level_button.gd`, `src/menu/menu.tscn` (content: `level_id` exports) |
| World (content) | shippable `WorldLocal` level scenes — `level_id` export |
| Session (optional) | `src/session/session_flow.gd` — shared id resolver |
| Docs | this file, cross-link in `checkpoint-save-system.md` if desired |

No changes required to `LevelFinishedEvent`, `CheckpointManager`, or `resetting_checkpoint.gd` for v1.
