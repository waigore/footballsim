extends GdToolsTest

## The two fixture calendars: real pairings and dates from the snapshot, and a
## generated PL-like double round robin that obeys the saved window and the
## weekend/midweek policy.

var CACHE_DIR := TestScratch.dir("cache_test_calendar_issue58")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _rules() -> Dictionary:
	var r := LeagueRules.defaults()
	r["season_start"] = "2026-08-15"
	r["season_end"] = "2027-05-23"
	return r

func test_a_generated_season_is_a_double_round_robin() -> void:
	var rows := FixtureCalendar.generate(TeamData.team_ids("PL"), _rules(), 42)
	assert_eq(rows.size(), 380, "a twenty-club double round robin is 380 fixtures")
	var home := {}
	var away := {}
	var rounds := {}
	for fx in rows:
		home[str(fx["home"])] = int(home.get(str(fx["home"]), 0)) + 1
		away[str(fx["away"])] = int(away.get(str(fx["away"]), 0)) + 1
		rounds[int(fx["matchday"])] = int(rounds.get(int(fx["matchday"]), 0)) + 1
	assert_eq(rounds.size(), 38, "the calendar does not have 38 gameweeks")
	for id in TeamData.team_ids("PL"):
		assert_eq(int(home.get(id, 0)), 19, "%s does not host 19 games" % id)
		assert_eq(int(away.get(id, 0)), 19, "%s does not travel 19 times" % id)
	for round in rounds:
		assert_eq(int(rounds[round]), 10, "gameweek %d does not have ten games" % round)

func test_generated_pairings_meet_every_club_twice() -> void:
	var rows := FixtureCalendar.generate(TeamData.team_ids("PL"), _rules(), 7)
	var pairs := {}
	for fx in rows:
		var key := [str(fx["home"]), str(fx["away"])]
		key.sort()
		var k := "%s|%s" % key
		pairs[k] = int(pairs.get(k, 0)) + 1
	for key in pairs:
		assert_eq(int(pairs[key]), 2, "%s does not meet twice" % key)
	assert_eq(pairs.size(), 190, "20 clubs should meet in 190 distinct pairings")

func test_generated_dates_are_pl_like() -> void:
	var rules := _rules()
	var rows := FixtureCalendar.generate(TeamData.team_ids("PL"), rules, 99)
	var by_round := {}
	for fx in rows:
		by_round[int(fx["matchday"])] = str(fx["kickoff"])
	var last := ""
	var midweek := 0
	for round in range(1, 39):
		var date := str(by_round[round])
		assert_true(date > last, "gameweek %d does not follow the previous one" % round)
		last = date
		if FixtureCalendar.weekday_of(FixtureCalendar.days_from(date)) != 6:
			midweek += 1
	assert_true(last >= "2027-05-01", "the generated season ends before May")
	assert_lte(int(midweek), int(rules["midweek_matchdays"]), "too many midweek rounds")
	assert_gte(int(midweek), 3, "the calendar has almost no midweek football")
	assert_gte(FixtureCalendar.days_from(str(by_round[1])), FixtureCalendar.days_from("2026-08-15") - 7, "the season starts too early")

func test_generation_is_seeded_and_repeatable() -> void:
	var a := FixtureCalendar.generate(TeamData.team_ids("PL"), _rules(), 1234)
	var b := FixtureCalendar.generate(TeamData.team_ids("PL"), _rules(), 1234)
	var c := FixtureCalendar.generate(TeamData.team_ids("PL"), _rules(), 4321)
	assert_eq(a.size(), b.size(), "two runs of one seed differ in size")
	assert_eq(str(a[0]["home"]), str(b[0]["home"]), "one seed produced two calendars")
	assert_eq(str(a[0]["kickoff"]), str(b[0]["kickoff"]), "one seed produced two dates")
	var differ := false
	for i in range(a.size()):
		if str(a[i]["home"]) != str(c[i]["home"]):
			differ = true
			break
	assert_true(differ, "the seed does not reach the calendar")

func test_a_real_calendar_matches_the_snapshot() -> void:
	var rows := FixtureCalendar.real_rows()
	assert_eq(rows.size(), 380, "the snapshot calendar lost fixtures")
	var rounds := {}
	for fx in rows:
		rounds[int(fx["matchday"])] = int(rounds.get(int(fx["matchday"]), 0)) + 1
	assert_eq(rounds.size(), 38, "the real calendar does not rebuild 38 gameweeks")
	for round in rounds:
		assert_eq(int(rounds[round]), 10, "real gameweek %d does not have ten games" % round)
	var snapshot := PLDatabase.rows(
		"SELECT id, kickoff, home_club_id, away_club_id FROM fixture WHERE competition_id = 'PL';")
	assert_eq(snapshot.size(), rows.size(), "the snapshot fixture count moved")
	var seen := {}
	for row in snapshot:
		seen["%s|%s|%s" % [str(row["kickoff"]), str(row["home_club_id"]), str(row["away_club_id"])]] = true
	for fx in rows:
		var key := "%s|%s|%s" % [str(fx["kickoff"]), str(fx["home"]), str(fx["away"])]
		assert_true(seen.has(key), "the real calendar invented a fixture: %s" % key)
		assert_eq(int(fx["home_goals"]) if fx.has("home_goals") else 0, 0, "a real fixture kept a result")

