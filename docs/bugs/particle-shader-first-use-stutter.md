# Particle effects — first-use shader / pipeline stutter

This document explains why new or runtime-spawned particle effects can freeze gameplay for a few seconds the **first** time they appear, why clearing Godot's `shader_cache` alone does not reproduce the hitch, and what we can do about it.

**Related code:** `src/vfx/`, `src/weapon/bazooka_bullet_local.gd`, `src/game/states/local/resetting_checkpoint.gd`, `src/ui/screen_fade.gd`

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

Quit the game (and editor if testing there), then:

```bash
rm -rf "$HOME/Library/Application Support/Godot/app_userdata/Armed Together/shader_cache"
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/com.nighttrainstudio.armedtogether/com.apple.metal"
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/com.nighttrainstudio.armedtogether/com.apple.metalfe"
```

Launch the **exported** `.app`, trigger each VFX once. Stutters should return on first use only.

### Verify without wiping caches

In the Godot debugger while running: **Monitors → Pipeline compilations**. A spike in **Surface** or **Draw** at the same moment as the hitch confirms shader/pipeline compile, not asset I/O.

---

## Effects most at risk in this project

Runtime-spawned scenes (preload alone is not enough):

| Scene | Spawned from |
|-------|----------------|
| `src/vfx/small_explosion.tscn` | `bazooka_bullet_local.gd` |
| `src/vfx/explosion.tscn` | `bazooka_bullet_local.gd` |
| `src/vfx/enemy_damage.tscn` | `enemy/state/dead.gd` |
| `src/vfx/puff_disappear.tscn` | `enemy/state/dead.gd` |
| `src/vfx/dash_particles.tscn` | `player/state/dashing.gd` |
| `src/vfx/fireball_spawn.tscn` | `enemy/mage/fireball_emitter.gd` |
| `src/vfx/fireball.tscn` | `fireball_spawn.gd` |
| `src/vfx/boss_axe_enrage_burst.tscn` | `boss_axe_fire_visual.gd` |
| `src/vfx/enemy/skeleton_boss/*.tscn` | Boss attack handlers |

Effects already in the level tree (footsteps, boss ambient fire) compile during level load and are less likely to hitch mid-fight.

Bazooka bullet scene note: `SpawnExplosion` starts with `emitting = false`, so the muzzle burst compiles on **first shot**, not when the bullet scene loads.

---

## Warmup rules (Godot 4.4+)

To force pipeline compile ahead of gameplay:

- Instantiate the scene and add it to the **main** scene tree.
- Keep the node **visible** (position off-camera is fine).
- Set `emitting = true` on `GPUParticles3D` nodes and wait **at least two frames** before freeing.
- **`visible = false` often does not compile.**
- A **SubViewport that never draws to the screen** also does not warm up ([godotengine/godot#103308](https://github.com/godotengine/godot/issues/103308)).

Good hook points in this project:

- `ResettingCheckpoint` — already calls `ScreenFade.fade_to_black()`; compile cost can be hidden behind the fade.
- Level load / `AwaitWorldLocalReady` — before `playing` state.
- Menu idle time — optional, but less ideal than level-load warmup.

---

## Possible fixes (not implemented)

### 1. VFX warmup during black screen (recommended)

Autoload or helper that, while the screen is faded out:

1. Iterates a manifest of runtime VFX scenes.
2. Spawns each off-camera, enables particles, awaits 2 frames, `queue_free()`.
3. Disables or stubs audio on warmed instances so SFX does not play.

### 2. Hidden decoy copies on persistent nodes

Attach invisible copies of high-frequency effects (dash, bazooka muzzle) to the player or weapon. Disable scripts on decoys. Documented in [Godot pipeline compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html).

### 3. Enable Shader Baker on export

`export_presets.cfg` currently has `shader_baker/enabled=false` for macOS and Windows. Enabling it bakes intermediate shaders into the PCK at export time (faster first compile of GLSL → MIL). It does **not** remove the Metal driver pipeline step on a player's first run.

### 4. Enable Godot pipeline cache

Project setting: `rendering/rendering_device/pipeline_cache/enable = true`

Helps **second and later** launches on the same machine. First launch on a new machine still needs warmup or accepts first-use hitches.

---

## Workaround for local testing

- To test cold-cache behaviour, clear **both** Godot `shader_cache` and the app's `com.apple.metal` folder (see commands above).
- To test whether a warmup fix works, use **Pipeline compilations** monitors instead of deleting caches every run.
- Editor runs use `org.godotengine.godot` Metal cache — behaviour differs from exported `.app` builds.

---

## References

- [Reducing stutter from shader (pipeline) compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) — Godot docs
- [godotengine/godot#103308](https://github.com/godotengine/godot/issues/103308) — GPUParticles2D first-emit stutter and warmup visibility requirements
- [godotengine/godot#106757](https://github.com/godotengine/godot/issues/106757) — Metal first-load compile times on macOS
