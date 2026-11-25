extends GdToolsTest

## Per-goal report clips: the generated pack, the stored rows, the live capture
## path and the codec — driven through a real save so the report and the clip are
## always read from the same ledger.

var SAVE_DIR := TestScratch.dir("saves_test_clips_issue89")
var CACHE_DIR := TestScratch.dir("cache_test_clips_issue89")
const SEED := 4242

var season: LeagueSeason = null
var home_xi: Array = []
var away_xi: Array = []

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Clip Season", "generated", "fixture_days", SEED)
	home_xi = StrongestXI.pick(TeamData.get_team("MUN"))
	away_xi = StrongestXI.pick(TeamData.get_team("MCI"))

func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	TestScratch.clear(SAVE_DIR)

func _goal(minute: int = 34, club: String = "MUN", index: int = 1) -> Dictionary:
	return {
		"fixture_id": "gw01-MUN-MCI", "goal_index": index, "minute": minute,
		"home": "MUN", "away": "MCI", "club_id": club,
		"player_id": str(home_xi[9]["id"]), "player_name": str(home_xi[9]["name"]),
		"assist_id": str(home_xi[6]["id"]), "assist_name": str(home_xi[6]["name"]),
		"club_short": "MUN", "opp_short": "MCI", "score_after": [2, 1],
	}

func _sides() -> Dictionary:
	return {"home": home_xi, "away": away_xi}

# ------------------------------------------------------------------ codec ---

func test_a_pack_round_trips_through_its_blob() -> void:
	var seed := GoalHighlight.seed_for(SEED, "gw01-MUN-MCI", 1)
	var clip := GoalHighlight.build(_goal(), _sides(), seed)
	var bytes := GoalHighlight.pack(clip)
	assert_gt(bytes.size(), 500, "the pack collapsed to nothing")
	assert_lt(bytes.size(), 40000, "one clip is too big for a season save")
	var back := GoalHighlight.unpack(bytes)
	assert_false(back.is_empty(), "the pack did not decode")
	assert_eq((back["frames"] as Array).size(), (clip["frames"] as Array).size(), "frames were lost")
	assert_eq(str(back["scorer"]), str(home_xi[9]["name"]), "the clip lost its scorer")
	assert_eq(int(back["minute"]), 34, "the clip lost its minute")
	assert_eq(str(back["codec"]), GoalHighlight.CODEC, "the codec marker moved")
	assert_eq(int(back["version"]), GoalHighlight.VERSION, "the version moved")

func test_an_unknown_version_is_refused() -> void:
	var clip := GoalHighlight.build(_goal(), _sides(), 7)
	clip["version"] = GoalHighlight.VERSION + 9
	assert_true(GoalHighlight.unpack(GoalHighlight.pack(clip)).is_empty(),
		"a clip from a newer build was played anyway")
	assert_true(GoalHighlight.unpack(PackedByteArray()).is_empty(), "an empty blob decoded")

func test_the_same_save_seed_reproduces_the_same_clip() -> void:
	var seed := GoalHighlight.seed_for(SEED, "gw01-MUN-MCI", 1)
	var a := GoalHighlight.pack(GoalHighlight.build(_goal(), _sides(), seed))
	var b := GoalHighlight.pack(GoalHighlight.build(_goal(), _sides(), seed))
	var c := GoalHighlight.pack(GoalHighlight.build(_goal(), _sides(), seed + 1))
	assert_true(a == b, "the same goal produced two different clips")
	assert_true(a != c, "a new seed reproduced the old clip")

