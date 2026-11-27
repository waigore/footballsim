class_name LeagueOverlay
extends Control


var ui_scale := 1.0
var fonts: Dictionary = {}
var panel: LeaguePanel = null
var active_pose := ""


var screen = null

var delete: LeagueDelete = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp


func _process(_delta: float) -> void:
	if delete != null and delete.is_open():
		queue_redraw()


func _draw() -> void:
	if panel == null:
		return
	var vp := design_vp()
	panel.draw(self, vp, fonts, active_pose)
	if delete == null or not delete.is_open():
		return
	delete.paint(self, vp, fonts, screen.mouse if screen is Control else Vector2(-1000, -1000),
		screen != null and screen.touch)


