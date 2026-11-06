class_name CharacterSelect
extends Control
## Both players pick a character at the same time. Each moves their own cursor over the roster
## and locks in; a character one player has locked in can't be taken by the other.
## Player 1 uses the p0_* actions and gamepad 0, player 2 the p1_* actions and gamepad 1.

const FONT := preload("res://assets/fonts/Lilita_One/LilitaOne-Regular.ttf")
const SOUND_TICKS: Array[AudioStream] = [
	preload("res://assets/sounds/wood/WoodStep01.wav"),
	preload("res://assets/sounds/wood/WoodStep05.wav"),
	preload("res://assets/sounds/wood/WoodStep09.wav"),
]

const PLAYER_COLORS: Array[Color] = [Color(0.22, 0.58, 1.0), Color(1.0, 0.4, 0.16)]
const MOVE_ACTIONS := {
	&"left": Vector2i(-1, 0),
	&"right": Vector2i(1, 0),
	&"up": Vector2i(0, -1),
	&"down": Vector2i(0, 1),
}
## Keyboard confirm keys come from these actions; gamepad A and B are read per device.
const CONFIRM_SUFFIXES: Array[String] = ["_start", "_action", "_accept"]
const GRID_COLUMNS := 4
const CARD_SIZE := Vector2(200.0, 250.0)
const CARD_GAP := 24.0
const GRID_TOP := 250.0
const PANEL_SIZE := Vector2(430.0, 660.0)
const PANEL_MARGIN := 56.0
const PANEL_TOP := 200.0
const INPUT_LOCK_SECONDS := 0.18
const ALL_READY_SECONDS := 0.9
const HINT_TEXT := "Move: stick / D-pad      Lock in: A      Cancel: B      Back: Esc"

## One roster slot: the character's head, its name, and frames for the players on it.
class Card:
	extends Control

	const INK := Color(0.27, 0.14, 0.06)
	const BOARD := Color(0.34, 0.15, 0.03, 0.94)
	const ICON_RECT := Rect2(15.0, 14.0, 170.0, 170.0)

	var icon: Texture2D
	var display_name := ""
	var rest_position := Vector2.ZERO
	var hovered_by: Array[bool] = [false, false]
	var locked_by := -1

	var _pop := MenuSpring.new(1.0, 360.0, 0.4)
	var _shake := MenuSpring.new(0.0, 1400.0, 0.12)
	var _time := 0.0

	func _process(delta: float) -> void:
		var step_delta := minf(delta, 1.0 / 30.0)
		_time += step_delta
		_pop.target = 1.08 if _is_hovered() else 1.0
		_pop.step(step_delta)
		_shake.step(step_delta)
		scale = Vector2.ONE * _pop.value
		position = rest_position + Vector2(_shake.value, 0.0)
		queue_redraw()

	func _draw() -> void:
		_draw_board()
		_draw_icon()
		_draw_name()
		for player in hovered_by.size():
			_draw_player_frame(player)
		_draw_lock_badge()

	func bump() -> void:
		_pop.velocity += 2.2

	func refuse() -> void:
		_shake.velocity += 900.0

	func _is_hovered() -> bool:
		return hovered_by[0] or hovered_by[1]

	func _draw_board() -> void:
		var style := StyleBoxFlat.new()
		style.bg_color = BOARD
		style.set_corner_radius_all(14)
		if locked_by >= 0:
			style.bg_color = PLAYER_COLORS[locked_by].darkened(0.45)
		draw_style_box(style, Rect2(Vector2.ZERO, size))

	func _draw_icon() -> void:
		var tint := Color.WHITE
		if locked_by >= 0:
			tint = Color(0.75, 0.75, 0.75)
		var bob := sin(_time * 3.0) * 4.0 if _is_hovered() else 0.0
		draw_texture_rect(icon, Rect2(ICON_RECT.position + Vector2(0.0, bob), ICON_RECT.size), false, tint)

	func _draw_name() -> void:
		var font_size := 28
		var width := size.x - 12.0
		var baseline := Vector2(6.0, size.y - 22.0)
		draw_string_outline(FONT, baseline, display_name, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 10, INK)
		draw_string(FONT, baseline, display_name, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, Color(0.98, 0.95, 0.86))

	## Player 1's frame sits outside player 2's, so both show when they share a card.
	func _draw_player_frame(player: int) -> void:
		if not hovered_by[player]:
			return
		var inset := -6.0 if player == 0 else 4.0
		var pulse := 1.0 + sin(_time * 6.0 + player * PI) * 0.15
		var style := StyleBoxFlat.new()
		style.draw_center = false
		style.border_color = PLAYER_COLORS[player]
		style.set_border_width_all(int(7.0 * pulse))
		style.set_corner_radius_all(16)
		draw_style_box(style, Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0))
		_draw_player_tag(player)

	func _draw_player_tag(player: int) -> void:
		var tag_size := Vector2(62.0, 38.0)
		var tag_position := Vector2(-14.0, -20.0)
		if player == 1:
			tag_position = Vector2(size.x - tag_size.x + 14.0, -20.0)
		var style := StyleBoxFlat.new()
		style.bg_color = PLAYER_COLORS[player]
		style.set_corner_radius_all(10)
		draw_style_box(style, Rect2(tag_position, tag_size))
		draw_string(FONT, tag_position + Vector2(0.0, 29.0), "P%d" % (player + 1), HORIZONTAL_ALIGNMENT_CENTER, tag_size.x, 28, Color.WHITE)

	func _draw_lock_badge() -> void:
		if locked_by < 0:
			return
		var text := "P%d READY" % (locked_by + 1)
		var baseline := Vector2(0.0, ICON_RECT.end.y - 70.0)
		draw_string_outline(FONT, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, 12, INK)
		draw_string(FONT, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, PLAYER_COLORS[locked_by].lightened(0.35))


