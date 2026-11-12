class_name GunshipCourse
extends Node3D
## Phase 3 of the gunship fight: the arena crumbles from west to east, and the carriers flee east along twin fragile
## tracks, one each, to a smaller platform, which crumbles 15 s after they land, and on to the next, up to
## `MAX_PLATFORMS`. The last one crumbles too, so the fight has to end before the course does.
##
## Tracks follow one of four shapes in turn (straights and 45° diagonals, so the two tracks stay within the fork
## cannon's carry range through every turn). Each track and the platform after it are built when the carriers land
## on the platform before, rising into place ahead of them. Plank pieces are FragileTile (3 s once stepped on; the
## first of each track 1 s and twice as long, so a pair walking single file loses the back carrier); platforms are
## station plates added to the deck's GridMaps (BreakableDeck), so they crumble like the arena.
##
## The gunship reads where to fly from here: over a platform it holds that platform's sides, as in the arena; on the
## tracks it escorts the carriers from the north.

signal phase_started
signal platform_reached(index: int)

const GROUP := &"gunship_course"
const MAX_PLATFORMS := 16
## Centre to centre. The fork cannon holds its carriers 1.6 to 4.2 m apart; 45° turns widen the gap to 3.25 m.
const TRACK_GAP := 3.0
const PLANK_LENGTH := 1.5
const PLANK_WIDTH := 1.5
const PLANK_THICKNESS := 0.3
const FIRST_PLANK_LENGTH := 3.0
const PAD_RADIUS := 0.95
const FUSE_SECONDS := 3.0
const FIRST_FUSE_SECONDS := 1.0
const PLATFORM_CELLS := 5
const PLATFORM_SECONDS := 15.0
## Track shapes in grid cells: straights and 45° diagonals, with a straight between any two turns, ending on the row
## they start on. Forward is east (+x); north is -z.
const SHAPES: Array = [
	[Vector2i(2, 0), Vector2i(2, -2), Vector2i(2, 0), Vector2i(3, 3), Vector2i(2, 0), Vector2i(1, -1), Vector2i(2, 0)],
	[Vector2i(1, 0), Vector2i(2, -2), Vector2i(1, 0), Vector2i(2, 2), Vector2i(1, 0), Vector2i(2, 2), Vector2i(1, 0), Vector2i(2, -2), Vector2i(1, 0)],
	[Vector2i(3, 0), Vector2i(3, 3), Vector2i(2, 0), Vector2i(3, -3), Vector2i(3, 0)],
	[Vector2i(2, 0), Vector2i(4, -4), Vector2i(1, 0), Vector2i(4, 4), Vector2i(2, 0)],
]

@export var deck: BreakableDeck
@export var phase_three_checkpoint: Checkpoint
## The arena: its cells crumble at the start, and it counts as platform 0.
@export var arena_cells_min := Vector2i(-3, -10)
@export var arena_cells_max := Vector2i(3, -4)
## Seconds from the phase starting to the arena's first column cracking.
@export var arena_crumble_delay := 2.5
@export var arena_column_seconds := 1.2
@export var plank_color := Color(0.46, 0.52, 0.58)
@export var trim_color := Color(0.35, 0.85, 1.0)

var _active := false
var _resume := false
## Index 0 is the arena; each later entry is a section: the track that leads to platform i, then platform i.
var _sections: Array[Dictionary] = []
var _reached := 0
var _material: StandardMaterial3D
var _floor_y := 0.0
## Bumped when the phase starts and on every reset, so timers from before a respawn do nothing.
var _run := 0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"checkpoint_resettable")
	_material = StandardMaterial3D.new()
	_material.albedo_color = plank_color
	_material.metallic = 0.25
	_material.roughness = 0.55
	_resume = _is_phase_three_checkpoint()


static func find(tree: SceneTree) -> GunshipCourse:
	return tree.get_first_node_in_group(GROUP) as GunshipCourse


# ---- The boss's view. ----

func is_active() -> bool:
	return _active


## True after a respawn at the phase three checkpoint: the gunship skips straight to phase 3 when it wakes.
func should_resume_phase_three() -> bool:
	return _resume


## The platform both carriers stand on (0 is the arena), or -1 while they're on the tracks.
func platform_under_players() -> int:
	var players := _living_players()
	if players.is_empty():
		return _reached
	for index in _sections.size():
		if _all_inside(players, _sections[index]["rect"]):
			return index
	return -1


func platforms_reached() -> int:
	return _reached


func focus_center(index: int) -> Vector3:
	var rect: Rect2 = _sections[index]["rect"]
	var middle := rect.get_center()
	return Vector3(middle.x, _floor_y, middle.y)


