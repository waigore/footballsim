class_name SeasonAvailability
extends RefCounted


const GRADE_DAYS := {
	"knock": [3, 9],
	"muscle": [10, 28],
	"ligament": [29, 84],
	"severe": [85, 240],
}

const GRADE_WEIGHTS := {"knock": 0.55, "muscle": 0.28, "ligament": 0.13, "severe": 0.04}


const BAN_RED := 1
const BAN_SECOND_YELLOW := 1


const THRESHOLDS := [[5, 19, 1], [10, 32, 2], [15, 38, 3]]


const INJURY_RATE := 0.22


const RATE_MIN := 0.8
const RATE_MAX := 1.2

const KIND_INJURY := "injury"
const KIND_SUSPENSION := "suspension"


static func enabled() -> bool:
	var season := LeagueSeason.active
	return season != null and season.save != null and PLDatabase.get_db() != null


static func unavailable(club_id: String, competition_id: String = "") -> Dictionary:
	var out := {}
	if club_id == "" or not enabled():
		return out
	var sql := "SELECT player_id FROM league_absence WHERE club_id = ?"
	var bindings: Array = [club_id]
	if competition_id != "":
		sql += " AND (kind = ? OR competition_id = ?)"
		bindings.append_array([KIND_INJURY, competition_id])
	for row in PLDatabase.rows(sql + ";", bindings):
		out[str(row["player_id"])] = true
	return out


static func rows(club_id: String, competition_id: String = "") -> Array:
	if club_id == "" or not enabled():
		return []
	var sql := ("SELECT a.*, p.name AS player_name, p.number AS number, p.pos AS pos "
		+ "FROM league_absence a LEFT JOIN player p ON p.id = a.player_id "
		+ "WHERE a.club_id = ?")
	var bindings: Array = [club_id]
	if competition_id != "":
		sql += " AND (a.kind = ? OR a.competition_id = ?)"
		bindings.append_array([KIND_INJURY, competition_id])
	return PLDatabase.rows(
		sql + " ORDER BY a.kind DESC, a.days_left DESC, a.matches_left DESC;", bindings)


static func absences(club_id: String, competition_id: String = "") -> Array:
	var out: Array = []
	for row in rows(club_id, competition_id):
		var kind := str(row.get("kind", ""))
		var label := recovery_label(int(row.get("days_left", 0))) if kind == KIND_INJURY \
			else ban_label(int(row.get("matches_left", 0)))
		out.append({
			"player_id": str(row["player_id"]),
			"name": str(row.get("player_name", "")),
			"number": int(row.get("number", 0)),
			"kind": kind,
			"grade": str(row.get("grade", "")),
			"competition_id": str(row.get("competition_id", "")),
			"label": label,
		})
	return out


static func recovery_label(days_left: int) -> String:
	if days_left <= 0:
		return "FIT"
	if days_left <= 7:
		return "1 WEEK"
	if days_left <= 60:
		return "%d WEEKS" % int(ceil(float(days_left) / 7.0))
	var months := int(ceil(float(days_left) / 30.0))
	return "%d MONTHS" % months if months > 1 else "1 MONTH"


static func ban_label(matches_left: int) -> String:
	if matches_left <= 0:
		return "AVAILABLE"
	return "1 MATCH" if matches_left == 1 else "%d MATCHES" % matches_left


static func injure(player_id: String, club_id: String, date: String, grade: String,
		days: int, rate: float = 1.0) -> bool:
	if player_id == "" or club_id == "" or not enabled():
		return false
	var span: Array = GRADE_DAYS.get(grade, GRADE_DAYS["knock"])
	var out_days := clampi(days, int(span[0]), int(span[1]))
	return PLDatabase.execute(
		"INSERT INTO league_absence (player_id, competition_id, club_id, kind, grade, days_left, "
		+ "matches_left, started_on, due_on, rate) VALUES (?, '', ?, ?, ?, ?, 0, ?, ?, ?) "
		+ "ON CONFLICT(player_id, competition_id) DO UPDATE SET club_id = excluded.club_id, "
		+ "kind = excluded.kind, grade = excluded.grade, days_left = excluded.days_left, "
		+ "matches_left = 0, started_on = excluded.started_on, due_on = excluded.due_on, "
		+ "rate = excluded.rate;",
		[player_id, club_id, KIND_INJURY, grade, out_days, date,
			FixtureCalendar.add_days(date, out_days) if date != "" else "", rate])


static func suspend(player_id: String, club_id: String, matches: int, reason: String,
		date: String = "", competition_id: String = "") -> bool:
	if player_id == "" or club_id == "" or matches <= 0 or not enabled():
		return false
	var competition := competition_id if competition_id != "" else league_of(club_id)
	return PLDatabase.execute(
		"INSERT INTO league_absence (player_id, competition_id, club_id, kind, grade, "
		+ "days_left, matches_left, started_on, due_on, rate) VALUES (?, ?, ?, ?, ?, 0, ?, ?, '', 1.0) "
		+ "ON CONFLICT(player_id, competition_id) DO UPDATE SET club_id = excluded.club_id, "
		+ "kind = excluded.kind, grade = excluded.grade, days_left = 0, "
		+ "matches_left = MAX(league_absence.matches_left, excluded.matches_left), "
		+ "started_on = excluded.started_on, due_on = '';",
		[player_id, competition, club_id, KIND_SUSPENSION, reason, matches, date])


static func league_of(club_id: String) -> String:
	var row := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	return str(row.get("competition_id", ""))


