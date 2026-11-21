class_name HighwayConvoyController
extends Node3D
## Orchestrates the highway intro convoy, Agent Richard's Phase 1 boss fight, and the
## follow-up highway crossings & Action Figure trooper ambush waves.
##
## Sequence:
##   1. Intro (no combat): BoxTruck1 -> ExpressBus -> ShuttleVan -> SemiTrailerAlpha ->
##      CargoVanB -> ArmoredTruckC -> ConvoyCarrier.
##   2. Boss Phase 1 (100% -> 75% HP) on ConvoyCarrier: Agent Richard jumps between left/right
##      flanking trucks, shoots bullets & throws grenades, then retreats at 75% HP + checkpoint.
##   3. Post-Phase-1 Crossings (4 trucks): EscortVan1 -> FlatbedTruck2 -> TransitBus3 -> ArenaSemi4.
##   4. Encounter 1: 3 Action Figure Shooters pull alongside on a truck on the RIGHT.
##   5. Mid Crossings (3 trucks): WeaveVan5 -> ShuttleTruck6 -> ArenaCarrier7.
##   6. Encounter 2: 2 Action Figure Grenadiers pull alongside on a truck on the LEFT.
##   7. Boss Phase 2 (75% -> 50% HP): Agent Richard returns with flanking trucks while players
##      must regularly cross between alternating trucks before their current truck drops off-screen.
##   8. Post-Phase-2 Crossings (2 trucks): PursuitBus8 -> MechArenaCarrier9.
##   9. Flying Winged Mech Duel on MechArenaCarrier9.
##  10. Boss Phase 3 (50% -> 25% HP) on MegaPlatform: Richard fights directly on the same huge
##      platform as the players, adding katana-style single & double melee dash lunges.
##  11. Break Crossings (2 trucks): BreakTruck10 -> FinaleTruckA.
##  12. Boss Phase 4 (25% -> 0% HP): Rolling forward highway finale combining everything —
##      players surge forward from truck to truck on a timer (trucks drop off-screen if missed)
##      while Agent Richard attacks from moving flanking trucks AND drops onto their roof to dash.

const VISUAL_GAP := 0.48
const PHASE2_Z := -124.0
const PHASE2_LEFT_X := -3.64
const PHASE2_RIGHT_X := 3.64
const PHASE2_OFFSCREEN_DEATH_Z := PHASE2_Z + 17.5
const MECH_ARENA_Z := -152.0
const PHASE3_Z := -172.0
const PHASE4_START_Z := -206.0
const PHASE4_LEFT_X := -3.94
const PHASE4_RIGHT_X := 3.94
const PHASE4_FORWARD_STEP_Z := 14.0
const UI_FONT := preload("res://assets/fonts/Lilita_One/LilitaOne-Regular.ttf")
const VehicleScript := preload("res://src/world/elements/highway/highway_vehicle.gd")
const RichardCtrlScript := preload("res://src/enemy/boss/agent_richard/agent_richard_controller.gd")
const TrooperCtrlScript := preload("res://src/enemy/highway_trooper/highway_trooper_controller.gd")
const SHOOTER_SCENE := preload("res://src/enemy/highway_trooper/enemy_action_shooter.tscn")
const GRENADIER_SCENE := preload("res://src/enemy/highway_trooper/enemy_action_grenadier.tscn")
const WINGED_MECH_SCENE := preload("res://src/enemy/enemy_winged_mech.tscn")

@export var checkpoint_intro_1: Checkpoint
@export var checkpoint_intro_2: Checkpoint
@export var checkpoint_intro_3: Checkpoint
@export var checkpoint_boss_phase_1: Checkpoint
@export var checkpoint_phase_1_cleared: Checkpoint
@export var checkpoint_shooters_wave: Checkpoint
@export var checkpoint_shooters_cleared: Checkpoint
@export var checkpoint_grenadiers_wave: Checkpoint
@export var checkpoint_boss_phase_2: Checkpoint
@export var checkpoint_phase_2_cleared: Checkpoint
@export var checkpoint_winged_mech: Checkpoint
@export var checkpoint_winged_mech_cleared: Checkpoint
@export var checkpoint_boss_phase_3: Checkpoint
@export var checkpoint_phase_3_cleared: Checkpoint
@export var checkpoint_boss_phase_4: Checkpoint
@export var agent_richard_boss: EnemyLocal
@export var level_finished_event: LevelEvent
@export var highway_speed: float = 38.0
@export var phase_2_fight_window_sec: float = 5.5
@export var phase_2_cross_time_limit_sec: float = 5.5
@export var phase_4_surge_sec: float = 4.6
@export var phase_4_cross_time_limit_sec: float = 5.0
@export var winged_mech_hp: int = 18

# Intro + Boss Phase 1 vehicles
var _box_truck_1: VehicleScript
var _express_bus: VehicleScript
var _shuttle_van: VehicleScript
var _semi_alpha: VehicleScript
var _cargo_van_b: VehicleScript
var _armored_truck_c: VehicleScript
var _convoy_carrier: VehicleScript
var _boss_truck_left: VehicleScript
var _boss_truck_right: VehicleScript

# Post-Phase-1 crossings + Trooper ambush vehicles
var _escort_van_1: VehicleScript
var _flatbed_truck_2: VehicleScript
var _transit_bus_3: VehicleScript
var _arena_semi_4: VehicleScript
var _shooter_enemy_truck: VehicleScript
var _weave_van_5: VehicleScript
var _shuttle_truck_6: VehicleScript
var _arena_carrier_7: VehicleScript
var _grenadier_enemy_truck: VehicleScript

# Boss Phase 2 alternating player trucks
var _phase2_truck_a: VehicleScript
var _phase2_truck_b: VehicleScript

# Post-Phase-2 crossings + Winged Mech arena + Phase 3 mega platform
var _pursuit_bus_8: VehicleScript
var _mech_arena_carrier_9: VehicleScript
var _phase3_mega_platform: VehicleScript
var _phase2_exit_truck: VehicleScript

# Post-Phase-3 break + Phase 4 rolling finale trucks
var _break_truck_10: VehicleScript
var _finale_truck_a: VehicleScript
var _finale_truck_b: VehicleScript

var _all_vehicles: Array[VehicleScript] = []
var _spawned_troopers: Array[EnemyLocal] = []
var _fall_area: Area3D

var _richard_ctrl: RichardCtrlScript
var _phase_one_cleared := false
var _phase_two_cleared := false
var _phase_three_cleared := false
var _boss_defeated := false

var _finish_pad: Node3D
var _finish_pad_mat: StandardMaterial3D
var _finish_hold_timer := 0.0

var _hud_layer: CanvasLayer
var _section_title_label: Label
var _section_hint_label: Label

## Bumped on every reset so stale coroutines exit immediately.
var _run_id := 0
var _prepared_for_reset := false


func _ready() -> void:
	add_to_group(&"checkpoint_resettable")
	_fall_area = get_node_or_null("../FallArea") as Area3D
	_spawn_vehicles()
	_bind_agent_richard()
	_build_finish_pad()
	_build_section_hud()
	_snap_anchor_vehicle_for_current_checkpoint()


func _physics_process(delta: float) -> void:
	_sync_with_game_state()
	_track_fall_area_with_players()
	_animate_markers(delta)


func _track_fall_area_with_players() -> void:
	if _fall_area == null:
		return
	var players := _living_players()
	if players.is_empty():
		return
	var sum_z := 0.0
	for p in players:
		sum_z += p.global_position.z
	_fall_area.global_position.z = sum_z / float(players.size())


func _bind_agent_richard() -> void:
	if agent_richard_boss == null:
		return
	_richard_ctrl = agent_richard_boss.get_node_or_null("AgentRichardController") as RichardCtrlScript
	if _richard_ctrl == null:
		return
	if not _richard_ctrl.phase_one_completed.is_connected(_on_phase_one_completed):
		_richard_ctrl.phase_one_completed.connect(_on_phase_one_completed)
	if not _richard_ctrl.phase_two_completed.is_connected(_on_phase_two_completed):
		_richard_ctrl.phase_two_completed.connect(_on_phase_two_completed)
	if not _richard_ctrl.phase_three_completed.is_connected(_on_phase_three_completed):
		_richard_ctrl.phase_three_completed.connect(_on_phase_three_completed)
	if not _richard_ctrl.boss_defeated.is_connected(_on_boss_defeated):
		_richard_ctrl.boss_defeated.connect(_on_boss_defeated)


func _on_phase_one_completed() -> void:
	_phase_one_cleared = true


func _on_phase_two_completed() -> void:
	_phase_two_cleared = true


func _on_phase_three_completed() -> void:
	_phase_three_cleared = true


func _on_boss_defeated() -> void:
	_boss_defeated = true


func _sync_with_game_state() -> void:
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		return
	var gsm := world.get_node_or_null("GameStateMachine") as GameStateMachine
	if gsm == null or gsm.current == null:
		return
	var state_name := gsm.current.name.to_lower()
	if state_name == "resettingcheckpoint":
		if not _prepared_for_reset:
			_prepared_for_reset = true
			_run_id += 1
			_set_camera_hold(false)
			_clear_spawned_troopers()
			_snap_anchor_vehicle_for_current_checkpoint()
	else:
		_prepared_for_reset = false


## Called by Checkpoint.set_world_at_checkpoint_state() once world reset finishes.
func reset_to_checkpoint() -> void:
	_run_id += 1
	_finish_hold_timer = 0.0
	_set_camera_hold(false)
	_clear_spawned_troopers()
	var start_stage := _current_checkpoint_stage()
	_phase_one_cleared = start_stage >= 50
	_phase_two_cleared = start_stage >= 100
	_phase_three_cleared = start_stage >= 140
	_boss_defeated = false
	_snap_anchor_vehicle_for_stage(start_stage)
	if _richard_ctrl != null:
		var resume_hp := 1.0
		if start_stage >= 140:
			resume_hp = 0.25
		elif start_stage >= 100:
			resume_hp = 0.50
		elif start_stage >= 50:
			resume_hp = 0.75
		_richard_ctrl.hide_offstage(resume_hp)
	_run_sequence(_run_id, start_stage)


