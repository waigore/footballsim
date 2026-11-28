extends RefCounted

## The windows verb: print every association's transfer-window state from a date alone.
## No deal engine, no ledger and no UI is loaded.


static func run(options: Dictionary) -> Dictionary:
	var date := str(options.get("date", ""))
	if date == "":
		date = FixtureCalendar.date_from(FixtureCalendar.days_from("2026-07-01"))
	var board := MarketWindows.board(date)
	if board.is_empty():
		return {"ok": false, "date": date, "reason": "no associations"}
	var open := 0
	for row in board:
		if bool(row.get("open", false)):
			open += 1
		print("%s %s %s %s..%s%s" % [str(row.get("country", "")), str(row.get("code", "")),
			"OPEN" if bool(row.get("open", false)) else "CLOSED",
			str(row.get("opens_on", "")), str(row.get("closes_on", "")),
			"  (%s)" % str(row.get("source", ""))])
	var fee := MarketWindows.allows(MarketWindows.FEE, date, "ENG", "ENG")
	var free := MarketWindows.allows(MarketWindows.FREE_AGENT, date, "ENG", "ENG")
	return {
		"ok": true, "date": date, "season_label": MarketWindows.season_label(date),
		"open": open, "associations": board,
		"fee": {"ok": bool(fee.get("ok", false)), "reason": str(fee.get("reason", "")),
			"opens_on": str(fee.get("opens_on", ""))},
		"free_agent": {"ok": bool(free.get("ok", false)), "reason": str(free.get("reason", ""))},
	}
