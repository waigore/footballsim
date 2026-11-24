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
## The snapshot stores no round number, and real fixtures move for cups and
## postponements, so the gameweek is rebuilt from the pairings themselves: the
## circle-method decomposition names every pairing once, the return leg is the
## mirror, and the rounds are then ordered by their mean date. Every gameweek
## therefore holds the ten games it should, and the dates stay exactly real.
static func real_rows() -> Array:
	var rows := PLDatabase.rows("SELECT * FROM fixture ORDER BY kickoff, id;")
	if rows.is_empty():
		return []
	var clubs: Array = []
	for row in rows:
		for key in ["home_club_id", "away_club_id"]:
			var id := str(row[key])
			if not clubs.has(id):
				clubs.append(id)
	clubs.sort()
	var first := pairings(clubs)
	var pivot := {}
	for r in range(first.size()):
		for pair in first[r]:
			pivot[_pair_key(str(pair[0]), str(pair[1]))] = {"round": r, "home": str(pair[0])}
	var dates := {}
	for row in rows:
		var h := str(row["home_club_id"])
		var entry: Dictionary = pivot.get(_pair_key(h, str(row["away_club_id"])), {})
		var round := int(entry.get("round", 0)) + 1
		if str(entry.get("home", h)) != h:
			round += first.size()
		var stamp := days_from(str(row["kickoff"]))
		if not dates.has(round):
			dates[round] = [0, 0]
		var slot: Array = dates[round]
		slot[0] = int(slot[0]) + stamp
		slot[1] = int(slot[1]) + 1
		row["round"] = round
		row["stamp"] = stamp
	var keys := dates.keys()
	keys.sort_custom(func(a, b):
		return float(dates[a][0]) / float(dates[a][1]) < float(dates[b][0]) / float(dates[b][1]))
	var number := {}
	for i in range(keys.size()):
		number[int(keys[i])] = i + 1
	var out: Array = []
	for row in rows:
		out.append({
			"id": "real-" + str(row["id"]),
			"matchday": int(number.get(int(row["round"]), 1)),
			"kickoff": str(row["kickoff"]),
			"kickoff_time": "",
			"home": str(row["home_club_id"]),
			"away": str(row["away_club_id"]),
		})
	return out

static func _pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)


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

## "SAT 15 AUG" — the calendar's day heading.
static func day_label(date: String) -> String:
	if date == "":
		return ""
	var d := Time.get_datetime_dict_from_unix_time(days_from(date) * SECONDS_PER_DAY)
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	return "%s %d %s" % [WEEKDAYS[int(d["weekday"])], int(d["day"]), months[int(d["month"]) - 1]]
