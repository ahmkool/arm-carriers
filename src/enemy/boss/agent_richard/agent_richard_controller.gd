class_name AgentRichardController
extends Node
## Drives Agent Richard's highway boss fight phases:
##   - Phase 1 (100% -> 75% HP): flanking trucks, sky jumps, bullets & grenades.
##   - Phase 2 (75% -> 50% HP): same while players cross timed trucks.
##   - Phase 3 (50% -> 25% HP): fights directly on the same big platform as players, adding
##     single and double chained melee dash lunges (with red floor lane telegraphs).
##   - Phase 4 (25% -> 0% HP): rolling forward highway convoy combining flanking assaults,
##     timed moving truck crossings, and on-deck melee dash raids until full defeat.

signal phase_one_completed
signal phase_two_completed
signal phase_three_completed
signal boss_defeated

const BOSS_NAME := "Agent Richard"
const BOSS_ICON := preload("res://assets/sprites/ui/icons/agent_richard_boss_icon.png")
const BULLET_SCENE := preload("res://src/enemy/boss/agent_richard/agent_bullet.tscn")
const GRENADE_SCRIPT := preload("res://src/enemy/boss/agent_richard/agent_grenade.gd")
const DASH_LANE_SHADER := preload("res://src/enemy/boss/agent_richard/dash_lane.gdshader")
const EXPLOSION_SCENE := preload("res://src/vfx/explosion.tscn")
const SHOTGUN_SCENE := preload("res://assets/models/weapon/enemies/survivalist/shotgun.gltf")
const BACKPACK_SCENE := preload("res://assets/models/weapon/enemies/survivalist/backpack.gltf")
const VEHICLE_SCRIPT := preload("res://src/world/elements/highway/highway_vehicle.gd")
## Matches KayKit Rig_Medium handslot.r alignment used by RobotGunner / AviatorGunner so +Z barrel points forward.
const GUN_HAND_TRANSFORM := Transform3D(
	Vector3(0.0186, 0.0022, -0.9998),
	Vector3(-0.055, 0.9985, 0.0011),
	Vector3(0.9983, 0.055, 0.0187),
	Vector3.ZERO,
)

const GUN_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/gun/Gun 6-1.wav"),
	preload("res://assets/sounds/gun/Gun 6-2.wav"),
]
const LAND_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")
const JUMP_SOUND := preload("res://assets/sounds/punch/Punch 3_1.wav")
const DASH_WARN_SOUND := preload("res://assets/sounds/cogs/807842__sabacky__complex-mechanism-short.wav")
const LUNGE_SOUND := preload("res://assets/sounds/slash_3.wav")
const SLASH_HIT_SOUND := preload("res://assets/sounds/slash_1.wav")

@export var phase_one_end_ratio: float = 0.75
@export var phase_two_end_ratio: float = 0.50
@export var phase_three_end_ratio: float = 0.25
@export var bullet_speed: float = 16.0
@export var bullet_damage: int = 1
@export var bullet_burst_count: int = 3
@export var bullet_interval_sec: float = 0.28
@export var grenade_count: int = 2
@export var grenade_flight_sec: float = 1.35
@export var grenade_blast_radius: float = 2.3
@export var grenade_damage: int = 1
@export var dash_damage: int = 1
@export var dash_min_length: float = 6.0
@export var dash_max_length: float = 15.5
@export var dash_overshoot: float = 3.2
@export var dash_hit_radius: float = 1.65
@export var dash_windup_sec: float = 0.90
@export var dash_followup_windup_sec: float = 0.68
@export var dash_lunge_sec: float = 0.26
@export var sky_height: float = 28.0

var _enemy: EnemyLocal
var _health: Health
var _anim_player: AnimationPlayer
var _muzzle: Marker3D
var _muzzle_flash: MeshInstance3D
var _landing_ring: Node3D
var _landing_ring_mat: StandardMaterial3D
var _dash_lane_root: Node3D
var _dash_lane_mesh: MeshInstance3D
var _dash_lane_mat: ShaderMaterial

var _left_truck: VEHICLE_SCRIPT
var _right_truck: VEHICLE_SCRIPT
var _player_truck: VEHICLE_SCRIPT
var _phase4_truck_a: VEHICLE_SCRIPT
var _phase4_truck_b: VEHICLE_SCRIPT
var _current_truck: VEHICLE_SCRIPT
var _on_right_truck := true
var _truck_local_offset := Vector3.ZERO
var _airborne := false
var _dash_locking := false
var _crossing_imminent := false
var _retreating := false
var _phase_done := false
var _active_phase := 0
var _target_threshold_ratio := 0.75
var _run_id := 0
var _muzzle_flash_timer := 0.0


func _ready() -> void:
	_enemy = get_parent() as EnemyLocal
	if _enemy == null:
		return
	_health = Health.from_target(_enemy)
	if _health != null:
		_health.damaged.connect(_on_health_damaged)
	_anim_player = _enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_attach_equipment()
	_build_muzzle_flash()
	_build_landing_ring()
	_build_dash_lane()
	hide_offstage()