# ---- Vehicle Setup ----

func _spawn_vehicles() -> void:
	# Intro + Boss Phase 1 convoy
	_box_truck_1 = _create_vehicle(
		"BoxTruck1",
		VehicleScript.Archetype.BOX_TRUCK,
		7.0, 14.0,
		Color(0.88, 0.44, 0.14),
		Color(0.76, 0.78, 0.82),
		Color(0.98, 0.82, 0.24),
	)
	_express_bus = _create_vehicle(
		"ExpressBus",
		VehicleScript.Archetype.EXPRESS_BUS,
		7.0, 18.0,
		Color(0.76, 0.16, 0.22),
		Color(0.82, 0.80, 0.78),
		Color(0.96, 0.76, 0.24),
	)
	_shuttle_van = _create_vehicle(
		"ShuttleVan",
		VehicleScript.Archetype.ARMORED_VAN,
		6.2, 11.0,
		Color(0.18, 0.36, 0.62),
		Color(0.68, 0.74, 0.82),
		Color(0.35, 0.88, 1.0),
	)
	_semi_alpha = _create_vehicle(
		"SemiTrailerAlpha",
		VehicleScript.Archetype.SEMI_TRAILER,
		7.6, 20.0,
		Color(0.14, 0.48, 0.54),
		Color(0.72, 0.76, 0.80),
		Color(0.98, 0.86, 0.22),
	)
	_cargo_van_b = _create_vehicle(
		"CargoVanB",
		VehicleScript.Archetype.BOX_TRUCK,
		6.6, 12.5,
		Color(0.88, 0.70, 0.14),
		Color(0.78, 0.78, 0.76),
		Color(0.22, 0.24, 0.28),
	)
	_armored_truck_c = _create_vehicle(
		"ArmoredTruckC",
		VehicleScript.Archetype.ARMORED_VAN,
		6.4, 13.0,
		Color(0.26, 0.42, 0.30),
		Color(0.66, 0.72, 0.68),
		Color(0.35, 0.92, 0.78),
	)
	_convoy_carrier = _create_vehicle(
		"ConvoyCarrier",
		VehicleScript.Archetype.CONVOY_CARRIER,
		11.2, 19.0,
		Color(0.22, 0.24, 0.32),
		Color(0.62, 0.66, 0.74),
		Color(0.30, 0.92, 1.0),
	)
	_boss_truck_left = _create_vehicle(
		"BossTruckLeft",
		VehicleScript.Archetype.ARMORED_VAN,
		6.4, 13.0,
		Color(0.16, 0.17, 0.22),
		Color(0.32, 0.34, 0.40),
		Color(0.95, 0.22, 0.20),
	)
	_boss_truck_right = _create_vehicle(
		"BossTruckRight",
		VehicleScript.Archetype.ARMORED_VAN,
		6.4, 13.0,
		Color(0.16, 0.17, 0.22),
		Color(0.32, 0.34, 0.40),
		Color(0.95, 0.22, 0.20),
	)

	# Post-Phase-1 Crossings A -> Shooters Encounter
	_escort_van_1 = _create_vehicle(
		"EscortVan1",
		VehicleScript.Archetype.ARMORED_VAN,
		6.4, 12.0,
		Color(0.22, 0.42, 0.68),
		Color(0.70, 0.75, 0.82),
		Color(0.38, 0.90, 1.0),
	)
	_flatbed_truck_2 = _create_vehicle(
		"FlatbedTruck2",
		VehicleScript.Archetype.BOX_TRUCK,
		7.0, 14.0,
		Color(0.84, 0.46, 0.16),
		Color(0.78, 0.78, 0.80),
		Color(0.98, 0.82, 0.24),
	)
	_transit_bus_3 = _create_vehicle(
		"TransitBus3",
		VehicleScript.Archetype.EXPRESS_BUS,
		7.0, 17.0,
		Color(0.16, 0.50, 0.46),
		Color(0.76, 0.82, 0.80),
		Color(0.96, 0.86, 0.28),
	)
	_arena_semi_4 = _create_vehicle(
		"ArenaSemi4",
		VehicleScript.Archetype.SEMI_TRAILER,
		8.4, 19.0,
		Color(0.26, 0.32, 0.48),
		Color(0.68, 0.72, 0.78),
		Color(0.32, 0.92, 1.0),
	)
	_shooter_enemy_truck = _create_vehicle(
		"ShooterEnemyTruck",
		VehicleScript.Archetype.BOX_TRUCK,
		6.8, 17.0,
		Color(0.42, 0.12, 0.16),
		Color(0.32, 0.28, 0.32),
		Color(0.98, 0.32, 0.22),
	)

	# Post-Shooters Crossings B -> Grenadiers Encounter
	_weave_van_5 = _create_vehicle(
		"WeaveVan5",
		VehicleScript.Archetype.BOX_TRUCK,
		6.6, 12.5,
		Color(0.86, 0.68, 0.16),
		Color(0.78, 0.78, 0.76),
		Color(0.24, 0.26, 0.30),
	)
	_shuttle_truck_6 = _create_vehicle(
		"ShuttleTruck6",
		VehicleScript.Archetype.ARMORED_VAN,
		6.4, 13.0,
		Color(0.24, 0.46, 0.34),
		Color(0.68, 0.74, 0.70),
		Color(0.38, 0.94, 0.76),
	)
	_arena_carrier_7 = _create_vehicle(
		"ArenaCarrier7",
		VehicleScript.Archetype.SEMI_TRAILER,
		8.4, 19.0,
		Color(0.24, 0.28, 0.40),
		Color(0.66, 0.70, 0.78),
		Color(0.30, 0.92, 1.0),
	)
	_grenadier_enemy_truck = _create_vehicle(
		"GrenadierEnemyTruck",
		VehicleScript.Archetype.BOX_TRUCK,
		6.8, 15.0,
		Color(0.30, 0.34, 0.18),
		Color(0.30, 0.32, 0.26),
		Color(0.98, 0.48, 0.14),
	)

	# Boss Phase 2 alternating player trucks (6.8 m wide, exact 0.48 m gap between -3.64 and +3.64)
	_phase2_truck_a = _create_vehicle(
		"Phase2TruckA",
		VehicleScript.Archetype.BOX_TRUCK,
		6.8, 17.5,
		Color(0.16, 0.34, 0.64),
		Color(0.68, 0.74, 0.84),
		Color(0.32, 0.92, 1.0),
	)
	_phase2_truck_b = _create_vehicle(
		"Phase2TruckB",
		VehicleScript.Archetype.BOX_TRUCK,
		6.8, 17.5,
		Color(0.86, 0.48, 0.14),
		Color(0.80, 0.78, 0.74),
		Color(1.0, 0.84, 0.24),
	)
	_phase2_exit_truck = _phase2_truck_a

	# Post-Phase-2 Crossings -> Flying Winged Mech Arena
	_pursuit_bus_8 = _create_vehicle(
		"PursuitBus8",
		VehicleScript.Archetype.EXPRESS_BUS,
		7.0, 17.0,
		Color(0.56, 0.18, 0.46),
		Color(0.78, 0.76, 0.82),
		Color(1.0, 0.78, 0.30),
	)
	_mech_arena_carrier_9 = _create_vehicle(
		"MechArenaCarrier9",
		VehicleScript.Archetype.CONVOY_CARRIER,
		10.4, 19.0,
		Color(0.16, 0.34, 0.44),
		Color(0.64, 0.70, 0.78),
		Color(0.32, 0.96, 1.0),
	)

	# Boss Phase 3 colossal shared-arena Megacarrier (20.0 m x 26.0 m)
	_phase3_mega_platform = _create_vehicle(
		"Phase3MegaPlatform",
		VehicleScript.Archetype.CONVOY_CARRIER,
		20.0, 26.0,
		Color(0.18, 0.19, 0.26),
		Color(0.56, 0.60, 0.68),
		Color(0.98, 0.32, 0.22),
	)

	# Post-Phase-3 Break + Phase 4 Rolling Finale Trucks (7.4 m wide -> exact 0.48 m gap between -3.94 and +3.94)
	_break_truck_10 = _create_vehicle(
		"BreakTruck10",
		VehicleScript.Archetype.ARMORED_VAN,
		6.4, 14.0,
		Color(0.24, 0.48, 0.52),
		Color(0.74, 0.80, 0.84),
		Color(0.38, 0.96, 0.88),
	)
	_finale_truck_a = _create_vehicle(
		"FinaleTruckA",
		VehicleScript.Archetype.BOX_TRUCK,
		7.4, 18.0,
		Color(0.16, 0.30, 0.62),
		Color(0.68, 0.74, 0.84),
		Color(0.34, 0.92, 1.0),
	)
	_finale_truck_b = _create_vehicle(
		"FinaleTruckB",
		VehicleScript.Archetype.BOX_TRUCK,
		7.4, 18.0,
		Color(0.84, 0.34, 0.14),
		Color(0.80, 0.76, 0.72),
		Color(1.0, 0.82, 0.22),
	)


func _create_vehicle(
	v_name: String,
	arch: VehicleScript.Archetype,
	width: float,
	length: float,
	body_col: Color,
	roof_col: Color,
	stripe_col: Color,
) -> VehicleScript:
	var v := VehicleScript.new()
	v.name = v_name
	v.archetype = arch
	v.roof_width = width
	v.roof_length = length
	v.body_color = body_col
	v.roof_color = roof_col
	v.stripe_color = stripe_col
	v.highway_speed = highway_speed
	add_child(v)
	v.ensure_built()
	v.set_active(false)
	_all_vehicles.append(v)
	return v


func _snap_anchor_vehicle_for_current_checkpoint() -> void:
	_snap_anchor_vehicle_for_stage(_current_checkpoint_stage())


