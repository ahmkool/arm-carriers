class_name PlayerCharacter
extends Node3D
## Root of a swappable player model. See docs/player-characters.md.

@export var arm_left: MeshInstance3D
@export var arm_right: MeshInstance3D
@export var health_bar_icon: Texture2D

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