func _physics_process(delta: float) -> void:
	if _enemy == null:
		return
	if _muzzle_flash_timer > 0.0:
		_muzzle_flash_timer = maxf(0.0, _muzzle_flash_timer - delta)
		if _muzzle_flash_timer <= 0.0 and _muzzle_flash != null:
			_muzzle_flash.visible = false

	if _landing_ring != null and _landing_ring.visible:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.018)
		_landing_ring_mat.albedo_color = Color(1.0, 0.35, 0.12, lerpf(0.45, 0.95, pulse))

	if not _enemy.visible or _airborne or _current_truck == null or not _current_truck.visible:
		return

	# Stay planted on whichever flanking truck roof Agent Richard is standing on.
	var deck_pos := _current_truck.get_deck_world_position()
	_enemy.global_position = deck_pos + _truck_local_offset
	_enemy.velocity = Vector3.ZERO

	# Smoothly face the closest living player unless a melee dash lane is locked or phase ended.
	if _dash_locking or _phase_done:
		return
	var target := _closest_living_player()
	if target != null:
		var to_player := target.global_position - _enemy.global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			_enemy.smooth_rotate_toward(to_player, delta)


## Hides Agent Richard offstage (used before/between phases or on checkpoint reset).
func hide_offstage(resume_hp_ratio: float = 1.0) -> void:
	_run_id += 1
	_airborne = true
	_dash_locking = false
	_retreating = false
	_phase_done = true
	_active_phase = 0
	_current_truck = null
	if _landing_ring != null:
		_landing_ring.visible = false
	if _dash_lane_root != null:
		_dash_lane_root.visible = false
	if _enemy != null:
		_enemy.visible = false
		_enemy.collision_layer = 0
		_enemy.is_offensive = false
		_enemy.global_position = Vector3(0.0, sky_height + 20.0, -40.0)
		if _enemy.enemy_state_machine != null and _enemy.enemy_state_machine.has_state("idle"):
			_enemy.enemy_state_machine.transition_to("idle")
	if _health != null:
		_health.reset_to_full()
		if resume_hp_ratio < 0.999:
			_health.current_hp = _ratio_to_hp(resume_hp_ratio)
			_health.grant_invulnerability(999.0)


## Updates the active player truck so future grenades and raids target the new roof.
## Never teleports Richard once he is visible or standing on a truck — he rides that truck
## (even if it drops off-screen) and then sky-jumps back to a side platform.
func set_player_truck(player_truck: VEHICLE_SCRIPT) -> void:
	var old_player_truck := _player_truck
	_player_truck = player_truck
	if _active_phase == 4 and _current_truck == old_player_truck and player_truck != null and _airborne and not _enemy.visible:
		_current_truck = player_truck


## Tells Phase 4 AI whether a timed truck drop-out is imminent so Richard stays on flanking trucks during crossings.
func set_crossing_imminent(imminent: bool) -> void:
	_crossing_imminent = imminent


## Starts Phase 1 (100% -> 75% HP): binds boss health bar, drops Richard onto right truck, begins attacks.
func begin_phase_one(
	left_truck: VEHICLE_SCRIPT,
	right_truck: VEHICLE_SCRIPT,
	player_truck: VEHICLE_SCRIPT,
) -> void:
	_begin_phase(1, 1.0, phase_one_end_ratio, left_truck, right_truck, player_truck)


## Starts Phase 2 (75% -> 50% HP): same combat loop while players regularly cross from truck to truck.
func begin_phase_two(
	left_truck: VEHICLE_SCRIPT,
	right_truck: VEHICLE_SCRIPT,
	player_truck: VEHICLE_SCRIPT,
) -> void:
	_begin_phase(2, phase_one_end_ratio, phase_two_end_ratio, left_truck, right_truck, player_truck)


## Starts Phase 3 (50% -> 25% HP): Richard drops directly onto the players' big platform and adds
## katana-style melee dash lunges (1 or 2 chained dashes) alongside bullets and grenades.
func begin_phase_three(arena_truck: VEHICLE_SCRIPT) -> void:
	_run_id += 1
	var run_id := _run_id
	_active_phase = 3
	_target_threshold_ratio = phase_three_end_ratio
	_left_truck = arena_truck
	_right_truck = arena_truck
	_player_truck = arena_truck
	_current_truck = arena_truck
	_phase_done = false
	_retreating = false
	_dash_locking = false
	_truck_local_offset = Vector3(0.0, 0.0, -7.5)

	if _health != null:
		_health.reset_to_full()
		_health.current_hp = _ratio_to_hp(phase_two_end_ratio)

	_bind_boss_health_bar()
	_run_phase_three_loop(run_id)


## Starts Phase 4 (25% -> 0% HP): Final rolling highway showdown combining flanking trucks,
## bullets, grenades, and on-deck melee dash raids while players advance through timed truck crossings.
func begin_phase_four(
	left_truck: VEHICLE_SCRIPT,
	right_truck: VEHICLE_SCRIPT,
	player_truck_a: VEHICLE_SCRIPT,
	player_truck_b: VEHICLE_SCRIPT = null,
) -> void:
	_run_id += 1
	var run_id := _run_id
	_active_phase = 4
	_target_threshold_ratio = 0.0
	_left_truck = left_truck
	_right_truck = right_truck
	_player_truck = player_truck_a
	_phase4_truck_a = player_truck_a
	_phase4_truck_b = player_truck_b
	_on_right_truck = true
	_current_truck = _right_truck
	_phase_done = false
	_retreating = false
	_dash_locking = false
	_crossing_imminent = false
	_truck_local_offset = Vector3(0.0, 0.0, -1.0)

	if _enemy != null and _enemy.enemy_state_machine != null and _enemy.enemy_state_machine.has_state("idle"):
		_enemy.enemy_state_machine.transition_to("idle")
	if _health != null:
		_health.reset_to_full()
		_health.current_hp = _ratio_to_hp(phase_three_end_ratio)

	_bind_boss_health_bar()
	_run_phase_four_loop(run_id)