## #171: a tagged penalty keeps its scorer and minute but reads and plays as a
## spot kick — no assist, a line from the spot, and a different picture from the
## open-play chance the same seed would have drawn.
func test_a_penalty_clip_reads_and_plays_as_a_spot_kick() -> void:
	var goal := _goal()
	goal["penalty"] = true
	goal["assist_id"] = ""
	goal["assist_name"] = ""
	var seed := GoalHighlight.seed_for(SEED, "gw01-MUN-MCI", 1)
	var open_goal := _goal()
	goal["commentary"] = GoalHighlight.commentary(goal, seed)
	open_goal["commentary"] = GoalHighlight.commentary(open_goal, seed)
	var pen := GoalHighlight.build(goal, _sides(), seed)
	var open := GoalHighlight.build(open_goal, _sides(), seed)
	assert_eq(str(pen["scorer_id"]), str(goal["player_id"]), "the spot kick lost its taker")
	assert_eq(int(pen["minute"]), int(goal["minute"]), "the spot kick lost its minute")
	var line := str(pen["commentary"]).to_upper()
	assert_true(line.find("PENALTY") >= 0 or line.find("SPOT") >= 0 or line.find("TWELVE") >= 0,
		"the penalty clip's line did not say what it was: %s" % pen["commentary"])
	assert_ne(str(pen["commentary"]), str(open["commentary"]),
		"a penalty was narrated as open play")
	assert_true(GoalHighlight.pack(pen) != GoalHighlight.pack(open),
		"a penalty played the open-play picture")

func test_the_seed_follows_the_goal_index() -> void:
	var a := GoalHighlight.seed_for(SEED, "gw01-MUN-MCI", 0)
	var b := GoalHighlight.seed_for(SEED, "gw01-MUN-MCI", 1)
	var c := GoalHighlight.seed_for(SEED, "gw02-MUN-LIV", 0)
	assert_ne(a, b, "two goals of one fixture share a seed")
	assert_ne(a, c, "two fixtures share a seed")

# ------------------------------------------------------------------ frames ---

func test_the_clip_ends_with_the_reported_goal() -> void:
	var clip := GoalHighlight.build(_goal(63), _sides(), 99)
	var frames: Array = clip["frames"]
	var first: Dictionary = frames[0]
	var last: Dictionary = frames[frames.size() - 1]
	assert_eq(int(first["g"]), 0, "the clip opened with the goal already scored")
	assert_eq(int(last["g"]), 1, "the clip never shows the goal")
	assert_eq(int(last["s"][0]), 2, "the clip's final score is wrong")
	assert_gte(float(last["c"]), 63.0 * 60.0, "the clip clock is before the goal's minute")
	var scored := 0
	for frame in frames:
		if int(frame["g"]) == 1:
			scored += 1
	assert_gt(scored, 0, "no frame shows the ball in the net")
	assert_lt(scored, frames.size(), "the whole clip was a goal")

func test_the_ball_travels_into_the_net() -> void:
	var clip := GoalHighlight.build(_goal(), _sides(), 5)
	var frames: Array = clip["frames"]
	var start := GoalHighlight.ball_at(frames[0])
	var end := GoalHighlight.ball_at(frames[frames.size() - 1])
	assert_gt(start.x, 30.0, "the clip does not open with the build-up")
	assert_gt(end.x, 100.0, "the ball never reached the goal the home side attacks")
	assert_lt(end.y, 41.0, "the finish is off the target")
	assert_lt(end.y, 68.0 - 3.0, "the finish went wide")

func test_an_away_goal_is_mirrored() -> void:
	var goal := _goal(51, "MCI")
	goal["player_id"] = str(away_xi[9]["id"])
	goal["player_name"] = str(away_xi[9]["name"])
	var clip := GoalHighlight.build(goal, _sides(), 11)
	var frames: Array = clip["frames"]
	var end := GoalHighlight.ball_at(frames[frames.size() - 1])
	assert_lt(end.x, 5.0, "an away goal was played toward the home net")

# ------------------------------------------------------------- simulation ---

