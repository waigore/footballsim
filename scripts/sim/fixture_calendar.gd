class_name FixtureCalendar
extends RefCounted

## The two ways a league save gets its fixture list.
##
## **Real** copies the shipped snapshot's calendar — the pairings and the dates
## of the season it was taken from (2026-27) — and clears the results, so a new
## save starts at gameweek one on real dates. **Generated** builds a PL-like
## schedule from the saved regulations: a double round robin (every club home
## and away against every other), mostly weekends from late August to May with
## the regulated number of midweek rounds.
##
## Both modes produce the same rows, so everything downstream (planner, table,
## calendar) is mode-blind.

const WEEKDAYS := ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT",
	"NOV", "DEC"]
const KICKOFF_TIMES := ["12:30", "15:00", "17:30"]
const SECONDS_PER_DAY := 86400

## Rows ready for `league_fixture`: id, matchday, kickoff, kickoff_time, home,
## away. Results stay empty — a save starts unplayed in either mode.
static func build(mode: String, rules: Dictionary, seed: int) -> Array:
	var rows: Array = []
	if mode == "real":
		rows = real_rows()
	if rows.is_empty():
		rows = generate(TeamData.team_ids(), rules, seed)
	return rows

# ------------------------------------------------------------------ real ---

## Pairings and dates from the shipped snapshot. The snapshot is a reading of a
## live season, so some fixtures already carry results; a new save starts
## unplayed, so the results are deliberately left behind and the calendar and
## its dates are what a real-mode save inherits.
##
## The snapshot stores no round number, and a real season packs one gameweek
## into the dates it was played on, so the gameweek is read off the calendar
## itself: dates are walked oldest first and a new gameweek opens at the first
## date that would not fit the one before it (see `date_rounds`). A date is
## never split across two gameweeks, so the hub's `GW n`, the round's ten games
## and the dates they are played on always name one weekend.
static func real_rows() -> Array:
	var rows := PLDatabase.rows("SELECT * FROM fixture ORDER BY kickoff, id;")
	if rows.is_empty():
		return []
	var clubs := {}
	for row in rows:
		clubs[str(row["home_club_id"])] = true
		clubs[str(row["away_club_id"])] = true
	var numbers := date_rounds(rows, maxi(clubs.size() / 2, 1))
	var out: Array = []
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		out.append({
			"id": "real-" + str(row["id"]),
			"matchday": int(numbers[i]),
			"kickoff": str(row["kickoff"]),
			"kickoff_time": "",
			"home": str(row["home_club_id"]),
			"away": str(row["away_club_id"]),
		})
	return out

## The gameweek of every snapshot row, in the order the rows arrive (kickoff,
## then id).
##
## Rows are grouped by date and a whole date joins one round, so a weekend's
## games are never divided between two gameweeks. A new round opens when the
## date would take the round past `per_round` games, or when a club on the date
## is already playing in that round — a rearranged fixture dropped among
## another weekend's games files itself into the next one. Consecutive dates
## therefore stay in one round until it is full, which is how a real weekend
## spreads ten games over Friday to Monday.
static func date_rounds(rows: Array, per_round: int) -> Array:
	var out: Array = []
	var round := 1
	var count := 0
	var playing := {}
	var i := 0
	while i < rows.size():
		var day := str((rows[i] as Dictionary)["kickoff"])
		var day_rows: Array = []
		while i < rows.size() and str((rows[i] as Dictionary)["kickoff"]) == day:
			day_rows.append(rows[i])
			i += 1
		var clash := false
		for row in day_rows:
			if playing.has(str(row["home_club_id"])) or playing.has(str(row["away_club_id"])):
				clash = true
		if clash or (count > 0 and count + day_rows.size() > per_round):
			round += 1
			count = 0
			playing = {}
		for row in day_rows:
			playing[str(row["home_club_id"])] = true
			playing[str(row["away_club_id"])] = true
			count += 1
			out.append(round)
	return out


# ------------------------------------------------------------- generated ---

