class_name NecromancerSpells
extends Node
## What the necromancer's moves do to the world. The behavior picks a move and the attacking state
## times it; this node owns the effects and the minions, which die with the boss.

const CAST_SOUND := preload("res://assets/sounds/fireball_cast.wav")
const PUFF_SCENE := preload("res://src/vfx/puff_disappear.tscn")
const BLINK_CANDIDATES := 10
const MINION_RING_RADIUS := 3.5
const MINION_MIN_PLAYER_DISTANCE := 3.0
const MINION_RING_TRIES := 8

@export var bolt_scene: PackedScene
@export var grave_scene: PackedScene
@export var minion_spawner_scene: PackedScene
@export var bolt_speed := 6.5
@export var volley_spread_degrees := 18.0
## How far from the boss's starting spot a blink can land. Keep it inside the arena.
@export var blink_radius := 11.0

@onready var _enemy: EnemyLocal = get_parent() as EnemyLocal
@onready var _model: Node3D = _enemy.get_node("Necromancer") as Node3D
@onready var _muzzle: Marker3D = _enemy.get_node("BoltMuzzle") as Marker3D
@onready var _cast_embers: GPUParticles3D = _enemy.get_node("CastEmbers") as GPUParticles3D
@onready var _swing_hit_box: Area3D = _enemy.get_node("SwingHitBox") as Area3D
@onready var _swing_telegraph: MeshInstance3D = _enemy.get_node("SwingTelegraph") as MeshInstance3D

var _home := Vector3.ZERO
var _minions_parent: Node3D


func _ready() -> void:
	_home = _enemy.global_position
	var health := Health.from_target(_enemy)
	if health == null:
		return
	health.died.connect(_on_died)


func _exit_tree() -> void:
	if not is_instance_valid(_minions_parent):
		return
	_minions_parent.queue_free()


func begin_move(move: StringName) -> void:
	_cast_embers.emitting = move != &"swing" and move != &"blink"
	_swing_telegraph.visible = move == &"swing"


func end_move() -> void:
	_cast_embers.emitting = false
	_swing_telegraph.visible = false
	_model.visible = true
	set_swing_active(false)


func fire_volley(bolts: int) -> void:
	if bolt_scene == null:
		return
	var aim := _get_flat_aim()
	var first_angle := -deg_to_rad(volley_spread_degrees) * (bolts - 1) * 0.5
	for index in bolts:
		var angle := first_angle + deg_to_rad(volley_spread_degrees) * index
		_fire_bolt(aim.rotated(Vector3.UP, angle))
	_play_sound(CAST_SOUND)


func summon_minions(count: int) -> void:
	if minion_spawner_scene == null:
		return
	for index in count:
		var angle := TAU * index / maxi(count, 1) + randf() * 0.5
		_spawn_minion(_pick_minion_point(angle))
	_play_sound(CAST_SOUND)


func erupt_graves() -> void:
	if grave_scene == null:
		return
	for player in _get_living_players():
		_spawn_grave(player.global_position)
	_play_sound(CAST_SOUND)


func set_swing_active(active: bool) -> void:
	_swing_hit_box.set_deferred("monitoring", active)


func blink_out() -> void:
	_spawn_puff()
	_model.visible = false
	_enemy.global_position = _pick_blink_point()


func blink_in() -> void:
	_model.visible = true
	_spawn_puff()


func taunt_burst() -> void:
	ImpactFeedback.play_boss_moment()


func count_minions() -> int:
	if not is_instance_valid(_minions_parent):
		return 0
	var total := 0
	for child in _minions_parent.get_children():
		if _counts_as_minion(child):
			total += 1
	return total


func _counts_as_minion(node: Node) -> bool:
	if node is EnemySpawner:
		return true
	if node is EnemyLocal:
		return (node as EnemyLocal).is_alive()
	return false


func _on_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	end_move()
	if not is_instance_valid(_minions_parent):
		return
	for child in _minions_parent.get_children():
		_end_minion(child)


