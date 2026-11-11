extends Node
## Plays the skull's "spawn" animation (it grows from nothing, with a little overshoot), then its flying loop.

@export var animation_player: AnimationPlayer
@export var spawn_animation := &"spawn"
@export var loop_animation := &"flying"


func _ready() -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation(spawn_animation):
		animation_player.play(loop_animation)
		return
	animation_player.play(spawn_animation)
	animation_player.queue(loop_animation)
