class_name SpikeTrap
extends Node3D
## Two spiked walls, north and south, that close in on the carriers, and two wooden pressure plates between them.
## Nobody on a plate: the walls close at full speed. One plate held: they slow down. Both held: they stop.
## The plates sit side by side along x, one carrier's spacing apart, so a pair carrying the weapon east-west
## can hold both while they shoot.
##
## The origin is the trap's centre, on the floor. It builds its walls and plates itself.
## SpikeTrapEvent starts and retracts it. Respawning at any checkpoint puts it back, open and waiting.

enum State { WAITING, CLOSING, RETRACTING, OPEN }

const RESET_GROUP := &"checkpoint_resettable"

@export_group("Walls")
## Distance from the centre to each wall's spike tips when the trap starts.
@export var start_half_gap := 8.0
## How wide each wall is, along x.
@export var wall_width := 33.0
## Moves both walls along x, for a floor that isn't centred on the plates.
@export var wall_offset_x := 0.0
@export var north_wall_height := 2.0
## The camera looks north from the south, so a tall south wall would hide the carriers.
@export var south_wall_height := 1.0
@export_group("Speeds")
## Metres per second each wall moves with nobody on a plate.
@export var close_speed := 0.32
## Metres per second each wall moves with one plate held.
@export var slowed_speed := 0.11
@export var retract_speed := 2.5
@export_group("Plates")
## Centre to centre, along x. The bazooka keeps its carriers 1.6 to 4.2 m apart.
@export var plate_spacing := 2.9
@export var plate_size := Vector2(1.3, 3.2)
## How far the plank deck under the plates reaches past them on every side.
@export var deck_margin := 0.6

var state := State.WAITING
var half_gap := 0.0
var north_wall: SpikeWall
var south_wall: SpikeWall
var plates: Array[PressurePlate] = []


func _ready() -> void:
	add_to_group(RESET_GROUP)
	north_wall = _make_wall("NorthWall", north_wall_height)
	south_wall = _make_wall("SouthWall", south_wall_height)
	_make_deck()
	plates.append(_make_plate("PlateWest", -plate_spacing * 0.5))
	plates.append(_make_plate("PlateEast", plate_spacing * 0.5))
	_set_half_gap(start_half_gap)


func start() -> void:
	if state != State.WAITING:
		return
	state = State.CLOSING


func retract() -> void:
	if state == State.OPEN:
		return
	state = State.RETRACTING


func reset_to_checkpoint() -> void:
	state = State.WAITING
	_set_half_gap(start_half_gap)


func pressed_plate_count() -> int:
	var count := 0
	for plate in plates:
		if plate.is_pressed():
			count += 1
	return count


## How fast the walls are closing right now, in metres per second each.
func current_speed() -> float:
	if state != State.CLOSING:
		return 0.0
	var pressed := pressed_plate_count()
	if pressed >= plates.size():
		return 0.0
	if pressed > 0:
		return slowed_speed
	return close_speed


func _physics_process(delta: float) -> void:
	var players := _living_players()
	for plate in plates:
		plate.update_pressed(players)
	if state == State.RETRACTING:
		_retract_step(delta)
		return
	if state != State.CLOSING:
		return
	_set_half_gap(maxf(0.0, half_gap - current_speed() * delta))


func _retract_step(delta: float) -> void:
	_set_half_gap(minf(start_half_gap, half_gap + retract_speed * delta))
	if half_gap < start_half_gap:
		return
	state = State.OPEN


func _set_half_gap(value: float) -> void:
	half_gap = value
	north_wall.position = Vector3(wall_offset_x, 0.0, -(half_gap + north_wall.get_reach()))
	south_wall.position = Vector3(wall_offset_x, 0.0, half_gap + south_wall.get_reach())


func _living_players() -> Array[PlayerLocal]:
	var out: Array[PlayerLocal] = []
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		return out
	for child in world.players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		out.append(player)
	return out


func _make_wall(wall_name: String, wall_height: float) -> SpikeWall:
	var wall := SpikeWall.new()
	wall.name = wall_name
	wall.width = wall_width
	wall.height = wall_height
	add_child(wall)
	if wall_name == "NorthWall":
		wall.rotation.y = PI  # faces south, so its spikes point at the centre
	return wall


## One thin plank deck under both plates, so they don't sit straight on the grass.
func _make_deck() -> void:
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var mesh := BoxMesh.new()
	var thickness := PressurePlate.DECK_TOP_Y + 0.05  # sunk a little, so bumps in the grass don't poke through
	mesh.size = Vector3(plate_spacing + plate_size.x + deck_margin * 2.0, thickness, plate_size.y + deck_margin * 2.0)
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/world/elements/sky_decks/wood_planks.gdshader")
	material.set_shader_parameter("wood_color", Color(0.45, 0.3, 0.17))
	material.set_shader_parameter("plank_width", 0.45)
	material.set_shader_parameter("plank_length", 2.4)
	material.set_shader_parameter("local_space", true)
	mesh.material = material
	deck.mesh = mesh
	deck.position = Vector3(0.0, PressurePlate.DECK_TOP_Y - thickness * 0.5, 0.0)
	add_child(deck)


func _make_plate(plate_name: String, x: float) -> PressurePlate:
	var plate := PressurePlate.new()
	plate.name = plate_name
	plate.size = plate_size
	plate.position = Vector3(x, 0.0, 0.0)
	add_child(plate)
	return plate
