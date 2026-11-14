extends Node
## Autoload "Sfx" (D5): music + every sound effect, all driven by Game's signals so no other
## scene has to know about audio. The only direct calls are Sfx.skate_state() from the
## skater (needs the physics floor flag) and Sfx.glitch() from the title screen.
## Everything that fades or times out ignores Engine.time_scale: slow-mo during a trick
## must not stretch the sounds.

# ---------- TUNING ----------
const MUSIC_DB := -7.0
const MUSIC_PITCH_PER_LEVEL := 0.05      # level 1 = 1.00x ... level 8 = 1.35x (tempo AND pitch)
const MUSIC_RAMP := 0.8                  # seconds to glide to the next speed
const ROLL_DB := -9.0
const KEY_DB := -4.0
const HIT_DB := -11.0                    # the 8-bit blip layered on every correct letter
const MAX_VOICES := 14

const MUSIC := preload("res://assets/music/electronic_outlaw.wav")
const ROLL := preload("res://assets/sound/skateboard-roll-loop.wav")
const OLLIE := preload("res://assets/sound/skateboard-ollie-26b3e768.mp3")
const LAND := preload("res://assets/sound/skateboard-ollie-land-566869e8.mp3")
const HIT := preload("res://assets/sound/8bit-shoot8.wav")
const DAMAGE := preload("res://assets/sound/8bit-damage7.wav")

const KEYS: Array[AudioStream] = [
	preload("res://assets/sound/single key/keypress-011.wav"),
	preload("res://assets/sound/single key/keypress-012.wav"),
	preload("res://assets/sound/single key/keypress-013.wav"),
	preload("res://assets/sound/single key/keypress-014.wav"),
	preload("res://assets/sound/single key/keypress-015.wav"),
]
const GLITCHES: Array[AudioStream] = [
	preload("res://assets/sound/glitch/mixkit-electric-buzz-glitch-2594.wav"),
	preload("res://assets/sound/glitch/mixkit-glitch-roar-1033.wav"),
	preload("res://assets/sound/glitch/mixkit-glitch-static-1457.wav"),
]
# One power-up jingle per adjective, in step with Game.RATINGS: Nice, Hot, Amazing, Feverish.
const POWERUPS: Array[AudioStream] = [
	preload("res://assets/sound/powerUp/8bit-powerup7.wav"),
	preload("res://assets/sound/powerUp/8bit-powerup8.wav"),
	preload("res://assets/sound/powerUp/8bit-powerup9.wav"),
	preload("res://assets/sound/powerUp/8bit-powerup6.wav"),
]

# The ollie clip is roll -> pop (~1.7 s) -> air -> landing crack (~2.3 s). We only want the
# pop, so jump starts just before it and is cut before the crack.
const OLLIE_FROM := 1.58
const OLLIE_LEN := 0.5
const LAND_LEN := 0.55                   # the land clip rolls on for 2 s; the loop takes over

var _music: AudioStreamPlayer
var _roll: AudioStreamPlayer
var _roll_tween: Tween
var _music_tween: Tween
var _voices: Array[AudioStreamPlayer] = []
var _voice_gen: Array[int] = []          # play sequence number per voice (stale fade-outs compare it)
var _seq := 0
var _rolling := false
var _was_on_floor := true
var _air_since := 0                      # real msec when the skater left the ground


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music = _make_player(MUSIC, MUSIC_DB)
	_roll = _make_player(ROLL, -60.0)
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
		_voice_gen.append(0)

	Game.game_started.connect(_on_game_started)
	Game.game_over.connect(_on_game_over)
	Game.level_changed.connect(_on_level_changed)
	Game.trick_started.connect(_on_trick_started)
	Game.key_correct.connect(_on_key_correct)
	Game.key_wrong.connect(_on_key_wrong)
	Game.word_rated.connect(_on_word_rated)
	Game.player_hit_obstacle.connect(_on_hit_obstacle)

	_music.play()                        # title screen music (web builds wait for the first click)


# ---------- PUBLIC ----------

# Title screen burst. `length` is how long the visual glitch lasts; the clip is cut to match.
func glitch(length: float) -> void:
	play(GLITCHES.pick_random(), -3.0, randf_range(0.9, 1.1), 0.0, length + 0.08)


