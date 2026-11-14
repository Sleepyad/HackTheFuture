class_name GameScreens
extends CanvasLayer
## Title ("Click to start") and game over screens. The click gives the web build keyboard focus.
## Buttons use FOCUS_NONE so Space/Enter typed during play can never "press" them.

signal start_requested

var _best := 0.0            # best survival this session (memory only, no file I/O)

@onready var title_screen: ColorRect = $TitleScreen
@onready var title_label: Label = $TitleScreen/TitleLabel
@onready var hint_label: Label = $TitleScreen/HintLabel
@onready var start_button: Button = $TitleScreen/StartButton
@onready var over_screen: ColorRect = $GameOverScreen
@onready var result_label: Label = $GameOverScreen/ResultLabel
@onready var restart_button: Button = $GameOverScreen/RestartButton


func _ready() -> void:
	layer = 20
	for s: ColorRect in [title_screen, over_screen]:
		s.size = Vector2(1280, 720)
		s.color = Color(0.03, 0.03, 0.1, 0.92)
	_setup_label(title_label, "SKATE.EXE", Vector2(0, 170), 96)
	_setup_label(hint_label, "Type the word to land the trick. Don't let the clock hit 0.", Vector2(0, 300), 28)
	_setup_label(result_label, "", Vector2(0, 150), 56)
	_setup_button(start_button, "CLICK TO START", Vector2(480, 430))
	_setup_button(restart_button, "RESTART", Vector2(480, 460))
	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	title_screen.show()
	over_screen.hide()


# Called by Main when Game.game_over fires.
func show_game_over(survived: float) -> void:
	_best = maxf(_best, survived)
	result_label.text = "GAME OVER\nYou survived %.1fs\nBest: %.1fs" % [survived, _best]
	over_screen.show()


func _on_start_pressed() -> void:
	title_screen.hide()
	start_requested.emit()


func _on_restart_pressed() -> void:
	over_screen.hide()
	start_requested.emit()        # Main calls Game.reset()


func _setup_label(l: Label, text: String, pos: Vector2, font_size: int) -> void:
	l.text = text
	l.position = pos
	l.size = Vector2(1280, 140)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)


func _setup_button(b: Button, text: String, pos: Vector2) -> void:
	b.text = text
	b.position = pos
	b.size = Vector2(320, 80)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
