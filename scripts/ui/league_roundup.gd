class_name LeagueRoundup
extends RefCounted


const OWN_GOAL := "own_goal"


const OG := " (OG)"

const PEN := " (PEN)"


static func is_goal(e: Dictionary) -> bool:
	var kind := str(e.get("kind", ""))
	return kind == "goal" or kind == OWN_GOAL


static func is_own_goal(e: Dictionary) -> bool:
	return str(e.get("kind", "")) == OWN_GOAL or bool(e.get("own_goal", false))


static func is_penalty(e: Dictionary) -> bool:
	return bool(e.get("penalty", false))


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

			row.erase("assist_name")
		elif is_goal(row) and str(row.get("assist_name", "")) == "":
			var helper := _take_assist(assists, str(row.get("club_id", "")), int(row.get("minute", 0)))
			if helper != "":
				row["assist_name"] = helper
		out.append(row)
	return out


static func side_of(fixture: Dictionary, e: Dictionary) -> String:
	var club := str(e.get("club_id", ""))
	if club == str(fixture.get("away_club_id", "")) and club != "":
		return "away"
	return "home"


static func sides(report: Dictionary) -> Dictionary:
	var fixture: Dictionary = report.get("fixture", {})
	var out := {"home": [], "away": []}
	for e in lines(report):
		var side := side_of(fixture, e)
		var bucket: Array = out[side]
		bucket.append(e)
	return out


static func goals(report: Dictionary) -> Array:
	var out: Array = []
	for e in lines(report):
		if is_goal(e):
			out.append(e)
	return out


static func line(e: Dictionary) -> String:
	var name := _player(e)
	if is_own_goal(e):
		name += OG
	elif is_penalty(e):
		name += PEN
	var assist := str(e.get("assist_name", ""))
	if assist != "":
		name += " (%s)" % assist
	return "%d' %s" % [int(e.get("minute", 0)), name]

static func _player(e: Dictionary) -> String:

	var raw = e.get("player_name", null)
	var name := "" if raw == null else str(raw)
	if name == "":
		raw = e.get("detail", null)
		name = "" if raw == null else str(raw)
	return name if name != "" else "Unknown"


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
