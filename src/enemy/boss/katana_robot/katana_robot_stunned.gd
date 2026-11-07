extends EnemyState
## 4GTN reeling after a vent breaks its shield: it stands slumped and can't
## act, a free window to shoot it. KatanaRobotMoves shows the slump and the sparks.

@export var stun_seconds := 2.5

var _time_remaining := 0.0
var _moves: KatanaRobotMoves


func enter() -> void:
	super.enter()
	_moves = enemy.get_node("KatanaRobotMoves") as KatanaRobotMoves
	_time_remaining = stun_seconds
	enemy.velocity = Vector3.ZERO
	_moves.begin_stun()


func exit() -> void:
	super.exit()
	_moves.end_stun()


func physics_update(delta: float) -> void:
	enemy.velocity = Vector3.ZERO
	_time_remaining -= delta
	if _time_remaining > 0.0:
		return
	enemy_state_machine.transition_to("idle")