func _run_phase_four_loop(run_id: int) -> void:
	if not await _drop_onto_truck(_right_truck, Vector3(0.0, 0.0, -1.0), run_id):
		return

	# Quick opening volley on the flank truck, then immediately queue an on-deck melee dash raid!
	if not await _wait_seconds(0.35, run_id):
		return
	if not await _perform_bullet_burst(run_id):
		return

	var raid_due := true
	while _is_active_run(run_id):
		if not await _wait_seconds(0.45, run_id):
			return

		if raid_due and _player_truck != null:
			if _crossing_imminent:
				# Keep pressure with a quick flank shot while players cross, without losing the queued melee raid!
				if not await _perform_bullet_burst(run_id):
					return
				continue

			# Sky-drop directly onto the players' moving truck and unleash a single melee dash!
			# (Double dashes are exclusive to Phase 3.)
			raid_due = false
			var raid_offset := Vector3(0.0, 0.0, -5.8)
			if not await _jump_to_truck(_player_truck, raid_offset, run_id):
				return
			if not await _wait_seconds(0.30, run_id):
				return
			if not await _perform_melee_dash_combo(1, run_id):
				return
			if not await _wait_seconds(0.40, run_id):
				return
			# Jump back out onto the opposite flanking boss truck.
			_on_right_truck = not _on_right_truck
			var exit_flank := _right_truck if _on_right_truck else _left_truck
			if not await _jump_to_truck(exit_flank, Vector3(0.0, 0.0, randf_range(-2.5, 2.0)), run_id):
				return
		else:
			# Flanking assault: bullet burst + moving-deck grenades, then queue the next on-deck melee raid.
			if not await _perform_bullet_burst(run_id):
				return
			if not await _wait_seconds(0.45, run_id):
				return
			if not await _perform_grenade_salvo(run_id):
				return
			raid_due = true


func _run_phase_three_loop(run_id: int) -> void:
	# Dramatic sky drop directly onto the front of the players' megacarrier platform!
	if not await _drop_onto_truck(_player_truck, Vector3(0.0, 0.0, -7.5), run_id):
		return

	var attack_cycle := 0
	while _is_active_run(run_id):
		if not await _wait_seconds(0.55, run_id):
			return

		match attack_cycle % 3:
			0:
				# Single melee dash lunge -> bullet burst.
				if not await _perform_melee_dash_combo(1, run_id):
					return
				if not await _wait_seconds(0.65, run_id):
					return
				if not await _perform_bullet_burst(run_id):
					return
			1:
				# Double chained melee dash lunge (katana-boss style!) -> grenade salvo.
				if not await _perform_melee_dash_combo(2, run_id):
					return
				if not await _wait_seconds(0.75, run_id):
					return
				if not await _perform_grenade_salvo(run_id):
					return
			_:
				# Bullet burst -> randomized 1 or 2 melee dashes -> sky-jump reposition across platform.
				if not await _perform_bullet_burst(run_id):
					return
				if not await _wait_seconds(0.55, run_id):
					return
				var dashes := 2 if randf() < 0.55 else 1
				if not await _perform_melee_dash_combo(dashes, run_id):
					return
				if not await _wait_seconds(0.55, run_id):
					return
				var jump_offset := _pick_platform_jump_offset()
				if not await _jump_to_truck(_player_truck, jump_offset, run_id):
					return

		attack_cycle += 1


func _pick_platform_jump_offset() -> Vector3:
	if _player_truck == null:
		return Vector3(0.0, 0.0, -7.0)
	var half_w := maxf(_player_truck.roof_width * 0.5 - 2.6, 2.0)
	var half_l := maxf(_player_truck.roof_length * 0.5 - 2.8, 3.0)
	# Pick a spot on the opposite side of the platform from the players for a dramatic slam.
	var target := _closest_living_player()
	var side_x := -1.0 if (target != null and target.global_position.x > _player_truck.get_deck_world_position().x) else 1.0
	var side_z := -1.0 if (target != null and target.global_position.z > _player_truck.get_deck_world_position().z) else 1.0
	return Vector3(
		side_x * randf_range(half_w * 0.35, half_w * 0.85),
		0.0,
		side_z * randf_range(half_l * 0.35, half_l * 0.80),
	)


func _perform_melee_dash_combo(dash_count: int, run_id: int) -> bool:
	for i in dash_count:
		if not _is_active_run(run_id):
			return false
		if _current_truck == null or not _current_truck.visible:
			_end_dash_visuals()
			return true
		if not await _perform_single_dash(i > 0, run_id):
			return false
		if i < dash_count - 1:
			if _current_truck == null or not _current_truck.visible:
				return true
			if not await _wait_seconds(0.22, run_id):
				return false
	return true