## #162: an AUTO clip is simulated, not posed. Bodies move at football speeds
## under acceleration, the ball obeys gravity, and the keeper dives late.
func test_the_auto_clip_is_a_physics_vignette() -> void:
	var clip := GoalHighlight.build(_goal(), _sides(), 21)
	var frames: Array = clip["frames"]
	var fastest := 0.0
	for i in range(1, frames.size()):
		var a: Dictionary = frames[i - 1]
		var b: Dictionary = frames[i]
		var span := maxf(float(b["t"]) - float(a["t"]), 0.001)
		for p in range(22):
			var step := GoalHighlight.player_at(a, p).distance_to(GoalHighlight.player_at(b, p))
			fastest = maxf(fastest, step / span)
	assert_lt(fastest, 11.5, "a body outran the pitch: the clip is posed, not simulated")
	# Gravity: the ball leaves the turf, peaks and comes back down into the net.
	var peak := 0.0
	var at := 0
	for i in range(frames.size()):
		var z := GoalHighlight.ball_at(frames[i]).z
		if z > peak:
			peak = z
			at = i
	assert_gt(peak, 0.4, "the shot never left the turf")
	assert_lt(peak, 4.0, "the shot ballooned over the stand")
	assert_lt(GoalHighlight.ball_at(frames[frames.size() - 1]).z, 0.4,
		"the ball never came back down")
	assert_gt(at, 0, "the ball was already airborne at kick-off")
	# The keeper is beaten by the dive, not by standing still.
	var keeper := 0
	for i in range(away_xi.size()):
		if str(away_xi[i].get("role", "")) == "GK":
			keeper = home_xi.size() + i
			break
	var from := GoalHighlight.player_at(frames[at], keeper)
	var to := GoalHighlight.player_at(frames[frames.size() - 1], keeper)
	assert_gt(from.distance_to(to), 0.3, "the keeper never dived")

## The seed decides the chance: two goals from one report do not share a shape.
func test_the_seed_shapes_the_chance() -> void:
	var a: Array = GoalHighlight.build(_goal(), _sides(), 31)["frames"]
	var b: Array = GoalHighlight.build(_goal(), _sides(), 77)["frames"]
	assert_eq(a.size(), b.size(), "two clips of one goal are different lengths")
	var apart := 0.0
	var path := 0.0
	for i in range(a.size()):
		apart = maxf(apart, GoalHighlight.ball_at(a[i]).distance_to(
			GoalHighlight.ball_at(b[i])))
		path = maxf(path, GoalHighlight.player_at(a[i], 0).distance_to(
			GoalHighlight.player_at(b[i], 0)))
	assert_gt(apart, 1.0, "two seeds played the same ball")
	assert_gt(path, 1.0, "two seeds put the same bodies in the same place")

## Every seeded chance is constrained to score: the ball crosses inside the
## frame and the report's own scoreline lands with it.
func test_every_seeded_chance_finishes_inside_the_frame() -> void:
	for seed in range(1, 9):
		var clip := GoalHighlight.build(_goal(34), _sides(), seed)
		var frames: Array = clip["frames"]
		var first := -1
		for i in range(frames.size()):
			if int(frames[i]["g"]) == 1:
				first = i
				break
		assert_gt(first, 0, "seed %d never scored" % seed)
		var ball := GoalHighlight.ball_at(frames[first])
		assert_gt(ball.x, 100.0, "seed %d missed the goal" % seed)
		assert_lt(absf(ball.y - 34.0), 3.66, "seed %d put the shot wide" % seed)
		assert_lt(ball.z, 2.44, "seed %d put the shot over the bar" % seed)
		assert_eq(int(frames[first]["s"][0]), 2, "seed %d lost its scoreline" % seed)
		assert_eq(int(frames[first]["s"][1]), 1, "seed %d lost its scoreline" % seed)

