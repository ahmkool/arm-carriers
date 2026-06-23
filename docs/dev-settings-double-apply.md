# Dev settings — double HP apply on respawned enemies

This document explains why `DevSettings.apply_to_health()` can run **twice** for the same logical enemy (e.g. the skeleton boss), and why HP multipliers can stack incorrectly on the second pass.

**Related code:** `src/autoload/dev_settings.gd`, `src/components/health.gd`, `src/enemy/normal_enemy_group.gd`

---

## Symptom

With `boss_hp_multiplier = 0.5` and a boss whose scene `max_hp` is 30, you may see logs like:

```
Applied boss HP multiplier to 15
PlayerLocal ready, device_id: 0
PlayerLocal ready, device_id: 1
Applied boss HP multiplier to 8
```

The boss ends up at **8 HP** instead of the expected **15**.

The same pattern applies to regular enemies under `NormalEnemyGroup` when `enemy_hp_multiplier` is not `1.0`.

---

## What is actually happening

This is **not** one `Health` node applying dev settings twice in a single `_ready()`. It is **two separate enemy instances**, each running `Health._ready()` once:

| Pass | When | Instance | Typical result (0.5× on 30 HP boss) |
|------|------|----------|--------------------------------------|
| 1st | Level load | Boss placed in the scene under `NormalEnemyGroup/InstancedEnemies` | 30 → 15 |
| 2nd | Checkpoint respawn | New boss cloned from `NormalEnemyGroup` snapshot | 15 → 8 |

Players appearing **between** the two passes is expected: the boss is part of the level and loads before you press start to spawn players. The second pass usually happens after a **checkpoint reset** (e.g. after dying and entering `resettingcheckpoint`).

---

## Call chain

### First apply — level load

1. Boss is authored in the level scene (e.g. `world_boss_scene.tscn`).
2. `Health._ready()` runs and calls `DevSettings.apply_to_health(self)`.
3. Dev multiplier is applied; `max_hp` becomes 15.

### Snapshot — after first apply

`NormalEnemyGroup._ready()` runs **after** child nodes (including `Health`) have already run `_ready()`. It snapshots each enemy:

```gdscript
# src/enemy/normal_enemy_group.gd
for enemy in _list_enemy_locals():
    _enemy_snapshots.append(enemy.duplicate(_SNAPSHOT_FLAGS))
```

The snapshot therefore captures the enemy **after** dev settings have already modified `max_hp` (15, not the original 30).

### Second apply — checkpoint respawn

On checkpoint reset, `Checkpoint.set_world_at_checkpoint_state()` calls `enemy_group.reset()` for groups listed in `enemy_groups_reset`. `NormalEnemyGroup.reset()`:

1. `queue_free()` the live boss.
2. `duplicate()` each snapshot and `add_child()` a fresh instance.

The new boss runs `Health._ready()` again → `DevSettings.apply_to_health()` runs again.

Because `get_scene_max_hp()` currently returns the **current** `max_hp` (already 15 on the clone), the multiplier is applied a second time: 15 × 0.5 = 8.

---

## Why player overrides are unaffected

`player_max_hp_override` sets an **absolute** value, not a multiplier. Each new player instance gets the same override in `_ready()`; there is no compounding across respawns unless the override itself changes.

---

## Possible fixes (not implemented)

Any fix should ensure dev multipliers are always computed from the **scene-authored** HP, not from a value already modified by dev settings or captured in a post-apply snapshot.

Options:

1. **`Health` stores scene base HP** — capture `max_hp` in `_enter_tree()` (before dev apply) as `_scene_max_hp`; `get_scene_max_hp()` returns that. Duplicates must preserve `_scene_max_hp` across `NormalEnemyGroup` snapshot/respawn.
2. **Snapshot before dev apply** — change ordering or snapshot source so `NormalEnemyGroup` stores pre-override state (e.g. snapshot from packed scene, not from live node after `_ready()`).
3. **Apply dev settings in one place after respawn** — e.g. only in `NormalEnemyGroup.reset()` after spawning, not in `Health._ready()` (larger refactor).

---

## Workaround for local testing

Until fixed:

- Avoid dying / checkpoint respawn when testing boss HP tuning, or
- Compensate manually (e.g. use `boss_hp_multiplier = 1.0` after respawn), or
- Use absolute HP in the boss scene temporarily instead of a dev multiplier.