static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var pick := rng.randf()
	var acc := 0.0
	var grade := "knock"
	for key in ["knock", "muscle", "ligament", "severe"]:
		acc += float(GRADE_WEIGHTS[key])
		if pick <= acc:
			grade = key
			break
	var span: Array = GRADE_DAYS[grade]
	var days := rng.randi_range(int(span[0]), int(span[1]))
	return {"grade": grade, "days": days, "rate": rng.randf_range(RATE_MIN, RATE_MAX)}


static func apply_fixture(matchday: int, date: String, sides: Array, seed: int,
		competition_id: String = "") -> void:
	if not enabled():
		return
	for side in sides:
		var club := str(side.get("club_id", ""))
		if club == "":
			continue
		var competition := competition_id if competition_id != "" else league_of(club)
		_serve(club, competition)
		_discipline(club, competition, matchday, side.get("rows", []), date)
		_injuries(club, side.get("events", []), date, seed)

static func _serve(club_id: String, competition_id: String) -> void:
	for row in PLDatabase.rows(
			"SELECT player_id, matches_left FROM league_absence WHERE club_id = ? AND kind = ? "
			+ "AND competition_id = ?;", [club_id, KIND_SUSPENSION, competition_id]):
		var left := int(row["matches_left"]) - 1
		var id := str(row["player_id"])
		if left <= 0:
			PLDatabase.execute(
				"DELETE FROM league_absence WHERE player_id = ? AND competition_id = ?;",
				[id, competition_id])
		else:
			PLDatabase.execute(
				"UPDATE league_absence SET matches_left = ? WHERE player_id = ? "
				+ "AND competition_id = ?;", [left, id, competition_id])

static func _discipline(club_id: String, competition_id: String, matchday: int,
		lines: Array, date: String) -> void:
	for line in lines:
		var id := str(line.get("player_id", ""))
		if id == "":
			continue
		var yellows := int(line.get("yellow", 0))
		if int(line.get("red", 0)) > 0:
			suspend(id, club_id, BAN_RED, "red", date, competition_id)
			continue
		if yellows >= 2:
			suspend(id, club_id, BAN_SECOND_YELLOW, "second_yellow", date, competition_id)
		_accumulation(id, club_id, competition_id, matchday, yellows, date)


static func _accumulation(player_id: String, club_id: String, competition_id: String,
		matchday: int, added: int, date: String) -> void:
	if added <= 0:
		return
	PLDatabase.execute(
		"INSERT INTO league_discipline (player_id, competition_id, club_id, yellows, "
		+ "yellow_mark) VALUES (?, ?, ?, ?, 0) ON CONFLICT(player_id, competition_id) "
		+ "DO UPDATE SET club_id = excluded.club_id, "
		+ "yellows = league_discipline.yellows + excluded.yellows;",
		[player_id, competition_id, club_id, added])
	if LeagueCup.is_cup(competition_id) or LeagueUefa.is_continental(competition_id):
		return
	var row := PLDatabase.row(
		"SELECT yellows, yellow_mark FROM league_discipline "
		+ "WHERE player_id = ? AND competition_id = ?;", [player_id, competition_id])
	var total := int(row.get("yellows", 0))
	var mark := int(row.get("yellow_mark", 0))
	for step in THRESHOLDS:
		var cards := int(step[0])
		var by := int(step[1])
		if total < cards or mark >= cards:
			continue
		if matchday > by:
			_set_mark(player_id, club_id, competition_id, cards)
			continue
		suspend(player_id, club_id, int(step[2]), "yellow", date, competition_id)
		_set_mark(player_id, club_id, competition_id, cards)

static func _set_mark(player_id: String, club_id: String, competition_id: String,
		mark: int) -> void:
	PLDatabase.execute(
		"INSERT INTO league_discipline (player_id, competition_id, club_id, yellows, yellow_mark) "
		+ "VALUES (?, ?, ?, 0, ?) ON CONFLICT(player_id, competition_id) "
		+ "DO UPDATE SET club_id = excluded.club_id, yellow_mark = excluded.yellow_mark;",
		[player_id, competition_id, club_id, mark])

static func _injuries(club_id: String, events: Array, date: String, seed: int) -> void:
	for e in events:
		if str(e.get("kind", "")) != KIND_INJURY:
			continue
		var id := str(e.get("player_id", ""))
		if id == "":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed(seed, id)
		var drawn := roll(rng)
		injure(id, club_id, date, str(drawn["grade"]), int(drawn["days"]), float(drawn["rate"]))


static func _seed(seed: int, player_id: String) -> int:
	var h := seed
	for i in range(player_id.length()):
		h = int((h * 31 + player_id.unicode_at(i)) % 2147483647)
	return h


static func month_tick(from_date: String, to_date: String) -> int:
	if not enabled() or from_date == "" or to_date == "":
		return 0
	if from_date.substr(0, 7) == to_date.substr(0, 7):
		return 0
	var elapsed := maxi(FixtureCalendar.days_from(to_date) - FixtureCalendar.days_from(from_date), 1)
	var healed := 0
	for row in PLDatabase.rows("SELECT * FROM league_absence WHERE kind = ?;", [KIND_INJURY]):
		var id := str(row["player_id"])
		var left := int(row["days_left"]) - int(round(float(elapsed) * float(row.get("rate", 1.0))))
		if left <= 0:
			PLDatabase.execute(
				"DELETE FROM league_absence WHERE player_id = ? AND competition_id = ?;",
				[id, str(row.get("competition_id", ""))])
			healed += 1
			continue
		PLDatabase.execute(
			"UPDATE league_absence SET days_left = ?, due_on = ? WHERE player_id = ? "
			+ "AND competition_id = ?;",
			[left, FixtureCalendar.add_days(to_date, left), id, str(row.get("competition_id", ""))])
	return healed
