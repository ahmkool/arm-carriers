class_name GunshipMoves
extends Node
## What the gunship's moves do to the world. The behavior picks a move, the attacking state times it, and this node
## fires the bolts, launches the rockets and runs the laser beam.
##
## The laser is the fight's big threat: a beam straight across the arena along the gunship's facing, as wide as
## `laser_half_width` either side, that hurts any carrier inside it. Its hit test is flat, so props and height don't
## shelter anyone: the only way out is sideways.

const CHARGE_SOUND := preload("res://assets/sounds/fireball_cast.wav")
const BEAM_SOUND := preload("res://assets/sounds/bazooka_shot.wav")
const GUN_SOUND := preload("res://assets/sounds/gun/Gun 6-2.wav")
## Gatlings first alternate left and right; rockets go left, right, left, right from the two tubes of each pod.
const GUN_ORDER: Array[String] = ["L", "R"]
const ROCKET_ORDER: Array[String] = ["L_0", "R_0", "L_1", "R_1"]

@export var bolt_spawn_scene: PackedScene
@export var rocket_scene: PackedScene
@export_group("Guns")
@export var bolt_speed := 12.0
@export var bolt_damage := 1
## Height on the target the bolts aim at.
@export var bolt_aim_height := 0.9
## Random scatter of each bolt's aim point, in metres.
@export var bolt_scatter := 0.6
@export var barrel_spin_turns_per_second := 5.0
@export_group("Rockets")
@export var rocket_flight_seconds := 1.3
## Rockets beyond one per carrier land this far off a carrier, in a random direction.
@export var rocket_spread := 3.5
## How far ahead of a moving carrier a rocket is aimed, as a share of where they'd be when it lands.
@export var rocket_lead := 0.5
@export var rocket_reload_seconds := 2.5
@export_group("Laser")
@export var laser_length := 45.0
@export var laser_half_width := 0.8
## Added to the beam's half width for a carrier's body.
@export var carrier_radius := 0.35
@export var laser_damage := 3

var _spin := 0.0
var _beam_scale := 0.0
var _beam_started := false

@onready var _enemy: EnemyLocal = get_parent() as EnemyLocal
@onready var _model: Node3D = _enemy.get_node("Visual/Model") as Node3D
@onready var _beam: Node3D = _enemy.get_node("LaserBeam") as Node3D
@onready var _beam_core: Node3D = _enemy.get_node("LaserBeam/Core") as Node3D
@onready var _aim_line: Node3D = _enemy.get_node("LaserBeam/AimLine") as Node3D
@onready var _charge_light: OmniLight3D = _enemy.get_node("LaserBeam/ChargeLight") as OmniLight3D
@onready var _laser_muzzle: Node3D = _model.find_child("Muzzle_Laser", true, false) as Node3D


func _ready() -> void:
	_hide_laser()
	var health := Health.from_target(_enemy)
	if health != null:
		health.died.connect(_on_died)
	var phases := BossPhaseController.from_enemy(_enemy)
	if phases != null:
		phases.phase_changed.connect(_on_phase_changed)


func begin_move(move: StringName) -> void:
	_beam_started = false
	_beam_scale = 0.0
	if move != AviatorGunshipBehavior.MOVE_LASER:
		return
	_play_sound(CHARGE_SOUND, 0.6, 2.0)


func end_move() -> void:
	_hide_laser()


# ---- Guns. ----

func spin_guns(on: bool, delta: float) -> void:
	var wanted := barrel_spin_turns_per_second if on else 0.0
	_spin = move_toward(_spin, wanted, barrel_spin_turns_per_second * 2.0 * delta)
	for side in GUN_ORDER:
		var barrels := _model.find_child("GunBarrels_" + side, true, false) as Node3D
		if barrels == null:
			continue
		barrels.rotate_object_local(Vector3.BACK, TAU * _spin * delta)


func fire_gun(index: int) -> void:
	var muzzle := _model.find_child("Muzzle_Gun_" + GUN_ORDER[index % GUN_ORDER.size()], true, false) as Node3D
	if muzzle == null or bolt_spawn_scene == null:
		return
	if not is_instance_valid(_enemy.target_player):
		return
	var aim := _enemy.target_player.global_position + Vector3.UP * bolt_aim_height + _scatter(bolt_scatter)
	var spawn := bolt_spawn_scene.instantiate() as FireballSpawn
	spawn.setup((aim - muzzle.global_position).normalized() * bolt_speed, bolt_damage)
	get_tree().current_scene.add_child(spawn)
	spawn.global_position = muzzle.global_position
	_play_sound(GUN_SOUND, randf_range(0.9, 1.1), -6.0)


# ---- Rockets. ----