func _end_minion(node: Node) -> void:
	if node is EnemySpawner:
		node.queue_free()
		return
	var minion := node as EnemyLocal
	if minion == null:
		return
	minion.die(_enemy.global_position)


func _get_flat_aim() -> Vector3:
	var forward := -_enemy.global_basis.z
	if not is_instance_valid(_enemy.target_player):
		return Vector3(forward.x, 0.0, forward.z).normalized()
	var to_target := _enemy.target_player.global_position - _muzzle.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() < 0.0001:
		return Vector3(forward.x, 0.0, forward.z).normalized()
	return flat.normalized()


func _fire_bolt(direction: Vector3) -> void:
	var bolt := bolt_scene.instantiate() as Fireball
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = _muzzle.global_position
	bolt.launch(direction * bolt_speed)


func _spawn_grave(at_position: Vector3) -> void:
	var grave := grave_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(grave)
	grave.global_position = Vector3(at_position.x, _enemy.global_position.y, at_position.z)


func _spawn_minion(at_position: Vector3) -> void:
	var spawner := minion_spawner_scene.instantiate() as EnemySpawner
	var parent := _get_minions_parent()
	spawner.enemies_parent = parent
	parent.add_child(spawner)
	spawner.global_position = at_position


## Minions live outside the enemy group, so they never count toward clearing it.
func _get_minions_parent() -> Node3D:
	if is_instance_valid(_minions_parent):
		return _minions_parent
	_minions_parent = Node3D.new()
	_minions_parent.name = "NecromancerMinions"
	get_tree().current_scene.add_child(_minions_parent)
	return _minions_parent


func _pick_minion_point(angle: float) -> Vector3:
	var point := _ring_point(angle)
	for attempt in MINION_RING_TRIES:
		point = _ring_point(angle + TAU * attempt / MINION_RING_TRIES)
		if _nearest_player_distance(point) >= MINION_MIN_PLAYER_DISTANCE:
			return point
	return point


func _ring_point(angle: float) -> Vector3:
	var offset := Vector3.FORWARD.rotated(Vector3.UP, angle) * MINION_RING_RADIUS
	return _snap_to_navmesh(_enemy.global_position + offset)


## Picks the spot farthest from the carriers among a few random ones.
func _pick_blink_point() -> Vector3:
	var best := _enemy.global_position
	var best_distance := _nearest_player_distance(best)
	for attempt in BLINK_CANDIDATES:
		var candidate := _random_home_point()
		var distance := _nearest_player_distance(candidate)
		if distance <= best_distance:
			continue
		best = candidate
		best_distance = distance
	return best


func _random_home_point() -> Vector3:
	var offset := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf() * blink_radius
	return _snap_to_navmesh(_home + offset)


## Keeps the boss's current height: the arena floor is flat and the navmesh floats above it.
func _snap_to_navmesh(point: Vector3) -> Vector3:
	var map_rid := _enemy.navigation_agent.get_navigation_map()
	var snapped := NavigationServer3D.map_get_closest_point(map_rid, point)
	return Vector3(snapped.x, _enemy.global_position.y, snapped.z)


func _nearest_player_distance(point: Vector3) -> float:
	var nearest := INF
	for player in _get_living_players():
		var offset := player.global_position - point
		nearest = minf(nearest, Vector2(offset.x, offset.z).length())
	return nearest


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


func _spawn_puff() -> void:
	var puff := PUFF_SCENE.instantiate() as GPUParticles3D
	var world := get_tree().current_scene
	world.add_child(puff)
	puff.global_position = _enemy.global_position
	puff.emitting = true
	get_tree().create_timer(puff.lifetime + 0.5).timeout.connect(puff.queue_free)


func _play_sound(stream: AudioStream) -> void:
	var sfx := AudioStreamPlayer3D.new()
	_enemy.add_child(sfx)
	sfx.bus = "SFX"
	sfx.stream = stream
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
