extends Node

const BOSS_HEALTH_BAR_PATH := "UI/BossHealthBar"

@export var fight_trigger: AllPlayersAreaTrigger
@export var enemy_group: EnemyGroup
@export var boss_name: String = ""


func _ready() -> void:
	if fight_trigger == null:
		return
	fight_trigger.all_players_inside.connect(_on_fight_started)


func _on_fight_started() -> void:
	var world := LevelNodes.find_world(self)
	if world == null:
		return
	var bar := world.get_node_or_null(BOSS_HEALTH_BAR_PATH) as BossHealthBar
	if bar == null:
		return
	var boss_node := _find_boss_node()
	if boss_node == null:
		return
	var health := Health.from_target(boss_node)
	if health == null:
		return
	bar.bind(health, boss_name)


func _find_boss_node() -> Node:
	if enemy_group == null:
		return null
	var instances_parent := enemy_group.get_node_or_null("InstancedEnemies")
	if instances_parent == null:
		instances_parent = enemy_group
	for child in instances_parent.get_children():
		var enemy := child as EnemyLocal
		if enemy == null:
			continue
		return enemy
	return null
