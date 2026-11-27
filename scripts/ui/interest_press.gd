class_name InterestPress
extends RefCounted


const HOLD := 0.45

const SLOP := 8.0


var club := ""

var at := Vector2.ZERO

var watching := false
var fired := false
var moved := false
var elapsed := 0.0


func press(point: Vector2, club_id: String) -> void:
	at = point
	club = club_id
	watching = club_id != ""
	fired = false
	moved = false
	elapsed = 0.0


func armed() -> bool:
	return watching and not fired and not moved


func move(point: Vector2) -> void:
	if armed() and point.distance_to(at) > SLOP:
		moved = true


func tick(delta: float) -> bool:
	if not armed():
		return false
	elapsed += delta
	if elapsed < HOLD:
		return false
	fired = true
	return true


func release_click() -> bool:
	var click: bool = not watching or (not fired and not moved)
	clear()
	return click


func clear() -> void:
	club = ""
	watching = false
	fired = false
	moved = false
	elapsed = 0.0
