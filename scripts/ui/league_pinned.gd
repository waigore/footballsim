class_name LeaguePinned
extends Control

## The doors a league sheet pins in screen space — BACK, the hub's CONTINUE, the
## table's reading doors, the calendar's month chips — painted above the body's
## clip.
##
## `LeagueBody` clips its own `_draw`, and Godot clips a Control's own commands as
## well as its children's. Every pinned door sits outside the body's band (BACK
## and CONTINUE in the header lane above it, the table's readings under the bar
## below it), so painting them in the body threw the pixels away: the hub's
## CONTINUE and the table's two reading doors never reached the screen, while
## BACK survived only because `LeagueExtra.header` paints a second one on the
## sheet itself (#284).
##
## The body still owns the rects, the press and the freeze; this layer is a
## sibling above the body, in the same design space and with no clip, so a pinned
## door paints over the rows it covers — which is what "pinned" means.

## The body whose pinned doors this layer paints.
var body: LeagueBody = null
## The font set the pinned doors draw with, refreshed by the screen on layout.
var fonts: Dictionary = {}
## The sheet's style cache, so a pinned door's style boxes are shared with the
## rows instead of built again on every paint.
var cache: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# gd-tools: no cover start

func _draw() -> void:
	if body == null:
		return
	for item in body.pinned:
		LeagueChrome.pinned_door(self, cache, item, fonts)

# gd-tools: no cover end