## The report's men play their parts: the recorded assist carries the ball and
## the recorded scorer strikes it.
func test_the_reported_men_play_their_parts() -> void:
	var goal := _goal(34)
	var clip := GoalHighlight.build(goal, _sides(), 42)
	var frames: Array = clip["frames"]
	var keys: Array = clip["keys"]
	var assist := keys.find(str(home_xi[6]["id"]))
	var scorer := keys.find(str(home_xi[9]["id"]))
	assert_gte(assist, 0, "the assist is not in the clip")
	assert_gte(scorer, 0, "the scorer is not in the clip")
	var carried := GoalHighlight.player_at(frames[0], assist)
	var at0 := GoalHighlight.ball_at(frames[0])
	assert_lt(carried.distance_to(Vector2(at0.x, at0.y)), 1.2,
		"the recorded assist never had the ball")
	# The strike is the frame where the ball's speed jumps.
	var strike := 0
	var jump := 0.0
	for i in range(1, frames.size()):
		var speed := GoalHighlight.ball_at(frames[i]).distance_to(GoalHighlight.ball_at(frames[i - 1]))
		var before := 0.0
		if i > 1:
			before = GoalHighlight.ball_at(frames[i - 1]).distance_to(
				GoalHighlight.ball_at(frames[i - 2]))
		if speed > before * 1.8 and speed - before > jump:
			jump = speed - before
			strike = i
	assert_gt(strike, 0, "the clip never struck the ball")
	var shooter := GoalHighlight.player_at(frames[strike - 1], scorer)
	var hit := GoalHighlight.ball_at(frames[strike - 1])
	assert_lt(shooter.distance_to(Vector2(hit.x, hit.y)), 3.5,
		"the recorded scorer was not the man striking the ball")

func test_every_frame_carries_all_twenty_two_players() -> void:
	var clip := GoalHighlight.build(_goal(), _sides(), 3)
	assert_eq((clip["keys"] as Array).size(), 22, "the clip lost a player")
	for frame in clip["frames"]:
		assert_eq((frame["p"] as Array).size(), 44, "a frame is missing a body")
	var frame: Dictionary = clip["frames"][30]
	var keeper := GoalHighlight.player_at(frame, 0)
	assert_gt(keeper.length(), 0.0, "the first player has no position")

func test_the_viewer_interpolates_between_frames() -> void:
	var clip := GoalHighlight.build(_goal(), _sides(), 8)
	var frames: Array = clip["frames"]
	var a: Dictionary = frames[10]
	var b: Dictionary = frames[11]
	var half := GoalHighlight.blend(a, b, 0.5)
	var pa := GoalHighlight.ball_at(a)
	var pb := GoalHighlight.ball_at(b)
	var ph := GoalHighlight.ball_at(half)
	assert_true(ph.z >= minf(pa.z, pb.z) - 0.01 and ph.z <= maxf(pa.z, pb.z) + 0.01,
		"the interpolated ball left the frame window")
	assert_eq((half["p"] as Array).size(), 44, "interpolation dropped a body")
	var start := GoalHighlight.blend(a, b, 0.0)
	assert_true(is_equal_approx(GoalHighlight.ball_at(start).x, pa.x), "alpha 0 is not frame a")
	var done := GoalHighlight.blend(a, b, 1.0)
	assert_true(is_equal_approx(GoalHighlight.ball_at(done).x, pb.x), "alpha 1 is not frame b")

# --------------------------------------------------------------- commentary ---

func test_an_away_goal_line_reads_from_the_scoring_side() -> void:
	var goal := _goal(51, "MCI")
	goal["score_after"] = [1, 2]
	goal["club_short"] = "MCI"
	goal["opp_short"] = "MUN"
	var line := GoalHighlight.commentary(goal, 12)
	assert_true(line.contains("MCI 2-1 MUN"), "the line read the scoreline from the home side")
	assert_true(line.contains("lead"), "the away side's lead was not named")

func test_the_line_names_the_report_scorer_and_score() -> void:
	var goal := _goal(34)
	var line := GoalHighlight.commentary(goal, 77)
	assert_true(line.contains(str(home_xi[9]["name"])), "the line does not name the scorer")
	assert_true(line.contains("MUN"), "the line does not name the scoring club")
	assert_true(line.contains("2-1") or line.contains("2–1"), "the line does not carry the score")
	assert_eq(line, GoalHighlight.commentary(goal, 77), "the line is not deterministic")

# ------------------------------------------------------------------- store ---

class FakeActors:
	var ball_trail: Array = []