func _perform_single_dash(is_follow_up: bool, run_id: int) -> bool:
	if _current_truck == null or not _current_truck.visible:
		return true
	var windup := dash_followup_windup_sec if is_follow_up else dash_windup_sec
	var lock_time := windup * 0.58

	_dash_locking = true
	_play_anim(&"Jump_Start", 1.1)
	_play_sfx(DASH_WARN_SOUND, 0.95 if is_follow_up else 0.80, -3.0)

	var dash_dir := -_enemy.global_basis.z
	dash_dir.y = 0.0
	dash_dir = dash_dir.normalized() if dash_dir.length_squared() > 0.001 else Vector3.BACK
	var dash_length := dash_min_length
	var dest_truck: VEHICLE_SCRIPT = _current_truck

	if _dash_lane_root != null:
		_dash_lane_root.visible = true

	var elapsed := 0.0
	while elapsed < windup:
		if not _is_active_run(run_id):
			_end_dash_visuals()
			return false
		if _current_truck == null or not _current_truck.visible:
			_end_dash_visuals()
			_enemy.visible = false
			return true
		var dt := get_physics_process_delta_time()
		var origin := _current_truck.get_deck_world_position() + _truck_local_offset

		# Track target during early windup, then lock the lane so players can read and sidestep it.
		if elapsed < lock_time:
			var target := _closest_living_player()
			if target != null:
				var to_target := target.global_position - origin
				to_target.y = 0.0
				if to_target.length_squared() > 0.01:
					_enemy.smooth_rotate_toward(to_target, dt * 1.4)
					dash_dir = -_enemy.global_basis.z
					dash_dir.y = 0.0
					dash_dir = dash_dir.normalized()
					var plan := _measure_dash_plan(origin, dash_dir, to_target.length())
					dash_length = plan["length"]
					dest_truck = plan["dest_truck"]

		_update_dash_lane_visual(origin, dash_dir, dash_length, clampf(elapsed / windup, 0.0, 1.0), elapsed >= lock_time)
		await get_tree().physics_frame
		elapsed += dt

	if not _is_active_run(run_id):
		_end_dash_visuals()
		return false
	if _current_truck == null or not _current_truck.visible:
		_end_dash_visuals()
		_enemy.visible = false
		return true

	# Safety check: if a cross-truck destination started falling back during windup, clamp back onto current truck.
	var start_truck := _current_truck
	if dest_truck != start_truck and dest_truck != _get_crossable_neighbor_truck():
		dest_truck = start_truck

	# Explosive melee lunge along the locked red lane (bridging onto an adjacent docked truck if planned)!
	if _dash_lane_root != null:
		_dash_lane_root.visible = false
	_play_anim(&"Running_HoldingRifle", 2.2)
	_play_sfx(LUNGE_SOUND, 0.65 if is_follow_up else 0.55, 1.5)
	CameraFeedback.add_trauma_dash()
	ImpactFeedback.spawn_dust(_enemy.global_position, 0.95)

	var start_offset := _truck_local_offset
	var start_world := start_truck.get_deck_world_position() + start_offset
	var is_cross_truck := (dest_truck != start_truck)
	var end_world := start_world + dash_dir * dash_length
	if dest_truck.deck != null:
		end_world = dest_truck.deck.clamp_inside(end_world, 1.35)
	var end_offset := end_world - dest_truck.get_deck_world_position()
	end_offset.y = 0.0

	if is_cross_truck:
		_airborne = true

	var hit_players: Array[PlayerLocal] = []
	var lunge_elapsed := 0.0
	var dust_timer := 0.0
	while lunge_elapsed < dash_lunge_sec:
		if not _is_active_run(run_id):
			_airborne = false
			_end_dash_visuals()
			return false
		if dest_truck == null or not dest_truck.visible:
			_airborne = false
			_end_dash_visuals()
			_enemy.visible = false
			return true
		var dt := get_physics_process_delta_time()
		lunge_elapsed = minf(lunge_elapsed + dt, dash_lunge_sec)
		var t := clampf(lunge_elapsed / maxf(dash_lunge_sec, 0.01), 0.0, 1.0)

		if is_cross_truck:
			var p_from := (start_truck.get_deck_world_position() + start_offset) if start_truck.visible else start_world
			var p_to := dest_truck.get_deck_world_position() + end_offset
			var hop_y := sin(t * PI) * 0.85
			_enemy.global_position = p_from.lerp(p_to, t) + Vector3.UP * hop_y
		else:
			if not start_truck.visible:
				_end_dash_visuals()
				_enemy.visible = false
				return true
			_truck_local_offset = start_offset.lerp(end_offset, t)
			_enemy.global_position = start_truck.get_deck_world_position() + _truck_local_offset

		dust_timer += dt
		if dust_timer >= 0.07:
			dust_timer = 0.0
			ImpactFeedback.spawn_dust(_enemy.global_position, 0.55)

		for p in _living_players():
			if hit_players.has(p):
				continue
			var off := p.global_position - _enemy.global_position
			if absf(off.y) <= 2.4 and Vector2(off.x, off.z).length() <= dash_hit_radius:
				hit_players.append(p)
				if Health.apply_damage(p, dash_damage, _enemy.global_position):
					CameraFeedback.add_trauma_hurt()
					ImpactFeedback.play_sfx(SLASH_HIT_SOUND, p.global_position, 0.85, 0.0)

		await get_tree().physics_frame

	_airborne = false
	if dest_truck == null or not dest_truck.visible:
		_end_dash_visuals()
		_enemy.visible = false
		return true

	_current_truck = dest_truck
	_truck_local_offset = end_offset
	_enemy.global_position = dest_truck.get_deck_world_position() + _truck_local_offset
	_play_anim(&"Throw", 1.6)
	ImpactFeedback.spawn_dust(_enemy.global_position, 1.1 if is_cross_truck else 1.0)
	if is_cross_truck:
		_play_sfx(LAND_SOUND, 1.05, -7.0)
	_dash_locking = false
	return true


