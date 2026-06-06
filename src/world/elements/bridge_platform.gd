class_name BridgePlatform
extends Node3D

@export var start_at_bottom: bool = true

# Called when the node enters the scene tree for the first time.
func _ready():
	if start_at_bottom:
		$AnimationPlayer.play("bottom")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
