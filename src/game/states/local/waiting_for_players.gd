extends GameState

func enter():
	print("Entering waiting for players state")

func exit():
	print("Exiting waiting for players state")

func update(_delta: float):
	pass

func physics_update(_delta: float):
	if Input.is_action_just_pressed("p0_start"):
		print("Player 0 pressed start")
		self.world.players.add_player(0)
	if Input.is_action_just_pressed("p1_start"):
		print("Player 1 pressed start")
		self.world.players.add_player(1)
	
	var number_of_players = self.world.players.get_child_count()
	if number_of_players >= 2:
		self.game_state_machine.transition_to("playing")
