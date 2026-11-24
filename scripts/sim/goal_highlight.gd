class_name GoalHighlight
extends RefCounted

## One goal's broadcast clip: a short playback-only pack built when a fixture is
## settled, stored in the league save, and played from the match report.
##
## The pack is not an engine snapshot. A match report only ever needs to *show*
## a goal, so each frame carries the ball and the twenty-two players' ground
## positions, the clock, the score and whether the goal has landed — no
## attributes, stats, tactics or manager state. That keeps a clip a few
## kilobytes against the megabytes a full snapshot ring would cost for a season.
##
## Frames are generated, not simulated: a goal already has its scorer, assist
## and minute on the report, so the clip is scripted to end with exactly that
## scorer (and the recorded assist playing the final ball). Nothing here ticks
## the match engine, so a whole matchday of clips costs milliseconds instead of
## minutes. Every draw runs off a seed folded from the save, the fixture and the
## goal's index, so the same save always replays the same clip.
##
## Geometry is world space with the home side attacking +x, exactly like the
## engine, so the viewer can bind the frames straight onto a real squad.

const CODEC := "goal-highlight"
const VERSION := 1
## Playback poses per match second. The viewer interpolates between them.
const FPS := 12
## Clip length in match time: build-up, finish, celebration.
const LENGTH := 10.0
## Match seconds of build-up shown before the clip's goal minute.
const PRE_ROLL := 9.0
const L := 105.0
const W := 68.0
## Seconds into the clip at which the ball crosses the line.
const GOAL_AT := 6.2

# ------------------------------------------------------------------ seed ---

## Deterministic clip seed: the save's own seed, the fixture and the goal's
## ordinal inside that fixture. Reopening a save and re-settling a fixture
## therefore reproduces the same clip and the same commentary line.
static func seed_for(save_seed: int, fixture_id: String, goal_index: int) -> int:
	var h := 0
	for i in range(fixture_id.length()):
		h = int((h * 31 + fixture_id.unicode_at(i)) % 2147483647)
	return int((save_seed % 2147483647) * 7 + h * 13 + goal_index * 977 + 1009) % 2147483647

# --------------------------------------------------------------- commentary ---

