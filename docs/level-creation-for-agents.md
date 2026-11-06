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
4. **Add the level to the level select**: add an entry to a tab in `src/menu/level_select/level_select_catalog.gd`, with `"weapon": "<the scene's weapon id>"`. Add `"requires": "ranged"` if some enemies can't be reached on foot. Each tab fits about three posters. Every other weapon is offered too, so run the swap test described in "Playing a level with another weapon" in [level-authoring.md](level-authoring.md).
5. **Test in the running game.** Copy `verify_saw_gauntlet.gd`, keep its helpers, and rewrite `_run()`:

   ```bash
   tools/level_gen/godot.sh test tools/level_gen/my_verify.gd res://src/world/levels/my_level.tscn /tmp/my_level_shots
   ```

   ```bash
   MENU_LEVEL=res://src/world/levels/my_level.tscn tools/level_gen/godot.sh test tools/level_gen/verify_menu_button.gd res://src/menu/menu.tscn /tmp/my_level_shots
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

**Music:** give each level a track that fits its theme with `Level(..., music="entangle")`. The keys are in `MUSIC` in `tools/level_gen/levelgen.py`. Without it, the level gets the old shared default (Amenoshita). To add a track, download it from peritune.com into `assets/music/`, turn on `loop=true` in its `.import` file, and add its uid and path to `MUSIC`.

**Footsteps** follow the floor under each player: grass, wood, stone or metal (`src/sound/footstep_surface.gd`). Hill tiles count as grass. A new tile set goes in `BY_MESH_LIBRARY` in that file. A new bridge or platform scene gets `metadata/footstep_surface = &"wood"` (or `stone` / `metal`) on its body. Without one, it sounds like grass.

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
- **Mage range:** the default `cast_max_distance` of 30 m is long. Set it so the mages do threaten the players: 14 m in the sword level, 10 m in the saw level. For mages that can be walked to, being off screen is fine (see below).
- **Zoom out only for enemies that can't be walked to.** A framing (`add_focus`) zooms the camera out, and players should keep the normal zoom whenever they can reach every enemy on foot. Use one only for targets across a gap or on their own platform, such as packs to shoot before a bridge opens, or mages on islands. Enemies that come to the players are close enough to see. `tools/level_gen/report_framing_reach.gd` lists each framing in a level and how many enemies inside it can be walked to. Run it with `godot.sh test`.
- **Mages may fire from off screen.** Working out where an unseen mage is shooting from is a difficulty the game wants. So at normal zoom, don't shorten a reachable mage's range or zoom out to show it. The test drivers only require that some mage is in range there. A mage the players can't walk to still gets a framing.
- **Arena framing:** when one is needed, add a focal point at all **four corners** with `add_focus`. Focal points on one side only shift the view, and pushed a player off the bottom of the screen while every enemy check passed. Clear them with `UnfocusCamera` when the group dies. Respawning clears them too, so the trigger must be able to fire again.
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

## Other environments: sky

`tools/level_gen/example_sky_prototype.py` builds a level on floating islands, with no water. Copy it as a starting point. The camera looks steeply down, so the environment is mostly what's visible *below* the play space. The panorama's lower half is flat colour, so depth has to come from the scene.

- **Clouds:** `Level.add_sky(floor)` adds `src/world/elements/sky/cloud_layers.tscn`, three drifting sheets at different depths. Their parallax is what makes it feel high up. Water and clouds are alternatives: leave `water_x` unset in `add_terrain`.
- **Cliffs:** `add_sky` also extends cliffs downward. They used to end where the water hid them.
- **Falling:** pass `fall_y=-17` to `add_terrain` so the kill plane sits about 11 m under the islands, and players visibly drop before the game over.
- **Scenery:** `add_distant_island` adds islands with no collision and a slow bob. Keep them far out and deep (about 55 m or more to the side, 26 m or more down), since deeper objects drift toward the centre of the screen.
- **Telling scenery from play space:** the top cloud sheet has `sky_opacity = 0.34`, which hazes everything below it. Without it, distant islands look walkable.
- **Bridges:** `add_sky` switches the level to `sky_bridge_platform.tscn`, a plank on small clouds. While lowered it is invisible and has no collision, then it rises and grows into place. Don't use `bridge_platform.tscn` with a low `fall_y`: its lowered block stays solid and is above the kill plane, so a player who steps into the gap lands on it and survives. It's safe in water levels because the kill plane is higher than the block.

## Other environments: dark dungeon

`tools/level_gen/example_dungeon_prototype.py` builds walled rooms lit by fire. Copy it as a starting point. `Level(palette="dungeon")`, then `use_dark_environment()` before `add_shell()`, and `add_dungeon_terrain(floor, pits, pillars, fall_z)` instead of `add_terrain`. The art is in `src/world/elements/dungeon/`, including its mesh library, because `.gitignore` excludes `assets/mesh_library/`.

- **Walls:** generated around every open cell. Those on the camera side are low so they don't hide the players. This camera looks down steeply, so tall walls only hide about 40% of their height behind them.
- **Gates:** `dungeon_gate.tscn` reuses the bridge events and is placed with `set_bridges`. "Open" sinks it into the floor, "close" raises it. The floor under a gate stays in the navmesh, so chasers would likely press against a shut gate if the players are on the other side (read from the setup, not tested). Only make a group offensive once the gate behind the players is shut.
- **Weapon:** rockets fly through terrain by default, so a bazooka can hit through walls unless `detonate_on_terrain` is set. Fireballs should pass through walls too, going by their collision settings (not tested). These prototypes use the sword.
- **Metal needs something to reflect.** With a black world, the sword's blade renders almost black. The dark environment keeps the sky panorama as a reflection source, without showing it as the background. That also tints metal teal, so give new iron props low `metallic`.
- **Light placement:** the camera sees what faces south and up, so put a brazier on the camera side of an enemy. One placed behind it leaves a dark silhouette.
- **Keep pits and solids distinct.** Pure black should only ever mean a pit or the void. Pillar and wall tops need visible stone: nearly black tops looked exactly like a hole.
- **Test brightness from real pixels:** `check_enemies_readable` in `verify_dungeon_prototype.gd` averages the screen around each nearby enemy, with the HUD hidden. The 0.05 threshold is a judgement call, so also look at the screenshots. `check_players_not_behind_walls` casts a ray from the camera to each carrier's head.

## Other environments: lava

`tools/level_gen/example_lava_prototype.py` builds a catapult level (it was a saw level before) on basalt over a molten surface. Copy it as a starting point. `Level(palette="lava")`, then `use_lava_environment()` before `add_shell()`, and `add_lava_terrain(floor, mouths, fall_z, outcrops)` instead of `add_terrain`. The art is in `src/world/elements/lava/`. Its tiles are the normal hill tiles with a basalt material, built by `tools/level_gen/build_lava_tiles.gd`, so `build_floor` works as usual. Re-run that script only to change which tiles are included; the look is in `lava_rock.gdshader`.

- **Touching the lava is the fall:** the kill box sits right at the surface (`LAVA_FALL_Y`), and `lava_surface.gd` throws up a splash.
- **Bridges:** `lava_bridge_platform.tscn` is a basalt slab that rises out of the lava. While lowered it is hidden and has no collision. Twin rails worked with the saw here; the catapult walks single file along one rail (not tested yet).
- **Vents:** `add_vents` places `lava_vent.tscn`, one (cx, cz, phase) each. By default each runs a 4 s cycle: 1.3 s of warning, then 0.9 s of eruption. The rim on the ground has the same radius as the burn (1.45 m), measured from a body's origin, and it stays visible while the vent is quiet. Stagger `phase` to make waves. Vents burn enemies too, so keep waiting enemies and spawn points clear of them; the example asserts this.
- **Scenery:** `add_lava_spouts` adds harmless, larger eruptions out in the lava, and `outcrops` adds rocks with no collision.
- **Unshaded materials ignore `EMISSION`.** The lava and vents first rendered pure black because of this. Write glowing colours to `ALBEDO` in an `unshaded` shader; values above 1 still trigger the environment's glow.
- **Lit from below:** emission doesn't light other objects, so `LavaGlow` is a shadowless directional light pointing up. It colours what stands above the lava and can't reach the tops of tiles. Too much of it, or a red sun, tints enemies into the ground.
- **Keep the ground plain.** Glowing cracks are only on cliff faces. Walkable ground should be a calm neutral colour, so the only bright things on it are hazards.
- **The saw's blade reflects the sky.** A dark sky turned it black, and a bright one or the sun's highlight blows it out to white, so check it from several camera distances. It still ranges from cream to white.
- **Test vents without dying:** `burned` fires even for invulnerable players. `sweep_straight_walk` in `verify_lava_prototype.gd` uses that to walk across a vent field from several points in the cycle and count the clean crossings. Measure how many enemies the vents kill on their own, too, so a fight doesn't finish itself. In the prototype they burned 2 of 7 guards and 1 of 13 chasers while the carriers stood still.
- **Catapult** (`src/weapon/catapult.tscn`, `weapon="catapult"`): carried in line, 4 to 7.5 m apart, so spawn markers go front and back: setter `(0, -2.25)`, shooter `(0, 2.25)`. The gap sets the launch angle, from an 82° lob that lands about 7.5 m ahead of the back carrier to a 45° throw that lands about 17 m ahead. A ring the size of the blast (3.5 m, the bazooka's explosion) shows the landing point, and the camera frames it. The shoot button throws, then the arm takes about 1.5 s to reload. Bombs land on terrain, unlike rockets, and a bomb that would fall into lava turns the ring red. Its model is built by `tools/blender/build_catapult.py`; `tools/level_gen/verify_catapult.gd` tests it in this level.
- **New class names:** a `class_name` in a new script isn't known until Godot rescans. Run `godot --headless --path . --import` once before a test driver uses it, or the driver fails to compile.

## Other environments: rotor decks

`tools/level_gen/example_rotor_decks_prototype.py` builds a sky level on wooden decks held up by propellers. Copy it as a starting point. `Level(palette="decks")`, then `use_rotor_decks()` before `add_shell()`, and `add_deck_terrain(decks, lanes, fall_z)` instead of `add_terrain`. The art is in `src/world/elements/sky_decks/`.

- **Rotors go outside the deck.** The camera looks steeply down, so anything under a deck is hidden. They sit on outrigger arms, have no collision, and are placed along outer edges automatically. List cells in `lanes` where a rotor shouldn't go, such as beside a ferry's path. Then check that every deck still has some.
- **Ferries replace bridges.** `rotor_ferry.tscn` is a `BridgePlatform` whose animation flies, so the normal events work with no new code. "Open" brings it from the far dock to the near one, and "close" flies it back. A trigger on the near dock runs the close event once both carriers are aboard. A checkpoint's `events_completed` snaps it back to the near dock after a death.
- **Wake a ferry's enemies on landing.** A moving platform isn't in the navmesh, so enemies can't reach carriers on it. A landing trigger covering the first rows past the far dock fires once both carriers are off. It sends the ferry back to its near dock with `bridge_event(..., camera_focus=False)`, then wakes the group through `next_event`. The landing triggers and the returned ferries are appended to the checkpoint arrays, because `checkpoint()` takes one name per array.
- **Enemies wait when they can't reach a player.** If a path ends more than 1.5 m short of its target, `enemy_local.gd` stops the enemy at the end of the path instead of running straight at the target, which used to walk enemies off edges. It also measures path progress flat, because the navmesh is baked about 0.5 m above the floor. The navigation agent's own 3D checks never let low-standing enemies such as the robots reach their first path point, so they ran straight into holes.
- **Moving platforms:** set `callback_mode_process = 0` on the `AnimationPlayer`, so the `AnimatableBody3D` moves during physics. Carriers then ride it without sliding: in testing they stayed put and kept the bazooka.
- **World-space shaders on moving things:** `wood_planks.gdshader` draws planks from world position, so decks of any shape tile. On something that moves, the boards stay still while it slides under them, so the ferry sets `local_space = true`. `check_boards_move_with_ferry` photographs the deck from a camera riding on it at both docks. It also runs the old behaviour as a control, to prove the measurement can fail.
- **Fixed flight distance:** the ferry always flies 4 cells, and its animation holds that distance, so every gap must be 7 cells. Other gap sizes need a new animation.
- **Don't frame the far deck while riding.** Focal points on the far deck pushed the carriers off screen mid-flight. The ring's chasers can be walked to anyway, so that deck has no framing now; only the mages' decks do.
- **Gaps limit shooting:** a 7-cell gap is too wide to shoot across on screen. The first targets stood 30 m away, beyond what `max_zoom_out` can frame, so they moved onto the start deck.
- **Rocket speed:** rockets fly at 5 m/s and a ferry at about 2.4 m/s, so a rocket fired mid-flight is slow to pull ahead. In one test, a rocket fired during the ride hadn't killed anything by the time the ferry landed.
- **Test driver trap:** teleporting both carriers with `move_players` after they've turned can leave the weapon sideways, so a rocket misses for reasons unrelated to the level. Walk them there with real input before firing.
- **Gridmap layers:** one cell holds one item, so `_deck_frame` stacks edge beams on lower layers and `deck_tiles.tres` lifts their meshes back up.

## Other environments: space station

`tools/level_gen/example_space_station_prototype.py` builds a pulse-rifle level on station decks above a gas giant. The rifle (`src/weapon/pulse_rifle.tscn`, `weapon="pulse_rifle"`) fires about 10 bolts a second while shoot is held, 1 damage each, and bolts fly through terrain and shoot down plasma. Its model is built by `tools/blender/build_pulse_rifle.py`. `tools/level_gen/example_katana_robot_boss.py` builds a boss arena on the same decks, against 4GTN (`src/enemy/enemy_katana_robot.tscn`), tested by `verify_katana_robot_boss.gd`. Copy it as a starting point. `Level(palette="space")`, then `use_space_station()` before `add_shell()`, and `add_station_terrain(decks, props, fall_z)` instead of `add_terrain`. The art is in `src/world/elements/space/`.

- **Robots replace skeletons.** `use_space_station()` makes `melee`, `mage` and the survival group use `src/enemy/enemy_robot.tscn` (KayKit Robot One) and `enemy_robot_gunner.tscn` (Robot Two). They are the skeleton scenes with the model swapped: the Robots share the `Rig_Medium` rig, so the same animation clips drive them.
- **Gunners carry a rifle.** Robot Two's right forearm is a cannon, so `borrowed_arm.gd` swaps in Robot One's arm, and the KayKit Space Ranger rifle sits on `handslot.r`. They aim, run and shoot with KayKit's rifle clips, extracted by `tools/level_gen/extract_kaykit_animations.gd`. They fire `laser_bolt` through `FireballEmitter.spawn_scene`, which behaves exactly like a fireball. `Casting.cast_animation_delay_seconds` delays the shoot animation so its recoil, about 0.33 s in, lands when the bolt leaves. The katana boss still fires `plasma_bolt`.
- **Tiles:** `space_tiles.tres` is built by `tools/level_gen/build_space_tiles.gd` from the KayKit Space Base glTFs in `assets/models/space_base/`, scaled 1.5× to fit 3 m cells. Each prop item is a deck plate with the prop on it and box collision, so props block movement and the navmesh bakes around them. Re-run the script to add props.
- **Bridges:** `hard_light_bridge_platform.tscn` projects across the gap ("open") and switches off ("close"). While off it is invisible and has no collision.
- **Scenery:** `add_planet`, `add_distant_station` and `add_asteroids`, all without collision. The starfield is a sky shader that also covers the view below the decks.
- **Plating brightness:** under the white sun the first panel colour washed out to near-white. Keep `panel_color` in `station_panels.gdshader` darker than about 0.45.

## Boss fights: the necromancer

`tools/level_gen/example_necromancer_boss.py` builds `world_local_necromancer_boss.tscn`, a dungeon arena with one gate. Copy it for a boss in a dark level. The boss is `src/enemy/enemy_necromancer.tscn`; its tuning is exported on `NecromancerBehavior` and `NecromancerSpells`.

- **Moves:** a bolt volley, summoned skeletons and a scythe swing at close range. The boss blinks away from carriers who stay close. Below 50% HP it taunts, the scythe burns, and eruptions start under each carrier.
- **Minions** live in a `NecromancerMinions` node outside the enemy group, so they don't count toward clearing it. They die with the boss, and are removed when a respawn resets it.
- **Sword hits need the blade to cross the body.** `hit_area.gd` only deals damage when a body enters or leaves the blade during a strike. A body already inside the blade at the start of a dash can take no hit, and a wider capsule makes that more likely, so keep boss capsules narrow.
- **Animations:** spell and melee clips aren't in the project's Rig_Medium glbs. Those in `assets/animations_source/animations/necromancer/` were extracted from `KayKit_Character_Animations_1.1` with `GLTFDocument` and saved as `.res`.
- **Dev settings:** `boss_hp_multiplier` scales any enemy with a `BossPhaseController`, and is applied twice ([bug](bugs/dev-settings-double-apply.md)). Read the HP in the scene, not the one in the running game.

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
- **A driver that fails to compile doesn't stop the game.** It runs until the time limit with no results, so check for `SCRIPT ERROR` in the output first. GDScript can't infer a type from values like `list[0].global_position.y`: declare it (`var safe: bool = ...`).
- **Check that threats can actually act.** Stationary mages only fire within `cast_max_distance`: test that some are in range, or a section can quietly have no danger. Also space rocket packs in metres, since whole cells are too far apart for one blast.
- **Save prompt:** if the level has saved progress, its menu button opens Continue / From beginning instead of loading. Don't press "From beginning" in a test: the level then starts over without the player's save, and new checkpoints could overwrite it.
- **Harmless output:** RID leak errors on exit come from quitting mid-game, and `--script` bakes print compile errors about autoloads.

## Known issues in the game

- **Level select space:** each tab in `level_select_catalog.gd` has room for about three posters. Beyond that, add a tab. A poster fits seven weapon tags under it, in two rows.
- **Simulating menu input in a driver:** send `InputEventAction` through `Input.parse_input_event`. `Input.action_press` was missed by the level select for some actions (`ui_left` never registered), probably a frame-timing issue.

## Code style

`.cursor/rules/coding-control-flow.mdc` applies to new code, including these tools: guard clauses, no nested `if`, the main path last. `tools/level_gen` has a `.gdignore`, so Godot doesn't import its scripts into the project.
