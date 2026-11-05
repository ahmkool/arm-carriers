# Creating levels as an agent

How to build a complete, playable level without the Godot editor, and how to prove it works. Three levels were made this way: `world_local_bazooka.tscn`, `world_local_sword.tscn` and `world_local_saw.tscn`.

Read [level-authoring.md](level-authoring.md) first for the scene structure, events and checkpoints. This guide covers what that one doesn't: designing around a weapon, generating the scene, and testing it.

Numbers below were read from the code when this was written. Check the source if something behaves differently.

## The main lesson

**A level can pass every logic check and still be broken for the player.** The first bazooka level had working triggers and rockets that hit, but its targets were 28 m away and the camera sees about 12 m, so the player was firing blind. A person found that on first play. Test what's on screen, then look at the screenshots yourself.

Also, nothing here tests difficulty or fun. Only a person playing can. Say so when you report back, and treat any difficulty label as a guess.

## Workflow

1. **Read the weapon's scripts** and write down what makes it different. The layout should come from that, not from copying a level.
2. **Copy the example:** `tools/level_gen/example_saw_gauntlet.py` to a new file. Change the output path, weapon, palette and layout.
3. **Generate, bake, regenerate.** The first run has no navmesh. Baking creates one, and the second run embeds it. Run from the project root:

   ```bash
   PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/level_gen python3 tools/level_gen/my_level.py
   ```

   ```bash
   tools/level_gen/godot.sh bake res://src/world/levels/my_level.tscn /tmp/my_level_nav.json
   ```

   ```bash
   PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/level_gen python3 tools/level_gen/my_level.py /tmp/my_level_nav.json --force
   ```

   Keep the JSON between runs: it also holds the scene's uid. Re-bake whenever the floor changes.
4. **Add a menu button** in `src/menu/menu.tscn`: copy an existing level button, and give it a unique node name, `level_scene_path` and `level_id`. Edit the text and insert one block; don't re-save the whole scene.
5. **Test in the running game.** Copy `verify_saw_gauntlet.gd`, keep its helpers, and rewrite `_run()`:

   ```bash
   tools/level_gen/godot.sh test tools/level_gen/my_verify.gd res://src/world/levels/my_level.tscn /tmp/my_level_shots
   ```

   ```bash
   MENU_BUTTON=MyLevelButton tools/level_gen/godot.sh test tools/level_gen/verify_menu_button.gd res://src/menu/menu.tscn /tmp/my_level_shots
   ```

6. **Look at every screenshot.** Then report what passed, and what was scripted rather than truly tested.

### Before regenerating

The generator is for getting a level started. Once someone has opened a level in the editor, it may hold hand edits, and regenerating erases them. So the generator refuses to overwrite an existing file without `--force`.

Before using `--force`, generate to a temporary path with `--out` and diff it against the scene. A changed first line is harmless, because Godot can add `load_steps=0`. Anything else is someone's work: stop and ask.

The user's editor may also be open, so a regenerated file will prompt them to reload. Tell them, and warn that saving the old copy overwrites your change.

## Weapons

The carry distance decides how wide bridges and lanes need to be.

| | Bazooka | Sword | Saw |
|---|---|---|---|
| **Attack** | Fire button, rocket explodes on an enemy or fireball | Dash; the blade hits only while a dash is moving it | None needed: always on |
| **Damage** | Kills within 3.5 m | 3 per hit (kills 3 HP enemies) | 3 per hit, 1 s per-enemy cooldown |
| **Reach** | 60 m, then a harmless pop; rockets fly through terrain (set `detonate_on_terrain` on the rocket scene to change that) | Blade about 7.5 m long | Disc about 3.3 m wide, between the carriers |
| **Other** | Rocket speed 5 m/s, 0.75 s cooldown; can shoot down fireballs | Dash covers about 2 m | Carriers exposed on both sides of the disc |
| **Carry distance** | 1.6 to 4.2 m | 1.6 to 3.2 m (settled at about 2 m when tested) | 5.5 to 7 m |
| **Designs that suit it** | Tight packs, shooting across gaps and pits | Open arenas, everything reachable on foot | Funnels that bunch enemies, pits and rails to straddle |
| **Bridge** | `single_bridge` | `double_bridge` | `triple_bridge` or `twin_rails` |
| **Spawn markers (local x, z)** | Setter `(0, -0.5)`, shooter `(0, 2.1)` | Same as bazooka | Setter `(-3, 0)`, shooter `(3, 0)` |

