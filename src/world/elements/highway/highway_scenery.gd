class_name HighwayScenery
extends Node3D
## High-speed scrolling highway environment for the stationary-reference-frame ("treadmill") chase.
## Moves recycled roadside props, streetlights, cantilever highway signs, city skyline towers,
## decorative background traffic, and wind streaks toward +Z at `highway_speed` while the asphalt
## shader scrolls at the exact same speed.

const ROAD_SHADER := preload("res://src/world/elements/highway/highway_road.gdshader")

## Base speed of the convoy in metres per second (38 m/s ≈ 137 km/h).
@export var highway_speed: float = 38.0
## Vertical height of the asphalt surface (car roofs sit at Y = 0.0).
@export var road_y: float = -3.0
## Half-width of the elevated highway asphalt deck.
@export var road_half_width: float = 21.5

const CHUNK_LENGTH := 24.0
const CHUNK_COUNT := 11
const CHUNK_START_Z := -156.0
const CHUNK_END_Z := CHUNK_START_Z + CHUNK_LENGTH * CHUNK_COUNT

const SKYLINE_COUNT := 14
const SKYLINE_SPACING := 22.0
const SKYLINE_START_Z := -170.0
const SKYLINE_END_Z := SKYLINE_START_Z + SKYLINE_SPACING * SKYLINE_COUNT

var _road_material: ShaderMaterial
var _deck_followers: Array[Node3D] = []
var _wind_streaks: GPUParticles3D
var _road_chunks: Array[Node3D] = []
var _skyline_chunks: Array[Node3D] = []
var _bg_cars: Array[Dictionary] = []

# Shared procedural materials & meshes to keep draw calls and memory minimal.
var _mat_concrete: StandardMaterial3D
var _mat_steel: StandardMaterial3D
var _mat_lamp_glow: StandardMaterial3D
var _mat_reflector_amber: StandardMaterial3D
var _mat_sign_green: StandardMaterial3D
var _mat_sign_border: StandardMaterial3D
var _mat_tower_dark: StandardMaterial3D
var _mat_window_warm: StandardMaterial3D
var _mat_window_cool: StandardMaterial3D
var _mat_headlight: StandardMaterial3D
var _mat_taillight: StandardMaterial3D


func _ready() -> void:
	_create_shared_materials()
	_build_road_deck()
	_build_roadside_chunks()
	_build_skyline_chunks()
	_build_background_traffic()
	_build_wind_streaks()


func _process(delta: float) -> void:
	var anchor_z := _get_anchor_z()
	var deck_z := anchor_z - 18.0
	for follower in _deck_followers:
		follower.position.z = deck_z
	if _road_material != null:
		_road_material.set_shader_parameter("fade_center_z", deck_z)
	if _wind_streaks != null:
		_wind_streaks.position.z = anchor_z - 75.0

	var step := highway_speed * delta
	var chunk_span := CHUNK_LENGTH * CHUNK_COUNT
	var chunk_min_z := anchor_z + CHUNK_START_Z
	var chunk_max_z := anchor_z + CHUNK_END_Z
	for chunk in _road_chunks:
		chunk.position.z += step
		while chunk.position.z > chunk_max_z:
			chunk.position.z -= chunk_span
		while chunk.position.z < chunk_min_z:
			chunk.position.z += chunk_span

	# Distant skyline scrolls slightly slower (0.72x) for subtle cinematic depth parallax.
	var skyline_step := highway_speed * 0.72 * delta
	var skyline_span := SKYLINE_SPACING * SKYLINE_COUNT
	var skyline_min_z := anchor_z + SKYLINE_START_Z
	var skyline_max_z := anchor_z + SKYLINE_END_Z
	for tower in _skyline_chunks:
		tower.position.z += skyline_step
		while tower.position.z > skyline_max_z:
			tower.position.z -= skyline_span
		while tower.position.z < skyline_min_z:
			tower.position.z += skyline_span

	var bg_min_z := anchor_z - 165.0
	var bg_max_z := anchor_z + 95.0
	for entry in _bg_cars:
		var node: Node3D = entry["node"]
		var rel_speed: float = entry["speed"]
		node.position.z += rel_speed * delta
		if rel_speed > 0.0 and node.position.z > bg_max_z:
			node.position.z = anchor_z - 155.0 - randf_range(0.0, 40.0)
		elif rel_speed > 0.0 and node.position.z < bg_min_z - 40.0:
			node.position.z = anchor_z + randf_range(-140.0, 80.0)
		elif rel_speed < 0.0 and node.position.z < bg_min_z:
			node.position.z = anchor_z + 85.0 + randf_range(0.0, 30.0)
		elif rel_speed < 0.0 and node.position.z > bg_max_z + 30.0:
			node.position.z = anchor_z + randf_range(-140.0, 80.0)