func test_a_real_calendar_keeps_one_gameweek_per_date() -> void:
	## A gameweek is the weekend it was played on (#206): the ten games of one
	## round sit on the same few days, and one date never carries two rounds.
	var rows := FixtureCalendar.real_rows()
	var rounds := {}
	var dates := {}
	for fx in rows:
		var md := int(fx["matchday"])
		var day := str(fx["kickoff"])
		if not rounds.has(md):
			rounds[md] = {"first": day, "last": day}
		var span: Dictionary = rounds[md]
		if day < str(span["first"]):
			span["first"] = day
		if day > str(span["last"]):
			span["last"] = day
		if dates.has(day) and int(dates[day]) != md:
			assert_eq(md, int(dates[day]), "%s carries two gameweeks" % day)
		dates[day] = md
	for md in rounds:
		var span: Dictionary = rounds[md]
		var days := FixtureCalendar.days_from(str(span["last"])) - FixtureCalendar.days_from(str(span["first"]))
		assert_lte(days, 4, "gameweek %d spreads over %d days" % [md, days])

func test_real_gameweeks_follow_the_calendar() -> void:
	## The round number only ever moves forward with the dates, so the hub's
	## `GW n` and the STATS list read the season in the order it was played.
	var rows := FixtureCalendar.build("real", _rules(), 1)
	var last_md := 0
	var last_day := ""
	for fx in rows:
		var day := str(fx["kickoff"])
		var md := int(fx["matchday"])
		if last_day != "":
			assert_true(day >= last_day, "%s follows %s in the calendar" % [day, last_day])
			assert_gte(md, last_md, "gameweek %d comes back after %d" % [md, last_md])
		last_day = day
		last_md = maxi(last_md, md)
	var first_week := {}
	for fx in rows:
		if str(fx["kickoff"]) <= "2026-08-24":
			first_week[int(fx["matchday"])] = true
	assert_eq(first_week.keys(), [1], "the opening weekend is not gameweek one")

func test_date_rounds_splits_dates_and_rolls_on_a_clash() -> void:
	## The round walk: a date joins one round, a full round closes, and a
	## rearranged fixture whose clubs already play that round waits for the next.
	var rows := [
		{"kickoff": "2026-08-21", "home_club_id": "A", "away_club_id": "B"},
		{"kickoff": "2026-08-22", "home_club_id": "C", "away_club_id": "D"},
		{"kickoff": "2026-08-22", "home_club_id": "E", "away_club_id": "F"},
		{"kickoff": "2026-08-23", "home_club_id": "A", "away_club_id": "C"},
	]
	assert_eq(FixtureCalendar.date_rounds(rows, 4), [1, 1, 1, 2], "a clash did not open a round")
	assert_eq(FixtureCalendar.date_rounds(rows, 2), [1, 2, 2, 3], "a full round did not close")
	assert_eq(FixtureCalendar.date_rounds([], 10), [], "an empty calendar took rounds")
	# Two games on one date never land in different rounds, however tight the cap.
	var same_day := [
		{"kickoff": "2026-08-22", "home_club_id": "A", "away_club_id": "B"},
		{"kickoff": "2026-08-22", "home_club_id": "C", "away_club_id": "D"},
	]
	assert_eq(FixtureCalendar.date_rounds(same_day, 1), [1, 1], "a date was split across rounds")

func test_the_calendar_builds_in_both_modes() -> void:
	var real := FixtureCalendar.build("real", _rules(), 1)
	assert_eq(real.size(), 380, "real mode did not build a calendar")
	var generated := FixtureCalendar.build("generated", _rules(), 1)
	assert_eq(generated.size(), 380, "generated mode did not build a calendar")
	assert_eq(FixtureCalendar.build("generated", _rules(), 1).size(), 380, "the build is not repeatable")

func test_an_unknown_mode_falls_back_to_the_generator() -> void:
	var rows := FixtureCalendar.build("nonsense", _rules(), 3)
	assert_eq(rows.size(), 380, "an unknown mode built no calendar")

func test_odd_club_counts_and_short_windows_still_build() -> void:
	var clubs: Array = []
	for i in range(21):
		clubs.append("T%d" % i)
	var rounds := FixtureCalendar.pairings(clubs)
	assert_eq(rounds.size(), 21, "an odd squad count did not get a bye round")
	for round in rounds:
		assert_eq((round as Array).size(), 10, "the bye round did not drop one pairing")
	var dates := FixtureCalendar.round_dates("2026-08-15", "2026-09-01", 10, 2)
	assert_eq(dates.size(), 10, "a short window produced the wrong number of dates")
	for i in range(1, dates.size()):
		assert_true(str(dates[i]) > str(dates[i - 1]), "short-window dates are not increasing")

func test_day_labels_are_readable() -> void:
	assert_eq(FixtureCalendar.day_label("2026-08-15"), "15/AUG/2026", "the date label is wrong")
	assert_eq(FixtureCalendar.day_label("2026-08-05"), "5/AUG/2026", "the day took a leading zero")
	assert_eq(FixtureCalendar.day_label("2026-08"), "", "a month key produced a day label")
	assert_eq(FixtureCalendar.day_label(""), "", "an empty date produced a label")
	assert_eq(FixtureCalendar.weekday_label("2026-08-15"), "SAT", "the weekday hint is wrong")
	assert_eq(FixtureCalendar.weekday_label(""), "", "an empty date produced a weekday")
	assert_eq(FixtureCalendar.add_days("2026-08-15", 3), "2026-08-18", "date arithmetic is wrong")
	assert_eq(FixtureCalendar.weekday_of(FixtureCalendar.days_from("2026-08-15")), 6, "Saturday is miscounted")
