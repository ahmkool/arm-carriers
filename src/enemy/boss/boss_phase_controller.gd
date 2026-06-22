class_name BossPhaseController
extends Node

signal phase_changed(phase_index: int)

@export var thresholds: Array[BossPhaseThreshold] = []
@export var fire_particles_path: NodePath = NodePath(
	"Skeleton_Golem/Rig_Large/Skeleton3D/BoneAttachment3D/Skeleton_Golem_Axe/FireParticles"
)
@export var axe_fire_visual_path: NodePath = NodePath(
	"Skeleton_Golem/Rig_Large/Skeleton3D/BoneAttachment3D/Skeleton_Golem_Axe/BossAxeFireVisual"
)

var _current_phase := 1
var _triggered_phases: Dictionary = {}


func _ready() -> void:
	_bind_health()
	_stop_enrage_visuals()


func get_current_phase() -> int:
	return _current_phase


func is_phase_at_least(phase: int) -> bool:
	return _current_phase >= phase


static func from_enemy(enemy: Node) -> BossPhaseController:
	if enemy == null:
		return null
	return enemy.get_node_or_null("BossPhaseController") as BossPhaseController


func _bind_health() -> void:
	var health := _get_health()
	if health == null:
		return
	health.damaged.connect(_on_health_damaged)
	health.died.connect(_on_health_died)


func _on_health_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	_stop_enrage_visuals()


func _get_health() -> Health:
	return Health.from_target(get_parent())


func _on_health_damaged(_amount: int, remaining: int, _source_position: Vector3) -> void:
	if remaining <= 0:
		return
	_evaluate_thresholds(remaining)


func _evaluate_thresholds(remaining: int) -> void:
	var health := _get_health()
	if health == null:
		return
	var max_hp := health.max_hp
	if max_hp <= 0:
		return
	var hp_ratio := float(remaining) / float(max_hp)
	for threshold in _get_sorted_thresholds():
		_try_trigger_threshold(threshold, hp_ratio)


func _get_sorted_thresholds() -> Array[BossPhaseThreshold]:
	var resolved := _resolve_thresholds()
	resolved.sort_custom(_sort_thresholds_descending)
	return resolved


func _sort_thresholds_descending(a: BossPhaseThreshold, b: BossPhaseThreshold) -> bool:
	return a.hp_ratio > b.hp_ratio


func _resolve_thresholds() -> Array[BossPhaseThreshold]:
	if thresholds.is_empty():
		return [_default_threshold()]
	return thresholds


func _default_threshold() -> BossPhaseThreshold:
	var threshold := BossPhaseThreshold.new()
	threshold.hp_ratio = 0.5
	threshold.phase_index = 2
	return threshold


func _try_trigger_threshold(threshold: BossPhaseThreshold, current_hp_ratio: float) -> void:
	if current_hp_ratio > threshold.hp_ratio:
		return
	if _triggered_phases.has(threshold.phase_index):
		return
	_enter_phase(threshold.phase_index)


func _enter_phase(phase_index: int) -> void:
	if phase_index <= _current_phase:
		return
	_triggered_phases[phase_index] = true
	_current_phase = phase_index
	_apply_phase_visuals(phase_index)
	phase_changed.emit(phase_index)


func _apply_phase_visuals(phase_index: int) -> void:
	if phase_index < 2:
		return
	_start_enrage_visuals()


func _start_enrage_visuals() -> void:
	_set_fire_vfx_emitting(true)
	_start_axe_blade_fire()


func _stop_enrage_visuals() -> void:
	_set_fire_vfx_emitting(false)
	_stop_axe_blade_fire()


func _start_axe_blade_fire() -> void:
	var visual := _get_axe_fire_visual()
	if visual == null:
		return
	visual.start_enrage()


func _stop_axe_blade_fire() -> void:
	var visual := _get_axe_fire_visual()
	if visual == null:
		return
	visual.stop_enrage()


func _get_axe_fire_visual() -> BossAxeFireVisual:
	if axe_fire_visual_path.is_empty():
		return null
	var boss := get_parent()
	if boss == null:
		return null
	return boss.get_node_or_null(axe_fire_visual_path) as BossAxeFireVisual


func _get_axe_mesh() -> MeshInstance3D:
	var particles := _get_fire_particles()
	if particles == null:
		return null
	return particles.get_parent() as MeshInstance3D


func _set_fire_vfx_emitting(emitting: bool) -> void:
	for particles in _get_axe_fire_particles():
		particles.emitting = emitting


func _get_axe_fire_particles() -> Array[GPUParticles3D]:
	var result: Array[GPUParticles3D] = []
	var primary := _get_fire_particles()
	if primary == null:
		return result
	result.append(primary)
	var parent := primary.get_parent()
	if parent == null:
		return result
	var embers := parent.get_node_or_null("FireEmbers") as GPUParticles3D
	if embers != null:
		result.append(embers)
	return result


func _get_fire_particles() -> GPUParticles3D:
	if fire_particles_path.is_empty():
		return null
	var boss := get_parent()
	if boss == null:
		return null
	return boss.get_node_or_null(fire_particles_path) as GPUParticles3D
