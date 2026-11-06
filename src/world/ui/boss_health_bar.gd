class_name BossHealthBar
extends MarginContainer

const INTRO_FADE_DURATION := 0.35
const INTRO_FILL_DURATION := 0.9
const TRAIL_DELAY := 0.4
const TRAIL_DURATION := 0.6
const HIT_FLASH_COLOR := Color(1.9, 1.9, 1.9, 1.0)
const HIT_FLASH_DURATION := 0.2
const PHASE_FLASH_COLOR := Color(2.6, 1.6, 1.2, 1.0)
const PHASE_FLASH_DURATION := 0.7
const PHASE_PUNCH_SCALE := Vector2(1.06, 1.06)
const DEATH_FLASH_DURATION := 0.15
const DEATH_FADE_DURATION := 0.8
## Health ratios that get a tick on the bar and a big flash when crossed (boss phase thresholds).
const PHASE_MARKERS: Array[float] = [0.5]
const MARKER_COLOR := Color(1, 0.88, 0.62, 0.85)
const MARKER_WIDTH := 3.0

@onready var _panel: PanelContainer = $PanelContainer
@onready var _icon: TextureRect = $PanelContainer/HBoxContainer/IconFrame/TextureRect
@onready var _name_label: Label = $PanelContainer/HBoxContainer/VBoxContainer/Header/NameLabel
@onready var _percent_label: Label = $PanelContainer/HBoxContainer/VBoxContainer/Header/PercentLabel
@onready var _bar_frame: PanelContainer = $PanelContainer/HBoxContainer/VBoxContainer/BarFrame
@onready var _trail_bar: ProgressBar = $PanelContainer/HBoxContainer/VBoxContainer/BarFrame/Bars/TrailBar
@onready var _progress_bar: ProgressBar = $PanelContainer/HBoxContainer/VBoxContainer/BarFrame/Bars/ProgressBar
@onready var _markers: Control = $PanelContainer/HBoxContainer/VBoxContainer/BarFrame/Bars/Markers

var _health: Health = null
var _intro_tween: Tween = null
var _trail_tween: Tween = null
var _flash_tween: Tween = null
var _death_tween: Tween = null


func _ready() -> void:
	_markers.draw.connect(_draw_markers)
	_panel.resized.connect(_center_panel_pivot)
	hide()


func _exit_tree() -> void:
	unbind()


func bind(health: Health, icon: Texture2D = null, boss_name: String = "") -> void:
	unbind()
	if health == null:
		return
	if icon != null:
		_icon.texture = icon
	_apply_name(boss_name)
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
	_kill_all_tweens()
	_reset_visual_state()
	show()
	_play_intro()


func hide_bar() -> void:
	unbind()
	_kill_all_tweens()
	_reset_visual_state()
	hide()


func _apply_name(boss_name: String) -> void:
	_name_label.text = boss_name
	_name_label.visible = not boss_name.is_empty()


func _sync_from_health() -> void:
	if _health == null:
		return
	_progress_bar.max_value = _health.max_hp
	_trail_bar.max_value = _health.max_hp
	_progress_bar.value = _health.current_hp
	_trail_bar.value = _health.current_hp
	_update_percent(_health.current_hp)
	_markers.queue_redraw()


func _play_intro() -> void:
	var target := _progress_bar.value
	modulate.a = 0.0
	_progress_bar.value = 0.0
	_trail_bar.value = 0.0
	_intro_tween = create_tween()
	_intro_tween.tween_property(self, "modulate:a", 1.0, INTRO_FADE_DURATION)
	_intro_tween.tween_property(_progress_bar, "value", target, INTRO_FILL_DURATION) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_intro_tween.parallel().tween_property(_trail_bar, "value", target, INTRO_FILL_DURATION) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _apply_damage(previous: int, remaining: int) -> void:
	_finish_intro()
	_progress_bar.value = remaining
	_update_percent(remaining)
	_play_trail(remaining)
	if _crossed_phase_marker(previous, remaining):
		_play_phase_flash()
		return
	_play_hit_flash()


func _finish_intro() -> void:
	if _intro_tween == null or not _intro_tween.is_valid():
		return
	_intro_tween.kill()
	modulate.a = 1.0
	_trail_bar.value = _progress_bar.max_value


func _update_percent(remaining: int) -> void:
	var ratio := float(remaining) / maxf(_progress_bar.max_value, 1.0)
	_percent_label.text = "%d%%" % ceili(ratio * 100.0)


func _play_trail(remaining: int) -> void:
	_kill_tween(_trail_tween)
	_trail_tween = create_tween()
	_trail_tween.tween_interval(TRAIL_DELAY)
	_trail_tween.tween_property(_trail_bar, "value", float(remaining), TRAIL_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_hit_flash() -> void:
	_kill_tween(_flash_tween)
	_bar_frame.modulate = HIT_FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_bar_frame, "modulate", Color.WHITE, HIT_FLASH_DURATION)


func _play_phase_flash() -> void:
	_kill_tween(_flash_tween)
	_bar_frame.modulate = Color.WHITE
	_panel.modulate = PHASE_FLASH_COLOR
	_panel.scale = PHASE_PUNCH_SCALE
	_flash_tween = create_tween().set_parallel()
	_flash_tween.tween_property(_panel, "modulate", Color.WHITE, PHASE_FLASH_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_panel, "scale", Vector2.ONE, PHASE_FLASH_DURATION * 0.6) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _crossed_phase_marker(previous: int, remaining: int) -> bool:
	var max_hp := maxf(_progress_bar.max_value, 1.0)
	var before := float(previous) / max_hp
	var after := float(remaining) / max_hp
	for marker in PHASE_MARKERS:
		if before > marker and after <= marker:
			return true
	return false


func _play_death() -> void:
	_kill_all_tweens()
	_progress_bar.value = 0.0
	_update_percent(0)
	_panel.modulate = HIT_FLASH_COLOR
	_death_tween = create_tween()
	_death_tween.tween_property(_panel, "modulate", Color.WHITE, DEATH_FLASH_DURATION)
	_death_tween.tween_property(_trail_bar, "value", 0.0, TRAIL_DURATION)
	_death_tween.tween_property(self, "modulate:a", 0.0, DEATH_FADE_DURATION)
	_death_tween.tween_callback(hide_bar)


func _reset_visual_state() -> void:
	modulate = Color.WHITE
	_panel.modulate = Color.WHITE
	_panel.scale = Vector2.ONE
	_bar_frame.modulate = Color.WHITE


func _kill_all_tweens() -> void:
	_kill_tween(_intro_tween)
	_kill_tween(_trail_tween)
	_kill_tween(_flash_tween)
	_kill_tween(_death_tween)


func _kill_tween(tween: Tween) -> void:
	if tween == null:
		return
	tween.kill()


func _center_panel_pivot() -> void:
	_panel.pivot_offset = _panel.size * 0.5


func _draw_markers() -> void:
	var width := _markers.size.x
	var height := _markers.size.y
	for marker in PHASE_MARKERS:
		var x := width * marker
		_markers.draw_line(Vector2(x, -2.0), Vector2(x, height + 2.0), MARKER_COLOR, MARKER_WIDTH)


func _on_health_damaged(amount: int, remaining: int, _source_position: Vector3) -> void:
	_apply_damage(remaining + amount, remaining)


func _on_health_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	unbind()
	_play_death()
