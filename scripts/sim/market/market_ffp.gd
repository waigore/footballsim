class_name MarketFFP
extends RefCounted


const PURPOSE := "ffp"
const EMBARGO := "embargo"
const COMPLIANT := "compliant"
const MONITORED := "monitored"
const BREACH := "breach"


static func window_years() -> int:
	return maxi(MarketRules.count("ffp", "window_years", 3), 1)


static func deduction_points() -> int:
	return maxi(MarketRules.count("ffp", "deduction_points", 6), 0)


static func allowed_loss(association: String) -> int:
	var table: Variant = MarketRules.section("ffp").get("allowed_loss", {})
	if table is Dictionary and (table as Dictionary).has(association):
		return int((table as Dictionary)[association])
	return MarketRules.count("ffp", "default_allowed_loss", 45000000)


static func association_of(club_id: String) -> String:
	if club_id == "":
		return ""
	var club := PLDatabase.row("SELECT id, competition_id, country FROM club WHERE id = ?;",
		[club_id])
	return MarketEligibility.association_of_club(club)


static func season_index(season: LeagueSeason = null) -> int:
	if season != null and season.save != null:
		return season.save.season_index()
	if LeagueSave.current != null:
		return LeagueSave.current.season_index()
	return 0


static func earnings(club_id: String, first_season: int, last_season: int) -> Dictionary:
	var revenue := 0
	var wages := 0
	var amortisation := 0
	var agent := 0
	for row in PLDatabase.rows(
			"SELECT kind, COALESCE(SUM(amount), 0) AS total FROM club_ledger "
			+ "WHERE club_id = ? AND season_index >= ? AND season_index <= ? GROUP BY kind;",
			[club_id, first_season, last_season]):
		match str(row["kind"]):
			MarketFinance.KIND_GATE, MarketFinance.KIND_COMMERCIAL, MarketFinance.KIND_PRIZE:
				revenue += int(row["total"])
			MarketFinance.KIND_WAGE:
				wages += absi(int(row["total"]))
			MarketFinance.KIND_AMORTISATION:
				amortisation += absi(int(row["total"]))
			MarketFinance.KIND_AGENT:
				agent += absi(int(row["total"]))
	var measure := revenue - wages - amortisation - agent
	return {
		"revenue": revenue, "wages": wages, "amortisation": amortisation,
		"agent": agent, "measure": measure,
		"first_season": first_season, "last_season": last_season,
	}


static func measure(club_id: String, season: int = -1) -> Dictionary:
	var last := season
	if last < 0:
		last = season_index()
	var first := maxi(last - window_years() + 1, 0)
	var out := earnings(club_id, first, last)
	out["club_id"] = club_id
	out["association"] = association_of(club_id)
	out["allowed"] = allowed_loss(str(out["association"]))
	out["headroom"] = int(out["allowed"]) + int(out["measure"])
	return out


static func compliant(club_id: String, season: int = -1) -> bool:
	return int(measure(club_id, season)["headroom"]) >= 0


static func monitored(season_index_value: int) -> bool:
	return season_index_value <= 0


static func headroom(club_id: String, season: int = -1) -> int:
	return int(measure(club_id, season)["headroom"])


static func status(club_id: String, season: int = -1) -> Dictionary:
	var index := season
	if index < 0:
		index = season_index()
	var counted := measure(club_id, index)
	var out := counted.duplicate()
	if monitored(index):
		out["state"] = MONITORED
		out["compliant"] = true
		return out
	out["state"] = COMPLIANT if int(counted["headroom"]) >= 0 else BREACH
	out["compliant"] = int(counted["headroom"]) >= 0
	return out


static func sanctioned(club_id: String, season: int = -1) -> bool:
	var index := season
	if index < 0:
		index = season_index()
	if monitored(index):
		return false
	return not compliant(club_id, index)


static func embargoed(club_id: String, season: int = -1) -> bool:
	return sanctioned(club_id, season)


static func book(club_id: String, competition_id: String, points: int, reason: String,
		date: String, season: int = -1) -> bool:
	if club_id == "" or competition_id == "" or points <= 0:
		return false
	var index := season
	if index < 0:
		index = season_index()
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO season_penalty (club_id, competition_id, season_index, points, "
		+ "reason, booked_on, applied) VALUES (?, ?, ?, ?, ?, ?, 0);",
		[club_id, competition_id, index, points, reason, date])


static func book_breach(club_id: String, competition_id: String, date: String,
		season: int = -1) -> bool:
	var index := season
	if index < 0:
		index = season_index()
	if not sanctioned(club_id, index):
		return false
	return book(club_id, competition_id, deduction_points(), BREACH, date, index + 1)


static func pending(club_id: String, competition_id: String, season: int = -1) -> Dictionary:
	var index := season
	if index < 0:
		index = season_index()
	return PLDatabase.row(
		"SELECT * FROM season_penalty WHERE club_id = ? AND competition_id = ? "
		+ "AND season_index = ? AND applied = 0;", [club_id, competition_id, index])


static func apply_at_table_start(competition_id: String, season: int = -1) -> int:
	if competition_id == "":
		return 0
	var index := season
	if index < 0:
		index = season_index()
	var applied := 0
	for row in PLDatabase.rows(
			"SELECT * FROM season_penalty WHERE competition_id = ? AND season_index = ? "
			+ "AND applied = 0 ORDER BY club_id;", [competition_id, index]):
		PLDatabase.execute(
			"UPDATE season_penalty SET applied = 1 WHERE club_id = ? AND competition_id = ? "
			+ "AND season_index = ?;", [str(row["club_id"]), competition_id, index])
		applied += 1
	return applied


static func apply_all(season: LeagueSeason) -> int:
	if season == null or season.save == null:
		return 0
	var total := 0
	for competition_id in season.save.actives:
		if not MarketEligibility.is_domestic(str(competition_id)):
			continue
		total += apply_at_table_start(str(competition_id), season.save.season_index())
	return total


static func check_at_commit(deal: Dictionary, mode: Dictionary = {}) -> Dictionary:
	if bool(mode.get("force", false)):
		return {"ok": true, "code": "ok", "note": "ffp_override"}
	var buyer := str(deal.get("to_club_id", ""))
	if buyer == "":
		return {"ok": true, "code": "ok"}
	if embargoed(buyer):
		return {"ok": false, "code": "ffp", "note": EMBARGO}
	var cost := MarketFinance.amortisation(int(deal.get("fee", 0)), int(deal.get("years", 1))) \
		+ int(deal.get("wage", 0)) * 52 + int(deal.get("agent_fee", 0))
	if headroom(buyer) - cost < 0:
		return {"ok": false, "code": "ffp", "note": "headroom"}
	return {"ok": true, "code": "ok"}


static func tick(season: LeagueSeason, date: String) -> Dictionary:
	if season == null or season.save == null:
		return {"embargoed": 0, "booked": 0}
	var index := season.save.season_index()
	if monitored(index):
		return {"embargoed": 0, "booked": 0, "monitored": true}
	var embargoed_count := 0
	var booked := 0
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for competition_id in season.save.actives:
		if not MarketEligibility.is_domestic(str(competition_id)):
			continue
		for row in PLDatabase.rows(
				"SELECT id FROM club WHERE competition_id = ? AND stub = 0 ORDER BY id;",
				[str(competition_id)]):
			var club_id := str(row["id"])
			if not sanctioned(club_id, index):
				continue
			embargoed_count += 1
			if book_breach(club_id, str(competition_id), date, index):
				booked += 1
	PLDatabase.transaction("COMMIT;")
	return {"embargoed": embargoed_count, "booked": booked}