func _get_crossable_neighbor_truck() -> VEHICLE_SCRIPT:
	if _active_phase != 4 or _current_truck == null:
		return null
	var other: VEHICLE_SCRIPT = null
	if _current_truck == _phase4_truck_a:
		other = _phase4_truck_b
	elif _current_truck == _phase4_truck_b:
		other = _phase4_truck_a
	if other == null or not other.visible or other.is_falling_back():
		return null
	var cur_pos := _current_truck.get_deck_world_position()
	var oth_pos := other.get_deck_world_position()
	var max_dx := (_current_truck.roof_width + other.roof_width) * 0.5 + 1.5
	var max_dz := (_current_truck.roof_length + other.roof_length) * 0.5 - 3.0
	if absf(oth_pos.x - cur_pos.x) > max_dx or absf(oth_pos.z - cur_pos.z) > max_dz:
		return null
	return other


## Probes along `dir` across `_current_truck` and (when docked side-by-side in Phase 4) its
## adjacent neighbor truck, stopping cleanly before any open highway edge.
func _measure_dash_plan(origin_world: Vector3, dir: Vector3, target_dist: float) -> Dictionary:
	var wanted := clampf(target_dist + dash_overshoot, dash_min_length, dash_max_length)
	if _current_truck == null or _current_truck.deck == null:
		return {"length": wanted, "dest_truck": _current_truck}

	var neighbor := _get_crossable_neighbor_truck()
	var last_safe_len := 2.0
	var last_safe_truck: VEHICLE_SCRIPT = _current_truck
	var step := 0.45
	var d := step
	while d <= wanted:
		var pt := origin_world + dir * d
		var on_cur := _current_truck.deck.contains(pt, 1.2)
		var on_neighbor := neighbor != null and neighbor.deck != null and neighbor.deck.contains(pt, 1.2)
		if on_neighbor:
			last_safe_len = d
			last_safe_truck = neighbor
		elif on_cur:
			last_safe_len = d
			last_safe_truck = _current_truck
		else:
			var in_bridge := neighbor != null and neighbor.deck != null \
				and _current_truck.deck.contains(pt, -1.6) \
				and neighbor.deck.contains(pt, -1.6)
			if not in_bridge:
				break
		d += step

	return {"length": maxf(last_safe_len, 2.0), "dest_truck": last_safe_truck}


func _update_dash_lane_visual(origin: Vector3, dir: Vector3, length: float, progress: float, is_locked: bool) -> void:
	if _dash_lane_root == null or _dash_lane_mesh == null:
		return
	var flat_dir := Vector3(dir.x, 0.0, dir.z)
	if flat_dir.length_squared() < 0.0001:
		flat_dir = Vector3.BACK
	flat_dir = flat_dir.normalized()

	if _current_truck != null and _current_truck.visible:
		var surf_xform := _current_truck.get_roof_indicator_transform(_truck_local_offset, 0.08)
		var surf_up := surf_xform.basis.y.normalized()
		var forward_on_roof := flat_dir - surf_up * flat_dir.dot(surf_up)
		if forward_on_roof.length_squared() < 0.0001:
			forward_on_roof = flat_dir
		_dash_lane_root.global_position = surf_xform.origin
		_dash_lane_root.global_basis = Basis.looking_at(forward_on_roof.normalized(), surf_up)
	else:
		_dash_lane_root.global_position = Vector3(origin.x, origin.y + 0.09, origin.z)
		_dash_lane_root.global_basis = Basis.looking_at(flat_dir, Vector3.UP)

	var clamped_len := maxf(length, 0.5)
	_dash_lane_mesh.scale.z = clamped_len
	_dash_lane_mesh.position.z = -clamped_len * 0.5
	if _dash_lane_mat != null:
		_dash_lane_mat.set_shader_parameter("charge", progress)
		_dash_lane_mat.set_shader_parameter("locked", 1.0 if is_locked else 0.0)
		_dash_lane_mat.set_shader_parameter("lane_length", clamped_len)


func _end_dash_visuals() -> void:
	_dash_locking = false
	if _dash_lane_root != null:
		_dash_lane_root.visible = false


func _begin_phase(
	phase_index: int,
	start_hp_ratio: float,
	end_hp_ratio: float,
	left_truck: VEHICLE_SCRIPT,
	right_truck: VEHICLE_SCRIPT,
	player_truck: VEHICLE_SCRIPT,
) -> void:
	_run_id += 1
	var run_id := _run_id
	_active_phase = phase_index
	_target_threshold_ratio = end_hp_ratio
	_left_truck = left_truck
	_right_truck = right_truck
	_player_truck = player_truck
	_phase_done = false
	_retreating = false
	_on_right_truck = true
	_current_truck = _right_truck
	_truck_local_offset = Vector3(0.0, 0.0, -1.0)

	if _health != null:
		_health.reset_to_full()
		if start_hp_ratio < 0.999:
			_health.current_hp = _ratio_to_hp(start_hp_ratio)

	_bind_boss_health_bar()
	_run_phase_loop(run_id)


func _run_phase_loop(run_id: int) -> void:
	# Dramatic sky drop onto the right flanking truck!
	if not await _drop_onto_truck(_right_truck, Vector3(0.0, 0.0, -1.0), run_id):
		return

	var attack_cycle := 0
	while _is_active_run(run_id):
		if not await _wait_seconds(0.65, run_id):
			return

		# Alternate between bullet burst and grenade throw, then jump across to the opposite truck.
		if attack_cycle % 2 == 0:
			if not await _perform_bullet_burst(run_id):
				return
			if not await _wait_seconds(0.75, run_id):
				return
			if not await _perform_grenade_salvo(run_id):
				return
		else:
			if not await _perform_grenade_salvo(run_id):
				return
			if not await _wait_seconds(0.75, run_id):
				return
			if not await _perform_bullet_burst(run_id):
				return

		if not await _wait_seconds(0.65, run_id):
			return

		# Jump up, disappear, and fall down onto the opposite side truck!
		_on_right_truck = not _on_right_truck
		var dest_truck := _right_truck if _on_right_truck else _left_truck
		var dest_z := randf_range(-3.2, 2.2)
		if not await _jump_to_truck(dest_truck, Vector3(0.0, 0.0, dest_z), run_id):
			return

		attack_cycle += 1


