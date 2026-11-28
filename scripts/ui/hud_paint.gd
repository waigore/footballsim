class_name HudPaint
extends RefCounted


static var BORDER: Color = HudChrome.BORDER

var ink: HudChrome = null
var vp := Vector2(1600, 900)

var followed := {}

func _init(surface: HudChrome, viewport_size: Vector2) -> void:
	ink = surface
	vp = viewport_size


func compact() -> bool:
	return HudLayout.is_compact(vp)

func panel(c: CanvasItem, fill: Color, r: Rect2, radius: int = 10, border: Color = Color(-1, -1, -1, -1)) -> void:
	ink.panel(c, fill, r, radius, border)

func text(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font, outline: int = 0, outline_col: Color = Color(0, 0, 0, 0.5)) -> void:
	ink.text(c, pos, s, size, color, font, outline, outline_col)

func text_c(c: CanvasItem, center_x: float, y: float, s: String, size: int, color: Color, font: Font) -> void:
	ink.text_c(c, center_x, y, s, size, color, font)

func text_r(c: CanvasItem, right_x: float, y: float, s: String, size: int, color: Color, font: Font) -> void:
	ink.text_r(c, right_x, y, s, size, color, font)

func add_button(id: String, r: Rect2, label: String, hint: String) -> void:
	ink.add_button(id, r, label, hint)
