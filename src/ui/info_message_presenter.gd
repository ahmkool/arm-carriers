class_name InfoMessagePresenter

const CONTENT_VBOX_NAME := "ContentVBox"
const DISCORD_BUTTON_NAME := "DiscordButton"


static func show_level_complete(info_message: Control) -> void:
	_prepare_level_complete_layout(info_message)
	info_message.show()


static func hide_feedback_controls(info_message: Control) -> void:
	var button := _discord_button(info_message)
	if button == null:
		return
	button.hide()


static func _prepare_level_complete_layout(info_message: Control) -> void:
	var label := _info_label(info_message)
	if label == null:
		return
	label.text = PlaytestFeedback.LEVEL_COMPLETE_NOTICE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var button := _ensure_discord_button(info_message)
	if button == null:
		return
	button.show()


static func _ensure_discord_button(info_message: Control) -> Button:
	var existing := _discord_button(info_message)
	if existing != null:
		return existing
	var margin := _margin_container(info_message)
	if margin == null:
		return null
	var label := _info_label(info_message)
	if label == null:
		return null
	var vbox := VBoxContainer.new()
	vbox.name = CONTENT_VBOX_NAME
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.remove_child(label)
	vbox.add_child(label)
	var button := _create_discord_button()
	vbox.add_child(button)
	margin.add_child(vbox)
	return button


static func _create_discord_button() -> Button:
	var button := Button.new()
	button.name = DISCORD_BUTTON_NAME
	button.text = PlaytestFeedback.DISCORD_BUTTON_TEXT
	button.pressed.connect(PlaytestFeedback.open_discord)
	return button


static func _margin_container(info_message: Control) -> MarginContainer:
	return info_message.get_node_or_null("PanelContainer/MarginContainer") as MarginContainer


static func _info_label(info_message: Control) -> Label:
	var margin := _margin_container(info_message)
	if margin == null:
		return null
	var vbox := margin.get_node_or_null(CONTENT_VBOX_NAME) as VBoxContainer
	if vbox != null:
		return vbox.get_node_or_null("InfoLabel") as Label
	return margin.get_node_or_null("InfoLabel") as Label


static func _discord_button(info_message: Control) -> Button:
	var margin := _margin_container(info_message)
	if margin == null:
		return null
	var vbox := margin.get_node_or_null(CONTENT_VBOX_NAME) as VBoxContainer
	if vbox == null:
		return null
	return vbox.get_node_or_null(DISCORD_BUTTON_NAME) as Button
