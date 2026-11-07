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
const BLINK_SCENE := preload("res://src/enemy/boss/katana_robot/katana_blink_vfx.tscn")
const SHIELD_SCRIPT := preload("res://src/enemy/shield/enemy_shield.gd")
const PULSE_RIFLE_ID := "pulse_rifle"
## Stunned, it slumps forward and its blade goes dark, with sparks off its frame.
const STUN_LEAN_DEG := 22.0
const STUN_DROP := 0.35
const STUN_EASE_SECONDS := 0.25
const STUN_SPARK_SECONDS := 0.45

## Telegraph alpha from the start of a wind-up to the strike.
const TELEGRAPH_ALPHA_START := 0.12
const TELEGRAPH_ALPHA_STRIKE := 0.5
## Lunge lane sampling along the deck, so it stops short of open space.
const DASH_PROBE_STEP := 0.5
const ENRAGED_BLADE_LIGHT := 2.5
const RAGE_BLADE_LIGHT := 5.0
const RAGE_BLADE_COLOR := Color(1.0, 0.25, 0.2)
const RAGE_PHASE := 3
## Random spots tried around the target before giving up on a blink.
const TELEPORT_ATTEMPTS := 24
## The blink pulls the model into a thin column of light, and springs it back out on landing.
const BLINK_SQUASH := Vector3(0.08, 1.7, 0.08)
const BLINK_OUT_SECONDS := 0.16
const BLINK_IN_SECONDS := 0.3

signal shield_broken

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

@export_group("Shield")
@export var shield_radius := 2.6
@export var shield_height := 2.1

@export_group("Rage blink")
## The blink lands this far from the target: inside the lunge range, so it lunges straight away.
@export var teleport_min_distance := 7.0
@export var teleport_max_distance := 9.5
## Never closer than this to any carrier, so it doesn't appear on top of one.
@export var teleport_min_player_distance := 6.0
## The camera sees less behind the carriers than ahead: limits how far toward the camera
## (+Z) from the target it can land, so it stays on screen.
@export var teleport_max_behind := 2.5

var _teleport_destination := Vector3.ZERO
var _blade_tween: Tween
var _blink_tween: Tween
var _robot_base_scale := Vector3.ONE
## True from the start of a blink until it lands.
var _is_blinked_out := false
var _shield: EnemyShield
var _stun_tween: Tween
var _stun_spark_timer: Timer
var _robot_base_position := Vector3.ZERO
var _robot_base_rotation := Vector3.ZERO

@onready var _enemy := get_parent() as EnemyLocal
@onready var _slash_hit_box: Area3D = _enemy.get_node("SlashHitBox")
@onready var _dash_hit_box: Area3D = _enemy.get_node("DashHitBox")
@onready var _slam_hit_box: Area3D = _enemy.get_node("SlamHitBox")
@onready var _slash_telegraph: MeshInstance3D = _enemy.get_node("VFX/SlashTelegraph")
@onready var _dash_lane: MeshInstance3D = _enemy.get_node("VFX/DashLane")
@onready var _slam_telegraph: MeshInstance3D = _enemy.get_node("VFX/SlamTelegraph")
@onready var _wave_fan: Node3D = _enemy.get_node("VFX/WaveFan")
@onready var _wave_muzzle: Marker3D = _enemy.get_node("WaveMuzzle")
@onready var _robot: Node3D = _enemy.get_node("Robot")
@onready var _blade_light: OmniLight3D = _enemy.get_node("Robot/Rig_Large/Skeleton3D/KatanaHand/Katana/BladeLight")
@onready var _telegraph_material: StandardMaterial3D = (_slash_telegraph.mesh as PrimitiveMesh).material


func _ready() -> void:
	_robot_base_scale = _robot.scale
	_robot_base_position = _robot.position
	_robot_base_rotation = _robot.rotation
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
	if move == &"teleport":
		_vanish()


func end_move() -> void:
	_slash_telegraph.visible = false
	_dash_lane.visible = false
	_slam_telegraph.visible = false
	_wave_fan.visible = false
	_reset_robot_after_blink()
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
		&"teleport":
			_reappear()
		&"shield":
			_raise_shield()


func end_strike(move: StringName) -> void:
	match move:
		&"slash":
			_set_hit_box_active(_slash_hit_box, false)
		&"dash":
			_set_hit_box_active(_dash_hit_box, false)
			ImpactFeedback.spawn_dust(_enemy.global_position, 1.0)
		&"waves":
			_set_hit_box_active(_slam_hit_box, false)


