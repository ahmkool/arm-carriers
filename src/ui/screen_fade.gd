extends Node

const DEFAULT_FADE_DURATION := 0.35
const FADE_LAYER := 101

var _layer: CanvasLayer
var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_ensure_overlay")

func fade_to_black(duration: float = DEFAULT_FADE_DURATION) -> void:
	_ensure_overlay()
	_kill_tween()
	_tween_alpha_to(1.0, duration)

func fade_from_black(duration: float = DEFAULT_FADE_DURATION) -> void:
	_ensure_overlay()
	_kill_tween()
	_tween_alpha_to(0.0, duration)

func _ensure_overlay() -> void:
	if Engine.is_editor_hint():
		return
	if _rect != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = FADE_LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(0, 0, 0, 0)
	_layer.add_child(_rect)

func _tween_alpha_to(target_alpha: float, duration: float) -> Tween:
	var start_alpha := _rect.color.a
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_method(_set_alpha, start_alpha, target_alpha, duration)
	return _tween

func _set_alpha(alpha: float) -> void:
	if _rect == null:
		return
	_rect.color = Color(0, 0, 0, alpha)

func _kill_tween() -> void:
	if _tween == null:
		return
	_tween.kill()
	_tween = null
