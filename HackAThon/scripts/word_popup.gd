extends PanelContainer
class_name WordPopup
## Windows 98 style typing window (Part B look).
## DISPLAY ONLY: the Game autoload picks the word and checks every key.
## This node just mirrors Game's state, so it can never disagree with it.
##   listens -> Game.trick_started, key_correct, key_wrong,
##              trick_succeeded, trick_failed, glitch, game_over
## Public API: scramble_word(), get_current_word()

## true  = hidden until Game starts a trick (normal play).
## false = always visible with preview_word. Handy for testing this scene alone (F6).
@export var only_while_jumping: bool = true
@export var preview_word: String = "y2k"
@export var window_title: String = "typing_test.exe"
@export var font_size: int = 32

const GRAY := Color("c0c0c0")
const NAVY := Color("000080")
const DARK := Color("404040")
const WRONG := Color("ff8080")

var _word: String = ""
var _index: int = 0               # number of letters typed correctly so far
var _scrambled_rest: String = ""  # shown instead of the remaining letters
var _scramble_id: int = 0

var _label: RichTextLabel
var _field_style: StyleBoxFlat
var _flash_tween: Tween


func _ready() -> void:
	_build_ui()
	Game.trick_started.connect(_on_trick_started)
	Game.key_correct.connect(_on_key_correct)
	Game.key_wrong.connect(_on_key_wrong)
	Game.trick_succeeded.connect(_on_trick_ended.unbind(1))
	Game.trick_failed.connect(_on_trick_ended)
	Game.glitch.connect(_on_glitch)
	Game.game_over.connect(_on_trick_ended.unbind(1))
	if only_while_jumping:
		hide()
	else:
		_show_word(preview_word)


# ---------------------------------------------------------------- public API

## Shuffles the letters that are still left to type, for `duration` seconds
## (real time, ignores Engine.time_scale). The word to type does not change,
## only what is displayed. duration <= 0 keeps it scrambled until the next
## correct letter.
func scramble_word(duration: float = 0.6) -> void:
	if _word.is_empty() or _index >= _word.length():
		return
	var letters: Array = Array(_word.substr(_index).split(""))
	letters.shuffle()
	_scrambled_rest = "".join(PackedStringArray(letters))
	_scramble_id += 1
	_refresh()
	if duration <= 0.0:
		return
	var id := _scramble_id
	await get_tree().create_timer(duration, true, false, true).timeout
	if id == _scramble_id:
		_scrambled_rest = ""
		_refresh()


func get_current_word() -> String:
	return _word


# ------------------------------------------------------------- Game signals

func _on_trick_started(word: String, _air_time: float) -> void:
	_show_word(word)


func _on_key_correct(index: int) -> void:
	_index = index + 1
	_scrambled_rest = ""
	_scramble_id += 1
	_refresh()


func _on_key_wrong(_penalty: float) -> void:
	_flash_wrong()


func _on_trick_ended() -> void:
	_scramble_id += 1
	if only_while_jumping:
		hide()


func _on_glitch(kind: String) -> void:
	if kind == "scramble" and visible:
		scramble_word()


# ------------------------------------------------------------------ internals

func _show_word(word: String) -> void:
	_word = word
	_index = 0
	_scrambled_rest = ""
	_scramble_id += 1
	_refresh()
	show()


func _refresh() -> void:
	if _label == null:
		return
	var done := _word.substr(0, _index)
	var rest := _scrambled_rest if _scrambled_rest != "" else _word.substr(_index)
	# Correctly typed letters are highlighted (white on navy).
	_label.text = "[center][bgcolor=#000080][color=#ffffff]%s[/color][/bgcolor]%s[/center]" % [done, rest]


func _flash_wrong() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_field_style.bg_color = WRONG
	_flash_tween = create_tween()
	_flash_tween.tween_property(_field_style, "bg_color", Color.WHITE, 0.25)


func _flat(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	return sb


# Windows 98 style window, built in code so the .tscn stays a single node.
func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Outer dark edge (bottom/right shadow of the bevel).
	var outer := _flat(DARK)
	outer.content_margin_right = 2
	outer.content_margin_bottom = 2
	add_theme_stylebox_override("panel", outer)

	# Gray window face with a white top/left highlight.
	var face := PanelContainer.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face_style := _flat(GRAY)
	face_style.border_color = Color.WHITE
	face_style.border_width_left = 2
	face_style.border_width_top = 2
	face_style.set_content_margin_all(4)
	face.add_theme_stylebox_override("panel", face_style)
	add_child(face)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	face.add_child(vbox)

	# Title bar.
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_style := _flat(NAVY)
	bar_style.set_content_margin_all(3)
	bar.add_theme_stylebox_override("panel", bar_style)
	vbox.add_child(bar)

	var bar_row := HBoxContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bar_row)

	var title := Label.new()
	title.text = window_title
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(title)

	var close := Label.new()   # decorative only
	close.text = " x "
	close.add_theme_color_override("font_color", Color.BLACK)
	close.add_theme_stylebox_override("normal", _flat(GRAY))
	bar_row.add_child(close)

	# Sunken white text field holding the word.
	var field := PanelContainer.new()
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_style = _flat(Color.WHITE)
	_field_style.border_color = DARK
	_field_style.border_width_left = 2
	_field_style.border_width_top = 2
	_field_style.set_content_margin_all(8)
	field.add_theme_stylebox_override("panel", _field_style)
	vbox.add_child(field)

	_label = RichTextLabel.new()
	_label.name = "WordLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size = Vector2(360, 0)
	_label.add_theme_color_override("default_color", Color.BLACK)
	_label.add_theme_font_size_override("normal_font_size", font_size)
	field.add_child(_label)
