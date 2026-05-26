class_name HitFlash3D
extends Node

const OVERLAY_SHADER := preload("res://src/shaders/hit_flash_overlay.gdshader")
const FLASH_DURATION_SEC := 0.5

var _meshes: Array[MeshInstance3D] = []
var _overlay: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	_cache_meshes()


func trigger() -> void:
	if _meshes.is_empty():
		_cache_meshes()
	if _meshes.is_empty():
		return
	_kill_tween()
	_apply_overlay()
	_start_flash_tween()


func _cache_meshes() -> void:
	_meshes.clear()
	var root := get_parent()
	if root == null:
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)


func _ensure_overlay_material() -> void:
	if _overlay != null:
		return
	_overlay = ShaderMaterial.new()
	_overlay.shader = OVERLAY_SHADER


func _apply_overlay() -> void:
	_ensure_overlay_material()
	_overlay.set_shader_parameter("flash_amount", 1.0)
	for mesh in _meshes:
		mesh.material_overlay = _overlay


func _start_flash_tween() -> void:
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_method(_set_flash_amount, 1.0, 0.0, FLASH_DURATION_SEC)
	_tween.finished.connect(_on_flash_finished, CONNECT_ONE_SHOT)


func _set_flash_amount(amount: float) -> void:
	if _overlay == null:
		return
	_overlay.set_shader_parameter("flash_amount", amount)


func _on_flash_finished() -> void:
	_clear_overlays()
	_kill_tween()


func _clear_overlays() -> void:
	for mesh in _meshes:
		if not is_instance_valid(mesh):
			continue
		mesh.material_overlay = null


func _kill_tween() -> void:
	if _tween == null:
		return
	_tween.kill()
	_tween = null
