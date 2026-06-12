extends Button


func _ready() -> void:
	text = PlaytestFeedback.DISCORD_BUTTON_TEXT
	pressed.connect(PlaytestFeedback.open_discord)
