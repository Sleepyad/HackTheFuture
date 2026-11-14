extends Node
# Autoload this script as "Game" (Project > Project Settings > Globals > Autoload).
# Godot 4.x. Handles: countdown, difficulty ramp, trick typing, penalties, bonuses, glitch rolls.

# ---------- TUNING (change these, not the logic) ----------
const START_TIME := 30.0            # seconds on the clock at the start
const MAX_TIME := 60.0              # clock can never exceed this
const SLOWMO_SCALE := 0.3           # world speed during a trick (option B). 1.0 = normal
const RAMP_SECONDS := 180.0         # how long until difficulty hits max (1.0)

# values at difficulty 0.0 (easy) and 1.0 (hard)
const WORD_LEN_EASY := 3
const WORD_LEN_HARD := 6
const AIR_TIME_EASY := 3.0          # real seconds the player has to type the word
const AIR_TIME_HARD := 1.8
const BONUS_EASY := 3.0             # seconds added on a clean word at level 1
const BONUS_HARD := 1.5             # ... at MAX_LEVEL
const PENALTY_PER_KEY := 0.5        # seconds lost per wrong key
const OBSTACLE_PENALTY := 3.0       # seconds lost when the skater hits an obstacle
const HIT_COOLDOWN := 0.6           # real seconds; one obstacle can only cost time once
const LEVEL_SECONDS := 25.0         # a new level every N real seconds (C3)
const MAX_LEVEL := 8
const POINTS_PER_WORD := 5          # score = seconds survived + POINTS_PER_WORD * words
const GLITCH_CHANCE_MAX := 0.6      # chance per roll at max difficulty
const GLITCH_ROLL_EVERY := 0.8      # real seconds between glitch rolls during a trick

const WORDS := {
	3: ["web", "pop", "cd", "aol", "msn", "dot", "net", "bug", "pc", "cam"],
	4: ["wifi", "icq", "mail", "disk", "byte", "chat", "dial", "beep", "y2k", "boot"],
	5: ["modem", "email", "pager", "login", "flash", "pixel", "cyber", "virus", "popup", "burn"],
	6: ["floppy", "online", "browse", "napster", "screen", "reboot", "client", "cookie", "domain", "banner"],
}

# ---------- SIGNALS (connect your skater, HUD, glitch FX to these) ----------
signal trick_started(word: String, air_time: float)
signal key_correct(index: int)               # index of the letter just typed
signal key_wrong(penalty: float)
signal trick_succeeded(bonus: float)
signal trick_failed()                        # ran out of air time
signal glitch(kind: String)                  # "flicker", "scramble", "popup"
signal time_changed(time_left: float)
signal game_over(survived_seconds: float)
# Names from the stories PDF (Events.gd), so everyone can plug into them:
signal game_started()                        # a run begins (Main calls Game.reset())
signal level_changed(level: int)             # 1, 2, 3 ... every LEVEL_SECONDS
signal player_landed()                       # trick over, slow-mo off
signal player_hit_obstacle()                 # emitted by hit_obstacle()
signal time_delta(seconds: float)            # any +/- change to the clock (bonus, penalty)

enum State { IDLE, RUNNING, TRICK, GAME_OVER }   # IDLE = title screen, clock stopped

var state: State = State.IDLE
var time_left := START_TIME
var elapsed := 0.0                           # real seconds survived
var difficulty := 0.0                        # 0.0 -> 1.0 (continuous, for speed etc.)
var level := 1                               # 1 -> MAX_LEVEL (steps, see level_changed)
var words_completed := 0
var _hit_cooldown := 0.0

var target_word := ""
var typed_count := 0
var _air_left := 0.0
var _glitch_timer := 0.0


func _ready() -> void:
	_clear()
	state = State.IDLE                       # clock waits for the first reset() (Play)


# Starts a new run. Main calls this when Play / Restart is pressed.
func reset() -> void:
	_clear()
	state = State.RUNNING
	time_changed.emit(time_left)
	game_started.emit()
	level_changed.emit(level)


func _clear() -> void:
	Engine.time_scale = 1.0
	time_left = START_TIME
	elapsed = 0.0
	difficulty = 0.0
	level = 1
	words_completed = 0
	_hit_cooldown = 0.0
	target_word = ""
	typed_count = 0


