class_name HudLayout
extends RefCounted

## Shared geometry for the bottom broadcast strip. The commentary ticker sits
## above the control bar, and both rects are read from here so a layout test can
## prove the panel never covers a button at any supported viewport.

const CONTROL_W := 108.0
const CONTROL_GAP := 6.0
const CONTROL_H := 46.0
const CONTROL_COUNT := 6

static func controls_rect(vp: Vector2) -> Rect2:
	var total := CONTROL_W * CONTROL_COUNT + CONTROL_GAP * (CONTROL_COUNT - 1)
	return Rect2(vp.x * 0.5 - total * 0.5, vp.y - 66.0, total, CONTROL_H)

static func commentary_rect(vp: Vector2) -> Rect2:
	return Rect2(24.0, vp.y - 126.0, minf(620.0, vp.x - 48.0), 52.0)
