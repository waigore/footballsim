class_name AttrKeeper
extends RefCounted


static func reach(p: Variant) -> float:
	var ref: float = float(p.gk["ref"])
	return 0.95 + ref * 0.0105


static func reaction(p: Variant) -> float:
	var ref: float = float(p.gk["ref"])
	return maxf(0.10, 0.34 - ref * 0.0024)


static func dive_reach(p: Variant) -> float:
	var div: float = float(p.gk["div"])
	return 0.85 + div * 0.0115


static func handling(p: Variant) -> float:
	return float(p.gk["han"]) / 100.0
