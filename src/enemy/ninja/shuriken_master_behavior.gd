class_name ShurikenMasterBehavior
extends NinjaBehavior
## The Shuriken Master, a mini-boss: a big ninja with two giant `BossShuriken` circling him. He runs circles round
## the carriers as the ninja does, and:
## - launches one of his stars at the nearer carrier (the Launching state), where it lingers and creeps after them;
## - after a few seconds pulls it back (the Pulling state), so it cuts back through the carriers on its way home;
## - swaps places with a star that is out, if it is clear of the carriers: he vanishes in a puff and is where it
##   was, and it is where he stood.
##   He does it when hurt, at most every `swap_cooldown` seconds, and now and then on his own to get away.
## His stars knock the carriers' shots off course. He doesn't dodge like the ninja: swapping is his escape.

const SWAP_PUFF := preload("res://src/vfx/small_explosion.tscn")
const SWAP_SOUND := preload("res://assets/sounds/slash_1.wav")
const STAR_COUNT := 2
## He won't swap to a star this close to a carrier, so he never lands on top of one.
const SWAP_CLEARANCE := 3.5

## Launches only at a target within this flat distance.
@export var launch_max_distance := 13.0
@export var first_launch_delay := 1.5
@export var launch_cooldown_min := 2.5
@export var launch_cooldown_max := 4.0
## A star that has drifted this long is pulled back, picked at random each time.
@export var pull_after_min := 2.5
@export var pull_after_max := 4.0
@export var swap_cooldown := 5.0
## Between swaps he makes on his own, without being hurt.
@export var idle_swap_min := 7.0
@export var idle_swap_max := 11.0

var stars: Array[BossShuriken] = []
var _launch_cooldown := 0.0
var _swap_cooldown := 0.0
var _idle_swap := 0.0
var _pull_after := 0.0
## The star the Pulling state will call back, and the one the Launching state throws.
var _star_to_pull: BossShuriken
var _star_to_launch: BossShuriken


func _ready() -> void:
	super()
	# Swapping places is his escape; the ninja's sidestep would only get in its way.
	has_dodged = true
	# The enemy's own @onready health isn't set yet: children are ready before their parent.
	var health := enemy.get_node("Health") as Health
	health.damaged.connect(_on_damaged)
	health.died.connect(func(_from): _free_stars())
	enemy.tree_exiting.connect(_free_stars)


## The Launching state's release: throws the chosen star at the nearer carrier.
func release_launch() -> void:
	if not is_instance_valid(_star_to_launch) or not is_instance_valid(enemy.target_player):
		return
	_star_to_launch.throw_at(enemy.target_player.global_position)
	_star_to_launch = null


## The Pulling state's release: calls the drifting star home.
func release_pull() -> void:
	if not is_instance_valid(_star_to_pull):
		return
	_star_to_pull.pull_back()
	_star_to_pull = null
	_pull_after = randf_range(pull_after_min, pull_after_max)


## Swaps places with a star that is out, if one is and the spot is on the roof. Returns whether he did.
func swap_places() -> bool:
	var star := _star_to_swap_with()
	if star == null:
		return false
	var here := enemy.global_position
	var there := Vector3(star.global_position.x, here.y, star.global_position.z)
	_puff(here)
	_puff(there)
	enemy.global_position = there
	enemy.velocity = Vector3.ZERO
	star.drift_from(here)
	_swap_cooldown = swap_cooldown
	_idle_swap = randf_range(idle_swap_min, idle_swap_max)
	ImpactFeedback.play_sfx(SWAP_SOUND, there, randf_range(1.5, 1.7), -2.0)
	return true


func _think(delta: float) -> void:
	if enemy == null or _is_busy():
		return
	if not enemy.is_offensive:
		_was_offensive = false
		return
	_wake_up()
	_launch_cooldown = maxf(_launch_cooldown - delta, 0.0)
	_swap_cooldown = maxf(_swap_cooldown - delta, 0.0)
	_idle_swap -= delta
	enemy.update_target_player()
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	to_target.y = 0.0
	if _try_pull():
		return
	if _try_launch(to_target):
		return
	_try_idle_swap()
	_circle(delta, to_target)


