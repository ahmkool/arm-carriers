class_name LevelTargetSelect
extends Control
## Level select: wanted posters hang in the menu's sky and the players shoot the one they want.
## Left/right aims between posters, up/down switches tab, accept picks a poster. A level that can
## be played with several weapons then asks for one: left/right picks it, accept fires, cancel backs out.
## Locked levels hang chained shut and rattle when picked; see LevelSelectCatalog for what opens them.

const LEFT_ACTIONS: Array[StringName] = [&"ui_left", &"p0_left", &"p1_left"]
const RIGHT_ACTIONS: Array[StringName] = [&"ui_right", &"p0_right", &"p1_right"]
const UP_ACTIONS: Array[StringName] = [&"ui_up", &"p0_up", &"p1_up"]
const DOWN_ACTIONS: Array[StringName] = [&"ui_down", &"p0_down", &"p1_down"]
const ACCEPT_ACTIONS: Array[StringName] = [&"ui_accept", &"p0_accept", &"p1_accept"]
const CANCEL_ACTIONS: Array[StringName] = [&"ui_cancel"]

const FONT := preload("res://assets/fonts/Lilita_One/LilitaOne-Regular.ttf")
const SMOKE_TEXTURE := preload("res://assets/sprites/particles/smoke_05_a.png")
const SOUND_TICKS: Array[AudioStream] = [
	preload("res://assets/sounds/wood/WoodStep01.wav"),
	preload("res://assets/sounds/wood/WoodStep05.wav"),
	preload("res://assets/sounds/wood/WoodStep09.wav"),
]

const RAIL_WIDTH := 280.0
const RAIL_MARGIN := Vector2(36.0, 44.0)
const POSTER_ROW_LEFT := 340.0
const POSTER_ROW_RIGHT_MARGIN := 30.0
const ROPE_EDGE_Y := 44.0
const ROPE_SAG := 46.0
const ROPE_STEPS := 40
const ROPE_COLOR := Color(0.34, 0.2, 0.1)
const ARC_COLOR := Color(1.0, 0.86, 0.45, 0.95)
const ARC_DOTS := 26
const ARC_SPEED := 0.5
const SWOOP_DISTANCE := 430.0
const SWOOP_LIFT := 240.0
const ROCKET_FLIGHT_SECONDS := 0.62
const AFTER_BLAST_SECONDS := 0.32
const INPUT_LOCK_SECONDS := 0.18
const ENTER_STAGGER_SECONDS := 0.07
const HINT_TEXT := "Left / Right: aim\nUp / Down: tab\nEnter / A: pick"
const WEAPON_HINT_TEXT := "Arrows: weapon\nEnter / A: FIRE!\nEsc / B: back"
const DIMMED_POSTER_ALPHA := 0.4
const LOCKED_TAB_ALPHA := 0.55
## Room left between neighbouring posters before they shrink to fit the rope.
const POSTER_GAP := 24.0

## Survive the menu scene reloading after a level, so players return where they left off.
static var _remembered_group := 0
static var _remembered_poster := 0
static var _seen_completed: Dictionary = {}
static var _seen_baseline_taken := false
## Last weapon fired per level scene, picked first next time.
static var _remembered_weapons: Dictionary = {}


class Crosshair:
	extends Control

	var _spin := 0.0

	func _process(delta: float) -> void:
		_spin += delta * 1.1
		queue_redraw()

	func _draw() -> void:
		var pulse := 86.0 + sin(_spin * 4.0) * 5.0
		draw_arc(Vector2.ZERO, pulse + 3.0, 0.0, TAU, 48, Color(0.2, 0.05, 0.02, 0.55), 11.0, true)
		draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 48, Color(0.98, 0.3, 0.1), 6.0, true)
		for index in 4:
			var direction := Vector2.from_angle(_spin + index * TAU / 4.0)
			draw_line(direction * (pulse - 22.0), direction * (pulse + 22.0), Color(0.98, 0.3, 0.1), 7.0, true)


