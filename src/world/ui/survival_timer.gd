class_name SurvivalTimer
extends MarginContainer
## HUD countdown for a running SurvivalEnemyGroup. The group binds itself when its fight starts;
## the widget then polls it and hides once the group is no longer active (cleared or reset).

const FADE_DURATION := 0.35
const URGENT_SECONDS := 10.0
const URGENT_COLOR := Color(1.0, 0.35, 0.3, 1.0)
const NORMAL_COLOR := Color(1.0, 0.88, 0.62, 1.0)
const PULSE_SCALE := Vector2(1.12, 1.12)
const PULSE_DURATION := 0.35
const CLEAR_TEXT := "Defeat the remaining enemies!"

@onready var _panel: PanelContainer = $PanelContainer
@onready var _title_label: Label = $PanelContainer/VBoxContainer/TitleLabel
@onready var _time_label: Label = $PanelContainer/VBoxContainer/TimeLabel
@onready var _progress_bar: ProgressBar = $PanelContainer/VBoxContainer/ProgressBar

var _group: SurvivalEnemyGroup = null
var _last_whole_second := -1
var _fade_tween: Tween = null
var _pulse_tween: Tween = null


func _ready() -> void:
	_time_label.resized.connect(_center_time_pivot)
	hide()
	set_process(false)


func bind(group: SurvivalEnemyGroup) -> void:
	if group == null:
		return
	_group = group
	_last_whole_second = -1
	_progress_bar.max_value = maxf(group.fight_duration, 0.01)
	_time_label.modulate = Color.WHITE
	_time_label.scale = Vector2.ONE
	_show_widget()
	set_process(true)
	_refresh()


func _process(_delta: float) -> void:
	if not _group_is_active():
		_unbind()
		return
	_refresh()


func _group_is_active() -> bool:
	if not is_instance_valid(_group):
		return false
	return _group.is_running()


func _refresh() -> void:
	var remaining := _group.get_time_remaining()
	_progress_bar.value = remaining
	if remaining <= 0.0:
		_show_clear_phase()
		return
	_title_label.text = "SURVIVE"
	_time_label.visible = true
	_time_label.text = _format_time(remaining)
	_update_urgency(remaining)


func _show_clear_phase() -> void:
	_title_label.text = CLEAR_TEXT
	_time_label.visible = false


func _update_urgency(remaining: float) -> void:
	var whole := ceili(remaining)
	if whole == _last_whole_second:
		return
	_last_whole_second = whole
	var urgent := remaining <= URGENT_SECONDS
	_time_label.add_theme_color_override("font_color", URGENT_COLOR if urgent else NORMAL_COLOR)
	if not urgent:
		return
	_play_pulse()


func _play_pulse() -> void:
	_kill_tween(_pulse_tween)
	_time_label.scale = PULSE_SCALE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_time_label, "scale", Vector2.ONE, PULSE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _format_time(seconds: float) -> String:
	var whole := ceili(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


func _show_widget() -> void:
	_kill_tween(_fade_tween)
	modulate.a = 0.0
	show()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION)


func _unbind() -> void:
	_group = null
	set_process(false)
	_kill_tween(_pulse_tween)
	_kill_tween(_fade_tween)
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	_fade_tween.tween_callback(hide)


func _kill_tween(tween: Tween) -> void:
	if tween == null:
		return
	tween.kill()


func _center_time_pivot() -> void:
	_time_label.pivot_offset = _time_label.size * 0.5
