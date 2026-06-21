class_name BossHealthBar
extends MarginContainer

@onready var _progress_bar: ProgressBar = $PanelContainer/MarginContainer/HBoxContainer/ProgressBar
@onready var _icon: TextureRect = $PanelContainer/MarginContainer/HBoxContainer/TextureRect

var _health: Health = null


func _ready() -> void:
	hide()


func _exit_tree() -> void:
	unbind()


func bind(health: Health, icon: Texture2D = null) -> void:
	unbind()
	if health == null:
		return
	if icon != null:
		_icon.texture = icon
	_health = health
	_health.damaged.connect(_on_health_damaged)
	_health.died.connect(_on_health_died)
	_sync_from_health()
	show_bar()


func unbind() -> void:
	if _health == null:
		return
	if _health.damaged.is_connected(_on_health_damaged):
		_health.damaged.disconnect(_on_health_damaged)
	if _health.died.is_connected(_on_health_died):
		_health.died.disconnect(_on_health_died)
	_health = null


func show_bar() -> void:
	show()


func hide_bar() -> void:
	unbind()
	hide()


func _sync_from_health() -> void:
	if _health == null:
		return
	_progress_bar.max_value = _health.max_hp
	_progress_bar.value = _health.current_hp


func _on_health_damaged(_amount: int, remaining: int, _source_position: Vector3) -> void:
	_progress_bar.value = remaining


func _on_health_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	hide_bar()
