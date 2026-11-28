class_name LeagueUefa
extends RefCounted


const IDS := ["UCL", "UEL", "UECL"]
const QUALIFYING := ["Q1", "Q2", "Q2CH", "Q2LP", "Q3", "Q3CH", "Q3LP", "PO", "POCH", "POLP"]
const KNOCKOUT := ["KOPO", "R16", "QF", "SF", "F"]
const LEAGUE_STAGE := "LP"


static func is_continental(competition_id: String) -> bool:
	return kind(competition_id) == "continental"


static func kind(competition_id: String) -> String:
	return str(rules(competition_id).get("kind", "league"))


static func rules(competition_id: String) -> Dictionary:
	var row := PLRepository.shared().competition(competition_id)
	var data: Variant = row.get("rules", {})
	return data if data is Dictionary else {}


static func active_ids(save: LeagueSave) -> Array:
	if save == null or str(save.meta.get("uefa", "off")) != "on":
		return []
	var out: Array = []
	for cid in IDS:
		if PLRepository.shared().competition_kind(cid) == "continental":
			out.append(cid)
	return out


static func rounds(competition_id: String) -> Array:
	var list: Variant = rules(competition_id).get("rounds", [])
	return list if list is Array else []


static func round_rule(competition_id: String, round_id: String) -> Dictionary:
	for row in rounds(competition_id):
		if str((row as Dictionary).get("id", "")) == round_id:
			return row
	return {}


static func round_ids(competition_id: String) -> Array:
	var out: Array = []
	for row in rounds(competition_id):
		out.append(str((row as Dictionary).get("id", "")))
	return out


static func first_round(competition_id: String) -> String:
	var ids := round_ids(competition_id)
	return str(ids[0]) if not ids.is_empty() else ""


static func after(competition_id: String, round_id: String) -> String:
	var ids := round_ids(competition_id)
	var at := ids.find(round_id)
	if at < 0 or at + 1 >= ids.size():
		return ""
	return str(ids[at + 1])


static func league_phase(competition_id: String) -> Dictionary:
	var data: Variant = rules(competition_id).get("league_phase", {})
	return data if data is Dictionary else {}


static func league_clubs(competition_id: String) -> int:
	return int(league_phase(competition_id).get("clubs", 36))


static func league_matches(competition_id: String) -> int:
	return int(league_phase(competition_id).get("matches", 8))


static func pots(competition_id: String) -> int:
	return int(league_phase(competition_id).get("pots", 4))


static func drops(competition_id: String, round_id: String) -> Array:
	var table: Variant = rules(competition_id).get("drops", {})
	if not (table is Dictionary):
		return []
	var list: Variant = (table as Dictionary).get(round_id, [])
	return list if list is Array else []


static func tier(competition_id: String) -> String:
	var table: Variant = rules(competition_id).get("tier", "")
	return str(table) if table is String else ""


static func name_of(competition_id: String) -> String:
	return str(PLRepository.shared().competition_name(competition_id))


static func club_name(club_id: String) -> String:
	return str(PLRepository.shared().club(club_id).get("name", club_id))


static func entrants(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club' AND role = ? ORDER BY member_id;",
			[competition_id, round_id]):
		out.append(str(row["member_id"]))
	return out


static func has_stage(competition_id: String, round_id: String) -> bool:
	var row := PLDatabase.row(
		"SELECT 1 AS n FROM cup_round WHERE competition_id = ? AND round_id = ?;",
		[competition_id, round_id])
	if not row.is_empty():
		return true
	if round_id == LEAGUE_STAGE:
		var phase := PLDatabase.row(
			"SELECT 1 AS n FROM league_fixture WHERE competition_id = ? AND stage = ? LIMIT 1;",
			[competition_id, LEAGUE_STAGE])
		return not phase.is_empty()
	return false


static func stage_complete(competition_id: String, round_id: String) -> bool:
	if round_id == LEAGUE_STAGE:
		var pending := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM league_fixture WHERE competition_id = ? "
			+ "AND stage = ? AND status <> 'played';", [competition_id, LEAGUE_STAGE])
		var total := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM league_fixture WHERE competition_id = ? AND stage = ?;",
			[competition_id, LEAGUE_STAGE])
		return int(total.get("n", 0)) > 0 and int(pending.get("n", 0)) == 0
	var total_ties := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ?;",
		[competition_id, round_id])
	var done_ties := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ? "
		+ "AND winner_club_id <> '';", [competition_id, round_id])
	return int(total_ties.get("n", 0)) > 0 \
		and int(done_ties.get("n", 0)) == int(total_ties.get("n", 0))


static func club_rank(club_id: String) -> float:
	var team := TeamData.get_team(club_id)
	var picks := StrongestXI.pick(team)
	var total := 0.0
	for player in picks:
		total += float((player as Dictionary).get("ovr", 0))
	return total / float(maxi(picks.size(), 1))


static func association_of(club_id: String) -> String:
	var club := PLRepository.shared().club(club_id)
	return str(club.get("country", ""))
