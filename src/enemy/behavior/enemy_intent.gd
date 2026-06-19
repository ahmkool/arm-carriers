class_name EnemyIntent
extends RefCounted

## Normalized XZ direction for locomotion; Vector3.ZERO means stand still.
var move_direction: Vector3 = Vector3.ZERO

## Optional aim/facing override; falls back to move_direction when unset.
var face_direction: Vector3 = Vector3.ZERO

## Locomotion state to enter (e.g. &"running", &"casting"); empty = no change.
var requested_locomotion: StringName = &""

## Attack to perform when entering &"attacking" (e.g. &"slash", &"stab").
var requested_attack: StringName = &""

## One-shot action request (e.g. start a cast this frame).
var wants_cast: bool = false
