extends CanvasLayer
## Autoload "GlitchFx" (D3): full-screen glitchy words. Owns the big "OOF!" that slams in
## when the skater hits an obstacle, and offers pop() so other scripts (the skater's trick
## name, for one) can reuse the same appear/disappear-in-glitch effect.
## Sits above the HUD (10) and TimerFx (15), under the title / game over screens (20).

const OOF_COLOR := Color(1.0, 0.18, 0.28)


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.player_hit_obstacle.connect(_on_hit_obstacle)
	Game.game_started.connect(_clear)
	Game.game_over.connect(func(_s: float) -> void: _clear())


# Generic glitch word, `center` in screen pixels.
func pop(text: String, font_size: int, color: Color, center: Vector2, angle := 0.0, hold := 0.6) -> void:
	GlitchText.spawn(self, text, font_size, color, center, angle, hold)


func _on_hit_obstacle() -> void:
	# Replace a still-visible OOF instead of stacking them.
	for c in get_children():
		if c is GlitchText:
			c.queue_free()
	# Low and to the right of the skater: the typing window sits above (y 170-320), so the
	# word being typed stays readable while the OOF slams in.
	pop("OOF!", 170, OOF_COLOR, Vector2(700, 455), randf_range(-0.12, 0.12), 0.55)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