# Called every physics frame by the skater. Handles the roll loop and the landing thud.
func skate_state(on_floor: bool) -> void:
	var live := Game.state == Game.State.RUNNING or Game.state == Game.State.TRICK
	var now := Time.get_ticks_msec()
	if not on_floor and _was_on_floor:
		_air_since = now
	if on_floor and not _was_on_floor and live and now - _air_since > 150:
		play(LAND, -2.0, randf_range(0.95, 1.05), 0.0, LAND_LEN)
	_was_on_floor = on_floor
	_set_rolling(on_floor and live)
	if _roll.playing:
		_roll.pitch_scale = lerpf(0.85, 1.3, Game.difficulty)    # faster road, faster rumble


# One-shot with an optional start offset and length cap (seconds, 0 = whole clip).
func play(stream: AudioStream, volume_db := 0.0, pitch := 1.0, from := 0.0, max_len := 0.0) -> void:
	var i := _free_voice()
	var p := _voices[i]
	_seq += 1
	_voice_gen[i] = _seq
	var gen := _seq
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play(from)
	if max_len > 0.0:
		var t := create_tween().set_ignore_time_scale(true)
		t.tween_interval(maxf(max_len - 0.06, 0.0))
		t.tween_property(p, "volume_db", -50.0, 0.06)
		t.tween_callback(func() -> void:
			if _voice_gen[i] == gen:
				p.stop())


# ---------- GAME EVENTS ----------

func _on_game_started() -> void:
	_glide_music(1.0, 0.2)
	if not _music.playing:
		_music.play()


func _on_game_over(_survived: float) -> void:
	_glide_music(1.0, 1.2)               # don't leave the game over screen at 1.35x
	_set_rolling(false)


# The music speeds up one notch per level.
func _on_level_changed(level: int) -> void:
	_glide_music(1.0 + float(level - 1) * MUSIC_PITCH_PER_LEVEL, MUSIC_RAMP)


func _on_trick_started(_word: String, _air_time: float) -> void:
	play(OLLIE, -2.0, randf_range(0.97, 1.04), OLLIE_FROM, OLLIE_LEN)


# Every letter: a keyboard clack. A correct one also gets an 8-bit blip that climbs with
# the position in the word, so finishing a word sounds like an arpeggio.
func _on_key_correct(index: int) -> void:
	play(KEYS.pick_random(), KEY_DB, randf_range(0.96, 1.06))
	play(HIT, HIT_DB, minf(1.0 + 0.07 * float(index), 1.6))


# A miss: dull clack plus a short burst of digital noise.
func _on_key_wrong(_penalty: float) -> void:
	play(KEYS.pick_random(), KEY_DB, 0.8)
	play(GLITCHES.pick_random(), -4.0, randf_range(0.95, 1.15), 0.0, 0.35)


# Same signal TimerFx listens to for the "Nice!" / "Hot!" tag, so jingle and word pop together.
func _on_word_rated(_adjective: String, tier: int) -> void:
	play(POWERUPS[clampi(tier, 0, POWERUPS.size() - 1)], -3.0)


func _on_hit_obstacle() -> void:
	play(DAMAGE, -2.0)


# ---------- INTERNALS ----------

func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)
	return p


# Prefer an idle voice; if all are busy, steal the one that started playing longest ago.
func _free_voice() -> int:
	for i in _voices.size():
		if not _voices[i].playing:
			return i
	var oldest := 0
	for i in _voices.size():
		if _voice_gen[i] < _voice_gen[oldest]:
			oldest = i
	return oldest


func _glide_music(pitch: float, seconds: float) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_ignore_time_scale(true)
	_music_tween.tween_property(_music, "pitch_scale", pitch, seconds).set_trans(Tween.TRANS_SINE)


func _set_rolling(on: bool) -> void:
	if on == _rolling:
		return
	_rolling = on
	if _roll_tween:
		_roll_tween.kill()
	_roll_tween = create_tween().set_ignore_time_scale(true)
	if on:
		if not _roll.playing:
			_roll.play()
		_roll_tween.tween_property(_roll, "volume_db", ROLL_DB, 0.12)
	else:
		_roll_tween.tween_property(_roll, "volume_db", -60.0, 0.1)
		_roll_tween.tween_callback(_roll.stop)