## Painted in the bazooka's brass colours. Points along +X.
class Rocket:
	extends Node2D

	func _draw() -> void:
		var brass := Color(0.72, 0.5, 0.2)
		var dark := Color(0.32, 0.2, 0.1)
		var flame := Color(1.0, 0.55, 0.12)
		draw_colored_polygon(PackedVector2Array([Vector2(-58.0, -9.0), Vector2(-112.0, 0.0), Vector2(-58.0, 9.0)]), flame)
		draw_colored_polygon(PackedVector2Array([Vector2(-34.0, -14.0), Vector2(-66.0, -40.0), Vector2(-66.0, 40.0), Vector2(-34.0, 14.0)]), dark)
		draw_rect(Rect2(-62.0, -17.0, 72.0, 34.0), brass)
		draw_rect(Rect2(-62.0, -17.0, 72.0, 10.0), Color(0.9, 0.7, 0.34))
		draw_colored_polygon(PackedVector2Array([Vector2(10.0, -21.0), Vector2(36.0, -17.0), Vector2(70.0, 0.0), Vector2(36.0, 17.0), Vector2(10.0, 21.0)]), dark)
		draw_rect(Rect2(2.0, -23.0, 12.0, 46.0), Color(0.9, 0.7, 0.34))


var _posters: Array[LevelPoster] = []
var _tabs: Array[Button] = []
var _group_index := 0
var _poster_index := 0
var _input_enabled := false
var _choosing_weapon := false
var _weapon_index := 0
var _hint: Label
var _launching := false
var _input_unlock_time := 0.0
var _time := 0.0
var _crosshair_x := MenuSpring.new(0.0, 220.0, 0.62)
var _crosshair_y := MenuSpring.new(0.0, 220.0, 0.62)

var _rail: VBoxContainer
var _crosshair: Crosshair
var _rocket: Rocket
var _trail: CPUParticles2D

@onready var _backdrop: MenuBackdropJuice = $"../MenuBackdropJuice"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_rail()
	_build_crosshair()
	_build_rocket()
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	_update_crosshair(minf(delta, 1.0 / 30.0))
	queue_redraw()
	_poll_input()


func _draw() -> void:
	_draw_rope()
	_draw_aim_arc()


## Shows the posters and hands control to the players.
func open() -> void:
	_take_completion_baseline()
	_launching = false
	_choosing_weapon = false
	_hint.text = HINT_TEXT
	_input_enabled = true
	_input_unlock_time = _now() + INPUT_LOCK_SECONDS
	_rocket.visible = false
	_trail.emitting = false
	_rail.modulate.a = 1.0
	_crosshair.visible = true
	set_process(true)
	_backdrop.tuck_logo(true)
	_show_group(clampi(_remembered_group, 0, LevelSelectCatalog.groups().size() - 1), _remembered_poster)


## Fires the rocket at the chosen poster. Returns once the blast has played.
func play_launch() -> void:
	_launching = true
	_input_enabled = false
	_crosshair.visible = false
	var target := _posters[_poster_index]
	var start := _backdrop.muzzle_position()
	var end := target.center_point()
	_backdrop.fire_bazooka()
	_rocket.visible = true
	_trail.emitting = true
	var flight := create_tween()
	flight.tween_method(_place_rocket.bind(start, end), 0.0, 1.0, ROCKET_FLIGHT_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await flight.finished
	_detonate(target, end)
	await get_tree().create_timer(AFTER_BLAST_SECONDS).timeout


func _build_rail() -> void:
	_rail = VBoxContainer.new()
	_rail.position = RAIL_MARGIN
	_rail.custom_minimum_size.x = RAIL_WIDTH
	_rail.add_theme_constant_override("separation", 12)
	add_child(_rail)
	for index in LevelSelectCatalog.groups().size():
		var tab := _make_rail_button(LevelSelectCatalog.groups()[index]["name"], 32)
		tab.pressed.connect(_on_tab_pressed.bind(index))
		_tabs.append(tab)
	var back := _make_rail_button("Back", 28)
	back.pressed.connect(_go_back)
	_style_tab(back, false)
	_hint = Label.new()
	_hint.text = HINT_TEXT
	_hint.add_theme_font_override("font", FONT)
	_hint.add_theme_font_size_override("font_size", 28)
	_hint.add_theme_color_override("font_color", Color(0.98, 0.95, 0.86))
	_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.16, 0.26))
	_hint.add_theme_constant_override("outline_size", 12)
	_rail.add_child(_hint)


