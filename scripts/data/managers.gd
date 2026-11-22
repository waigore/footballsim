class_name ManagerData
extends RefCounted

## In-match manager identity. Real manager names live with the squad shards
## (teams_*.gd); this table adds the identity profile that biases live
## decisions — how quickly a manager reacts, how stubborn he is, how much risk
## he takes, how patient he is between changes, and which levers he reaches for.
##
## Profiles are inputs to the decision engine only: they never apply pitch
## physics themselves. Every playable club resolves to a real manager plus a
## profile, even when the club has no entry here (the default is steady).

const DEFAULT := {
	"reactive": 0.55,
	"stubborn": 0.50,
	"risk": 0.50,
	"patience": 0.52,
	"sub_style": 0.50,
	"levers": ["mentality", "press", "formation"],
	"formation": "4-2-3-1",
	"mentality": "balanced",
	"trait": "steady hand",
}

## reactive  — how strongly events feed urgency (0 = ice cold, 1 = touchline)
## stubborn  — resistance to changing a plan (dampens urgency, slows reactions)
## risk      — leans attacking / chasing when a game turns (0 = shut up shop)
## patience  — how long he waits between tactical changes
## sub_style — how eagerly he rotates the bench (0.5 = reactive, 0.8 = proactive)
const PROFILES := {
	"MUN": {"reactive": 0.62, "stubborn": 0.44, "risk": 0.58, "patience": 0.48, "sub_style": 0.55,
		"levers": ["mentality", "press", "formation", "width"], "formation": "4-2-3-1", "mentality": "positive",
		"trait": "front-foot, switches shape early"},
	"MCI": {"reactive": 0.52, "stubborn": 0.64, "risk": 0.50, "patience": 0.66, "sub_style": 0.42,
		"levers": ["mentality", "tempo", "press", "set_piece"], "formation": "4-3-3", "mentality": "positive",
		"trait": "controls tempo, hates losing control"},
	"ARS": {"reactive": 0.58, "stubborn": 0.50, "risk": 0.55, "patience": 0.55, "sub_style": 0.50,
		"levers": ["mentality", "press", "line", "set_piece"], "formation": "4-3-3", "mentality": "positive",
		"trait": "high line, set-piece detail"},
	"AVL": {"reactive": 0.70, "stubborn": 0.34, "risk": 0.60, "patience": 0.42, "sub_style": 0.62,
		"levers": ["formation", "mentality", "press", "width"], "formation": "4-4-2", "mentality": "balanced",
		"trait": "shifts shape mid-game"},
	"BOU": {"reactive": 0.74, "stubborn": 0.28, "risk": 0.62, "patience": 0.40, "sub_style": 0.46,
		"levers": ["press", "line", "mentality"], "formation": "4-2-3-1", "mentality": "positive",
		"trait": "relentless presser"},
	"BRE": {"reactive": 0.48, "stubborn": 0.56, "risk": 0.44, "patience": 0.58, "sub_style": 0.52,
		"levers": ["set_piece", "formation", "tempo"], "formation": "4-2-3-1", "mentality": "balanced",
		"trait": "organised, set-piece focused"},
	"BHA": {"reactive": 0.66, "stubborn": 0.38, "risk": 0.58, "patience": 0.46, "sub_style": 0.56,
		"levers": ["press", "tempo", "formation"], "formation": "4-2-3-1", "mentality": "positive",
		"trait": "brave build-up, quick to react"},
	"BUR": {"reactive": 0.42, "stubborn": 0.62, "risk": 0.38, "patience": 0.62, "sub_style": 0.44,
		"levers": ["line", "mentality", "time_wasting"], "formation": "4-4-2", "mentality": "cautious",
		"trait": "deep block, hard to move"},
	"CHE": {"reactive": 0.60, "stubborn": 0.48, "risk": 0.56, "patience": 0.52, "sub_style": 0.58,
		"levers": ["mentality", "tempo", "press"], "formation": "4-2-3-1", "mentality": "positive",
		"trait": "possession with intent"},
	"CRY": {"reactive": 0.64, "stubborn": 0.42, "risk": 0.54, "patience": 0.48, "sub_style": 0.52,
		"levers": ["formation", "press", "line"], "formation": "3-5-2", "mentality": "balanced",
		"trait": "back three, wing-back press"},
	"EVE": {"reactive": 0.50, "stubborn": 0.56, "risk": 0.42, "patience": 0.58, "sub_style": 0.46,
		"levers": ["line", "mentality", "set_piece"], "formation": "4-2-3-1", "mentality": "cautious",
		"trait": "compact, waits for his moment"},
	"FUL": {"reactive": 0.56, "stubborn": 0.48, "risk": 0.50, "patience": 0.54, "sub_style": 0.50,
		"levers": ["width", "tempo", "press"], "formation": "4-2-3-1", "mentality": "balanced",
		"trait": "wide, patient circulation"},
	"LEE": {"reactive": 0.52, "stubborn": 0.52, "risk": 0.50, "patience": 0.56, "sub_style": 0.48,
		"levers": ["tempo", "width", "press"], "formation": "4-2-3-1", "mentality": "balanced",
		"trait": "front-foot Championship habits"},
	"LIV": {"reactive": 0.58, "stubborn": 0.50, "risk": 0.58, "patience": 0.52, "sub_style": 0.54,
		"levers": ["press", "mentality", "tempo"], "formation": "4-3-3", "mentality": "positive",
		"trait": "counter-press, vertical"},
	"NEW": {"reactive": 0.54, "stubborn": 0.50, "risk": 0.52, "patience": 0.55, "sub_style": 0.50,
		"levers": ["press", "width", "set_piece"], "formation": "4-3-3", "mentality": "balanced",
		"trait": "physical, wide overloads"},
	"NFO": {"reactive": 0.40, "stubborn": 0.68, "risk": 0.36, "patience": 0.66, "sub_style": 0.38,
		"levers": ["line", "time_wasting", "formation"], "formation": "4-4-2", "mentality": "cautious",
		"trait": "stubborn low block"},
	"SUN": {"reactive": 0.60, "stubborn": 0.45, "risk": 0.54, "patience": 0.50, "sub_style": 0.52,
		"levers": ["press", "tempo", "mentality"], "formation": "4-2-3-1", "mentality": "balanced",
		"trait": "young legs, high energy"},
	"TOT": {"reactive": 0.62, "stubborn": 0.44, "risk": 0.56, "patience": 0.48, "sub_style": 0.58,
		"levers": ["set_piece", "press", "formation"], "formation": "4-2-3-1", "mentality": "positive",
		"trait": "set-piece coach, front-foot"},
	"WHU": {"reactive": 0.46, "stubborn": 0.62, "risk": 0.42, "patience": 0.60, "sub_style": 0.44,
		"levers": ["line", "mentality", "time_wasting"], "formation": "4-2-3-1", "mentality": "cautious",
		"trait": "experienced, protects a lead"},
	"WOL": {"reactive": 0.50, "stubborn": 0.54, "risk": 0.48, "patience": 0.56, "sub_style": 0.50,
		"levers": ["tempo", "width", "press"], "formation": "4-2-3-1", "mentality": "balanced",
		"trait": "compact, counters wide"},
}

const REQUIRED := ["name", "reactive", "stubborn", "risk", "patience", "sub_style", "levers", "formation", "mentality", "trait"]

## Resolve the real manager of a club plus the profile that biases his match
## decisions. Unknown clubs fall back to a steady hand built from squad data.
static func profile(club_id: String) -> Dictionary:
	var out: Dictionary = DEFAULT.duplicate(true)
	if PROFILES.has(club_id):
		out.merge(PROFILES[club_id].duplicate(true), true)
	var data: Dictionary = TeamData.get_team(club_id)
	out["name"] = str(data.get("manager", "The manager"))
	out["club"] = str(data.get("short", club_id))
	out["levers"] = (out["levers"] as Array).duplicate()
	return out

static func has_full_profile(p: Dictionary) -> bool:
	for key in REQUIRED:
		if not p.has(key):
			return false
	return true

## One short line for the broadcast overlay, e.g. "front-foot, switches shape early".
static func trait_line(club_id: String) -> String:
	return str(profile(club_id).get("trait", ""))