## A player's side panel: their hovered character in 3D, its name and whether they're ready.
class PlayerPanel:
	extends PanelContainer

	const IDLE_ANIMATION := &"Player/Idle_A"
	const CHEER_ANIMATION := &"Player/Jump_Full_Short"
	const TAKEN_ANIMATION := &"Player/Hit_A"

	var _player := 0
	var _viewport: SubViewport
	var _pivot: Node3D
	var _model: PlayerCharacter
	var _name_label: Label
	var _status_label: Label
	var _pop := MenuSpring.new(1.0, 260.0, 0.35)
	var _time := 0.0

	func _init(player: int) -> void:
		_player = player
		size = PANEL_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.07, 0.03, 0.82)
		style.border_color = PLAYER_COLORS[player]
		style.set_border_width_all(6)
		style.set_corner_radius_all(18)
		style.set_content_margin_all(18.0)
		add_theme_stylebox_override("panel", style)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		add_child(column)
		column.add_child(_make_label("PLAYER %d" % (player + 1), 46, PLAYER_COLORS[player].lightened(0.2)))
		column.add_child(_build_stage())
		_name_label = _make_label("", 52, Color(0.98, 0.95, 0.86))
		column.add_child(_name_label)
		_status_label = _make_label("", 30, Color(0.98, 0.95, 0.86))
		column.add_child(_status_label)

	func _process(delta: float) -> void:
		var step_delta := minf(delta, 1.0 / 30.0)
		_time += step_delta
		_pop.step(step_delta)
		_pivot.scale = Vector3.ONE * _pop.value
		_pivot.rotation.y = PI + sin(_time * 0.9) * 0.45

	func show_character(index: int) -> void:
		var character: Dictionary = CharacterRoster.CHARACTERS[index]
		_name_label.text = character["name"]
		if _model != null:
			_model.queue_free()
		_model = (character["scene"] as PackedScene).instantiate()
		_pivot.add_child(_model)
		_model.animation_tree.active = false
		_model.animation_player.animation_finished.connect(_on_animation_finished)
		_play(IDLE_ANIMATION)
		_pop.value = 0.7
		_pop.velocity = 3.0

	func set_status(text: String, is_ready: bool) -> void:
		_status_label.text = text
		_status_label.modulate = PLAYER_COLORS[_player].lightened(0.35) if is_ready else Color(0.85, 0.82, 0.75)

	func cheer() -> void:
		_play(CHEER_ANIMATION)
		_pop.velocity += 2.5

	func flinch() -> void:
		_play(TAKEN_ANIMATION)

	func _play(animation: StringName) -> void:
		if not _model.animation_player.has_animation(animation):
			return
		_model.animation_player.play(animation, 0.15)

	func _on_animation_finished(_animation: StringName) -> void:
		_play(IDLE_ANIMATION)

	func _build_stage() -> SubViewportContainer:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.custom_minimum_size = Vector2(0.0, 440.0)
		_viewport = SubViewport.new()
		_viewport.own_world_3d = true
		_viewport.transparent_bg = true
		_viewport.msaa_3d = Viewport.MSAA_4X
		container.add_child(_viewport)
		_pivot = Node3D.new()
		_viewport.add_child(_pivot)
		var camera := Camera3D.new()
		camera.fov = 30.0
		camera.position = Vector3(0.0, 1.15, 5.4)
		camera.rotation_degrees.x = -5.0
		_viewport.add_child(camera)
		_add_lighting()
		return container

	func _add_lighting() -> void:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-30.0, 25.0, 0.0)
		sun.light_energy = 1.3
		_viewport.add_child(sun)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_CLEAR_COLOR
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 0.75
		var world_environment := WorldEnvironment.new()
		world_environment.environment = environment
		_viewport.add_child(world_environment)

	func _make_label(text: String, font_size: int, color: Color) -> Label:
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
		label.add_theme_constant_override("outline_size", 12)
		return label


