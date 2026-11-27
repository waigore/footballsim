class_name InterestLayer
extends Control


var hold: InterestHold = null

var screen = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if hold == null or screen == null or not hold.is_open():
		return
	hold.vp = screen.design_vp()
	hold.menu.mouse = screen.mouse if screen is Control else Vector2(-1000, -1000)
	hold.menu.draw(self, hold.vp, UiChrome.fonts())


