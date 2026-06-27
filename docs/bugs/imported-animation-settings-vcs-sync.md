# Imported animations — loop / custom tracks lost across machines (VCS)

This document explains why animation settings configured in the Godot editor on one machine (Mac) do not survive a git pull on another (Windows), and why manual fixes on Windows can be wiped again on the next reimport.

**Related code:** `src/enemy/enemy_boss.tscn`, `src/enemy/boss/skeleton_boss/slash_impact_point.gd`, `src/enemy/boss/skeleton_boss/slam_impact_point.gd`

**Related assets:** `assets/animations_source/animations/rig_large/skeleton/*.res`, `assets/animations_source/characters/rig_large/skeleton/*.glb.import`

**Engine:** Godot 4.x

**Status:** Workaround applied manually on Windows (2025-06). Proper import-pipeline fix not yet done.

---

## Symptom

After pushing from Mac and pulling on Windows:

- **Loop mode** is off for locomotion clips (`Idle_A`, `Walking_A`, `Running_A`, etc.) even though it was enabled in AnimationPlayer on Mac.
- **Custom animation tracks** are missing — e.g. `Melee_1H_Slash` no longer calls `instantiate_impact()` at the expected frame, and hitbox `monitoring` / `monitorable` keyframes on attack animations are gone.
- Re-applying the setup on Windows “works” until the next GLB reimport or fresh `.godot/` cache rebuild.

This is **not** a Mac vs Windows line-ending or Git corruption issue. `.gitattributes` already normalizes to LF.

---

## What is actually happening

In Godot 4, loop mode and custom tracks (Call Method, property keyframes) live on the **`Animation` resource**, not on `AnimationPlayer`.

For the skeleton boss, most clips are **external `.res` files** exported from GLB import (“Save to File”), referenced from `enemy_boss.tscn`:

```gdscript
# AnimationLibrary in enemy_boss.tscn — external refs, no loop_mode in .tscn
&"Idle_A": ExtResource("16_q7vqw"),       # → Idle_A.res
&Melee_1H_Slash": ExtResource("18_70v76") # → Melee_1H_Slash.res
```

Contrast with inline animations (e.g. `enemy_flying_skull.tscn`) where `loop_mode = 1` is stored directly in the `.tscn` and syncs reliably via Git.

When you toggle loop or add tracks in AnimationPlayer on Mac, Godot writes changes into the **`.res` file** (binary). That file is tracked in Git. However, the GLB importer remains the **source of truth** for reimport:

1. Windows opens the project → Godot builds a fresh `.godot/` cache (gitignored).
2. Godot **reimports** source GLBs (`Rig_Large_General.glb`, `Rig_Large_MovementBasic.glb`, `Rig_Large_CombatMelee.glb`, etc.).
3. Importer **regenerates** each external `.res` from skeleton data in the GLB.
4. Without correct import flags, **custom metadata is discarded** — loop mode reset to none, method-call tracks removed, hitbox property tracks removed.

---

## Import settings that cause the loss

In `*.glb.import` files under `assets/animations_source/characters/rig_large/skeleton/`, affected animations had:

| Setting | Value in repo (before fix) | Effect |
|---------|---------------------------|--------|
| `"settings/loop_mode"` | `0` (none) | Reimport exports non-looping clips |
| `"save_to_file/keep_custom_tracks"` | `""` / disabled | Reimport wipes editor-added tracks |

Example (`Rig_Large_CombatMelee.glb.import`):

```
"Melee_1H_Slash": {
"save_to_file/enabled": true,
"save_to_file/keep_custom_tracks": "",
"settings/loop_mode": 0,
...
}
```

**Keep Custom Tracks** must be enabled for any animation that has Call Method or property keyframes added after import. Without it, reimport treats the `.res` as disposable output from the GLB, not as an editable resource.

---

## Affected boss animations (non-exhaustive)

