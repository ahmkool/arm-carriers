# Particle effects — first-use shader / pipeline stutter

This document explains why new or runtime-spawned particle effects can freeze gameplay for a few seconds the **first** time they appear, why clearing Godot's `shader_cache` alone does not reproduce the hitch, and what we implemented to fix it.

**Related code:** `src/vfx/vfx_warmup.gd`, `src/vfx/hit_flash_3d.gd`, `src/vfx/`, `src/weapon/bazooka_bullet_local.gd`, `src/game/states/local/resetting_checkpoint.gd`, `src/world/world_local.gd`, `src/ui/screen_fade.gd`, `scripts/clear_shader_caches_mac.sh`

**Autoload:** `VfxWarmup` in `project.godot`

**Engine:** Godot 4.5, Forward+ (see `project.godot` features)

**Export:** macOS bundle ID `com.nighttrainstudio.armedtogether` (`export_presets.cfg`)

---

## Symptom

- First time a particle effect is used in an **exported** build, the game hitches or appears frozen for roughly 0.5–3 seconds.
- The same effect is smooth on every later trigger in that session.
- Deleting only `~/Library/Application Support/Godot/app_userdata/Armed Together/shader_cache/` does **not** bring the hitch back.
- Most visible on effects spawned at runtime via `instantiate()` + `add_child()`, especially when `emitting` starts in `_ready()` or on first player input (e.g. bazooka `SpawnExplosion` with `emitting = false` until fired).

This is **not** slow `.tscn` loading. Preloading the scene does not remove the stall.

---

## What is actually happening

Godot compiles GPU **pipelines** lazily: the first time a unique particle material + mesh + render state combination is **drawn**, the driver compiles it. On macOS exports this goes through **Metal** (`MTLCompilerService`), which is often the slowest step.

Rough pipeline:

1. GLSL → intermediate format (SPIR-V / MIL) — partially cached in Godot `shader_cache`
2. Intermediate → final GPU pipeline — cached by the **OS Metal driver** per app bundle ID

Godot 4.4+ Forward+ also uses ubershaders and load-time precompilation, but effects that are only added to the scene tree during gameplay still pay a **Surface** or **Draw** compile on first render unless warmed up explicitly.

---

## Where caches live (macOS)

| Layer | What it stores | Location |
|-------|----------------|----------|
| Godot shader cache | Intermediate shader bytecode | `~/Library/Application Support/Godot/app_userdata/Armed Together/shader_cache/` |
| Godot pipeline cache | Pipeline state (if enabled in project settings) | `~/Library/Application Support/Godot/app_userdata/Armed Together/pipeline_cache/` |
| **macOS Metal cache** | Final compiled GPU binaries for the exported app | `$(getconf DARWIN_USER_CACHE_DIR)/com.nighttrainstudio.armedtogether/com.apple.metal` |
| macOS Metal FE cache | Related Metal frontend cache | `$(getconf DARWIN_USER_CACHE_DIR)/com.nighttrainstudio.armedtogether/com.apple.metalfe` |
| Godot editor Metal cache | Separate from exported builds | `$(getconf DARWIN_USER_CACHE_DIR)/org.godotengine.godot/` |

Wiping only Godot's `shader_cache` leaves the Metal driver cache intact, so the hitch does not return.

### Reproduce a true cold start

Quit the game (and editor if testing there), then either run the helper script or delete caches manually.

**Helper script (recommended):**

```bash
./scripts/clear_shader_caches_mac.sh
```

Add `--editor` to also clear the Godot editor Metal cache when testing in-editor.

**Manual commands (same paths the script clears):**

```bash
rm -rf "$HOME/Library/Application Support/Godot/app_userdata/Armed Together/shader_cache"
rm -rf "$HOME/Library/Application Support/Godot/app_userdata/Armed Together/pipeline_cache"
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/com.nighttrainstudio.armedtogether/com.apple.metal"
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/com.nighttrainstudio.armedtogether/com.apple.metalfe"
```

Launch the **exported** `.app`, trigger each VFX once. Stutters should return on first use only.

### Verify without wiping caches

In the Godot debugger while running: **Monitors → Pipeline compilations**.

