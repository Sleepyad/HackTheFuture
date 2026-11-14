class_name GlitchText
extends Control
## A word that stutters in, holds, then tears itself away (OOF!, 360 SPIN!, ...).
## The text is drawn as horizontal bands, each a clipped copy of the label, so the
## glitch really slices the letters sideways; two tinted copies behind it give the
## red/cyan split. Timing uses real time, so it keeps its pace during slow-mo.
##
## GlitchText.spawn(parent, "OOF!", 150, Color.RED, Vector2(640, 300), -0.1, 0.7)

const BANDS := 6
const IN_TIME := 0.28                    # stutter-in
const OUT_TIME := 0.34                   # tear-out
const SHIFT := 0.5                       # max sideways shove, as a fraction of the text height

var _bands: Array[Control] = []          # clipped strips
var _band_labels: Array[Label] = []      # the copy inside each strip
var _ghost_r: Label
var _ghost_c: Label
var _text_size := Vector2.ZERO
var _hold := 0.6
var _born := 0
var _tint := Color.WHITE


static func spawn(parent: Node, text: String, font_size: int, color: Color, center: Vector2,
		angle := 0.0, hold := 0.6) -> GlitchText:
	var g := GlitchText.new()
	g._hold = hold
	g._tint = color
	g._build(text, font_size, color)
	g.position = center - g._text_size * 0.5
	g.pivot_offset = g._text_size * 0.5
	g.rotation = angle
	parent.add_child(g)
	return g


func _build(text: String, font_size: int, color: Color) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

	# Measure once with the default font; the label copies all use the same settings.
	var font := ThemeDB.fallback_font
	_text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(24, 20)
	size = _text_size

	_ghost_r = _make_label(text, font_size, Color(1.0, 0.1, 0.25, 0.75))
	_ghost_c = _make_label(text, font_size, Color(0.1, 0.95, 1.0, 0.75))
	add_child(_ghost_r)
	add_child(_ghost_c)

	var band_h := _text_size.y / float(BANDS)
	for i in BANDS:
		var strip := Control.new()
		strip.clip_contents = true
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.position = Vector2(0.0, band_h * i)
		strip.size = Vector2(_text_size.x * 2.0, band_h + 1.0)
		var l := _make_label(text, font_size, color)
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1, 1))
		l.add_theme_constant_override("outline_size", 12)
		l.position = Vector2(0.0, -band_h * i)
		strip.add_child(l)
		add_child(strip)
		_bands.append(strip)
		_band_labels.append(l)
	_born = Time.get_ticks_msec()
	_apply(1.0)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.size = _text_size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _process(_delta: float) -> void:
	var t := float(Time.get_ticks_msec() - _born) / 1000.0
	var out_start := IN_TIME + _hold
	if t >= out_start + OUT_TIME:
		queue_free()
		return

	var amount := 0.0                    # 0 = clean, 1 = fully torn
	var visible_now := true
	if t < IN_TIME:
		amount = 1.0 - t / IN_TIME
		visible_now = randf() < 0.35 + 0.65 * (t / IN_TIME)       # flickers on, more often as it settles
	elif t < out_start:
		# holding: a quick single-frame twitch now and then keeps it alive
		amount = 0.55 if randf() < 0.05 else 0.0
	else:
		var k := (t - out_start) / OUT_TIME
		amount = k
		visible_now = randf() > 0.15 + 0.7 * k                    # flickers off, more often as it dies
	visible = visible_now
	_apply(amount)


# amount 0 -> bands lined up, ghosts hidden. amount 1 -> bands shoved apart, ghosts split wide.
func _apply(amount: float) -> void:
	var h := _text_size.y
	for i in BANDS:
		var torn := randf() < 0.35 + 0.5 * amount                # not every band moves
		var dx := randf_range(-1.0, 1.0) * h * SHIFT * amount if torn else 0.0
		_band_labels[i].position.x = dx
	var split := h * 0.10 * amount
	_ghost_r.position = Vector2(-split, randf_range(-2.0, 2.0) * amount)
	_ghost_c.position = Vector2(split, randf_range(-2.0, 2.0) * amount)
	_ghost_r.visible = amount > 0.02
	_ghost_c.visible = amount > 0.02
	modulate.a = 1.0 - 0.3 * amount * randf()
