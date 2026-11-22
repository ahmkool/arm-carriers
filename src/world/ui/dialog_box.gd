class_name DialogBox
extends MarginContainer
## Zelda-style bottom dialog box with typewriter reveal, voice blips, and co-op advance input.

signal finished(completed: bool)

const ADVANCE_ACTIONS: Array[StringName] = [
	&"ui_accept",
	&"p0_accept",
	&"p1_accept",
	&"p0_shoot",
	&"p1_shoot",
	&"twinstick_p0_shoot",
	&"twinstick_p1_shoot",
	&"p0_action",
	&"p1_action",
]
const DEFAULT_VOICE_SOUND := preload("res://assets/sounds/wood/WoodStep05.wav")
const ADVANCE_SOUND := preload("res://assets/sounds/wood/WoodStep09.wav")

const CHARS_PER_SECOND := 38.0
const SENTENCE_PAUSE_SEC := 0.14
const COMMA_PAUSE_SEC := 0.07
const VOICE_CHAR_STEP := 3
const VOICE_VOLUME_DB := -15.0
const ADVANCE_VOLUME_DB := -10.0
const ADVANCE_PITCH := 1.15
const OPEN_DURATION := 0.24
const CLOSE_DURATION := 0.16
const OPEN_INPUT_GUARD_SEC := 0.2
const STEP_INPUT_GUARD_SEC := 0.08
const INDICATOR_COLOR := Color(1.0, 0.88, 0.52, 1.0)
const INDICATOR_SHADOW := Color(0.05, 0.04, 0.07, 0.85)
const INDICATOR_BOB_SPEED := 6.5
const INDICATOR_BOB_AMPLITUDE := 3.5


