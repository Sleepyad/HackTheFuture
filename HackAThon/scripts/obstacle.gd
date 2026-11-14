class_name Obstacle
extends Node2D
## One street hazard. The sheets are plain strips/grids, so a single Sprite2D with
## hframes/vframes is enough - no SpriteFrames resource needed.
##
## `art` is the tight bounding box of the drawing inside one cell (measured once,
## hard-coded here). We use it to park the node's origin on the obstacle's bottom-left
## corner, which is what Main's spawn and jump-trigger maths expect, and to report a
## `width` that matches what the player actually sees.
const KINDS := {
	"dog": {
		"texture": "res://assets/sprite/dog/Dog.png",
		"hframes": 8, "vframes": 2, "first": 8, "frames": 8,   # row 1 = the yellow dog
		"art": Rect2(0, 2, 16, 14), "fps": 10.0, "zoom": 4.2, "flip": false, "hover": 0.0,
	},
	"cat": {
		"texture": "res://assets/sprite/cat/cat_walk.png",
		"hframes": 8, "vframes": 1, "first": 0, "frames": 8,
		"art": Rect2(0, 0, 28, 30), "fps": 8.0, "zoom": 2.5, "flip": false, "hover": 0.0,
	},
	"grandma": {
		"texture": "res://assets/sprite/grandma/grandma_walk.png",
		"hframes": 7, "vframes": 1, "first": 0, "frames": 7,   # art walks right, flip to face us
		"art": Rect2(1, 0, 15, 16), "fps": 7.0, "zoom": 4.2, "flip": true, "hover": 0.0,
	},
	"croc": {
		"texture": "res://assets/sprite/croc/croc_walk.png",
		"hframes": 6, "vframes": 1, "first": 0, "frames": 6,
		"art": Rect2(1, 17, 29, 15), "fps": 9.0, "zoom": 3.2, "flip": false, "hover": 0.0,
	},
	"balloon": {
		"texture": "res://assets/sprite/ballon/Balloon.png",
		"region": Rect2(90, 40, 150, 240),                     # crop the padding off
		"hframes": 1, "vframes": 1, "first": 0, "frames": 1,
		"art": Rect2(0, 0, 150, 240), "fps": 0.0, "zoom": 0.36, "flip": false, "hover": 8.0,
	},
}

var width := 48.0                      # Main uses this for spacing and jump timing

var _first := 0
var _frames := 1
var _fps := 0.0
var _time := 0.0
var _hover := 0.0
var _base_y := 0.0

@onready var sprite: Sprite2D = $Sprite


static func random_kind() -> String:
	var keys: Array = KINDS.keys()
	return keys[randi() % keys.size()]


# Call right after instantiate(); works before the node is in the tree.
func setup(kind: String) -> void:
	if not KINDS.has(kind):
		kind = "dog"
	var d: Dictionary = KINDS[kind]
	if sprite == null:
		sprite = $Sprite

	var tex: Texture2D = load(String(d["texture"]))
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var cell := Vector2(tex.get_width() / float(d["hframes"]), tex.get_height() / float(d["vframes"]))
	if d.has("region"):
		var r: Rect2 = d["region"]
		sprite.region_enabled = true
		sprite.region_rect = r
		cell = r.size
	else:
		sprite.hframes = int(d["hframes"])
		sprite.vframes = int(d["vframes"])

	_first = int(d["first"])
	_frames = int(d["frames"])
	_fps = float(d["fps"])
	_hover = float(d["hover"])
	sprite.frame = _first
	sprite.flip_h = bool(d["flip"])

	var zoom := float(d["zoom"])
	sprite.scale = Vector2(zoom, zoom)

	# Sprite2D draws the cell centred on its position. Shift it so the node's origin
	# lands on the bottom-left of the visible art.
	var art: Rect2 = d["art"]
	width = art.size.x * zoom
	sprite.position = Vector2(
		(cell.x * 0.5 - art.position.x) * zoom,
		(cell.y * 0.5 - art.position.y - art.size.y) * zoom - _hover
	)
	_base_y = sprite.position.y


func _process(delta: float) -> void:
	if _fps > 0.0 and _frames > 1:
		_time += delta
		sprite.frame = _first + int(_time * _fps) % _frames
	if _hover > 0.0:
		sprite.position.y = _base_y + sin(Time.get_ticks_msec() * 0.004) * _hover
