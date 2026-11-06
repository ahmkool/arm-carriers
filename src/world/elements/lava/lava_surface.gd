extends Node3D
## The molten surface. A carrier who falls in throws up a splash where they hit.
## The level's FallArea handles the game over; this only adds the feedback.

@onready var _catch_area: Area3D = $CatchArea
@onready var _splash: GPUParticles3D = $Splash


func _ready() -> void:
	_catch_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is not PlayerLocal:
		return
	_splash.global_position = Vector3(body.global_position.x, global_position.y, body.global_position.z)
	_splash.restart()
