# Player characters

Each player model is a small scene in `src/player/characters/`. `PlayerLocal` creates it when it enters the tree. All gameplay code stays in the one shared `src/player/player_local.tscn`.

## Character select

Both players pick a character at the same time (`src/menu/character_select/character_select.gd`). The first **Play** opens it and then goes on to the level select. Once picks are saved, **Play** goes straight to the level select, and the **Characters** button on the home menu opens the select to change them, returning to the home menu afterwards. Player 1 uses the `p0_*` actions and gamepad 0, Player 2 the `p1_*` actions and gamepad 1. Gamepad A (or the player's start/action key) locks in, B unlocks, and Esc goes back. A character the other player has locked in can't be picked.

The roster lives in the `CharacterRoster` autoload (`src/autoload/character_roster.gd`). The picks are saved by character name under `"characters"` in `user://save.json` through `GameSave`; a renamed or removed character counts as no pick, so the select shows again. `Players` uses the pick for each device and falls back to `character_scenes` when there is none, such as when a level is run straight from the editor.

## Swap the fallback character

Open `src/world/levels/players.tscn`, select the `Players` node and change `character_scenes`. Index 0 is Player 1 and index 1 is Player 2.

## Add a character

The model must use the `Rig_Medium` skeleton, which all KayKit Adventurers do.

1. Copy the `.glb` to `assets/models/Kaykit/characters/`, unless it is already there.
2. Render a health bar icon, listing words from the names of the head meshes:

   ```bash
   ~/Downloads/Godot_4_5.app/Contents/MacOS/Godot --path . --script tools/characters/render_icon.gd -- res://assets/models/Kaykit/characters/Mage.glb assets/sprites/ui/icons/mage_icon.png Head,Hat
   ```

   The script errors about `explosion.gd` because autoloads are missing in `--script` mode. They don't affect the icon.
3. Copy `src/player/characters/knight.tscn` to a new name. Replace `Knight` with the new character in the root node name, the model path, the icon path and the two arm paths.
4. Add the character to `CHARACTERS` in `src/autoload/character_roster.gd` so it shows in the character select. The grid has four columns.

## What a character scene provides

- **Root:** the imported model with `player_character.gd`, rotated 180° to face the player's forward direction.
- **Exports:** `arm_left`, `arm_right` and `health_bar_icon`. Weapons hide the arm meshes while carrying.
- **Animation:** `AnimationPlayer` and `AnimationTree` children, using the shared `player_animation_library.tres` and `player_animation_tree.tres`. The library must keep the name `Player`, because `play_hit_animation` looks up `Player/Hit_A`.
