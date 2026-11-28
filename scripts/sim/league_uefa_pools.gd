class_name LeagueUefaPools
extends RefCounted


const AUDIT_KEY := "uefa_pools"
const REAL := ["ENG", "ESP", "GER", "ITA"]
const ROUND_ORDER := ["LP", "POMP", "POLP", "POCH", "PO",
	"Q3MP", "Q3LP", "Q3CH", "Q2MP", "Q2LP", "Q2CH", "Q1"]


static func regenerate(season: LeagueSeason) -> Dictionary:
	if season == null or season.save == null:
		return {"ok": false, "reason": "no_season"}
	var save := season.save
	if LeagueUefa.active_ids(save).is_empty():
		return {"ok": false, "reason": "uefa_off"}
	var slots := _slots_by_association()
	if slots.is_empty():
		return {"ok": false, "reason": "no_slots"}
	var played := save.season_index()
	var audit := {
		"ok": true, "season_index": played, "season_label": save.season_label(),
		"regenerated": [], "carried": [], "fallback": [],
	}
	var rows: Array = []
	var keys := slots.keys()
	keys.sort()
	for key in keys:
		var association := str(key)
		var ladder: Array = slots[association]
		if not REAL.has(association) or not _league_active(save, association):
			if REAL.has(association):
				(audit["carried"] as Array).append(association)
			for slot in ladder:
				rows.append(_row(slot, str((slot as Dictionary)["club"])))
			continue
		var picks := _picks(season, association, ladder.size(), audit)
		for i in range(ladder.size()):
			var kept := str((ladder[i] as Dictionary)["club"])
			var pick := str(picks[i]) if i < picks.size() else ""
			rows.append(_row(ladder[i], pick if pick != "" else kept))
		(audit["regenerated"] as Array).append(association)
	_write(rows)
	save.put_meta(AUDIT_KEY, JSON.stringify(audit))
	return audit


static func audit_of(save: LeagueSave) -> Dictionary:
	if save == null:
		return {}
	var raw := str(save.meta.get(AUDIT_KEY, ""))
	if raw == "":
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func note(save: LeagueSave) -> String:
	var audit := audit_of(save)
	if audit.is_empty():
		return ""
	var parts: Array = []
	for key in audit.get("carried", []):
		parts.append("%s CARRIED OVER" % str(key))
	for row in audit.get("fallback", []):
		var entry: Dictionary = row
		var association := str(entry.get("association", ""))
		if str(entry.get("reason", "")) == "cup_off":
			parts.append("%s CUP SLOT TO THE LEAGUE" % association)
		else:
			parts.append("%s CUP SLOT PASSED DOWN" % association)
	if parts.is_empty():
		return ""
	return "ENTRANTS: " + " · ".join(PackedStringArray(parts))


static func _slots_by_association() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows(
			"SELECT competition_id, role, member_id FROM competition_member "
			+ "WHERE competition_id IN ('UCL', 'UEL', 'UECL') AND member_kind = 'club';"):
		var club_id := str(row["member_id"])
		var association := LeagueUefa.association_of(club_id)
		if association == "":
			continue
		if not out.has(association):
			out[association] = []
		(out[association] as Array).append({
			"competition_id": str(row["competition_id"]),
			"role": str(row["role"]),
			"club": club_id,
		})
	for key in out.keys():
		(out[key] as Array).sort_custom(_slot_before)
	return out


static func _slot_before(a: Dictionary, b: Dictionary) -> bool:
	var left := LeagueUefa.IDS.find(str(a["competition_id"]))
	var right := LeagueUefa.IDS.find(str(b["competition_id"]))
	if left != right:
		return left < right
	var left_round := _round_rank(str(a["role"]))
	var right_round := _round_rank(str(b["role"]))
	if left_round != right_round:
		return left_round < right_round
	return str(a["club"]) < str(b["club"])


static func _round_rank(role: String) -> int:
	var at := ROUND_ORDER.find(role)
	return at if at >= 0 else ROUND_ORDER.size()


static func _row(slot: Dictionary, club_id: String) -> Dictionary:
	return {"competition_id": str(slot["competition_id"]), "role": str(slot["role"]),
		"club": club_id}


static func _league_active(save: LeagueSave, association: String) -> bool:
	var league := _top_league(association)
	return league != "" and save.actives.has(league)


static func _top_league(association: String) -> String:
	var chain: Variant = LeagueTiers.TIERS.get(MarketWindows.name(association), [])
	if not (chain is Array) or (chain as Array).is_empty():
		return ""
	return str((chain as Array)[0])


static func _positions(season_index: int, competition_id: String) -> Array:
	var out: Array = []
	if competition_id == "":
		return out
	for row in PLDatabase.rows(
			"SELECT club_id FROM season_archive WHERE season_index = ? "
			+ "AND competition_id = ? ORDER BY position ASC;", [season_index, competition_id]):
		out.append(str(row["club_id"]))
	return out


static func _cup_winner(save: LeagueSave, association: String) -> String:
	if str(save.meta.get("cups", "off")) != "on":
		return ""
	var name := MarketWindows.name(association)
	var off := str(save.meta.get("cups_off", ""))
	if off != "" and (",%s," % off).find(",%s," % name) >= 0:
		return ""
	var cup := _cup_of(name)
	if cup == "":
		return ""
	var rounds := LeagueCup.rounds(cup)
	if rounds.is_empty():
		return ""
	var last := str((rounds[rounds.size() - 1] as Dictionary).get("id", ""))
	var row := PLDatabase.row(
		"SELECT winner_club_id FROM cup_tie WHERE competition_id = ? AND round_id = ? "
		+ "AND winner_club_id <> '' ORDER BY season_index DESC, tie_index DESC LIMIT 1;",
		[cup, last])
	return str(row.get("winner_club_id", ""))


static func _cup_of(name: String) -> String:
	for row in PLRepository.shared().cups():
		var rules: Dictionary = row.get("rules", {})
		if str(row.get("country", "")) != name:
			continue
		if str(rules.get("kind", "")) == "cup":
			return str(row.get("id", ""))
	return ""


static func _picks(season: LeagueSeason, association: String, count: int,
		audit: Dictionary) -> Array:
	var save := season.save
	var positions := _positions(save.season_index(), _top_league(association))
	var picks: Array = []
	var used := {}
	var league_slots := maxi(count - 1, 0)
	for club_id in positions:
		if picks.size() >= league_slots:
			break
		picks.append(str(club_id))
		used[str(club_id)] = true
	var winner := _cup_winner(save, association)
	if winner != "" and not used.has(winner):
		used[winner] = true
		picks.append(winner)
	else:
		var next := ""
		for club_id in positions:
			if not used.has(str(club_id)):
				next = str(club_id)
				break
		picks.append(next)
		(audit["fallback"] as Array).append({
			"association": association,
			"reason": "cup_winner_higher" if winner != "" else "cup_off",
			"club": next,
		})
	while picks.size() < count:
		picks.append("")
	return picks


static func _write(rows: Array) -> void:
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute(
		"DELETE FROM competition_member WHERE competition_id IN ('UCL', 'UEL', 'UECL') "
		+ "AND member_kind = 'club';")
	for row in rows:
		PLDatabase.execute(
			"INSERT OR REPLACE INTO competition_member (competition_id, member_kind, "
			+ "member_id, role) VALUES (?, 'club', ?, ?);",
			[str(row["competition_id"]), str(row["club"]), str(row["role"])])
	PLDatabase.transaction("COMMIT;")
