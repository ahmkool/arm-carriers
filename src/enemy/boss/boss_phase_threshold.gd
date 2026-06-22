class_name BossPhaseThreshold
extends Resource

## Enter this phase when remaining HP / max HP is at or below this ratio (e.g. 0.5 = 50%).
@export_range(0.0, 1.0) var hp_ratio: float = 0.5
@export var phase_index: int = 2
