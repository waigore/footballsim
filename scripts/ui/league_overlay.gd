class_name LeagueOverlay
extends Control

## The league's top layer: the left slide panel, and the one confirmation the
## sheets raise over themselves (a save is deleted for good). It sits above
## `LeagueBody`, so both are painted over scrolling rows and are not clipped to
## the body band.
##
## Geometry and paint belong to `LeaguePanel` / `LeagueDelete`; this node only
## asks them to draw in design space and keeps its reading scale in sync with the
## screen.

var ui_scale := 1.0
var fonts: Dictionary = {}
var panel: LeaguePanel = null
var active_pose := ""
## The hosting screen: it owns the pointer and the touch reading, exactly like
## `InterestLayer` does for the shortlist menu.
var screen = null
## The load list's delete question, empty while no save is waiting for an answer.
var delete: LeagueDelete = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp

## The open question reads its hover every frame, like the shortlist menu.
func _process(_delta: float) -> void:
	if delete != null and delete.is_open():
		queue_redraw()

# gd-tools: no cover start

func _draw() -> void:
	if panel == null:
		return
	var vp := design_vp()
	panel.draw(self, vp, fonts, active_pose)
	if delete == null or not delete.is_open():
		return
	delete.paint(self, vp, fonts, screen.mouse if screen is Control else Vector2(-1000, -1000),
		screen != null and screen.touch)

# gd-tools: no cover end
