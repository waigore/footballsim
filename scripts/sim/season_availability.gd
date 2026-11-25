class_name SeasonAvailability
extends RefCounted

## Availability across a season: injuries that outlive the match they started in,
## and suspensions served by later fixtures. Both are stored in the save, so a
## club carries them through every gameweek on either outcome path.
##
## An injury has a **severity grade**, an exact number of days out that the
## player never sees, and a recovery rate. The hidden count is only recalculated
## when the season clock crosses a calendar month (see `month_tick`); the screen
## reads weeks or months (`recovery_label`), never the days.
##
## A suspension is a count of the club's next fixtures. The Premier League
## 2026-27 disciplinary table lives here (`THRESHOLDS`, `BAN_RED`,
## `BAN_SECOND_YELLOW`) and the cards themselves stay the sims' own: this module
## only turns cards already in the report into bans.
##
## Everything reads the save bound to `PLDatabase` through the active
## `LeagueSeason`, so single-match mode — which closes the season — never sees a
## season absence and fields a full squad.

## Severity grades, lightest first. Days out are hidden from the player.
const GRADE_DAYS := {
	"knock": [3, 9],
	"muscle": [10, 28],
	"ligament": [29, 84],
	"severe": [85, 240],
}
## Share of season injuries in each grade. Most knocks, few long terms.
const GRADE_WEIGHTS := {"knock": 0.55, "muscle": 0.28, "ligament": 0.13, "severe": 0.04}

## A straight red is a one-match ban; so is a second yellow in one match.
const BAN_RED := 1
const BAN_SECOND_YELLOW := 1
## Yellow accumulation: `[cards, by matchday, matches banned]`. A player who
## reaches five after the nineteenth game carries on without a ban but still
## counts towards ten, exactly as the league's own table works.
const THRESHOLDS := [[5, 19, 1], [10, 32, 2], [15, 38, 3]]

## Chance a side loses a body in an auto-simmed fixture, per side. The engine's
## fatigue path lands at about a quarter per side, so the two paths agree.
const INJURY_RATE := 0.22
## A recovery rate is drawn per injury and stays with it: a body heals a little
## faster or slower than the calendar, never wildly so.
const RATE_MIN := 0.8
const RATE_MAX := 1.2

const KIND_INJURY := "injury"
const KIND_SUSPENSION := "suspension"

# ------------------------------------------------------------------ state ---

## A season is open and owns the bound save. Without one there is no availability
## to read: single-match mode always fields a full squad.
static func enabled() -> bool:
	var season := LeagueSeason.active
	return season != null and season.save != null and PLDatabase.get_db() != null

## Player ids who cannot be picked for `club_id` (injured or suspended).
static func unavailable(club_id: String) -> Dictionary:
	var out := {}
	if club_id == "" or not enabled():
		return out
	for row in PLDatabase.rows("SELECT player_id FROM league_absence WHERE club_id = ?;", [club_id]):
		out[str(row["player_id"])] = true
	return out

## Every absence row for one club, joined with the player's name and number.
static func rows(club_id: String) -> Array:
	if club_id == "" or not enabled():
		return []
	return PLDatabase.rows(
		"SELECT a.*, p.name AS player_name, p.number AS number, p.pos AS pos "
		+ "FROM league_absence a LEFT JOIN player p ON p.id = a.player_id "
		+ "WHERE a.club_id = ? ORDER BY a.kind DESC, a.days_left DESC, a.matches_left DESC;",
		[club_id])

## What the briefing reads: one line per absence, in public wording only.
static func absences(club_id: String) -> Array:
	var out: Array = []
	for row in rows(club_id):
		var kind := str(row.get("kind", ""))
		var label := recovery_label(int(row.get("days_left", 0))) if kind == KIND_INJURY \
			else ban_label(int(row.get("matches_left", 0)))
		out.append({
			"player_id": str(row["player_id"]),
			"name": str(row.get("player_name", "")),
			"number": int(row.get("number", 0)),
			"kind": kind,
			"grade": str(row.get("grade", "")),
			"label": label,
		})
	return out

## Public wording for an injury: weeks up to two months, then months. The exact
## day count is never printed.
static func recovery_label(days_left: int) -> String:
	if days_left <= 0:
		return "FIT"
	if days_left <= 7:
		return "1 WEEK"
	if days_left <= 60:
		return "%d WEEKS" % int(ceil(float(days_left) / 7.0))
	var months := int(ceil(float(days_left) / 30.0))
	return "%d MONTHS" % months if months > 1 else "1 MONTH"

## Public wording for a suspension: the club's next fixtures.
static func ban_label(matches_left: int) -> String:
	if matches_left <= 0:
		return "AVAILABLE"
	return "1 MATCH" if matches_left == 1 else "%d MATCHES" % matches_left

# ----------------------------------------------------------------- writes ---

## Grade one injury and write it into the save. `days` is hidden.
static func injure(player_id: String, club_id: String, date: String, grade: String,
		days: int, rate: float = 1.0) -> bool:
	if player_id == "" or club_id == "" or not enabled():
		return false
	var span: Array = GRADE_DAYS.get(grade, GRADE_DAYS["knock"])
	var out_days := clampi(days, int(span[0]), int(span[1]))
	return PLDatabase.execute(
		"INSERT INTO league_absence (player_id, club_id, kind, grade, days_left, matches_left, "
		+ "started_on, due_on, rate) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?) "
		+ "ON CONFLICT(player_id) DO UPDATE SET club_id = excluded.club_id, kind = excluded.kind, "
		+ "grade = excluded.grade, days_left = excluded.days_left, matches_left = 0, "
		+ "started_on = excluded.started_on, due_on = excluded.due_on, rate = excluded.rate;",
		[player_id, club_id, KIND_INJURY, grade, out_days, date,
			FixtureCalendar.add_days(date, out_days) if date != "" else "", rate])