## Just enough of the play scene for the ring director: an engine, a mode and
## the flags it drives.
class FakeHost:
	var engine = null
	var mode := "full"
	var actors = FakeActors.new()
	var batch_abort := false
	var in_highlight := false
	var fast_mode := true
	var highlight_until := 0.0
	var replay_banner := 0.0
	var accumulator := 0.0

func _ring_host(seed: int) -> Array:
	var engine = MatchEngine.new(seed, "MUN", "MCI")
	var host := FakeHost.new()
	host.engine = engine
	var director := HighlightDirector.new(host)
	director.restart()
	for i in range(150):
		engine.tick()
		director.sample()
	return [host, director, engine]

func test_a_live_goal_is_cut_from_the_ring() -> void:
	var ring := _ring_host(202)
	var director: HighlightDirector = ring[1]
	var engine = ring[2]
	assert_gte(director.history.size(), 4, "the ring never filled")
	var fx := str((season.plan()[0] as Dictionary)["id"])
	season.start_watch(fx)
	var before := season.captured.size()
	director.capture({"clock": engine.clock, "minute": 3, "player_id": -1, "team": 0, "text": "GOAL!"})
	assert_eq(season.captured.size(), before + 1, "the ring did not hand a clip to the season")
	var pack: Dictionary = season.captured[season.captured.size() - 1]
	assert_eq(str(pack["fixture_id"]), fx, "the capture went to another fixture")
	assert_eq(str(pack["source"]), "watch", "the capture is not marked live")
	assert_gte((pack["frames"] as Array).size(), 4, "the capture is too short to play")
	assert_false(GoalHighlight.unpack(GoalHighlight.pack(pack)).is_empty(), "the capture will not decode")

func test_a_replayed_goal_is_not_captured_twice() -> void:
	var ring := _ring_host(505)
	var host: FakeHost = ring[0]
	var director: HighlightDirector = ring[1]
	var engine = ring[2]
	host.mode = "highlights"
	var fx := str((season.plan()[0] as Dictionary)["id"])
	season.start_watch(fx)
	var before := season.captured.size()
	var event := {"type": "goal", "clock": float(engine.clock), "minute": 2,
		"player_id": -1, "team": 0, "text": "GOAL!"}
	director.on_event(event)
	assert_eq(season.captured.size(), before + 1, "the goal was not captured")
	director.on_event(event)
	assert_eq(season.captured.size(), before + 1, "a rewound goal was captured twice")

func test_a_capture_needs_a_watch_and_a_ring() -> void:
	var fx := str((season.plan()[0] as Dictionary)["id"])
	season.watching_fixture = ""
	var before := season.captured.size()
	season.capture_goal({"source": "watch", "frames": []})
	assert_eq(season.captured.size(), before, "a clip was held with no watched fixture")
	season.start_watch(fx)
	var ring := _ring_host(303)
	var director: HighlightDirector = ring[1]
	director.history.clear()
	var held := season.captured.size()
	director.capture({"clock": 12.0, "minute": 1, "player_id": -1, "team": 0, "text": "GOAL!"})
	assert_eq(season.captured.size(), held, "a clip was cut from an empty ring")

func test_a_shot_rewinds_the_live_picture_once() -> void:
	var ring := _ring_host(404)
	var host: FakeHost = ring[0]
	var director: HighlightDirector = ring[1]
	var engine = ring[2]
	host.mode = "highlights"
	var trigger := float(engine.clock)
	director.on_event({"type": "shot", "clock": trigger, "player_id": -1})
	assert_true(host.in_highlight, "the shot did not open a replay")
	assert_true(host.batch_abort, "the rewound batch was not abandoned")
	assert_false(host.fast_mode, "the replay did not hold the fast-forward")
	assert_gt(host.highlight_until, float(engine.clock), "the replay window is empty")
	host.in_highlight = false
	director.on_event({"type": "shot", "clock": trigger, "player_id": -1})
	assert_false(host.in_highlight, "the same shot was replayed twice")

