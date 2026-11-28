class_name LeagueClock
extends RefCounted


static func move(season: LeagueSeason, from_date: String, to_date: String) -> bool:
	if season == null or season.save == null or to_date == "":
		return false
	season.save.set_date(to_date)
	season.save.set_matchday(season.matchday_of(to_date))
	SeasonAvailability.month_tick(from_date, to_date)
	var tick := MarketTick.advance(season.save, from_date, to_date)
	if bool(tick.get("ok", false)):
		season.market_date = str(tick.get("date", to_date))
		season.market_ticks += 1
		season.market_days += int(tick.get("days", 0))
		season.market_day = to_date
	return true