func _is_busy() -> bool:
	var machine := enemy.enemy_state_machine
	if machine == null:
		return true
	if machine.is_in_state("dead"):
		return true
	if machine.is_in_state("launching"):
		return true
	return machine.is_in_state("pulling")


## Raises his two stars the first time he wakes; a respawned boss is a new one and raises his own.
func _wake_up() -> void:
	if _was_offensive:
		return
	_was_offensive = true
	_launch_cooldown = first_launch_delay
	_pull_after = randf_range(pull_after_min, pull_after_max)
	_idle_swap = randf_range(idle_swap_min, idle_swap_max)
	if not stars.is_empty():
		return
	for i in STAR_COUNT:
		var star := BossShuriken.new()
		star.master = enemy
		star.orbit_angle = i * TAU / STAR_COUNT
		enemy.get_tree().current_scene.add_child(star)
		star.global_position = enemy.global_position + Vector3.UP * BossShuriken.HEIGHT
		stars.append(star)


func _try_pull() -> bool:
	for star in stars:
		if not is_instance_valid(star) or not star.is_drifting():
			continue
		if star.drift_seconds() < _pull_after:
			continue
		_star_to_pull = star
		_face(star.global_position)
		intent.requested_locomotion = &"pulling"
		return true
	return false


func _try_launch(to_target: Vector3) -> bool:
	if _launch_cooldown > 0.0:
		return false
	if to_target.length() > launch_max_distance:
		return false
	var star := _orbiting_star()
	if star == null:
		return false
	_star_to_launch = star
	_launch_cooldown = randf_range(launch_cooldown_min, launch_cooldown_max)
	intent.face_direction = to_target
	intent.requested_locomotion = &"launching"
	return true


## One star at a time: he only throws while both are home.
func _orbiting_star() -> BossShuriken:
	for star in stars:
		if not is_instance_valid(star):
			continue
		if star.mode != BossShuriken.Mode.ORBITING:
			return null
	for star in stars:
		if is_instance_valid(star):
			return star
	return null


func _try_idle_swap() -> void:
	if _idle_swap > 0.0 or _swap_cooldown > 0.0:
		return
	if not swap_places():
		_idle_swap = 1.0


func _on_damaged(_amount: int, remaining: int, _from: Vector3) -> void:
	if remaining <= 0 or _swap_cooldown > 0.0:
		return
	if not enemy.is_offensive:
		return
	swap_places()


func _star_to_swap_with() -> BossShuriken:
	for star in stars:
		if _can_swap_to(star):
			return star
	return null


func _can_swap_to(star: BossShuriken) -> bool:
	if not is_instance_valid(star) or not star.is_out():
		return false
	if not _is_on_navmesh(star.global_position):
		return false
	return _carrier_distance(star.global_position) >= SWAP_CLEARANCE


func _carrier_distance(point: Vector3) -> float:
	var players := enemy.get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return INF
	var nearest := INF
	for node in players.get_children():
		var player := node as PlayerLocal
		if player == null:
			continue
		nearest = minf(nearest, Vector2(player.global_position.x - point.x, player.global_position.z - point.z).length())
	return nearest


func _face(point: Vector3) -> void:
	var to_point := point - enemy.global_position
	intent.face_direction = Vector3(to_point.x, 0.0, to_point.z)


func _puff(at: Vector3) -> void:
	var puff := SWAP_PUFF.instantiate() as Node3D
	enemy.get_tree().current_scene.add_child(puff)
	puff.global_position = at + Vector3.UP


func _free_stars() -> void:
	for star in stars:
		if is_instance_valid(star):
			star.vanish()
	stars.clear()