func _make_rail_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	_rail.add_child(button)
	return button


func _build_crosshair() -> void:
	_crosshair = Crosshair.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)


func _build_rocket() -> void:
	_trail = CPUParticles2D.new()
	_trail.emitting = false
	_trail.amount = 60
	_trail.lifetime = 0.55
	_trail.texture = SMOKE_TEXTURE
	_trail.scale_amount_min = 0.12
	_trail.scale_amount_max = 0.24
	_trail.gravity = Vector2(0.0, -40.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.72, 0.36, 0.9))
	ramp.set_color(1, Color(0.8, 0.76, 0.72, 0.0))
	_trail.color_ramp = ramp
	add_child(_trail)
	_rocket = Rocket.new()
	_rocket.visible = false
	add_child(_rocket)


func _show_group(group_index: int, poster_index: int) -> void:
	_group_index = group_index
	_remembered_group = group_index
	_clear_posters()
	var levels: Array = LevelSelectCatalog.groups()[group_index]["levels"]
	for index in levels.size():
		_add_poster(group_index, index, levels.size())
	_refresh_tabs()
	_select_poster(clampi(poster_index, 0, levels.size() - 1))
	_snap_crosshair()


func _clear_posters() -> void:
	for poster in _posters:
		poster.play_leave()
	_posters.clear()


func _add_poster(group_index: int, index: int, count: int) -> void:
	var level: Dictionary = LevelSelectCatalog.groups()[group_index]["levels"][index]
	var poster := LevelPoster.new()
	var completed_weapons := _completed_weapons(level)
	var new_wins := _unseen_wins(level, completed_weapons)
	var is_new_win := not new_wins.is_empty()
	var stamped := not completed_weapons.is_empty() and not is_new_win
	var lock_reason := LevelSelectCatalog.lock_reason(group_index, index)
	poster.setup(level, stamped, completed_weapons, LevelSelectCatalog.offered_weapons(level), lock_reason, _poster_fit_scale(count))
	var center_x := _poster_center_x(index, count)
	poster.rest_position = Vector2(center_x - LevelPoster.POSTER_SIZE.x * 0.5, _rope_y(center_x) + 4.0)
	poster.mouse_entered.connect(_on_poster_hovered.bind(poster))
	poster.gui_input.connect(_on_poster_gui_input.bind(poster))
	add_child(poster)
	move_child(poster, _rail.get_index())
	_posters.append(poster)
	poster.play_enter(ENTER_STAGGER_SECONDS * index)
	if not is_new_win:
		return
	for save_id in new_wins:
		_seen_completed[save_id] = true
	poster.stamp_landed.connect(_backdrop.thump)
	poster.play_stamp_slam()