var _cards: Array[Card] = []
var _panels: Array[PlayerPanel] = []
var _cursors: Array[int] = [0, 1]
var _locked: Array[bool] = [false, false]
var _pad_buttons_down := {}
var _input_enabled := false
var _input_unlock_time := 0.0

var _dim: ColorRect
var _title: Label

@onready var _backdrop: MenuBackdropJuice = $"../MenuBackdropJuice"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_dim()
	_build_title()
	_build_cards()
	_build_panels()
	_build_hint()
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)


func _process(_delta: float) -> void:
	if not _can_read_input():
		return
	if _is_new_press("escape", Input.is_key_pressed(KEY_ESCAPE)):
		_go_back()
		return
	for player in CharacterRoster.PLAYER_COUNT:
		_poll_player(player)


## Shows the roster with each player's cursor on their last pick.
func open() -> void:
	_locked = [false, false]
	_cursors = [CharacterRoster.remembered_pick(0), CharacterRoster.remembered_pick(1)]
	_prime_held_buttons()
	_input_enabled = true
	_input_unlock_time = _now() + INPUT_LOCK_SECONDS
	_backdrop.tuck_logo(true)
	_layout()
	for player in CharacterRoster.PLAYER_COUNT:
		_panels[player].show_character(_cursors[player])
	_refresh()
	set_process(true)


## Buttons still held from the previous screen must be released before they count.
func _prime_held_buttons() -> void:
	_pad_buttons_down.clear()
	_pad_buttons_down["escape"] = Input.is_key_pressed(KEY_ESCAPE)
	for player in CharacterRoster.PLAYER_COUNT:
		_pad_buttons_down["p%d_a" % player] = Input.is_joy_button_pressed(player, JOY_BUTTON_A)
		_pad_buttons_down["p%d_b" % player] = Input.is_joy_button_pressed(player, JOY_BUTTON_B)


func _build_dim() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.03, 0.02, 0.45)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)


func _build_title() -> void:
	_title = _make_outlined_label("CHOOSE YOUR CARRIERS", 78)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.offset_top = 70.0
	add_child(_title)


func _build_cards() -> void:
	for character in CharacterRoster.CHARACTERS:
		var card := Card.new()
		card.icon = character["icon"]
		card.display_name = character["name"]
		card.size = CARD_SIZE
		card.pivot_offset = CARD_SIZE * 0.5
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card)
		_cards.append(card)


func _build_panels() -> void:
	for player in CharacterRoster.PLAYER_COUNT:
		var panel := PlayerPanel.new(player)
		add_child(panel)
		_panels.append(panel)


func _build_hint() -> void:
	var hint := _make_outlined_label(HINT_TEXT, 30)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -44.0
	add_child(hint)


func _make_outlined_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.98, 0.95, 0.86))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.16, 0.26))
	label.add_theme_constant_override("outline_size", 16)
	return label


func _layout() -> void:
	var rows := ceili(float(_cards.size()) / GRID_COLUMNS)
	var grid_size := Vector2(GRID_COLUMNS * CARD_SIZE.x + (GRID_COLUMNS - 1) * CARD_GAP, rows * CARD_SIZE.y + (rows - 1) * CARD_GAP)
	var grid_origin := Vector2((size.x - grid_size.x) * 0.5, GRID_TOP)
	for index in _cards.size():
		var cell := Vector2(index % GRID_COLUMNS, index / GRID_COLUMNS)
		_cards[index].rest_position = grid_origin + cell * (CARD_SIZE + Vector2.ONE * CARD_GAP)
	_panels[0].position = Vector2(PANEL_MARGIN, PANEL_TOP)
	_panels[1].position = Vector2(size.x - PANEL_MARGIN - PANEL_SIZE.x, PANEL_TOP)


func _poll_player(player: int) -> void:
	if _pressed_cancel(player):
		_cancel(player)
		return
	if _pressed_confirm(player):
		_lock_in(player)
		return
	if _locked[player]:
		return
	for direction in MOVE_ACTIONS:
		_try_move(player, direction)


