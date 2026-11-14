extends Node2D
## Main: scrolling parallax world, obstacle spawner, automatic jump trigger, run flow.
## The skater stays put; the background, road stripes and obstacles move left. All
## scrolling uses _process delta, which Godot scales by Engine.time_scale, so slow-mo
## during tricks is free.

const W := 1280.0
const GROUND_Y := 560.0
const SPEED_EASY := 400.0            # px/s at difficulty 0
const SPEED_HARD := 850.0            # px/s at difficulty 1 (C: faster ramp)
const GAP_MIN := 520.0               # px between obstacles
const GAP_MAX := 780.0
const SPAWN_X := W + 60.0

const OBSTACLE_SCENE := preload("res://scenes/obstacle.tscn")

var playing := false
var _layers: Array[Dictionary] = []  # {node, factor, span}
var _obstacles: Array[Obstacle] = []
var _next_gap := GAP_MIN
var _last_kind := ""

@onready var skater: Skater = $Skater
@onready var background: SkyBackground = $Background
@onready var obstacle_root: Node2D = $Obstacles
@onready var hud: GameHUD = $HUD
@onready var screens: GameScreens = $Screens


func _ready() -> void:
	# Dusk skyline parallax lives in Background.tscn; here we only add the road dashes.
	_build_layer($StripeLayer, 610.0, Vector2(50, 70), Vector2(6, 6), Vector2(70, 110), Color(1, 0.95, 0.75, 0.55), 1.0)
	hud.visible = false                      # Game's clock ticks from boot; hide until a run starts
	screens.start_requested.connect(_start_run)
	Game.game_over.connect(_on_game_over)


func _process(delta: float) -> void:
	if not playing:
		return
	var speed := lerpf(SPEED_EASY, SPEED_HARD, Game.difficulty)
	background.scroll(speed * delta)
	_scroll_layers(speed * delta)
	_move_obstacles(speed * delta)
	_maybe_spawn()
	_check_jump_trigger(speed)


# ---------- RUN FLOW ----------

# Starts (or restarts) a run. Game.reset() also zeroes the clock that ran during the title.
func _start_run() -> void:
	for o in _obstacles:
		o.queue_free()
	_obstacles.clear()
	_next_gap = GAP_MIN
	skater.reset()
	Game.reset()
	hud.reset()
	hud.visible = true
	playing = true


func _on_game_over(survived: float) -> void:
	if not playing:
		return                               # clock expired while on the title screen
	playing = false
	screens.show_game_over(survived)


# ---------- ROAD DASHES ----------

# Fills `root` with random ColorRects in a row, wide enough to wrap seamlessly.
func _build_layer(root: Node2D, y_bottom: float, w: Vector2, h: Vector2, gap: Vector2, color: Color, factor: float) -> void:
	var x := 0.0
	while x < W + 300.0:
		var r := ColorRect.new()
		r.size = Vector2(randf_range(w.x, w.y), randf_range(h.x, h.y))
		r.position = Vector2(x, y_bottom - r.size.y)
		r.color = color
		root.add_child(r)
		x += r.size.x + randf_range(gap.x, gap.y)
	_layers.append({"node": root, "factor": factor, "span": x})


func _scroll_layers(dist: float) -> void:
	for layer in _layers:
		var root: Node2D = layer["node"]
		var span: float = layer["span"]
		for child in root.get_children():
			var r := child as ColorRect
			r.position.x -= dist * float(layer["factor"])
			if r.position.x + r.size.x < 0.0:
				r.position.x += span         # wrap to the right end


# ---------- OBSTACLES ----------

func _move_obstacles(dist: float) -> void:
	for i in range(_obstacles.size() - 1, -1, -1):
		var o := _obstacles[i]
		o.position.x -= dist
		if o.position.x + o.width < -80.0:
			o.queue_free()
			_obstacles.remove_at(i)


func _maybe_spawn() -> void:
	if not _obstacles.is_empty() and _obstacles.back().position.x > W - _next_gap:
		return
	var kind := Obstacle.random_kind()
	while kind == _last_kind:                # don't send the same critter twice in a row
		kind = Obstacle.random_kind()
	_last_kind = kind
	var o: Obstacle = OBSTACLE_SCENE.instantiate()
	o.setup(kind)
	o.position = Vector2(SPAWN_X, GROUND_Y)
	obstacle_root.add_child(o)
	_obstacles.append(o)
	_next_gap = randf_range(GAP_MIN, GAP_MAX)


# Jumps when an obstacle's centre is half a flight-distance away, so the skater is at
# the apex as it passes over. Flight is `air_time * SLOWMO_SCALE` game-seconds.
func _check_jump_trigger(speed: float) -> void:
	if not skater.can_jump():
		return
	var air := lerpf(Game.AIR_TIME_EASY, Game.AIR_TIME_HARD, Game.difficulty)
	var flight := air * Game.SLOWMO_SCALE
	for o in _obstacles:
		var dx := o.position.x + o.width * 0.5 - skater.position.x
		if dx > 0.0 and dx <= speed * flight * 0.5:
			skater.try_jump()
			return
