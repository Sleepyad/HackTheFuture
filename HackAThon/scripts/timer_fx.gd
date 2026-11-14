extends CanvasLayer
## Autoload "TimerFx" (C2 / C3): floating "+2.0s" / "-3.0s" next to the clock,
## a "LEVEL N" banner when Game.level_changed fires, a small level/words counter,
## and a tilted speed adjective (Nice / Hot / Amazing / Feverish) after each clean word.
## Lives in its own file so it never clashes with hud.gd. Pure display, ignores mouse.
## All tweens ignore Engine.time_scale so they keep real-time pacing during slow-mo.

const W := 1280.0
const PLUS := Color(0.4, 1.0, 0.4)
const MINUS := Color(1.0, 0.35, 0.35)
# Speed adjectives (Game.word_rated), slow -> fast. Drawn tilted like a hand-written tag.
const RATING_COLORS: Array[Color] = [
	Color(0.55, 0.9, 1.0),    # Nice
	Color(1.0, 0.6, 0.15),    # Hot
	Color(1.0, 0.3, 0.9),     # Amazing
	Color(1.0, 0.15, 0.15),   # Feverish
]
const RATING_SIZES: Array[int] = [56, 66, 76, 88]
const RATING_ANGLE := -0.45                      # radians, rising to the right

var _stats: Label
var _banner: Label
var _banner_tween: Tween


func _ready() -> void:
	layer = 15                                   # above HUD (10), under Screens (20)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_stats = _make_label(20, Vector2(W - 260.0, 20.0), Vector2(240, 60), HORIZONTAL_ALIGNMENT_RIGHT)
	_banner = _make_label(64, Vector2(0, 250), Vector2(W, 90), HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_hide_all()

	Game.game_started.connect(_on_game_started)
	Game.game_over.connect(_on_game_over)
	Game.time_delta.connect(_on_time_delta)
	Game.level_changed.connect(_on_level_changed)
	Game.trick_succeeded.connect(_update_stats.unbind(1))
	Game.word_rated.connect(_on_word_rated)


func _on_game_started() -> void:
	_clear_floaters()
	_stats.show()
	_update_stats()


func _on_game_over(_survived: float) -> void:
	_hide_all()


func _hide_all() -> void:
	_clear_floaters()
	_stats.hide()
	_banner.hide()
	if _banner_tween:
		_banner_tween.kill()


func _update_stats() -> void:
	_stats.text = "LEVEL %d\nWORDS %d" % [Game.level, Game.words_completed]


# ---------- "+2.0s" / "-3.0s" next to the clock ----------

func _on_time_delta(seconds: float) -> void:
	var l := _make_label(36, Vector2(W / 2.0 + 90.0, 20.0), Vector2(200, 50), HORIZONTAL_ALIGNMENT_LEFT)
	l.text = "%+.1fs" % seconds
	l.add_theme_color_override("font_color", PLUS if seconds > 0.0 else MINUS)
	l.set_meta("floater", true)
	var t := create_tween().set_ignore_time_scale(true).set_parallel(true)
	t.tween_property(l, "position:y", l.position.y + (-30.0 if seconds > 0.0 else 30.0), 0.9)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	t.chain().tween_callback(l.queue_free)


# ---------- "Nice" / "Hot" / "Amazing" / "Feverish" diagonal tag ----------

func _on_word_rated(adjective: String, tier: int) -> void:
	var sz := Vector2(520, 120)
	var l := _make_label(RATING_SIZES[tier], Vector2(700, 330) + Vector2(randf_range(-30, 30), randf_range(-20, 20)), sz, HORIZONTAL_ALIGNMENT_CENTER)
	l.text = adjective + "!"
	l.add_theme_color_override("font_color", RATING_COLORS[tier])
	l.add_theme_constant_override("outline_size", 10)
	l.pivot_offset = sz / 2.0
	l.rotation = RATING_ANGLE + randf_range(-0.08, 0.08)
	l.scale = Vector2(0.3, 0.3)
	l.set_meta("floater", true)
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(l, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "scale", Vector2.ONE, 0.08)
	t.tween_interval(0.5)
	t.set_parallel(true)
	t.tween_property(l, "position", l.position + Vector2(60, -40), 0.4)
	t.tween_property(l, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(l.queue_free)


# ---------- "LEVEL N" banner ----------

func _on_level_changed(level: int) -> void:
	_update_stats()
	if level <= 1:
		return                                   # no banner at the very start
	_banner.text = "LEVEL %d" % level
	_banner.modulate.a = 1.0
	_banner.scale = Vector2.ONE
	_banner.show()
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween().set_ignore_time_scale(true)
	_banner_tween.tween_interval(1.0)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_callback(_banner.hide)


# ---------- helpers ----------

func _make_label(font_size: int, pos: Vector2, sz: Vector2, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.focus_mode = Control.FOCUS_NONE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l


func _clear_floaters() -> void:
	for c in get_children():
		if c.has_meta("floater"):
			c.queue_free()
