class_name CommentaryPick
extends RefCounted


var pick := 0


func _init(seed_value: int = 0) -> void:
	pick = seed_value


func randi_range(from: int, to: int) -> int:
	var span := to - from + 1
	if span <= 1:
		return from
	return from + posmod(pick, span)
