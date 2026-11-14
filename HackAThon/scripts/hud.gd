class_name GameHUD
extends CanvasLayer
## HUD: countdown, Win98 taskbar with a Y2K tray clock, tooltip toasts, glitch effects.
## The word itself is drawn by WordPopup (scenes/word_popup.tscn), which handles its
## own highlight, wrong-key flash, air-time bar and scramble.
## The tray clock counts down to midnight, Dec 31 1999: running out of time = Y2K hits.
## Every control here ignores the mouse and never takes focus, so it can't eat key input.
## Timers use ignore_time_scale=true so effects keep real-time pacing during slow-mo.

const POPUP_LIFETIME := 2.0
const POPUP_CLEARANCE := 24.0      # fake ads stay at least this far from the typing window
const TASKBAR_H := 40.0
const LOW_TIME := 10.0             # tray clock turns red below this
const UI_GRAY := Color("c0c0c0")
const UI_DARK := Color("404040")
const TOOLTIP_BG := Color("ffffe1")
const FLICKER_STEPS := 4
const POPUP_TITLES: Array[String] = ["Warning!", "Error 404", "You won a prize!", "Virus detected", "System Alert"]
const POPUP_BODIES: Array[String] = [
	"Your PC is running slowly. Click OK to fix.",
	"Congratulations! You are visitor #1,000,000!",
	"This program has performed an illegal operation.",
	"Download more RAM now!",
]

var _flicker_busy := false
var _toast_id := 0
var _tray_clock: Label             # "12/31/1999 11:59:30 PM" in the taskbar
var _task_button: Panel            # taskbar button for the open typing window
var _task_label: Label

@onready var time_label: Label = $TimeLabel
@onready var word_popup: WordPopup = $WordPopup
@onready var toast_label: Label = $ToastLabel
@onready var popup_layer: Control = $PopupLayer


func _ready() -> void:
	_layout()
	Game.time_changed.connect(_on_time_changed)
	Game.trick_started.connect(_on_trick_started)
	Game.trick_succeeded.connect(_on_trick_succeeded)
	Game.trick_failed.connect(_on_trick_failed)
	Game.player_landed.connect(_task_button.hide)   # also covers a combo word that times out
	Game.game_over.connect(_task_button.hide.unbind(1))
	Game.glitch.connect(_on_glitch)


# Clears all transient UI (called by Main at the start of a run).
func reset() -> void:
	word_popup.hide()
	word_popup.modulate = Color.WHITE
	toast_label.hide()
	_task_button.hide()
	for p in popup_layer.get_children():
		p.queue_free()


# ---------- LAYOUT (code-built so the .tscn stays tiny) ----------

func _layout() -> void:
	time_label.position = Vector2(0, 16)
	time_label.size = Vector2(1280, 60)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 48)

	_build_taskbar()

	# WordPopup sizes itself to the word, so re-center it whenever it resizes.
	word_popup.resized.connect(_center_word_popup)
	_center_word_popup()

	# Toasts look like a yellow Win98 tooltip, above the typing window.
	var tip := StyleBoxFlat.new()
	tip.bg_color = TOOLTIP_BG
	tip.border_color = Color.BLACK
	tip.set_border_width_all(1)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.content_margin_top = 2
	tip.content_margin_bottom = 2
	toast_label.add_theme_stylebox_override("normal", tip)
	toast_label.add_theme_font_size_override("font_size", 28)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	popup_layer.position = Vector2.ZERO
	popup_layer.size = Vector2(1280, 720)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------- CORE HUD ----------

# Win98 taskbar along the bottom: a start-style button, a button for the open
# typing window and the tray clock.
func _build_taskbar() -> void:
	var bar := Panel.new()
	bar.name = "Taskbar"
	bar.position = Vector2(0, 720.0 - TASKBAR_H)
	bar.size = Vector2(1280, TASKBAR_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI_GRAY
	sb.border_color = Color.WHITE
	sb.border_width_top = 2
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)
	move_child(bar, popup_layer.get_index())   # fake ads still draw on top

	var start := _bevel_box(Vector2(4, 5), Vector2(110, 30), false)
	start.add_child(_make_label("skate.exe", Vector2(0, 3), Vector2(110, 24), 16, Color.BLACK, true))
	bar.add_child(start)

	_task_button = _bevel_box(Vector2(122, 5), Vector2(230, 30), true)
	_task_label = _make_label("", Vector2(8, 4), Vector2(214, 22), 14, Color.BLACK)
	_task_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_task_label.clip_text = true
	_task_button.add_child(_task_label)
	_task_button.hide()
	bar.add_child(_task_button)

	var tray := _bevel_box(Vector2(1010, 5), Vector2(266, 30), true)
	bar.add_child(tray)
	_tray_clock = _make_label("", Vector2(0, 3), Vector2(266, 24), 17, Color.BLACK, true)
	_tray_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	tray.add_child(_tray_clock)