func _snap_anchor_vehicle_for_stage(stage: int) -> void:
	var anchor: VehicleScript = _box_truck_1
	var anchor_pos := Vector3(-4.0, 0.0, 0.0)
	match stage:
		20:
			anchor = _express_bus
			anchor_pos = Vector3(3.48, 0.0, -1.0)
		30:
			anchor = _semi_alpha
			anchor_pos = Vector3(-10.98, 0.0, -19.0)
		40, 50:
			anchor = _convoy_carrier
			anchor_pos = Vector3(0.0, 0.0, -38.0)
		60, 70:
			anchor = _arena_semi_4
			anchor_pos = Vector3(-5.50, 0.0, -76.0)
		80:
			anchor = _arena_carrier_7
			anchor_pos = Vector3(5.50, 0.0, -108.0)
		90, 100:
			anchor = _phase2_truck_a
			anchor_pos = Vector3(PHASE2_LEFT_X, 0.0, PHASE2_Z)
			_phase2_exit_truck = _phase2_truck_a
		110, 120:
			anchor = _mech_arena_carrier_9
			anchor_pos = Vector3(0.0, 0.0, MECH_ARENA_Z)
		130, 140:
			anchor = _phase3_mega_platform
			anchor_pos = Vector3(0.0, 0.0, PHASE3_Z)
		150:
			anchor = _finale_truck_a
			anchor_pos = Vector3(PHASE4_LEFT_X, 0.0, PHASE4_START_Z)

	for v in _all_vehicles:
		if v == anchor:
			continue
		v.set_active(false)
	if _finish_pad != null:
		_finish_pad.visible = false

	anchor.snap_to(anchor_pos)
	anchor.set_active(true)


# ---- Full Highway Sequence ----

func _run_sequence(run_id: int, start_stage: int) -> void:
	if start_stage <= 10:
		if not await _run_intro_1(run_id):
			return
	if start_stage <= 20:
		if not await _run_intro_2(run_id):
			return
	if start_stage <= 30:
		if not await _run_intro_3(run_id):
			return
	if start_stage <= 40:
		if not await _run_boss_phase_1(run_id):
			return
	if start_stage <= 50:
		if not await _run_post_phase_1_crossings(run_id):
			return
	if start_stage <= 60:
		if not await _run_shooters_encounter(run_id):
			return
	if start_stage <= 70:
		if not await _run_mid_crossings(run_id):
			return
	if start_stage <= 80:
		if not await _run_grenadiers_encounter(run_id):
			return
		if not await _run_transition_to_phase_2(run_id):
			return
	if start_stage <= 90:
		if not await _run_boss_phase_2(run_id):
			return
	if start_stage <= 100:
		if not await _run_post_phase_2_crossings(run_id):
			return
	if start_stage <= 110:
		if not await _run_winged_mech_encounter(run_id):
			return
	if start_stage <= 120:
		if not await _run_transition_to_phase_3(run_id):
			return
	if start_stage <= 130:
		if not await _run_boss_phase_3(run_id):
			return
	if start_stage <= 140:
		if not await _run_post_phase_3_break_crossings(run_id):
			return
	await _run_boss_phase_4(run_id)


## Intro Part 1 (no fight): BoxTruck1 -> ExpressBus.
func _run_intro_1(run_id: int) -> bool:
	_set_hud("HIGHWAY INTRO — CATCH THE CONVOY", "Cruising on Box Truck... Express Bus approaching on the right")
	if not await _wait_seconds(1.8, run_id):
		return false

	_express_bus.spawn_and_drive(Vector3(3.48, 0.0, 68.0), Vector3(3.48, 0.0, -1.0), 3.0, -1)
	if not await _wait_vehicle_stop(_express_bus, run_id):
		return false

	_box_truck_1.set_transfer_side(VehicleScript.TransferSide.RIGHT)
	_box_truck_1.set_warning(true)
	_set_hud("HIGHWAY INTRO — LANE TRANSFER", "Cross RIGHT onto the Express Bus →")

	if not await _wait_all_players_on(_express_bus, run_id):
		return false

	_box_truck_1.start_fall_back(72.0, 2.2, 0.0)
	_activate_checkpoint(checkpoint_intro_2)
	return true


## Intro Part 2 (no fight): ExpressBus -> ShuttleVan overtake -> SemiTrailerAlpha.
func _run_intro_2(run_id: int) -> bool:
	_set_hud("HIGHWAY INTRO — OVERTAKE SHUTTLE", "Semi-Trailer Alpha spotted ahead — hold steady on the Bus")

	_semi_alpha.spawn_and_drive(Vector3(-10.98, 0.0, -96.0), Vector3(-10.98, 0.0, -19.0), 3.2, 0)
	if not await _wait_vehicle_stop(_box_truck_1, run_id):
		return false

	_set_hud("HIGHWAY INTRO — OVERTAKE SHUTTLE", "Armored Shuttle Van pulling up on the left")
	_shuttle_van.spawn_and_drive(Vector3(-3.60, 0.0, 64.0), Vector3(-3.60, 0.0, -2.0), 2.6, 1)
	if not await _wait_vehicle_stop(_shuttle_van, run_id):
		return false

	_express_bus.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_express_bus.set_warning(true)
	_set_hud("HIGHWAY INTRO — BOARD SHUTTLE", "← Cross LEFT onto the Armored Shuttle Van")

	if not await _wait_all_players_on(_shuttle_van, run_id):
		return false

	_express_bus.start_fall_back(72.0, 2.3, 1.0)
	_set_hud("HIGHWAY INTRO — OVERTAKING", "Hold on! Closing distance to Semi-Trailer Alpha ↑")
	_shuttle_van.drive_to(Vector3(-3.60, 0.0, -17.0), 3.0, -1)
	if not await _wait_vehicle_stop(_shuttle_van, run_id):
		return false
	if not await _wait_vehicle_stop(_semi_alpha, run_id):
		return false

	_shuttle_van.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_shuttle_van.set_warning(true)
	_set_hud("HIGHWAY INTRO — BOARD SEMI-TRAILER", "← Cross LEFT onto Semi-Trailer Alpha")

	if not await _wait_all_players_on(_semi_alpha, run_id):
		return false

	_shuttle_van.start_fall_back(66.0, 2.2, 1.0)
	_activate_checkpoint(checkpoint_intro_3)
	return true


## Intro Part 3 (no fight): SemiTrailerAlpha -> CargoVanB weave -> ArmoredTruckC -> ConvoyCarrier.
func _run_intro_3(run_id: int) -> bool:
	_set_hud("HIGHWAY INTRO — TRAFFIC WEAVE", "Advance along Semi-Trailer Alpha — Yellow Cargo Van incoming!")

	if not await _wait_vehicle_stop(_shuttle_van, run_id):
		return false

	_cargo_van_b.spawn_and_drive(Vector3(-3.40, 0.0, 52.0), Vector3(-3.40, 0.0, -21.0), 2.6, -1)
	if not await _wait_vehicle_stop(_cargo_van_b, run_id):
		return false

	_semi_alpha.set_transfer_side(VehicleScript.TransferSide.RIGHT)
	_semi_alpha.set_warning(true)
	_set_hud("HIGHWAY INTRO — CAR HOP 1/2", "Cross RIGHT onto the Yellow Cargo Van →")

	if not await _wait_all_players_on(_cargo_van_b, run_id):
		return false

	_semi_alpha.start_fall_back(68.0, 2.4, -0.8)
	_set_hud("HIGHWAY INTRO — LANE WEAVE", "Weaving across lanes — stay centered on the roof!")

	_cargo_van_b.drive_to(Vector3(6.80, 0.0, -23.5), 2.2, 1)
	if not await _wait_vehicle_stop(_cargo_van_b, run_id):
		return false
	_cargo_van_b.drive_to(Vector3(3.46, 0.0, -25.0), 1.4, -1)
	if not await _wait_vehicle_stop(_cargo_van_b, run_id):
		return false

	_armored_truck_c.spawn_and_drive(Vector3(10.44, 0.0, 46.0), Vector3(10.44, 0.0, -25.0), 2.5, -1)
	if not await _wait_vehicle_stop(_armored_truck_c, run_id):
		return false

	_cargo_van_b.set_transfer_side(VehicleScript.TransferSide.RIGHT)
	_cargo_van_b.set_warning(true)
	_set_hud("HIGHWAY INTRO — CAR HOP 2/2", "Cross RIGHT onto the Armored Truck →")

	if not await _wait_all_players_on(_armored_truck_c, run_id):
		return false

	_cargo_van_b.start_fall_back(58.0, 2.3, -1.5)
	_convoy_carrier.spawn_and_drive(Vector3(0.0, 0.0, -112.0), Vector3(0.0, 0.0, -38.0), 3.2, 0)

	_set_hud("HIGHWAY INTRO — APPROACHING BOSS PLATFORM", "Pulling alongside the Heavy Convoy Carrier ↑")
	_armored_truck_c.drive_to(Vector3(10.44, 0.0, -36.0), 2.2, 0)
	if not await _wait_vehicle_stop(_armored_truck_c, run_id):
		return false
	if not await _wait_vehicle_stop(_convoy_carrier, run_id):
		return false

	_armored_truck_c.drive_to(Vector3(9.28, 0.0, -36.0), 0.9, -1)
	if not await _wait_vehicle_stop(_armored_truck_c, run_id):
		return false

	_armored_truck_c.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_armored_truck_c.set_warning(true)
	_set_hud("BOARD BOSS PLATFORM", "← Cross LEFT onto the Heavy Convoy Carrier")

	if not await _wait_all_players_on(_convoy_carrier, run_id):
		return false

	_armored_truck_c.start_fall_back(52.0, 2.3, 1.5)
	_activate_checkpoint(checkpoint_boss_phase_1)
	return true


