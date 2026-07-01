extends Area3D

@export var damage: int = 1

const HIT_SOUND := preload("res://assets/sounds/damage.wav")


func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(_delta):
	pass

func _on_body_entered(body: Node) -> void:
	if body is not PlayerLocal:
		return
	var player := body as PlayerLocal
	if player == null:
		return
	CameraFeedback.add_trauma_hurt()
	if not Health.apply_damage(player, damage, global_position):
		return
	_play_hit_sfx()


func _play_hit_sfx() -> void:
	var sfx := AudioStreamPlayer3D.new()
	add_child(sfx)
	sfx.global_position = global_position
	sfx.bus = "SFX"
	sfx.stream = HIT_SOUND
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
