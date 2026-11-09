class_name BoardingEnemyGroup
extends NormalEnemyGroup
## Enemies that drop out of the sky onto a moving deck, such as a rotor barge, when triggered.
## Until then they are hidden and switched off. Each enemy's position in the scene is its landing spot,
## relative to the deck's centre, so place the group at the origin and its enemies around it.
## Flyers use FLY_IN instead: they swoop in from the side and brake at their spot, which can be above the deck.

enum Entry { DROP, FLY_IN }

@export var deck: MovingFloor
## How far above the deck an enemy appears, and how long it takes to land.
@export var drop_height := 9.0
@export var drop_seconds := 0.85
## Time between one enemy's drop and the next.
@export var drop_stagger_seconds := 0.2
@export var entry := Entry.DROP
## FLY_IN: where each enemy starts, relative to its spot in the deck's space. Enemies on the deck's west half
## (negative x) come from the mirrored side, so a pair arrives from both flanks.
@export var fly_in_offset := Vector3(16, 7, -10)
@export var fly_in_seconds := 1.6

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
	var progress := minf(drop["time"] / _entry_seconds(), 1.0)
	var landing: Transform3D = drop["landing"]
	enemy.global_transform = deck.global_transform * landing.translated(_entry_offset(landing, progress))
	enemy.visible = true
	if progress < 1.0:
		return
	_drops.erase(drop)
	enemy.velocity = Vector3.ZERO
	enemy.process_mode = Node.PROCESS_MODE_INHERIT


func _entry_seconds() -> float:
	if entry == Entry.FLY_IN:
		return fly_in_seconds
	return drop_seconds


## Where the enemy is, relative to its spot, `progress` (0 to 1) through its entry.
func _entry_offset(landing: Transform3D, progress: float) -> Vector3:
	if entry == Entry.FLY_IN:
		return _fly_in_offset(landing, progress)
	# Falls like a dropped weight: slow at first, fastest on landing.
	return Vector3.UP * (drop_height * (1.0 - progress * progress) + 0.05)


## Fast at first, braking into its spot like a craft coming to a hover.
func _fly_in_offset(landing: Transform3D, progress: float) -> Vector3:
	var remaining := (1.0 - progress) * (1.0 - progress)
	var start := fly_in_offset
	if landing.origin.x < 0.0:
		start.x = -start.x
	return start * remaining


## Hidden and out of physics until it boards. Its spot in the scene is kept as its landing spot.
func _stow_all() -> void:
	for enemy in _list_enemy_locals():
		if enemy.is_queued_for_deletion():
			continue
		enemy.set_meta(&"deck_landing", enemy.transform)
		enemy.visible = false
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
