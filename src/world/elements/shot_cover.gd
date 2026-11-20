class_name ShotCover
extends StaticBody3D
## Solid cover that stops the carriers' shots. Most terrain lets shots fly through, since levels are built
## around that, so only bodies on this layer stop them: the shuriken launcher's star hangs where it hits one,
## and its kunai stop on it. Put a ShotCover on the level layer too, so the carriers and enemies bump into it.

## Physics layer 7, "shot_cover".
const LAYER := 64
const CLANK := preload("res://assets/sounds/metal/GridStep03.wav")
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")


## Sparks and a clank where a shot strikes the cover.
static func play_hit(tree: SceneTree, at_position: Vector3, strength: float) -> void:
	ImpactFeedback.play_sfx(CLANK, at_position, randf_range(0.9, 1.1), -4.0)
	var sparks := SPARKS_SCENE.instantiate() as GPUParticles3D
	tree.current_scene.add_child(sparks)
	sparks.global_position = at_position
	sparks.amount_ratio = strength
	sparks.emitting = true
