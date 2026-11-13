class_name DevSettingsConfig
extends Resource

@export var enabled := true
## Set to a positive value to override scene HP. -1 keeps the scene default.
@export var player_max_hp_override := -1
@export var boss_hp_multiplier := 1.0
@export var enemy_hp_multiplier := 1.0
## Opens every level, world and weapon in the level select, ignoring save progress.
@export var unlock_all_levels := false
## Adds a checkpoint selector menu to the pause menu during levels.
@export var checkpoint_selector := false
## Hides the carry and front-carrier prompts and the bottom-right info message, for recording trailers.
@export var trailer_mode := false
