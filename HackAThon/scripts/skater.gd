class_name Skater
extends CharacterBody2D
## Skater: stays at a fixed x (the world scrolls past). Jumps are triggered by Main
## via try_jump(), which starts the typing trick through Game.start_trick().

const JUMP_HEIGHT := 150.0          # apex height in px
const DEFAULT_GRAVITY := 2400.0

var _gravity := DEFAULT_GRAVITY
var _home := Vector2.ZERO
var _tween: Tween

@onready var body: Node2D = $Body   # all placeholder visuals live here (rotate/scale this)


func _ready() -> void:
	_home = position
	Game.trick_started.connect(_on_trick_started)
	Game.trick_succeeded.connect(_on_trick_succeeded)
	Game.trick_failed.connect(_on_trick_failed)


func _physics_process(delta: float) -> void:
	velocity.y += _gravity * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = 0.0
		_gravity = DEFAULT_GRAVITY


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
	body.rotation = 0.0
	body.scale = Vector2.ONE
	body.modulate = Color.WHITE


# Jump arc is sized so the flight lasts exactly the trick's air time in GAME time
# (real air_time * slow-mo scale). Peak height stays JUMP_HEIGHT.
func _on_trick_started(_word: String, air_time: float) -> void:
	var t := maxf(air_time * Game.SLOWMO_SCALE, 0.1)
	_gravity = 8.0 * JUMP_HEIGHT / (t * t)
	velocity.y = -4.0 * JUMP_HEIGHT / t
	play_jump()


func _on_trick_succeeded(_bonus: float) -> void:
	play_trick_success()


func _on_trick_failed() -> void:
	play_trick_fail()


# ---------- PLACEHOLDER ANIMATIONS: swap the bodies for AnimatedSprite2D calls ----------

# e.g. $AnimatedSprite2D.play("jump")
func play_jump() -> void:
	pass


# e.g. $AnimatedSprite2D.play("kickflip")
func play_trick_success() -> void:
	if _tween:
		_tween.kill()
	body.rotation = 0.0
	_tween = create_tween()
	_tween.tween_property(body, "rotation", TAU, 0.35)
	_tween.tween_callback(func() -> void: body.rotation = 0.0)


# e.g. $AnimatedSprite2D.play("bail")
func play_trick_fail() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(body, "modulate", Color(1.0, 0.3, 0.3), 0.1)
	_tween.tween_property(body, "rotation", 0.7, 0.15)
	_tween.tween_property(body, "rotation", 0.0, 0.25)
	_tween.tween_property(body, "modulate", Color.WHITE, 0.2)