## Picks where the next blink lands: around `target`, on the deck, away from every carrier,
## on screen, and with a clear lane back to the target. False when no spot qualifies.
func plan_teleport(target: Node3D) -> bool:
	if target == null:
		return false
	for attempt in TELEPORT_ATTEMPTS:
		var candidate := _get_random_spot_around(target.global_position)
		if not _is_safe_teleport_spot(candidate, target.global_position):
			continue
		_teleport_destination = candidate
		return true
	return false


func _get_random_spot_around(center: Vector3) -> Vector3:
	var offset := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	offset *= randf_range(teleport_min_distance, teleport_max_distance)
	return Vector3(center.x + offset.x, _enemy.global_position.y, center.z + offset.z)


func _is_safe_teleport_spot(spot: Vector3, target_position: Vector3) -> bool:
	if spot.z - target_position.z > teleport_max_behind:
		return false
	if not can_dash_through(spot):
		return false
	if _is_near_a_player(spot):
		return false
	return _has_clear_lane(spot, target_position)


func _is_near_a_player(spot: Vector3) -> bool:
	for player in _get_living_players():
		var offset := player.global_position - spot
		if Vector2(offset.x, offset.z).length() < teleport_min_player_distance:
			return true
	return false


func _get_living_players() -> Array[PlayerLocal]:
	var players: Array[PlayerLocal] = []
	var players_node := _enemy._get_players_node()
	if players_node == null:
		return players
	for child in players_node.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		players.append(player)
	return players


## The lunge from `from` toward `to` stays on the deck the whole way.
func _has_clear_lane(from: Vector3, to: Vector3) -> bool:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := flat.length()
	var direction := flat.normalized()
	var travelled := DASH_PROBE_STEP
	while travelled < length:
		if not can_dash_through(from + direction * travelled):
			return false
		travelled += DASH_PROBE_STEP
	return true


## Squeezes into a column of light and bursts away, while light gathers where it will land.
func _vanish() -> void:
	_is_blinked_out = true
	_play_sound(SERVO_SOUND, 1.4, -2.0)
	_spawn_blink(_teleport_destination).play_gather()
	var tween := _restart_blink_tween()
	tween.tween_property(_robot, "scale", _robot_base_scale * BLINK_SQUASH, BLINK_OUT_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(_burst_away)


func _burst_away() -> void:
	_robot.visible = false
	_spawn_blink(_enemy.global_position).play_burst()
	ImpactFeedback.spawn_dust(_enemy.global_position, 0.6)
	CameraFeedback.add_trauma_shot()


## Lands on the planned spot already facing the target, so the lunge's lane reads at once,
## and springs out of the column of light.
func _reappear() -> void:
	_is_blinked_out = false
	_enemy.global_position = _teleport_destination
	_face_target_now()
	_play_sound(TAUNT_SOUND, 1.3, -4.0)
	_spawn_blink(_enemy.global_position).play_burst()
	ImpactFeedback.spawn_dust(_enemy.global_position, 0.8)
	_robot.scale = _robot_base_scale * BLINK_SQUASH
	_robot.visible = true
	var tween := _restart_blink_tween()
	tween.tween_property(_robot, "scale", _robot_base_scale, BLINK_IN_SECONDS) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _spawn_blink(at_position: Vector3) -> KatanaBlinkVfx:
	var vfx := BLINK_SCENE.instantiate() as KatanaBlinkVfx
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = at_position
	return vfx


func _restart_blink_tween() -> Tween:
	if _blink_tween != null:
		_blink_tween.kill()
	_blink_tween = _robot.create_tween()
	return _blink_tween


## A move that ends mid-blink (death, say) must not leave the model hidden or squashed.
## The landing spring is left to finish: it plays on into the lunge's wind-up.
func _reset_robot_after_blink() -> void:
	if not _is_blinked_out:
		return
	_is_blinked_out = false
	if _blink_tween != null:
		_blink_tween.kill()
	_robot.scale = _robot_base_scale
	_robot.visible = true


func _face_target_now() -> void:
	if not is_instance_valid(_enemy.target_player):
		return
	var to_target := _enemy.target_player.global_position - _enemy.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() < 0.0001:
		return
	_enemy.global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)


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