func _get_anchor_z() -> float:
	var world := get_tree().current_scene
	if world != null:
		var players := world.get_node_or_null(^"Players")
		if players != null:
			var sum_z := 0.0
			var count := 0
			for child in players.get_children():
				var p := child as Node3D
				if p == null:
					continue
				if "is_dead" in p and p.is_dead:
					continue
				sum_z += p.global_position.z
				count += 1
			if count > 0:
				return sum_z / float(count)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position.z - 6.8
	return 0.0


func set_highway_speed(new_speed: float) -> void:
	highway_speed = maxf(new_speed, 0.0)
	if _road_material != null:
		_road_material.set_shader_parameter("scroll_speed", highway_speed)


func _create_shared_materials() -> void:
	_mat_concrete = StandardMaterial3D.new()
	_mat_concrete.albedo_color = Color(0.28, 0.29, 0.33)
	_mat_concrete.roughness = 0.85

	_mat_steel = StandardMaterial3D.new()
	_mat_steel.albedo_color = Color(0.22, 0.25, 0.30)
	_mat_steel.metallic = 0.65
	_mat_steel.roughness = 0.42

	_mat_lamp_glow = StandardMaterial3D.new()
	_mat_lamp_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_lamp_glow.albedo_color = Color(1.6, 1.15, 0.55)

	_mat_reflector_amber = StandardMaterial3D.new()
	_mat_reflector_amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_reflector_amber.albedo_color = Color(1.5, 0.65, 0.14)

	_mat_sign_green = StandardMaterial3D.new()
	_mat_sign_green.albedo_color = Color(0.08, 0.42, 0.28)
	_mat_sign_green.roughness = 0.45
	_mat_sign_green.emission_enabled = true
	_mat_sign_green.emission = Color(0.05, 0.28, 0.18)
	_mat_sign_green.emission_energy_multiplier = 0.55

	_mat_sign_border = StandardMaterial3D.new()
	_mat_sign_border.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_sign_border.albedo_color = Color(0.95, 0.96, 0.98)

	_mat_tower_dark = StandardMaterial3D.new()
	_mat_tower_dark.albedo_color = Color(0.09, 0.11, 0.17)
	_mat_tower_dark.roughness = 0.72

	_mat_window_warm = StandardMaterial3D.new()
	_mat_window_warm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_window_warm.albedo_color = Color(1.35, 0.86, 0.42)

	_mat_window_cool = StandardMaterial3D.new()
	_mat_window_cool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_window_cool.albedo_color = Color(0.45, 0.92, 1.35)

	_mat_headlight = StandardMaterial3D.new()
	_mat_headlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_headlight.albedo_color = Color(1.8, 1.7, 1.35)

	_mat_taillight = StandardMaterial3D.new()
	_mat_taillight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_taillight.albedo_color = Color(1.8, 0.16, 0.14)


