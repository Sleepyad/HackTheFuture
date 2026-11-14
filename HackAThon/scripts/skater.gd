class_name Skater
extends CharacterBody2D
## Skater: stays at a fixed x (the world scrolls past). Jumps are triggered by Main
## via try_jump(), which starts the typing trick through Game.start_trick().

const JUMP_HEIGHT := 150.0          # apex height in px
const DEFAULT_GRAVITY := 2400.0
const TRICKS: Array[String] = ["backflip", "frontflip", "kickflip", "shuvit", "360 spin"]

signal trick_performed(trick_name: String)   # lets the HUD show the name if it wants to

var _gravity := DEFAULT_GRAVITY
var _home := Vector2.ZERO
var _tween: Tween
var _board_scale := Vector2.ONE   # board sprite is scaled up in the scene

@onready var body: Node2D = $Body   # all placeholder visuals live here (rotate/scale this)
@onready var board: Sprite2D = $Body/Board


func _ready() -> void:
	_board_scale = board.scale            # Sprite2D is centred, so it already spins on its middle
	_home = position
	Game.trick_started.connect(_on_trick_started)
	Game.trick_succeeded.connect(_on_trick_succeeded)
	Game.trick_failed.connect(_on_trick_failed)
	Game.combo_changed.connect(_on_combo_changed)


func _physics_process(delta: float) -> void:
	velocity.y += _gravity * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = 0.0
		_gravity = DEFAULT_GRAVITY
	Sfx.skate_state(is_on_floor())         # roll loop + landing thud


# True when we may start a new jump/trick.
func can_jump() -> bool:
	return is_on_floor() and Game.state == Game.State.RUNNING


# Called by Main when an obstacle is close. Game.start_trick() emits trick_started
# synchronously, which sets our jump velocity in _on_trick_started().
func try_jump() -> void:
	if can_jump():
		Game.start_trick()


# Puts the skater back at the start (used on restart).
func reset() -> void:
	if _tween:
		_tween.kill()
	position = _home
	velocity = Vector2.ZERO
	_gravity = DEFAULT_GRAVITY
	_reset_pose()
	body.modulate = Color.WHITE


# Jump arc is sized so the flight lasts exactly the trick's air time in GAME time
# (real air_time * slow-mo scale). Peak height stays JUMP_HEIGHT.
func _on_trick_started(_word: String, air_time: float) -> void:
	if not is_on_floor():
		return                       # combo word in the same jump: keep flying, no new jump
	var t := maxf(air_time * Game.SLOWMO_SCALE, 0.1)
	_gravity = 8.0 * JUMP_HEIGHT / (t * t)
	velocity.y = -4.0 * JUMP_HEIGHT / t
	play_jump()


func _on_trick_succeeded(_bonus: float) -> void:
	play_trick_success()


func _on_trick_failed() -> void:
	play_trick_fail()


# Floating "COMBO xN" above the trick name when another word is chained in the same jump.
func _on_combo_changed(multiplier: int) -> void:
	var l := Label.new()
	l.text = "COMBO x%d" % multiplier
	l.position = Vector2(-60, -160)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	await get_tree().create_timer(0.9, true, false, true).timeout
	if is_instance_valid(l):
		l.queue_free()


# ---------- PLACEHOLDER ANIMATIONS: swap the bodies for AnimatedSprite2D calls ----------

# e.g. $AnimatedSprite2D.play("jump")
func play_jump() -> void:
	pass


# Picks a random trick from TRICKS and plays it. Add a name to TRICKS and a case here
# for a new one. With real sprites: $AnimatedSprite2D.play(trick)
func play_trick_success() -> void:
	if _tween:
		_tween.kill()
	_reset_pose()
	var trick: String = TRICKS.pick_random()
	match trick:
		"backflip": _flip(-TAU)      # counter-clockwise = backwards for a right-facing skater
		"frontflip": _flip(TAU)
		"kickflip": _spin_board()
		"shuvit": _flip_board()
		"360 spin": _spin_body()
	trick_performed.emit(trick)
	_show_trick_name(trick)


# Whole body rotates one full turn.
func _flip(angle: float) -> void:
	_tween = create_tween()
	_tween.tween_property(body, "rotation", angle, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_reset_pose)


# Board spins in place under the feet.
func _spin_board() -> void:
	_tween = create_tween()
	_tween.tween_property(board, "rotation", TAU, 0.4)
	_tween.tween_callback(_reset_pose)


# Board turns around (mirror flip) and back.
func _flip_board() -> void:
	_tween = create_tween()
	_tween.tween_property(board, "scale:x", -_board_scale.x, 0.2)
	_tween.tween_property(board, "scale:x", _board_scale.x, 0.2)
	_tween.tween_callback(_reset_pose)


# Whole body turns around its vertical axis (squash to flat and back out mirrored, then back).
func _spin_body() -> void:
	_tween = create_tween()
	_tween.tween_property(body, "scale:x", -1.0, 0.2)
	_tween.tween_property(body, "scale:x", 1.0, 0.2)
	_tween.tween_callback(_reset_pose)


func _reset_pose() -> void:
	body.rotation = 0.0
	body.scale = Vector2.ONE
	board.rotation = 0.0
	board.scale = _board_scale


# The trick name glitches in above the skater, holds a moment, then tears away.
func _show_trick_name(trick: String) -> void:
	var at := get_global_transform_with_canvas().origin + Vector2(120.0, -235.0)
	GlitchFx.pop(trick.to_upper() + "!", 54, Color(1.0, 0.9, 0.2), at, -0.1, 0.6)


# e.g. $AnimatedSprite2D.play("bail")
func play_trick_fail() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(body, "modulate", Color(1.0, 0.3, 0.3), 0.1)
	_tween.tween_property(body, "rotation", 0.7, 0.15)
	_tween.tween_property(body, "rotation", 0.0, 0.25)
	_tween.tween_property(body, "modulate", Color.WHITE, 0.2)
