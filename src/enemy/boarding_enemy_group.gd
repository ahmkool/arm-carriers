class_name BoardingEnemyGroup
extends NormalEnemyGroup
## Enemies that drop out of the sky onto a moving deck, such as a rotor barge, when triggered.
## Until then they are hidden and switched off. Each enemy's position in the scene is its landing spot,
## relative to the deck's centre, so place the group at the origin and its enemies around it.

@export var deck: MovingFloor
## How far above the deck an enemy appears, and how long it takes to land.
@export var drop_height := 9.0
@export var drop_seconds := 0.85
## Time between one enemy's drop and the next.
@export var drop_stagger_seconds := 0.2

var _boarded := false
## {enemy, landing (Transform3D relative to the deck), time (seconds since its drop began, negative while waiting)}
var _drops: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	_stow_all()


func has_boarded() -> bool:
	return _boarded


func trigger(offensive: bool = true) -> void:
	if _boarded or not offensive:
		return
	_boarded = true
	var delay := 0.0
	for enemy in _list_enemy_locals():
		if not enemy.is_alive():
			continue
		enemy.is_offensive = true
		_drops.append({"enemy": enemy, "landing": enemy.get_meta(&"deck_landing"), "time": -delay})
		delay += drop_stagger_seconds


func reset() -> void:
	super.reset()
	_boarded = false
	_drops.clear()
	_stow_all()


func mark_as_defeated() -> void:
	_drops.clear()
	super.mark_as_defeated()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	for drop in _drops.duplicate():
		_advance_drop(drop, delta)


func _advance_drop(drop: Dictionary, delta: float) -> void:
	var enemy: EnemyLocal = drop["enemy"]
	if not is_instance_valid(enemy):
		_drops.erase(drop)
		return
	drop["time"] += delta
	if drop["time"] < 0.0:
		return
	var progress := minf(drop["time"] / drop_seconds, 1.0)
	# Falls like a dropped weight: slow at first, fastest on landing.
	var height := drop_height * (1.0 - progress * progress)
	var landing: Transform3D = drop["landing"]
	enemy.global_transform = deck.global_transform * landing.translated(Vector3.UP * (height + 0.05))
	enemy.visible = true
	if progress < 1.0:
		return
	_drops.erase(drop)
	enemy.velocity = Vector3.ZERO
	enemy.process_mode = Node.PROCESS_MODE_INHERIT


## Hidden and out of physics until it boards. Its spot in the scene is kept as its landing spot.
func _stow_all() -> void:
	for enemy in _list_enemy_locals():
		if enemy.is_queued_for_deletion():
			continue
		enemy.set_meta(&"deck_landing", enemy.transform)
		enemy.visible = false
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
