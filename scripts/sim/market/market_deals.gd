class_name MarketDeals
extends RefCounted


static func propose(save: LeagueSave, offer: Dictionary) -> Dictionary:
	if save == null or not save.ensure_open() or not MarketDealRecords.available():
		return {"ok": false, "reason": "no_save"}
	var date := str(offer.get("date", save.current_date()))
	if date == "":
		return {"ok": false, "reason": "no_date"}
	var to_club := str(offer.get("to_club_id", ""))
	var window := MarketWindows.state(date, MarketWindows.country_of_club(
		PLDatabase.row("SELECT * FROM club WHERE id = ?;", [to_club])))
	var filled := offer.duplicate(true)
	filled["window_id"] = str(window.get("window_id", ""))
	var deal_id := MarketDealRecords.insert(filled, date, save.season_index())
	if deal_id == "":
		return {"ok": false, "reason": "insert_failed"}
	return {"ok": true, "deal_id": deal_id, "state": MarketDealRecords.PROPOSED,
		"date": date, "window_id": str(filled["window_id"])}


static func negotiate(save: LeagueSave, deal_id: String) -> Dictionary:
	var date: String = save.current_date() if save != null else ""
	return _step(deal_id, MarketDealRecords.NEGOTIATING, date)


static func agree(save: LeagueSave, deal_id: String) -> Dictionary:
	var date: String = save.current_date() if save != null else ""
	return _step(deal_id, MarketDealRecords.AGREED, date)