func launch_rocket(index: int) -> void:
	var tube := ROCKET_ORDER[index % ROCKET_ORDER.size()]
	var muzzle := _model.find_child("Muzzle_Rocket_" + tube, true, false) as Node3D
	if muzzle == null or rocket_scene == null:
		return
	var target: Variant = _rocket_target(index)
	if target == null:
		return
	var rocket := rocket_scene.instantiate() as GunshipRocket
	rocket.add_to_group(Checkpoint.ENEMY_PROJECTILE_GROUP)
	var behavior := _enemy.behavior as AviatorGunshipBehavior
	rocket.breaks_floor = behavior != null and behavior.phase() >= AviatorGunshipBehavior.PHASE_STRAFE
	get_tree().current_scene.add_child(rocket)
	rocket.launch(muzzle.global_position, target as Vector3, rocket_flight_seconds)
	_hide_pod_rocket(tube)


## One rocket per living carrier, aimed a little ahead of them; any left over land near a carrier.
func _rocket_target(index: int) -> Variant:
	var players := _get_living_players()
	if players.is_empty():
		return null
	var player := players[index % players.size()]
	var flat_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var point := player.global_position + flat_velocity * rocket_flight_seconds * rocket_lead
	if index < players.size():
		return point
	var direction := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	return point + direction * rocket_spread


## The pod's own rocket leaves with the shot and is back once the tube has reloaded.
func _hide_pod_rocket(tube: String) -> void:
	var mesh := _model.find_child("Rocket_" + tube, true, false) as Node3D
	if mesh == null:
		return
	mesh.visible = false
	get_tree().create_timer(rocket_reload_seconds).timeout.connect(func(): if is_instance_valid(mesh): mesh.visible = true)


# ---- Laser. ----

## progress: 0 to 1 over the charge. The aim line shows the beam's path and pulses faster as it fills.
func charge_laser(progress: float) -> void:
	_place_beam()
	_beam.visible = true
	_aim_line.visible = true
	_beam_core.visible = false
	_charge_light.light_energy = lerpf(0.5, 6.0, progress)
	_aim_line.scale = Vector3.ONE * (0.6 + 0.4 * absf(sin(progress * progress * 40.0)))


func fire_laser(delta: float) -> void:
	_place_beam()
	_start_beam()
	_beam_scale = move_toward(_beam_scale, 1.0, delta * 6.0)
	var flicker := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.05)
	_beam_core.scale = Vector3(_beam_scale * flicker, _beam_scale * flicker, 1.0)
	_hurt_carriers_in_beam()


func stop_laser() -> void:
	_hide_laser()


func is_laser_firing() -> bool:
	return _beam_core.visible


## The beam's start and flat direction, for tests and the hit check.
func beam_origin() -> Vector3:
	return _laser_muzzle.global_position


func beam_direction() -> Vector3:
	var forward := -_enemy.global_basis.z
	return Vector3(forward.x, 0.0, forward.z).normalized()


func is_in_beam(point: Vector3) -> bool:
	var offset := point - beam_origin()
	var flat := Vector3(offset.x, 0.0, offset.z)
	var along := flat.dot(beam_direction())
	if along < 0.0 or along > laser_length:
		return false
	var across := (flat - beam_direction() * along).length()
	return across <= laser_half_width + carrier_radius


func _start_beam() -> void:
	if _beam_started:
		return
	_beam_started = true
	_aim_line.visible = false
	_beam_core.visible = true
	_charge_light.light_energy = 8.0
	CameraFeedback.add_trauma_explosion()
	_play_sound(BEAM_SOUND, 0.55, 2.0)


func _place_beam() -> void:
	_beam.global_transform = Transform3D(Basis.looking_at(beam_direction(), Vector3.UP), beam_origin())


func _hurt_carriers_in_beam() -> void:
	for player in _get_living_players():
		if not is_in_beam(player.global_position):
			continue
		if Health.apply_damage(player, laser_damage, beam_origin()):
			CameraFeedback.add_trauma_hurt()


func _hide_laser() -> void:
	if _beam == null:
		return
	_beam.visible = false
	_aim_line.visible = false
	_beam_core.visible = false
	_charge_light.light_energy = 0.0


# ---- Events. ----

func _on_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	_hide_laser()


func _on_phase_changed(phase_index: int) -> void:
	if phase_index < 2:
		return
	ImpactFeedback.play_boss_moment()
	CameraFeedback.add_trauma_boss_moment()


# ---- Helpers. ----

func _scatter(amount: float) -> Vector3:
	return Vector3(randf_range(-amount, amount), randf_range(-amount, amount) * 0.5, randf_range(-amount, amount))


func _get_living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var players := _enemy._get_players_node()
	if players == null:
		return living
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		living.append(player)
	return living


func _play_sound(stream: AudioStream, pitch: float, volume_db: float) -> void:
	var sfx := AudioStreamPlayer3D.new()
	_enemy.add_child(sfx)
	sfx.bus = "SFX"
	sfx.stream = stream
	sfx.pitch_scale = pitch
	sfx.volume_db = volume_db
	sfx.max_distance = 60.0
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
