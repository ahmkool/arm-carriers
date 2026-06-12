class_name InfoMessagePresenter

const LABEL_PATH := "PanelContainer/MarginContainer/VBoxContainer/InfoLabel"
const DISCORD_BUTTON_PATH := "PanelContainer/MarginContainer/VBoxContainer/DiscordButton"


static func show_level_complete(info_message: Control) -> void:
	var label := info_message.get_node(LABEL_PATH) as Label
	label.text = PlaytestFeedback.LEVEL_COMPLETE_NOTICE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_message.get_node(DISCORD_BUTTON_PATH).show()
	info_message.show()


static func hide_feedback_controls(info_message: Control) -> void:
	info_message.get_node(DISCORD_BUTTON_PATH).hide()
