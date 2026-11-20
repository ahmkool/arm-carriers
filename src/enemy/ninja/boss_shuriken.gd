class_name BossShuriken
extends Node3D
## One of the Shuriken Master's two giant throwing stars. It spins the whole time and is always in one of four
## modes:
## - ORBITING: circling its master at `ORBIT_RADIUS`, opposite the other star.
## - THROWN: flying flat to the spot it was thrown at.
## - DRIFTING: lingering there, wandering slowly after the nearer carrier, until its master pulls it back.
## - RETURNING: flying back to its place in the orbit, cutting through anything on the way.
## A carrier it touches takes `DAMAGE`. It carries a `BoltMirror`, so the carriers' shots glance off it: pulse
## bolts bounce, and the shuriken launcher's star and kunai are knocked off course (see `Shuriken`, `Kunai`).
## It lives in the scene, not under its master, so it doesn't turn when he does; he frees it when he goes.

enum Mode { ORBITING, THROWN, DRIFTING, RETURNING }

const MODEL := preload("res://assets/models/weapon/enemies/ninja/Ninja_Shuriken.gltf")
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")
const HIT_SOUND := preload("res://assets/sounds/damage/sword_hit.wav")
const WHOOSH := preload("res://assets/sounds/slash_2.wav")

## The KayKit shuriken is 0.44 m across; this makes it about 2 m.
const MODEL_SCALE := 4.5
const SPIN_HZ := 3.0
const HEIGHT := 1.1
const ORBIT_RADIUS := 2.4
## Radians per second round its master.
const ORBIT_SPEED := 1.8
const THROW_SPEED := 10.0
const RETURN_SPEED := 13.0
## How fast a drifting star creeps after the nearer carrier, and the small loop it turns as it goes.
const DRIFT_SPEED := 1.0
const DRIFT_LOOP_RADIUS := 1.2
const DRIFT_LOOP_SPEED := 1.4
const DAMAGE := 1
## A carrier it just cut can't be cut again for this long.
const HIT_COOLDOWN_SEC := 0.8
const HIT_RADIUS := 1.0
const ARRIVE_DISTANCE := 0.3
## Players (layer 1).
const PLAYER_LAYER := 1

var master: EnemyLocal
var mode := Mode.ORBITING
var orbit_angle := 0.0
var _target := Vector3.ZERO
var _drift_centre := Vector3.ZERO
var _drift_angle := 0.0
var _drift_sec := 0.0
var _spinner: Node3D
var _hit_cooldowns := {}


func _ready() -> void:
	add_to_group(Checkpoint.ENEMY_PROJECTILE_GROUP)
	_spinner = Node3D.new()
	add_child(_spinner)
	var model := MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * MODEL_SCALE
	_spinner.add_child(model)
	add_child(_make_glow())
	add_child(_make_hurt_area())
	var mirror := BoltMirror.create(_sphere(HIT_RADIUS))
	mirror.deflected.connect(_on_deflected)
	add_child(mirror)


func is_out() -> bool:
	return mode == Mode.THROWN or mode == Mode.DRIFTING


func is_drifting() -> bool:
	return mode == Mode.DRIFTING


## How long it has been drifting.
func drift_seconds() -> float:
	return _drift_sec if mode == Mode.DRIFTING else 0.0


## Sends it flat at `target`; it lingers there once it arrives.
func throw_at(target: Vector3) -> void:
	_target = Vector3(target.x, _floor_y() + HEIGHT, target.z)
	mode = Mode.THROWN
	ImpactFeedback.play_sfx(WHOOSH, global_position, randf_range(0.7, 0.8), -2.0)


## Calls it back to its place in the orbit.
func pull_back() -> void:
	if not is_out():
		return
	mode = Mode.RETURNING
	ImpactFeedback.play_sfx(WHOOSH, global_position, randf_range(0.9, 1.0), -2.0)


## Leaves it drifting at `at`, as when its master swaps places with it.
func drift_from(at: Vector3) -> void:
	global_position = Vector3(at.x, _floor_y() + HEIGHT, at.z)
	_start_drift()


