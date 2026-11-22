extends "res://scripts/sim/match_engine_core.gd"

## Broadcast-facing helpers: event log, clock formatting, possession and summaries.

## Implemented by the restarts layer. Declared here so the base layers can
## reach it virtually (a base script cannot call a method only a subclass has).
func _start_restart(kind: String, team: int, pos: Vector2, delay: float = -1.0) -> void:
	pass

## Implemented by the restarts layer (tick calls it).
func _update_restart(dt: float) -> void:
	pass

## Implemented by the rules layer (actions call it when a flagged man touches it).
func _offside(p) -> void:
	pass

func _vlog(msg: String) -> void:
	if verbose:
		print("[%6.2f] %s" % [clock, msg])

func _nearest_teammate_to(pos: Vector2, t: int, include_gk: bool = false, exclude_id: int = -1):
	var best = null
	var bd = 1e9
	for p in players:
		if p.team != t or p.sent_off or p.id == exclude_id:
			continue
		if p.is_gk and not include_gk:
			continue
		var d = p.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best

func elapsed_minutes() -> float:
	return clock / 60.0

func display_clock() -> String:
	if half == 1:
		if clock <= 2700.0:
			return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]
		return "45:00 +%02d:%02d" % [int(clock - 2700.0) / 60, int(clock - 2700.0) % 60]
	if clock <= 5400.0:
		return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]
	return "90:00 +%02d:%02d" % [int(clock - 5400.0) / 60, int(clock - 5400.0) % 60]

func minute_of(t: float) -> int:
	return clampi(int(ceil(t / 60.0)), 1, 120)

# ----------------------------------------------------------------- physics --

func _emit(kind: String, text: String, team: int, player, extra: Dictionary = {}) -> void:
	ev_seq += 1
	var e = {
		"id": ev_seq, "type": kind, "text": text, "team": team,
		"player": player.name if player != null else "",
		"player_id": player.id if player != null else -1,
		"minute": minute_of(clock), "clock": clock, "pos": ball.pos,
	}
	for k in extra.keys():
		e[k] = extra[k]
	events.append(e)
	if events.size() > 600:
		events.pop_front()
	event_fired.emit(e)

func _add_involvement(p, kind: String, text: String, pos: Vector2) -> void:
	if p == null:
		return
	p.involvements.append({"t": clock, "minute": minute_of(clock), "type": kind, "text": text, "pos": pos})

func _flash(v: float) -> void:
	flash = maxf(flash, v)

func possession_pct() -> Vector2:
	var tot: float = stats[0]["possession"] + stats[1]["possession"]
	if tot < 0.01:
		return Vector2(50, 50)
	var a: float = float(stats[0]["possession"]) / tot * 100.0
	return Vector2(snappedf(a, 0.1), snappedf(100.0 - a, 0.1))

func summary() -> Dictionary:
	return {
		"score": score.duplicate(), "half": half, "clock": display_clock(),
		"possession": possession_pct(), "stats": stats.duplicate(true),
		"events": events.size(), "phase": phase,
	}
