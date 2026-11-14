class_name GameHUD
extends CanvasLayer
## HUD: countdown, typing pop-up (highlight + wrong-key flash), toast, glitch effects.
## Every control here ignores the mouse and never takes focus, so it can't eat key input.
## Timers use ignore_time_scale=true so effects keep real-time pacing during slow-mo.

const POPUP_LIFETIME := 2.0
const FLICKER_STEPS := 4
const SCRAMBLE_TIME := 0.6
const POPUP_TITLES: Array[String] = ["Warning!", "Error 404", "You won a prize!", "Virus detected", "System Alert"]
const POPUP_BODIES: Array[String] = [
	"Your PC is running slowly. Click OK to fix.",
	"Congratulations! You are visitor #1,000,000!",
	"This program has performed an illegal operation.",
	"Download more RAM now!",
]

var _typed := 0              # letters typed correctly so far
var _scrambled := ""         # non-empty while a scramble glitch is active
var _flicker_busy := false
var _toast_id := 0

@onready var time_label: Label = $TimeLabel
@onready var word_panel: Panel = $WordPanel
@onready var word_label: RichTextLabel = $WordPanel/WordLabel
@onready var toast_label: Label = $ToastLabel
@onready var popup_layer: Control = $PopupLayer


func _ready() -> void:
	_layout()
	Game.time_changed.connect(_on_time_changed)
	Game.trick_started.connect(_on_trick_started)
	Game.key_correct.connect(_on_key_correct)
	Game.key_wrong.connect(_on_key_wrong)
	Game.trick_succeeded.connect(_on_trick_succeeded)
	Game.trick_failed.connect(_on_trick_failed)
	Game.glitch.connect(_on_glitch)


# Clears all transient UI (called by Main at the start of a run).
func reset() -> void:
	word_panel.hide()
	toast_label.hide()
	_typed = 0
	_scrambled = ""
	for p in popup_layer.get_children():
		p.queue_free()


# ---------- LAYOUT (code-built so the .tscn stays tiny) ----------

func _layout() -> void:
	time_label.position = Vector2(0, 16)
	time_label.size = Vector2(1280, 60)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 48)

	word_panel.position = Vector2(340, 170)
	word_panel.size = Vector2(600, 130)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.15, 0.85)
	sb.set_corner_radius_all(12)
	word_panel.add_theme_stylebox_override("panel", sb)
	word_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	word_label.position = Vector2(10, 22)
	word_label.size = Vector2(580, 100)
	word_label.bbcode_enabled = true
	word_label.scroll_active = false
	word_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word_label.add_theme_font_size_override("normal_font_size", 72)

	toast_label.position = Vector2(0, 320)
	toast_label.size = Vector2(1280, 50)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 40)

	popup_layer.position = Vector2.ZERO
	popup_layer.size = Vector2(1280, 720)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------- CORE HUD ----------

func _on_time_changed(t: float) -> void:
	time_label.text = "%.1f" % maxf(t, 0.0)
	var c := Color(1.0, 0.3, 0.3) if t < 5.0 else Color.WHITE
	time_label.add_theme_color_override("font_color", c)


func _on_trick_started(_word: String, _air_time: float) -> void:
	_typed = 0
	_scrambled = ""
	word_label.visible = true
	word_panel.modulate = Color.WHITE
	word_panel.show()
	_render()


# key_correct fires BEFORE Game bumps typed_count, so use index + 1.
func _on_key_correct(index: int) -> void:
	_typed = index + 1
	_render()


func _on_key_wrong(_penalty: float) -> void:
	_flash_wrong()


func _on_trick_succeeded(bonus: float) -> void:
	word_panel.hide()
	_toast("+%.1fs" % bonus, Color(0.4, 1.0, 0.4))


func _on_trick_failed() -> void:
	word_panel.hide()
	_toast("MISSED!", Color(1.0, 0.3, 0.3))


# Draws the word: typed part green, rest white. While scrambled, shows shuffled letters.
func _render() -> void:
	if _scrambled != "":
		word_label.text = "[center][color=white]%s[/color][/center]" % _scrambled.to_upper()
		return
	var word := Game.target_word
	word_label.text = "[center][color=lime]%s[/color][color=white]%s[/color][/center]" % [
		word.substr(0, _typed).to_upper(), word.substr(_typed).to_upper()]


func _flash_wrong() -> void:
	word_panel.modulate = Color(1.0, 0.25, 0.25)
	await _wait(0.12)
	word_panel.modulate = Color.WHITE


func _toast(text: String, color: Color) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", color)
	toast_label.show()
	_toast_id += 1
	var id := _toast_id
	await _wait(0.8)
	if id == _toast_id:
		toast_label.hide()


# Real-time wait that ignores Engine.time_scale.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# ---------- GLITCHES ----------

func _on_glitch(kind: String) -> void:
	match kind:
		"flicker": _glitch_flicker()
		"scramble": _glitch_scramble()
		"popup": _glitch_popup()


# Blink the word on/off a few times.
func _glitch_flicker() -> void:
	if _flicker_busy:
		return
	_flicker_busy = true
	for i in FLICKER_STEPS:
		word_label.visible = false
		await _wait(0.06)
		word_label.visible = true
		await _wait(0.06)
	_flicker_busy = false


# Briefly DRAW shuffled letters. Game.target_word is untouched, so input stays correct.
func _glitch_scramble() -> void:
	if _scrambled != "":
		return
	_scrambled = Game.scrambled_display()
	_render()
	await _wait(SCRAMBLE_TIME)
	_scrambled = ""
	if Game.state == Game.State.TRICK:
		_render()


# Spawns a fake OS-style window over the word. Purely visual, auto-closes.
func _glitch_popup() -> void:
	var win := Panel.new()
	win.size = Vector2(randf_range(240.0, 340.0), randf_range(110.0, 150.0))
	win.position = word_panel.position + Vector2(randf_range(-120.0, 380.0), randf_range(-70.0, 60.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.75, 0.75, 0.75)
	sb.border_color = Color.BLACK
	sb.set_border_width_all(2)
	win.add_theme_stylebox_override("panel", sb)

	var bar := ColorRect.new()
	bar.color = Color(0.1, 0.2, 0.7)
	bar.size = Vector2(win.size.x, 24.0)
	win.add_child(bar)
	win.add_child(_make_label(POPUP_TITLES.pick_random(), Vector2(6, 2), Vector2(win.size.x - 12.0, 20), 14, Color.WHITE))
	win.add_child(_make_label(POPUP_BODIES.pick_random(), Vector2(10, 34), Vector2(win.size.x - 20.0, 50), 14, Color.BLACK))
	var ok := Panel.new()
	ok.position = Vector2(win.size.x - 70.0, win.size.y - 34.0)
	ok.size = Vector2(60, 24)
	ok.add_child(_make_label("OK", Vector2(0, 2), Vector2(60, 20), 14, Color.BLACK, true))
	win.add_child(ok)

	_ignore_mouse(win)
	popup_layer.add_child(win)
	await _wait(POPUP_LIFETIME)
	if is_instance_valid(win):
		win.queue_free()


func _make_label(text: String, pos: Vector2, sz: Vector2, font_size: int, color: Color, centered := false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# Recursively make a control tree click-through (ColorRect/Panel default to STOP).
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_ignore_mouse(child)