# Gray box with a one-colour bevel: dark bottom/right = raised, dark top/left = sunken.
func _bevel_box(pos: Vector2, sz: Vector2, sunken: bool) -> Panel:
	var box := Panel.new()
	box.position = pos
	box.size = sz
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("d8d8d8") if sunken else UI_GRAY
	sb.border_color = UI_DARK
	if sunken:
		sb.border_width_left = 2
		sb.border_width_top = 2
	else:
		sb.border_width_right = 2
		sb.border_width_bottom = 2
	box.add_theme_stylebox_override("panel", sb)
	return box


func _on_time_changed(t: float) -> void:
	time_label.text = "%.1f" % maxf(t, 0.0)
	var c := Color(1.0, 0.3, 0.3) if t < 5.0 else Color.WHITE
	time_label.add_theme_color_override("font_color", c)
	_update_tray_clock(t)


# The tray clock shows time left as seconds until midnight on Dec 31 1999.
# At zero the date rolls over to 1900: the millennium bug strikes.
@warning_ignore("integer_division")
func _update_tray_clock(t: float) -> void:
	var left := ceili(maxf(t, 0.0))
	if left <= 0:
		_tray_clock.text = "1/1/1900  12:00:00 AM"
	else:
		var secs := 86400 - left
		var h := secs / 3600
		var h12 := 12 if h % 12 == 0 else h % 12
		_tray_clock.text = "12/31/1999  %d:%02d:%02d %s" % [
			h12, (secs % 3600) / 60, secs % 60, "PM" if h >= 12 else "AM"]
	var c := Color(0.8, 0.0, 0.0) if t < LOW_TIME else Color.BLACK
	_tray_clock.add_theme_color_override("font_color", c)


func _center_word_popup() -> void:
	word_popup.position = Vector2((1280.0 - word_popup.size.x) / 2.0, 170.0)


# WordPopup shows itself; just make sure a leftover flicker didn't leave it faded.
# Also shows a taskbar button for the window (WordPopup sets its title first,
# since it connected to the signal before us).
func _on_trick_started(_word: String, _air_time: float) -> void:
	word_popup.modulate = Color.WHITE
	_task_label.text = word_popup.get_window_title()
	_task_button.show()


# No "+3.0s" toast here: P3's timer_fx already floats the time bonus next to the clock.
func _on_trick_succeeded(_bonus: float) -> void:
	_task_button.hide()


func _on_trick_failed() -> void:
	_task_button.hide()
	_toast("MISSED!", Color(0.75, 0.0, 0.0))


func _toast(text: String, color: Color) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", color)
	toast_label.reset_size()
	toast_label.position = Vector2((1280.0 - toast_label.size.x) / 2.0, 110.0)
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
		# "scramble" is handled by WordPopup itself.
		"popup": _glitch_popup()


# Blink the word on/off a few times. Uses alpha, not visible, so it never
# fights WordPopup's own show/hide.
func _glitch_flicker() -> void:
	if _flicker_busy:
		return
	_flicker_busy = true
	for i in FLICKER_STEPS:
		word_popup.modulate.a = 0.0
		await _wait(0.06)
		word_popup.modulate.a = 1.0
		await _wait(0.06)
	_flicker_busy = false


# Spawns a fake OS-style window somewhere on screen, but NEVER over the typing window,
# so the player can always read the word. Purely visual, auto-closes.
func _glitch_popup() -> void:
	var win := Panel.new()
	win.size = Vector2(randf_range(240.0, 340.0), randf_range(110.0, 150.0))
	win.position = _popup_spot(win.size)
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


# Random spot for a fake ad that does not touch the typing window (which resizes to fit
# the word, so we read its current rect every time). Falls back to just below/above it.
func _popup_spot(win_size: Vector2) -> Vector2:
	var keep_clear := Rect2(word_popup.position, word_popup.size).grow(POPUP_CLEARANCE)
	var max_y := 720.0 - TASKBAR_H - win_size.y - 10.0
	for i in 30:
		var pos := Vector2(randf_range(10.0, 1270.0 - win_size.x), randf_range(80.0, max_y))
		if not keep_clear.intersects(Rect2(pos, win_size)):
			return pos
	# No free spot found (very wide word window): put it below, or above if there's no room.
	var x := clampf(keep_clear.get_center().x - win_size.x * 0.5, 10.0, 1270.0 - win_size.x)
	if keep_clear.end.y + win_size.y <= 720.0 - TASKBAR_H:
		return Vector2(x, keep_clear.end.y)
	return Vector2(x, maxf(80.0, keep_clear.position.y - win_size.y))


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
