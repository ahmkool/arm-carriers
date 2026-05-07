extends CharacterBody3D

const SPEED = 5.0

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

# Distinct colors; assignment is stable per peer id on every client.
const PLAYER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0),
	Color(1.0, 0.35, 0.28),
	Color(0.35, 0.88, 0.45),
	Color(0.95, 0.72, 0.2),
	Color(0.75, 0.45, 1.0),
	Color(0.95, 0.45, 0.75),
]

func _ready():
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color_for_peer_id(name.to_int())
	$MeshInstance3D.material_override = mat

func _color_for_peer_id(peer_id: int) -> Color:
	var idx := absi(hash(peer_id)) % PLAYER_COLORS.size()
	return PLAYER_COLORS[idx]

func _enter_tree():
	# Set the multiplayer authority to the peer ID (which will be the node's name)
	set_multiplayer_authority(name.to_int())

func _physics_process(delta):
	# Only the player who owns this sphere can control it
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Get input for 4-way movement (using default arrow keys or WASD)
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	if is_on_floor():
		velocity.y = 0.0
