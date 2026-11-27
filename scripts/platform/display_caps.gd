class_name DisplayCaps
extends RefCounted


static func can_read_frame() -> bool:
	return DisplayServer.get_name() != "headless"