func _build_road_deck() -> void:
	_road_material = ShaderMaterial.new()
	_road_material.shader = ROAD_SHADER
	_road_material.set_shader_parameter("scroll_speed", highway_speed)
	_road_material.set_shader_parameter("road_half_width", road_half_width)

	var road_mesh := PlaneMesh.new()
	road_mesh.size = Vector2(road_half_width * 2.0, 280.0)
	road_mesh.material = _road_material

	var road := MeshInstance3D.new()
	road.name = "AsphaltDeck"
	road.mesh = road_mesh
	road.position = Vector3(0.0, road_y, -18.0)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	_deck_followers.append(road)

	# Concrete bridge underside deck + side aprons.
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(road_half_width * 2.0 + 3.0, 1.4, 270.0)
	slab_mesh.material = _mat_concrete
	var slab := MeshInstance3D.new()
	slab.name = "OverpassSlab"
	slab.mesh = slab_mesh
	slab.position = Vector3(0.0, road_y - 0.76, -18.0)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slab)
	_deck_followers.append(slab)

	# Outer lower collector lanes for decorative passing background traffic.
	var outer_mat := StandardMaterial3D.new()
	outer_mat.albedo_color = Color(0.075, 0.08, 0.105)
	outer_mat.roughness = 0.8
	var outer_mesh := BoxMesh.new()
	outer_mesh.size = Vector3(7.0, 0.6, 260.0)
	outer_mesh.material = outer_mat
	for side: float in [-1.0, 1.0]:
		var apron := MeshInstance3D.new()
		apron.mesh = outer_mesh
		apron.position = Vector3(side * (road_half_width + 7.2), road_y - 2.6, -18.0)
		apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(apron)
		_deck_followers.append(apron)

	# Continuous concrete jersey barriers on both edges of the main 4-lane highway.
	var barrier_mesh := BoxMesh.new()
	barrier_mesh.size = Vector3(1.1, 1.35, 270.0)
	barrier_mesh.material = _mat_concrete
	for side: float in [-1.0, 1.0]:
		var barrier := MeshInstance3D.new()
		barrier.name = "JerseyBarrierLeft" if side < 0.0 else "JerseyBarrierRight"
		barrier.mesh = barrier_mesh
		barrier.position = Vector3(side * (road_half_width + 0.55), road_y + 0.65, -18.0)
		add_child(barrier)
		_deck_followers.append(barrier)


