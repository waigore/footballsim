class_name LeagueRoundup
extends RefCounted

## A fixture's events, read as two sides: the goals, cards and injuries that sit
## under the club they belong to, in minute order, with a goal's assist in
## brackets (#168).
##
## The row that prints them gives each side its own column, so an entry never
## carries its club's label — the column is the label. A goal is credited to the
## club stored on its row, which for an own goal is the side that gained it; the
## row says `(OG)` so the reader still knows the ball went in off the other
## side's player. Assist rows are folded into the goal they served instead of
## taking a line of their own; a report whose goals have no assist rows (a
## watched fixture) reads exactly the same, only without the bracket.
##
## Geometry and text only, no nodes: the sheets paint what this returns.

## The report kind an own goal is stored under, beside a goal row that carries
## the flag itself.
const OWN_GOAL := "own_goal"
## The mark that names an own goal on the line, the grammar the broadcast card
## already uses.
const OG := " (OG)"

## True when the row put the ball in the net: a goal, or an own goal that still
## counts for the side its club names.
static func is_goal(e: Dictionary) -> bool:
	var kind := str(e.get("kind", ""))
	return kind == "goal" or kind == OWN_GOAL

## True when the goal was put in off the conceding side's own player.
static func is_own_goal(e: Dictionary) -> bool:
	return str(e.get("kind", "")) == OWN_GOAL or bool(e.get("own_goal", false))

## The rows of a report in the order the report prints them: by minute, then by
## the order the ledger wrote them. Rows without an id (a test, a hand-made
## report) keep the order they arrived in.
static func ordered(events: Array) -> Array:
	var keyed: Array = []
	for i in range(events.size()):
		keyed.append({"i": i, "e": events[i]})
	keyed.sort_custom(func(a, b):
		var ma := int((a["e"] as Dictionary).get("minute", 0))
		var mb := int((b["e"] as Dictionary).get("minute", 0))
		if ma != mb:
			return ma < mb
		var ia := int((a["e"] as Dictionary).get("id", 0))
		var ib := int((b["e"] as Dictionary).get("id", 0))
		if ia != ib:
			return ia < ib
		return int(a["i"]) < int(b["i"]))
	var out: Array = []
	for item in keyed:
		out.append(item["e"])
	return out

## Every row that takes a line on the sheet: assists are folded into their goal
## and do not print on their own.
static func lines(report: Dictionary) -> Array:
	var events := ordered(report.get("events", []))
	var assists: Array = []
	for e in events:
		if str(e.get("kind", "")) == "assist":
			assists.append({"e": e, "used": false})
	var out: Array = []
	for e in events:
		var kind := str(e.get("kind", ""))
		if kind == "assist":
			continue
		var row: Dictionary = (e as Dictionary).duplicate()
		if is_own_goal(row):
			# An own goal has no assister: the ball went in off the wrong foot.
			row.erase("assist_name")
		elif is_goal(row) and str(row.get("assist_name", "")) == "":
			var helper := _take_assist(assists, str(row.get("club_id", "")), int(row.get("minute", 0)))
			if helper != "":
				row["assist_name"] = helper
		out.append(row)
	return out

## The side column a row belongs to: the club on the row decides it, and a row
## that names neither side (an older save, a hand-made report) reads under the
## home column rather than vanishing.
static func side_of(fixture: Dictionary, e: Dictionary) -> String:
	var club := str(e.get("club_id", ""))
	if club == str(fixture.get("away_club_id", "")) and club != "":
		return "away"
	return "home"

## Every printing row split by side, each side already in minute order.
static func sides(report: Dictionary) -> Dictionary:
	var fixture: Dictionary = report.get("fixture", {})
	var out := {"home": [], "away": []}
	for e in lines(report):
		var side := side_of(fixture, e)
		var bucket: Array = out[side]
		bucket.append(e)
	return out

## The goal rows of a report in report order: the ordinals the ▶ doors and the
## stored clips are keyed by.
static func goals(report: Dictionary) -> Array:
	var out: Array = []
	for e in lines(report):
		if is_goal(e):
			out.append(e)
	return out

## One line as a column prints it: `6' Y. Pino (J. Eze)`, `58' J. Mateta (OG)`.
static func line(e: Dictionary) -> String:
	var name := _player(e)
	if is_own_goal(e):
		name += OG
	var assist := str(e.get("assist_name", ""))
	if assist != "":
		name += " (%s)" % assist
	return "%d' %s" % [int(e.get("minute", 0)), name]

static func _player(e: Dictionary) -> String:
	# A row with no player join comes back as NULL, not an empty string.
	var raw = e.get("player_name", null)
	var name := "" if raw == null else str(raw)
	if name == "":
		raw = e.get("detail", null)
		name = "" if raw == null else str(raw)
	return name if name != "" else "Unknown"

## The first unused assist row for this side and minute. Synthetic reports write
## the assist row straight after its goal, so the first match is the right one.
static func _take_assist(assists: Array, club_id: String, minute: int) -> String:
	for slot in assists:
		if bool(slot["used"]):
			continue
		var e: Dictionary = slot["e"]
		if str(e.get("club_id", "")) != club_id or int(e.get("minute", 0)) != minute:
			continue
		slot["used"] = true
		return _player(e)
	return ""
