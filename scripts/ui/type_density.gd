class_name TypeDensity
extends RefCounted


const MAX := 4.0

static func window_stretch(view: Viewport) -> float:
	if view == null:
		return 1.0
	var visible: Vector2 = view.get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if visible.x <= 0.0 or visible.y <= 0.0 or window.x <= 0.0 or window.y <= 0.0:
		return 1.0
	return maxf(window.x / visible.x, window.y / visible.y)

static func multiplier(stretch: float, layer_scale: float) -> float:
	return clampf(maxf(stretch, 1.0) * maxf(layer_scale, 1.0), 1.0, MAX)

static func apply(view: Viewport, layer_scale: float) -> float:
	if view == null:
		return 0.0
	var want: float = multiplier(window_stretch(view), layer_scale)
	var value: float = 0.0 if is_equal_approx(want, 1.0) else want
	if not is_equal_approx(view.oversampling_override, value):
		view.oversampling_override = value
	return want
