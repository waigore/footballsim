class_name InterestLayer
extends Control

## Paints the long-press menu (#107) above a sheet's body. Every surface that
## hosts an `InterestHold` drops one in as its last child, so the menu sits over
## scrolling rows without each sheet growing its own overlay.

## The handler that decides whether the menu is up and what it says.
var hold: InterestHold = null
## The hosting screen: it owns the pointer (design space) and the sheet scale.
var screen = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

## The menu reads the pointer every frame, so a hover that never moved an event
## still lights the door under it.
func _process(_delta: float) -> void:
	queue_redraw()

# gd-tools: no cover start

func _draw() -> void:
	if hold == null or screen == null or not hold.is_open():
		return
	hold.vp = screen.design_vp()
	hold.menu.mouse = screen.mouse if screen is Control else Vector2(-1000, -1000)
	# The footer names the pointer's verb, so the host hands its own device over
	# (#310): the same menu is raised on a desktop sheet and on a phone HUD.
	var device = screen.get("touch")
	hold.menu.touch = device != null and bool(device)
	hold.menu.draw(self, hold.vp, UiChrome.fonts())

# gd-tools: no cover end
