extends Node3D

const SLASH_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/slash_1.wav"),
	preload("res://assets/sounds/slash_2.wav"),
	preload("res://assets/sounds/slash_3.wav"),
	preload("res://assets/sounds/slash_4.wav"),
]

@onready var _sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D


func _ready() -> void:
	_sfx.stream = SLASH_SOUNDS.pick_random()
	_sfx.finished.connect(queue_free, CONNECT_ONE_SHOT)
	_sfx.play()
