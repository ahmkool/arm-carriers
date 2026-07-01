class_name YouDiedScreen
extends Control

@onready var _animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	hide_screen()


func show_and_animate() -> void:
	modulate = Color(1, 1, 1, 0)
	show()
	_animation_player.play(&"animate")


func hide_screen() -> void:
	if _animation_player.is_playing():
		_animation_player.stop()
	modulate = Color(1, 1, 1, 0)
	hide()
