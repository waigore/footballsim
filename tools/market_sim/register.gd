extends RefCounted

## The register verb: lists and permits on a fixed clock with the window open.
## No deal engine, no AI and no UI is loaded; the registration model is the
## whole world. It prints the club's own list, then one verdict per rule.
##
##   godot --headless --path . --script res://tools/market_sim.gd -- register \
##     --competition ucl --clubs 20 --inject homegrown_min
##
## --inject  none | list_full | homegrown_min | non_eu_cap | u21 | permit


static func run(options: Dictionary) -> Dictionary:
	var competition_id := str(options.get("competition", "PL")).to_upper()
	var seed_value := int(options.get("seed", "8151"))
	var uefa := MarketEligibility.is_uefa(competition_id)
	var competitions: Array = ["PL"]
	if competition_id != "PL":
		competitions.append(competition_id)
	var season := LeagueSeason.create("Register Sandbox", "generated", "fixture_days", seed_value,
		competitions, uefa, [], uefa)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var club_id := _club_for(competition_id)
	if club_id == "":
		season.close()
		return {"ok": false, "reason": "no club in %s" % competition_id}
	var date := str(options.get("date", "2026-08-20"))
	var counts := MarketRegistration.tally(club_id, competition_id)
	var state := MarketRegistration.state_of(club_id, competition_id)
	print("register: %s in %s opens %s with %s" % [club_id, competition_id, state,
		JSON.stringify(counts)])
	var matrix := matrix(club_id, competition_id)
	for key in matrix:
		print("  %-14s %s" % [key, JSON.stringify(matrix[key])])
	var inject := str(options.get("inject", "none"))
	var outcome := _case(club_id, competition_id, date, inject)
	print("register: inject '%s' -> %s" % [inject, JSON.stringify(outcome)])
	var ok := matrix_ok(matrix) and bool(outcome.get("ok", false))
	season.close()
	return {"ok": ok, "competition": competition_id, "club": club_id, "state": state,
		"counts": counts, "matrix": matrix, "injected": inject, "outcome": outcome}


static func matrix(club_id: String, competition_id: String) -> Dictionary:
	var counts := MarketRegistration.tally(club_id, competition_id)
	var association := str(counts.get("association_code", ""))
	var outs: Dictionary = {}
	outs["slots"] = {"ok": int(counts.get("slots", 0)) <= MarketEligibility.slots(),
		"slots": int(counts.get("slots", 0)), "max": MarketEligibility.slots()}
	outs["u21"] = _u21_verdict(club_id, competition_id)
	outs["homegrown"] = _reason_verdict(competition_id, association, counts,
		_incoming("Brazil", 28, "", club_id))
	outs["non_eu"] = _reason_verdict(competition_id, association, counts,
		_incoming("Brazil", 28, "", club_id))
	outs["permit"] = _permit_verdict(club_id, competition_id)
	outs["freeze"] = _freeze_verdict(club_id, competition_id)
	return outs


static func matrix_ok(outs: Dictionary) -> bool:
	if not bool((outs.get("slots", {}) as Dictionary).get("ok", false)):
		return false
	if not bool((outs.get("u21", {}) as Dictionary).get("ok", false)):
		return false
	if not bool((outs.get("permit", {}) as Dictionary).get("ok", false)):
		return false
	if not bool((outs.get("freeze", {}) as Dictionary).get("ok", false)):
		return false
	return true


static func _case(club_id: String, competition_id: String, date: String,
		inject: String) -> Dictionary:
	match inject:
		"permit":
			return _permit_case(club_id, competition_id, date)
		"list_full":
			return _slot_case(club_id, competition_id)
		"homegrown_min":
			return _homegrown_case(club_id, competition_id)
		"non_eu_cap":
			return _non_eu_case(club_id, competition_id)
		"u21":
			return _u21_verdict(club_id, competition_id)
	return _register_case(club_id, competition_id, date)


static func _register_case(club_id: String, competition_id: String, date: String) -> Dictionary:
	var player := _outsider(club_id)
	if player.is_empty():
		return {"ok": false, "reason": "no signing to attempt"}
	_move_to_club(str(player["id"]), club_id)
	return MarketRegistration.register(str(player["id"]), club_id, competition_id,
		"permanent", "", _season_index(), date)


static func _permit_case(club_id: String, competition_id: String, date: String) -> Dictionary:
	var player := _weak_outsider(club_id)
	if player.is_empty():
		return {"ok": false, "reason": "no weak outsider"}
	_move_to_club(str(player["id"]), club_id)
	var out := MarketRegistration.register(str(player["id"]), club_id, competition_id,
		"permanent", "", _season_index(), date)
	var row := MarketRegistration.row(str(player["id"]), competition_id)
	return {"ok": str(row.get("state", "")) == MarketRegistration.INELIGIBLE,
		"state": str(row.get("state", "")), "code": str(out.get("code", ""))}


static func _slot_case(club_id: String, competition_id: String) -> Dictionary:
	var counts := MarketRegistration.tally(club_id, competition_id)
	counts["slots"] = MarketEligibility.slots()
	var reasons := MarketEligibility.admits(competition_id,
		str(counts.get("association_code", "")), counts,
		_incoming("France", 28, "", club_id))
	return {"ok": reasons.has("list_full"), "reasons": reasons}