class AdvanceIndicator:
	extends Control

	var is_final := false
	var bob_offset := 0.0

	func _draw() -> void:
		var center := size * 0.5 + Vector2(0.0, bob_offset)
		var points := _diamond_points(center) if is_final else _triangle_points(center)
		var shadow_points := _offset_points(points, Vector2(0.0, 2.0))
		draw_colored_polygon(shadow_points, INDICATOR_SHADOW)
		draw_colored_polygon(points, INDICATOR_COLOR)

	func _triangle_points(center: Vector2) -> PackedVector2Array:
		return PackedVector2Array([
			center + Vector2(-8.0, -5.0),
			center + Vector2(8.0, -5.0),
			center + Vector2(0.0, 6.0),
		])

	func _diamond_points(center: Vector2) -> PackedVector2Array:
		return PackedVector2Array([
			center + Vector2(0.0, -7.0),
			center + Vector2(7.0, 0.0),
			center + Vector2(0.0, 7.0),
			center + Vector2(-7.0, 0.0),
		])

	func _offset_points(points: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
		var shifted := PackedVector2Array()
		for point in points:
			shifted.append(point + delta)
		return shifted


@onready var _panel: PanelContainer = $PanelContainer
@onready var _portrait_frame: PanelContainer = $PanelContainer/HBoxContainer/PortraitFrame
@onready var _portrait_texture: TextureRect = $PanelContainer/HBoxContainer/PortraitFrame/PortraitTexture
@onready var _header_row: HBoxContainer = $PanelContainer/HBoxContainer/ContentColumn/HeaderRow
@onready var _speaker_label: Label = $PanelContainer/HBoxContainer/ContentColumn/HeaderRow/SpeakerLabel
@onready var _page_label: Label = $PanelContainer/HBoxContainer/ContentColumn/HeaderRow/PageLabel
@onready var _divider: ColorRect = $PanelContainer/HBoxContainer/ContentColumn/Divider
@onready var _text_label: RichTextLabel = $PanelContainer/HBoxContainer/ContentColumn/TextLabel
@onready var _footer_row: HBoxContainer = $PanelContainer/HBoxContainer/ContentColumn/FooterRow
@onready var _prompt_label: Label = $PanelContainer/HBoxContainer/ContentColumn/FooterRow/PromptLabel
@onready var _indicator_slot: Control = $PanelContainer/HBoxContainer/ContentColumn/FooterRow/IndicatorSlot

var _indicator: AdvanceIndicator
var _voice_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer

var _is_active := false
var _is_closing := false
var _lines: PackedStringArray = PackedStringArray()
var _line_index := 0
var _parsed_text := ""
var _total_chars := 0
var _revealed_chars := 0
var _voice_chars_counted := 0
var _char_accumulator := 0.0
var _pause_remaining := 0.0
var _is_line_complete := false
var _input_unlock_time := 0.0
var _bob_time := 0.0
var _voice_stream: AudioStream = DEFAULT_VOICE_SOUND
var _voice_pitch := 0.48
var _box_tween: Tween = null


func _ready() -> void:
	_setup_audio_players()
	_setup_indicator()
	_panel.resized.connect(_center_panel_pivot)
	set_process(false)
	set_process_unhandled_input(false)
	hide()


func is_open() -> bool:
	return _is_active


## Displays a sequence of lines and resolves true when finished or false if cancelled.
func play_dialog(
	speaker_name: String,
	lines: PackedStringArray,
	portrait: Texture2D = null,
	voice_stream: AudioStream = null,
	voice_pitch: float = 0.48
) -> bool:
	if lines.is_empty():
		return true
	if _is_active:
		cancel()
	_hide_overlapping_launch_hint()
	_configure_content(speaker_name, lines, portrait, voice_stream, voice_pitch)
	_begin_active_state()
	_play_open_animation()
	_start_line(0)
	var completed: bool = await finished
	return completed


func cancel() -> void:
	if not _is_active:
		return
	_kill_box_tween()
	_stop_active_state()
	hide()
	finished.emit(false)


func _process(delta: float) -> void:
	if not _is_active or _is_closing:
		return
	_update_indicator_bob(delta)
	_step_typewriter(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_handle_advance(event):
		return
	_mark_input_handled()
	_handle_advance_pressed()


func _setup_audio_players() -> void:
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = &"SFX"
	_voice_player.volume_db = VOICE_VOLUME_DB
	add_child(_voice_player)

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = &"SFX"
	_sfx_player.stream = ADVANCE_SOUND
	_sfx_player.volume_db = ADVANCE_VOLUME_DB
	add_child(_sfx_player)


func _setup_indicator() -> void:
	_indicator = AdvanceIndicator.new()
	_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator_slot.add_child(_indicator)


func _configure_content(
	speaker_name: String,
	lines: PackedStringArray,
	portrait: Texture2D,
	voice_stream: AudioStream,
	voice_pitch: float
) -> void:
	_lines = lines.duplicate()
	_line_index = 0
	_voice_stream = voice_stream if voice_stream != null else DEFAULT_VOICE_SOUND
	_voice_pitch = voice_pitch

	var has_portrait := portrait != null
	_portrait_frame.visible = has_portrait
	_portrait_texture.texture = portrait

	var has_speaker := not speaker_name.is_empty()
	_speaker_label.text = speaker_name
	_speaker_label.visible = has_speaker
	_header_row.visible = has_speaker or _lines.size() > 1
	_divider.visible = has_speaker


func _begin_active_state() -> void:
	_is_active = true
	_is_closing = false
	_input_unlock_time = _now() + OPEN_INPUT_GUARD_SEC
	set_process(true)
	set_process_unhandled_input(true)
	show()


func _stop_active_state() -> void:
	_is_active = false
	_is_closing = false
	set_process(false)
	set_process_unhandled_input(false)


func _start_line(index: int) -> void:
	_line_index = index
	_text_label.text = _lines[index]
	_parsed_text = _text_label.get_parsed_text()
	_total_chars = _parsed_text.length()
	_revealed_chars = 0
	_voice_chars_counted = 0
	_char_accumulator = 0.0
	_pause_remaining = 0.0
	_bob_time = 0.0
	_text_label.visible_characters = 0
	_is_line_complete = _total_chars == 0
	_update_page_label()
	_update_footer_visibility()


func _update_page_label() -> void:
	var show_pages := _lines.size() > 1
	_page_label.visible = show_pages
	if not show_pages:
		return
	_page_label.text = "%d / %d" % [_line_index + 1, _lines.size()]


func _update_footer_visibility() -> void:
	var is_last := _line_index >= _lines.size() - 1
	_indicator.is_final = is_last
	_indicator.queue_redraw()
	_prompt_label.text = "Space / A"
	_footer_row.modulate.a = 1.0 if _is_line_complete else 0.0


func _step_typewriter(delta: float) -> void:
	if _is_line_complete:
		return
	if _pause_remaining > 0.0:
		_pause_remaining = maxf(0.0, _pause_remaining - delta)
		return
	_char_accumulator += delta * CHARS_PER_SECOND
	while _char_accumulator >= 1.0 and not _is_line_complete:
		_char_accumulator -= 1.0
		_reveal_next_character()
		if _pause_remaining > 0.0:
			break


func _reveal_next_character() -> void:
	if _revealed_chars >= _total_chars:
		_finish_current_line()
		return
	var ch := _parsed_text.substr(_revealed_chars, 1)
	_revealed_chars += 1
	_text_label.visible_characters = _revealed_chars
	_maybe_play_voice_blip(ch)
	_apply_punctuation_pause(ch)
	if _revealed_chars >= _total_chars:
		_finish_current_line()


func _finish_current_line() -> void:
	_revealed_chars = _total_chars
	_text_label.visible_characters = -1
	_is_line_complete = true
	_bob_time = 0.0
	_update_footer_visibility()


func _maybe_play_voice_blip(ch: String) -> void:
	if ch.strip_edges().is_empty():
		return
	_voice_chars_counted += 1
	if (_voice_chars_counted - 1) % VOICE_CHAR_STEP != 0:
		return
	if _voice_stream == null:
		return
	_voice_player.stream = _voice_stream
	_voice_player.pitch_scale = _voice_pitch * randf_range(0.92, 1.08)
	_voice_player.play()


func _apply_punctuation_pause(ch: String) -> void:
	if ch == "." or ch == "!" or ch == "?":
		_pause_remaining = SENTENCE_PAUSE_SEC
		return
	if ch == "," or ch == ";" or ch == ":":
		_pause_remaining = COMMA_PAUSE_SEC


func _update_indicator_bob(delta: float) -> void:
	if not _is_line_complete:
		return
	_bob_time += delta
	_indicator.bob_offset = sin(_bob_time * INDICATOR_BOB_SPEED) * INDICATOR_BOB_AMPLITUDE
	_indicator.queue_redraw()


func _can_handle_advance(event: InputEvent) -> bool:
	if not _is_active or _is_closing:
		return false
	if not is_inside_tree() or get_tree().paused:
		return false
	if _now() < _input_unlock_time:
		return false
	return _is_advance_event(event)


func _is_advance_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		return click.button_index == MOUSE_BUTTON_LEFT and click.pressed
	if not event.is_pressed() or event.is_echo():
		return false
	for action in ADVANCE_ACTIONS:
		if event.is_action(action):
			return true
	return false


func _handle_advance_pressed() -> void:
	_input_unlock_time = _now() + STEP_INPUT_GUARD_SEC
	if not _is_line_complete:
		_finish_current_line()
		return
	_play_advance_sfx()
	if _line_index + 1 < _lines.size():
		_start_line(_line_index + 1)
		return
	_begin_close()


func _begin_close() -> void:
	_is_closing = true
	_play_close_animation()


func _play_open_animation() -> void:
	_kill_box_tween()
	modulate.a = 0.0
	_center_panel_pivot()
	_center_panel_pivot.call_deferred()
	_panel.scale = Vector2(0.92, 0.92)
	_box_tween = create_tween().set_parallel()
	_box_tween.tween_property(self, "modulate:a", 1.0, OPEN_DURATION * 0.7)
	_box_tween.tween_property(_panel, "scale", Vector2.ONE, OPEN_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_close_animation() -> void:
	_kill_box_tween()
	_center_panel_pivot()
	_box_tween = create_tween().set_parallel()
	_box_tween.tween_property(self, "modulate:a", 0.0, CLOSE_DURATION)
	_box_tween.tween_property(_panel, "scale", Vector2(0.95, 0.95), CLOSE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_box_tween.chain().tween_callback(_complete_close)


func _complete_close() -> void:
	if not _is_active:
		return
	_stop_active_state()
	modulate.a = 1.0
	_panel.scale = Vector2.ONE
	hide()
	finished.emit(true)


func _play_advance_sfx() -> void:
	_sfx_player.pitch_scale = ADVANCE_PITCH * randf_range(0.96, 1.04)
	_sfx_player.play()


func _hide_overlapping_launch_hint() -> void:
	var ui := get_parent()
	if ui == null:
		return
	var hint := ui.get_node_or_null("InfoMessageBottomRight") as Control
	if hint == null:
		return
	hint.hide()


func _kill_box_tween() -> void:
	if _box_tween == null:
		return
	_box_tween.kill()
	_box_tween = null


func _center_panel_pivot() -> void:
	_panel.pivot_offset = _panel.size * 0.5


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.set_input_as_handled()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
