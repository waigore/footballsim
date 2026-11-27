class_name Tactics
extends RefCounted


const MENTALITIES := ["very_defensive", "defensive", "cautious", "balanced", "positive", "attacking", "very_attacking"]
const NEUTRAL := "balanced"
const DUTIES := ["defend", "support", "attack"]


const MENTALITY_SHIFT := {
	"very_defensive": {"possession": 0.06, "line": -0.12, "press": -0.10, "tempo": -0.06, "directness": 0.08, "width": -0.06},
	"defensive": {"possession": 0.03, "line": -0.06, "press": -0.05, "tempo": -0.03, "directness": 0.04, "width": -0.03},
	"cautious": {"possession": 0.01, "line": -0.03, "press": -0.02, "tempo": -0.01, "directness": 0.02, "width": -0.01},
	"balanced": {},
	"positive": {"possession": -0.01, "line": 0.03, "press": 0.02, "tempo": 0.02, "directness": -0.01, "width": 0.01},
	"attacking": {"possession": -0.03, "line": 0.07, "press": 0.05, "tempo": 0.05, "directness": -0.03, "width": 0.03},
	"very_attacking": {"possession": -0.05, "line": 0.12, "press": 0.09, "tempo": 0.08, "directness": -0.05, "width": 0.05},
}

const CORNER_ROUTINES := ["near_post", "far_post", "short"]
const FREE_KICK_ROUTINES := ["direct", "worked"]

var base := {}
var formation := "4-2-3-1"
var mentality := NEUTRAL
var tempo := 0.5
var width := 0.5
var line := 0.5
var press := 0.5
var directness := 0.5
var crossing := 0.5
var time_wasting := 0.0
var roles := {}
var opposition := {"press": "standard", "marking": "zonal"}
var set_pieces := {"corner": "far_post", "free_kick": "worked", "penalty": "striker"}


static func from_team(data: Dictionary, profile: Dictionary = {}) -> Tactics:
	var t := Tactics.new()
	var style: Dictionary = data.get("style", {})
	t.base = style.duplicate(true)
	t.formation = str(data.get("formation", "4-2-3-1"))
	t.tempo = float(style.get("tempo", 0.5))
	t.width = float(style.get("width", 0.5))
	t.line = float(style.get("line", 0.5))
	t.press = float(style.get("press", 0.5))
	t.directness = float(style.get("directness", 0.5))
	t.crossing = float(style.get("crossing", 0.5))
	for role in TeamData.slots(t.formation).keys():
		t.roles[role] = _default_duty(role)
	return t

static func _default_duty(role: String) -> String:
	if Attrs.is_defender(role) or role == "GK":
		return "defend"
	if Attrs.role_push(role) >= 0.7:
		return "attack"
	return "support"

func mentality_index() -> int:
	return MENTALITIES.find(mentality)

func describe() -> Array:
	var out := [formation, str(mentality).replace("_", " ")]
	if line > float(base.get("line", 0.5)) + 0.04:
		out.append("higher line")
	elif line < float(base.get("line", 0.5)) - 0.04:
		out.append("deeper line")
	if press > float(base.get("press", 0.5)) + 0.04:
		out.append("more pressing")
	elif press < float(base.get("press", 0.5)) - 0.04:
		out.append("less pressing")
	if width > float(base.get("width", 0.5)) + 0.04:
		out.append("wider")
	elif width < float(base.get("width", 0.5)) - 0.04:
		out.append("narrower")
	if tempo < float(base.get("tempo", 0.5)) - 0.04:
		out.append("slower tempo")
	elif tempo > float(base.get("tempo", 0.5)) + 0.04:
		out.append("faster tempo")
	if directness > float(base.get("directness", 0.5)) + 0.05:
		out.append("more direct")
	if time_wasting > 0.25:
		out.append("time-wasting")
	return out


func style() -> Dictionary:
	var m: Dictionary = MENTALITY_SHIFT.get(mentality, {})
	return {
		"possession": clampf(float(base.get("possession", 0.5)) + float(m.get("possession", 0.0)), 0.05, 0.95),
		"tempo": clampf(tempo + float(m.get("tempo", 0.0)), 0.0, 1.0),
		"press": clampf(press + float(m.get("press", 0.0)), 0.0, 1.0),
		"line": clampf(line + float(m.get("line", 0.0)), 0.0, 1.0),
		"width": clampf(width + float(m.get("width", 0.0)), 0.0, 1.0),
		"directness": clampf(directness + float(m.get("directness", 0.0)), 0.0, 1.0),
		"crossing": clampf(crossing, 0.0, 1.0),
		"aggression": float(base.get("aggression", MatchContact.NEUTRAL)),
		"time_wasting": clampf(time_wasting, 0.0, 1.0),
		"press_trigger": str(opposition.get("press", "standard")),
		"marking": str(opposition.get("marking", "zonal")),
	}

