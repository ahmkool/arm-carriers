extends Node

var _locked: bool = false

func lock() -> void:
	_locked = true

func unlock() -> void:
	_locked = false

func is_locked() -> bool:
	return _locked