Sword or saw levels can't be sniped, so every enemy must be somewhere the carriers can walk to. Put a launch hint in sword and saw levels: `Level(..., hint="...")`.

**Twin rails drop the sword's carriers.** Its 3.2 m limit leaves almost no footing either side of a 3 m gap: in testing, one carrier got pulled into it. A checkpoint on the centre line also walks them straight at the gap. Rails suit the saw, whose spacing matches the 6 m between them. The bazooka's limits weren't tried on rails.

## Enemies and players

| | HP | Speed | Notes |
|---|---|---|---|
| Player | 3 | 5 m/s | Dash lasts 0.07 s at 30 m/s |
| Skeleton (`enemy_local.tscn`) | 3 | 2 m/s | Touch deals 3, so **one hit kills a player** |
| Mage (`enemy_mage_no_behavior.tscn` + `MageBehavior` child) | 3 | 5 m/s if mobile | Fireball one-hit kills, 5 m/s from this mage (its emitter overrides the 8 m/s default), 5 s lifetime. Rockets and explosions destroy it; nothing in the sword or saw code does |
| Flying skull (`enemy_flying_skull.tscn`) | 3 | 3 m/s | Flies straight at players, ignoring pits. Not used or tested in these levels |

- Set `is_offensive = false` on anything that should wait for a trigger, or it starts attacking as soon as the level loads.
- `mobility = 1` makes a mage stationary. Mobile mages keep about 5 m away from players at the same speed as them, so a melee weapon can only catch them against an edge.
- A level with one-hit deaths is harder than its enemy count suggests.

## Camera: what the player can see

This caused most of the problems, so check it for every section.

- **Each weapon frames differently.** The camera follows the players plus the weapon's `CameraAddons` markers. Camera height was about 9 with the bazooka, 12.6 with the sword and 7.7 with the saw. The bazooka sees only about 12 m ahead.
- **Raising it for one level:** `Level(..., follow_offset="Vector3(0, 11, 4.714)")`. Keep the 7:3 ratio of the default `(0, 7, 3)` to keep the same angle. The saw level uses this.
- **Mage range:** the default `cast_max_distance` of 30 m shoots from far off-screen. Set it shorter, or frame the mages. 14 m worked with the sword's camera; the saw level needed 10 m.
- **Arena framing:** add a focal point at all **four corners** with `add_focus`. Focal points on one side only shift the view, and pushed a player off the bottom of the screen while every enemy check passed. Clear them with `UnfocusCamera` when the group dies. Respawning clears them too, so the trigger must be able to fire again.
- **Zoom limit:** the camera stops zooming out at `max_zoom_out`, so a very long area won't fit on screen. For those, make sure threats are visible when they're close enough to hurt, rather than all at once.
- **Don't spawn inside a trigger.** Triggers fire when a body enters, so one the players are already inside may not fire after a respawn (read from the code, not tested). Place it ahead of the spawn so it fires as they walk in.

## Geometry reference