## Boss Fight Phase 1 (100% -> 75% HP): Starts once players board the Heavy Convoy Carrier!
func _run_boss_phase_1(run_id: int) -> bool:
	_phase_one_cleared = false
	_set_hud("BOSS FIGHT — AGENT RICHARD", "Flanking boss trucks approaching on left and right!")

	if not await _wait_vehicle_stop(_armored_truck_c, run_id):
		return false

	_boss_truck_left.spawn_and_drive(Vector3(-14.8, 0.0, -116.0), Vector3(-14.8, 0.0, -40.0), 2.4, 0)
	_boss_truck_right.spawn_and_drive(Vector3(14.8, 0.0, -116.0), Vector3(14.8, 0.0, -40.0), 2.4, 0)
	if not await _wait_vehicle_stop(_boss_truck_left, run_id):
		return false
	if not await _wait_vehicle_stop(_boss_truck_right, run_id):
		return false

	_set_hud("AGENT RICHARD — PHASE 1", "Drive Richard to 75% HP! Watch for bullets & grenades")
	if _richard_ctrl != null:
		_richard_ctrl.begin_phase_one(_boss_truck_left, _boss_truck_right, _convoy_carrier)

	while _is_valid_run(run_id) and not _phase_one_cleared:
		await get_tree().physics_frame
	if not _is_valid_run(run_id):
		return false

	_activate_checkpoint(checkpoint_phase_1_cleared)
	_set_hud("CHECKPOINT — AGENT RICHARD RETREATED!", "75% HP reached — pursue up the highway convoy!")
	_boss_truck_left.start_fall_back(46.0, 2.4, 0.0)
	_boss_truck_right.start_fall_back(46.0, 2.4, 0.0)
	return true


## Post-Phase-1 Crossings (4 trucks): ConvoyCarrier -> EscortVan1 -> FlatbedTruck2 -> TransitBus3 -> ArenaSemi4.
func _run_post_phase_1_crossings(run_id: int) -> bool:
	if not await _wait_vehicle_stop(_boss_truck_left, run_id):
		return false
	if not await _wait_vehicle_stop(_boss_truck_right, run_id):
		return false

	_set_hud("HIGHWAY PURSUIT — CROSSING 1/4", "Escort Van pulling up on the left!")
	_escort_van_1.spawn_and_drive(Vector3(-9.28, 0.0, 34.0), Vector3(-9.28, 0.0, -38.0), 2.6, 1)
	if not await _wait_vehicle_stop(_escort_van_1, run_id):
		return false

	_convoy_carrier.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_convoy_carrier.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 1/4", "← Cross LEFT onto the Escort Van")
	if not await _wait_all_players_on(_escort_van_1, run_id):
		return false

	_convoy_carrier.start_fall_back(38.0, 2.3, 0.0)
	_set_hud("HIGHWAY PURSUIT — ADVANCING", "Overtaking up the left lane ↑")
	_escort_van_1.drive_to(Vector3(-9.28, 0.0, -52.0), 2.2, 0)
	if not await _wait_vehicle_stop(_escort_van_1, run_id):
		return false
	if not await _wait_vehicle_stop(_convoy_carrier, run_id):
		return false

	# Crossing 2/4: FlatbedTruck2 enters from ahead in center-left lane (-2.10).
	_set_hud("HIGHWAY PURSUIT — CROSSING 2/4", "Box Truck approaching on the right!")
	_flatbed_truck_2.spawn_and_drive(Vector3(-2.10, 0.0, -134.0), Vector3(-2.10, 0.0, -54.0), 2.7, -1)
	if not await _wait_vehicle_stop(_flatbed_truck_2, run_id):
		return false

	_escort_van_1.set_transfer_side(VehicleScript.TransferSide.RIGHT)
	_escort_van_1.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 2/4", "Cross RIGHT onto the Box Truck →")
	if not await _wait_all_players_on(_flatbed_truck_2, run_id):
		return false

	_escort_van_1.start_fall_back(20.0, 2.3, -1.2)
	_set_hud("HIGHWAY PURSUIT — LANE WEAVE", "Cutting right across traffic — stay steady!")
	_flatbed_truck_2.drive_to(Vector3(5.20, 0.0, -60.0), 2.4, 1)
	if not await _wait_vehicle_stop(_flatbed_truck_2, run_id):
		return false
	if not await _wait_vehicle_stop(_escort_van_1, run_id):
		return false

	# Crossing 3/4: TransitBus3 surges up from behind on the left (-2.28).
	_set_hud("HIGHWAY PURSUIT — CROSSING 3/4", "Transit Bus pulling alongside on the left!")
	_transit_bus_3.spawn_and_drive(Vector3(-2.28, 0.0, 16.0), Vector3(-2.28, 0.0, -62.0), 2.6, 1)
	if not await _wait_vehicle_stop(_transit_bus_3, run_id):
		return false

	_flatbed_truck_2.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_flatbed_truck_2.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 3/4", "← Cross LEFT onto the Transit Bus")
	if not await _wait_all_players_on(_transit_bus_3, run_id):
		return false

	_flatbed_truck_2.start_fall_back(16.0, 2.3, 1.2)
	_set_hud("HIGHWAY PURSUIT — OVERTAKING", "Accelerating toward the Heavy Semi ahead ↑")
	_transit_bus_3.drive_to(Vector3(-2.28, 0.0, -74.0), 2.0, 0)
	if not await _wait_vehicle_stop(_transit_bus_3, run_id):
		return false
	if not await _wait_vehicle_stop(_flatbed_truck_2, run_id):
		return false

	# Crossing 4/4: TransitBus3 shifts right (+2.68) so ArenaSemi4 can enter cleanly on the left (-5.50).
	_transit_bus_3.drive_to(Vector3(2.68, 0.0, -74.0), 1.4, 1)
	if not await _wait_vehicle_stop(_transit_bus_3, run_id):
		return false

	_set_hud("HIGHWAY PURSUIT — CROSSING 4/4", "Heavy Semi-Trailer pulling up on the left!")
	_arena_semi_4.spawn_and_drive(Vector3(-5.50, 0.0, -156.0), Vector3(-5.50, 0.0, -76.0), 2.7, 0)
	if not await _wait_vehicle_stop(_arena_semi_4, run_id):
		return false

	_transit_bus_3.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_transit_bus_3.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 4/4", "← Cross LEFT onto the Heavy Semi-Trailer")
	if not await _wait_all_players_on(_arena_semi_4, run_id):
		return false

	_transit_bus_3.start_fall_back(10.0, 2.3, 1.5)
	_activate_checkpoint(checkpoint_shooters_wave)
	return true


## Encounter 1: 3 Action Figure Shooters attack from a truck on the RIGHT.
func _run_shooters_encounter(run_id: int) -> bool:
	_set_hud("AMBUSH ON THE RIGHT!", "Enemy gun truck pulling alongside — watch out!")
	if not await _wait_vehicle_stop(_transit_bus_3, run_id):
		return false

	_shooter_enemy_truck.spawn_and_drive(Vector3(8.60, 0.0, -158.0), Vector3(8.60, 0.0, -76.0), 2.5, 0)
	var wave := _spawn_trooper_squad(
		SHOOTER_SCENE,
		_shooter_enemy_truck,
		_arena_semi_4,
		[
			Vector3(0.0, 0.0, -5.2),
			Vector3(0.0, 0.0, 0.0),
			Vector3(0.0, 0.0, 5.2),
		],
		[2.3, 2.9, 3.5],
	)

	if not await _wait_vehicle_stop(_shooter_enemy_truck, run_id):
		return false

	_set_hud("AMBUSH — 3 SHOOTERS (RIGHT)", "Take out all 3 shooters on the enemy truck!")
	if not await _wait_troopers_cleared(wave, run_id):
		return false

	_clear_enemy_projectiles()
	_shooter_enemy_truck.start_fall_back(12.0, 2.3, 1.0)
	_activate_checkpoint(checkpoint_shooters_cleared)
	_set_hud("AMBUSH CLEARED!", "Enemy gun truck retreating — keep pushing forward!")
	return true


## Mid Crossings (3 trucks): ArenaSemi4 -> WeaveVan5 -> ShuttleTruck6 -> ArenaCarrier7.
func _run_mid_crossings(run_id: int) -> bool:
	if not await _wait_vehicle_stop(_shooter_enemy_truck, run_id):
		return false

	# Crossing 1/3: WeaveVan5 enters from behind on the right (+2.48).
	_set_hud("HIGHWAY PURSUIT — CROSSING 1/3", "Cargo Van pulling up on the right!")
	_weave_van_5.spawn_and_drive(Vector3(2.48, 0.0, -6.0), Vector3(2.48, 0.0, -78.0), 2.5, -1)
	if not await _wait_vehicle_stop(_weave_van_5, run_id):
		return false

	_arena_semi_4.set_transfer_side(VehicleScript.TransferSide.RIGHT)
	_arena_semi_4.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 1/3", "Cross RIGHT onto the Cargo Van →")
	if not await _wait_all_players_on(_weave_van_5, run_id):
		return false

	_arena_semi_4.start_fall_back(10.0, 2.3, -1.2)
	_set_hud("HIGHWAY PURSUIT — LANE WEAVE", "Weaving into the fast right lane — hold tight!")
	_weave_van_5.drive_to(Vector3(10.0, 0.0, -86.0), 2.4, 1)
	if not await _wait_vehicle_stop(_weave_van_5, run_id):
		return false
	if not await _wait_vehicle_stop(_arena_semi_4, run_id):
		return false

	# Crossing 2/3: ShuttleTruck6 enters from behind on the left (+3.02).
	_set_hud("HIGHWAY PURSUIT — CROSSING 2/3", "Armored Shuttle pulling up on the left!")
	_shuttle_truck_6.spawn_and_drive(Vector3(3.02, 0.0, -14.0), Vector3(3.02, 0.0, -88.0), 2.6, 1)
	if not await _wait_vehicle_stop(_shuttle_truck_6, run_id):
		return false

	_weave_van_5.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_weave_van_5.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 2/3", "← Cross LEFT onto the Armored Shuttle")
	if not await _wait_all_players_on(_shuttle_truck_6, run_id):
		return false

	_weave_van_5.start_fall_back(-10.0, 2.3, 1.2)
	_set_hud("HIGHWAY PURSUIT — OVERTAKING", "Closing in on the Lead Hauler ahead ↑")
	_shuttle_truck_6.drive_to(Vector3(3.02, 0.0, -106.0), 2.4, 0)
	if not await _wait_vehicle_stop(_shuttle_truck_6, run_id):
		return false
	if not await _wait_vehicle_stop(_weave_van_5, run_id):
		return false

	# Crossing 3/3: ShuttleTruck6 shifts left (-2.38) so ArenaCarrier7 enters cleanly on the right (+5.50).
	_shuttle_truck_6.drive_to(Vector3(-2.38, 0.0, -106.0), 1.4, -1)
	if not await _wait_vehicle_stop(_shuttle_truck_6, run_id):
		return false

	_set_hud("HIGHWAY PURSUIT — CROSSING 3/3", "Lead Hauler pulling alongside on the right!")
	_arena_carrier_7.spawn_and_drive(Vector3(5.50, 0.0, -186.0), Vector3(5.50, 0.0, -108.0), 2.7, 0)
	if not await _wait_vehicle_stop(_arena_carrier_7, run_id):
		return false

	_shuttle_truck_6.set_transfer_side(VehicleScript.TransferSide.RIGHT)
	_shuttle_truck_6.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 3/3", "Cross RIGHT onto the Lead Hauler →")
	if not await _wait_all_players_on(_arena_carrier_7, run_id):
		return false

	_shuttle_truck_6.start_fall_back(-24.0, 2.3, -1.5)
	_activate_checkpoint(checkpoint_grenadiers_wave)
	return true