func _try_move(player: int, direction: StringName) -> void:
	if not Input.is_action_just_pressed("p%d_%s" % [player, direction]):
		return
	_move_cursor(player, MOVE_ACTIONS[direction])


func _pressed_confirm(player: int) -> bool:
	if _is_new_press("p%d_a" % player, Input.is_joy_button_pressed(player, JOY_BUTTON_A)):
		return true
	for suffix in CONFIRM_SUFFIXES:
		if Input.is_action_just_pressed("p%d%s" % [player, suffix]):
			return true
	return false


func _pressed_cancel(player: int) -> bool:
	return _is_new_press("p%d_b" % player, Input.is_joy_button_pressed(player, JOY_BUTTON_B))


## Edge detection for inputs read straight from the device, which have no "just pressed".
func _is_new_press(key: String, down: bool) -> bool:
	var was_down: bool = _pad_buttons_down.get(key, false)
	_pad_buttons_down[key] = down
	return down and not was_down


## Wraps around the grid in both directions.
func _move_cursor(player: int, step: Vector2i) -> void:
	var rows := ceili(float(_cards.size()) / GRID_COLUMNS)
	var column := posmod(_cursors[player] % GRID_COLUMNS + step.x, GRID_COLUMNS)
	var row := posmod(_cursors[player] / GRID_COLUMNS + step.y, rows)
	var index := mini(row * GRID_COLUMNS + column, _cards.size() - 1)
	if index == _cursors[player]:
		return
	_cursors[player] = index
	_cards[index].bump()
	_panels[player].show_character(index)
	_play_tick(1.3 + player * 0.15)
	_refresh()


func _lock_in(player: int) -> void:
	if _locked[player]:
		return
	var index := _cursors[player]
	if _is_taken_by_other(player, index):
		_refuse(player, index)
		return
	_locked[player] = true
	_cards[index].bump()
	_panels[player].cheer()
	_backdrop.thump()
	_backdrop.play_sfx(MenuBackdropJuice.SOUND_PLAYERS_LAND, -8.0, randf_range(0.95, 1.08))
	_refresh()
	_finish_if_all_ready()


func _is_taken_by_other(player: int, index: int) -> bool:
	var other := 1 - player
	return _locked[other] and _cursors[other] == index


func _refuse(player: int, index: int) -> void:
	_cards[index].refuse()
	_panels[player].flinch()
	_play_tick(0.6)


func _cancel(player: int) -> void:
	if not _locked[player]:
		_go_back()
		return
	_locked[player] = false
	_play_tick(0.8)
	_refresh()


func _finish_if_all_ready() -> void:
	if _locked.has(false):
		return
	_input_enabled = false
	CharacterRoster.set_picks(_cursors[0], _cursors[1])
	_title.text = "LET'S GO!"
	await get_tree().create_timer(ALL_READY_SECONDS).timeout
	if not visible:
		return
	SessionFlow.finish_character_select()


func _go_back() -> void:
	if not _input_enabled:
		return
	_input_enabled = false
	_play_tick(0.8)
	SessionFlow.transition_to("homemenu")


func _refresh() -> void:
	for index in _cards.size():
		_refresh_card(_cards[index], index)
	for player in CharacterRoster.PLAYER_COUNT:
		_refresh_panel_status(player)


func _refresh_card(card: Card, index: int) -> void:
	card.locked_by = -1
	for player in CharacterRoster.PLAYER_COUNT:
		card.hovered_by[player] = _cursors[player] == index
		_mark_card_locked(card, index, player)


func _mark_card_locked(card: Card, index: int, player: int) -> void:
	if not _locked[player] or _cursors[player] != index:
		return
	card.locked_by = player


func _refresh_panel_status(player: int) -> void:
	var panel := _panels[player]
	if _locked[player]:
		panel.set_status("READY!  (B to change)", true)
		return
	if _is_taken_by_other(player, _cursors[player]):
		panel.set_status("Taken by Player %d" % (2 - player), false)
		return
	panel.set_status("Press A to lock in", false)


func _can_read_input() -> bool:
	if not _input_enabled:
		return false
	return _now() >= _input_unlock_time


func _play_tick(pitch: float) -> void:
	_backdrop.play_sfx(SOUND_TICKS.pick_random(), -14.0, pitch * randf_range(0.95, 1.05))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_visibility_changed() -> void:
	if visible:
		return
	_input_enabled = false
	_title.text = "CHOOSE YOUR CARRIERS"
	_backdrop.tuck_logo(false)
	set_process(false)