- **Grid:** cells are 2.999 m. Cell x = 0 is centred on world x = 1.5, not 0. Use `world(cx, cz)` for every position.
- **Tiles:** always look items up by name, as `Level` does. Item numbers differ between palettes: 43 is a floor edge in Color7 and a cliff in Color1.
- **Palettes:** `1` green, `6` orange, `7` pink. Use the `_no_shadows` libraries.
- **Floor layout:** a Hill_Top tile at y = -1 for every floor cell, plus a Hill_Cliff_Tall tile at y = -3 under each edge and corner. `build_floor` handles it, including orientations.
- **Floor rules:** every part of the floor must be at least 2 cells wide; the generator asserts this.
- **Pits:** subtract a `rect` from the floor. Enemies path around them.
- **Mouths:** floor cells where a bridge lands use a flat centre tile. List them in `MOUTHS`, or the bridge meets an edge tile.
- **Bridges:** a platform's root sits at y = -3.9927697, in its own cell along the gap. Its top is at y = -5.99 lowered and -0.99 raised. Platforms aren't in the navmesh, so chasers can't cross them.
- **Decoration:** use grass only (`Grass_*`), since those items have no collision. That GridMap has 2 m cells, not 3 m.
- **Fall area:** the box must cover the whole level and extend past it. Leave its y values as they are.

## Testing

### Running the game

`godot --script` doesn't register autoloads, so game scripts fail to compile and results are meaningless, even when some checks pass. `godot.sh test` launches normally instead, with a temporary `override.cfg` that adds your driver as an autoload.

In the driver:

- The level is already loaded when the driver's `_ready` runs. Read `get_tree().current_scene`. A `node_added` signal will never fire for it.
- Set `skip_save = true` and call `GameSave.untrack_manager(...)`, or you write to the player's `save.json`. `godot.sh` warns if the file changed. If it changes between runs while nobody is testing, that's probably the user playing, so leave it alone.
- Keep the Godot window in front. A run once stalled until its time limit, with no result, and a covered window was the likely cause (not confirmed).

### What to check

- **Real input where it matters:** press the player's own actions (`Input.action_press(player.action_up)`, `player.action_dash`), and fire through the weapon's own code. Scripted kills only prove the wiring.
- **Each new mechanic, once for real:** a real hit from the weapon, and walking across each type of bridge in each formation.
- **On screen:** `Camera3D.unproject_position` for both players and nearby enemies, from several spots per section including the corners. Count players too.
- **Navigation:** `NavigationServer3D.map_get_path` for what must connect and what must not.
- **Flow:** each group's death sets the right checkpoint and opens its bridge, each trigger closes the bridge behind and starts the next fight, and the end area finishes the level.
- **A mid-level respawn:** bridges, dead groups and reset groups are all correct.
- **Survival:** shorten `fight_duration` in the driver only, and assert the scene's real value first.

### Traps in test code

- **GDScript lambdas capture local variables by value.** `var hit := false` updated inside a lambda stays false. Use an array: `var hit := [false]`.
- **A game over restarts the level by itself** about 3 s later. If a test forces a respawn during that time, the two collide and the players move unexpectedly. Keep players invulnerable with `Health.grant_invulnerability`, and check for `gameoverlost` as a failure.
- **Survival spawners can still be mid-spawn** after you kill everything. Keep killing in a loop until `signal_emitted` is true.
- **Enemy node names change after a reset.** Re-created enemies get generated names, so look them up from the group's children.
- **Aim at the middle of a hit area.** Use the `CollisionShape3D`'s position; the `Area3D` origin can be at the end of the blade.
- **Save prompt:** if the level has saved progress, its menu button opens Continue / From beginning instead of loading. Don't press "From beginning" in a test: the level then starts over without the player's save, and new checkpoints could overwrite it.
- **Harmless output:** RID leak errors on exit come from quitting mid-game, and `--script` bakes print compile errors about autoloads.

## Known issues in the game

- **Menu height:** the level picker runs from 108 to 972 of 1080 px with the current buttons, so one or two more may need scrolling or a rearrange.

## Code style

`.cursor/rules/coding-control-flow.mdc` applies to new code, including these tools: guard clauses, no nested `if`, the main path last. `tools/level_gen` has a `.gdignore`, so Godot doesn't import its scripts into the project.
