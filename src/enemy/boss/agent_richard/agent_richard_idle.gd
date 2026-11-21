extends EnemyState
## Passive state for Agent Richard: AgentRichardController drives his truck-top positioning,
## sky jumps, bullet bursts, and grenade throws directly.


func physics_update(_delta: float) -> void:
	enemy.velocity = Vector3.ZERO
