extends Sprite3D

@export var carrying_weapon_data: CarryingWeaponData

const SHOW_DURATION := 0.24
const HIDE_DURATION := 0.16
const IDLE_BOB_AMOUNT := 0.06
const IDLE_BOB_SPEED := 4.0
const REST_SCALE := Vector3.ONE

var _prompt_visible := false
var _base_prompt_y := 0.0
var _visibility_tween: Tween = null
var _idle_time := 0.0


func _ready() -> void:
	_resolve_carrying_weapon_data()
	var prompt_parent := get_parent() as Node3D
	if prompt_parent != null:
		_base_prompt_y = prompt_parent.position.y
	_kill_visibility_tween()
	modulate.a = 0.0
	scale = Vector3.ZERO
	visible = false


func _process(delta: float) -> void:
	if carrying_weapon_data == null:
		return
	var should_show := _should_show_prompt()
	if should_show != _prompt_visible:
		_prompt_visible = should_show
		if should_show:
			_play_show_animation()
		else:
			_play_hide_animation()
	if not _prompt_visible:
		return
	_idle_time += delta
	_apply_idle_bob()


func _resolve_carrying_weapon_data() -> void:
	if carrying_weapon_data != null:
		return
	carrying_weapon_data = get_node_or_null("../../CarryingWeaponData") as CarryingWeaponData


func _should_show_prompt() -> bool:
	if carrying_weapon_data == null:
		return false
	var player := carrying_weapon_data.get_parent() as PlayerLocal
	if player != null and player.is_dead:
		return false
	return _is_can_carry_status(carrying_weapon_data.can_carry_status)


func _is_can_carry_status(status: CarryingWeaponData.CanCarryStatus) -> bool:
	if status == CarryingWeaponData.CanCarryStatus.CAN_CARRY_SHOOTER:
		return true
	if status == CarryingWeaponData.CanCarryStatus.CAN_CARRY_DIRECTION_SETTER:
		return true
	return false


func _apply_idle_bob() -> void:
	var prompt_parent := get_parent() as Node3D
	if prompt_parent == null:
		return
	var bob_offset := sin(_idle_time * IDLE_BOB_SPEED) * IDLE_BOB_AMOUNT
	prompt_parent.position.y = _base_prompt_y + bob_offset


func _reset_prompt_bob() -> void:
	_idle_time = 0.0
	var prompt_parent := get_parent() as Node3D
	if prompt_parent == null:
		return
	prompt_parent.position.y = _base_prompt_y


func _play_show_animation() -> void:
	_kill_visibility_tween()
	_reset_prompt_bob()
	visible = true
	scale = Vector3.ZERO
	modulate.a = 0.0
	_visibility_tween = create_tween()
	_visibility_tween.set_parallel(true)
	_visibility_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_visibility_tween.tween_property(self, "scale", REST_SCALE, SHOW_DURATION)
	_visibility_tween.tween_property(self, "modulate:a", 1.0, SHOW_DURATION * 0.85)


func _play_hide_animation() -> void:
	_kill_visibility_tween()
	_reset_prompt_bob()
	_visibility_tween = create_tween()
	_visibility_tween.set_parallel(true)
	_visibility_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_visibility_tween.tween_property(self, "scale", Vector3.ZERO, HIDE_DURATION)
	_visibility_tween.tween_property(self, "modulate:a", 0.0, HIDE_DURATION)
	_visibility_tween.chain().tween_callback(_on_hide_animation_finished)


func _on_hide_animation_finished() -> void:
	if _prompt_visible:
		return
	visible = false


func _kill_visibility_tween() -> void:
	if _visibility_tween == null:
		return
	_visibility_tween.kill()
	_visibility_tween = null