## Encounter 2: 2 Action Figure Grenadiers attack from a truck on the LEFT.
func _run_grenadiers_encounter(run_id: int) -> bool:
	_set_hud("GRENADIER TRUCK ON THE LEFT!", "Incoming bombardier truck — dodge the red blast zones!")
	if not await _wait_vehicle_stop(_shuttle_truck_6, run_id):
		return false

	_grenadier_enemy_truck.spawn_and_drive(Vector3(-8.60, 0.0, -188.0), Vector3(-8.60, 0.0, -108.0), 2.5, 0)
	var wave := _spawn_trooper_squad(
		GRENADIER_SCENE,
		_grenadier_enemy_truck,
		_arena_carrier_7,
		[
			Vector3(0.0, 0.0, -3.6),
			Vector3(0.0, 0.0, 3.6),
		],
		[2.3, 3.3],
	)

	if not await _wait_vehicle_stop(_grenadier_enemy_truck, run_id):
		return false

	_set_hud("AMBUSH — 2 GRENADIERS (LEFT)", "Eliminate both grenadiers on the left truck!")
	if not await _wait_troopers_cleared(wave, run_id):
		return false

	_clear_enemy_projectiles()
	_grenadier_enemy_truck.start_fall_back(-20.0, 2.3, -1.0)
	_set_hud("GRENADIERS CLEARED!", "Agent Richard is closing in ahead — brace for Phase 2!")
	return true


## Transition from ArenaCarrier7 onto Phase2TruckA centered for the Phase 2 boss arena.
func _run_transition_to_phase_2(run_id: int) -> bool:
	if not await _wait_vehicle_stop(_grenadier_enemy_truck, run_id):
		return false

	_set_hud("APPROACHING BOSS PHASE 2", "Blue Box Truck pulling alongside on the left!")
	_phase2_truck_a.spawn_and_drive(Vector3(-2.58, 0.0, -186.0), Vector3(-2.58, 0.0, -108.0), 2.5, 0)
	if not await _wait_vehicle_stop(_phase2_truck_a, run_id):
		return false

	_arena_carrier_7.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_arena_carrier_7.set_warning(true)
	_set_hud("BOARD PHASE 2 TRUCK", "← Cross LEFT onto the Blue Box Truck")
	if not await _wait_all_players_on(_phase2_truck_a, run_id):
		return false

	_arena_carrier_7.start_fall_back(-30.0, 2.3, 1.5)
	_set_hud("BOSS PHASE 2 INCOMING", "Pulling into the express lanes — Agent Richard spotted ahead!")
	_phase2_truck_a.drive_to(Vector3(PHASE2_LEFT_X, 0.0, PHASE2_Z), 2.4, 0)
	if not await _wait_vehicle_stop(_phase2_truck_a, run_id):
		return false
	if not await _wait_vehicle_stop(_arena_carrier_7, run_id):
		return false

	_activate_checkpoint(checkpoint_boss_phase_2)
	return true


## Boss Fight Phase 2 (75% -> 50% HP):
## Same Agent Richard fight (left/right flanking trucks, sky jumps, bullets & grenades),
## PLUS players must regularly cross between alternating trucks before their current truck
## drops off the bottom of the screen and kills anyone left behind!
func _run_boss_phase_2(run_id: int) -> bool:
	_phase_two_cleared = false
	var current_truck: VehicleScript = _phase2_truck_a
	var next_truck: VehicleScript = _phase2_truck_b

	_set_hud("BOSS FIGHT — AGENT RICHARD RETURNS!", "Flanking boss trucks closing in — stay ready to switch trucks!")
	_boss_truck_left.spawn_and_drive(Vector3(-15.6, 0.0, PHASE2_Z - 78.0), Vector3(-15.6, 0.0, PHASE2_Z - 1.0), 2.4, 0)
	_boss_truck_right.spawn_and_drive(Vector3(15.6, 0.0, PHASE2_Z - 78.0), Vector3(15.6, 0.0, PHASE2_Z - 1.0), 2.4, 0)
	if not await _wait_vehicle_stop(_boss_truck_left, run_id):
		return false
	if not await _wait_vehicle_stop(_boss_truck_right, run_id):
		return false

	if _richard_ctrl != null:
		_richard_ctrl.begin_phase_two(_boss_truck_left, _boss_truck_right, current_truck)

	var cycle := 0
	while _is_valid_run(run_id) and not _phase_two_cleared:
		# 1) Fight window on the current truck.
		_set_hud(
			"AGENT RICHARD — PHASE 2 (75% → 50%)",
			"Fight Richard! Watch for the next truck to pull alongside",
		)
		var wait_elapsed := 0.0
		while wait_elapsed < phase_2_fight_window_sec and _is_valid_run(run_id) and not _phase_two_cleared:
			await get_tree().physics_frame
			wait_elapsed += get_physics_process_delta_time()
		if not _is_valid_run(run_id) or _phase_two_cleared:
			break

		# Make sure the incoming truck has completely finished any prior fall-back.
		while next_truck.is_moving() and _is_valid_run(run_id) and not _phase_two_cleared:
			await get_tree().physics_frame
		if not _is_valid_run(run_id) or _phase_two_cleared:
			break

		# 2) Bring the alternating truck alongside in the empty adjacent center lane.
		var crossing_right := (current_truck == _phase2_truck_a)
		var next_x := PHASE2_RIGHT_X if crossing_right else PHASE2_LEFT_X
		var spawn_z := (PHASE2_Z + 74.0) if (cycle % 2 == 0) else (PHASE2_Z - 78.0)
		var turn_sig := -1 if crossing_right else 1
		var side_word := "RIGHT" if crossing_right else "LEFT"

		_set_hud(
			"TRUCK APPROACHING ON THE %s!" % side_word,
			"Get ready to cross %s while fighting Agent Richard!" % side_word,
		)
		next_truck.spawn_and_drive(Vector3(next_x, 0.0, spawn_z), Vector3(next_x, 0.0, PHASE2_Z), 2.3, turn_sig)

		while next_truck.is_moving() and _is_valid_run(run_id) and not _phase_two_cleared:
			await get_tree().physics_frame
		if not _is_valid_run(run_id) or _phase_two_cleared:
			break

		# 3) Timed crossing countdown — players MUST cross before their current truck drops back!
		var transfer_side := VehicleScript.TransferSide.RIGHT if crossing_right else VehicleScript.TransferSide.LEFT
		current_truck.set_transfer_side(transfer_side)
		current_truck.set_warning(true)

		var time_left := phase_2_cross_time_limit_sec
		var crossed_in_time := false
		while time_left > 0.0 and _is_valid_run(run_id) and not _phase_two_cleared:
			if _all_living_players_on(next_truck):
				crossed_in_time = true
				break
			var arrow_hint := "Cross RIGHT onto the adjacent truck! →" if crossing_right else "← Cross LEFT onto the adjacent truck!"
			_set_hud(
				"CROSS %s NOW! (%.1fs)" % [side_word, time_left],
				arrow_hint + " Your truck is about to drop out!",
			)
			await get_tree().physics_frame
			time_left -= get_physics_process_delta_time()

		if not _is_valid_run(run_id):
			return false
		if _phase_two_cleared:
			current_truck.set_transfer_side(VehicleScript.TransferSide.NONE)
			current_truck.set_warning(false)
			break

		# 4) Either they crossed safely, or the truck brakes and drops off-screen!
		var drift_away := -0.8 if crossing_right else 0.8
		if crossed_in_time:
			current_truck.start_fall_back(PHASE2_Z + 62.0, 2.3, drift_away)
			var old_truck := current_truck
			current_truck = next_truck
			next_truck = old_truck
			if _richard_ctrl != null:
				_richard_ctrl.set_player_truck(current_truck)
			cycle += 1
			continue

		# Timed out! Hold camera at the highway arena so the truck visibly drops off the bottom of the screen.
		current_truck.start_fall_back(PHASE2_Z + 52.0, 2.2, 0.0)
		current_truck.set_warning(true)
		_set_camera_hold(true)
		_set_hud("TOO SLOW — TRUCK DROPPING BACK!", "Truck going off-screen!")

		var clutched := false
		while _is_valid_run(run_id) and not _phase_two_cleared:
			if _all_living_players_on(next_truck):
				clutched = true
				break
			var truck_z := current_truck.get_deck_world_position().z
			if truck_z >= PHASE2_OFFSCREEN_DEATH_Z or not current_truck.is_moving():
				_kill_stranded_players(next_truck)
				return false
			await get_tree().physics_frame

		_set_camera_hold(false)
		if not _is_valid_run(run_id):
			return false
		if clutched:
			var old_truck := current_truck
			current_truck = next_truck
			next_truck = old_truck
			if _richard_ctrl != null:
				_richard_ctrl.set_player_truck(current_truck)
			cycle += 1

	if not _is_valid_run(run_id):
		return false

	# Phase 2 cleared at 50% HP! Ensure no player gets stranded if they were mid-crossing.
	_set_camera_hold(false)
	current_truck.set_transfer_side(VehicleScript.TransferSide.NONE)
	current_truck.set_warning(false)
	_boss_truck_left.start_fall_back(PHASE2_Z + 64.0, 2.4, 0.0)
	_boss_truck_right.start_fall_back(PHASE2_Z + 64.0, 2.4, 0.0)

	if next_truck.visible:
		if _all_living_players_on(next_truck):
			var old_t := current_truck
			current_truck = next_truck
			next_truck = old_t
		elif not _all_living_players_on(current_truck):
			# Players are split across both docked trucks — wait for them to regroup on `current_truck`.
			var regroup_side := VehicleScript.TransferSide.LEFT if current_truck == _phase2_truck_a else VehicleScript.TransferSide.RIGHT
			next_truck.set_transfer_side(regroup_side)
			next_truck.set_warning(true)
			_set_hud("AGENT RICHARD RETREATED!", "Regroup onto the safe truck before the spare drops back!")
			if not await _wait_all_players_on(current_truck, run_id):
				return false
		var spare_drift := 0.8 if next_truck == _phase2_truck_b else -0.8
		next_truck.start_fall_back(PHASE2_Z + 58.0, 2.3, spare_drift)

	_phase2_exit_truck = current_truck
	_activate_checkpoint(checkpoint_phase_2_cleared)
	_set_hud("CHECKPOINT — PHASE 2 CLEARED (50% HP)!", "Agent Richard retreated again — pursue further up the highway!")
	return true


