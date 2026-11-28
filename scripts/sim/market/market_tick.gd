class_name MarketTick
extends RefCounted


const DAY_KEY := "market_day"
const AI_KEY := "market_ai"

static var _clubs_key := ""
static var _club_ids: Array = []


static func enabled(season: LeagueSeason) -> bool:
	if season == null or season.save == null:
		return false
	return str(season.save.meta.get(AI_KEY, "on")) == "on"


static func advance(season: LeagueSeason, from_date: String, to_date: String) -> bool:
	if season == null or season.save == null or to_date == "" or from_date == to_date:
		return false
	for day in pending_days(season, from_date, to_date):
		step(season, str(day))
	season.market_date = to_date
	season.market_ticks += 1
	return true


static func step(season: LeagueSeason, day: String) -> void:
	if season == null or season.save == null or day == "":
		return
	if day.ends_with("-01"):
		MarketFinanceFlows.month(day)
		MarketFinanceFlows.tick_gates(season, day)
	MarketLoans.review(season, day)
	if not enabled(season):
		return
	MarketAi.run_day(season, day)
	MarketCompleteness.ensure_day(season, day)


static func pending_days(season: LeagueSeason, from_date: String, to_date: String) -> Array:
	var out: Array = []
	if season == null or season.save == null or from_date == "" or to_date <= from_date:
		return out
	var seen := str(season.save.meta.get(DAY_KEY, ""))
	var day := from_date
	while day < to_date:
		day = FixtureCalendar.add_days(day, 1)
		if seen != "" and day <= seen:
			continue
		out.append(day)
	if not out.is_empty():
		season.market_days += out.size()
		season.market_day = to_date
		season.save.put_meta(DAY_KEY, to_date)
	return out


static func walk(season: LeagueSeason, from_date: String, to_date: String) -> int:
	return pending_days(season, from_date, to_date).size()


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


static func clubs() -> Array:
	var key := "%s#%d" % [PLDatabase.current_path(), _season_index()]
	if key == _clubs_key and not _club_ids.is_empty():
		return _club_ids
	_clubs_key = key
	_club_ids = []
	for row in PLDatabase.rows(
			"SELECT c.id FROM club c JOIN club_finance f ON f.club_id = c.id "
			+ "WHERE c.stub = 0 ORDER BY c.id;"):
		_club_ids.append(str(row.get("id", "")))
	return _club_ids


static func invalidate() -> void:
	_clubs_key = ""
	_club_ids = []
	MarketNeeds.invalidate()


static func _season_index() -> int:
	return LeagueSave.current.season_index() if LeagueSave.current != null else 0


static func roll(season: LeagueSeason, date: String, key: String) -> float:
	var seed_value := 0
	if season != null and season.save != null:
		seed_value = int(str(season.save.meta.get("seed", "0")))
	var h := absi(seed_value) + 7919
	for part in [str(date), str(key)]:
		var text := str(part)
		for i in range(text.length()):
			h = int((h * 31 + text.unicode_at(i)) % 2147483647)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	return rng.randf()
