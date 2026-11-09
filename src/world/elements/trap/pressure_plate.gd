class_name PressurePlate
extends Node3D
## A wooden button standing proud of a plank deck. It counts as pressed while a living carrier's feet are on it,
## and sinks almost flush with the deck so both players can see it is held.
##
## The origin is on the floor, under the plate's centre. SpikeTrap lays the deck (DECK_TOP_Y high) around it.
## Visual only: there is no collision, so carriers walk onto it without a step.

## How high the deck around the plate comes. SpikeTrap builds the deck to this height.
const DECK_TOP_Y := 0.05
## The plate's top when nobody stands on it, and when it is pressed down.
const TOP_REST_Y := 0.34
const TOP_PRESSED_Y := 0.08
const PLATE_THICKNESS := 0.3
## Pressed down, the wood darkens a little, as if it sank into shade.
const WOOD_COLOR := Color(0.7, 0.48, 0.26)
const PRESSED_WOOD_COLOR := Color(0.5, 0.33, 0.18)
## The dark recess the plate sinks into shows this far past its edges.
const SOCKET_MARGIN := 0.06
## A quick drop and a slower rise, like a heavy button on a spring.
const PRESS_SPEED := 9.0
const RELEASE_SPEED := 3.0
## A carrier whose feet are this far past the edge still counts: the capsule overhangs the feet.
const EDGE_TOLERANCE := 0.15
const HEIGHT_TOLERANCE := 1.2

## x is across, z is along. Longer in z gives the carriers room to move along it.
@export var size := Vector2(1.3, 3.2)

var _pressed := false
var _press_amount := 0.0
var _top: MeshInstance3D
var _top_material: ShaderMaterial


func _ready() -> void:
	_build_socket()
	_build_top()


func _process(delta: float) -> void:
	if _pressed:
		_press_amount = move_toward(_press_amount, 1.0, PRESS_SPEED * delta)
	if not _pressed:
		_press_amount = move_toward(_press_amount, 0.0, RELEASE_SPEED * delta)
	var top_y := lerpf(TOP_REST_Y, TOP_PRESSED_Y, _press_amount)
	_top.position.y = top_y - PLATE_THICKNESS * 0.5
	_top_material.set_shader_parameter("wood_color", WOOD_COLOR.lerp(PRESSED_WOOD_COLOR, _press_amount))


## Re-reads who stands on it. The trap calls this once per physics frame.
func update_pressed(players: Array[PlayerLocal]) -> bool:
	_pressed = false
	for player in players:
		if _is_standing_on(player):
			_pressed = true
			return true
	return false


func is_pressed() -> bool:
	return _pressed


func _is_standing_on(player: PlayerLocal) -> bool:
	if player.is_dead:
		return false
	var local := to_local(player.global_position)
	if absf(local.y) > HEIGHT_TOLERANCE:
		return false
	if absf(local.x) > size.x * 0.5 + EDGE_TOLERANCE:
		return false
	return absf(local.z) <= size.y * 0.5 + EDGE_TOLERANCE


## A dark slot in the deck, just above it, so a gap shows round the plate.
func _build_socket() -> void:
	var socket := MeshInstance3D.new()
	socket.name = "Socket"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x + SOCKET_MARGIN * 2.0, 0.02, size.y + SOCKET_MARGIN * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.06, 0.04)
	material.roughness = 1.0
	mesh.material = material
	socket.mesh = mesh
	socket.position = Vector3(0.0, DECK_TOP_Y + 0.01, 0.0)
	add_child(socket)


func _build_top() -> void:
	_top = MeshInstance3D.new()
	_top.name = "Top"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, PLATE_THICKNESS, size.y)
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/world/elements/sky_decks/wood_planks.gdshader")
	material.set_shader_parameter("wood_color", WOOD_COLOR)
	material.set_shader_parameter("plank_width", 0.32)
	# Rows run along z, so each row is one short board laid across the plate.
	material.set_shader_parameter("plank_length", size.x + 0.4)
	material.set_shader_parameter("local_space", true)
	mesh.material = material
	_top_material = material
	_top.mesh = mesh
	_top.position = Vector3(0.0, TOP_REST_Y - PLATE_THICKNESS * 0.5, 0.0)
	add_child(_top)