func _completed_weapons(level: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for weapon_id in LevelSelectCatalog.weapons_for(level):
		if GameSave.is_level_completed(LevelSelectCatalog.save_id(level, weapon_id)):
			result.append(weapon_id)
	return result


## Save keys of wins earned since the level select last showed them, so their stamp slams in.
func _unseen_wins(level: Dictionary, completed_weapons: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for weapon_id in completed_weapons:
		var save_id := LevelSelectCatalog.save_id(level, weapon_id)
		if _seen_completed.has(save_id):
			continue
		result.append(save_id)
	return result


func _poster_center_x(index: int, count: int) -> float:
	return POSTER_ROW_LEFT + _poster_row_width() * (index + 0.5) / count


func _poster_row_width() -> float:
	return size.x - POSTER_ROW_LEFT - POSTER_ROW_RIGHT_MARGIN


## Selected posters grow, so leave room for that too.
func _poster_fit_scale(count: int) -> float:
	var room := _poster_row_width() / count - POSTER_GAP
	return minf(1.0, room / (LevelPoster.POSTER_SIZE.x * LevelPoster.SELECTED_SCALE))


func _rope_y(x: float) -> float:
	var from_center := x / size.x * 2.0 - 1.0
	return ROPE_EDGE_Y + ROPE_SAG * (1.0 - from_center * from_center)


func _select_poster(index: int) -> void:
	_poster_index = index
	_remembered_poster = index
	for poster_index in _posters.size():
		_posters[poster_index].set_selected(poster_index == index)
	var target := _posters[index].center_point()
	_crosshair_x.target = target.x
	_crosshair_y.target = target.y
	_backdrop.aim_players(target.x / size.x)


func _snap_crosshair() -> void:
	_crosshair_x.value = _crosshair_x.target
	_crosshair_y.value = _crosshair_y.target


func _refresh_tabs() -> void:
	for index in _tabs.size():
		_style_tab(_tabs[index], index == _group_index)
		_tabs[index].text = _tab_text(index)
		_tabs[index].modulate.a = 1.0 if LevelSelectCatalog.is_group_open(index) else LOCKED_TAB_ALPHA


## The world's name and how many of its posters are stamped. A closed world shows its name only,
## dimmed, and its posters say what opens it.
func _tab_text(group_index: int) -> String:
	var group: Dictionary = LevelSelectCatalog.groups()[group_index]
	var group_name: String = group["name"]
	if not LevelSelectCatalog.is_group_open(group_index):
		return group_name
	if group.get("dev", false):
		return group_name  # dev sandboxes never save, so a count would stay at 0
	return "%s %d/%d" % [group_name, LevelSelectCatalog.cleared_count(group_index), group["levels"].size()]


func _style_tab(button: Button, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.52, 0.24, 0.04) if selected else Color(0.34, 0.15, 0.03, 0.92)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6.0)
	style.border_color = Color(1.0, 0.86, 0.45)
	style.set_border_width_all(4 if selected else 0)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)


func _poll_input() -> void:
	if not _can_read_input():
		return
	if _choosing_weapon:
		_poll_weapon_input()
		return
	if _any_just_pressed(CANCEL_ACTIONS):
		_go_back()
		return
	if _any_just_pressed(ACCEPT_ACTIONS):
		_pick_poster()
		return
	if _any_just_pressed(LEFT_ACTIONS):
		_move_poster(-1)
		return
	if _any_just_pressed(RIGHT_ACTIONS):
		_move_poster(1)
		return
	if _any_just_pressed(UP_ACTIONS):
		_move_group(-1)
		return
	if _any_just_pressed(DOWN_ACTIONS):
		_move_group(1)


func _poll_weapon_input() -> void:
	if _any_just_pressed(CANCEL_ACTIONS):
		_leave_weapon_choice()
		return
	if _any_just_pressed(ACCEPT_ACTIONS):
		_fire_chosen_weapon()
		return
	if _any_just_pressed(LEFT_ACTIONS):
		_move_weapon(-1)
		return
	if _any_just_pressed(RIGHT_ACTIONS):
		_move_weapon(1)
		return
	if _any_just_pressed(UP_ACTIONS):
		_move_weapon_row(-1)
		return
	if _any_just_pressed(DOWN_ACTIONS):
		_move_weapon_row(1)


func _can_read_input() -> bool:
	if not _input_enabled:
		return false
	return _now() >= _input_unlock_time


func _any_just_pressed(actions: Array[StringName]) -> bool:
	for action in actions:
		if Input.is_action_just_pressed(action):
			return true
	return false


func _move_poster(direction: int) -> void:
	_select_poster(posmod(_poster_index + direction, _posters.size()))
	_play_tick(1.4)


func _move_group(direction: int) -> void:
	_show_group(posmod(_group_index + direction, LevelSelectCatalog.groups().size()), 0)
	_play_tick(1.0)


func _go_back() -> void:
	if not _input_enabled:
		return
	_input_enabled = false
	_play_tick(0.8)
	SessionFlow.transition_to("homemenu")


## A level with one weapon fires straight away; otherwise the players pick the weapon first.
func _pick_poster() -> void:
	if _posters[_poster_index].is_locked():
		_deny_poster()
		return
	var level := _posters[_poster_index].level
	var weapons := LevelSelectCatalog.offered_weapons(level)
	if weapons.size() == 1:
		_fire(weapons[0])
		return
	_enter_weapon_choice(level)


