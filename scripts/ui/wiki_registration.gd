class_name WikiRegistration
extends RefCounted


const INELIGIBLE_TAG := "INELIGIBLE"
const PROVISIONAL_TAG := "PROVISIONAL"


static func competition_of(club_id: String) -> String:
	if club_id == "":
		return ""
	return str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[club_id]).get("competition_id", ""))


static func summary(club_id: String) -> Dictionary:
	if club_id == "" or not MarketRegistration.available():
		return {}
	var competition_id := competition_of(club_id)
	if competition_id == "" or MarketEligibility.is_uefa(competition_id):
		return {}
	if not MarketEligibility.is_domestic(competition_id) \
			and not MarketEligibility.is_italy(competition_id):
		return {}
	var counts := MarketRegistration.tally(club_id, competition_id)
	if int(counts.get("slots", 0)) == 0 and int(counts.get("u21", 0)) == 0:
		return {}
	var association := str(counts.get("association_code", ""))
	var target := MarketEligibility.homegrown_min()
	if MarketEligibility.is_italy(competition_id):
		target = MarketEligibility.italy_association_min()
	var cap := MarketEligibility.non_eu_cap(association)
	return {
		"competition_id": competition_id,
		"slots": int(counts.get("slots", 0)),
		"slots_max": MarketEligibility.slots(),
		"homegrown": int(counts.get("homegrown", 0)),
		"homegrown_min": target,
		"association": int(counts.get("association", 0)),
		"association_min": MarketEligibility.association_min(),
		"non_eu": int(counts.get("non_eu", 0)),
		"non_eu_cap": cap,
		"u21": int(counts.get("u21", 0)),
		"state": MarketRegistration.state_of(club_id, competition_id),
	}


static func flags(club_id: String) -> Dictionary:
	var out := {}
	if club_id == "" or not MarketRegistration.available():
		return out
	var competition_id := competition_of(club_id)
	if competition_id == "":
		return out
	for row in MarketRegistration.rows_of(club_id, competition_id):
		var tag := flag_of(row)
		if tag == "":
			continue
		out[str(row.get("player_id", ""))] = tag
	return out


static func flag_of(row: Dictionary) -> String:
	if str(row.get("state", "")) == MarketRegistration.INELIGIBLE:
		return INELIGIBLE_TAG
	if str(row.get("state", "")) == MarketRegistration.PROVISIONAL:
		return PROVISIONAL_TAG
	return ""
