class_name MarketCompleteness
extends RefCounted


const MINIMUM := 11


static func ensure_day(season: LeagueSeason, day: String) -> int:
	if season == null or season.save == null or day == "" or not MarketDeals.available():
		return 0
	var clubs := clubs_on(day)
	var signed := 0
	for club_id in clubs:
		signed += ensure_club(str(club_id), day)
	return signed


static func clubs_on(day: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT home_club_id AS id FROM league_fixture WHERE kickoff = ? "
			+ "AND status = 'pending' UNION SELECT away_club_id FROM league_fixture "
			+ "WHERE kickoff = ? AND status = 'pending' ORDER BY id;", [day, day]):
		var club_id := str(row.get("id", ""))
		if club_id != "" and not out.has(club_id):
			out.append(club_id)
	return out


static func ensure_club(club_id: String, day: String) -> int:
	if club_id == "":
		return 0
	var need := shortfall(club_id)
	var want_players := int(need.get("players", 0))
	var want_keepers := int(need.get("keepers", 0))
	if want_players <= 0 and want_keepers <= 0:
		return 0
	var signed := 0
	for player in MarketContracts.free_agents(300):
		if want_players <= 0 and want_keepers <= 0:
			break
		var keeper := str(player.get("pos", "")) == "GK"
		if keeper and want_keepers > 0:
			if _sign(club_id, player, day):
				want_keepers -= 1
				signed += 1
			continue
		if not keeper and want_players > 0:
			if _sign(club_id, player, day):
				want_players -= 1
				signed += 1
	return signed


static func shortfall(club_id: String) -> Dictionary:
	var available := 0
	var keepers := 0
	var out_ids := SeasonAvailability.unavailable(club_id)
	for row in PLDatabase.rows(
			"SELECT p.id, p.pos FROM player p WHERE p.club_id = ?;", [club_id]):
		var player_id := str(row.get("id", ""))
		if out_ids.has(player_id):
			continue
		available += 1
		if str(row.get("pos", "")) == "GK":
			keepers += 1
	return {
		"players": maxi(MINIMUM - available, 0),
		"keepers": maxi(1 - keepers, 0),
	}


static func _sign(club_id: String, player: Dictionary, day: String) -> bool:
	var player_id := str(player.get("id", ""))
	if player_id == "":
		return false
	var worth := MarketValuation.value(player, {}, day)
	var terms := {
		"fee": 0, "wage": MarketValuation.weekly_wage(worth, 0), "years": 1,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0,
	}
	var opened := MarketDeals.propose(null, "", club_id, player_id, terms, day)
	var deal_id := str(opened.get("deal", ""))
	if deal_id == "":
		return false
	var agreed := MarketDeals.agree(deal_id, day, {})
	if str(agreed.get("state", "")) == MarketDealRecords.CLEARANCE_PENDING:
		return false
	if not bool(agreed.get("ok", false)):
		return false
	var done := MarketDeals.seal(deal_id, day, {})
	MarketNeeds.forget(club_id)
	return str(done.get("state", "")) == MarketDealRecords.SIGNED
