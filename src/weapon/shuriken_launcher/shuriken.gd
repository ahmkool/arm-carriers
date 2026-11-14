class_name Shuriken
extends Node3D
## The launcher's big throwing star. It flies flat and spinning, slicing every enemy it passes
## through once, like the siege bow's arrow pierces. At the end of its range it hangs in the air,
## still spinning, for a moment, then pops.
##
## A kunai rides in each of its four blades. Until the star pops, `scatter` throws all four
## outwards along the blades, wherever they point at that instant: the front carrier picks the
## moment, the spin picks the angle. It flies through terrain, like the other carriers' shots.
##
## `set_slowed` eases the star into slow motion: its flight, spin and hang all slow down, and faint
## lines along the blades show where the kunai would fly, so the front carrier can line one up.

signal enemy_hit(enemy: EnemyLocal)
signal scattered(kunais: Array[Kunai])
signal spent

## Every star in flight is in this group, so enemies can see one coming, such as a ninja that dodges.
const GROUP := &"player_shurikens"
## Turns per second while flying. Fast enough to read as a buzz-saw, slow enough to see the kunai.
const SPIN_HZ := 2.2
const HIT_RADIUS := 1.2
const HIT_HEIGHT := 2.4
## Enemies (layer 2) and enemy projectiles such as fireballs (layer 4).
const HIT_MASK := 2 | 8
## Hanging at the end of the range: the front carrier's last window to scatter.
const HOVER_SEC := 0.6
const KUNAI_SPEED := 24.0
const KUNAI_RANGE := 9.0
const KUNAI_DAMAGE := 2
const SLASH_HEIGHT := 1.0
const SLASH_SCENE := preload("res://src/vfx/sword_slash.tscn")
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")
const HIT_SOUND := preload("res://assets/sounds/damage/sword_hit.wav")
const SCATTER_SOUND := preload("res://assets/sounds/slash_3.wav")
## How fast the star's clock runs while slowed: flight, spin and hang alike.
const SLOW_TIME_SCALE := 0.05
## Per second: how quickly the clock eases towards slow motion and back.
const TIME_EASE := 12.0
const AIM_LINE_WIDTH := 0.06
const AIM_LINE_COLOR := Color(1.0, 0.9, 0.6, 0.45)

var _visual: ShurikenVisual
var _hit_area: Area3D
var _direction := Vector3.FORWARD
var _speed := 0.0
var _range := 0.0
var _damage := 0
var _travelled := 0.0
var _hover_left := HOVER_SEC
var _has_kunais := true
var _is_spent := false
var _already_hit: Array[Node] = []
var _slowed := false
var _time_scale := 1.0
var _aim_lines: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	_visual = ShurikenVisual.new()
	add_child(_visual)
	_hit_area = _make_hit_area()
	add_child(_hit_area)
	_hit_area.body_entered.connect(_on_body_entered)
	_hit_area.area_entered.connect(_on_area_entered)
	for i in ShurikenVisual.BLADE_COUNT:
		var line := _make_aim_line(i)
		_visual.add_child(line)
		_aim_lines.append(line)


func launch(origin: Vector3, direction: Vector3, speed: float, flight_range: float, damage: int, spin_angle: float) -> void:
	global_position = origin
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_speed = speed
	_range = flight_range
	_damage = damage
	_visual.rotation.y = spin_angle


func has_kunais() -> bool:
	return _has_kunais and not _is_spent


func is_hovering() -> bool:
	return _travelled >= _range and not _is_spent


func is_spent() -> bool:
	return _is_spent


## Still flying out, not yet hanging at the end of its range or popped.
func is_flying() -> bool:
	return _travelled < _range and not _is_spent


## The flat direction it flies in.
func get_direction() -> Vector3:
	return _direction


func is_slowed() -> bool:
	return _slowed


## How fast the star's clock runs now: 1 at full speed, SLOW_TIME_SCALE when fully slowed.
func get_time_scale() -> float:
	return _time_scale


