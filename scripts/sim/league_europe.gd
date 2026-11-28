class_name LeagueEurope
extends RefCounted


const PATHS := {"CH": "CHAMPIONS PATH", "LP": "LEAGUE PATH", "MP": "MAIN PATH"}
const KO := ["KOPO", "R16", "QF", "SF", "F"]
const SHORT := {
	"Q1": "Q1", "Q2": "Q2", "Q2CH": "Q2 CH", "Q2LP": "Q2 LP", "Q2MP": "Q2 MP",
	"Q3": "Q3", "Q3CH": "Q3 CH", "Q3LP": "Q3 LP", "Q3MP": "Q3 MP",
	"PO": "PO", "POCH": "PO CH", "POLP": "PO LP", "POMP": "PO MP",
	"LP": "LEAGUE PHASE", "KOPO": "KO PLAY-OFF", "R16": "R16", "QF": "QF",
	"SF": "SF", "F": "FINAL",
}


static func is_continental(competition_id: String) -> bool:
	return LeagueUefa.is_continental(competition_id)


static func active(save: LeagueSave) -> Array:
	return LeagueUefa.active_ids(save)


static func hub(save: LeagueSave) -> Dictionary:
	var cards: Array = []
	for competition_id in active(save):
		cards.append(card(save, str(competition_id)))
	return {"cards": cards, "tonight": LeagueEuropeTies.tonight(save), "on": not cards.is_empty()}


static func card(save: LeagueSave, competition_id: String) -> Dictionary:
	var comp := PLRepository.shared().competition(competition_id)
	return {
		"id": competition_id,
		"name": str(comp.get("name", competition_id)),
		"short": str(comp.get("short_name", competition_id)),
		"stage": stage_of(competition_id),
		"stage_label": stage_label(competition_id),
		"alive": alive(competition_id),
		"next": next_night(save, competition_id),
		"winner": _winner(competition_id),
		"winner_name": club_name(_winner(competition_id)),
		"runner_up_name": club_name(_runner_up(competition_id)),
		"score_line": score_line(_final(competition_id)),
	}


static func stage_of(competition_id: String) -> String:
	var last := ""
	for round_id in LeagueUefa.round_ids(competition_id):
		var id := str(round_id)
		if not LeagueUefa.has_stage(competition_id, id):
			break
		last = id
		if not LeagueUefa.stage_complete(competition_id, id):
			return id
	return last


static func stage_label(competition_id: String) -> String:
	var winner := _winner(competition_id)
	if winner != "":
		return "COMPLETE"
	var stage_id := stage_of(competition_id)
	if stage_id == "":
		return "NOT DRAWN"
	if stage_id == LeagueUefa.LEAGUE_STAGE:
		return "LEAGUE PHASE · MD %d" % _matchday(competition_id)
	return round_label(stage_id)


static func round_label(round_id: String) -> String:
	if KO.has(round_id):
		return str(SHORT.get(round_id, round_id))
	if round_id.begins_with("Q"):
		return "QUALIFYING " + _qualifying_label(round_id)
	if round_id.begins_with("PO"):
		return "PLAY-OFF" + _path_suffix("PO", round_id)
	return str(SHORT.get(round_id, round_id))


static func round_short(round_id: String) -> String:
	return str(SHORT.get(round_id, round_id))


static func _path_suffix(prefix: String, round_id: String) -> String:
	var code := round_id.substr(prefix.length())
	if PATHS.has(code):
		return " · " + str(PATHS[code])
	return ""


static func _qualifying_label(round_id: String) -> String:
	var number := round_id.substr(1, 1)
	var code := round_id.substr(2)
	var label := "Q" + number
	if PATHS.has(code):
		label += " · " + str(PATHS[code])
	return label


static func table(competition_id: String) -> Array:
	var rows: Array = LeagueUefaLeaguePhase.table(competition_id)
	var out: Array = []
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var place := int(row.get("position", i + 1))
		out.append({
			"position": place, "club_id": str(row.get("club_id", "")),
			"club_name": str(row.get("club_name", "")),
			"played": int(row.get("played", 0)), "won": int(row.get("won", 0)),
			"drawn": int(row.get("drawn", 0)), "lost": int(row.get("lost", 0)),
			"gf": int(row.get("gf", 0)), "ga": int(row.get("ga", 0)),
			"gd": int(row.get("gf", 0)) - int(row.get("ga", 0)),
			"points": int(row.get("points", 0)), "zone": zone_of(place),
		})
	return out


