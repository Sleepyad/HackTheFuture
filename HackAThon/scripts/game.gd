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
const BONUS_EASY := 3.0             # seconds added on a clean word
const BONUS_HARD := 1.5
const PENALTY_PER_KEY := 0.5        # seconds lost per wrong key
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

enum State { RUNNING, TRICK, GAME_OVER }

var state: State = State.RUNNING
var time_left := START_TIME
var elapsed := 0.0                           # real seconds survived
var difficulty := 0.0                        # 0.0 -> 1.0

var target_word := ""
var typed_count := 0
var _air_left := 0.0
var _glitch_timer := 0.0


func _ready() -> void:
	reset()


func reset() -> void:
	Engine.time_scale = 1.0
	state = State.RUNNING
	time_left = START_TIME
	elapsed = 0.0
	difficulty = 0.0
	target_word = ""
	typed_count = 0
	time_changed.emit(time_left)


func _process(delta: float) -> void:
	if state == State.GAME_OVER:
		return

	# _process delta is scaled by Engine.time_scale. Convert back to REAL time
	# so slow-mo does not give free clock time.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)

	elapsed += real_delta
	difficulty = clampf(elapsed / RAMP_SECONDS, 0.0, 1.0)

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


# For the HUD: the word as it should be DRAWN during a scramble glitch.
# The real target_word is never changed, so input checking stays correct.
func scrambled_display() -> String:
	var chars := target_word.split("")
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
	if success:
		var bonus := lerpf(BONUS_EASY, BONUS_HARD, difficulty)
		_add_time(bonus)
		trick_succeeded.emit(bonus)
	else:
		trick_failed.emit()
	target_word = ""
	typed_count = 0


func _add_time(seconds: float) -> void:
	time_left = clampf(time_left + seconds, 0.0, MAX_TIME)
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