func set_slowed(slowed: bool) -> void:
	_slowed = slowed
	_set_aim_lines_visible(slowed and has_kunais())


## Throws the four kunai out along the blades. Returns them, or an empty array if they are gone.
func scatter() -> Array[Kunai]:
	var kunais: Array[Kunai] = []
	if not has_kunais():
		return kunais
	_has_kunais = false
	_slowed = false
	_set_aim_lines_visible(false)
	_visual.set_kunais_visible(false)
	for i in ShurikenVisual.BLADE_COUNT:
		kunais.append(_throw_kunai(i))
	ImpactFeedback.play_sfx(SCATTER_SOUND, global_position, randf_range(1.3, 1.5), -2.0)
	scattered.emit(kunais)
	return kunais


func _throw_kunai(index: int) -> Kunai:
	var slot := _visual.global_transform * ShurikenVisual.kunai_slot_transform(index)
	var direction := slot.basis.z
	direction.y = 0.0
	var kunai := Kunai.new()
	get_tree().current_scene.add_child(kunai)
	kunai.launch(slot.origin, direction, KUNAI_SPEED, KUNAI_RANGE, KUNAI_DAMAGE)
	return kunai


func _physics_process(delta: float) -> void:
	if _is_spent:
		return
	var target_scale := SLOW_TIME_SCALE if _slowed else 1.0
	_time_scale = move_toward(_time_scale, target_scale, TIME_EASE * delta)
	var star_delta := delta * _time_scale
	_visual.rotation.y = wrapf(_visual.rotation.y + SPIN_HZ * TAU * star_delta, 0.0, TAU)
	if is_hovering():
		_hover(star_delta)
		return
	var step := minf(_speed * star_delta, _range - _travelled)
	global_position += _direction * step
	_travelled += step


func _hover(delta: float) -> void:
	_hover_left -= delta
	if _hover_left > 0.0:
		return
	_finish()


func _on_body_entered(body: Node3D) -> void:
	if _is_spent or _already_hit.has(body):
		return
	if not body is EnemyLocal:
		return
	_already_hit.append(body)
	# Damage comes from just behind the enemy, so knockback pushes along the flight.
	if not Health.apply_damage(body, _damage, body.global_position - _direction):
		return
	_play_hit_feedback(body)
	enemy_hit.emit(body)


func _on_area_entered(area: Area3D) -> void:
	if _is_spent:
		return
	var fireball := area.get_parent() as Fireball
	if fireball == null:
		return
	_spawn_effect(POP_SCENE, fireball.global_position)
	fireball.queue_free()


func _play_hit_feedback(body: Node3D) -> void:
	ImpactFeedback.play_sfx(HIT_SOUND, body.global_position, randf_range(1.0, 1.2), -2.0)
	var slash := _spawn_effect(SLASH_SCENE, body.global_position + Vector3.UP * SLASH_HEIGHT) as SwordSlash
	slash.align_to(_direction)


func _spawn_effect(scene: PackedScene, at_position: Vector3) -> Node3D:
	var effect := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(effect)
	effect.global_position = at_position
	return effect


func _set_aim_lines_visible(shown: bool) -> void:
	for line in _aim_lines:
		line.visible = shown


## A thin flat strip from the blade's kunai out to the kunai's range, along the blade.
func _make_aim_line(index: int) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = AIM_LINE_COLOR
	material.no_depth_test = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(AIM_LINE_WIDTH, 0.01, KUNAI_RANGE)
	mesh.material = material
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var slot := ShurikenVisual.kunai_slot_transform(index)
	line.transform = Transform3D(slot.basis, slot.origin + slot.basis.z * KUNAI_RANGE / 2.0)
	line.visible = false
	return line


func _make_hit_area() -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = HIT_MASK
	var shape := CylinderShape3D.new()
	shape.radius = HIT_RADIUS
	shape.height = HIT_HEIGHT
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	return area


func _finish() -> void:
	if _is_spent:
		return
	_is_spent = true
	_spawn_effect(POP_SCENE, global_position)
	spent.emit()
	queue_free()