## Write a suspension: `matches` of the club's next fixtures.
static func suspend(player_id: String, club_id: String, matches: int, reason: String,
		date: String = "") -> bool:
	if player_id == "" or club_id == "" or matches <= 0 or not enabled():
		return false
	# A ban replaces any ban already being served rather than stacking silently.
	return PLDatabase.execute(
		"INSERT INTO league_absence (player_id, club_id, kind, grade, days_left, matches_left, "
		+ "started_on, due_on, rate) VALUES (?, ?, ?, ?, 0, ?, ?, '', 1.0) "
		+ "ON CONFLICT(player_id) DO UPDATE SET club_id = excluded.club_id, kind = excluded.kind, "
		+ "grade = excluded.grade, days_left = 0, matches_left = excluded.matches_left, "
		+ "started_on = excluded.started_on, due_on = '';",
		[player_id, club_id, KIND_SUSPENSION, reason, matches, date])

## Draw a severity grade and its exact days out from a seeded generator.
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

# ------------------------------------------------------------- fixture hook ---

## Settle one finished fixture for both clubs: serve the bans that were waiting
## for it, read today's cards into new bans, and turn injury events into season
## injuries. `sides` is `[{club_id, rows: [{player_id, yellow, red}]}, …]`.
static func apply_fixture(matchday: int, date: String, sides: Array, seed: int) -> void:
	if not enabled():
		return
	for side in sides:
		var club := str(side.get("club_id", ""))
		if club == "":
			continue
		# A ban is served by the club's next fixture, so today's games clear
		# yesterday's bans before today's cards can add new ones.
		_serve(club)
		_discipline(club, matchday, side.get("rows", []), date)
		_injuries(club, side.get("events", []), date, seed)

static func _serve(club_id: String) -> void:
	for row in PLDatabase.rows(
			"SELECT player_id, matches_left FROM league_absence WHERE club_id = ? AND kind = ?;",
			[club_id, KIND_SUSPENSION]):
		var left := int(row["matches_left"]) - 1
		var id := str(row["player_id"])
		if left <= 0:
			PLDatabase.execute("DELETE FROM league_absence WHERE player_id = ?;", [id])
		else:
			PLDatabase.execute("UPDATE league_absence SET matches_left = ? WHERE player_id = ?;",
				[left, id])

static func _discipline(club_id: String, matchday: int, lines: Array, date: String) -> void:
	for line in lines:
		var id := str(line.get("player_id", ""))
		if id == "":
			continue
		if int(line.get("red", 0)) > 0:
			suspend(id, club_id, BAN_RED, "red", date)
			continue
		if int(line.get("yellow", 0)) >= 2:
			suspend(id, club_id, BAN_SECOND_YELLOW, "second_yellow", date)
		_accumulation(id, club_id, matchday, date)

## Yellow accumulation against the locked table. A threshold already punished is
## remembered in `league_discipline`, so ten cards never pays twice for five.
static func _accumulation(player_id: String, club_id: String, matchday: int, date: String) -> void:
	var stat := PLDatabase.row("SELECT yellow FROM league_player_stat WHERE player_id = ?;",
		[player_id])
	var total := int(stat.get("yellow", 0))
	if total <= 0:
		return
	var mark_row := PLDatabase.row("SELECT yellow_mark FROM league_discipline WHERE player_id = ?;",
		[player_id])
	var mark := int(mark_row.get("yellow_mark", 0))
	for step in THRESHOLDS:
		var cards := int(step[0])
		var by := int(step[1])
		if total < cards or mark >= cards:
			continue
		# Past its cut-off the threshold no longer bans, but it is spent: the
		# next one (ten) is what the rest of the season plays for.
		if matchday > by:
			_set_mark(player_id, club_id, cards)
			continue
		suspend(player_id, club_id, int(step[2]), "yellow", date)
		_set_mark(player_id, club_id, cards)

static func _set_mark(player_id: String, club_id: String, mark: int) -> void:
	PLDatabase.execute(
		"INSERT INTO league_discipline (player_id, club_id, yellow_mark) VALUES (?, ?, ?) "
		+ "ON CONFLICT(player_id) DO UPDATE SET club_id = excluded.club_id, "
		+ "yellow_mark = excluded.yellow_mark;",
		[player_id, club_id, mark])

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

## Deterministic per player, so reopening a save and replaying the same fixture
## draws the same injury.
static func _seed(seed: int, player_id: String) -> int:
	var h := seed
	for i in range(player_id.length()):
		h = int((h * 31 + player_id.unicode_at(i)) % 2147483647)
	return h

# ------------------------------------------------------------- month tick ---

## The clock crossed into a new calendar month: every body out heals by the days
## that passed, scaled by its own recovery rate. Bounded drift, not a reroll —
## an injury can heal faster or slower than the calendar but never jump.
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
			PLDatabase.execute("DELETE FROM league_absence WHERE player_id = ?;", [id])
			healed += 1
			continue
		PLDatabase.execute(
			"UPDATE league_absence SET days_left = ?, due_on = ? WHERE player_id = ?;",
			[left, FixtureCalendar.add_days(to_date, left), id])
	return healed
