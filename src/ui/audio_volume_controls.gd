class_name AudioVolumeControls
extends Node

@export var music_slider: HSlider
@export var sfx_slider: HSlider


func _ready() -> void:
	_setup_slider(music_slider, AudioSettings.get_music_volume(), _on_music_changed)
	_setup_slider(sfx_slider, AudioSettings.get_sfx_volume(), _on_sfx_changed)


func _setup_slider(slider: HSlider, volume: float, callback: Callable) -> void:
	if slider == null:
		return
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = AudioSettings.volume_to_slider_percent(volume)
	slider.value_changed.connect(callback)


func _on_music_changed(value: float) -> void:
	print("on_music_changed (audio_volume_controls): %s" % value)
	AudioSettings.set_music_volume(AudioSettings.slider_percent_to_volume(value))


func _on_sfx_changed(value: float) -> void:
	AudioSettings.set_sfx_volume(AudioSettings.slider_percent_to_volume(value))
