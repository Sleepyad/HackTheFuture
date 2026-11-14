class_name SkyBackground
extends Node2D
## D2 - Dusk city parallax.
## Eight PSD layers exported from assets/sprite/Dusk, stacked back-to-front and
## scrolled at different rates. Main calls scroll() every frame with the distance
## the world travelled, so slow-mo during a trick slows the skyline too.

const SRC_W := 512.0                  # source art size
const SRC_H := 288.0
const VIEW_W := 1280.0                # viewport size
const VIEW_H := 720.0
const ZOOM := VIEW_H / SRC_H          # 2.5 -> art fills the screen exactly
const TILE_W := SRC_W * ZOOM          # 1280 px per copy
const COPIES := 2                     # enough to cover the screen while wrapping

# Back to front. The order matches the original PSD stack (0 is the sky plate,
# 7 the foreground wires); factor is the fraction of the world speed each gets.
const LAYERS := [
	{"file": "Dusk_0007_0.png", "factor": 0.00},   # sky + gradient
	{"file": "Dusk_0006_1.png", "factor": 0.05},
	{"file": "Dusk_0005_2.png", "factor": 0.02},   # moon - almost pinned
	{"file": "Dusk_0004_3.png", "factor": 0.12},
	{"file": "Dusk_0003_4.png", "factor": 0.20},
	{"file": "Dusk_0002_5.png", "factor": 0.30},
	{"file": "Dusk_0001_6.png", "factor": 0.45},   # the big towers
	{"file": "Dusk_0000_7.png", "factor": 0.65},   # power lines in front
]
const DIR := "res://assets/sprite/Dusk/Original/"

var _layers: Array[Dictionary] = []   # {sprites: Array[Sprite2D], factor: float}


func _ready() -> void:
	for i in LAYERS.size():
		var data: Dictionary = LAYERS[i]
		var tex: Texture2D = load(DIR + String(data["file"]))
		var sprites: Array[Sprite2D] = []
		for copy in COPIES:
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # keep the pixels crisp
			s.scale = Vector2(ZOOM, ZOOM)
			s.position = Vector2(copy * TILE_W, 0.0)
			s.z_index = i                                          # relative to this node (-20)
			add_child(s)
			sprites.append(s)
		_layers.append({"sprites": sprites, "factor": float(data["factor"])})


# Called by Main with the distance the world moved this frame (px).
func scroll(dist: float) -> void:
	for layer in _layers:
		var factor: float = layer["factor"]
		if factor == 0.0:
			continue
		var sprites: Array = layer["sprites"]
		for s: Sprite2D in sprites:
			s.position.x -= dist * factor
			if s.position.x <= -TILE_W:
				s.position.x += TILE_W * COPIES
