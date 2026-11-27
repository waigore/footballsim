class_name PreMatchCopy
extends RefCounted


const DERBIES := [
	["MUN", "MCI"], ["LIV", "EVE"], ["ARS", "TOT"], ["NEW", "SUN"],
	["CHE", "FUL"], ["AVL", "WOL"], ["NFO", "LEI"],
]

const DERBY_LINES := [
	"There is no friendly in this one. Our people expect us first to every ball.",
	"Form goes out of the window in a derby. We will need character, not just quality.",
	"These are the games you remember as a player. Nobody has to be motivated today.",
]

const FORM_GOOD_LINES := [
	"We have won {wins} of our last five. Belief is easy to talk about; we have it.",
	"The run is not luck. The players have earned the right to be confident.",
	"Winning becomes a habit. We want to keep it that way this afternoon.",
]

const FORM_POOR_LINES := [
	"Results have not come, but the work has. Today is a chance to answer with a performance.",
	"We are not hiding from the table. We are here to change it.",
	"One good afternoon can turn a season. We intend to have one.",
]

const PRESSURE_LINES := [
	"{place} is not where this club belongs, and the players know it.",
	"Everyone can read a table. Our job is to make the next game count.",
	"We carry the expectation of this club. That is a privilege, not a burden.",
]

const PLAIN_LINES := [
	"We respect {opponent}, but we have come here to win the game.",
	"They are a good side. So are we. Let us see who is better today.",
	"The plan is simple: be compact, be brave, take our chances.",
]


const FRIENDLY_LINES := [
	"A good run-out for both squads. We want the habits right before the season.",
	"No points at stake, but the standards are the same. That is why we play it.",
	"These games are for sharpness and for the people who came to watch.",
]

const NEWS_TITLE_TOP := "TITLE RACE"
const NEWS_TITLE_DERBY := "DERBY DAY"
const NEWS_TITLE_BOTTOM := "SURVIVAL WATCH"
const NEWS_TITLE_PLAIN := "MATCHDAY BRIEFING"
const NEWS_TITLE_FRIENDLY := "FRIENDLY"


static func derby(a: String, b: String) -> bool:
	for pair in DERBIES:
		if (str(pair[0]) == a and str(pair[1]) == b) or (str(pair[0]) == b and str(pair[1]) == a):
			return true
	return false


static func quote(seed: int, team: Dictionary, opponent: Dictionary, ctx: Dictionary) -> Dictionary:
	var manager := str(team.get("manager", "")).to_upper()
	var wins := str(ctx.get("form", "")).count("W")
	var line := ""
	if bool(ctx.get("friendly", false)):
		line = _pick(FRIENDLY_LINES, seed, 17)
	elif bool(ctx.get("derby", false)):
		line = _pick(DERBY_LINES, seed, 3)
	elif wins >= 3:
		line = _pick(FORM_GOOD_LINES, seed, 5).replace("{wins}", str(wins))
	elif wins <= 1:
		line = _pick(FORM_POOR_LINES, seed, 7)
	elif int(ctx.get("position", 0)) > 0 and int(ctx.get("position", 0)) >= 12:
		line = _pick(PRESSURE_LINES, seed, 11).replace("{place}", place(int(ctx["position"])))
	else:
		line = _pick(PLAIN_LINES, seed, 13).replace("{opponent}", str(opponent.get("name", "")))
	return {"by": manager, "line": line}


static func news(seed: int, home: Dictionary, away: Dictionary, ctx: Dictionary) -> Dictionary:
	var title := NEWS_TITLE_PLAIN
	var line := ""
	var league := not bool(ctx.get("friendly", false))
	if bool(ctx.get("derby", false)) and league:
		title = NEWS_TITLE_DERBY
		line = "%s host %s at %s. Bragging rights, and three points that matter more than usual." % [
			str(home.get("name", "")), str(away.get("name", "")), str(home.get("stadium", ""))]
	elif bool(ctx.get("derby", false)):
		title = NEWS_TITLE_DERBY
		line = "%s host %s at %s. Bragging rights are the whole prize in a friendly." % [
			str(home.get("name", "")), str(away.get("name", "")), str(home.get("stadium", ""))]
	elif league and int(ctx.get("home_position", 0)) > 0 and int(ctx.get("home_position", 0)) <= 4 \
			and int(ctx.get("away_position", 0)) > 0 and int(ctx.get("away_position", 0)) <= 4:
		title = NEWS_TITLE_TOP
		line = "%s (%s) meet %s (%s) at %s — a top-four six-pointer on matchday %d." % [
			str(home.get("name", "")), place(int(ctx["home_position"])), str(away.get("name", "")),
			place(int(ctx["away_position"])), str(home.get("stadium", "")), int(ctx.get("matchday", 1))]
	elif league and (int(ctx.get("home_position", 0)) >= 16 or int(ctx.get("away_position", 0)) >= 16):
		title = NEWS_TITLE_BOTTOM
		line = "Both sides need the points at %s. %s sit %s, %s %s." % [
			str(home.get("stadium", "")), str(home.get("name", "")), place(int(ctx.get("home_position", 0))),
			str(away.get("name", "")), place(int(ctx.get("away_position", 0)))]
	elif league:
		line = "%s welcome %s to %s for matchday %d in the %s." % [
			str(home.get("name", "")), str(away.get("name", "")),
			str(home.get("stadium", "")), int(ctx.get("matchday", 1)),
			str(ctx.get("competition", "")) if str(ctx.get("competition", "")) != "" else "league"]
	else:
		title = NEWS_TITLE_FRIENDLY
		line = "%s welcome %s to %s for a friendly: no table, no points, just the game." % [
			str(home.get("name", "")), str(away.get("name", "")), str(home.get("stadium", ""))]
	return {"title": title, "line": line}


static func place(n: int) -> String:
	if n <= 0:
		return ""
	var suffix := "th"
	var last_two := n % 100
	if last_two < 11 or last_two > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]

static func _pick(lines: Array, seed: int, salt: int) -> String:
	var index := absi(seed + salt * 7919) % lines.size()
	return str(lines[index])