static func generate(clubs: Array, rules: Dictionary, seed: int) -> Array:
	var ids := clubs.duplicate()
	if ids.size() < 2:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# A fixed pairing pattern, rotated per save so no two saves start alike.
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = ids[i]
		ids[i] = ids[j]
		ids[j] = swap
	var first := pairings(ids)
	var rounds: Array = first.duplicate(true)
	for round in first:
		var mirrored: Array = []
		for pair in round:
			mirrored.append([str(pair[1]), str(pair[0])])
		rounds.append(mirrored)
	var dates := round_dates(
		str(rules.get("season_start", LeagueRules.DEFAULTS["season_start"])),
		str(rules.get("season_end", LeagueRules.DEFAULTS["season_end"])),
		rounds.size(),
		int(rules.get("midweek_matchdays", 5)),
	)
	var out: Array = []
	for r in range(rounds.size()):
		var pairs: Array = rounds[r]
		var date: String = dates[mini(r, dates.size() - 1)]
		for k in range(pairs.size()):
			var pair: Array = pairs[k]
			out.append({
				"id": "gw%02d-%s-%s" % [r + 1, str(pair[0]), str(pair[1])],
				"matchday": r + 1,
				"kickoff": date,
				"kickoff_time": KICKOFF_TIMES[k % KICKOFF_TIMES.size()],
				"home": str(pair[0]),
				"away": str(pair[1]),
			})
	return out

## Circle method: one round of pairings per call, alternating the home side so
## no club collects a long home or away run.
static func pairings(clubs: Array) -> Array:
	var pool := clubs.duplicate()
	if pool.size() % 2 == 1:
		pool.append("BYE")
	var n := pool.size()
	var rotation := pool.duplicate()
	var rounds: Array = []
	for r in range(n - 1):
		var pairs: Array = []
		for i in range(n / 2):
			var a := str(rotation[i])
			var b := str(rotation[n - 1 - i])
			if a == "BYE" or b == "BYE":
				continue
			if (r + i) % 2 == 0:
				pairs.append([a, b])
			else:
				pairs.append([b, a])
		rounds.append(pairs)
		var rest: Array = rotation.slice(1)
		rest.push_front(rest.pop_back())
		rotation = [rotation[0]]
		rotation.append_array(rest)
	return rounds

## One date per round: Saturdays across the window, with the regulated number
## of rounds moved to the Wednesday before. Dates stay strictly increasing.
static func round_dates(start: String, end: String, rounds: int, midweek: int) -> Array:
	var first := days_from(start)
	var last := days_from(end)
	var saturdays: Array = []
	var d := first
	while d <= last:
		if weekday_of(d) == 6:
			saturdays.append(d)
		d += 1
	if saturdays.size() < rounds:
		saturdays.clear()
		for i in range(rounds):
			saturdays.append(first + i * 7)
	var picks: Array = []
	for i in range(rounds):
		var span: float = float(maxi(saturdays.size() - 1, 0))
		var idx: int = int(round(span * float(i) / float(maxi(rounds - 1, 1)))) if saturdays.size() > rounds else i
		picks.append(int(saturdays[mini(idx, saturdays.size() - 1)]))
	picks.sort()
	for j in range(midweek):
		var idx: int = clampi(int(round((float(j) + 0.5) * float(rounds) / float(maxi(midweek, 1)))), 0, rounds - 1)
		var wed: int = int(picks[idx]) - 3
		var floor: int = int(picks[idx - 1]) + 2 if idx > 0 else first
		if wed > floor:
			picks[idx] = wed
	for i in range(1, picks.size()):
		if int(picks[i]) <= int(picks[i - 1]):
			picks[i] = int(picks[i - 1]) + 7
	var out: Array = []
	for v in picks:
		out.append(date_from(int(v)))
	return out

# ------------------------------------------------------------------ dates ---

static func days_from(date: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(date + "T00:00:00")) / SECONDS_PER_DAY

static func date_from(days: int) -> String:
	return Time.get_date_string_from_unix_time(days * SECONDS_PER_DAY)

static func weekday_of(days: int) -> int:
	return int(Time.get_datetime_dict_from_unix_time(days * SECONDS_PER_DAY)["weekday"])

static func add_days(date: String, days: int) -> String:
	return date_from(days_from(date) + days)

## "15/AUG/2026" — the one display form for a calendar date. The day carries no
## leading zero; months are the three-letter English name in upper case and the
## year is always four digits. Internal storage stays ISO.
static func day_label(date: String) -> String:
	var d := _parts(date)
	if d.is_empty():
		return ""
	return "%d/%s/%d" % [int(d["day"]), MONTHS[int(d["month"]) - 1], int(d["year"])]

## "SAT" — the weekday a displayed date carries as its hover hint, never in the
## date itself.
static func weekday_label(date: String) -> String:
	var d := _parts(date)
	if d.is_empty():
		return ""
	return WEEKDAYS[int(d["weekday"])]

## The calendar pieces of an ISO date, or an empty dictionary when there is no
## date to read (a month key, a timeslot, an empty field).
static func _parts(date: String) -> Dictionary:
	if date.length() < 10:
		return {}
	return Time.get_datetime_dict_from_unix_time(days_from(date) * SECONDS_PER_DAY)