## Post-Phase-2 Crossings (2 trucks): Phase2TruckA/B -> PursuitBus8 -> MechArenaCarrier9.
func _run_post_phase_2_crossings(run_id: int) -> bool:
	var start_truck: VehicleScript = _phase2_exit_truck if _phase2_exit_truck != null else _phase2_truck_a
	var spare_truck: VehicleScript = _phase2_truck_b if start_truck == _phase2_truck_a else _phase2_truck_a

	if not await _wait_vehicle_stop(_boss_truck_left, run_id):
		return false
	if not await _wait_vehicle_stop(_boss_truck_right, run_id):
		return false
	if not await _wait_vehicle_stop(spare_truck, run_id):
		return false

	# Crossing 1/2: PursuitBus8 (width 7.0) docks alongside whichever Phase 2 truck players ended on.
	var on_left_truck := (start_truck == _phase2_truck_a)
	var bus_dock_x := 3.74 if on_left_truck else -3.74
	var bus_turn_sig := -1 if on_left_truck else 1
	var side_word := "RIGHT" if on_left_truck else "LEFT"

	_set_hud("HIGHWAY PURSUIT — CROSSING 1/2", "Express Bus pulling alongside on the %s!" % side_word.to_lower())
	_pursuit_bus_8.spawn_and_drive(Vector3(bus_dock_x, 0.0, PHASE2_Z + 74.0), Vector3(bus_dock_x, 0.0, PHASE2_Z), 2.5, bus_turn_sig)
	if not await _wait_vehicle_stop(_pursuit_bus_8, run_id):
		return false

	start_truck.set_transfer_side(VehicleScript.TransferSide.RIGHT if on_left_truck else VehicleScript.TransferSide.LEFT)
	start_truck.set_warning(true)
	var arrow_hint := "Cross RIGHT onto the Express Bus →" if on_left_truck else "← Cross LEFT onto the Express Bus"
	_set_hud("HIGHWAY PURSUIT — CROSSING 1/2", arrow_hint)
	if not await _wait_all_players_on(_pursuit_bus_8, run_id):
		return false

	start_truck.start_fall_back(PHASE2_Z + 68.0, 2.3, -1.2 if on_left_truck else 1.2)
	_set_hud("HIGHWAY PURSUIT — ADVANCING", "Overtaking toward the Heavy Carrier ahead ↑")
	_pursuit_bus_8.drive_to(Vector3(bus_dock_x, 0.0, -142.0), 2.1, 0)
	if not await _wait_vehicle_stop(_pursuit_bus_8, run_id):
		return false
	if not await _wait_vehicle_stop(start_truck, run_id):
		return false

	# Weave into right-side docking lane (+9.18) so MechArenaCarrier9 (width 10.4 at X = 0) docks cleanly with 0.48 m gap.
	_pursuit_bus_8.drive_to(Vector3(9.18, 0.0, -150.0), 1.8, 1)
	if not await _wait_vehicle_stop(_pursuit_bus_8, run_id):
		return false

	# Crossing 2/2: MechArenaCarrier9 enters from ahead in center lane (0.0, 0.0, -152.0).
	_set_hud("HIGHWAY PURSUIT — CROSSING 2/2", "Heavy Armored Carrier pulling alongside on the left!")
	_mech_arena_carrier_9.spawn_and_drive(Vector3(0.0, 0.0, -230.0), Vector3(0.0, 0.0, MECH_ARENA_Z), 2.7, 0)
	if not await _wait_vehicle_stop(_mech_arena_carrier_9, run_id):
		return false

	_pursuit_bus_8.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_pursuit_bus_8.set_warning(true)
	_set_hud("HIGHWAY PURSUIT — CROSSING 2/2", "← Cross LEFT onto the Heavy Armored Carrier")
	if not await _wait_all_players_on(_mech_arena_carrier_9, run_id):
		return false

	_pursuit_bus_8.start_fall_back(-76.0, 2.3, 1.5)
	_activate_checkpoint(checkpoint_winged_mech)
	return true


## Flying Winged Mech encounter on MechArenaCarrier9.
func _run_winged_mech_encounter(run_id: int) -> bool:
	_set_hud("AERIAL THREAT DETECTED!", "Flying Winged Mech diving in from ahead!")
	if not await _wait_vehicle_stop(_pursuit_bus_8, run_id):
		return false

	var mech := _spawn_winged_mech(Vector3(0.0, 7.5, MECH_ARENA_Z - 22.0))
	if mech == null:
		return true

	_set_hud("WINGED MECH INTERCEPT", "Shoot down the flying Winged Mech! Dodge its minigun & jet dashes")
	while _is_valid_run(run_id):
		if not is_instance_valid(mech) or not mech.is_alive():
			break
		if mech.health != null and not mech.health.is_alive():
			break
		await get_tree().physics_frame

	if not _is_valid_run(run_id):
		return false

	_clear_enemy_projectiles()
	_set_hud("WINGED MECH DESTROYED!", "Skies clear — checkpoint saved!")
	if not await _wait_seconds(1.2, run_id):
		return false
	_activate_checkpoint(checkpoint_winged_mech_cleared)
	return true


## Transition from MechArenaCarrier9 onto the colossal Phase 3 Megacarrier platform.
func _run_transition_to_phase_3(run_id: int) -> bool:
	_set_hud("MEGA TRANSPORT AHEAD!", "Pulling right to dock alongside the Heavy Megacarrier!")
	_mech_arena_carrier_9.drive_to(Vector3(15.68, 0.0, -168.0), 2.4, 1)
	if not await _wait_vehicle_stop(_mech_arena_carrier_9, run_id):
		return false

	_phase3_mega_platform.spawn_and_drive(Vector3(0.0, 0.0, -268.0), Vector3(0.0, 0.0, PHASE3_Z), 2.8, 0)
	if not await _wait_vehicle_stop(_phase3_mega_platform, run_id):
		return false

	_mech_arena_carrier_9.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_mech_arena_carrier_9.set_warning(true)
	_set_hud("BOARD THE MEGACARRIER", "← Cross LEFT onto the Heavy Megacarrier Platform")
	if not await _wait_all_players_on(_phase3_mega_platform, run_id):
		return false

	_mech_arena_carrier_9.start_fall_back(-92.0, 2.4, 0.0)
	_activate_checkpoint(checkpoint_boss_phase_3)
	return true


## Boss Fight Phase 3 (50% -> 25% HP):
## Agent Richard drops directly onto the same huge Megacarrier platform as the players!
## Alongside bullets & grenades, he now performs katana-boss-style melee dashes (1 or 2 chained dashes).
func _run_boss_phase_3(run_id: int) -> bool:
	_phase_three_cleared = false
	_set_hud("BOSS FIGHT — AGENT RICHARD PHASE 3", "He's dropping onto YOUR deck — watch out for red dash lanes!")
	if not await _wait_vehicle_stop(_mech_arena_carrier_9, run_id):
		return false

	if _richard_ctrl != null:
		_richard_ctrl.begin_phase_three(_phase3_mega_platform)

	_set_hud(
		"AGENT RICHARD — PHASE 3 (50% → 25%)",
		"Step out of his red dash lanes! Watch for double dashes, bullets & grenades",
	)
	while _is_valid_run(run_id) and not _phase_three_cleared:
		await get_tree().physics_frame
	if not _is_valid_run(run_id):
		return false

	_activate_checkpoint(checkpoint_phase_3_cleared)
	_set_hud("CHECKPOINT — PHASE 3 CLEARED (25% HP)!", "Brief breather — 2 trucks ahead before the final showdown!")
	return true


