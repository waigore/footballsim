class_name LeagueNavStack
extends RefCounted

## The season's page history: every forward move inside the league pushes the
## page it left, and BACK / Esc / Backspace pop one page at a time (#169).
##
## The stack is **session UI state** — a field of the screen, never written into
## a save. It holds at most `CAPACITY` entries; a player who walks deeper drops
## the oldest page rather than the newest, because the nearest history is what
## BACK is expected to reach.
##
## A page is a snapshot of what the pose needs to paint itself again: the mode,
## the calendar's selected day and month, the report or roundup on screen, the
## shortlist's query, the System dialog's own state, and the scroll offsets. The
## table's reading lives in the save, so it needs no entry from here.

## Deepest history BACK keeps. Older pages fall off the bottom.
const CAPACITY := 30

var entries: Array = []

func depth() -> int:
	return entries.size()

func is_empty() -> bool:
	return entries.is_empty()

## Remember the page the player is leaving. A stack at its cap drops the oldest
## entry, so the thirty most recent pages are always the ones BACK can reach.
func push(entry: Dictionary) -> void:
	entries.append(entry)
	while entries.size() > CAPACITY:
		entries.pop_front()

## The page BACK returns to, or an empty dictionary at the root.
func pop() -> Dictionary:
	if entries.is_empty():
		return {}
	return entries.pop_back()

func clear() -> void:
	entries.clear()

## Everything one pose needs to come back as it was left.
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
		"scroll": float(body.scroll) if body != null else 0.0,
		"hscroll": float(body.hscroll) if body != null else 0.0,
	}

## Put a page back exactly as it was left: its pose, its day and month, the
## report or roundup it was showing, and where it was scrolled to. The scroll
## is applied after the relayout, which is why the refresh comes first.
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
	screen.refresh()
	if screen.body != null:
		screen.body.scroll_to(float(entry.get("scroll", 0.0)))
		screen.body.hscroll_to(float(entry.get("hscroll", 0.0)))