func test_a_watch_goal_keeps_the_captured_clip() -> void:
	# A watched fixture the engine has just finished: its goal rows are written,
	# one goal has a live capture and the other does not.
	var fx := str((season.record.fixtures.all(2)[0] as Dictionary)["id"])
	var row := season.record.fixtures.one(fx)
	var home := str(row["home_club_id"])
	var away := str(row["away_club_id"])
	var home_id := str(StrongestXI.pick(TeamData.get_team(home))[9]["id"])
	var away_id := str(StrongestXI.pick(TeamData.get_team(away))[9]["id"])
	season.record.report.add_events([
		{"fixture_id": fx, "minute": 10, "kind": "goal", "player_id": home_id, "club_id": home, "detail": "A"},
		{"fixture_id": fx, "minute": 55, "kind": "goal", "player_id": away_id, "club_id": away, "detail": "B"},
	])
	var snaps: Array = []
	var engine = MatchEngine.new(909, home, away)
	for i in range(24):
		engine.tick()
		if i % 4 == 0:
			snaps.append(engine.to_dict())
	var captured := GoalHighlight.from_snapshots(snaps, {
		"seed": 909, "fixture_id": fx, "home": home, "away": away, "minute": 10,
		"club_id": home, "scorer_id": home_id, "scorer_name": "Live Scorer",
		"assist_id": "", "assist_name": "", "commentary": "", "score_after": [1, 0],
	})
	assert_eq(str(captured.get("commentary", "")), "", "the capture invented a line")
	LeagueHighlights.store_watch(season.record, SEED, fx, [captured], home, away)
	var rows := season.record.clips.list(fx)
	assert_eq(rows.size(), 2, "a watched goal has no stored clip")
	assert_eq(str(rows[0]["source"]), "watch", "the captured goal is not marked live")
	assert_true(int(rows[0]["match_event_id"]) > 0, "the clip is not linked to its goal row")
	assert_true(str(rows[0]["commentary"]) != "", "the capture was stored without a line")
	assert_eq(str(rows[1]["source"]), "auto", "a goal with no capture was not filled in")
	var live := season.record.clips.pack(fx, 0)
	assert_eq((live["frames"] as Array).size(), (captured["frames"] as Array).size(),
		"the captured clip lost frames on the way in")
	assert_eq(int(live["score"][0]), 1, "the captured clip lost its scoreline")
	season.record.clips.clear(fx)
	assert_true(season.record.clips.list(fx).is_empty(), "clearing a fixture left clip rows")

## #171: a stored penalty recipe is drawn as a spot kick, and the line the
## settling pass wrote survives beside it. The tag is part of the ledger, so a
## reopened report still plays the right picture.
func test_a_stored_penalty_clip_draws_as_a_spot_kick() -> void:
	var fx := str((season.plan()[0] as Dictionary)["id"])
	var row := season.record.fixtures.one(fx)
	var home := str(row["home_club_id"])
	var away := str(row["away_club_id"])
	var scorer: Dictionary = StrongestXI.pick(TeamData.get_team(home))[9]
	season.record.clips.clear(fx)
	LeagueHighlights.store_auto(season.record, SEED, fx, [{
		"fixture_id": fx, "minute": 20, "kind": "goal", "club_id": home,
		"player_id": str(scorer["id"]), "player_name": str(scorer["name"]),
		"detail": str(scorer["name"]), "penalty": true,
	}], home, away)
	var stored := season.record.clips.list(fx)
	assert_eq(stored.size(), 1, "the penalty goal stored no clip")
	assert_eq(int(stored[0].get("penalty", 0)), 1, "the stored clip lost the tag")
	var pack := season.record.clips.pack(fx, 0)
	assert_false(pack.is_empty(), "the stored penalty clip does not decode")
	var line := str(pack.get("commentary", "")).to_upper()
	assert_true(line.find("PENALTY") >= 0 or line.find("SPOT") >= 0 or line.find("TWELVE") >= 0,
		"the stored penalty clip was narrated as open play: %s" % line)
	assert_eq(str(pack.get("scorer_id", "")), str(scorer["id"]), "the clip lost its taker")
	assert_eq(int(pack.get("minute", 0)), 20, "the clip lost its minute")
	season.record.clips.clear(fx)

