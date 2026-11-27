class_name PreMatchModel
extends RefCounted


const FORM_LEN := 5


static func build(home_id: String, away_id: String, fixture: Dictionary, season: LeagueSeason) -> Dictionary:
	var home := TeamData.get_team(home_id)
	var away := TeamData.get_team(away_id)
	if home.is_empty() or away.is_empty():
		return {}
	var live := season != null and season.save != null
	var billing := MatchBilling.new()
	billing.bind_fixture(home_id, fixture, away_id)
	var home_xi := StrongestXI.pick(home)
	var away_xi := StrongestXI.pick(away)
	var seed := _seed(home_id, away_id, fixture)
	var table := _positions(season) if live else {}
	var home_pos := int(table.get(home_id, 0))
	var away_pos := int(table.get(away_id, 0))
	var ctx := {
		"derby": PreMatchCopy.derby(home_id, away_id),
		"matchday": billing.matchday,
		"home_position": home_pos,
		"away_position": away_pos,


		"friendly": billing.friendly,
		"competition": billing.full_name,
	}
	var home_form := _form(season, home_id) if live else ""
	var away_form := _form(season, away_id) if live else ""
	var home_ctx := ctx.duplicate(true)
	home_ctx["form"] = home_form
	home_ctx["position"] = home_pos
	var away_ctx := ctx.duplicate(true)
	away_ctx["form"] = away_form
	away_ctx["position"] = away_pos
	var date := str(fixture.get("kickoff", ""))
	return {
		"home": home, "away": away,
		"home_xi": home_xi, "away_xi": away_xi,
		"home_captain": _captain(home_xi), "away_captain": _captain(away_xi),
		"home_absences": SeasonAvailability.absences(home_id) if live else [],
		"away_absences": SeasonAvailability.absences(away_id) if live else [],
		"home_quote": PreMatchCopy.quote(seed, home, away, home_ctx),
		"away_quote": PreMatchCopy.quote(seed + 17, away, home, away_ctx),
		"news": PreMatchCopy.news(seed, home, away, ctx),
		"home_form": home_form, "away_form": away_form,
		"home_position": home_pos, "away_position": away_pos,
		"caption": billing.caption(),
		"competition": billing.chrome_name(),
		"friendly": billing.friendly,
		"matchday": billing.matchday,
		"date_label": FixtureCalendar.day_label(date) if date != "" else "",
		"time": str(fixture.get("kickoff_time", "")),
		"kick": "CONTINUE" if live and not fixture.is_empty() else "KICK OFF",
		"back": "BACK",
		"auto_seconds": 10.0,
	}


static func _captain(xi: Array) -> String:
	var best := ""
	var best_ovr := -1
	for p in xi:
		if int(p.get("ovr", 0)) > best_ovr:
			best_ovr = int(p.get("ovr", 0))
			best = str(p.get("id", ""))
	return best


static func _positions(season: LeagueSeason) -> Dictionary:
	var out := {}
	if season == null or season.record == null:
		return out
	for row in season.record.standings.table():
		out[str(row["club_id"])] = int(row["position"])
	return out


static func _form(season: LeagueSeason, club_id: String) -> String:
	if season == null or season.record == null:
		return ""
	var rows := season.record.fixtures.recent(club_id, FORM_LEN)
	var out := ""
	for i in range(rows.size() - 1, -1, -1):
		var fx: Dictionary = rows[i]
		var home := str(fx["home_club_id"]) == club_id
		var mine := int(fx["home_goals"]) if home else int(fx["away_goals"])
		var theirs := int(fx["away_goals"]) if home else int(fx["home_goals"])
		out += "W" if mine > theirs else ("D" if mine == theirs else "L")
	return out


static func _seed(home_id: String, away_id: String, fixture: Dictionary) -> int:
	var text := str(fixture.get("id", "")) if not fixture.is_empty() else home_id + "v" + away_id
	var h := 17
	for i in range(text.length()):
		h = int((h * 31 + text.unicode_at(i)) % 2147483647)
	return h