func _process(delta: float) -> void:
	if state == State.GAME_OVER or state == State.IDLE:
		return

	# _process delta is scaled by Engine.time_scale. Convert back to REAL time
	# so slow-mo does not give free clock time.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)

	elapsed += real_delta
	difficulty = clampf(elapsed / RAMP_SECONDS, 0.0, 1.0)
	_hit_cooldown -= real_delta

	var new_level := mini(1 + int(elapsed / LEVEL_SECONDS), MAX_LEVEL)
	if new_level != level:
		level = new_level
		level_changed.emit(level)

	time_left -= real_delta
	time_changed.emit(time_left)

	if state == State.TRICK:
		_air_left -= real_delta
		_glitch_timer -= real_delta
		if _glitch_timer <= 0.0:
			_glitch_timer = GLITCH_ROLL_EVERY
			_roll_glitch()
		if _air_left <= 0.0:
			_end_trick(false)

	if time_left <= 0.0:
		time_left = 0.0
		_set_game_over()


# ---------- PUBLIC API ----------
# Call this from the skater when it jumps.
func start_trick() -> void:
	if state != State.RUNNING:
		return
	state = State.TRICK
	typed_count = 0
	target_word = _pick_word()
	_air_left = lerpf(AIR_TIME_EASY, AIR_TIME_HARD, difficulty)
	_glitch_timer = GLITCH_ROLL_EVERY
	Engine.time_scale = SLOWMO_SCALE
	trick_started.emit(target_word, _air_left)


# Call this when the skater touches an obstacle (P1 / A2). Safe to call every frame
# while overlapping: the cooldown makes one obstacle cost OBSTACLE_PENALTY once.
func hit_obstacle() -> void:
	if state != State.RUNNING and state != State.TRICK:
		return
	if _hit_cooldown > 0.0:
		return
	_hit_cooldown = HIT_COOLDOWN
	player_hit_obstacle.emit()
	penalty(OBSTACLE_PENALTY)


# Removes `seconds` from the clock (positive number) and shows "-Xs".
func penalty(seconds: float) -> void:
	if state != State.RUNNING and state != State.TRICK:
		return
	_add_time(-absf(seconds))


# Final score for the game over screen (C4).
func score() -> int:
	return int(elapsed) + words_completed * POINTS_PER_WORD


# Bonus for a clean word; drops as the level goes up (C3).
func current_bonus() -> float:
	var t := float(level - 1) / float(MAX_LEVEL - 1)
	return lerpf(BONUS_EASY, BONUS_HARD, t)


# For the HUD: the word as it should be DRAWN during a scramble glitch.
# The real target_word is never changed, so input checking stays correct.
func scrambled_display() -> String:
	var chars: Array = Array(target_word.split(""))   # PackedStringArray has no shuffle()
	chars.shuffle()
	return "".join(chars)


# ---------- INPUT ----------
func _unhandled_input(event: InputEvent) -> void:
	if state != State.TRICK:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:            # ignore key repeat
		return
	if key.unicode == 0:                       # ignore shift/ctrl/arrows etc.
		return

	var typed := char(key.unicode).to_lower()
	if typed.length() != 1:
		return
	# only react to letters and digits
	if not (typed >= "a" and typed <= "z") and not (typed >= "0" and typed <= "9"):
		return

	var expected := target_word[typed_count].to_lower()
	if typed == expected:
		key_correct.emit(typed_count)
		typed_count += 1
		if typed_count >= target_word.length():
			_end_trick(true)
	else:
		_add_time(-PENALTY_PER_KEY)
		key_wrong.emit(PENALTY_PER_KEY)
		# stay on the same letter, player just retries it


# ---------- INTERNALS ----------
func _end_trick(success: bool) -> void:
	state = State.RUNNING
	Engine.time_scale = 1.0
	target_word = ""
	typed_count = 0
	player_landed.emit()
	if success:
		words_completed += 1
		var bonus := current_bonus()
		_add_time(bonus)
		trick_succeeded.emit(bonus)
	else:
		trick_failed.emit()


func _add_time(seconds: float) -> void:
	var before := time_left
	time_left = clampf(time_left + seconds, 0.0, MAX_TIME)
	if not is_equal_approx(time_left, before):
		time_delta.emit(time_left - before)
	time_changed.emit(time_left)
	if time_left <= 0.0:
		_set_game_over()


func _set_game_over() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	Engine.time_scale = 1.0
	game_over.emit(elapsed)


func _pick_word() -> String:
	var length := roundi(lerpf(WORD_LEN_EASY, WORD_LEN_HARD, difficulty))
	length = clampi(length, WORD_LEN_EASY, WORD_LEN_HARD)
	var bucket: Array = WORDS[length]
	return bucket[randi() % bucket.size()]


func _roll_glitch() -> void:
	if randf() > difficulty * GLITCH_CHANCE_MAX:
		return
	var kinds := ["flicker", "scramble", "popup"]
	glitch.emit(kinds[randi() % kinds.size()])