func _build_roadside_chunks() -> void:
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.22, 1.75, 0.22)
	post_mesh.material = _mat_steel

	var reflector_mesh := BoxMesh.new()
	reflector_mesh.size = Vector3(0.18, 0.14, 0.55)
	reflector_mesh.material = _mat_reflector_amber

	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.14
	pole_mesh.bottom_radius = 0.22
	pole_mesh.height = 9.2
	pole_mesh.radial_segments = 8
	pole_mesh.material = _mat_steel

	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(3.6, 0.18, 0.22)
	arm_mesh.material = _mat_steel

	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(1.1, 0.16, 0.48)
	lamp_mesh.material = _mat_lamp_glow

	var pier_mesh := BoxMesh.new()
	pier_mesh.size = Vector3(2.4, 24.0, 2.4)
	pier_mesh.material = _mat_concrete

	var sign_tower_mesh := BoxMesh.new()
	sign_tower_mesh.size = Vector3(0.55, 8.6, 0.55)
	sign_tower_mesh.material = _mat_steel

	var sign_arm_mesh := BoxMesh.new()
	sign_arm_mesh.size = Vector3(5.4, 0.35, 0.35)
	sign_arm_mesh.material = _mat_steel

	var sign_board_mesh := BoxMesh.new()
	sign_board_mesh.size = Vector3(4.8, 1.85, 0.18)
	sign_board_mesh.material = _mat_sign_green

	var sign_stripe_mesh := BoxMesh.new()
	sign_stripe_mesh.size = Vector3(3.6, 0.22, 0.22)
	sign_stripe_mesh.material = _mat_sign_border

	for i in CHUNK_COUNT:
		var chunk := Node3D.new()
		chunk.name = "RoadChunk_%d" % i
		chunk.position = Vector3(0.0, 0.0, CHUNK_START_Z + i * CHUNK_LENGTH)

		for side: float in [-1.0, 1.0]:
			var edge_x := side * (road_half_width + 0.55)

			# Repeating steel guardrail posts & glowing reflectors along the jersey barrier.
			for sub in 3:
				var sub_z := (sub - 1) * (CHUNK_LENGTH / 3.0)
				var post := MeshInstance3D.new()
				post.mesh = post_mesh
				post.position = Vector3(edge_x + side * 0.2, road_y + 1.15, sub_z)
				chunk.add_child(post)

				var reflector := MeshInstance3D.new()
				reflector.mesh = reflector_mesh
				reflector.position = Vector3(edge_x - side * 0.56, road_y + 1.05, sub_z)
				chunk.add_child(reflector)

			# Highway cobra-head streetlamp on each chunk.
			var pole := MeshInstance3D.new()
			pole.mesh = pole_mesh
			pole.position = Vector3(edge_x + side * 0.45, road_y + 4.6, 0.0)
			chunk.add_child(pole)

			var arm := MeshInstance3D.new()
			arm.mesh = arm_mesh
			arm.position = Vector3(edge_x - side * 1.2, road_y + 9.0, 0.0)
			chunk.add_child(arm)

			var lamp := MeshInstance3D.new()
			lamp.mesh = lamp_mesh
			lamp.position = Vector3(edge_x - side * 2.5, road_y + 8.85, 0.0)
			chunk.add_child(lamp)

			# Concrete support pier underneath the elevated highway.
			var pier := MeshInstance3D.new()
			pier.mesh = pier_mesh
			pier.position = Vector3(side * (road_half_width - 3.5), road_y - 13.0, 0.0)
			pier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(pier)

		# Every 3rd chunk gets a dramatic roadside cantilever highway sign (stays over shoulder, never blocks camera).
		if i % 3 == 0:
			var sign_side := 1.0 if (i % 6 == 0) else -1.0
			var sx := sign_side * (road_half_width + 1.4)
			var tower := MeshInstance3D.new()
			tower.mesh = sign_tower_mesh
			tower.position = Vector3(sx, road_y + 4.3, 6.0)
			chunk.add_child(tower)

			var s_arm := MeshInstance3D.new()
			s_arm.mesh = sign_arm_mesh
			s_arm.position = Vector3(sx - sign_side * 2.5, road_y + 7.8, 6.0)
			chunk.add_child(s_arm)

			var board := MeshInstance3D.new()
			board.mesh = sign_board_mesh
			board.position = Vector3(sx - sign_side * 3.1, road_y + 7.6, 6.0)
			chunk.add_child(board)

			# Two horizontal white text-bar stripes on the sign face.
			for row: float in [-0.35, 0.32]:
				var stripe := MeshInstance3D.new()
				stripe.mesh = sign_stripe_mesh
				stripe.position = Vector3(sx - sign_side * 3.1, road_y + 7.6 + row, 6.0)
				chunk.add_child(stripe)

		add_child(chunk)
		_road_chunks.append(chunk)