static func sign(save: LeagueSave, deal_id: String, options: Dictionary = {}) -> Dictionary:
	if save == null or not save.ensure_open():
		return {"ok": false, "reason": "no_save"}
	var deal := MarketDealRecords.one(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	var state := str(deal.get("state", ""))
	if MarketDealRecords.TERMINAL.has(state):
		return {"ok": false, "state": state, "reason": str(deal.get("reason", "")),
			"deal_id": deal_id}
	if state != MarketDealRecords.AGREED and state != MarketDealRecords.CLEARANCE_PENDING:
		return {"ok": false, "state": state, "reason": "not_agreed", "deal_id": deal_id}
	var date := str(options.get("date", save.current_date()))
	var rules := MarketDealRules.run(deal, options)
	var cross := _cross(deal)
	var clears_on := ""
	if cross and state == MarketDealRecords.AGREED \
			and (bool(rules.get("ok", false)) or str(rules.get("reason", "")) \
			== MarketDealRecords.NO_CLEARANCE):
		var seed_value := int(str(save.meta.get("seed", "0")))
		var days := MarketSeed.mix(seed_value, deal_id, 7) % 5 + 1
		clears_on = FixtureCalendar.add_days(date, days)
		_transition(deal_id, MarketDealRecords.CLEARANCE_PENDING, "", date, clears_on)
		MarketDealRecords.set_clearance(deal_id, clears_on)
	if not bool(rules.get("ok", false)):
		var failed := _fail(deal_id, str(rules.get("reason", "")), date)
		failed["clears_on"] = clears_on
		return failed
	var result := _commit(save, deal, date, str(rules.get(
		"registration_state", MarketDealRecords.REGISTERED)), options)
	result["clears_on"] = clears_on
	return result


static func force(save: LeagueSave, offer: Dictionary, options: Dictionary = {}) -> Dictionary:
	var opts := options.duplicate(true)
	opts["force"] = true
	var made := propose(save, offer)
	if not bool(made.get("ok", false)):
		return made
	var deal_id := str(made["deal_id"])
	negotiate(save, deal_id)
	agree(save, deal_id)
	return MarketDeals.sign(save, deal_id, opts)


static func block(save: LeagueSave, deal_id: String, options: Dictionary = {}) -> Dictionary:
	var fallback: String = save.current_date() if save != null else ""
	var date := str(options.get("date", fallback))
	var deal := MarketDealRecords.one(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	if not _transition(deal_id, MarketDealRecords.BLOCKED, MarketDealRecords.GOD_BLOCKED,
			date, str(deal.get("window_id", ""))):
		return {"ok": false, "state": str(deal.get("state", "")), "reason": "not_live"}
	return {"ok": true, "state": MarketDealRecords.BLOCKED,
		"reason": MarketDealRecords.GOD_BLOCKED, "deal_id": deal_id}


static func rewrite(save: LeagueSave, deal_id: String, changes: Dictionary,
		options: Dictionary = {}) -> Dictionary:
	var deal := MarketDealRecords.one(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	if MarketDealRecords.TERMINAL.has(str(deal.get("state", ""))):
		return {"ok": false, "state": str(deal.get("state", "")), "reason": "terminal"}
	var fallback: String = save.current_date() if save != null else ""
	var date := str(options.get("date", fallback))
	var filled := changes.duplicate(true)
	filled["date"] = date
	MarketDealRecords.update_terms(deal_id, filled)
	_transition(deal_id, MarketDealRecords.AGREED, "", date, "rewrite")
	return MarketDeals.sign(save, deal_id, options)


static func withdraw(save: LeagueSave, deal_id: String, options: Dictionary = {}) -> Dictionary:
	var fallback: String = save.current_date() if save != null else ""
	var date := str(options.get("date", fallback))
	if not _transition(deal_id, MarketDealRecords.WITHDRAWN, "withdrawn", date, ""):
		return {"ok": false, "reason": "not_live"}
	return {"ok": true, "state": MarketDealRecords.WITHDRAWN, "deal_id": deal_id}


static func one(deal_id: String) -> Dictionary:
	return MarketDealRecords.one(deal_id)


static func timeline(deal_id: String) -> Array:
	return MarketDealRecords.timeline(deal_id)


static func live_for(player_id: String, exclude_id: String = "") -> Dictionary:
	return MarketDealRecords.live_for(player_id, exclude_id)


static func _step(deal_id: String, state: String, date: String) -> Dictionary:
	if not _transition(deal_id, state, "", date, ""):
		var deal := MarketDealRecords.one(deal_id)
		return {"ok": false, "state": str(deal.get("state", "")), "reason": "not_live",
			"deal_id": deal_id}
	return {"ok": true, "state": state, "deal_id": deal_id}


static func _transition(deal_id: String, state: String, reason: String, date: String,
		detail: String = "") -> bool:
	var deal := MarketDealRecords.one(deal_id)
	if deal.is_empty():
		return false
	var from := str(deal.get("state", ""))
	if from == state:
		return true
	var live := MarketDealRecords.LIVE.has(from)
	var allowed := false
	if state in [MarketDealRecords.FAILED, MarketDealRecords.BLOCKED,
			MarketDealRecords.WITHDRAWN] and live:
		allowed = true
	elif from == MarketDealRecords.PROPOSED and state == MarketDealRecords.NEGOTIATING:
		allowed = true
	elif from in [MarketDealRecords.PROPOSED, MarketDealRecords.NEGOTIATING] \
			and state == MarketDealRecords.AGREED:
		allowed = true
	elif from == MarketDealRecords.AGREED and state == MarketDealRecords.CLEARANCE_PENDING:
		allowed = true
	elif from in [MarketDealRecords.AGREED, MarketDealRecords.CLEARANCE_PENDING] \
			and state == MarketDealRecords.SIGNED:
		allowed = true
	if not allowed:
		return false
	return MarketDealRecords.set_state(deal_id, state, reason, date, detail)


static func _commit(save: LeagueSave, deal: Dictionary, date: String, registration_state: String,
		options: Dictionary) -> Dictionary:
	var deal_id := str(deal.get("id", ""))
	var old_day := str(save.meta.get(MarketTick.DAY_KEY, ""))
	if not PLDatabase.transaction("BEGIN TRANSACTION;"):
		return _fail(deal_id, "commit_failed", date)
	if not _money(deal, date):
		return _rollback(save, old_day, deal_id, "commit_failed")
	if str(options.get("inject", "")) == "fault":
		return _rollback(save, old_day, deal_id, "injected")
	if not _contract(save, deal, date):
		return _rollback(save, old_day, deal_id, "commit_failed")
	if not _registration(deal, date, registration_state, save.season_index()):
		return _rollback(save, old_day, deal_id, "commit_failed")
	if not _move(deal):
		return _rollback(save, old_day, deal_id, "commit_failed")
	if not _history(save, deal, date):
		return _rollback(save, old_day, deal_id, "commit_failed")
	var sink: Variant = options.get("news", null)
	if sink is Callable:
		sink.call(deal)
	if not _stamp(save, date):
		return _rollback(save, old_day, deal_id, "commit_failed")
	if not _transition(deal_id, MarketDealRecords.SIGNED, "", date, ""):
		return _rollback(save, old_day, deal_id, "commit_failed")
	PLDatabase.transaction("COMMIT;")
	PLRepository.shared().invalidate()
	return {"ok": true, "state": MarketDealRecords.SIGNED, "deal_id": deal_id,
		"registration": registration_state, "cash": MarketFinance.cash(str(deal["to_club_id"])),
		"headroom": MarketFinance.ffp_headroom(str(deal["to_club_id"]))}


static func _money(deal: Dictionary, date: String) -> bool:
	var fee := int(deal.get("fee", 0))
	if fee <= 0:
		return true
	var buyer := str(deal.get("to_club_id", ""))
	var seller := str(deal.get("from_club_id", ""))
	var player := str(deal.get("player_id", ""))
	var deal_id := str(deal.get("id", ""))
	if not MarketFinance.post(buyer, date, MarketFinance.KIND_FEE, -fee, seller, player, deal_id):
		return false
	if not MarketFinance.post(seller, date, MarketFinance.KIND_FEE, fee, buyer, player, deal_id):
		return false
	return true


static func _contract(save: LeagueSave, deal: Dictionary, date: String) -> bool:
	var player := str(deal.get("player_id", ""))
	var from_club := str(deal.get("from_club_id", ""))
	var to_club := str(deal.get("to_club_id", ""))
	var years := maxi(int(deal.get("years", 1)), 1)
	var end := FixtureCalendar.add_days(FixtureCalendar.add_years(date, years), -1)
	if from_club != "" and not MarketDealRecords.close_contract(player, from_club):
		return false
	return MarketDealRecords.open_contract(player, to_club, date, end,
		int(deal.get("wage", 0)), str(deal.get("id", "")), save.season_index())


static func _registration(deal: Dictionary, date: String, state: String,
		season_index: int) -> bool:
	var player := str(deal.get("player_id", ""))
	var from_club := str(deal.get("from_club_id", ""))
	var to_club := str(deal.get("to_club_id", ""))
	if from_club != "" and not MarketDealRecords.close_registration(player, from_club, date):
		return false
	var competition_id := str(PLDatabase.row(
		"SELECT competition_id FROM club WHERE id = ?;", [to_club]).get("competition_id", ""))
	var reason: String = "" if state == MarketDealRecords.REGISTERED \
		else MarketDealRecords.LIST_REFUSED
	return MarketDealRecords.open_registration(player, competition_id, to_club,
		str(deal.get("kind", MarketDealRecords.KIND_PERMANENT)), state, reason, date,
		str(deal.get("id", "")), season_index)


static func _move(deal: Dictionary) -> bool:
	var player := str(deal.get("player_id", ""))
	var to_club := str(deal.get("to_club_id", ""))
	var number := MarketDealRecords.move_player(player, to_club)
	if number <= 0:
		return false
	MarketContracts.rehome(player, to_club)
	return true


static func _history(save: LeagueSave, deal: Dictionary, date: String) -> bool:
	var to_club := str(deal.get("to_club_id", ""))
	var competition_id := str(PLDatabase.row(
		"SELECT competition_id FROM club WHERE id = ?;", [to_club]).get("competition_id", ""))
	return MarketDealRecords.history(str(deal.get("player_id", "")), to_club, competition_id,
		date, save.season_index())


static func _stamp(save: LeagueSave, date: String) -> bool:
	return save.put_meta(MarketTick.DAY_KEY, date)


static func _rollback(save: LeagueSave, old_day: String, deal_id: String,
		reason: String) -> Dictionary:
	PLDatabase.transaction("ROLLBACK;")
	save.put_meta(MarketTick.DAY_KEY, old_day)
	PLRepository.shared().invalidate()
	var deal := MarketDealRecords.one(deal_id)
	return {"ok": false, "state": str(deal.get("state", "")), "reason": reason,
		"rolled_back": true, "deal_id": deal_id}


static func _fail(deal_id: String, reason: String, date: String) -> Dictionary:
	_transition(deal_id, MarketDealRecords.FAILED, reason, date, "")
	return {"ok": false, "state": MarketDealRecords.FAILED, "reason": reason,
		"deal_id": deal_id}


static func _cross(deal: Dictionary) -> bool:
	var from_club := str(deal.get("from_club_id", ""))
	var to_club := str(deal.get("to_club_id", ""))
	if from_club == "" or to_club == "":
		return false
	var from_country := MarketWindows.country_of_club(
		PLDatabase.row("SELECT * FROM club WHERE id = ?;", [from_club]))
	var to_country := MarketWindows.country_of_club(
		PLDatabase.row("SELECT * FROM club WHERE id = ?;", [to_club]))
	return from_country != "" and to_country != "" and from_country != to_country
