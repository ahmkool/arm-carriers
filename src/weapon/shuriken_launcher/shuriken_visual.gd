class_name ShurikenVisual
extends Node3D
## The big four-bladed star with a kunai riding in the slot of each blade. Used both for the star
## loaded on the launcher and for the one in flight. Blades lie along local +-X and +-Z; each kunai
## points out along its blade. Models come from tools/blender/build_shuriken_launcher.py.
## A scene can place the models itself (the launcher does, so its icon shows the star): then the
## children whose names start with "Kunai" are the kunai. With no children, it builds them.

const SHURIKEN_MODEL := preload("res://assets/models/weapon/shuriken_launcher/shuriken.glb")
const KUNAI_MODEL := preload("res://assets/models/weapon/shuriken_launcher/kunai.glb")
## Middle of each blade's slot, in metres from the hub. Matches SLOT_FROM / SLOT_TO in the Blender script.
const KUNAI_RADIUS := 0.65
const BLADE_COUNT := 4

var _kunais: Array[Node3D] = []


func _ready() -> void:
	if get_child_count() == 0:
		_build()
	for child in get_children():
		if child.name.begins_with("Kunai"):
			_kunais.append(child)


func _build() -> void:
	add_child(SHURIKEN_MODEL.instantiate())
	for i in BLADE_COUNT:
		var kunai := KUNAI_MODEL.instantiate() as Node3D
		kunai.name = "Kunai%d" % i
		kunai.transform = kunai_slot_transform(i)
		add_child(kunai)


## A kunai's place in blade `index`, local to the star: centred in the slot, tip outwards.
static func kunai_slot_transform(index: int) -> Transform3D:
	var basis := Basis(Vector3.UP, index * TAU / BLADE_COUNT)
	return Transform3D(basis, basis.z * KUNAI_RADIUS)


func set_kunais_visible(shown: bool) -> void:
	for kunai in _kunais:
		kunai.visible = shown
