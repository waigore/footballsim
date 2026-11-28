class_name GoalHighlight
extends RefCounted


const CODEC := "goal-highlight"
const VERSION := 1

const FPS := 12


static func seed_for(save_seed: int, fixture_id: String, goal_index: int) -> int:
	var h := 0
	for i in range(fixture_id.length()):
		h = int((h * 31 + fixture_id.unicode_at(i)) % 2147483647)
	return int((save_seed % 2147483647) * 7 + h * 13 + goal_index * 977 + 1009) % 2147483647


static func commentary(goal: Dictionary, seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var score: Array = goal.get("score_after", [0, 0])
	var scoring_home := str(goal.get("club_id", "")) == str(goal.get("home", ""))
	var goals_for := int(score[0]) if scoring_home else int(score[1])
	var goals_against := int(score[1]) if scoring_home else int(score[0])
	return Commentary.goal(rng, str(goal.get("player_name", "Unknown")),
		str(goal.get("assist_name", "")), false, str(goal.get("club_short", "")),
		str(goal.get("opp_short", "")), maxi(goals_for - 1, 0), goals_against,
		int(goal.get("minute", 0)), bool(goal.get("penalty", false)))


static func build(goal: Dictionary, sides: Dictionary, seed: int) -> Dictionary:
	var home := str(goal.get("home", ""))
	var away := str(goal.get("away", ""))
	var club := str(goal.get("club_id", home))
	var score: Array = goal.get("score_after", [0, 0])
	var shot := GoalVignette.build(goal, sides, seed)
	return {
		"codec": CODEC, "version": VERSION, "seed": seed,
		"fixture_id": str(goal.get("fixture_id", "")), "home": home, "away": away,
		"goal_index": int(goal.get("goal_index", 0)), "minute": int(goal.get("minute", 1)),
		"club_id": club, "scorer": str(goal.get("player_name", "")),
		"scorer_id": str(goal.get("player_id", "")),
		"assist": str(goal.get("assist_name", "")),
		"assist_id": str(goal.get("assist_id", "")),
		"commentary": str(goal.get("commentary", "")),
		"source": str(goal.get("source", "auto")),
		"score": [int(score[0]), int(score[1])],
		"keys": shot.get("keys", []), "frames": shot.get("frames", []),
	}


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


static func pack(clip: Dictionary) -> PackedByteArray:
	var raw := JSON.stringify(clip).to_utf8_buffer()
	var body := raw.compress(FileAccess.COMPRESSION_GZIP)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(body)
	return out


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


static func player_at(frame: Dictionary, index: int) -> Vector2:
	var flat: Array = frame.get("p", [])
	var at := index * 2
	if at + 1 >= flat.size():
		return Vector2.ZERO
	return Vector2(float(flat[at]), float(flat[at + 1]))


static func ball_at(frame: Dictionary) -> Vector3:
	var b: Array = frame.get("b", [0.0, 0.0, 0.0])
	if b.size() < 3:
		return Vector3.ZERO
	return Vector3(float(b[0]), float(b[1]), float(b[2]))


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