| Clip | Library / source GLB | Settings at risk |
|------|---------------------|------------------|
| `Idle_A`, `Idle_B` | `Rig_Large_General.glb` | Loop mode |
| `Walking_A`, `Running_A` | `Rig_Large_MovementBasic.glb` | Loop mode |
| `Melee_1H_Slash` | `Rig_Large_CombatMelee.glb` | `instantiate_impact()` method track, hitbox keyframes |
| `Melee_1H_Stab`, `Melee_2H_Slam`, … | `Rig_Large_CombatMelee.glb` | Custom tracks as authored |

Hitbox tracks in `enemy_boss.tscn` today exist only on the tiny inline `RESET` animation (sets weapon hitbox off at frame 0), not on attack clips in the committed `.res` files.

---

## How to verify before / after a fix

**On Mac, after editing animations in AnimationPlayer:**

```bash
git status assets/animations_source/
```

Expect changes to **both** `.glb.import` (text, ideal) **and** `.res` (binary). If neither changed, settings may only exist in local `.godot/` editor state (gitignored).

**On Windows, after pull, before opening Godot:**

```bash
strings assets/animations_source/animations/rig_large/skeleton/Melee_1H_Slash.res | findstr instantiate
```

- **No match** → reimport already wiped custom tracks (or they were never committed).
- **Match present but animation silent at runtime** → separate NodePath issue (method track target path wrong from AnimationPlayer root).

---

## Proper fix (not yet implemented in repo)

### 1. Loop mode — set in Advanced Import (VCS-friendly)

For each looping clip:

1. Double-click the source GLB in FileSystem → **Advanced Import**.
2. Select the animation (`Idle_A`, `Walking_A`, `Running_A`, …).
3. Set **Loop Mode → Linear**.
4. Reimport on one machine.
5. Commit the updated **`.glb.import`** files.

### 2. Custom tracks — enable Keep Custom Tracks

For each attack clip with method calls or hitbox keyframes:

1. Same Advanced Import dialog → select animation (e.g. `Melee_1H_Slash`).
2. Confirm **Save to File** is enabled.
3. Enable **Keep Custom Tracks**.
4. Reimport.
5. Re-add custom tracks if a prior reimport already stripped them, then save and commit **`.import` + `.res`**.

Repeat for all rig_large GLB import files that export animations to `assets/animations_source/animations/rig_large/skeleton/`.

### 3. Optional — post-import script

An `EditorScenePostImport` script on the GLB importers can set `loop_mode = Animation.LOOP_LINEAR` for clips whose names match `Idle`, `Walk`, `Run`, etc., so loop survives even if someone forgets import UI settings. Custom method/hitbox tracks still need **Keep Custom Tracks** or code-driven alternatives.

### 4. Optional — move gameplay out of animation tracks

More robust long-term:

- Hitbox on/off → attack state code (`set_weapon_hitbox_monitoring()` in `enemy_local.gd` already exists).
- Impact VFX → timed call from attack state or AnimationTree signal, not Call Method on imported `.res`.

Survives reimport and is easier to review in Git than binary `.res` diffs.

---

## Workaround (current)

Manual re-setup on Windows after pull (loop toggles + custom tracks in AnimationPlayer), then avoid reimporting source GLBs until import flags are fixed.

**Fragile:** any Reimport on either machine can wipe the manual work again.

---

## References

- [godotengine/godot#75912](https://github.com/godotengine/godot/issues/75912) — Save animation paths breaks looping on reimport
- [godotengine/godot#108823](https://github.com/godotengine/godot/issues/108823) — `-loop` suffix not preserved when using save paths
- [Godot forum — Keep custom tracks](https://forum.godotengine.org/t/what-does-keep-custom-tracks-do-for-anims-in-the-advanced-3d-scene-import/52596)
- [Godot forum — Call method track on imported animations](https://forum.godotengine.org/t/call-method-track-in-blender-imported-animations/107736/4)
- [godotengine/godot#28275](https://github.com/godotengine/godot/issues/28275) — Custom tracks on imported models (3.x, still relevant conceptually)
