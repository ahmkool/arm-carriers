class_name FrontCarrierPrompt
extends Node3D
## Teaches a weapon's front-carrier move: a word such as "VENT" next to the front carrier's
## shoot button, floating over their head while the move is worth doing. It bobs faster and
## turns to the highlight colour when the move is at its best. After a few uses in a session
## it stops showing, since by then the carriers know the move.

## Uses of a move before its prompt retires for the session.
const USES_TO_LEARN := 3
## Above the carry prompt's height, so the steep camera doesn't put the badge over the head.
const HEAD_HEIGHT := 4.0
## The button sits left of the word, which the fixed camera never turns away from. The key
## text is anchored on its right edge and the word on its left, so they meet in the middle.
const ICON_OFFSET := Vector3(-0.38, 0.0, 0.0)
const KEY_TEXT_OFFSET := Vector3(-0.08, 0.0, 0.0)
const TEXT_OFFSET := Vector3(0.05, 0.0, 0.0)
const ICON_PIXEL_SIZE := 0.003
const LABEL_PIXEL_SIZE := 0.005
const FONT := preload("res://assets/fonts/Lilita_One/LilitaOne-Regular.ttf")
const GAMEPAD_ICON := preload("res://assets/sprites/ui/controls/T_X_RB_Light.png")
const SPACE_ICON := preload("res://assets/sprites/ui/controls/T_Space_Key_White.png")
const TEXT_COLOR := Color(1.0, 0.85, 0.55)
const HIGHLIGHT_COLOR := Color(0.7, 1.0, 1.0)
const SHOW_SEC := 0.2
const HIDE_SEC := 0.14
const BOB_AMOUNT := 0.08
const BOB_HZ := 2.0
const HIGHLIGHT_BOB_HZ := 5.0
const HIGHLIGHT_PULSE := 0.12

## Uses per move, shared across weapons and levels, so each prompt retires once per session.
static var _uses := {}

var _word := ""
var _icon: Sprite3D
var _key_label: Label3D
var _text: Label3D
var _shown := false
var _time := 0.0
var _tween: Tween
var _bound_action := ""


func _init(word: String) -> void:
	_word = word


func _ready() -> void:
	top_level = true
	_icon = _make_icon()
	_key_label = _make_label(56, KEY_TEXT_OFFSET, HORIZONTAL_ALIGNMENT_RIGHT)
	_text = _make_label(96, TEXT_OFFSET, HORIZONTAL_ALIGNMENT_LEFT)
	_text.text = _word
	scale = Vector3.ZERO
	visible = false


static func get_uses(word: String) -> int:
	return _uses.get(word, 0)


static func is_learned(word: String) -> bool:
	return get_uses(word) >= USES_TO_LEARN


static func note_use(word: String) -> void:
	_uses[word] = get_uses(word) + 1


## `ignore_learned` shows the prompt even after it has retired, for a moment that needs the move.
func update_prompt(front_carrier: PlayerLocal, wanted: bool, highlight: bool, delta: float, ignore_learned := false) -> void:
	var showing := wanted and _can_show(front_carrier, ignore_learned)
	_set_shown(showing)
	if not showing:
		return
	_bind_to(front_carrier)
	_time += delta
	var hz := HIGHLIGHT_BOB_HZ if highlight else BOB_HZ
	var bob := sin(_time * TAU * hz)
	global_position = front_carrier.global_position + Vector3.UP * (HEAD_HEIGHT + bob * BOB_AMOUNT)
	_text.modulate = HIGHLIGHT_COLOR if highlight else TEXT_COLOR
	if _tween != null and _tween.is_running():
		return
	var pulse := 1.0 + (bob * HIGHLIGHT_PULSE if highlight else 0.0)
	scale = Vector3.ONE * pulse


func hide_prompt() -> void:
	_set_shown(false)


func _can_show(front_carrier: PlayerLocal, ignore_learned: bool) -> bool:
	if DevSettings.is_trailer_mode():
		return false
	if is_learned(_word) and not ignore_learned:
		return false
	if not is_instance_valid(front_carrier):
		return false
	return not front_carrier.is_dead


## Shows the button the front carrier would actually press: their pad's RB when they have
## a pad, otherwise the keyboard key bound to their shoot action.
func _bind_to(front_carrier: PlayerLocal) -> void:
	var uses_pad := Input.get_connected_joypads().has(front_carrier.device_id)
	var key := "pad" if uses_pad else String(front_carrier.action_shoot)
	if key == _bound_action:
		return
	_bound_action = key
	if uses_pad:
		_show_icon(GAMEPAD_ICON)
		return
	var event := _find_key_event(front_carrier.action_shoot)
	if event == null:
		_show_icon(GAMEPAD_ICON)
		return
	if event.physical_keycode == KEY_SPACE:
		_show_icon(SPACE_ICON)
		return
	_show_key_text(_describe_key(event))


func _find_key_event(action: String) -> InputEventKey:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event
	return null


func _describe_key(event: InputEventKey) -> String:
	var key_name := OS.get_keycode_string(event.physical_keycode).to_upper()
	if event.location == KEY_LOCATION_RIGHT:
		return "R-" + key_name
	if event.location == KEY_LOCATION_LEFT:
		return "L-" + key_name
	return key_name


func _show_icon(texture: Texture2D) -> void:
	_icon.texture = texture
	_icon.visible = true
	_key_label.visible = false


func _show_key_text(text: String) -> void:
	_key_label.text = "[" + text + "]"
	_key_label.visible = true
	_icon.visible = false


func _set_shown(wanted: bool) -> void:
	if wanted == _shown:
		return
	_shown = wanted
	_kill_tween()
	_tween = create_tween()
	if wanted:
		_time = 0.0
		visible = true
		_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "scale", Vector3.ONE, SHOW_SEC)
		return
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "scale", Vector3.ZERO, HIDE_SEC)
	_tween.tween_callback(_on_hidden)


func _on_hidden() -> void:
	if _shown:
		return
	visible = false


func _kill_tween() -> void:
	if _tween == null:
		return
	_tween.kill()
	_tween = null


func _make_icon() -> Sprite3D:
	var icon := Sprite3D.new()
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.pixel_size = ICON_PIXEL_SIZE
	icon.no_depth_test = true
	icon.render_priority = 2
	icon.position = ICON_OFFSET
	add_child(icon)
	return icon


func _make_label(font_size: int, offset: Vector3, alignment: HorizontalAlignment) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = FONT
	label.font_size = font_size
	label.outline_size = 24
	label.outline_modulate = Color(0.05, 0.05, 0.1)
	label.pixel_size = LABEL_PIXEL_SIZE
	label.no_depth_test = true
	label.render_priority = 2
	label.modulate = TEXT_COLOR
	label.position = offset
	label.horizontal_alignment = alignment
	# Pins the label at its aligned edge instead of its centre.
	label.offset.x = 0.0
	add_child(label)
	return label
