class_name EnemyHealthBar3D
extends MeshInstance3D
## A small health bar that floats over an enemy's head and always faces the camera.
## Add `enemy_health_bar_3d.tscn` as a direct child of the enemy and move it above the head.
## It reads the enemy's `Health` node, so the enemy needs no code for it.
## Hidden at full health, it shows on the first hit and fades out after a quiet spell.
## Meant for tougher enemies; bosses use the on-screen `BossHealthBar` instead.

## Keep the bar up between hits and at full health.
@export var always_visible := false
## Seconds after the last hit before the bar fades out.
@export var linger_seconds := 3.0

const FADE_IN_PER_SEC := 8.0
const FADE_OUT_PER_SEC := 2.5
## How long the trail holds where the health was before draining down to it.
const TRAIL_DELAY := 0.4
const TRAIL_DRAIN_PER_SEC := 1.5
const FLASH_DECAY_PER_SEC := 5.0
## How long the emptied bar stays up after the enemy dies, so the last hit reads.
const DEATH_LINGER_SECONDS := 0.6
const PARAM_FILL := &"fill"
const PARAM_TRAIL := &"trail"
const PARAM_FLASH := &"flash"
const PARAM_OPACITY := &"opacity"

var _health: Health
var _fill := 1.0
var _trail := 1.0
var _flash := 0.0
var _opacity := 0.0
var _trail_hold := 0.0
var _linger := 0.0
var _is_dead := false


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_health = Health.from_target(get_parent())
	if _health == null:
		push_warning("EnemyHealthBar3D needs a sibling Health node: %s" % get_path())
		hide()
		set_process(false)
		return
	_health.damaged.connect(_on_health_damaged)
	_health.died.connect(_on_health_died)
	_health.restored.connect(_on_health_restored)
	_on_health_restored()


func _process(delta: float) -> void:
	_linger = maxf(0.0, _linger - delta)
	if _is_idle_hidden():
		_trail = _fill
		return
	_step_trail(delta)
	_flash = move_toward(_flash, 0.0, FLASH_DECAY_PER_SEC * delta)
	var target := _target_opacity()
	_opacity = move_toward(_opacity, target, _fade_rate(target) * delta)
	_push_params()


func _is_idle_hidden() -> bool:
	if _opacity > 0.0:
		return false
	if _target_opacity() > 0.0:
		return false
	visible = false
	return true


func _step_trail(delta: float) -> void:
	if _trail_hold > 0.0:
		_trail_hold -= delta
		return
	_trail = move_toward(_trail, _fill, TRAIL_DRAIN_PER_SEC * delta)


func _target_opacity() -> float:
	if _linger > 0.0:
		return 1.0
	if _is_dead:
		return 0.0
	if always_visible:
		return 1.0
	return 0.0


func _fade_rate(target: float) -> float:
	if target > _opacity:
		return FADE_IN_PER_SEC
	return FADE_OUT_PER_SEC


func _push_params() -> void:
	visible = _opacity > 0.0
	set_instance_shader_parameter(PARAM_FILL, _fill)
	set_instance_shader_parameter(PARAM_TRAIL, _trail)
	set_instance_shader_parameter(PARAM_FLASH, _flash)
	set_instance_shader_parameter(PARAM_OPACITY, _opacity)


func _health_ratio() -> float:
	return clampf(float(_health.current_hp) / maxf(float(_health.max_hp), 1.0), 0.0, 1.0)


func _on_health_damaged(_amount: int, _remaining: int, _source_position: Vector3) -> void:
	_fill = _health_ratio()
	_flash = 1.0
	_trail_hold = TRAIL_DELAY
	_linger = linger_seconds


func _on_health_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	_is_dead = true
	_fill = 0.0
	_linger = DEATH_LINGER_SECONDS


func _on_health_restored() -> void:
	_is_dead = false
	_fill = _health_ratio()
	_trail = _fill
	_flash = 0.0
	_trail_hold = 0.0
	_linger = 0.0
	_opacity = 1.0 if always_visible else 0.0
	_push_params()