func test_a_settled_matchday_stores_a_clip_for_every_goal() -> void:
	var result := season.advance()
	var reports: Array = result["played"]
	assert_gt(reports.size(), 0, "the matchday did not settle")
	var goals := 0
	var clips := 0
	for report in reports:
		var rows: Array = report.get("highlights", [])
		var reported := 0
		for e in report["events"]:
			if str(e.get("kind", "")) == "goal":
				reported += 1
		goals += reported
		clips += rows.size()
		assert_eq(rows.size(), reported, "a goal has no stored clip")
		for row in rows:
			assert_true(str(row.get("commentary", "")) != "", "a clip has no line")
			var pack := season.record.clips.pack(str(row["fixture_id"]), int(row["goal_index"]))
			assert_false(pack.is_empty(), "a stored clip does not decode")
			assert_eq(str(pack["scorer_id"]), str(row["scorer_id"]), "the clip's scorer drifted")
			assert_eq(int(pack["minute"]), int(row["minute"]), "the clip's minute drifted")
	assert_gt(goals, 0, "no goals were reported at all")
	assert_eq(clips, goals, "the clips do not cover the goals")

## A settled auto goal keeps a recipe, not a picture: the first report to ask
## draws the pack from the save itself. It must be the clip the settling pass
## would have drawn eagerly — same seed, same eleven, same scoreline.
func test_a_settled_clip_is_drawn_from_its_recipe() -> void:
	var fixture := ""
	var row := {}
	for candidate in season.record.fixtures.all():
		for r in season.record.clips.list(str(candidate["id"])):
			if str(r.get("source", "")) == "auto":
				fixture = str(candidate["id"])
				row = r
				break
		if not row.is_empty():
			break
	assert_false(row.is_empty(), "no settled clip to draw")
	var index := int(row["goal_index"])
	var fx := season.record.fixtures.one(fixture)
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var club := str(row["club_id"])
	# The scoreline at that goal, from the report's own goal rows.
	var score := [0, 0]
	var goals := 0
	for e in season.report(fixture)["events"]:
		if str(e.get("kind", "")) != "goal":
			continue
		score[0 if str(e["club_id"]) == home else 1] += 1
		if goals >= index:
			break
		goals += 1
	var fields := {
		"fixture_id": fixture, "goal_index": index, "minute": int(row["minute"]),
		"home": home, "away": away, "club_id": club,
		"player_id": str(row["scorer_id"]), "player_name": str(row["scorer_name"]),
		"assist_id": str(row["assist_id"]), "assist_name": str(row["assist_name"]),
		"club_short": LeagueHighlights.short_name(club),
		"opp_short": LeagueHighlights.short_name(away if club == home else home),
		"score_after": score, "source": "auto", "commentary": str(row["commentary"]),
		"penalty": int(row.get("penalty", 0)) == 1,
	}
	var sides := {"home": StrongestXI.pick(TeamData.get_team(home)),
		"away": StrongestXI.pick(TeamData.get_team(away))}
	var eager := GoalHighlight.pack(
		GoalHighlight.build(fields, sides, GoalHighlight.seed_for(SEED, fixture, index)))
	var stored: PackedByteArray = PLDatabase.row(
		"SELECT bytes FROM goal_highlight WHERE fixture_id = ? AND goal_index = ?;",
		[fixture, index]).get("bytes", PackedByteArray())
	assert_false(stored.is_empty(), "the report did not draw the clip")
	assert_true(stored == eager, "the drawn clip is not the one the recipe describes")
	# The draw is cached in the row: a second report reads the same bytes back.
	assert_true(PLDatabase.row(
		"SELECT bytes FROM goal_highlight WHERE fixture_id = ? AND goal_index = ?;",
		[fixture, index]).get("bytes", PackedByteArray()) == eager,
		"the recipe drew two different clips")
	# A clip that is not there, and a recipe too bare to draw, read as empty
	# rather than throw: a report must never crash on a missing picture.
	season.record.clips.add([{"fixture_id": "gw99-NONE-NONE", "goal_index": 0,
		"club_id": "NONE", "minute": 1, "source": "auto"}])
	assert_true(season.record.clips.pack("gw99-NONE-NONE", 0).is_empty(),
		"a recipe without its clubs drew a clip")
	assert_true(season.record.clips.pack("gw99-NONE-NONE", 7).is_empty(),
		"a missing clip decoded to a picture")

