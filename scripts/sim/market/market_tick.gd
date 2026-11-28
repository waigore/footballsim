class_name MarketTick
extends RefCounted


const DAY_KEY := "market_day"


static func advance(save: LeagueSave, from_date: String, to_date: String) -> Dictionary:
	if save == null or to_date == "" or from_date == to_date:
		return {"ok": false, "days": 0, "date": to_date}
	var days := walk(save, from_date, to_date)
	post_months(save, from_date, to_date)
	MarketLoans.review(save, to_date)
	return {"ok": true, "days": days, "date": to_date}


static func post_months(save: LeagueSave, from_date: String, to_date: String) -> int:
	if from_date.length() < 7 or to_date.length() < 7:
		return 0
	var year := int(from_date.substr(0, 4))
	var month := int(from_date.substr(5, 2))
	var last_year := int(to_date.substr(0, 4))
	var last_month := int(to_date.substr(5, 2))
	var posted := 0
	while year < last_year or (year == last_year and month < last_month):
		month += 1
		if month > 12:
			month = 1
			year += 1
		var stamp := "%04d-%02d-01" % [year, month]
		posted += MarketFinanceFlows.month(stamp)
		MarketFinanceFlows.tick_gates(save, stamp)
	return posted


static func walk(save: LeagueSave, from_date: String, to_date: String) -> int:
	if save == null or from_date == "" or to_date <= from_date:
		return 0
	var seen := str(save.meta.get(DAY_KEY, ""))
	var day := from_date
	var walked := 0
	while day < to_date:
		day = FixtureCalendar.add_days(day, 1)
		if seen != "" and day <= seen:
			continue
		walked += 1
	if walked > 0:
		save.put_meta(DAY_KEY, to_date)
	return walked


static func window_days(from_date: String, to_date: String, country: String) -> int:
	if from_date == "" or to_date <= from_date:
		return 0
	var day := from_date
	var count := 0
	while day < to_date:
		day = FixtureCalendar.add_days(day, 1)
		if not MarketWindows.open_window(day, country).is_empty():
			count += 1
	return count


static func roll(save: LeagueSave, date: String, key: String) -> float:
	var seed_value := 0
	if save != null:
		seed_value = int(str(save.meta.get("seed", "0")))
	var h := absi(seed_value) + 7919
	for part in [str(date), str(key)]:
		var text := str(part)
		for i in range(text.length()):
			h = int((h * 31 + text.unicode_at(i)) % 2147483647)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	return rng.randf()