# ---- Attacks ----

func _perform_bullet_burst(run_id: int) -> bool:
	for i in bullet_burst_count:
		if not _is_active_run(run_id):
			return false
		_fire_single_bullet()
		if i < bullet_burst_count - 1:
			if not await _wait_seconds(bullet_interval_sec, run_id):
				return false
	return true


func _fire_single_bullet() -> void:
	var target := _closest_living_player()
	if target == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	_play_anim(&"Ranged_2H_Shoot", 1.8)
	var flash_origin := _muzzle.global_position if _muzzle != null else (_enemy.global_position + Vector3.UP * 1.45 - _enemy.global_basis.z * 0.9)
	var origin := Vector3(flash_origin.x, _enemy.global_position.y + 1.25, flash_origin.z)
	var aim_pos := target.global_position + Vector3.UP * 1.0
	var dir := aim_pos - origin
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = -_enemy.global_basis.z
	dir = dir.normalized()
	# Tiny tactical spread so rapid bursts feel natural yet dodgeable.
	var spread := deg_to_rad(randf_range(-4.0, 4.0))
	dir = dir.rotated(Vector3.UP, spread)

	var bullet := BULLET_SCENE.instantiate() as Fireball
	bullet.damage = bullet_damage
	scene_root.add_child(bullet)
	bullet.global_position = origin
	bullet.launch(dir * bullet_speed)

	if _muzzle_flash != null:
		_muzzle_flash.global_position = flash_origin
		_muzzle_flash.visible = true
		_muzzle_flash_timer = 0.07
	_play_sfx(GUN_SOUNDS.pick_random(), randf_range(0.92, 1.08), -5.0)


func _perform_grenade_salvo(run_id: int) -> bool:
	var players := _living_players()
	if players.is_empty():
		return true

	for i in grenade_count:
		if not _is_active_run(run_id):
			return false
		var target_player := players[i % players.size()]
		var target_pos := target_player.global_position
		if i > 0:
			# Offset second grenade slightly so players aren't hit by overlapping blasts.
			target_pos += Vector3(randf_range(-2.6, 2.6), 0.0, randf_range(-2.6, 2.6))
		if _player_truck != null and _player_truck.deck != null:
			target_pos = _player_truck.deck.clamp_inside(target_pos, 1.5)
		_launch_grenade(target_pos)
		if i < grenade_count - 1:
			if not await _wait_seconds(0.42, run_id):
				return false
	return true


func _launch_grenade(target_world: Vector3) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	_play_anim(&"Throw", 1.25)
	var grenade := GRENADE_SCRIPT.new()
	grenade.blast_radius = grenade_blast_radius
	grenade.damage = grenade_damage
	scene_root.add_child(grenade)
	var hand_pos := _enemy.global_position + Vector3.UP * 1.9
	var track_surface: Node3D = _player_truck.get_visual_surface_node() if _player_truck != null else null
	grenade.launch(hand_pos, target_world, grenade_flight_sec, track_surface)


# ---- Sky Jump & Drop ----

func _jump_to_truck(dest_truck: VEHICLE_SCRIPT, local_offset: Vector3, run_id: int) -> bool:
	# 1) Crouch telegraph + leap straight UP and disappear.
	if not await _leap_up_and_vanish(run_id):
		return false
	# 2) Drop straight down onto the target truck roof.
	return await _drop_onto_truck(dest_truck, local_offset, run_id)


func _leap_up_and_vanish(run_id: int, allow_retreat: bool = false) -> bool:
	# If Richard already rode a departing truck off-screen, skip crouch/leap and drop straight onto the next truck.
	if not _enemy.visible or (_current_truck != null and not _current_truck.visible):
		_airborne = true
		_enemy.collision_layer = 0
		_enemy.is_offensive = false
		_enemy.visible = false
		return true

	_play_anim(&"Jump_Start", 1.6)
	ImpactFeedback.spawn_dust(_enemy.global_position, 0.7)
	var crouch_elapsed := 0.0
	while crouch_elapsed < 0.24:
		await get_tree().physics_frame
		if not _is_jump_valid(run_id, allow_retreat):
			return false
		crouch_elapsed += get_physics_process_delta_time()

	_airborne = true
	_enemy.collision_layer = 0
	_enemy.is_offensive = false
	_play_anim(&"Jump_Idle", 1.2)
	_play_sfx(JUMP_SOUND, 1.35, -4.0)

	var start_pos := _enemy.global_position
	var duration := 0.34
	var elapsed := 0.0
	while elapsed < duration:
		await get_tree().physics_frame
		if not _is_jump_valid(run_id, allow_retreat):
			return false
		elapsed += get_physics_process_delta_time()
		var t := clampf(elapsed / duration, 0.0, 1.0)
		var eased := t * t
		_enemy.global_position = Vector3(start_pos.x, lerpf(start_pos.y, sky_height, eased), start_pos.z)

	_enemy.visible = false
	return true


