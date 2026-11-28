class_name AttrRoles
extends RefCounted


static func is_defender(role: String) -> bool:
	return role in ["RB", "LB", "CB", "RCB", "LCB", "RWB", "LWB"]


static func is_mid(role: String) -> bool:
	return role in ["CDM", "RDM", "LDM", "CM", "RM", "LM", "CAM"]


static func is_forward(role: String) -> bool:
	return role in ["RW", "LW", "ST", "CF"]


static func is_wide(role: String) -> bool:
	return role in ["RB", "LB", "RWB", "LWB", "RW", "LW", "RM", "LM"]


static func is_gk(role: String) -> bool:
	return role == "GK"


static func role_push(role: String) -> float:
	match role:
		"ST":
			return 1.0
		"RW", "LW":
			return 0.8
		"CAM":
			return 0.7
		"CM", "RDM", "LDM", "CDM":
			return 0.35
		"RB", "LB":
			return 0.3
		"CB", "RCB", "LCB":
			return 0.05
	return 0.3