## Small Break — 2 Truck Crossings after Phase 3: Phase3MegaPlatform -> BreakTruck10 -> FinaleTruckA.
func _run_post_phase_3_break_crossings(run_id: int) -> bool:
	# Crossing 1/2: BreakTruck10 pulls up on the right (+13.68) alongside Phase3MegaPlatform (right edge +10.00).
	_set_hud("FINAL PURSUIT — CROSSING 1/2", "Catch your breath! Armored Escort pulling up on the right")
	_break_truck_10.spawn_and_drive(Vector3(13.68, 0.0, PHASE3_Z + 68.0), Vector3(13.68, 0.0, PHASE3_Z), 2.6, -1)
	if not await _wait_vehicle_stop(_break_truck_10, run_id):
		return false

	_phase3_mega_platform.set_transfer_side(VehicleScript.TransferSide.RIGHT)
	_phase3_mega_platform.set_warning(true)
	_set_hud("FINAL PURSUIT — CROSSING 1/2", "Cross RIGHT onto the Armored Escort →")
	if not await _wait_all_players_on(_break_truck_10, run_id):
		return false

	_phase3_mega_platform.start_fall_back(-92.0, 2.5, 0.0)
	_set_hud("FINAL PURSUIT — OVERTAKING", "Advancing up the expressway toward the lead convoy ↑")
	_break_truck_10.drive_to(Vector3(13.68, 0.0, -196.0), 2.3, 0)
	if not await _wait_vehicle_stop(_break_truck_10, run_id):
		return false
	if not await _wait_vehicle_stop(_phase3_mega_platform, run_id):
		return false

	# Shift left to +3.44 so FinaleTruckA (-3.94, right edge -0.24) docks cleanly with exact 0.48 m gap.
	_break_truck_10.drive_to(Vector3(3.44, 0.0, PHASE4_START_Z), 1.9, -1)
	if not await _wait_vehicle_stop(_break_truck_10, run_id):
		return false

	# Crossing 2/2: FinaleTruckA enters from ahead at -3.94.
	_set_hud("FINAL PURSUIT — CROSSING 2/2", "Lead Convoy Truck pulling alongside on the left!")
	_finale_truck_a.spawn_and_drive(Vector3(PHASE4_LEFT_X, 0.0, PHASE4_START_Z - 78.0), Vector3(PHASE4_LEFT_X, 0.0, PHASE4_START_Z), 2.6, 0)
	if not await _wait_vehicle_stop(_finale_truck_a, run_id):
		return false

	_break_truck_10.set_transfer_side(VehicleScript.TransferSide.LEFT)
	_break_truck_10.set_warning(true)
	_set_hud("FINAL PURSUIT — CROSSING 2/2", "← Cross LEFT onto the Lead Convoy Truck")
	if not await _wait_all_players_on(_finale_truck_a, run_id):
		return false

	_break_truck_10.start_fall_back(PHASE4_START_Z + 76.0, 2.3, 1.5)
	_activate_checkpoint(checkpoint_boss_phase_4)
	return true


## Boss Fight Phase 4 (25% -> 0% HP) — Final Rolling Highway Showdown!
## Combines EVERYTHING:
##   - Players and flanking boss trucks surge FORWARD up the highway every cycle.
##   - Alternating trucks dock ahead/alongside on a strict timer; failing to cross drops the
##     abandoned truck off the bottom of the screen and kills anyone left behind.
##   - Agent Richard attacks from both moving flanking trucks (bullets + tracking grenades)
##     AND drops onto the players' moving truck for single/double melee dashes until 0% HP!
func _run_boss_phase_4(run_id: int) -> bool:
	_boss_defeated = false
	var current_truck: VehicleScript = _finale_truck_a
	var next_truck: VehicleScript = _finale_truck_b
	var convoy_z := PHASE4_START_Z

	_set_hud("FINAL PHASE — AGENT RICHARD (25% → 0%)", "Flanking trucks closing in — keep moving forward to survive!")
	if not await _wait_vehicle_stop(_break_truck_10, run_id):
		return false

	_boss_truck_left.spawn_and_drive(Vector3(-15.8, 0.0, convoy_z - 78.0), Vector3(-15.8, 0.0, convoy_z - 1.0), 2.4, 0)
	_boss_truck_right.spawn_and_drive(Vector3(15.8, 0.0, convoy_z - 78.0), Vector3(15.8, 0.0, convoy_z - 1.0), 2.4, 0)
	if not await _wait_vehicle_stop(_boss_truck_left, run_id):
		return false
	if not await _wait_vehicle_stop(_boss_truck_right, run_id):
		return false

	if _richard_ctrl != null:
		_richard_ctrl.begin_phase_four(_boss_truck_left, _boss_truck_right, _finale_truck_a, _finale_truck_b)

	while _is_valid_run(run_id) and not _boss_defeated:
		# 1) Surge FORWARD up the highway (-Z) with both flanking boss trucks keeping pace!
		var next_z := convoy_z - PHASE4_FORWARD_STEP_Z
		var on_left := (current_truck == _finale_truck_a)
		var cur_x := PHASE4_LEFT_X if on_left else PHASE4_RIGHT_X
		var next_x := PHASE4_RIGHT_X if on_left else PHASE4_LEFT_X
		var side_word := "RIGHT" if on_left else "LEFT"
		var turn_sig := -1 if on_left else 1

		if _richard_ctrl != null:
			_richard_ctrl.set_crossing_imminent(false)

		_set_hud(
			"FINAL PHASE — KEEP MOVING! (25% → 0%)",
			"Surging forward ↑ Fight Richard while the next truck approaches on the %s!" % side_word.to_lower(),
		)
		current_truck.drive_to(Vector3(cur_x, 0.0, next_z), phase_4_surge_sec, 0)
		_boss_truck_left.drive_to(Vector3(-15.8, 0.0, next_z - 1.0), phase_4_surge_sec, 0)
		_boss_truck_right.drive_to(Vector3(15.8, 0.0, next_z - 1.0), phase_4_surge_sec, 0)

		# Halfway through the forward surge (once next_truck finished falling back), bring next_truck in from ahead!
		var surge_elapsed := 0.0
		var next_spawned := false
		while _is_valid_run(run_id) and not _boss_defeated:
			if not next_spawned and surge_elapsed >= phase_4_surge_sec * 0.48 and not next_truck.is_moving():
				next_spawned = true
				next_truck.spawn_and_drive(Vector3(next_x, 0.0, next_z - 76.0), Vector3(next_x, 0.0, next_z), 2.4, turn_sig)
			if not current_truck.is_moving() and next_spawned and not next_truck.is_moving():
				break
			await get_tree().physics_frame
			surge_elapsed += get_physics_process_delta_time()

		if not _is_valid_run(run_id) or _boss_defeated:
			break

		# 2) Timed Crossing Window — cross onto next_truck before current_truck drops off-screen!
		if _richard_ctrl != null:
			_richard_ctrl.set_crossing_imminent(true)
		var transfer_side := VehicleScript.TransferSide.RIGHT if on_left else VehicleScript.TransferSide.LEFT
		current_truck.set_transfer_side(transfer_side)
		current_truck.set_warning(true)

		var time_left := phase_4_cross_time_limit_sec
		var crossed_in_time := false
		while time_left > 0.0 and _is_valid_run(run_id) and not _boss_defeated:
			if _all_living_players_on(next_truck):
				crossed_in_time = true
				break
			var arrow_hint := "Cross RIGHT onto the next truck! →" if on_left else "← Cross LEFT onto the next truck!"
			_set_hud(
				"CROSS %s NOW! (%.1fs)" % [side_word, time_left],
				arrow_hint + " Your truck is dropping off-screen!",
			)
			await get_tree().physics_frame
			time_left -= get_physics_process_delta_time()

		if not _is_valid_run(run_id):
			return false
		if _boss_defeated:
			current_truck.set_transfer_side(VehicleScript.TransferSide.NONE)
			current_truck.set_warning(false)
			break

		var drift_away := -0.8 if on_left else 0.8
		if crossed_in_time:
			current_truck.start_fall_back(next_z + 64.0, 2.2, drift_away)
			var old_truck := current_truck
			current_truck = next_truck
			next_truck = old_truck
			convoy_z = next_z
			if _richard_ctrl != null:
				_richard_ctrl.set_player_truck(current_truck)
			continue

		# 3) Timed out! Hold camera at next_z so the abandoned truck visibly slides off the bottom of the screen!
		current_truck.start_fall_back(next_z + 52.0, 2.2, 0.0)
		current_truck.set_warning(true)
		_set_camera_hold(true)
		_set_hud("TOO SLOW — TRUCK DROPPING OUT!", "Truck going off-screen!")

		var clutched := false
		var offscreen_z := next_z + 17.5
		while _is_valid_run(run_id) and not _boss_defeated:
			if _all_living_players_on(next_truck):
				clutched = true
				break
			var truck_z := current_truck.get_deck_world_position().z
			if truck_z >= offscreen_z or not current_truck.is_moving():
				_kill_stranded_players(next_truck)
				return false
			await get_tree().physics_frame

		_set_camera_hold(false)
		if not _is_valid_run(run_id):
			return false
		if clutched:
			var old_truck := current_truck
			current_truck = next_truck
			next_truck = old_truck
			convoy_z = next_z
			if _richard_ctrl != null:
				_richard_ctrl.set_player_truck(current_truck)

	if not _is_valid_run(run_id):
		return false

	# Boss Defeated (0% HP)! Celebrate and trigger LevelSucceeded!
	_set_camera_hold(false)
	current_truck.set_transfer_side(VehicleScript.TransferSide.NONE)
	current_truck.set_warning(false)
	if next_truck.visible:
		next_truck.set_transfer_side(VehicleScript.TransferSide.NONE)
		next_truck.set_warning(false)

	_set_hud("VICTORY — AGENT RICHARD DEFEATED!", "The highway convoy is yours!")
	if not await _wait_seconds(1.8, run_id):
		return false

	# Retire flanking trucks after letting players see Richard's defeat animation.
	var cur_z := current_truck.get_deck_world_position().z
	_boss_truck_left.start_fall_back(cur_z + 68.0, 2.4, 0.0)
	_boss_truck_right.start_fall_back(cur_z + 68.0, 2.4, 0.0)
	if not await _wait_seconds(1.2, run_id):
		return false

	if level_finished_event != null:
		level_finished_event.trigger()
	return true


