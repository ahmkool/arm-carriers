class_name KatanaRobotMoves
extends Node
## What 4GTN's moves look and feel like: floor telegraphs, hitboxes, the lunge's lane, the
## plasma waves and the feedback. KatanaRobotAttacking decides when each beat happens.

const SLASH_SOUND := preload("res://assets/sounds/slash_1.wav")
const LUNGE_SOUND := preload("res://assets/sounds/slash_3.wav")
const SERVO_SOUND := preload("res://assets/sounds/cogs/807842__sabacky__complex-mechanism-short.wav")
const TAUNT_SOUND := preload("res://assets/sounds/cogs/807844__sabacky__complex-mechanism-long.wav")
const SLAM_SOUND := preload("res://assets/sounds/explosion/Medium Explosion 4_1.wav")
const WAVE_SOUND := preload("res://assets/sounds/fireball_cast.wav")
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")

## Telegraph alpha from the start of a wind-up to the strike.
const TELEGRAPH_ALPHA_START := 0.12
const TELEGRAPH_ALPHA_STRIKE := 0.5
## Lunge lane sampling along the deck, so it stops short of open space.
const DASH_PROBE_STEP := 0.5
const ENRAGED_BLADE_LIGHT := 2.5

@export_group("Lunge")
@export var dash_min_length := 5.0
@export var dash_max_length := 14.0
## How far past the target the lunge carries, so stepping back isn't enough to dodge it.
@export var dash_overshoot := 3.0

@export_group("Plasma waves")
@export var wave_scene: PackedScene
@export var wave_count := 5
@export var wave_spread_deg := 70.0
@export var wave_speed := 8.0
@export var wave_lifetime := 3.0
@export var wave_damage := 1
@export var wave_lane_length := 7.0

@onready var _enemy := get_parent() as EnemyLocal
@onready var _slash_hit_box: Area3D = _enemy.get_node("SlashHitBox")
@onready var _dash_hit_box: Area3D = _enemy.get_node("DashHitBox")
@onready var _slam_hit_box: Area3D = _enemy.get_node("SlamHitBox")
@onready var _slash_telegraph: MeshInstance3D = _enemy.get_node("VFX/SlashTelegraph")
@onready var _dash_lane: MeshInstance3D = _enemy.get_node("VFX/DashLane")
@onready var _slam_telegraph: MeshInstance3D = _enemy.get_node("VFX/SlamTelegraph")
@onready var _wave_fan: Node3D = _enemy.get_node("VFX/WaveFan")
@onready var _wave_muzzle: Marker3D = _enemy.get_node("WaveMuzzle")
@onready var _blade_light: OmniLight3D = _enemy.get_node("Robot/Rig_Large/Skeleton3D/KatanaHand/Katana/BladeLight")
@onready var _telegraph_material: StandardMaterial3D = (_slash_telegraph.mesh as PrimitiveMesh).material


func _ready() -> void:
	_build_wave_fan()
	end_move()
	# The boss's own @onready vars aren't set yet: children are ready before their parent.
	Health.from_target(_enemy).died.connect(_on_died)
	var phase_controller := BossPhaseController.from_enemy(_enemy)
	if phase_controller == null:
		return
	phase_controller.phase_changed.connect(_on_phase_changed)


func begin_move(move: StringName) -> void:
	set_telegraph_progress(0.0)
	_slash_telegraph.visible = move == &"slash"
	_dash_lane.visible = move == &"dash"
	_slam_telegraph.visible = move == &"waves"
	_wave_fan.visible = move == &"waves"
	if move == &"dash" or move == &"waves":
		_play_sound(SERVO_SOUND, 0.8, -4.0)


func end_move() -> void:
	_slash_telegraph.visible = false
	_dash_lane.visible = false
	_slam_telegraph.visible = false
	_wave_fan.visible = false
	_set_hit_box_active(_slash_hit_box, false)
	_set_hit_box_active(_dash_hit_box, false)
	_set_hit_box_active(_slam_hit_box, false)


func set_telegraph_progress(progress: float) -> void:
	var color := _telegraph_material.albedo_color
	color.a = lerpf(TELEGRAPH_ALPHA_START, TELEGRAPH_ALPHA_STRIKE, progress * progress)
	_telegraph_material.albedo_color = color


## How far a lunge along `direction` goes: past the target, but never off the deck.
func measure_dash(direction: Vector3, target_distance: float) -> float:
	var wanted := clampf(target_distance + dash_overshoot, dash_min_length, dash_max_length)
	var length := 0.0
	while length + DASH_PROBE_STEP <= wanted:
		if not can_dash_through(_enemy.global_position + direction * (length + DASH_PROBE_STEP)):
			return length
		length += DASH_PROBE_STEP
	return length