func focus_half_extent(index: int) -> float:
	return (_sections[index]["rect"] as Rect2).size.x * 0.5


## The track's centre line on the way to the next platform, at `x`: where the escorting gunship lines up.
func track_centre_at(x: float) -> Vector3:
	var section := mini(_reached + 1, _sections.size() - 1)
	var line: PackedVector2Array = _sections[section].get("centre", PackedVector2Array())
	if line.is_empty():
		return focus_center(_reached)
	return Vector3(x, _floor_y, _z_on_line(line, x))


## The two track lines of section `index` (north and south), for tests: world points at deck height.
func track_lines(index: int) -> Dictionary:
	var section: Dictionary = _sections[index]
	return {"centre": _to_3d(section["centre"]), "north": _to_3d(section["north"]), "south": _to_3d(section["south"])}


func section_count() -> int:
	return _sections.size()


# ---- Running the phase. ----

func begin_phase_three() -> void:
	if _active:
		return
	_active = true
	_resume = false
	_run += 1
	if phase_three_checkpoint != null:
		phase_three_checkpoint._trigger_checkpoint()
	_floor_y = deck.cell_top(arena_cells_min).y
	_sections.clear()
	_reached = 0
	_sections.append({"rect": _cells_rect(arena_cells_min, arena_cells_max), "landed": true, "tiles": []})
	_crumble_arena()
	_build_section()
	phase_started.emit()


func reset_to_checkpoint() -> void:
	for section in _sections:
		for tile in section.get("tiles", []):
			if is_instance_valid(tile):
				tile.queue_free()
	_sections.clear()
	_active = false
	_reached = 0
	_run += 1
	_resume = _is_phase_three_checkpoint()


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	var players := _living_players()
	_light_tiles_under(players)
	_check_landing(players)


func _light_tiles_under(players: Array[PlayerLocal]) -> void:
	var space := get_world_3d().direct_space_state
	for player in players:
		var from := player.global_position + Vector3.UP * 0.5
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, FragileTile.FLOOR_LAYER)
		var hit := space.intersect_ray(query)
		var tile := hit.get("collider") as FragileTile
		if tile == null:
			continue
		tile.step_on()


func _check_landing(players: Array[PlayerLocal]) -> void:
	var next := _reached + 1
	if next >= _sections.size() or players.is_empty():
		return
	if not _all_inside(players, _sections[next]["rect"]):
		return
	_reached = next
	_sections[next]["landed"] = true
	get_tree().create_timer(PLATFORM_SECONDS).timeout.connect(_crumble_platform.bind(next, _run))
	if next < MAX_PLATFORMS:
		_build_section()
	platform_reached.emit(next)


# ---- Crumbling. ----

func _crumble_arena() -> void:
	var delays := {}
	var jitter := randf_range(0.6, 1.0)
	for x in range(arena_cells_min.x, arena_cells_max.x + 1):
		for z in range(arena_cells_min.y, arena_cells_max.y + 1):
			var cell := Vector2i(x, z)
			if not deck.has_tile(cell):
				continue
			delays[cell] = arena_crumble_delay + (x - arena_cells_min.x) * arena_column_seconds + randf_range(0.0, jitter)
	deck.crumble(delays, 1.2)


## West to east, with a different feel each time: column pace, a slant across the rows and per-plate jitter.
func _crumble_platform(index: int, run: int) -> void:
	if run != _run or index >= _sections.size():
		return
	var section: Dictionary = _sections[index]
	var pace := randf_range(0.6, 1.0)
	var slant := randf_range(-0.25, 0.25)
	var jitter := randf_range(0.3, 0.9)
	var delays := {}
	for cell in section["cells"]:
		var column: int = cell.x - section["cells"][0].x
		var row: int = cell.y - section["row"]
		delays[cell] = maxf(0.0, column * pace + row * slant + randf_range(0.0, jitter))
	deck.crumble(delays, 1.0)


# ---- Building. ----

