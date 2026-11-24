class_name LeagueOverlay
extends Control

## The league's top layer: the left slide panel and the long-press interest
## menu. It sits above `LeagueBody` so the panel is painted over scrolling rows
## and is not clipped to the body band.
##
## Geometry and paint belong to `LeaguePanel` / `InterestMenu`; this node only
## asks them to draw in design space.

var ui_scale := 1.0
var fonts: Dictionary = {}
var panel: LeaguePanel = null
var menu: InterestMenu = null
var active_pose := ""
## Repaint one extra frame after the menu closes, so its last pixels go away.
var _was_painting := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)

## The panel animates through its own update; the interest menu has no clock of
## its own, so this layer watches it and clears the frame after it closes.
func _process(_delta: float) -> void:
	var painting := menu != null and menu.open
	if painting or _was_painting:
		queue_redraw()
	_was_painting = painting

func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp

# gd-tools: no cover start

func _draw() -> void:
	var vp := design_vp()
	if panel != null:
		panel.draw(self, vp, fonts, active_pose)
	if menu != null and menu.open:
		menu.draw(self, vp, fonts, LeagueInterest.marked(menu.club_id))

# gd-tools: no cover end