func _deny_poster() -> void:
	_posters[_poster_index].play_denied()
	_backdrop.thump()
	_play_tick(0.55)


func _enter_weapon_choice(level: Dictionary) -> void:
	_choosing_weapon = true
	_input_unlock_time = _now() + INPUT_LOCK_SECONDS
	_hint.text = WEAPON_HINT_TEXT
	_set_other_posters_dimmed(true)
	_focus_weapon(_remembered_weapon_index(level))
	_play_tick(1.2)


func _leave_weapon_choice() -> void:
	_choosing_weapon = false
	_hint.text = HINT_TEXT
	_posters[_poster_index].set_weapon_focus(-1)
	_set_other_posters_dimmed(false)
	_select_poster(_poster_index)
	_play_tick(0.8)


func _move_weapon(direction: int) -> void:
	var count := LevelSelectCatalog.offered_weapons(_posters[_poster_index].level).size()
	_focus_weapon(posmod(_weapon_index + direction, count))
	_play_tick(1.6)


## Jumps between the rows of weapon tags; the short second row catches the last tag.
func _move_weapon_row(direction: int) -> void:
	var count := LevelSelectCatalog.offered_weapons(_posters[_poster_index].level).size()
	var target_row := _weapon_index / LevelPoster.TAGS_PER_ROW + direction
	var last_row := (count - 1) / LevelPoster.TAGS_PER_ROW
	if target_row < 0 or target_row > last_row:
		return
	var target := _weapon_index + direction * LevelPoster.TAGS_PER_ROW
	_focus_weapon(mini(target, count - 1))
	_play_tick(1.6)


## Puts the highlight and the crosshair on one weapon tag of the chosen poster.
func _focus_weapon(index: int) -> void:
	_weapon_index = index
	var poster := _posters[_poster_index]
	poster.set_weapon_focus(index)
	var target := poster.weapon_tag_point(index)
	_crosshair_x.target = target.x
	_crosshair_y.target = target.y


func _remembered_weapon_index(level: Dictionary) -> int:
	var weapons := LevelSelectCatalog.offered_weapons(level)
	var remembered: String = _remembered_weapons.get(level["scene"], "")
	return maxi(weapons.find(remembered), 0)


func _set_other_posters_dimmed(dimmed: bool) -> void:
	for index in _posters.size():
		if index == _poster_index:
			continue
		_posters[index].modulate.a = DIMMED_POSTER_ALPHA if dimmed else 1.0


func _fire_chosen_weapon() -> void:
	var level := _posters[_poster_index].level
	_fire(LevelSelectCatalog.offered_weapons(level)[_weapon_index])


## Asks about saved progress before the shot, so the rocket is always the last thing that happens.
func _fire(weapon_id: String) -> void:
	_input_enabled = false
	_choosing_weapon = false
	_crosshair.visible = false
	var level := _posters[_poster_index].level
	_remembered_weapons[level["scene"]] = weapon_id
	_send_away_all_but_target()
	if not GameSave.get_saved_checkpoint(LevelSelectCatalog.save_id(level, weapon_id)).is_empty():
		_request_level(level, weapon_id)
		return
	await play_launch()
	_request_level(level, weapon_id)


func _request_level(level: Dictionary, weapon_id: String) -> void:
	SessionFlow.request_level(level["scene"], level["scene"], weapon_id)


func _send_away_all_but_target() -> void:
	var target := _posters[_poster_index]
	var remaining: Array[LevelPoster] = [target]
	for poster in _posters:
		_send_away_unless_target(poster, target)
	_posters = remaining
	_poster_index = 0
	var fade := create_tween()
	fade.tween_property(_rail, "modulate:a", 0.0, 0.15)


func _send_away_unless_target(poster: LevelPoster, target: LevelPoster) -> void:
	if poster == target:
		return
	poster.play_leave()


func _place_rocket(progress: float, start: Vector2, end: Vector2) -> void:
	var point := _arc_point(start, end, progress)
	var ahead := _arc_point(start, end, minf(progress + 0.02, 1.0))
	_rocket.position = point
	_trail.position = point
	if ahead.is_equal_approx(point):
		return
	_rocket.rotation = (ahead - point).angle()