## The one line a report shows for a goal. It reuses the broadcast voice but is
## drawn from a fresh, seeded RNG so it never disturbs the season's own stream.
static func commentary(goal: Dictionary, seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var short_a := str(goal.get("club_short", "HOM"))
	var short_b := str(goal.get("opp_short", "AWY"))
	var score: Array = goal.get("score_after", [0, 0])
	var before_for := maxi(int(score[0]) - 1, 0)
	var before_against := int(score[1])
	if str(goal.get("club_id", "")) != str(goal.get("home", "")):
		before_for = maxi(int(score[1]) - 1, 0)
		before_against = int(score[0])
		short_a = str(goal.get("opp_short", "AWY"))
		short_b = str(goal.get("club_short", "HOM"))
	return Commentary.goal(rng, str(goal.get("player_name", "Unknown")),
		str(goal.get("assist_name", "")), false, short_a, short_b,
		before_for, before_against, int(goal.get("minute", 0)))

# ------------------------------------------------------------------ build ---

## Playback pack for one goal. `sides` maps "home"/"away" to the XI that played,
## in the order the engine fields them, so the viewer can bind frames by key.
static func build(goal: Dictionary, sides: Dictionary, seed: int) -> Dictionary:
	var home := str(goal.get("home", ""))
	var away := str(goal.get("away", ""))
	var club := str(goal.get("club_id", home))
	var attack := 1.0 if club == home else -1.0
	var minute := int(goal.get("minute", 1))
	var home_xi: Array = sides.get("home", [])
	var away_xi: Array = sides.get("away", [])
	var keys: Array = []
	for p in home_xi:
		keys.append(str(p.get("id", "")))
	for p in away_xi:
		keys.append(str(p.get("id", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var score: Array = goal.get("score_after", [0, 0])
	var frames: Array = []
	var count := int(LENGTH * FPS)
	for i in range(count + 1):
		var t := float(i) / float(FPS)
		frames.append(_frame(float(minute) * 60.0 - PRE_ROLL + t, t, goal, sides, attack, keys, rng))
	return {
		"codec": CODEC, "version": VERSION, "seed": seed,
		"fixture_id": str(goal.get("fixture_id", "")), "home": home, "away": away,
		"goal_index": int(goal.get("goal_index", 0)), "minute": minute,
		"club_id": club, "scorer": str(goal.get("player_name", "")),
		"scorer_id": str(goal.get("player_id", "")),
		"assist": str(goal.get("assist_name", "")),
		"assist_id": str(goal.get("assist_id", "")),
		"commentary": str(goal.get("commentary", "")),
		"source": str(goal.get("source", "auto")),
		"score": [int(score[0]), int(score[1])],
		"keys": keys, "frames": frames,
	}

## One frame: clock, score, ball and the flat player list in key order.
static func _frame(clock: float, t: float, goal: Dictionary, sides: Dictionary,
		attack: float, keys: Array, rng: RandomNumberGenerator) -> Dictionary:
	var score: Array = goal.get("score_after", [0, 0])
	var scoring_home := str(goal.get("club_id", "")) == str(goal.get("home", ""))
	var before := [int(score[0]), int(score[1])]
	if scoring_home:
		before[0] = maxi(before[0] - 1, 0)
	else:
		before[1] = maxi(before[1] - 1, 0)
	var scored := t >= GOAL_AT
	var pose := _pose(t, goal, sides, attack)
	var flat: Array = []
	for i in range(keys.size()):
		var p: Vector2 = pose.get(str(keys[i]), Vector2.ZERO)
		flat.append(snappedf(p.x, 0.01))
		flat.append(snappedf(p.y, 0.01))
	# The pack is generated, so a hair of seeded wobble keeps two goals that
	# share a shape from looking like the same animation twice.
	var wobble := (rng.randf() - 0.5) * 0.06
	return {
		"t": snappedf(t, 0.01), "c": snappedf(clock, 0.01),
		"s": [int(score[0]), int(score[1])] if scored else before,
		"g": 1 if scored else 0,
		"b": [snappedf(pose["ball_x"], 0.01), snappedf(pose["ball_y"], 0.01),
			snappedf(pose["z"] + wobble, 0.01)],
		"p": flat,
	}

## Ball and body positions for one instant. `attack` is +1 when the scoring
## club is the home side; every point is built in the attacking frame and then
## mirrored into world space, so the away side's clips run right to left.
static func _pose(t: float, goal: Dictionary, sides: Dictionary, attack: float) -> Dictionary:
	var home_xi: Array = sides.get("home", [])
	var away_xi: Array = sides.get("away", [])
	var club := str(goal.get("club_id", ""))
	var scoring_home := str(goal.get("home", "")) == club
	var attack_xi: Array = home_xi if scoring_home else away_xi
	var defend_xi: Array = away_xi if scoring_home else home_xi
	var assist_id := str(goal.get("assist_id", ""))
	var scorer_id := str(goal.get("player_id", ""))
	var carrier := _carrier_index(attack_xi, assist_id, scorer_id)
	var shooter := _index_of(attack_xi, scorer_id)
	var pass_from := Vector2(56.0, 30.0)
	var pass_to := Vector2(78.0, 40.0)
	var net := Vector2(L - 0.4, W * 0.5 + 2.2)
	var ball := _ball_path(t, pass_from, pass_to, net)
	var push := _attack_push(t)
	var pose := {"ball_x": _world_x(ball.x, attack), "ball_y": ball.y, "z": ball.z}
	# The finishing side: the carrier meets the ball, the scorer strikes it.
	for i in range(attack_xi.size()):
		var id := str(attack_xi[i].get("id", ""))
		var role := str(attack_xi[i].get("role", ""))
		var base := _slot_point(role, i, attack_xi.size())
		var target := base + Vector2(push * _push_share(role), 0.0)
		if i == carrier:
			target = pass_from + Vector2(2.0, 0.8)
		if i == shooter:
			target = pass_to + Vector2(2.2, -1.4)
		var pos := base.lerp(target, smoothstep(0.0, GOAL_AT, t))
		if t > GOAL_AT and i != shooter:
			# Everyone piles onto the scorer.
			pos = pos.lerp(pass_to + Vector2(3.6, 1.8), clampf((t - GOAL_AT) / 2.6, 0.0, 1.0))
		pose[id] = _world(pos, attack)
	# The defending side drops with the ball; the keeper dives too late. Their
	# shape is mirrored inside the attacking frame, so their own goal is the one
	# being attacked and their keeper stands in it.
	for i in range(defend_xi.size()):
		var id := str(defend_xi[i].get("id", ""))
		var role := str(defend_xi[i].get("role", ""))
		var slot := _slot_point(role, i, defend_xi.size())
		var base := Vector2(L - slot.x, slot.y)
		var target := base + Vector2(push * 0.4 * _push_share(role), 0.0)
		if role == "GK":
			target = Vector2(L - 3.0, W * 0.5 + _dive(t) * 1.7)
		var pos := base.lerp(target, smoothstep(0.0, GOAL_AT, t))
		pose[id] = _world(pos, attack)
	return pose

## The ball's scripted journey: carried, laid off, struck, then resting in the
## net. `z` gives the height, so the shot rises over the keeper.
static func _ball_path(t: float, from: Vector2, to: Vector2, net: Vector2) -> Vector3:
	if t < 2.4:
		return Vector3(from.x, from.y, 0.11)
	if t < 4.0:
		var k := smoothstep(2.4, 4.0, t)
		return Vector3(lerpf(from.x, to.x, k), lerpf(from.y, to.y, k), 0.11 + sin(k * PI) * 0.55)
	if t < 4.6:
		return Vector3(to.x, to.y, 0.11)
	if t < GOAL_AT:
		var k := smoothstep(4.6, GOAL_AT, t)
		return Vector3(lerpf(to.x, net.x, k), lerpf(to.y, net.y, k), 0.11 + sin(k * PI * 0.85) * 1.1)
	return Vector3(net.x, net.y, 0.12)

## How far up the pitch the shape has pushed at this instant.
static func _attack_push(t: float) -> float:
	if t < 2.4:
		return smoothstep(0.0, 2.4, t) * 6.0
	if t < GOAL_AT:
		return 6.0 + smoothstep(2.4, GOAL_AT, t) * 12.0
	return 18.0

## Keepers are beaten by the finish: central, then a late dive.
static func _dive(t: float) -> float:
	if t < 4.6:
		return 0.0
	return smoothstep(4.6, GOAL_AT, t) * 0.9

## Home attacks +x, the away side -x, exactly like the engine's direction.
static func _world_x(x_attacking: float, attack: float) -> float:
	return x_attacking if attack > 0.0 else L - x_attacking

static func _world(p: Vector2, attack: float) -> Vector2:
	return Vector2(_world_x(p.x, attack), p.y)

## Formation slot in the attacking frame: keepers deep, the back line behind
## the ball, the front line in the box.
static func _slot_point(role: String, index: int, total: int) -> Vector2:
	var line := 3
	if role == "GK":
		line = 0
	elif role in ["RB", "LB", "RCB", "LCB", "CB"]:
		line = 1
	elif role in ["RDM", "LDM", "CDM", "CM", "LM", "RM"]:
		line = 2
	var xs: PackedFloat32Array = [4.0, 21.0, 38.0, 56.0]
	var spread: PackedFloat32Array = [6.0, 44.0, 46.0, 28.0]
	var per := maxi(total - 1, 1)
	var y := W * 0.5 + (float(index) / float(per) - 0.5) * float(spread[line])
	return Vector2(float(xs[line]), clampf(y, 3.0, W - 3.0))

## The XI player carrying the ball into the chance: the recorded assist when
## there is one, else the scorer himself so a solo goal still has a carrier.
static func _carrier_index(xi: Array, assist_id: String, scorer_id: String) -> int:
	if assist_id != "":
		var found := _index_of(xi, assist_id)
		if found >= 0:
			return found
	return maxi(_index_of(xi, scorer_id), 0)

static func _index_of(xi: Array, player_id: String) -> int:
	if player_id == "":
		return -1
	for i in range(xi.size()):
		if str(xi[i].get("id", "")) == player_id:
			return i
	return -1

static func _push_share(role: String) -> float:
	if role == "GK":
		return 0.0
	if role in ["ST", "CAM", "RW", "LW", "RM", "LM"]:
		return 1.0
	if role in ["RDM", "LDM", "CDM", "CM"]:
		return 0.6
	return 0.35

# ---------------------------------------------------------------- capture ---

## A pack built from the live match's own snapshot ring, so a watched goal
## replays the picture that actually happened. `snaps` are engine snapshots
## (`MatchEngine.to_dict()`); only positions, clock and score are kept.
static func from_snapshots(snaps: Array, meta: Dictionary) -> Dictionary:
	if snaps.is_empty():
		return {}
	var keys: Array = []
	for pd in snaps[0].get("players", []):
		keys.append(str(pd.get("key", "")))
	var start := float(snaps[0].get("clock", 0.0))
	var before: Array = snaps[0].get("score", [0, 0])
	var frames: Array = []
	for snap in snaps:
		var flat: Array = []
		for pd in snap.get("players", []):
			var pos: Vector2 = pd.get("pos", Vector2.ZERO)
			flat.append(snappedf(pos.x, 0.01))
			flat.append(snappedf(pos.y, 0.01))
		var ball: Dictionary = snap.get("ball", {})
		var bp: Vector2 = ball.get("pos", Vector2.ZERO)
		var score: Array = snap.get("score", before)
		frames.append({
			"t": snappedf(float(snap.get("clock", 0.0)) - start, 0.01),
			"c": snappedf(float(snap.get("clock", 0.0)), 0.01),
			"s": [int(score[0]), int(score[1])],
			"g": 1 if int(score[0]) + int(score[1]) > int(before[0]) + int(before[1]) else 0,
			"b": [snappedf(bp.x, 0.01), snappedf(bp.y, 0.01), snappedf(float(ball.get("z", 0.0)), 0.01)],
			"p": flat,
		})
	var score_after: Array = meta.get("score_after", snaps[snaps.size() - 1].get("score", before))
	return {
		"codec": CODEC, "version": VERSION, "seed": int(meta.get("seed", 0)),
		"fixture_id": str(meta.get("fixture_id", "")),
		"home": str(meta.get("home", "")), "away": str(meta.get("away", "")),
		"goal_index": int(meta.get("goal_index", 0)), "minute": int(meta.get("minute", 0)),
		"club_id": str(meta.get("club_id", "")),
		"scorer": str(meta.get("scorer_name", "")), "scorer_id": str(meta.get("scorer_id", "")),
		"assist": str(meta.get("assist_name", "")), "assist_id": str(meta.get("assist_id", "")),
		"commentary": str(meta.get("commentary", "")), "source": "watch",
		"score": [int(score_after[0]), int(score_after[1])],
		"keys": keys, "frames": frames,
	}

# ------------------------------------------------------------------ codec ---
## Wire format: a four-byte little-endian length, then the gzipped JSON pack.
## The length rides in the blob so the row is readable without the schema.
static func pack(clip: Dictionary) -> PackedByteArray:
	var raw := JSON.stringify(clip).to_utf8_buffer()
	var body := raw.compress(FileAccess.COMPRESSION_GZIP)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(body)
	return out

## Decode a stored pack. Empty on a codec or version the viewer does not know,
## so an old save offers no ▶ instead of playing a broken clip.
static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 5:
		return {}
	var size := bytes.decode_u32(0)
	var raw := (bytes.slice(4)).decompress(size, FileAccess.COMPRESSION_GZIP)
	if raw.size() != size:
		return {}
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary:
		return {}
	if int(parsed.get("version", 0)) != VERSION or str(parsed.get("codec", "")) != CODEC:
		return {}
	if not parsed.get("frames", []) is Array or (parsed["frames"] as Array).is_empty():
		return {}
	return parsed

## Position of one player in a frame, in world space, honouring the frame's
## flat [x0, y0, x1, y1, ...] layout.
static func player_at(frame: Dictionary, index: int) -> Vector2:
	var flat: Array = frame.get("p", [])
	var at := index * 2
	if at + 1 >= flat.size():
		return Vector2.ZERO
	return Vector2(float(flat[at]), float(flat[at + 1]))

## Ball position of a frame in world space.
static func ball_at(frame: Dictionary) -> Vector3:
	var b: Array = frame.get("b", [0.0, 0.0, 0.0])
	if b.size() < 3:
		return Vector3.ZERO
	return Vector3(float(b[0]), float(b[1]), float(b[2]))

## Interpolated pose between two frames: the viewer plays at screen rate while
## the clip stores twelve poses a second.
static func blend(a: Dictionary, b: Dictionary, alpha: float) -> Dictionary:
	var k := clampf(alpha, 0.0, 1.0)
	var ba := ball_at(a)
	var bb := ball_at(b)
	var out: Array = []
	var pa: Array = a.get("p", [])
	var pb: Array = b.get("p", [])
	for i in range(mini(pa.size(), pb.size())):
		out.append(lerpf(float(pa[i]), float(pb[i]), k))
	return {
		"b": [lerpf(ba.x, bb.x, k), lerpf(ba.y, bb.y, k), lerpf(ba.z, bb.z, k)],
		"p": out,
	}
