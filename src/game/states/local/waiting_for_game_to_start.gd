extends GameState

func enter():
	self.world.get_node("UI/InfoMessage/PanelContainer/MarginContainer/InfoLabel").text = "Player 1 press start to start the game"
	
