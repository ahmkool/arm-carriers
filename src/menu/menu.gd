extends Control

const MENU_MUSIC_DELAY_SECONDS := 1.5

@onready var _press_start_root: Control = $PressStartRoot
@onready var _home_menu_root: Control = $HomeMenuRoot
@onready var _settings_menu_root: Control = $SettingsMenuRoot
@onready var _main_menu_root: Control = $MainMenuRoot
@onready var _level_start_choice_root: Control = $LevelStartChoiceRoot
@onready var _menu_navigator: GamepadMenuNavigator = $GamepadMenuNavigator
@onready var _play_button: Button = $HomeMenuRoot/PanelContainer/MarginContainer/VBoxContainer/PlayButton
@onready var _settings_button: Button = $HomeMenuRoot/PanelContainer/MarginContainer/VBoxContainer/SettingsButton
@onready var _quit_button: Button = $HomeMenuRoot/PanelContainer/MarginContainer/VBoxContainer/QuitButton
@onready var _settings_back_button: Button = $SettingsMenuRoot/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var _level_picker_focus: Button = $MainMenuRoot/PanelContainer/MarginContainer/VBoxContainer/Level1Button
@onready var _continue_button: Button = $LevelStartChoiceRoot/PanelContainer/MarginContainer/VBoxContainer/ContinueButton
@onready var _from_beginning_button: Button = $LevelStartChoiceRoot/PanelContainer/MarginContainer/VBoxContainer/FromBeginningButton
@onready var _level_start_prompt: Label = $LevelStartChoiceRoot/PanelContainer/MarginContainer/VBoxContainer/PromptLabel
@onready var _menu_music: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_back_button.pressed.connect(_on_settings_back_pressed)
	_continue_button.pressed.connect(_on_continue_from_checkpoint_pressed)
	_from_beginning_button.pressed.connect(_on_from_beginning_pressed)
	SessionFlow.register_menu_ui(
		_press_start_root,
		_home_menu_root,
		_settings_menu_root,
		_main_menu_root,
		_level_start_choice_root,
		_menu_navigator,
		_play_button,
		_settings_back_button,
		_level_picker_focus,
		_continue_button,
		_level_start_prompt,
	)
	SessionFlow.start()
	_begin_menu_music()


func _begin_menu_music() -> void:
	await get_tree().create_timer(MENU_MUSIC_DELAY_SECONDS).timeout
	if not is_inside_tree():
		return
	_menu_music.play()


func _on_play_pressed() -> void:
	SessionFlow.transition_to("mainmenu")


func _on_settings_pressed() -> void:
	SessionFlow.transition_to("settingsmenu")


func _on_settings_back_pressed() -> void:
	SessionFlow.transition_to("homemenu")


func _on_quit_pressed() -> void:
	SessionFlow.quit_game()


func _on_continue_from_checkpoint_pressed() -> void:
	SessionFlow.load_level_with_choice(true)


func _on_from_beginning_pressed() -> void:
	SessionFlow.load_level_with_choice(false)