func _physics_process(delta: float) -> void:
	_spinner.rotation.y = wrapf(_spinner.rotation.y + SPIN_HZ * TAU * delta, 0.0, TAU)
	_tick_hit_cooldowns(delta)
	if not is_instance_valid(master):
		return
	match mode:
		Mode.ORBITING:
			global_position = _orbit_point()
		Mode.THROWN:
			_fly_to(_target, THROW_SPEED, delta, _start_drift)
		Mode.DRIFTING:
			_drift(delta)
		Mode.RETURNING:
			_fly_to(_orbit_point(), RETURN_SPEED, delta, _start_orbit)


## Its place in the orbit; the orbit turns whether or not it is there.
func _orbit_point() -> Vector3:
	orbit_angle = wrapf(orbit_angle + ORBIT_SPEED * get_physics_process_delta_time(), 0.0, TAU)
	var offset := Vector3(cos(orbit_angle), 0.0, sin(orbit_angle)) * ORBIT_RADIUS
	return master.global_position + offset + Vector3.UP * HEIGHT


func _fly_to(point: Vector3, speed: float, delta: float, on_arrive: Callable) -> void:
	var offset := point - global_position
	var step := speed * delta
	if offset.length() <= maxf(step, ARRIVE_DISTANCE):
		global_position = point
		on_arrive.call()
		return
	global_position += offset.normalized() * step


func _start_drift() -> void:
	mode = Mode.DRIFTING
	_drift_sec = 0.0
	_drift_centre = global_position
	_drift_angle = randf() * TAU


func _start_orbit() -> void:
	mode = Mode.ORBITING


## A slow loop round a centre that creeps after the nearer carrier.
func _drift(delta: float) -> void:
	_drift_sec += delta
	var prey := _nearest_carrier()
	if prey != null:
		var to_prey := prey.global_position - _drift_centre
		to_prey.y = 0.0
		_drift_centre += to_prey.limit_length(DRIFT_SPEED * delta)
	_drift_angle = wrapf(_drift_angle + DRIFT_LOOP_SPEED * delta, 0.0, TAU)
	var loop := Vector3(cos(_drift_angle), 0.0, sin(_drift_angle)) * DRIFT_LOOP_RADIUS
	global_position = Vector3(_drift_centre.x + loop.x, _floor_y() + HEIGHT, _drift_centre.z + loop.z)


func _nearest_carrier() -> PlayerLocal:
	var nearest: PlayerLocal = null
	var best := INF
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return null
	for node in players.get_children():
		var player := node as PlayerLocal
		if player == null or player.is_dead:
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best:
			best = distance
			nearest = player
	if nearest != null:
		return nearest
	if is_instance_valid(master) and is_instance_valid(master.target_player):
		return master.target_player
	return null


func _floor_y() -> float:
	if is_instance_valid(master):
		return master.global_position.y
	return global_position.y - HEIGHT


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerLocal
	if player == null or player.is_dead:
		return
	if _hit_cooldowns.has(player):
		return
	_hit_cooldowns[player] = HIT_COOLDOWN_SEC
	if not Health.apply_damage(player, DAMAGE, global_position):
		return
	ImpactFeedback.play_sfx(HIT_SOUND, player.global_position, randf_range(0.8, 0.9), 0.0)
	CameraFeedback.add_trauma_hurt()


func _tick_hit_cooldowns(delta: float) -> void:
	for player in _hit_cooldowns.keys():
		_hit_cooldowns[player] -= delta
		if _hit_cooldowns[player] <= 0.0:
			_hit_cooldowns.erase(player)


func _on_deflected(point: Vector3) -> void:
	ShotCover.play_hit(get_tree(), point, 0.4)


## Spawns the puff it leaves when its master falls, then goes.
func vanish() -> void:
	var pop := POP_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(pop)
	pop.global_position = global_position
	queue_free()


func _make_hurt_area() -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = PLAYER_LAYER
	var collision := CollisionShape3D.new()
	collision.shape = _sphere(HIT_RADIUS)
	area.add_child(collision)
	area.body_entered.connect(_on_body_entered)
	return area


## A dim red light, so it reads on the night rooftops.
func _make_glow() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.25)
	light.light_energy = 1.2
	light.omni_range = 3.0
	return light


func _sphere(radius: float) -> SphereShape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return shape
