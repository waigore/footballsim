class_name MarketLoanObligations
extends RefCounted


static func due(season: LeagueSeason, date: String) -> Array:
	var out: Array = []
	if not MarketLoans.available() or date == "":
		return out
	for loan in MarketLoanRecords.all_active():
		var end := str(loan.get("end_date", ""))
		if end != "" and date >= end:
			out.append(str(loan.get("id", "")))
			continue
		if last_fixture_passed(str(loan.get("loanee_club_id", "")), date):
			out.append(str(loan.get("id", "")))
	return out


static func review(season: LeagueSeason, date: String) -> Dictionary:
	var returned := 0
	for loan_id in due(season, date):
		var out := MarketLoans.return_loan(str(loan_id), date)
		if str(out.get("state", "")) == MarketLoanRecords.RETURNED:
			returned += 1
	var triggered := fire(season, date)
	return {"returned": returned, "converted": triggered}


static func fire(season: LeagueSeason, date: String) -> int:
	var fired := 0
	for loan in MarketLoanRecords.all_active():
		var kind := str(loan.get("trigger_kind", ""))
		if kind == "":
			continue
		if not triggered(season, loan, date):
			continue
		var out := MarketLoans.buy(str(loan.get("id", "")), date)
		if str(out.get("state", "")) == MarketLoanRecords.CONVERTED:
			fired += 1
	return fired


static func trigger(loan_id: String, date: String) -> Dictionary:
	var loan := MarketLoanRecords.load(loan_id)
	if loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	return MarketLoans.buy(loan_id, date)


static func triggered(season: LeagueSeason, loan: Dictionary, date: String) -> bool:
	var kind := str(loan.get("trigger_kind", ""))
	if kind == "":
		return false
	var value := str(loan.get("trigger_value", ""))
	var player_id := str(loan.get("player_id", ""))
	var loanee := str(loan.get("loanee_club_id", ""))
	match kind:
		"appearances_n":
			var needed := maxi(int(value), 1)
			var apps := int(PLDatabase.row(
				"SELECT COALESCE(SUM(apps), 0) AS n FROM league_player_stat "
				+ "WHERE club_id = ? AND player_id = ?;", [loanee, player_id]).get("n", 0))
			return apps >= needed
		"club_promoted":
			return promoted(season, loanee)
		"league_position":
			return position_met(loanee, int(value))
		"season_end":
			return season_over(season, date)
	return false


static func last_fixture_passed(loanee_club_id: String, date: String) -> bool:
	if loanee_club_id == "":
		return false
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE (home_club_id = ? OR away_club_id = ?) "
		+ "AND status <> 'played' AND kickoff > ?;",
		[loanee_club_id, loanee_club_id, date])
	if int(row.get("n", 0)) > 0:
		return false
	var any := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE home_club_id = ? OR away_club_id = ?;",
		[loanee_club_id, loanee_club_id])
	return int(any.get("n", 0)) > 0


static func promoted(season: LeagueSeason, club_id: String) -> bool:
	if season == null or season.record == null or season.save == null:
		return false
	var payload := SeasonSettle.stored_payload(season)
	for key in ["pyramid", "promotion"]:
		var part: Dictionary = payload.get(key, {})
		if part.is_empty():
			continue
		for entry in part.get("to_top", []):
			if str(entry) == club_id:
				return true
		for entry in part.get("links", []):
			if (entry as Dictionary).get("to_top", []).has(club_id):
				return true
	return false


static func position_met(club_id: String, wanted: int) -> bool:
	if wanted <= 0:
		return false
	var competition_id := MarketLoanRegister.competition_of(club_id)
	if competition_id == "":
		return false
	var table: Array = LeagueLedger.table(competition_id)
	for i in range(table.size()):
		if str((table[i] as Dictionary).get("club_id", "")) == club_id:
			return i + 1 <= wanted
	return false


static func season_over(season: LeagueSeason, date: String) -> bool:
	if season == null or season.record == null:
		return false
	if season.record.fixtures.unplayed() == 0:
		return true
	if season.save == null:
		return false
	var end := str(season.save.rules.get("season_end", ""))
	return end != "" and date >= end
