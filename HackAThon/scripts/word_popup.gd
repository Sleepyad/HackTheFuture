extends PanelContainer
class_name WordPopup
## Windows 98 style typing window (Part B look).
## DISPLAY ONLY: the Game autoload picks the word and checks every key.
## This node just mirrors Game's state, so it can never disagree with it.
##   listens -> Game.trick_started, key_correct, key_wrong,
##              trick_succeeded, trick_failed, glitch, game_over
## Public API: scramble_word(), get_current_word(), get_window_title()
##
## Y2K extras:
##   - title bar named after the word's category (from the JSON word bank)
##   - blinking text cursor
##   - segmented progress bar that drains with the air time
##   - scramble glitch looks like corrupted data (junk symbols + leetspeak)
##   - a missed word greys out as "(Not Responding)" before closing
##   - long phrases get a wide, wrapping "untitled.txt" window

## true  = hidden until Game starts a trick (normal play).
## false = always visible with preview_word. Handy for testing this scene alone (F6).
@export var only_while_jumping: bool = true
@export var preview_word: String = "y2k"
## Title used when a word has no category in the word bank.
@export var window_title: String = "typing_test.exe"
@export var font_size: int = 32
@export_file("*.json") var words_json: String = "res://data/y2k_words.json"

const GRAY := Color("c0c0c0")
const NAVY := Color("000080")
const DARK := Color("404040")
const WRONG := Color("ff8080")
const FROZEN := Color("808080")       # title bar colour while "Not Responding"
const LOW_AIR := Color("aa0000")      # progress bar colour when almost out of air

const CATEGORY_TITLES := {
	"Chat Slang": "buddy_chat.exe",
	"Internet": "netsurfer.exe",
	"Software & Bugs": "error.log",
	"Tech & Hardware": "hardware_wizard.exe",
	"Music & Pop Culture": "jukebox.exe",
	"Fashion & Style": "mall_rat.exe",
	"Y2K & Millennium": "y2k_countdown.exe",
}
const LONG_WORD := 14                 # more characters than this -> wide wrapping window
const WIDE_WIDTH := 900.0
const NARROW_WIDTH := 360.0
const CURSOR_BLINK_MS := 500
const NOT_RESPONDING_TIME := 0.6      # seconds the frozen window stays up after a miss
const CORRUPT_CHANCE := 0.4           # share of scrambled letters turned into junk
const JUNK := "#%@&$!?*"
const LEET := {"a": "4", "e": "3", "i": "1", "o": "0", "s": "5", "t": "7", "b": "8", "g": "9"}
const SEGMENT_W := 10.0
const SEGMENT_GAP := 2.0

var _word: String = ""
var _index: int = 0               # number of letters typed correctly so far
var _scrambled_rest: String = ""  # shown instead of the remaining letters
var _scramble_id: int = 0
var _hide_id: int = 0
var _frozen: bool = false         # true while "Not Responding" is showing
var _cursor_on: bool = true
var _air_total: float = 0.0       # 0 = no trick running (bar shows full)
var _air_start_ms: int = 0
var _categories: Dictionary = {}  # word -> category, from the JSON word bank

var _label: RichTextLabel
var _title: Label
var _bar_style: StyleBoxFlat
var _field_style: StyleBoxFlat
var _air_bar: Control
var _flash_tween: Tween


func _ready() -> void:
	_load_categories()
	_build_ui()
	Game.trick_started.connect(_on_trick_started)
	Game.key_correct.connect(_on_key_correct)
	Game.key_wrong.connect(_on_key_wrong)
	Game.trick_succeeded.connect(_close.unbind(1))
	Game.trick_failed.connect(_on_trick_failed)
	Game.player_landed.connect(_on_landed)
	Game.glitch.connect(_on_glitch)
	Game.game_over.connect(_close.unbind(1))
	if only_while_jumping:
		hide()
	else:
		_show_word(preview_word)


func _process(_delta: float) -> void:
	if not visible:
		return
	var on := (Time.get_ticks_msec() / CURSOR_BLINK_MS) % 2 == 0
	if on != _cursor_on:
		_cursor_on = on
		_refresh()
	_air_bar.queue_redraw()


# ---------------------------------------------------------------- public API

## Corrupts the letters that are still left to type, for `duration` seconds
## (real time, ignores Engine.time_scale): shuffled, with some turned into
## junk symbols or leetspeak. The word to type does not change, only what is
## displayed. duration <= 0 keeps it scrambled until the next correct letter.
func scramble_word(duration: float = 0.6) -> void:
	if _word.is_empty() or _index >= _word.length():
		return
	var letters: Array = Array(_word.substr(_index).split(""))
	letters.shuffle()
	for i in letters.size():
		if letters[i] != " " and randf() < CORRUPT_CHANCE:
			letters[i] = LEET.get(letters[i], JUNK[randi() % JUNK.length()])
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


func get_window_title() -> String:
	return _title.text if _title else window_title


# ------------------------------------------------------------- Game signals

func _on_trick_started(word: String, air_time: float) -> void:
	_air_total = air_time
	_air_start_ms = Time.get_ticks_msec()
	_show_word(word)


func _on_key_correct(index: int) -> void:
	_index = index + 1
	_scrambled_rest = ""
	_scramble_id += 1
	_refresh()


func _on_key_wrong(_penalty: float) -> void:
	_flash_wrong()


func _on_glitch(kind: String) -> void:
	if kind == "scramble" and visible:
		scramble_word()


