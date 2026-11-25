class_name HudPaint
extends RefCounted

## One overlay frame's paint scope: the overlay's shared drawing surface plus the
## design viewport it paints into, so a band module calls `p.text(...)` /
## `p.panel(...)` and never reaches into the overlay node.

const BORDER := HudChrome.BORDER

var ink: HudChrome = null
var vp := Vector2(1600, 900)
## Followed club ids as a set (#107): a followed club's name paints gold.
var followed := {}

func _init(surface: HudChrome, viewport_size: Vector2) -> void:
	ink = surface
	vp = viewport_size

## Handheld metrics: the phone layout every band switches on.
func compact() -> bool:
	return HudLayout.is_compact(vp)

func panel(c: CanvasItem, fill: Color, r: Rect2, radius: int = 10, border: Color = BORDER) -> void:
	ink.panel(c, fill, r, radius, border)

func text(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font, outline: int = 0, outline_col: Color = Color(0, 0, 0, 0.5)) -> void:
	ink.text(c, pos, s, size, color, font, outline, outline_col)

func text_c(c: CanvasItem, center_x: float, y: float, s: String, size: int, color: Color, font: Font) -> void:
	ink.text_c(c, center_x, y, s, size, color, font)

func text_r(c: CanvasItem, right_x: float, y: float, s: String, size: int, color: Color, font: Font) -> void:
	ink.text_r(c, right_x, y, s, size, color, font)

func add_button(id: String, r: Rect2, label: String, hint: String) -> void:
	ink.add_button(id, r, label, hint)
