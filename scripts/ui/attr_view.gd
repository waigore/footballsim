class_name AttrView
extends RefCounted


const SIDES := ["SIMPLIFIED", "FULL"]

const GROUPS := [
	["ATTACKING", ["crossing", "finishing", "heading_accuracy", "short_passing", "volleys"]],
	["SKILL", ["dribbling", "curve", "fk_accuracy", "long_passing", "ball_control"]],
	["MOVEMENT", ["acceleration", "sprint_speed", "agility", "reactions", "balance"]],
	["POWER", ["shot_power", "jumping", "stamina", "strength", "long_shots"]],
	["MENTALITY", ["aggression", "interceptions", "positioning", "vision", "penalties", "composure"]],
	["DEFENDING", ["marking_awareness", "standing_tackle", "sliding_tackle"]],
]

const KEEPER_GROUP := ["GLOVE", ["gk_diving", "gk_handling", "gk_kicking", "gk_positioning", "gk_reflexes"]]

const LABELS := {
	"crossing": "CRO", "finishing": "FIN", "heading_accuracy": "HEA",
	"short_passing": "SPA", "volleys": "VOL", "dribbling": "DRI",
	"curve": "CUR", "fk_accuracy": "FKA", "long_passing": "LPA",
	"ball_control": "CTR", "acceleration": "ACC", "sprint_speed": "SPD",
	"agility": "AGI", "reactions": "REA", "balance": "BAL",
	"shot_power": "POW", "jumping": "JUM", "stamina": "STA",
	"strength": "STR", "long_shots": "LON", "aggression": "AGR",
	"interceptions": "INT", "positioning": "POS", "vision": "VIS",
	"penalties": "PEN", "composure": "COM", "marking_awareness": "MRK",
	"standing_tackle": "STT", "sliding_tackle": "SLT", "gk_diving": "DIV",
	"gk_handling": "HAN", "gk_kicking": "KIC", "gk_positioning": "POS",
	"gk_reflexes": "REF",
}

const TITLES := {
	"crossing": "CROSSING", "finishing": "FINISHING", "heading_accuracy": "HEADING",
	"short_passing": "SHORT PASSING", "volleys": "VOLLEYS", "dribbling": "DRIBBLING",
	"curve": "CURVE", "fk_accuracy": "FREE KICKS", "long_passing": "LONG PASSING",
	"ball_control": "BALL CONTROL", "acceleration": "ACCELERATION",
	"sprint_speed": "SPRINT SPEED", "agility": "AGILITY", "reactions": "REACTIONS",
	"balance": "BALANCE", "shot_power": "SHOT POWER", "jumping": "JUMPING",
	"stamina": "STAMINA", "strength": "STRENGTH", "long_shots": "LONG SHOTS",
	"aggression": "AGGRESSION", "interceptions": "INTERCEPTIONS",
	"positioning": "POSITIONING", "vision": "VISION", "penalties": "PENALTIES",
	"composure": "COMPOSURE", "marking_awareness": "MARKING",
	"standing_tackle": "STANDING TACKLE", "sliding_tackle": "SLIDING TACKLE",
	"gk_diving": "DIVING", "gk_handling": "HANDLING", "gk_kicking": "KICKING",
	"gk_positioning": "POSITIONING", "gk_reflexes": "REFLEXES",
}


static func normalize(mode: String) -> String:
	return "FULL" if mode == "FULL" else "SIMPLIFIED"


static func other(mode: String) -> String:
	return "SIMPLIFIED" if normalize(mode) == "FULL" else "FULL"


static func label(mode: String) -> String:
	return "%s VIEW" % normalize(mode)


static func next_label(mode: String) -> String:
	return "SHOW %s" % normalize(other(mode))


static func groups(role: String) -> Array:
	if role == "GK":
		return [KEEPER_GROUP]
	return GROUPS


static func short(key: String) -> String:
	return str(LABELS.get(key, key.to_upper().substr(0, 3)))


static func title(key: String) -> String:
	return str(TITLES.get(key, key.to_upper().replace("_", " ")))


static func rows(role: String, subs: Dictionary) -> Array:
	var out: Array = []
	for group in groups(role):
		var cells: Array = []
		for key in group[1]:
			cells.append([short(str(key)), str(int(subs.get(str(key), 0))), title(str(key))])
		out.append({"title": str(group[0]), "cells": cells})
	return out


static func flat(role: String, subs: Dictionary) -> Array:
	"""Every sub-stat in reading order, as [short label, value, full title]."""
	var out: Array = []
	for group in groups(role):
		for key in group[1]:
			out.append([short(str(key)), str(int(subs.get(str(key), 0))), title(str(key))])
	return out


static func extras(player: Dictionary) -> Array:
	var info: Dictionary = player.get("extras", {})
	var out: Array = []
	if player.get("ratings_matched", false):
		out.append(["SOURCE", "SOFIFA"])
	else:
		out.append(["SOURCE", "SYNTHESIZED"])
	var potential := int(info.get("potential", 0))
	if potential > 0:
		out.append(["POTENTIAL", str(potential)])
	var weak := int(info.get("weak_foot", 0))
	if weak > 0:
		out.append(["WEAK FOOT", "%d/5" % weak])
	var moves := int(info.get("skill_moves", 0))
	if moves > 0:
		out.append(["SKILL MOVES", "%d/5" % moves])
	var rep := int(info.get("international_reputation", 0))
	if rep > 0:
		out.append(["INTL REP", "%d/5" % rep])
	return out
