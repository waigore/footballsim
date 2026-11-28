class_name MarketPurse
extends RefCounted


static func size(competition_id: String) -> int:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_table WHERE competition_id = ?;", [competition_id])
	return int(row.get("n", 0))


static func prize(competition_id: String, place: int, clubs: int) -> int:
	if place <= 0 or clubs <= 0:
		return 0
	var pool: Dictionary = MarketRules.section("prize").get("pool", {})
	var total := float(pool.get(competition_id,
		MarketRules.section("prize").get("default_pool", 4000000)))
	var rank := float(clampi(place, 1, clubs))
	return int(round(total * (0.5 + 0.5 * ((float(clubs) - rank + 1.0) / float(clubs)))))


static func opening(revenue: int, competition_id: String, clubs: int) -> int:
	var share := float(MarketRules.section("finance").get("opening_cash_share", 0.15))
	var mid := (clubs + 1) / 2
	return int(round(float(revenue) * share)) + prize(competition_id, mid, clubs)


static func reputation(revenue: int, position: int, clubs: int) -> int:
	var form := 0.0
	if clubs > 0 and position > 0:
		form = 12.0 * (1.0 - float(position - 1) / float(clubs))
	return clampi(int(round(6.0 + float(revenue) / 1500000.0 + form)), 1, 99)


static func marks(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(count):
		out.append("?")
	return out
