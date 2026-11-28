class_name MatchCadence
extends RefCounted


const MIN_GAP := 420.0


const NEUTRAL_PATIENCE := 0.52


const SPAN := 3.0


static func tactics_gap(profile: Dictionary) -> float:
	var patience := clampf(float(profile.get("patience", NEUTRAL_PATIENCE)), 0.0, 1.0)
	return MIN_GAP * (1.0 + maxf(0.0, patience - NEUTRAL_PATIENCE) * SPAN)


static func may_change(profile: Dictionary, since_last: float) -> bool:
	return since_last >= tactics_gap(profile)