## The shield needs the pulse rifle: nothing else can break it.
func can_raise_shield() -> bool:
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		return false
	return world.get_active_weapon_id() == PULSE_RIFLE_ID


func is_shield_up() -> bool:
	return is_instance_valid(_shield) and _shield.is_up()


## Raises a shield that stays up while it fights on, until a vent breaks it.
func _raise_shield() -> void:
	_shield = SHIELD_SCRIPT.new() as EnemyShield
	_shield.radius = shield_radius
	_shield.height = shield_height
	_shield.forces_vent_prompt = true
	_shield.shattered.connect(_on_shield_shattered)
	_enemy.add_child(_shield)
	_play_sound(TAUNT_SOUND, 0.7, 0.0)
	_play_sound(SERVO_SOUND, 0.6, -2.0)
	CameraFeedback.add_trauma_shot()


## A vent broke the shield: it reels, whatever it was in the middle of.
func _on_shield_shattered() -> void:
	shield_broken.emit()
	if not _enemy.is_alive():
		return
	_enemy.enemy_state_machine.transition_to("stunned")


## Slumps forward with its blade dark, throwing sparks, until `end_stun`.
func begin_stun() -> void:
	_play_sound(TAUNT_SOUND, 0.45, 0.0)
	_spawn(SPARKS_SCENE, _enemy.global_position + Vector3.UP * 2.5)
	CameraFeedback.add_trauma_shot()
	var tween := _restart_stun_tween().set_parallel()
	tween.tween_property(_robot, "rotation:x", _robot_base_rotation.x + deg_to_rad(STUN_LEAN_DEG), STUN_EASE_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_robot, "position:y", _robot_base_position.y - STUN_DROP, STUN_EASE_SECONDS)
	tween.tween_property(_blade_light, "light_energy", 0.0, STUN_EASE_SECONDS)
	_stun_spark_timer = Timer.new()
	_stun_spark_timer.wait_time = STUN_SPARK_SECONDS
	_stun_spark_timer.timeout.connect(func(): _spawn(SPARKS_SCENE, _enemy.global_position + Vector3.UP * randf_range(1.5, 3.0)))
	add_child(_stun_spark_timer)
	_stun_spark_timer.start()


func end_stun() -> void:
	if is_instance_valid(_stun_spark_timer):
		_stun_spark_timer.queue_free()
	var tween := _restart_stun_tween().set_parallel()
	tween.tween_property(_robot, "rotation:x", _robot_base_rotation.x, STUN_EASE_SECONDS)
	tween.tween_property(_robot, "position:y", _robot_base_position.y, STUN_EASE_SECONDS)
	tween.tween_property(_blade_light, "light_energy", _get_phase_blade_light(), STUN_EASE_SECONDS)
	_play_sound(SERVO_SOUND, 1.1, -4.0)


## The blade's glow for the phase it is in now: a big hit while stunned can start the rage.
func _get_phase_blade_light() -> float:
	var phase_controller := BossPhaseController.from_enemy(_enemy)
	if phase_controller != null and phase_controller.is_phase_at_least(RAGE_PHASE):
		return RAGE_BLADE_LIGHT
	return ENRAGED_BLADE_LIGHT


func _restart_stun_tween() -> Tween:
	if _stun_tween != null:
		_stun_tween.kill()
	_stun_tween = _robot.create_tween()
	return _stun_tween


func _on_phase_changed(phase_index: int) -> void:
	if phase_index >= RAGE_PHASE:
		_start_rage_visuals()
		return
	if phase_index < 2:
		return
	var tween := _restart_blade_tween()
	tween.tween_property(_blade_light, "light_energy", ENRAGED_BLADE_LIGHT, 0.6)


func _start_rage_visuals() -> void:
	var tween := _restart_blade_tween().set_parallel()
	tween.tween_property(_blade_light, "light_energy", RAGE_BLADE_LIGHT, 0.6)
	tween.tween_property(_blade_light, "light_color", RAGE_BLADE_COLOR, 0.6)


## A big hit can cross both thresholds at once: the rage glow replaces the enraged one.
func _restart_blade_tween() -> Tween:
	if _blade_tween != null:
		_blade_tween.kill()
	_blade_tween = _blade_light.create_tween()
	return _blade_tween


func _on_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	end_move()
	if is_shield_up():
		_shield.dissolve()
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
