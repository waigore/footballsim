class_name DisplayCaps
extends RefCounted

## Platform capability queries live here so gameplay and view code never branch
## on the OS or the display backend directly (RUB-P3-05).

## False on a headless run: there is no window to read a rendered frame back
## from, so a capture step has to degrade to a no-op instead of erroring.
static func can_read_frame() -> bool:
	return DisplayServer.get_name() != "headless"