## Lays out the track from the last platform's east edge, then the platform at its end.
func _build_section() -> void:
	var index := _sections.size()
	var shape: Array = SHAPES[(index - 1) % SHAPES.size()]
	var start := _section_start(index)
	var centre := PackedVector2Array([start])
	for step in shape:
		centre.append(centre[centre.size() - 1] + Vector2(step) * deck.floor_map.cell_size.x)
	var north := _offset_line(centre, TRACK_GAP * 0.5)
	var south := _offset_line(centre, -TRACK_GAP * 0.5)
	var tiles: Array = []
	tiles.append_array(_lay_track(north))
	tiles.append_array(_lay_track(south))
	var end_cell := deck.cell_at(Vector3(centre[centre.size() - 1].x + 0.1, _floor_y, centre[centre.size() - 1].y))
	var half := PLATFORM_CELLS / 2
	var cells: Array[Vector2i] = []
	for x in range(end_cell.x, end_cell.x + PLATFORM_CELLS):
		for z in range(end_cell.y - half, end_cell.y + half + 1):
			cells.append(Vector2i(x, z))
	deck.add_platform(cells)
	_sections.append({"centre": centre, "north": north, "south": south, "tiles": tiles, "cells": cells, "row": end_cell.y,
		"rect": _cells_rect(cells[0], cells[cells.size() - 1]), "landed": false})


## Where section `index`'s track leaves: the middle of the previous platform's east edge.
func _section_start(index: int) -> Vector2:
	var rect: Rect2 = _sections[index - 1]["rect"]
	return Vector2(rect.end.x, rect.get_center().y)


## Planks along one track line, a pad over each turn. The first plank is long and quick to fall.
func _lay_track(line: PackedVector2Array) -> Array:
	var tiles: Array = []
	var order := 0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var length := a.distance_to(b)
		var direction := (b - a) / length
		var walked := 0.0
		while walked < length - 0.01:
			var first := i == 0 and walked == 0.0
			var piece := minf(FIRST_PLANK_LENGTH if first else PLANK_LENGTH, length - walked)
			var tile := FragileTile.make_plank(piece, PLANK_WIDTH, PLANK_THICKNESS, FIRST_FUSE_SECONDS if first else FUSE_SECONDS, _material)
			var middle := a + direction * (walked + piece * 0.5)
			_place(tile, middle, direction, 0.0, order)
			tiles.append(tile)
			walked += piece
			order += 1
		if i == 0:
			continue
		var pad := FragileTile.make_pad(PAD_RADIUS, PLANK_THICKNESS, FUSE_SECONDS, _material)
		_place(pad, a, direction, 0.02, order)
		tiles.append(pad)
	return tiles


func _place(tile: FragileTile, flat: Vector2, direction: Vector2, lift: float, order: int) -> void:
	add_child(tile)
	var forward := Vector3(direction.x, 0.0, direction.y)
	tile.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), Vector3(flat.x, _floor_y + lift, flat.y))
	tile.rise(0.04 * order)


## The line moved `distance` to its left (north when heading east), mitred at the turns.
static func _offset_line(line: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in line.size():
		var before := (line[i] - line[maxi(i - 1, 0)]).normalized() if i > 0 else (line[1] - line[0]).normalized()
		var after := (line[mini(i + 1, line.size() - 1)] - line[i]).normalized() if i < line.size() - 1 else before
		var left_before := Vector2(before.y, -before.x)
		var left_after := Vector2(after.y, -after.x)
		var mitre := (left_before + left_after).normalized()
		out.append(line[i] + mitre * distance / maxf(mitre.dot(left_after), 0.5))
	return out


# ---- Helpers. ----

func _cells_rect(a: Vector2i, b: Vector2i) -> Rect2:
	var size := deck.floor_map.cell_size.x
	var low := Vector2(mini(a.x, b.x), mini(a.y, b.y)) * size
	var high := Vector2(maxi(a.x, b.x) + 1, maxi(a.y, b.y) + 1) * size
	return Rect2(low, high - low)


func _all_inside(players: Array[PlayerLocal], rect: Rect2) -> bool:
	for player in players:
		if not rect.has_point(Vector2(player.global_position.x, player.global_position.z)):
			return false
		if player.global_position.y < _floor_y - 1.0:
			return false
	return true


static func _z_on_line(line: PackedVector2Array, x: float) -> float:
	if x <= line[0].x:
		return line[0].y
	for i in line.size() - 1:
		if x > line[i + 1].x:
			continue
		var t := inverse_lerp(line[i].x, line[i + 1].x, x)
		return lerpf(line[i].y, line[i + 1].y, t)
	return line[line.size() - 1].y


func _to_3d(line: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in line:
		out.append(Vector3(point.x, _floor_y, point.y))
	return out


func _is_phase_three_checkpoint() -> bool:
	if phase_three_checkpoint == null:
		return false
	var manager := phase_three_checkpoint.get_parent() as CheckpointManager
	return manager != null and manager.current_checkpoint == phase_three_checkpoint


func _living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var players := get_tree().current_scene.get_node_or_null(^"Players")
	if players == null:
		return living
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		living.append(player)
	return living
