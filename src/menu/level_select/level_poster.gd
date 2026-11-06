class_name LevelPoster
extends Control
## A wanted poster hanging from the rope. Draws itself and swings from its peg.

signal stamp_landed

const POSTER_SIZE := Vector2(300.0, 420.0)
const SELECTED_SCALE := 1.12
const FONT := preload("res://assets/fonts/Lilita_One/LilitaOne-Regular.ttf")
const SKELETONS := preload("res://assets/sprites/menu/skeletons.png")
const BOSS := preload("res://assets/sprites/menu/enemy_boss.png")
const PORTRAIT_RECT := Rect2(28.0, 78.0, 244.0, 206.0)
const INK := Color(0.27, 0.14, 0.06)
const PAPER := Color(0.93, 0.82, 0.6)
const PAPER_SHADOW := Color(0.1, 0.05, 0.02, 0.35)
const STAMP_RED := Color(0.72, 0.09, 0.05, 0.88)
const SKULL_SPACING := 44.0
## The boss art is hazed for depth; warm it back up so it reads on paper.
const BOSS_TINT := Color(1.3, 1.08, 0.86)
const MAX_DIFFICULTY := 4
const JAGGED_PIXELS := 5.0
const EDGE_STEPS := 8
const STAMP_DELAY_SECONDS := 0.55
## Weapon tags hang on cords below the poster, one per weapon the level can be played with,
## in rows of up to TAGS_PER_ROW. The second row sits between the first row's tags.
const TAGS_PER_ROW := 4
const TAG_RADIUS := 31.0
const TAG_GAP := 12.0
const TAG_DROP := 26.0
const TAG_ROW_STEP := 74.0
const TAG_FOCUS_SCALE := 1.18
const TAG_FOCUS_RING := Color(1.0, 0.86, 0.45)
const CHECK_RADIUS := 12.0

var level: Dictionary
var rest_position := Vector2.ZERO

var _size_spring := MenuSpring.new(1.0, 320.0, 0.42)
var _swing_spring := MenuSpring.new(0.0, 80.0, 0.14)
var _selected := false
var _time := 0.0
var _outline: PackedVector2Array
var _stamped := false
var _stamp_scale := 1.0
var _weapon_ids: Array = []
var _weapon_icons: Array[Texture2D] = []
var _completed_weapons: Dictionary = {}
var _focused_weapon := -1
var _focus_pulse := 0.0


