extends Node

## Near-zero rather than zero, so physics and timers keep a valid time step.
const HITSTOP_TIME_SCALE := 0.05
const SWORD_HIT_STOP_SEC := 0.06
const EXPLOSION_STOP_SEC := 0.09
const BOSS_MOMENT_STOP_SEC := 0.15
const DUST_SCENE := preload("res://src/vfx/carry_dust.tscn")

var _hitstop_end_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func play_sword_hit() -> void:
	CameraFeedback.add_trauma_sword_hit()
	_request_hitstop(SWORD_HIT_STOP_SEC)


func play_explosion() -> void:
	CameraFeedback.add_trauma_explosion()
	_request_hitstop(EXPLOSION_STOP_SEC)


func play_boss_moment() -> void:
	CameraFeedback.add_trauma_boss_moment()
	_request_hitstop(BOSS_MOMENT_STOP_SEC)


## Does nothing for a player on keyboard: joypad device ids match `PlayerLocal.device_id`.
func rumble(player: PlayerLocal, weak: float, strong: float, duration_sec: float) -> void:
	Input.start_joy_vibration(player.device_id, weak, strong, duration_sec)


## `density` is the 0-1 share of the effect's particles to emit.
func spawn_dust(at_position: Vector3, density: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var dust := DUST_SCENE.instantiate() as GPUParticles3D
	dust.amount_ratio = density
	scene_root.add_child(dust)
	dust.global_position = at_position
	dust.emitting = true


func play_sfx(stream: AudioStream, at_position: Vector3, pitch: float, volume_db: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sfx := AudioStreamPlayer3D.new()
	sfx.bus = "SFX"
	sfx.stream = stream
	sfx.pitch_scale = pitch
	sfx.volume_db = volume_db
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	scene_root.add_child(sfx)
	sfx.global_position = at_position
	sfx.play()


## Overlapping requests keep the latest end time instead of adding together.
func _request_hitstop(duration_sec: float) -> void:
	var end_usec := Time.get_ticks_usec() + int(duration_sec * 1000000.0)
	_hitstop_end_usec = maxi(_hitstop_end_usec, end_usec)
	Engine.time_scale = HITSTOP_TIME_SCALE
	set_process(true)


## Uses real time because `delta` is scaled by the hitstop itself.
func _process(_delta: float) -> void:
	if Time.get_ticks_usec() < _hitstop_end_usec:
		return
	Engine.time_scale = 1.0
	set_process(false)
