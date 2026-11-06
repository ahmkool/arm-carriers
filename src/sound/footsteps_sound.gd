class_name FootstepsSound
extends AudioStreamPlayer3D
## Player footsteps that match the floor: grass, wood, stone or metal (see FootstepSurface).

@export var grass_steps: AudioStream
@export var wood_steps: AudioStream
@export var stone_steps: AudioStream
@export var metal_steps: AudioStream

## The grass recordings are quieter than the others, so the harder surfaces are pulled down to match.
const SURFACE_VOLUME_OFFSET_DB := {
	FootstepSurface.GRASS: 0.0,
	FootstepSurface.WOOD: -4.0,
	FootstepSurface.STONE: -3.0,
	FootstepSurface.METAL: -5.0,
}

var _surface := FootstepSurface.GRASS


## Plays one step on the given surface. An unknown surface keeps the last one heard.
## `volume_db` stays the caller's base volume; the surface offset is added on top.
func play_step(surface: StringName, base_volume_db: float) -> void:
	if surface != FootstepSurface.UNKNOWN:
		_surface = surface
	stream = _stream_for(_surface)
	volume_db = base_volume_db + SURFACE_VOLUME_OFFSET_DB.get(_surface, 0.0)
	play()


func _stream_for(surface: StringName) -> AudioStream:
	match surface:
		FootstepSurface.WOOD:
			return wood_steps
		FootstepSurface.STONE:
			return stone_steps
		FootstepSurface.METAL:
			return metal_steps
	return grass_steps
