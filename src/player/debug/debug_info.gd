extends MarginContainer

@onready var carrying_status_p0_label: Label = $PanelContainer/VBoxContainer/CarryingStatusP0
@onready var carrying_status_p1_label: Label = $PanelContainer/VBoxContainer/CarryingStatusP1


# Called when the node enters the scene tree for the first time.
func _ready():
	_update_all_carrying_statuses()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	_update_all_carrying_statuses()


func _update_all_carrying_statuses() -> void:
	if is_instance_valid(carrying_status_p0_label):
		carrying_status_p0_label.text = _build_status_text(0)
	if is_instance_valid(carrying_status_p1_label):
		carrying_status_p1_label.text = _build_status_text(1)


func _build_status_text(player_id: int) -> String:
	var player := _get_player_by_id(player_id)
	if not is_instance_valid(player):
		return "P%s Carrying: (player missing)" % str(player_id)

	var carrying_weapon_data := player.get_node_or_null("CarryingWeaponData") as CarryingWeaponData
	if not is_instance_valid(carrying_weapon_data):
		return "P%s Carrying: (missing CarryingWeaponData)" % str(player_id)

	var status_idx: int = int(carrying_weapon_data.can_carry_status)
	var keys := CarryingWeaponData.CanCarryStatus.keys()
	var status_name := "UNKNOWN"
	if status_idx >= 0 and status_idx < keys.size():
		status_name = str(keys[status_idx])
	return "P%s Carrying: %s" % [str(player_id), status_name]


func _get_player_by_id(player_id: int) -> Node:
	var players_node := get_tree().root.find_child("Players", true, false)
	if not is_instance_valid(players_node):
		return null
	for child in players_node.get_children():
		if "device_id" in child and int(child.device_id) == player_id:
			return child
	return null
