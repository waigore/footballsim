class_name LeaguePinned
extends Control


var body: LeagueBody = null

var fonts: Dictionary = {}


var cache: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if body == null:
		return
	for item in body.pinned:
		LeagueChrome.pinned_door(self, cache, item, fonts)