| Counter | What to expect |
|---------|----------------|
| **Surface** | Spikes when a new mesh/material combo is first drawn. After warmup, should climb during the checkpoint fade, not during combat. |
| **Draw** | Should stay at **0** during normal play. |
| **Specialization** | May climb gradually during play — that is normal and not the same as first-use Surface hitches. |

A spike in **Surface** or **Draw** at the same moment as a hitch confirms shader/pipeline compile, not asset I/O.

---

## Effects most at risk in this project

Runtime-spawned scenes (preload alone is not enough):

| Scene | Spawned from | Warmed by |
|-------|----------------|-----------|
| `src/vfx/small_explosion.tscn` | `bazooka_bullet_local.gd` | Shared list |
| `src/vfx/explosion.tscn` | `bazooka_bullet_local.gd` | Shared list |
| `src/vfx/enemy_damage.tscn` | `enemy/state/dead.gd` | Shared list |
| `src/vfx/puff_disappear.tscn` | `enemy/state/dead.gd` | Shared list |
| `src/vfx/dash_particles.tscn` | `player/state/dashing.gd` | Shared list |
| `src/vfx/ghost.tscn` | `player/state/dashing.gd` (dash afterimage meshes) | Shared list |
| `src/vfx/dash.tscn` | `player/state/dashing.gd` (audio only) | Shared list |
| `src/vfx/fireball_spawn.tscn` | `enemy/mage/fireball_emitter.gd` | Shared list |
| `src/vfx/fireball.tscn` | `fireball_spawn.gd` | Shared list |
| `src/weapon/bazooka_bullet_local.tscn` | weapon spawn | Shared list |
| `src/vfx/boss_axe_enrage_burst.tscn` | `boss_axe_fire_visual.gd` | Boss `vfx_warmup_scenes` |
| `src/vfx/enemy/skeleton_boss/*.tscn` | Boss attack handlers | Boss `vfx_warmup_scenes` |
| Hit flash overlay shader | `hit_flash_3d.gd` on damage | Per-actor `warm_render()` |

Effects already in the level tree (footsteps, boss ambient fire) compile during level load and are less likely to hitch mid-fight.

Bazooka bullet scene note: `SpawnExplosion` starts with `emitting = false`, so the muzzle burst compiles on **first shot**, not when the bullet scene loads. The shared warmup list includes `bazooka_bullet_local.tscn` to cover this.

---

## Warmup rules (Godot 4.4+)

To force pipeline compile ahead of gameplay:

- Instantiate the scene and add it to the **main** scene tree.
- Keep the node **visible** (position off-camera is fine).
- Set `emitting = true` on `GPUParticles3D` nodes and wait **at least two frames** before freeing.
- **`visible = false` often does not compile.**
- A **SubViewport that never draws to the screen** also does not warm up ([godotengine/godot#103308](https://github.com/godotengine/godot/issues/103308)).

---

## Fix: VfxWarmup during checkpoint fade

### Hook point

`ResettingCheckpoint` is the right place to warm VFX:

- Runs on **every level start** (`AwaitWorldLocalReady` → `ResettingCheckpoint` → `playing`).
- Runs again on death (`GameOverLost` → `ResettingCheckpoint`).
- Already calls `ScreenFade.fade_to_black()` — compile cost is hidden behind the black screen.

The title screen is **not** a good hook: no 3D render context, and level-specific VFX are unknown there.

### Behaviour

`VfxWarmup` (autoload) warms shared combat VFX plus each level's `WorldLocal.vfx_warmup_scenes` during `ResettingCheckpoint`.

- Warmup runs on the **first visit** to a level per session (keyed by `level_id`).
- Checkpoint respawns on the same level **skip** warmup.
- `ResettingCheckpoint` **blocks** transition to `playing` until warmup finishes (`_warmup_done`). The black screen may last longer than the normal fade timers — that is intentional on a cold cache.

### Shared scenes (all levels)

Defined in `SHARED_WARMUP_SCENES` in `vfx_warmup.gd`:

- `small_explosion.tscn`, `explosion.tscn`
- `enemy_damage.tscn`, `puff_disappear.tscn`
- `dash_particles.tscn`, `ghost.tscn`, `dash.tscn`
- `fireball_spawn.tscn`, `fireball.tscn`
- `bazooka_bullet_local.tscn`

Scenes are deduplicated when merged with per-level extras.

### Per-level scenes

`WorldLocal` exports `vfx_warmup_scenes: Array[PackedScene]`.

Boss levels (`world_boss_scene.tscn`, `world_boss_scene_sword.tscn`) include skeleton boss VFX plus `boss_axe_enrage_burst.tscn`.

To add warmup for a new level, assign extra `PackedScene`s to `WorldLocal.vfx_warmup_scenes` in the editor.

### Hit flash overlays

`HitFlash3D.warm_render()` runs on every `EnemyLocal` and `PlayerLocal` already in the level tree. It applies the overlay at full strength on their **real meshes**, awaits 2 frames, then clears — no tween or SFX.

A proxy cube is **not** sufficient: hit-flash pipelines are mesh-dependent, so boss meshes need to be warmed on the actual in-scene actors.

### What each warmup instance does

For each scene in the manifest, `vfx_warmup.gd`:

1. Instantiates and adds the node under `WorldLocal`.
2. Strips the root script, disables processing, pauses `AnimationPlayer` nodes (prevents `ghost.tscn` from `queue_free` during warmup).
3. Silences `AudioStreamPlayer` / `AudioStreamPlayer3D` nodes.
4. Disables `Area3D` monitoring (no accidental hits).
5. Spawns off-camera (behind the active camera + vertical offset).
6. Sets `emitting = true` on all particle nodes, awaits **2 frames**, then `queue_free()`.

After all scenes, hit flashes are warmed per actor.

---

## Troubleshooting with Pipeline compilations

Useful patterns observed while debugging:

| Observation | Likely cause | Fix |
|-------------|--------------|-----|
| First bazooka hit on boss: **Surface +1** | Hit flash overlay on boss mesh not warmed | `HitFlash3D.warm_render()` on in-scene actors (implemented) |
| First dash: **Surface +2** (e.g. 27 → 29) | `ghost.tscn` afterimage meshes not warmed | Added `ghost.tscn` to shared list |
| Surface climbs during fade, flat during combat | Warmup working | — |
| Surface climbs on every dash after fade | Scene not in warmup list, or not drawn for 2 frames | Add to shared or per-level list; check visibility |
| Only `shader_cache` cleared, no hitch returns | Metal driver cache still warm | Also clear `com.apple.metal` (see script above) |

---

## Known gaps

- **Enemies spawned mid-level** (e.g. wave spawners) are not in the level tree at warmup time. Their hit-flash pipelines may still compile on first damage unless we add spawn-time warmup or a representative mesh probe.
- **Shader Baker** and **Godot pipeline cache** (below) reduce repeat cost but do not replace first-run warmup on a new machine.

---

## Other mitigations

### Shader Baker on export

`export_presets.cfg` currently has `shader_baker/enabled=false` for macOS and Windows. Enabling it bakes intermediate shaders into the PCK at export time (faster first compile of GLSL → MIL). It does **not** remove the Metal driver pipeline step on a player's first run.

### Godot pipeline cache

Project setting: `rendering/rendering_device/pipeline_cache/enable = true`

Helps **second and later** launches on the same machine. First launch on a new machine still needs warmup or accepts first-use hitches.

---

## Workaround for local testing

- **Cold-cache test:** run `./scripts/clear_shader_caches_mac.sh` (or manual commands above). Quit the game and editor first.
- **Warmup test (faster iteration):** use **Pipeline compilations → Surface** — no cache wipe needed. Surface should spike during the checkpoint fade, not on first dash/shot.
- **Editor vs export:** editor runs use `org.godotengine.godot` Metal cache — behaviour differs from exported `.app` builds. Use `--editor` on the script when testing in-editor.

---

## References

- [Reducing stutter from shader (pipeline) compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) — Godot docs
- [godotengine/godot#103308](https://github.com/godotengine/godot/issues/103308) — GPUParticles2D first-emit stutter and warmup visibility requirements
- [godotengine/godot#106757](https://github.com/godotengine/godot/issues/106757) — Metal first-load compile times on macOS