# Missed word: freeze the window like a hung program, then close it.
func _on_trick_failed() -> void:
	_scramble_id += 1
	if _air_total > 0.0:   # out of air: show the progress bar empty
		_air_start_ms = Time.get_ticks_msec() - int(_air_total * 1000.0)
	if not visible:
		return
	_frozen = true
	_title.text = "%s (Not Responding)" % _title_for(_word)
	_bar_style.bg_color = FROZEN
	_label.modulate = Color(1, 1, 1, 0.35)
	var id := _hide_id
	await get_tree().create_timer(NOT_RESPONDING_TIME, true, false, true).timeout
	if id == _hide_id:      # a new trick may have started meanwhile
		_close()


# The jump is over. A normal success/miss closes the window itself, but a chained
# combo word that times out ends the jump WITHOUT trick_failed, so close it here.
# Deferred so a trick_failed sent right after player_landed can start its
# "Not Responding" freeze first.
func _on_landed() -> void:
	_close_if_landed.call_deferred()


func _close_if_landed() -> void:
	if visible and not _frozen and Game.state != Game.State.TRICK:
		_close()


func _close() -> void:
	_hide_id += 1
	_scramble_id += 1
	_frozen = false
	_air_total = 0.0
	if only_while_jumping:
		hide()


# ------------------------------------------------------------------ internals

func _show_word(word: String) -> void:
	_hide_id += 1
	_frozen = false
	_word = word
	_index = 0
	_scrambled_rest = ""
	_scramble_id += 1
	_title.text = _title_for(word)
	_bar_style.bg_color = NAVY
	_label.modulate = Color.WHITE
	_apply_word_size(word)
	_refresh()
	show()


func _title_for(word: String) -> String:
	if word.length() > LONG_WORD:
		return "untitled.txt"
	return CATEGORY_TITLES.get(_categories.get(word.to_lower(), ""), window_title)


# Short words: one line, window grows with the word.
# Long phrases: fixed wide window, smaller font, wraps onto several lines.
func _apply_word_size(word: String) -> void:
	if word.length() > LONG_WORD:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size.x = WIDE_WIDTH
		_label.add_theme_font_size_override("normal_font_size", int(font_size * 0.75))
	else:
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.custom_minimum_size.x = NARROW_WIDTH
		_label.add_theme_font_size_override("normal_font_size", font_size)
	reset_size.call_deferred()   # let the window shrink back after a long phrase


func _refresh() -> void:
	if _label == null:
		return
	var done := _word.substr(0, _index)
	var rest := _scrambled_rest if _scrambled_rest != "" else _word.substr(_index)
	# Blinking cursor = underline on the next letter to type. It is not an extra glyph, so the
	# typed letters and the remaining ones stay in one continuous run of the same font.
	var next := rest.substr(0, 1)
	var tail := rest.substr(1)
	if _cursor_on and next != "":
		next = "[u]%s[/u]" % next
	# Correctly typed letters are highlighted (white on navy).
	_label.text = "[center][bgcolor=#000080][color=#ffffff]%s[/color][/bgcolor]%s%s[/center]" % [done, next, tail]


func _flash_wrong() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_field_style.bg_color = WRONG
	_flash_tween = create_tween()
	_flash_tween.tween_property(_field_style, "bg_color", Color.WHITE, 0.25)


func _air_fraction() -> float:
	if _air_total <= 0.0:
		return 1.0
	var used := (Time.get_ticks_msec() - _air_start_ms) / 1000.0
	return clampf(1.0 - used / _air_total, 0.0, 1.0)


# Win98 progress bar: sunken white box with navy blocks that drain.
func _draw_air_bar() -> void:
	var w := _air_bar.size.x
	var h := _air_bar.size.y
	_air_bar.draw_rect(Rect2(0, 0, w, h), Color.WHITE)
	_air_bar.draw_rect(Rect2(0, 0, w, 2), DARK)      # sunken: dark top/left edge
	_air_bar.draw_rect(Rect2(0, 0, 2, h), DARK)
	var inner := Rect2(4, 4, w - 7, h - 7)
	var count := int((inner.size.x + SEGMENT_GAP) / (SEGMENT_W + SEGMENT_GAP))
	var frac := _air_fraction()
	var lit := ceili(count * frac)
	var color := LOW_AIR if frac < 0.3 else NAVY
	for i in lit:
		var x := inner.position.x + i * (SEGMENT_W + SEGMENT_GAP)
		_air_bar.draw_rect(Rect2(x, inner.position.y, SEGMENT_W, inner.size.y), color)


func _load_categories() -> void:
	if not FileAccess.file_exists(words_json):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(words_json))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for level in data.get("levels", []):
		for entry in level.get("words", []):
			_categories[str(entry.get("word", "")).to_lower()] = str(entry.get("category", ""))


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
	_bar_style = _flat(NAVY)
	_bar_style.set_content_margin_all(3)
	bar.add_theme_stylebox_override("panel", _bar_style)
	vbox.add_child(bar)

	var bar_row := HBoxContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bar_row)

	_title = Label.new()
	_title.text = window_title
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(_title)

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
	_label.custom_minimum_size = Vector2(NARROW_WIDTH, 0)
	_label.add_theme_color_override("default_color", Color.BLACK)
	_label.add_theme_font_size_override("normal_font_size", font_size)
	field.add_child(_label)

	# Air-time progress bar.
	_air_bar = Control.new()
	_air_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_air_bar.custom_minimum_size = Vector2(0, 20)
	_air_bar.draw.connect(_draw_air_bar)
	vbox.add_child(_air_bar)
