class_name MatchContact
extends RefCounted


const NEUTRAL := 0.535


const TACKLE_SPAN := 0.16
const FOUL_SPAN := 1.20


static func tackle_bonus(style: Dictionary) -> float:
	return (bar(style) - NEUTRAL) * TACKLE_SPAN


static func foul_multiplier(style: Dictionary) -> float:
	return 1.0 + (bar(style) - NEUTRAL) * FOUL_SPAN


static func bar(style: Dictionary) -> float:
	return clampf(float(style.get("aggression", NEUTRAL)), 0.0, 1.0)
