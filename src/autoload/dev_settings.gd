extends Node

const CONFIG_PATH := "res://dev/dev_settings.tres"
const USER_OVERRIDES_PATH := "user://dev_settings.json"

var _config: DevSettingsConfig = null


func _ready() -> void:
	_load_config()
	_load_user_overrides()


func is_active() -> bool:
	if _config == null:
		return false
	if not _config.enabled:
		return false
	return OS.is_debug_build() or OS.has_feature("editor")


func apply_to_health(health: Health) -> void:
	if not is_active():
		return
	if health == null:
		return
	var health_owner := health.get_parent()
	if health_owner == null:
		return
	if health_owner is PlayerLocal:
		_apply_player_hp(health)
		return
	if _is_boss(health_owner):
		_apply_boss_hp(health)
		return
	if health_owner is EnemyLocal:
		_apply_enemy_hp(health)


func _apply_player_hp(health: Health) -> void:
	if _config.player_max_hp_override <= 0:
		return
	health.max_hp = _config.player_max_hp_override


# Bug: applied twice for instanced bosses. See docs/dev-settings-double-apply.md
func _apply_boss_hp(health: Health) -> void:
	if _config.boss_hp_multiplier == 1.0:
		return
	health.max_hp = _scaled_hp(health.get_scene_max_hp(), _config.boss_hp_multiplier)
	print("Applied boss HP multiplier to ", health.max_hp)

# Bug: applied twice for instanced enemies. See docs/dev-settings-double-apply.md
func _apply_enemy_hp(health: Health) -> void:
	if _config.enemy_hp_multiplier == 1.0:
		return
	health.max_hp = _scaled_hp(health.get_scene_max_hp(), _config.enemy_hp_multiplier)


func _scaled_hp(base_hp: int, multiplier: float) -> int:
	return maxi(1, int(round(float(base_hp) * multiplier)))


func _is_boss(health_owner: Node) -> bool:
	return health_owner.get_node_or_null("BossPhaseController") != null


func _load_config() -> void:
	if not ResourceLoader.exists(CONFIG_PATH):
		_config = DevSettingsConfig.new()
		return
	var loaded := load(CONFIG_PATH) as DevSettingsConfig
	if loaded == null:
		_config = DevSettingsConfig.new()
		return
	_config = loaded


func _load_user_overrides() -> void:
	if not FileAccess.file_exists(USER_OVERRIDES_PATH):
		return
	var file := FileAccess.open(USER_OVERRIDES_PATH, FileAccess.READ)
	if file == null:
		push_error("DevSettings: failed to read %s (error %d)." % [USER_OVERRIDES_PATH, FileAccess.get_open_error()])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("DevSettings: corrupt overrides file at %s." % USER_OVERRIDES_PATH)
		return
	_apply_user_overrides(parsed)


func _apply_user_overrides(data: Dictionary) -> void:
	if data.has("enabled"):
		_config.enabled = bool(data["enabled"])
	if data.has("player_max_hp_override"):
		_config.player_max_hp_override = int(data["player_max_hp_override"])
	if data.has("boss_hp_multiplier"):
		_config.boss_hp_multiplier = float(data["boss_hp_multiplier"])
	if data.has("enemy_hp_multiplier"):
		_config.enemy_hp_multiplier = float(data["enemy_hp_multiplier"])
