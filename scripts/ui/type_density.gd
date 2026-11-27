class_name TypeDensity
extends RefCounted

## How many device pixels one design unit lands on, so type is rasterized at the
## resolution it is really drawn at (issue #337).
##
## The overlay and the non-match sheets lay out in a smaller design space and are
## then scaled back up by a `CanvasLayer` transform. That transform is not part
## of a `CanvasItem`'s global transform, so the font rasterizer never sees it: it
## rasterizes glyph atlases at the viewport's oversampling (the window's stretch
## factor alone) and the GPU then magnifies every glyph. On a high-DPI phone that
## is a 2.2x upscale of a 1.2x atlas, which is the soft type the reporter saw;
## a 1440p desktop window has the same seam at 1.6x.
##
## `Viewport.oversampling_override` is the one lever that moves the atlas
## density, and it does not touch glyph metrics: advances, ascent and centring
## read the same numbers at every density, so no rect moves.

## Ceiling on the multiplier: a 1440p phone lands near 3.5, and a glyph atlas
## past this is memory spent for no visible gain.
const MAX := 4.0

## Device pixels per viewport unit: the window's own size over the size the
## stretch gives the viewport. A headless run has no window, so it reads 1.0.
static func window_stretch(view: Viewport) -> float:
	if view == null:
		return 1.0
	var visible: Vector2 = view.get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if visible.x <= 0.0 or visible.y <= 0.0 or window.x <= 0.0 or window.y <= 0.0:
		return 1.0
	return maxf(window.x / visible.x, window.y / visible.y)

## The oversampling factor a layer drawn at `layer_scale` needs: the window's
## stretch times the layer's own scale. A layer at or under 1.0 never shrinks
## type below the engine's own density.
static func multiplier(stretch: float, layer_scale: float) -> float:
	return clampf(maxf(stretch, 1.0) * maxf(layer_scale, 1.0), 1.0, MAX)

## Point the viewport's glyph atlases at that density. Returns the factor used;
## an engine-default density clears the override (0.0) so a desktop window keeps
## the stock path. Safe to call on every resize and every frame: it reads the
## window, not state, and a factor that has not changed is not rewritten.
static func apply(view: Viewport, layer_scale: float) -> float:
	if view == null:
		return 0.0
	var want: float = multiplier(window_stretch(view), layer_scale)
	var value: float = 0.0 if is_equal_approx(want, 1.0) else want
	if not is_equal_approx(view.oversampling_override, value):
		view.oversampling_override = value
	return want