## Leaves along the barrel, then swoops round to the target wherever it hangs.
func _arc_point(start: Vector2, end: Vector2, progress: float) -> Vector2:
	var control := start + MenuBackdropJuice.FIRE_DIRECTION * SWOOP_DISTANCE + Vector2(0.0, -SWOOP_LIFT)
	return start.bezier_interpolate(control, control, end, progress)


func _detonate(target: LevelPoster, at: Vector2) -> void:
	_rocket.visible = false
	_trail.emitting = false
	target.visible = false
	_backdrop.blast_at(at)
	_burst_paper(at)


func _burst_paper(at: Vector2) -> void:
	var paper := CPUParticles2D.new()
	paper.amount = 34
	paper.lifetime = 1.1
	paper.one_shot = true
	paper.explosiveness = 1.0
	paper.spread = 180.0
	paper.initial_velocity_min = 240.0
	paper.initial_velocity_max = 760.0
	paper.damping_min = 280.0
	paper.damping_max = 420.0
	paper.gravity = Vector2(0.0, 520.0)
	paper.angular_velocity_min = -420.0
	paper.angular_velocity_max = 420.0
	paper.scale_amount_min = 7.0
	paper.scale_amount_max = 17.0
	paper.color = LevelPoster.PAPER
	paper.position = at
	paper.finished.connect(paper.queue_free)
	add_child(paper)
	paper.emitting = true


func _update_crosshair(delta: float) -> void:
	_crosshair_x.step(delta)
	_crosshair_y.step(delta)
	_crosshair.position = Vector2(_crosshair_x.value, _crosshair_y.value)


func _draw_rope() -> void:
	var points := PackedVector2Array()
	for step in ROPE_STEPS + 1:
		var x := size.x * step / ROPE_STEPS
		points.append(Vector2(x, _rope_y(x)))
	draw_polyline(points, ROPE_COLOR, 6.0, true)


## Dots travel along the path the rocket will take.
func _draw_aim_arc() -> void:
	if not _input_enabled or _posters.is_empty():
		return
	var start := _backdrop.muzzle_position()
	var end := Vector2(_crosshair_x.value, _crosshair_y.value)
	for dot in ARC_DOTS:
		var progress := fposmod(float(dot) / ARC_DOTS + _time * ARC_SPEED, 1.0)
		draw_circle(_arc_point(start, end, progress), 4.0 + 3.0 * (1.0 - progress), ARC_COLOR)


func _take_completion_baseline() -> void:
	if _seen_baseline_taken:
		return
	_seen_baseline_taken = true
	for group in LevelSelectCatalog.groups():
		_add_completed_to_seen(group["levels"])


func _add_completed_to_seen(levels: Array) -> void:
	for level in levels:
		for weapon_id in _completed_weapons(level):
			_seen_completed[LevelSelectCatalog.save_id(level, weapon_id)] = true


func _play_tick(pitch: float) -> void:
	_backdrop.play_sfx(SOUND_TICKS.pick_random(), -14.0, pitch * randf_range(0.95, 1.05))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_tab_pressed(index: int) -> void:
	if not _input_enabled or _choosing_weapon or index == _group_index:
		return
	_show_group(index, 0)
	_play_tick(1.0)


func _on_poster_hovered(poster: LevelPoster) -> void:
	if not _input_enabled or _choosing_weapon:
		return
	var index := _posters.find(poster)
	if index == _poster_index:
		return
	_select_poster(index)
	_play_tick(1.4)


func _on_poster_gui_input(event: InputEvent, poster: LevelPoster) -> void:
	if not _can_read_input():
		return
	if not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	_click_poster(_posters.find(poster))


## Clicking the poster being armed fires its chosen weapon; clicking another one backs out first.
func _click_poster(index: int) -> void:
	if not _choosing_weapon:
		_poster_index = index
		_pick_poster()
		return
	if index == _poster_index:
		_fire_chosen_weapon()
		return
	_leave_weapon_choice()


func _on_visibility_changed() -> void:
	if visible or _launching:
		return
	_input_enabled = false
	set_process(false)
	_clear_posters()
	_backdrop.tuck_logo(false)
	_backdrop.aim_players(-1.0)