func test_a_clip_records_the_assist_it_was_built_with() -> void:
	var rows := season.record.clips.list(str((season.record.fixtures.all()[0] as Dictionary)["id"]))
	for row in rows:
		var name := str(row.get("assist_name", ""))
		var pack := season.record.clips.pack(str(row["fixture_id"]), int(row["goal_index"]))
		assert_eq(str(pack.get("assist", "")), name, "the clip and its row disagree on the assist")
		assert_eq(str(pack.get("scorer", "")), str(row.get("scorer_name", "")),
			"the clip and its row disagree on the scorer")

func test_reopening_the_save_replays_the_same_clip() -> void:
	var fixture := ""
	var index := 0
	var before := PackedByteArray()
	for fx in season.record.fixtures.all():
		var rows := season.record.clips.list(str(fx["id"]))
		if rows.is_empty():
			continue
		fixture = str(fx["id"])
		index = int((rows[0] as Dictionary)["goal_index"])
		before = GoalHighlight.pack(season.record.clips.pack(fixture, index))
		break
	assert_false(before.is_empty(), "no clip was stored to reopen")
	var slug := season.save.slug
	season.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the save did not reopen")
	var after := GoalHighlight.pack(season.goal_clip(fixture, index))
	assert_true(before == after, "reopening changed the stored clip")
	var pack := season.goal_clip(fixture, index)
	assert_true(str(pack.get("commentary", "")) != "", "the reopened clip lost its line")

func test_a_watched_fixture_keeps_the_captured_clip() -> void:
	var fx := str((season.plan()[0] as Dictionary)["id"])
	var start := season.start_watch(fx)
	assert_false(start.is_empty(), "the watch did not start")
	var snaps: Array = []
	var engine = MatchEngine.new(101, "MUN", "MCI")
	for i in range(40):
		engine.tick()
		if i % 4 == 0:
			snaps.append(engine.to_dict())
	var captured := GoalHighlight.from_snapshots(snaps, {
		"seed": 101, "fixture_id": fx, "home": "MUN", "away": "MCI",
		"minute": 12, "club_id": "MUN", "scorer_id": str(home_xi[9]["id"]),
		"scorer_name": str(home_xi[9]["name"]), "assist_name": "", "assist_id": "",
		"commentary": "Captured live!", "score_after": [1, 0],
	})
	assert_false(captured.is_empty(), "the live capture produced no pack")
	assert_eq(str(captured["source"]), "watch", "the capture is not marked live")
	assert_eq((captured["frames"] as Array).size(), snaps.size(), "frames were dropped")
	season.capture_goal(captured)
	assert_eq(season.captured.size(), 1, "the season did not hold the capture")

func test_the_schema_migrates_an_older_save() -> void:
	var save := LeagueSave.create("Migrating", LeagueRules.defaults())
	assert_not_null(save, "the save was not created")
	PLDatabase.execute("DROP TABLE goal_highlight;")
	var found := PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'goal_highlight';")
	assert_true(found.is_empty(), "the table was not dropped")
	var reopened := LeagueSave.open(save.slug)
	assert_not_null(reopened, "the old save did not reopen")
	var back := PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'goal_highlight';")
	assert_false(back.is_empty(), "opening an old save did not add the clip table")
	LeagueSave.open(season.save.slug)
