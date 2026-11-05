class_name MenuUiJuice
extends MenuPanelJuice
## Main menu panels and buttons. Starting the action also fires the bazooka in the menu art.

const SCREEN_ROOTS: Array[String] = ["HomeMenuRoot", "SettingsMenuRoot", "CreditsMenuRoot", "MainMenuRoot", "LevelStartChoiceRoot"]
const LAUNCH_ROOTS: Array[String] = ["MainMenuRoot"]
const LAUNCH_FADE_SECONDS := 0.4

@onready var _menu: Control = get_parent()
@onready var _backdrop: MenuBackdropJuice = $"../MenuBackdropJuice"
@onready var _play_button: BaseButton = $"../HomeMenuRoot/PanelContainer/MarginContainer/VBoxContainer/PlayButton"
@onready var _launch_screen: Control = $"../ShaderCompilingRoot"


func _ready() -> void:
	for root_name in SCREEN_ROOTS:
		var root := _menu.get_node(root_name) as Control
		watch_screen(root)
		watch_controls(root)
	watch_controls(_menu.get_node("PlaytestNoticeRoot"))
	watch_navigator($"../GamepadMenuNavigator" as GamepadMenuNavigator)
	_launch_screen.visibility_changed.connect(_on_launch_screen_visibility_changed)


func _on_screen_opened(_root: Control) -> void:
	_backdrop.hurry_intro()


func _on_button_activated(button: BaseButton) -> void:
	if not _is_launch_button(button):
		_play_tick(1.0)
		return
	_backdrop.fire_bazooka()


func _is_launch_button(button: BaseButton) -> bool:
	if button == _play_button:
		return true
	for root_name in LAUNCH_ROOTS:
		if _menu.get_node(root_name).is_ancestor_of(button):
			return true
	return false


## Keeps the bazooka shot visible by fading the loading screen in instead of cutting to it.
func _on_launch_screen_visibility_changed() -> void:
	if not _launch_screen.visible:
		return
	_launch_screen.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_launch_screen, "modulate:a", 1.0, LAUNCH_FADE_SECONDS)
