class_name MarketTick
extends RefCounted


static func advance(season: LeagueSeason, from_date: String, to_date: String) -> bool:
	if season == null or to_date == "" or from_date == to_date:
		return false
	season.market_date = to_date
	season.market_ticks += 1
	return true
