class_name PlayerHealthBar
extends HBoxContainer

const TRAIL_DELAY := 0.35
const TRAIL_DURATION := 0.45
const HIT_FLASH_COLOR := Color(2.2, 2.2, 2.2, 1.0)
const ICON_HIT_COLOR := Color(1.8, 0.55, 0.5, 1.0)
const ICON_HIT_SCALE := Vector2(1.18, 1.18)
const LOW_HP_RATIO := 0.34
const LOW_HP_PULSE_COLOR := Color(1.7, 1.25, 1.25, 1.0)
const LOW_HP_PULSE_HALF_PERIOD := 0.35
const SEGMENT_LINE_COLOR := Color(0.03, 0.03, 0.05, 0.9)
const SEGMENT_LINE_WIDTH := 3.0
const MAX_SEGMENTS := 12

@onready var _icon_frame: PanelContainer = $IconFrame
@onready var _icon: TextureRect = $IconFrame/Icon
@onready var _hp_label: Label = $BarStack/HpLabel
@onready var _bar_frame: PanelContainer = $BarStack/BarFrame
@onready var _trail_bar: ProgressBar = $BarStack/BarFrame/Bars/TrailBar
@onready var _progress_bar: ProgressBar = $BarStack/BarFrame/Bars/ProgressBar
@onready var _segments: Control = $BarStack/BarFrame/Bars/Segments

var _health: Health = null
var _trail_tween: Tween = null
var _hit_tween: Tween = null
var _pulse_tween: Tween = null


func _ready() -> void:
	_icon_frame.hide()
	_segments.draw.connect(_draw_segments)
	_icon_frame.resized.connect(_center_icon_pivot)
	_center_icon_pivot()
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
	_stop_low_hp_pulse()
	hide()


func _apply_icon(icon: Texture2D) -> void:
	if icon == null:
		_icon_frame.hide()
		return
	_icon.texture = icon
	_icon_frame.show()


func _sync_from_health() -> void:
	if _health == null:
		return
	_kill_tween(_trail_tween)
	_progress_bar.max_value = _health.max_hp
	_trail_bar.max_value = _health.max_hp
	_progress_bar.value = _health.current_hp
	_trail_bar.value = _health.current_hp
	_update_label(_health.current_hp)
	_update_low_hp_pulse(_health.current_hp)
	_segments.queue_redraw()


func _set_hp(remaining: int) -> void:
	_progress_bar.value = remaining
	_update_label(remaining)
	_update_low_hp_pulse(remaining)
	_play_trail(remaining)
	_play_hit_feedback()


func _update_label(remaining: int) -> void:
	_hp_label.text = "%d / %d" % [remaining, int(_progress_bar.max_value)]


func _play_trail(remaining: int) -> void:
	_kill_tween(_trail_tween)
	_trail_tween = create_tween()
	_trail_tween.tween_interval(TRAIL_DELAY)
	_trail_tween.tween_property(_trail_bar, "value", float(remaining), TRAIL_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_hit_feedback() -> void:
	_kill_tween(_hit_tween)
	_bar_frame.modulate = HIT_FLASH_COLOR
	_icon.modulate = ICON_HIT_COLOR
	_icon_frame.scale = ICON_HIT_SCALE
	_hit_tween = create_tween().set_parallel()
	_hit_tween.tween_property(_bar_frame, "modulate", Color.WHITE, 0.25)
	_hit_tween.tween_property(_icon, "modulate", Color.WHITE, 0.35)
	_hit_tween.tween_property(_icon_frame, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_low_hp_pulse(remaining: int) -> void:
	if not _is_low_hp(remaining):
		_stop_low_hp_pulse()
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_progress_bar, "self_modulate", LOW_HP_PULSE_COLOR, LOW_HP_PULSE_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_progress_bar, "self_modulate", Color.WHITE, LOW_HP_PULSE_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE)


func _is_low_hp(remaining: int) -> bool:
	if remaining <= 0:
		return false
	return float(remaining) / maxf(_progress_bar.max_value, 1.0) <= LOW_HP_RATIO


func _stop_low_hp_pulse() -> void:
	_kill_tween(_pulse_tween)
	_pulse_tween = null
	_progress_bar.self_modulate = Color.WHITE


func _kill_tween(tween: Tween) -> void:
	if tween == null:
		return
	tween.kill()


func _center_icon_pivot() -> void:
	_icon_frame.pivot_offset = _icon_frame.size * 0.5


## Draws dividers between HP pips so small HP pools read as discrete hits.
func _draw_segments() -> void:
	var segment_count := int(_progress_bar.max_value)
	if segment_count <= 1 or segment_count > MAX_SEGMENTS:
		return
	var width := _segments.size.x
	var height := _segments.size.y
	for i in range(1, segment_count):
		var x := width * float(i) / float(segment_count)
		_segments.draw_line(Vector2(x, 0.0), Vector2(x, height), SEGMENT_LINE_COLOR, SEGMENT_LINE_WIDTH)


func _on_health_damaged(_amount: int, remaining: int, _source_position: Vector3) -> void:
	_set_hp(remaining)


func _on_health_restored() -> void:
	_sync_from_health()


func _on_health_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	# `damaged` already played the hit feedback for the killing blow.
	_progress_bar.value = 0
	_update_label(0)
	_stop_low_hp_pulse()
