class_name GameScreens
extends CanvasLayer
## Title (logo sticker + "Click to start") and game over screens. The click gives the
## web build keyboard focus. Buttons use FOCUS_NONE so Space/Enter typed during play
## can never "press" them.

signal start_requested

const CARD_SIZE := Vector2(720, 414)     # white sticker holding the CONCRETE FEVER logo
const CARD_TILT := -0.055                # radians, just enough to look stuck on by hand
const CARD_POS := Vector2((1280.0 - CARD_SIZE.x) * 0.5, 70.0)

# D3 - the title glitches in short bursts instead of wobbling non-stop.
const GLITCH_GAP := Vector2(3.0, 5.0)    # real seconds between bursts (min, max)
const GLITCH_LEN := Vector2(0.22, 0.42)  # how long one burst lasts

var _best := 0.0            # best survival this session (memory only, no file I/O)
var _glitch_mat: ShaderMaterial
var _glitch_wait := 0.0
var _glitch_left := 0.0
var _glitch_span := 1.0

@onready var title_screen: ColorRect = $TitleScreen
@onready var logo_card: Panel = $TitleScreen/LogoCard
@onready var logo: TextureRect = $TitleScreen/LogoCard/Logo
@onready var hint_label: Label = $TitleScreen/HintLabel
@onready var start_button: Button = $TitleScreen/StartButton
@onready var over_screen: ColorRect = $GameOverScreen
@onready var result_label: Label = $GameOverScreen/ResultLabel
@onready var restart_button: Button = $GameOverScreen/RestartButton


func _ready() -> void:
	layer = 20
	for s: ColorRect in [title_screen, over_screen]:
		s.size = Vector2(1280, 720)
	# The title is see-through: the live dusk skyline IS the background.
	title_screen.color = Color(0, 0, 0, 0)
	over_screen.color = Color(0.03, 0.03, 0.1, 0.92)

	_setup_logo()
	_setup_label(hint_label, "Type the word to land the trick. Don't let the clock hit 0.", Vector2(0, 505), 28)
	_setup_label(result_label, "", Vector2(0, 150), 56)
	_setup_button(start_button, "CLICK TO START", Vector2(480, 565))
	_setup_button(restart_button, "RESTART", Vector2(480, 460))
	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	title_screen.show()
	over_screen.hide()
	_glitch_wait = randf_range(GLITCH_GAP.x, GLITCH_GAP.y)


func _process(delta: float) -> void:
	if _glitch_mat == null or not title_screen.visible:
		return
	if _glitch_left > 0.0:
		_run_glitch(delta)
	else:
		_glitch_wait -= delta
		if _glitch_wait <= 0.0:
			_glitch_span = randf_range(GLITCH_LEN.x, GLITCH_LEN.y)
			_glitch_left = _glitch_span
			_glitch_wait = randf_range(GLITCH_GAP.x, GLITCH_GAP.y)


# Called by Main when Game.game_over fires.
func show_game_over(survived: float) -> void:
	_best = maxf(_best, survived)
	result_label.text = "GAME OVER\nYou survived %.1fs\nBest: %.1fs" % [survived, _best]
	over_screen.show()


func _on_start_pressed() -> void:
	_clear_glitch()
	title_screen.hide()
	start_requested.emit()


func _on_restart_pressed() -> void:
	over_screen.hide()
	start_requested.emit()        # Main calls Game.reset()


# ---------- GLITCH ----------

# One burst: ramps hard, decays, and kicks the whole sticker around while it lasts.
func _run_glitch(delta: float) -> void:
	_glitch_left -= delta
	if _glitch_left <= 0.0:
		_clear_glitch()
		return
	var t := _glitch_left / _glitch_span          # 1 -> 0 across the burst
	var amount := t * t * (0.6 + randf() * 0.4)   # decays, with per-frame crackle
	_glitch_mat.set_shader_parameter("amount", amount)
	_glitch_mat.set_shader_parameter("seed_t", float(Time.get_ticks_msec()) * 0.001)
	logo_card.position = CARD_POS + Vector2(randf_range(-9.0, 9.0), randf_range(-4.0, 4.0)) * amount
	logo_card.rotation = CARD_TILT + randf_range(-0.012, 0.012) * amount
	logo_card.modulate.a = 1.0 - randf() * 0.25 * amount


func _clear_glitch() -> void:
	_glitch_left = 0.0
	if _glitch_mat != null:
		_glitch_mat.set_shader_parameter("amount", 0.0)
	logo_card.position = CARD_POS
	logo_card.rotation = CARD_TILT
	logo_card.modulate.a = 1.0


# ---------- LAYOUT ----------

# The logo art ships on a white background, so we keep that white and turn it into a
# rounded sticker instead of cutting it out - that also keeps the black "FEVER" readable.
func _setup_logo() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 1)
	box.set_corner_radius_all(22)
	box.border_width_left = 5
	box.border_width_top = 5
	box.border_width_right = 5
	box.border_width_bottom = 5
	box.border_color = Color(0.11, 0.09, 0.16, 1)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 20
	box.shadow_offset = Vector2(7, 11)
	logo_card.add_theme_stylebox_override("panel", box)

	logo_card.size = CARD_SIZE
	logo_card.position = CARD_POS
	logo_card.pivot_offset = CARD_SIZE * 0.5
	logo_card.rotation = CARD_TILT
	logo_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_card.clip_contents = true

	# expand_mode first: while it is KEEP_SIZE the texture's own 1460x838 is a minimum
	# size and any size we set gets clamped straight back up to it.
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.position = Vector2(26, 22)
	logo.size = CARD_SIZE - Vector2(52, 44)
	_glitch_mat = logo.material as ShaderMaterial


func _setup_label(l: Label, text: String, pos: Vector2, font_size: int) -> void:
	l.text = text
	l.position = pos
	l.size = Vector2(1280, 140)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	# No dark plane behind the title any more, so the text carries its own outline.
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.09, 1))
	l.add_theme_constant_override("outline_size", 10)


func _setup_button(b: Button, text: String, pos: Vector2) -> void:
	b.text = text
	b.position = pos
	b.size = Vector2(320, 80)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.07, 0.05, 0.13, 0.95) if state != "hover" else Color(0.16, 0.1, 0.24, 0.95)
		box.set_corner_radius_all(10)
		box.border_width_left = 3
		box.border_width_top = 3
		box.border_width_right = 3
		box.border_width_bottom = 3
		box.border_color = Color(1, 0.35, 0.65, 1) if state != "pressed" else Color(1, 0.82, 0.25, 1)
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 0.88, 0.45, 1))
