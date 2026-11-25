class_name LeagueOverlay
extends Control

## The league's top layer: the left slide panel. It sits above `LeagueBody` so
## the panel is painted over scrolling rows and is not clipped to the body band.
##
## Geometry and paint belong to `LeaguePanel`; this node only asks it to draw in
## design space and keeps its reading scale in sync with the screen.

var ui_scale := 1.0
var fonts: Dictionary = {}
var panel: LeaguePanel = null
var active_pose := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp

# gd-tools: no cover start

func _draw() -> void:
	if panel == null:
		return
	panel.draw(self, design_vp(), fonts, active_pose)

# gd-tools: no cover end