func _build_skyline_chunks() -> void:
	# Deterministic pseudo-random tower silhouettes flanking the elevated expressway.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42087

	for i in SKYLINE_COUNT:
		var row := Node3D.new()
		row.name = "SkylineRow_%d" % i
		row.position = Vector3(0.0, 0.0, SKYLINE_START_Z + i * SKYLINE_SPACING)

		for side: float in [-1.0, 1.0]:
			var width := rng.randf_range(10.0, 18.0)
			var depth := rng.randf_range(10.0, 16.0)
			var height := rng.randf_range(24.0, 56.0)
			var offset_x := side * rng.randf_range(38.0, 62.0)

			var tower_mesh := BoxMesh.new()
			tower_mesh.size = Vector3(width, height, depth)
			tower_mesh.material = _mat_tower_dark

			var tower := MeshInstance3D.new()
			tower.mesh = tower_mesh
			tower.position = Vector3(offset_x, road_y - 24.0 + height * 0.5, 0.0)
			tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			row.add_child(tower)

			# Glowing window accent bands facing the highway.
			var win_mat := _mat_window_warm if rng.randf() > 0.35 else _mat_window_cool
			var band_mesh := BoxMesh.new()
			band_mesh.size = Vector3(0.2, 0.55, depth * 0.72)
			band_mesh.material = win_mat

			var band_count := rng.randi_range(3, 6)
			for b in band_count:
				var band := MeshInstance3D.new()
				band.mesh = band_mesh
				var by := road_y - 10.0 + height * 0.32 + b * 2.8
				if by > road_y - 24.0 + height - 1.5:
					continue
				band.position = Vector3(offset_x - side * (width * 0.5 + 0.08), by, 0.0)
				band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				row.add_child(band)

		add_child(row)
		_skyline_chunks.append(row)


func _build_background_traffic() -> void:
	# Decorative non-colliding express cars rushing past on the lower side collector roads.
	var body_colors: Array[Color] = [
		Color(0.85, 0.22, 0.22),
		Color(0.22, 0.45, 0.85),
		Color(0.92, 0.76, 0.22),
		Color(0.78, 0.82, 0.88),
		Color(0.18, 0.68, 0.64),
	]
	var car_mesh := BoxMesh.new()
	car_mesh.size = Vector3(2.4, 1.25, 4.8)
	var light_mesh := BoxMesh.new()
	light_mesh.size = Vector3(0.45, 0.25, 0.15)

	for i in 8:
		var side := -1.0 if i < 4 else 1.0
		var car := Node3D.new()
		car.name = "BgCar_%d" % i

		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_colors[i % body_colors.size()]
		mat.metallic = 0.4
		mat.roughness = 0.35

		var body := MeshInstance3D.new()
		body.mesh = car_mesh
		body.material_override = mat
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(body)

		# Headlights (-Z) and taillights (+Z).
		for lx: float in [-0.75, 0.75]:
			var hl := MeshInstance3D.new()
			hl.mesh = light_mesh
			hl.material_override = _mat_headlight
			hl.position = Vector3(lx, -0.1, -2.42)
			car.add_child(hl)

			var tl := MeshInstance3D.new()
			tl.mesh = light_mesh
			tl.material_override = _mat_taillight
			tl.position = Vector3(lx, -0.1, 2.42)
			car.add_child(tl)

		# Left collector lane is oncoming (fast +Z); right collector lane is slower same-direction (+Z relative).
		var speed := 74.0 if side < 0.0 else 16.0
		if side < 0.0:
			car.rotation.y = PI
		car.position = Vector3(side * (road_half_width + 7.2), road_y - 1.65, -140.0 + (i % 4) * 58.0)
		add_child(car)
		_bg_cars.append({"node": car, "speed": speed})


func _build_wind_streaks() -> void:
	# Translucent wind / speed lines streaming past along +Z for tactile sense of velocity.
	var particles := GPUParticles3D.new()
	particles.name = "WindStreaks"
	particles.position = Vector3(0.0, 1.4, -75.0)
	particles.amount = 42
	particles.lifetime = 2.6
	particles.preprocess = 2.0
	particles.visibility_aabb = AABB(Vector3(-35, -8, -40), Vector3(70, 20, 190))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(24.0, 3.2, 25.0)
	proc.direction = Vector3(0.0, 0.0, 1.0)
	proc.spread = 0.5
	proc.initial_velocity_min = highway_speed * 1.15
	proc.initial_velocity_max = highway_speed * 1.45
	proc.gravity = Vector3.ZERO
	particles.process_material = proc

	var streak_mat := StandardMaterial3D.new()
	streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.24)

	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.05, 0.05, 5.2)
	streak_mesh.material = streak_mat
	particles.draw_pass_1 = streak_mesh

	add_child(particles)
	_wind_streaks = particles