func _is_jump_valid(run_id: int, allow_retreat: bool) -> bool:
	if not is_inside_tree() or run_id != _run_id:
		return false
	if allow_retreat:
		return true
	return not _phase_done and not _retreating


func _drop_onto_truck(dest_truck: VEHICLE_SCRIPT, local_offset: Vector3, run_id: int) -> bool:
	_current_truck = dest_truck
	_truck_local_offset = local_offset
	_airborne = true
	_enemy.visible = false
	_enemy.collision_layer = 0

	# Show pulsing landing ring on destination truck roof so players see him incoming!
	if _landing_ring != null:
		_landing_ring.visible = true
	var telegraph := 0.48
	var t_wait := 0.0
	while t_wait < telegraph:
		await get_tree().physics_frame
		if not _is_active_run(run_id):
			if _landing_ring != null:
				_landing_ring.visible = false
			return false
		t_wait += get_physics_process_delta_time()
		if _landing_ring != null and _current_truck != null:
			_landing_ring.global_transform = _current_truck.get_roof_indicator_transform(_truck_local_offset, 0.09)

	# Fall straight down from the sky onto the target position.
	var landing_pos := _current_truck.get_deck_world_position() + _truck_local_offset
	_enemy.global_position = Vector3(landing_pos.x, sky_height, landing_pos.z)
	_face_players_immediately()
	_enemy.visible = true
	_play_anim(&"Jump_Idle", 1.0)

	var fall_duration := 0.28
	var elapsed := 0.0
	while elapsed < fall_duration:
		await get_tree().physics_frame
		if not _is_active_run(run_id):
			if _landing_ring != null:
				_landing_ring.visible = false
			return false
		elapsed += get_physics_process_delta_time()
		var t := clampf(elapsed / fall_duration, 0.0, 1.0)
		var land_now := _current_truck.get_deck_world_position() + _truck_local_offset
		_enemy.global_position = Vector3(land_now.x, lerpf(sky_height, land_now.y, t * t), land_now.z)
		if _landing_ring != null and _current_truck != null:
			_landing_ring.global_transform = _current_truck.get_roof_indicator_transform(_truck_local_offset, 0.09)

	if _landing_ring != null:
		_landing_ring.visible = false

	_enemy.global_position = _current_truck.get_deck_world_position() + _truck_local_offset
	_airborne = false
	_enemy.collision_layer = 2
	_enemy.is_offensive = true
	_play_anim(&"Jump_Land", 1.4)
	ImpactFeedback.spawn_dust(_enemy.global_position, 1.0)
	CameraFeedback.add_trauma(0.18)
	_play_sfx(LAND_SOUND, 0.85, -5.0)
	return true


# ---- Phase Threshold Retreat & Completion ----

func _on_health_damaged(_amount: int, remaining: int, _source_position: Vector3) -> void:
	if _phase_done or _retreating or _active_phase <= 0:
		return
	var threshold := _ratio_to_hp(_target_threshold_ratio)
	if remaining > threshold:
		return

	# Clamp at exact phase threshold HP so burst damage can't overshoot into the next quarter.
	var completed_phase := _active_phase
	_phase_done = true
	_retreating = true
	_end_dash_visuals()
	_run_id += 1
	if _health != null:
		_health.current_hp = threshold
		if threshold > 0:
			_health.grant_invulnerability(999.0)
	_enemy.collision_layer = 0
	_enemy.is_offensive = false
	get_tree().call_group(Checkpoint.ENEMY_PROJECTILE_GROUP, "queue_free")
	ImpactFeedback.play_boss_moment()
	CameraFeedback.add_trauma_boss_moment()
	if completed_phase == 4:
		_run_final_defeat(_run_id)
	else:
		_run_retreat_jump(completed_phase, _run_id)


func _run_final_defeat(defeat_run_id: int) -> void:
	if _landing_ring != null:
		_landing_ring.visible = false
	if _dash_lane_root != null:
		_dash_lane_root.visible = false
	_retreating = false
	_airborne = false
	_enemy.visible = true
	_play_anim(&"Death_A", 1.0)
	var scene_root := get_tree().current_scene
	if scene_root != null:
		var blast := EXPLOSION_SCENE.instantiate()
		blast.set("hurts_enemies", false)
		blast.set("damage_radius", 0.0)
		scene_root.add_child(blast)
		blast.global_position = _enemy.global_position + Vector3.UP * 1.1
	ImpactFeedback.spawn_dust(_enemy.global_position, 1.4)
	_hide_boss_health_bar_soon(defeat_run_id)
	boss_defeated.emit()


func _run_retreat_jump(completed_phase: int, retreat_run_id: int) -> void:
	if _landing_ring != null:
		_landing_ring.visible = false
	if _dash_lane_root != null:
		_dash_lane_root.visible = false
	if _enemy.visible:
		await _leap_up_and_vanish(retreat_run_id, true)
	if not is_inside_tree() or retreat_run_id != _run_id:
		return
	_retreating = false
	_current_truck = null
	_hide_boss_health_bar_soon(retreat_run_id)
	if completed_phase == 1:
		phase_one_completed.emit()
	elif completed_phase == 2:
		phase_two_completed.emit()
	elif completed_phase == 3:
		phase_three_completed.emit()


func _ratio_to_hp(ratio: float) -> int:
	if _health == null:
		return int(round(160.0 * ratio))
	return int(round(_health.max_hp * ratio))


# ---- Equipment & Visual Helpers ----

