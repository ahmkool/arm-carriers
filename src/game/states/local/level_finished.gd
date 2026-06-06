extends GameState


func enter() -> void:
	self.world.get_node("UI/InfoMessage").show()
	self.world.get_node("UI/InfoMessage/PanelContainer/MarginContainer/InfoLabel").text = "Level Complete! - Press Start to return to the main menu"

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	if Input.is_action_just_pressed("p0_start") or Input.is_action_just_pressed("p1_start"):
		SessionFlow.go_to_main_menu()
