class_name LeagueNavStack
extends RefCounted


const CAPACITY := 30

var entries: Array = []

func depth() -> int:
	return entries.size()

func is_empty() -> bool:
	return entries.is_empty()


func push(entry: Dictionary) -> void:
	entries.append(entry)
	while entries.size() > CAPACITY:
		entries.pop_front()


func pop() -> Dictionary:
	if entries.is_empty():
		return {}
	return entries.pop_back()

func clear() -> void:
	entries.clear()


static func snapshot(screen) -> Dictionary:
	var body = screen.body
	return {
		"mode": str(screen.mode),
		"month": str(screen.month),
		"day": str(screen.day),
		"days": (screen.days_cache as Dictionary).duplicate(true),
		"day_fixtures": (screen.day_fixtures as Array).duplicate(true),
		"report": (screen.report as Dictionary).duplicate(true),
		"roundup": (screen.roundup as Array).duplicate(true),
		"report_back": str(screen.report_back),
		"query": str(screen.interest_query),
		"sys": (screen.sys as Dictionary).duplicate(true),
		"cup": str(screen.cup_focus),
		"cup_round": str(screen.cups_round),
		"draw": (screen.draw_state as Dictionary).duplicate(true),
		"deal": str(screen.deal_id),
		"scroll": float(body.scroll) if body != null else 0.0,
		"hscroll": float(body.hscroll) if body != null else 0.0,
	}


static func restore(screen, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	screen.mode = str(entry.get("mode", screen.mode))
	screen.month = str(entry.get("month", screen.month))
	screen.day = str(entry.get("day", screen.day))
	screen.days_cache = (entry.get("days", {}) as Dictionary).duplicate(true)
	screen.day_fixtures = (entry.get("day_fixtures", []) as Array).duplicate(true)
	screen.report = (entry.get("report", {}) as Dictionary).duplicate(true)
	screen.roundup = (entry.get("roundup", []) as Array).duplicate(true)
	screen.report_back = str(entry.get("report_back", screen.MODE_HUB))
	screen.interest_query = str(entry.get("query", ""))
	screen.sys = (entry.get("sys", {}) as Dictionary).duplicate(true)
	screen.cup_focus = str(entry.get("cup", screen.cup_focus))
	screen.cups_round = str(entry.get("cup_round", screen.cups_round))
	screen.draw_state = (entry.get("draw", screen.draw_state) as Dictionary).duplicate(true)
	screen.deal_id = str(entry.get("deal", screen.deal_id))
	screen.refresh()
	if screen.body != null:
		screen.body.scroll_to(float(entry.get("scroll", 0.0)))
		screen.body.hscroll_to(float(entry.get("hscroll", 0.0)))