static func _homegrown_case(club_id: String, competition_id: String) -> Dictionary:
	var counts := _full_non_homegrown(club_id, competition_id)
	var reasons := MarketEligibility.bands(competition_id,
		str(counts.get("association_code", "")), counts)
	return {"ok": reasons.has("homegrown_min"), "reasons": reasons}


static func _non_eu_case(club_id: String, competition_id: String) -> Dictionary:
	var counts := MarketRegistration.tally(club_id, competition_id)
	var association := str(counts.get("association_code", ""))
	var cap := MarketEligibility.non_eu_cap(association)
	if cap < 0:
		return _capped_non_eu_case()
	counts["slots"] = mini(int(counts.get("slots", 0)), MarketEligibility.slots())
	counts["non_eu"] = cap + 1
	var reasons := MarketEligibility.bands(competition_id, association, counts)
	return {"ok": reasons.has("non_eu_cap"), "reasons": reasons, "cap": cap}


static func _capped_non_eu_case() -> Dictionary:
	var counts := {"slots": 20, "homegrown": 12, "association": 12, "non_eu": 0,
		"club_trained": 8}
	counts["non_eu"] = MarketEligibility.non_eu_cap("ESP") + 1
	var reasons := MarketEligibility.bands("LL", "ESP", counts)
	return {"ok": reasons.has("non_eu_cap"), "reasons": reasons,
		"cap": MarketEligibility.non_eu_cap("ESP"), "note": "England has no non-EU cap"}


static func _u21_verdict(club_id: String, competition_id: String) -> Dictionary:
	var counts := MarketRegistration.tally(club_id, competition_id)
	var before := int(counts.get("slots", 0))
	var after := MarketEligibility.admits(competition_id,
		str(counts.get("association_code", "")), counts, _incoming("France", 19, "", club_id))
	var expected_ok := not after.has("list_full")
	return {"ok": expected_ok and before <= MarketEligibility.slots(),
		"reasons": after, "slots": before}


static func _permit_verdict(club_id: String, competition_id: String) -> Dictionary:
	var club := PLDatabase.row("SELECT id, competition_id, country FROM club WHERE id = ?;",
		[club_id])
	var association := MarketEligibility.association_of_club(club)
	var gate := MarketRegistration.permit(_weak_outsider(club_id).get("id", ""), club_id)
	var threshold := MarketEligibility.permit_threshold(association)
	if threshold <= 0:
		return {"ok": true, "reason": "no permit regime in %s" % association}
	return {"ok": not bool(gate.get("ok", false)),
		"state": str(gate.get("state", "")), "threshold": threshold}


static func _freeze_verdict(club_id: String, competition_id: String) -> Dictionary:
	var outsider := _outsider(club_id)
	if outsider.is_empty():
		return {"ok": false, "reason": "no outsider"}
	var closed := "2026-10-20"
	var out := MarketRegistration.register(str(outsider["id"]), club_id, competition_id,
		"permanent", "", _season_index(), closed)
	return {"ok": str(out.get("code", "")) == MarketDealRules.WINDOW_CLOSED,
		"code": str(out.get("code", "")), "date": closed}


static func _reason_verdict(competition_id: String, association: String, counts: Dictionary,
		incoming: Dictionary) -> Dictionary:
	var reasons := MarketEligibility.admits(competition_id, association, counts, incoming)
	return {"ok": true, "reasons": reasons}


static func _full_non_homegrown(club_id: String, competition_id: String) -> Dictionary:
	var counts := MarketRegistration.tally(club_id, competition_id)
	var size := MarketEligibility.slots()
	counts["slots"] = size
	counts["homegrown"] = 0
	counts["club_trained"] = 0
	counts["association"] = 0
	return counts


static func _incoming(nationality: String, age: int, homegrown: String,
		club_id: String) -> Dictionary:
	return {"nationality": nationality, "age": age, "homegrown_club_id": homegrown,
		"club_id": club_id}


static func _club_for(competition_id: String) -> String:
	if MarketEligibility.is_uefa(competition_id):
		return str(PLDatabase.row(
			"SELECT m.member_id FROM competition_member m JOIN club c ON c.id = m.member_id "
			+ "WHERE m.competition_id = ? AND c.stub = 0 ORDER BY m.member_id LIMIT 1;",
			[competition_id]).get("member_id", ""))
	return str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = ? AND stub = 0 ORDER BY id LIMIT 1;",
		[competition_id]).get("id", ""))


static func _outsider(club_id: String) -> Dictionary:
	return PLDatabase.row(
		"SELECT id, ovr FROM player WHERE club_id <> ? AND club_id <> '' "
		+ "ORDER BY ovr DESC LIMIT 1;", [club_id])


static func _weak_outsider(club_id: String) -> Dictionary:
	return PLDatabase.row(
		"SELECT id, ovr, nationality FROM player WHERE club_id <> ? AND club_id <> '' "
		+ "AND nationality NOT IN ('England', 'Spain', 'Germany', 'Italy') "
		+ "ORDER BY ovr LIMIT 1;", [club_id])


static func _move_to_club(player_id: String, club_id: String) -> void:
	PLDatabase.execute(
		"UPDATE player SET club_id = ?, homegrown_club_id = '' WHERE id = ?;",
		[club_id, player_id])


static func _season_index() -> int:
	return LeagueSave.current.season_index() if LeagueSave.current != null else 0