func can_dash_through(world_position: Vector3) -> bool:
	return _enemy._is_on_navmesh(world_position)


## The lane runs from the boss's feet to where the lunge will stop.
func show_dash_lane(length: float) -> void:
	_dash_lane.scale.z = maxf(length, 0.01)
	_dash_lane.position.z = -length * 0.5


func strike(move: StringName) -> void:
	_slash_telegraph.visible = false
	_dash_lane.visible = false
	_slam_telegraph.visible = false
	_wave_fan.visible = false
	match move:
		&"taunt":
			_taunt_burst()
		&"slash":
			_set_hit_box_active(_slash_hit_box, true)
			_play_sound(SLASH_SOUND, randf_range(0.6, 0.7), 0.0)
		&"dash":
			_set_hit_box_active(_dash_hit_box, true)
			_play_sound(LUNGE_SOUND, 0.55, 2.0)
			CameraFeedback.add_trauma_dash()
		&"waves":
			_slam()


func end_strike(move: StringName) -> void:
	match move:
		&"slash":
			_set_hit_box_active(_slash_hit_box, false)
		&"dash":
			_set_hit_box_active(_dash_hit_box, false)
			ImpactFeedback.spawn_dust(_enemy.global_position, 1.0)
		&"waves":
			_set_hit_box_active(_slam_hit_box, false)


func _set_hit_box_active(hit_box: Area3D, active: bool) -> void:
	hit_box.set_deferred("monitoring", active)


func _taunt_burst() -> void:
	_play_sound(TAUNT_SOUND, 0.9, -2.0)
	_spawn(SPARKS_SCENE, _blade_light.global_position)
	CameraFeedback.add_trauma_shot()


func _slam() -> void:
	_set_hit_box_active(_slam_hit_box, true)
	_play_sound(SLAM_SOUND, 1.1, -2.0)
	_spawn(POP_SCENE, _slam_telegraph.global_position)
	ImpactFeedback.spawn_dust(_slam_telegraph.global_position, 1.0)
	ImpactFeedback.play_explosion()
	_fire_waves()


func _fire_waves() -> void:
	if wave_scene == null:
		return
	_play_sound(WAVE_SOUND, 0.8, 0.0)
	for direction in _get_wave_directions():
		var wave := wave_scene.instantiate() as Fireball
		wave.damage = wave_damage
		wave.lifetime_seconds = wave_lifetime
		get_tree().current_scene.add_child(wave)
		wave.global_position = _wave_muzzle.global_position
		wave.launch(direction * wave_speed)


func _get_wave_directions() -> Array[Vector3]:
	var forward := -_enemy.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var directions: Array[Vector3] = []
	for angle in _get_wave_angles():
		directions.append(forward.rotated(Vector3.UP, angle))
	return directions


func _get_wave_angles() -> Array[float]:
	var angles: Array[float] = []
	var spread := deg_to_rad(wave_spread_deg)
	for index in wave_count:
		var t := 0.5 if wave_count == 1 else float(index) / float(wave_count - 1)
		angles.append(lerpf(-spread * 0.5, spread * 0.5, t))
	return angles


## One lane per wave, each a copy of the template strip, fanned out from the muzzle.
func _build_wave_fan() -> void:
	var template := _wave_fan.get_node("Lane") as MeshInstance3D
	_wave_fan.position = Vector3(_wave_muzzle.position.x, _wave_fan.position.y, _wave_muzzle.position.z)
	for angle in _get_wave_angles():
		var pivot := Node3D.new()
		pivot.rotation.y = angle
		_wave_fan.add_child(pivot)
		var lane := template.duplicate() as MeshInstance3D
		lane.visible = true
		lane.scale.z = wave_lane_length
		lane.position.z = -wave_lane_length * 0.5
		pivot.add_child(lane)
	template.visible = false


func _on_phase_changed(phase_index: int) -> void:
	if phase_index < 2:
		return
	var tween := _blade_light.create_tween()
	tween.tween_property(_blade_light, "light_energy", ENRAGED_BLADE_LIGHT, 0.6)


func _on_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	end_move()
	_blade_light.light_energy = 0.0


func _spawn(scene: PackedScene, at_position: Vector3) -> void:
	var effect := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(effect)
	effect.global_position = at_position
	var particles := effect as GPUParticles3D
	if particles == null:
		return
	particles.emitting = true


func _play_sound(stream: AudioStream, pitch: float, volume_db: float) -> void:
	ImpactFeedback.play_sfx(stream, _enemy.global_position + Vector3.UP * 2.0, pitch, volume_db)