func _spawn_winged_mech(spawn_pos: Vector3) -> EnemyLocal:
	var parent_node: Node = self
	var world := get_tree().current_scene
	if world != null:
		var enemies_node := world.get_node_or_null(^"Enemies")
		if enemies_node != null:
			parent_node = enemies_node

	var mech := WINGED_MECH_SCENE.instantiate() as EnemyLocal
	if mech == null:
		return null
	parent_node.add_child(mech)
	mech.global_position = spawn_pos
	mech.rotation.y = PI
	if mech.health != null:
		mech.health.max_hp = winged_mech_hp
		mech.health.reset_to_full()
	var bar := mech.get_node_or_null("EnemyHealthBar3D") as EnemyHealthBar3D
	if bar != null:
		bar.always_visible = true
	mech.is_offensive = true
	_spawned_troopers.append(mech)
	return mech


# ---- Trooper Squad Helpers ----

func _spawn_trooper_squad(
	scene: PackedScene,
	host_truck: VehicleScript,
	player_truck: VehicleScript,
	offsets: Array[Vector3],
	delays: Array[float],
) -> Array[EnemyLocal]:
	var wave: Array[EnemyLocal] = []
	var parent_node: Node = self
	var world := get_tree().current_scene
	if world != null:
		var enemies_node := world.get_node_or_null(^"Enemies")
		if enemies_node != null:
			parent_node = enemies_node

	for i in offsets.size():
		var trooper := scene.instantiate() as EnemyLocal
		if trooper == null:
			continue
		parent_node.add_child(trooper)
		var ctrl := trooper.get_node_or_null("HighwayTrooperController") as TrooperCtrlScript
		var delay := delays[i] if i < delays.size() else 0.8 + i * 0.5
		if ctrl != null:
			ctrl.deploy_on_truck(host_truck, offsets[i], player_truck, delay)
		_spawned_troopers.append(trooper)
		wave.append(trooper)
	return wave


func _wait_troopers_cleared(wave: Array[EnemyLocal], run_id: int) -> bool:
	while _is_valid_run(run_id):
		var alive_count := 0
		for trooper in wave:
			if not is_instance_valid(trooper):
				continue
			var ctrl := trooper.get_node_or_null("HighwayTrooperController") as TrooperCtrlScript
			if ctrl != null and ctrl.is_trooper_alive():
				alive_count += 1
		if alive_count == 0:
			return true
		await get_tree().physics_frame
	return false


func _clear_spawned_troopers() -> void:
	for trooper in _spawned_troopers:
		if is_instance_valid(trooper):
			trooper.queue_free()
	_spawned_troopers.clear()


func _clear_enemy_projectiles() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(Checkpoint.ENEMY_PROJECTILE_GROUP):
		if is_instance_valid(node):
			node.queue_free()


# ---- Visual Markers & Lightweight HUD ----

func _build_finish_pad() -> void:
	_finish_pad = Node3D.new()
	_finish_pad.name = "FinishPad"
	_finish_pad.position = Vector3(0.0, 0.03, -6.4)
	_finish_pad.visible = false

	_finish_pad_mat = StandardMaterial3D.new()
	_finish_pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_finish_pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_finish_pad_mat.albedo_color = Color(0.28, 1.55, 0.82, 0.55)

	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(5.6, 0.04, 3.8)
	pad_mesh.material = _finish_pad_mat
	var pad := MeshInstance3D.new()
	pad.mesh = pad_mesh
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_finish_pad.add_child(pad)

	var label := Label3D.new()
	label.text = "CONTINUE / FINISH"
	label.font = UI_FONT
	label.font_size = 72
	label.pixel_size = 0.01
	label.modulate = Color(0.85, 1.0, 0.92)
	label.outline_size = 14
	label.rotation.x = -PI * 0.5
	label.position = Vector3(0.0, 0.06, 0.0)
	_finish_pad.add_child(label)

	_phase3_mega_platform.body.add_child(_finish_pad)


func _mount_finish_pad_on(truck: VehicleScript, z_offset: float = -6.2) -> void:
	if _finish_pad == null or truck == null or truck.body == null:
		return
	var current_parent := _finish_pad.get_parent()
	if current_parent != truck.body:
		if current_parent != null:
			current_parent.remove_child(_finish_pad)
		truck.body.add_child(_finish_pad)
	_finish_pad.position = Vector3(0.0, 0.03, z_offset)


func _build_section_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HighwaySectionHud"
	_hud_layer.layer = 5
	add_child(_hud_layer)

	# Bottom-center banner so it never overlaps the top-center BossHealthBar.
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = -460.0
	vbox.offset_right = 460.0
	vbox.offset_top = -108.0
	vbox.offset_bottom = -18.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(vbox)

	_section_title_label = Label.new()
	_section_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_section_title_label.add_theme_font_override("font", UI_FONT)
	_section_title_label.add_theme_font_size_override("font_size", 32)
	_section_title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48))
	_section_title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12))
	_section_title_label.add_theme_constant_override("outline_size", 10)
	vbox.add_child(_section_title_label)

	_section_hint_label = Label.new()
	_section_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_section_hint_label.add_theme_font_override("font", UI_FONT)
	_section_hint_label.add_theme_font_size_override("font_size", 22)
	_section_hint_label.add_theme_color_override("font_color", Color(0.75, 0.96, 1.0))
	_section_hint_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12))
	_section_hint_label.add_theme_constant_override("outline_size", 8)
	vbox.add_child(_section_hint_label)


func _set_hud(title: String, hint: String) -> void:
	if _section_title_label != null:
		_section_title_label.text = title
	if _section_hint_label != null:
		_section_hint_label.text = hint


func _animate_markers(_delta: float) -> void:
	if _finish_pad_mat != null and _finish_pad != null and _finish_pad.visible:
		var pulse := 0.45 + 0.30 * sin(Time.get_ticks_msec() * 0.006)
		_finish_pad_mat.albedo_color = Color(0.28, 1.55, 0.82, pulse)


# ---- Helpers ----

func _current_checkpoint_stage() -> int:
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		return 10
	var manager := world.checkpoint_manager as CheckpointManager
	if manager == null or manager.current_checkpoint == null:
		return 10
	var cp := manager.current_checkpoint
	if cp == checkpoint_boss_phase_4:
		return 150
	if cp == checkpoint_phase_3_cleared:
		return 140
	if cp == checkpoint_boss_phase_3:
		return 130
	if cp == checkpoint_winged_mech_cleared:
		return 120
	if cp == checkpoint_winged_mech:
		return 110
	if cp == checkpoint_phase_2_cleared:
		return 100
	if cp == checkpoint_boss_phase_2:
		return 90
	if cp == checkpoint_grenadiers_wave:
		return 80
	if cp == checkpoint_shooters_cleared:
		return 70
	if cp == checkpoint_shooters_wave:
		return 60
	if cp == checkpoint_phase_1_cleared:
		return 50
	if cp == checkpoint_boss_phase_1:
		return 40
	if cp == checkpoint_intro_3:
		return 30
	if cp == checkpoint_intro_2:
		return 20
	return 10


func _activate_checkpoint(cp: Checkpoint) -> void:
	if cp == null:
		return
	cp._trigger_checkpoint()


func _set_camera_hold(held: bool) -> void:
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		return
	var rig := world.get_node_or_null("CameraFollowRig") as CameraFollowRig
	if rig == null:
		return
	rig._cutscene_active = held


func _kill_stranded_players(safe_truck: VehicleScript) -> void:
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		return
	var gsm := world.get_node_or_null("GameStateMachine") as GameStateMachine
	if gsm == null or gsm.current == null or gsm.current.name.to_lower() != "playing":
		return
	var killed_any := false
	for player in _living_players():
		if safe_truck != null and safe_truck.contains_player(player, 0.3):
			continue
		player._animate_on_dead_enter = false
		CameraFeedback.add_trauma_hurt()
		Health.apply_damage(player, 9999)
		killed_any = true
	if killed_any:
		gsm.transition_to("gameoverlost")


func _is_valid_run(run_id: int) -> bool:
	return is_inside_tree() and run_id == _run_id


func _wait_seconds(seconds: float, run_id: int) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		if not _is_valid_run(run_id):
			return false
		elapsed += get_physics_process_delta_time()
	return true


func _wait_vehicle_stop(vehicle: VehicleScript, run_id: int) -> bool:
	while vehicle.is_moving():
		await get_tree().physics_frame
		if not _is_valid_run(run_id):
			return false
	return true


func _wait_all_players_on(vehicle: VehicleScript, run_id: int) -> bool:
	while true:
		await get_tree().physics_frame
		if not _is_valid_run(run_id):
			return false
		if _all_living_players_on(vehicle):
			return true
	return false


func _all_living_players_on(vehicle: VehicleScript) -> bool:
	var players := _living_players()
	if players.is_empty():
		return false
	for player in players:
		if not vehicle.contains_player(player, 0.2):
			return false
	return true


func _all_players_on_finish_pad() -> bool:
	if _finish_pad == null or not _finish_pad.visible:
		return false
	var players := _living_players()
	if players.is_empty():
		return false
	var pad_pos := _finish_pad.global_position
	for player in players:
		var dx := absf(player.global_position.x - pad_pos.x)
		var dz := absf(player.global_position.z - pad_pos.z)
		if dx > 2.9 or dz > 2.1:
			return false
	return true


func _living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var world := get_tree().current_scene
	if world == null:
		return living
	var players_node := world.get_node_or_null(^"Players")
	if players_node == null:
		return living
	for child in players_node.get_children():
		var p := child as PlayerLocal
		if p == null or p.is_dead:
			continue
		living.append(p)
	return living
