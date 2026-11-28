class_name LeagueClock
extends RefCounted


static func move(season: LeagueSeason, from_date: String, to_date: String) -> bool:
	if season == null or season.save == null or to_date == "":
		return false
	season.save.set_date(to_date)
	season.save.set_matchday(season.matchday_of(to_date))
	SeasonAvailability.month_tick(from_date, to_date)
	MarketTick.advance(season, from_date, to_date)
	return true