func duty_of(role: String) -> String:
	return str(roles.get(role, "support"))


func duty_offset(role: String) -> float:
	match duty_of(role):
		"attack":
			return 0.06
		"defend":
			return -0.06
	return 0.0

func corner_routine() -> String:
	return str(set_pieces.get("corner", "far_post"))

func free_kick_routine() -> String:
	return str(set_pieces.get("free_kick", "worked"))


func apply(change: Dictionary) -> Array:
	var out := []
	if change.has("formation"):
		var f := str(change["formation"])
		if TeamData.FORMATIONS.has(f) and f != formation:
			formation = f
			out.append(f)
	if change.has("mentality_shift"):
		var idx: int = clampi(mentality_index() + int(change["mentality_shift"]), 0, MENTALITIES.size() - 1)
		mentality = MENTALITIES[idx]
		out.append("mentality " + mentality.replace("_", " "))
	elif change.has("mentality"):
		var m := str(change["mentality"])
		if MENTALITIES.has(m) and m != mentality:
			mentality = m
			out.append("mentality " + m.replace("_", " "))
	for pair in [["tempo", "tempo"], ["width", "width"], ["line", "line"], ["press", "press"],
			["directness", "directness"], ["crossing", "crossing"]]:
		var key := str(pair[0]) + "_delta"
		if change.has(key):
			var before: float = float(get(pair[1]))
			set(pair[1], clampf(before + float(change[key]), 0.0, 1.0))
			var after: float = float(get(pair[1]))
			if absf(after - before) > 0.001:
				out.append(label_delta(pair[1], after - before))
	if change.has("time_wasting"):
		time_wasting = clampf(float(change["time_wasting"]), 0.0, 1.0)
		out.append("time-wasting" if time_wasting > 0.25 else "play on")
	if change.has("corner"):
		var r := str(change["corner"])
		if CORNER_ROUTINES.has(r) and r != corner_routine():
			set_pieces["corner"] = r
			out.append("corners " + r.replace("_", " "))
	if change.has("free_kick"):
		var fk := str(change["free_kick"])
		if FREE_KICK_ROUTINES.has(fk) and fk != free_kick_routine():
			set_pieces["free_kick"] = fk
			out.append("free kicks " + fk)
	if change.has("roles"):
		var got: Dictionary = change["roles"]
		for role in got.keys():
			if DUTIES.has(str(got[role])):
				roles[str(role)] = str(got[role])
				out.append("%s duty %s" % [str(role), str(got[role])])
	if change.has("opposition"):
		var opp: Dictionary = change["opposition"]
		for k in opp.keys():
			opposition[str(k)] = str(opp[k])
		out.append("opposition " + str(opp.keys()[0] if not opp.is_empty() else "set"))
	return out

static func label_delta(field: String, delta: float) -> String:
	var up: bool = delta > 0.0
	match field:
		"line":
			return "higher line" if up else "deeper line"
		"press":
			return "more pressing" if up else "less pressing"
		"width":
			return "wider" if up else "narrower"
		"tempo":
			return "faster tempo" if up else "slower tempo"
		"directness":
			return "more direct" if up else "shorter passing"
		"crossing":
			return "more crosses" if up else "fewer crosses"
	return field

func to_dict() -> Dictionary:
	return {
		"formation": formation, "mentality": mentality, "tempo": tempo, "width": width,
		"line": line, "press": press, "directness": directness, "crossing": crossing,
		"time_wasting": time_wasting, "roles": roles.duplicate(true),
		"opposition": opposition.duplicate(true), "set_pieces": set_pieces.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	formation = str(d.get("formation", formation))
	mentality = str(d.get("mentality", mentality))
	tempo = float(d.get("tempo", tempo))
	width = float(d.get("width", width))
	line = float(d.get("line", line))
	press = float(d.get("press", press))
	directness = float(d.get("directness", directness))
	crossing = float(d.get("crossing", crossing))
	time_wasting = float(d.get("time_wasting", time_wasting))
	roles = (d.get("roles", roles) as Dictionary).duplicate(true)
	opposition = (d.get("opposition", opposition) as Dictionary).duplicate(true)
	set_pieces = (d.get("set_pieces", set_pieces) as Dictionary).duplicate(true)
