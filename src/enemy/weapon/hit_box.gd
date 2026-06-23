extends Area3D

@export var damage: int = 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	print("monitorable: ", monitorable)
	print("monitoring: ", monitoring)

func _on_body_entered(body: Node) -> void:
	if body is not PlayerLocal:
		return
	var player := body as PlayerLocal
	if player == null:
		return
	print("DAMAGIIIIIING")
	CameraFeedback.add_trauma_hurt()
	Health.apply_damage(player, damage, global_position)