func _attach_equipment() -> void:
	var skeleton := _enemy.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return

	# Shotgun in right hand aligned to point straight forward in Ranged_2H_Aiming.
	var right_hand := BoneAttachment3D.new()
	right_hand.name = "RightHandAttachment"
	right_hand.bone_name = "handslot.r"
	skeleton.add_child(right_hand)
	var shotgun := SHOTGUN_SCENE.instantiate() as Node3D
	if shotgun != null:
		shotgun.transform = GUN_HAND_TRANSFORM
		right_hand.add_child(shotgun)
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		_muzzle.position = Vector3(0.0, 0.16, 0.88)
		shotgun.add_child(_muzzle)

	# Survivalist tactical backpack on chest/back.
	var back := BoneAttachment3D.new()
	back.name = "BackAttachment"
	back.bone_name = "chest"
	skeleton.add_child(back)
	var backpack := BACKPACK_SCENE.instantiate() as Node3D
	if backpack != null:
		backpack.position = Vector3(0.0, 0.18, -0.34)
		backpack.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		back.add_child(backpack)


func _build_muzzle_flash() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.2, 1.35, 0.35, 0.95)
	var mesh := SphereMesh.new()
	mesh.radius = 0.32
	mesh.height = 0.64
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = mat
	_muzzle_flash = MeshInstance3D.new()
	_muzzle_flash.top_level = true
	_muzzle_flash.visible = false
	_muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_flash.mesh = mesh
	add_child(_muzzle_flash)


func _build_landing_ring() -> void:
	_landing_ring = Node3D.new()
	_landing_ring.top_level = true
	_landing_ring.visible = false
	add_child(_landing_ring)

	_landing_ring_mat = StandardMaterial3D.new()
	_landing_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_landing_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_landing_ring_mat.albedo_color = Color(1.0, 0.35, 0.12, 0.85)

	var torus := TorusMesh.new()
	torus.inner_radius = 1.45
	torus.outer_radius = 1.75
	torus.rings = 32
	torus.ring_segments = 4
	torus.material = _landing_ring_mat

	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.08, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_landing_ring.add_child(ring)


func _build_dash_lane() -> void:
	_dash_lane_root = Node3D.new()
	_dash_lane_root.top_level = true
	_dash_lane_root.visible = false
	add_child(_dash_lane_root)

	_dash_lane_mat = ShaderMaterial.new()
	_dash_lane_mat.shader = DASH_LANE_SHADER
	_dash_lane_mat.set_shader_parameter("charge", 0.0)
	_dash_lane_mat.set_shader_parameter("locked", 0.0)
	_dash_lane_mat.set_shader_parameter("lane_length", 10.0)

	var plane := PlaneMesh.new()
	plane.size = Vector2(2.5, 1.0)
	plane.material = _dash_lane_mat

	_dash_lane_mesh = MeshInstance3D.new()
	_dash_lane_mesh.mesh = plane
	_dash_lane_mesh.position = Vector3(0.0, 0.0, -0.5)
	_dash_lane_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dash_lane_root.add_child(_dash_lane_mesh)


func _play_anim(anim_name: StringName, speed_scale: float = 1.0) -> void:
	if _anim_player == null:
		return
	var full_name := StringName("survivalist/" + String(anim_name))
	if not _anim_player.has_animation(full_name):
		return
	_anim_player.speed_scale = speed_scale
	_anim_player.play(full_name, 0.1)
	if anim_name != &"Death_A" and anim_name != &"Ranged_2H_Aiming" and anim_name != &"Idle_B" and anim_name != &"Jump_Idle":
		_anim_player.queue(&"survivalist/Ranged_2H_Aiming")


func _bind_boss_health_bar() -> void:
	var world := get_tree().current_scene as WorldLocal
	if world == null or _health == null:
		return
	var bar := world.get_node_or_null("UI/BossHealthBar") as BossHealthBar
	if bar == null:
		return
	bar.bind(_health, BOSS_ICON, BOSS_NAME)


func _hide_boss_health_bar_soon(expected_run_id: int) -> void:
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		return
	var bar := world.get_node_or_null("UI/BossHealthBar") as BossHealthBar
	if bar == null:
		return
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(bar) and _phase_done and _run_id == expected_run_id:
			bar.hide_bar()
	)


func _face_players_immediately() -> void:
	var target := _closest_living_player()
	if target == null:
		return
	var to_player := target.global_position - _enemy.global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		_enemy.global_basis = Basis.looking_at(to_player.normalized(), Vector3.UP)


func _is_active_run(run_id: int) -> bool:
	return is_inside_tree() and run_id == _run_id and not _phase_done and not _retreating


func _wait_seconds(seconds: float, run_id: int) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		if not _is_active_run(run_id):
			return false
		elapsed += get_physics_process_delta_time()
	return true


func _living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var world := get_tree().current_scene
	if world == null:
		return living
	var players := world.get_node_or_null(^"Players")
	if players == null:
		return living
	for child in players.get_children():
		var p := child as PlayerLocal
		if p == null or p.is_dead:
			continue
		living.append(p)
	return living


func _closest_living_player() -> PlayerLocal:
	var best: PlayerLocal = null
	var best_dist := INF
	for p in _living_players():
		var d := _enemy.global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _play_sfx(stream: AudioStream, pitch: float, volume_db: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sfx := AudioStreamPlayer3D.new()
	scene_root.add_child(sfx)
	sfx.global_position = _enemy.global_position
	sfx.bus = "SFX"
	sfx.stream = stream
	sfx.pitch_scale = pitch
	sfx.volume_db = volume_db
	sfx.max_distance = 70.0
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
