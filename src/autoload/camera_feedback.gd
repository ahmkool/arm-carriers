extends Node

const TRAUMA_SHOT := 1.5
const TRAUMA_DASH := 0.9
const TRAUMA_HURT := 0.42

## Fullscreen darken scales with trauma²; keep low — large values read as a “black flash”.
@export var vignette_enabled: bool = false
@export_range(0.0, 1.0, 0.01) var vignette_max_alpha: float = 0.12
@export_range(0.0, 1.0, 0.01) var vignette_from_trauma_scale: float = 0.14

var _pivot: Node3D
var _vignette_layer: CanvasLayer
var _vignette_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_setup_vignette")


func _setup_vignette() -> void:
	if Engine.is_editor_hint():
		return
	if not vignette_enabled:
		return
	if _vignette_rect != null:
		return
	_vignette_layer = CanvasLayer.new()
	_vignette_layer.layer = 100
	_vignette_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_vignette_layer)
	_vignette_rect = ColorRect.new()
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.color = Color(0, 0, 0, 0)
	_vignette_layer.add_child(_vignette_rect)


func register_shake_pivot(pivot: Node3D) -> void:
	_pivot = pivot


func add_trauma(amount: float) -> void:
	_refresh_pivot()
	if _pivot != null and _pivot.has_method("add_trauma"):
		_pivot.call("add_trauma", amount)


func add_trauma_shot() -> void:
	add_trauma(TRAUMA_SHOT)


func add_trauma_dash() -> void:
	add_trauma(TRAUMA_DASH)


func add_trauma_hurt() -> void:
	add_trauma(TRAUMA_HURT)


func _refresh_pivot() -> void:
	if _pivot != null and is_instance_valid(_pivot):
		return
	_pivot = get_tree().get_first_node_in_group("camera_shake") as Node3D


func _process(_delta: float) -> void:
	if not vignette_enabled or _vignette_rect == null:
		return
	_refresh_pivot()
	var t := 0.0
	if _pivot != null and _pivot.has_method("get_trauma"):
		t = _pivot.call("get_trauma")
	var alpha := t * t * vignette_from_trauma_scale
	_vignette_rect.color = Color(0, 0, 0, clampf(alpha, 0.0, vignette_max_alpha))