static func zone_of(position: int) -> String:
	if position <= 8:
		return "r16"
	if position <= 24:
		return "kopo"
	return "out"


static func zone_caption() -> String:
	return "1–8 ROUND OF 16  ·  9–16 KO PLAY-OFF SEEDED  ·  17–24 KO PLAY-OFF  ·  25–36 OUT"


static func honours(save: LeagueSave) -> Array:
	var out: Array = []
	for competition_id in active(save):
		var tie := _final(str(competition_id))
		if tie.is_empty() or str(tie.get("winner_club_id", "")) == "":
			continue
		var comp := PLRepository.shared().competition(str(competition_id))
		out.append({
			"id": str(competition_id), "name": str(comp.get("name", str(competition_id))),
			"short": str(comp.get("short_name", str(competition_id))),
			"winner_name": club_name(str(tie.get("winner_club_id", ""))),
			"runner_up_name": club_name(_runner_up(str(competition_id))),
			"score_line": score_line(tie),
		})
	return out


static func score_line(tie: Dictionary) -> String:
	if tie.is_empty() or str(tie.get("winner_club_id", "")) == "":
		return ""
	var home := str(tie.get("home_club_id", ""))
	var winner_home := str(tie.get("winner_club_id", "")) == home
	var home_goals := int(tie.get("home_goals", 0))
	var away_goals := int(tie.get("away_goals", 0))
	var won := away_goals
	var lost := home_goals
	if winner_home:
		won = home_goals
		lost = away_goals
	var line := "%d–%d" % [won, lost]
	if int(tie.get("extra_time", 0)) == 1:
		line += " AET"
	var pens_home := int(tie.get("pens_home", -1))
	if pens_home >= 0:
		var pens_away := int(tie.get("pens_away", 0))
		var pens_won := pens_away
		var pens_lost := pens_home
		if winner_home:
			pens_won = pens_home
			pens_lost = pens_away
		line += "  %d–%d PENS" % [pens_won, pens_lost]
	return line


static func alive(competition_id: String) -> int:
	if _winner(competition_id) != "":
		return 0
	var stage_id := stage_of(competition_id)
	if stage_id == "":
		return 0
	if stage_id == LeagueUefa.LEAGUE_STAGE:
		var table_row := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM league_table WHERE competition_id = ?;",
			[competition_id])
		return int(table_row.get("n", 0))
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM (SELECT home_club_id AS c FROM cup_tie "
		+ "WHERE competition_id = ? AND round_id = ? UNION SELECT away_club_id FROM cup_tie "
		+ "WHERE competition_id = ? AND round_id = ?);",
		[competition_id, stage_id, competition_id, stage_id])
	return int(row.get("n", 0))


static func next_night(save: LeagueSave, competition_id: String) -> String:
	var row := PLDatabase.row(
		"SELECT MIN(kickoff) AS d FROM league_fixture WHERE competition_id = ? "
		+ "AND status <> 'played';", [competition_id])
	if row.get("d", null) == null:
		return ""
	return str(row.get("d", ""))


static func club_name(club_id: String) -> String:
	if club_id == "":
		return ""
	return str(PLRepository.shared().club(club_id).get("name", club_id))


static func _matchday(competition_id: String) -> int:
	var pending := PLDatabase.row(
		"SELECT MIN(matchday) AS n FROM league_fixture WHERE competition_id = ? "
		+ "AND stage = ? AND status <> 'played';", [competition_id, LeagueUefa.LEAGUE_STAGE])
	if pending.get("n", null) != null:
		return int(pending.get("n", 1))
	var total := PLDatabase.row(
		"SELECT MAX(matchday) AS n FROM league_fixture WHERE competition_id = ? AND stage = ?;",
		[competition_id, LeagueUefa.LEAGUE_STAGE])
	return int(total.get("n", 0))


static func _final(competition_id: String) -> Dictionary:
	return PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = ? AND round_id = 'F' "
		+ "ORDER BY tie_index LIMIT 1;", [competition_id])


static func _winner(competition_id: String) -> String:
	return str(_final(competition_id).get("winner_club_id", ""))


static func _runner_up(competition_id: String) -> String:
	var tie := _final(competition_id)
	if tie.is_empty():
		return ""
	var home := str(tie.get("home_club_id", ""))
	if str(tie.get("winner_club_id", "")) == home:
		return str(tie.get("away_club_id", ""))
	return home
