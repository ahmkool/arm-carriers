extends Node

const FADE_OUT_DURATION := 0.5
const INFO_MESSAGE_PATH := "UI/InfoMessageBottomRight"
const INFO_LABEL_PATH := "UI/InfoMessageBottomRight/PanelContainer/MarginContainer/InfoLabel"

@export var duration_in_seconds: float = 5
@export_multiline var message_string: String

var _fade_tween: Tween = null


func _ready() -> void:
	if message_string.is_empty():
		return
	var world := LevelNodes.find_world(self)
	if world == null:
		return
	var container := world.get_node_or_null(INFO_MESSAGE_PATH) as Control
	if container == null:
		return
	var label := world.get_node_or_null(INFO_LABEL_PATH) as RichTextLabel
	if label == null:
		return
	label.text = message_string
	container.modulate.a = 1.0
	container.show()
	_begin_dismiss_sequence(container)


func _begin_dismiss_sequence(container: Control) -> void:
	await get_tree().create_timer(duration_in_seconds).timeout
	if not is_inside_tree():
		return
	_fade_out(container)


func _fade_out(container: Control) -> void:
	_kill_fade_tween()
	_fade_tween = create_tween()
	_fade_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fade_tween.tween_property(container, "modulate:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.chain().tween_callback(container.hide)


func _kill_fade_tween() -> void:
	if _fade_tween == null:
		return
	_fade_tween.kill()
	_fade_tween = null