## `completed_weapons` holds the ids of the weapons that have beaten this level.
func setup(p_level: Dictionary, stamped: bool, completed_weapons: Array[String]) -> void:
	level = p_level
	_stamped = stamped
	_weapon_ids = LevelSelectCatalog.weapons_for(level)
	for weapon_id in _weapon_ids:
		_weapon_icons.append(WeaponCatalog.icon(weapon_id))
	for weapon_id in completed_weapons:
		_completed_weapons[weapon_id] = true
	size = POSTER_SIZE
	pivot_offset = Vector2(POSTER_SIZE.x * 0.5, 0.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_time = randf() * TAU
	_outline = _build_torn_outline(hash(level["scene"]))


func _process(delta: float) -> void:
	var step_delta := minf(delta, 1.0 / 30.0)
	_time += step_delta
	_size_spring.target = SELECTED_SCALE if _selected else 1.0
	_size_spring.step(step_delta)
	_swing_spring.step(step_delta)
	scale = Vector2.ONE * _size_spring.value
	rotation_degrees = _swing_spring.value + sin(_time * 1.5) * 1.4
	self_modulate = Color.WHITE if _selected else Color(0.86, 0.86, 0.86)
	_step_focus_pulse(step_delta)


func _draw() -> void:
	_draw_paper()
	_draw_title()
	_draw_portrait()
	_draw_difficulty()
	_draw_peg()
	_draw_stamp()
	_draw_weapon_tags()


func set_selected(selected: bool) -> void:
	_selected = selected
	if not selected:
		return
	_size_spring.velocity += 1.6
	_swing_spring.velocity += 40.0 * (1.0 if randf() < 0.5 else -1.0)


## Highlights one weapon tag while the players pick a weapon; -1 clears it.
func set_weapon_focus(index: int) -> void:
	_focused_weapon = index
	_focus_pulse = 0.0
	queue_redraw()


## Where a weapon tag hangs, in the parent's coordinates, following the poster's swing and scale.
func weapon_tag_point(index: int) -> Vector2:
	return get_transform() * _tag_center(index)


func center_point() -> Vector2:
	return rest_position + POSTER_SIZE * Vector2(0.5, 0.5 * SELECTED_SCALE)


func play_enter(delay: float) -> void:
	position = rest_position + Vector2(0.0, -POSTER_SIZE.y - 140.0)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(self, "position", rest_position, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Falls off the rope and removes itself.
func play_leave() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y + 700.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.32)
	tween.chain().tween_callback(queue_free)


func play_stamp_slam() -> void:
	_stamped = true
	_stamp_scale = 0.0
	var tween := create_tween()
	tween.tween_interval(STAMP_DELAY_SECONDS)
	tween.tween_callback(_begin_stamp_fall)
	tween.tween_method(_set_stamp_scale, 3.2, 1.0, 0.14).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_callback(_on_stamp_landed)


func _begin_stamp_fall() -> void:
	_set_stamp_scale(3.2)


func _set_stamp_scale(value: float) -> void:
	_stamp_scale = value
	queue_redraw()


func _on_stamp_landed() -> void:
	_size_spring.velocity -= 4.0
	_swing_spring.velocity += 60.0
	stamp_landed.emit()


func _draw_paper() -> void:
	var shadow := _outline.duplicate()
	for index in shadow.size():
		shadow[index] += Vector2(7.0, 9.0)
	draw_colored_polygon(shadow, PAPER_SHADOW)
	draw_colored_polygon(_outline, PAPER)
	draw_rect(Rect2(Vector2(14.0, 14.0), POSTER_SIZE - Vector2(28.0, 28.0)), Color(INK, 0.45), false, 3.0)


func _draw_title() -> void:
	var title: String = level["title"]
	draw_string(FONT, Vector2(0.0, 66.0), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, POSTER_SIZE.x, 42, INK)


func _draw_portrait() -> void:
	draw_rect(PORTRAIT_RECT, Color(INK, 0.12))
	var art: int = level["art"]
	if art == LevelSelectCatalog.Art.BOSS:
		_draw_fitted(BOSS, Rect2(1640.0, 726.0, 135.0, 125.0), BOSS_TINT)
		return
	if art == LevelSelectCatalog.Art.HORDE:
		_draw_fitted(SKELETONS, Rect2(0.0, 660.0, 430.0, 320.0))
		return
	_draw_fitted(SKELETONS, Rect2(46.0, 662.0, 170.0, 160.0))


func _draw_fitted(texture: Texture2D, region: Rect2, tint := Color.WHITE) -> void:
	var fit := minf(PORTRAIT_RECT.size.x / region.size.x, PORTRAIT_RECT.size.y / region.size.y)
	var drawn := region.size * fit
	draw_texture_rect_region(texture, Rect2(PORTRAIT_RECT.get_center() - drawn * 0.5, drawn), region, tint)


func _draw_difficulty() -> void:
	var difficulty: int = level["difficulty"]
	var start_x := POSTER_SIZE.x * 0.5 - SKULL_SPACING * (MAX_DIFFICULTY - 1) * 0.5
	for index in MAX_DIFFICULTY:
		var earned := index < difficulty
		_draw_skull(Vector2(start_x + index * SKULL_SPACING, 318.0), INK if earned else Color(INK, 0.2))
	draw_string(FONT, Vector2(0.0, 380.0), _label_text(), HORIZONTAL_ALIGNMENT_CENTER, POSTER_SIZE.x, 28, _label_color())


## While the players pick a weapon, the label names it, since the tags below can be covered.
func _label_text() -> String:
	if _focused_weapon < 0:
		return String(level["label"]).to_upper()
	return "WITH " + WeaponCatalog.display_name(_weapon_ids[_focused_weapon]).to_upper()


func _label_color() -> Color:
	return STAMP_RED if _focused_weapon >= 0 else INK


func _draw_skull(at: Vector2, color: Color) -> void:
	draw_circle(at, 15.0, color, true, -1.0, true)
	draw_rect(Rect2(at + Vector2(-9.0, 9.0), Vector2(18.0, 12.0)), color)
	draw_circle(at + Vector2(-6.0, 0.0), 4.5, PAPER, true, -1.0, true)
	draw_circle(at + Vector2(6.0, 0.0), 4.5, PAPER, true, -1.0, true)


func _draw_peg() -> void:
	var peg := Rect2(POSTER_SIZE.x * 0.5 - 11.0, -22.0, 22.0, 46.0)
	draw_rect(peg, Color(0.46, 0.27, 0.12))
	draw_rect(peg, INK, false, 2.0)


func _draw_stamp() -> void:
	if not _stamped or _stamp_scale <= 0.0:
		return
	var is_boss: bool = level["art"] == LevelSelectCatalog.Art.BOSS
	var text := "SLAIN" if is_boss else "CLEARED"
	var font_size := 66 if is_boss else 48
	draw_set_transform(POSTER_SIZE * Vector2(0.5, 0.45), deg_to_rad(-16.0), Vector2.ONE * _stamp_scale)
	draw_rect(Rect2(-130.0, -50.0, 260.0, 100.0), STAMP_RED, false, 8.0)
	var baseline := FONT.get_ascent(font_size) * 0.5 - 5.0
	draw_string(FONT, Vector2(-130.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, 260.0, font_size, STAMP_RED)
	draw_set_transform(Vector2.ZERO)


func _step_focus_pulse(delta: float) -> void:
	if _focused_weapon < 0:
		return
	_focus_pulse += delta
	queue_redraw()


func _tag_center(index: int) -> Vector2:
	var row := index / TAGS_PER_ROW
	var column := index % TAGS_PER_ROW
	var in_row := mini(_weapon_ids.size() - row * TAGS_PER_ROW, TAGS_PER_ROW)
	var row_width := in_row * TAG_RADIUS * 2.0 + (in_row - 1) * TAG_GAP
	var x := (POSTER_SIZE.x - row_width) * 0.5 + TAG_RADIUS + column * (TAG_RADIUS * 2.0 + TAG_GAP)
	return Vector2(x, POSTER_SIZE.y + TAG_DROP + TAG_RADIUS + row * TAG_ROW_STEP)


## Cords first, so the second row's cords pass behind the first row's tags.
func _draw_weapon_tags() -> void:
	for index in _weapon_ids.size():
		var center := _tag_center(index)
		draw_line(Vector2(center.x, POSTER_SIZE.y - 8.0), center, INK, 3.0, true)
	for index in _weapon_ids.size():
		_draw_weapon_tag(index)


func _draw_weapon_tag(index: int) -> void:
	var center := _tag_center(index)
	var focused := index == _focused_weapon
	var radius := TAG_RADIUS * (TAG_FOCUS_SCALE + sin(_focus_pulse * 6.0) * 0.04 if focused else 1.0)
	draw_circle(center + Vector2(4.0, 5.0), radius, PAPER_SHADOW, true, -1.0, true)
	draw_circle(center, radius, PAPER, true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 40, INK, 3.0, true)
	_draw_tag_icon(index, center, radius)
	if focused:
		draw_arc(center, radius + 5.0, 0.0, TAU, 40, TAG_FOCUS_RING, 6.0, true)
	if _completed_weapons.has(_weapon_ids[index]):
		_draw_check(center + Vector2(radius, radius) * 0.7)


func _draw_tag_icon(index: int, center: Vector2, radius: float) -> void:
	var icon := _weapon_icons[index]
	if icon == null:
		return
	var side := radius * 1.7
	draw_texture_rect(icon, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false)


## The red tick that says this weapon has beaten the level.
func _draw_check(at: Vector2) -> void:
	draw_circle(at, CHECK_RADIUS, STAMP_RED, true, -1.0, true)
	var points := PackedVector2Array([at + Vector2(-7.0, 0.0), at + Vector2(-2.0, 6.0), at + Vector2(8.0, -6.0)])
	draw_polyline(points, PAPER, 4.0, true)


func _build_torn_outline(random_seed: int) -> PackedVector2Array:
	var random := RandomNumberGenerator.new()
	random.seed = random_seed
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(POSTER_SIZE.x, 0.0), POSTER_SIZE, Vector2(0.0, POSTER_SIZE.y)]
	var points := PackedVector2Array()
	for corner_index in corners.size():
		var from := corners[corner_index]
		var to := corners[(corner_index + 1) % corners.size()]
		for step in EDGE_STEPS:
			var jitter := Vector2(random.randf_range(-1.0, 1.0), random.randf_range(-1.0, 1.0)) * JAGGED_PIXELS
			points.append(from.lerp(to, float(step) / EDGE_STEPS) + jitter)
	return points
