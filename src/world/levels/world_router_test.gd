extends Node3D

@export var level: PackedScene

const LOADED_LEVEL_NODE_NAME := "LoadedLevel"


func _ready() -> void:
	_load_selected_level()


func _load_selected_level() -> void:
	var existing_level := get_node_or_null(LOADED_LEVEL_NODE_NAME)
	if existing_level != null:
		existing_level.queue_free()

	if level == null:
		push_warning("WorldRouterTest: no level assigned.")
		return

	var level_instance := level.instantiate() as Node3D
	if level_instance == null:
		push_error("WorldRouterTest: assigned scene root must be Node3D.")
		return

	level_instance.name = LOADED_LEVEL_NODE_NAME
	add_child(level_instance)
