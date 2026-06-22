class_name PlayerHealthBar
extends HBoxContainer

@onready var _icon: TextureRect = $Icon
@onready var _progress_bar: ProgressBar = $ProgressBar

var _health: Health = null


func _ready() -> void:
	_icon.hide()
	hide()


func _exit_tree() -> void:
	unbind()


func bind(health: Health, icon: Texture2D = null) -> void:
	unbind()
	if health == null:
		return
	_apply_icon(icon)
	_health = health
	_health.damaged.connect(_on_health_damaged)
	_health.died.connect(_on_health_died)
	_health.restored.connect(_on_health_restored)
	_sync_from_health()
	show()


func unbind() -> void:
	if _health == null:
		return
	if _health.damaged.is_connected(_on_health_damaged):
		_health.damaged.disconnect(_on_health_damaged)
	if _health.died.is_connected(_on_health_died):
		_health.died.disconnect(_on_health_died)
	if _health.restored.is_connected(_on_health_restored):
		_health.restored.disconnect(_on_health_restored)
	_health = null


func hide_bar() -> void:
	unbind()
	hide()


func _apply_icon(icon: Texture2D) -> void:
	if icon == null:
		_icon.hide()
		return
	_icon.texture = icon
	_icon.show()


func _sync_from_health() -> void:
	if _health == null:
		return
	_progress_bar.max_value = _health.max_hp
	_progress_bar.value = _health.current_hp


func _on_health_damaged(_amount: int, remaining: int, _source_position: Vector3) -> void:
	_progress_bar.value = remaining


func _on_health_restored() -> void:
	_sync_from_health()


func _on_health_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	_progress_bar.value = 0
