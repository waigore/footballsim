class_name LeagueReportSheet
extends RefCounted


const HEADER := 58.0

const PLAY_W := 44.0
const PLAY_H := 26.0
const GUTTER := 16.0

const ROW_H := 20.0
const CLIP_H := 40.0

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()


static func columns(vp: Vector2) -> Dictionary:
	var w := (vp.x - 48.0 - GUTTER) * 0.5
	return {"home_x": 24.0, "away_x": 24.0 + w + GUTTER, "w": maxf(w, 120.0)}


static func block_fixture(report: Dictionary) -> Dictionary:
	var fx: Dictionary = (report.get("fixture", {}) as Dictionary).duplicate()
	fx["events"] = report.get("events", [])
	return fx

func layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []


	items.append(LeagueExtra.back_item())
	var roundup: Array = view.get("roundup", [])
	if not roundup.is_empty():
		items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
			"pinned": true, "rect": LeagueExtra.primary_rect(vp)})
	var y := HEADER + 70.0
	var mixed := false
	if roundup.size() > 1:
		var ids := {}
		for report in roundup:
			ids[str(block_fixture(report).get("competition_id", ""))] = true
		mixed = ids.size() > 1
	var last_comp := ""
	for report in roundup:
		var fx := block_fixture(report)
		var comp := str(fx.get("competition_id", ""))
		if mixed and comp != last_comp:
			last_comp = comp
			items.append({"id": "", "kind": "league_head", "competition": comp,
				"matchday": int(fx.get("matchday", 1)),
				"rect": Rect2(24.0, y, vp.x - 48.0, 16.0)})
			y += 18.0
		var row := Rect2(24.0, y, vp.x - 48.0, LeagueBlock.height(fx) + 10.0)
		items.append({"id": "match:" + str(fx.get("id", "")), "kind": "result",
			"report": report, "rect": row})
		y += row.size.y + 6.0
	if not (view.get("roundup", []) as Array).is_empty():
		return items
	var report := {"fixture": view.get("fixture", {}), "events": view.get("events", [])}
	var clips := {}
	for row in view.get("highlights", []):
		clips[int(row.get("goal_index", -1))] = row
	var numbered: Array = []
	var goal := 0
	for e in LeagueRoundup.lines(report):
		var ordinal := -1
		if LeagueRoundup.is_goal(e):
			ordinal = goal
			goal += 1
		numbered.append({"event": e, "goal": ordinal})


	var places := columns(vp)
	var cursors := {"home": y, "away": y}
	for item in numbered:
		var e: Dictionary = item["event"]
		var side := LeagueRoundup.side_of(report["fixture"], e)
		var clip: Dictionary = clips.get(int(item["goal"]), {}) if int(item["goal"]) >= 0 else {}
		var h := CLIP_H if not clip.is_empty() else ROW_H
		var x := float(places["home_x"]) if side == "home" else float(places["away_x"])
		var line := Rect2(x, float(cursors[side]), float(places["w"]), h)
		items.append({"id": "", "kind": "event", "event": e, "side": side,
			"clip": clip, "rect": line})
		if not clip.is_empty():
			items.append({"id": "goal:%d" % int(item["goal"]), "kind": "play", "clip": clip,
				"rect": Rect2(line.end.x - PLAY_W, line.position.y + 1.0, PLAY_W, PLAY_H)})
		cursors[side] = float(cursors[side]) + h + 1.0
	return items


func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	var roundup: Array = view.get("roundup", [])
	var date := str(view.get("day", ""))
	var kicker := "MATCH REPORT"
	var caption := ""
	var right := 0.0
	if not roundup.is_empty():
		kicker = "RESULTS"
		caption = FixtureCalendar.day_label(date) if date != "" else date

		right = LeagueExtra.primary_rect(vp).size.x + 12.0
	LeagueExtra.header(c, vp, fonts, kicker, caption, right)

func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	var roundup: Array = view.get("roundup", [])
	var fx: Dictionary = view.get("fixture", {})
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	if roundup.is_empty():


		var head_y := HEADER + 34.0
		var home_id := str(fx.get("home_club_id", ""))
		var away_id := str(fx.get("away_club_id", ""))
		var hx := 24.0
		hx += InterestNames.run(c, names, home_id, str(fx.get("home_name", "")),
			Vector2(hx, head_y), 22, LeagueInterestMark.ink(interest, home_id), bold) + 10.0
		var score := "%d – %d" % [int(fx.get("home_goals", 0)), int(fx.get("away_goals", 0))]
		UiChrome.text(c, Vector2(hx, head_y), score, 22, UiChrome.C_TEXT, bold)
		hx += InterestNames.width(bold, score, 22) + 10.0
		InterestNames.run(c, names, away_id, str(fx.get("away_name", "")),
			Vector2(hx, head_y), 22, LeagueInterestMark.ink(interest, away_id), bold)
		var date := str(view.get("day", ""))
		var label := FixtureCalendar.day_label(date)
		UiChrome.text(c, Vector2(24.0, HEADER + 54.0), label, 10, UiChrome.C_DIM, med)
		if date != "":
			hints.add(DateHints.strip(med, label, Vector2(24.0, HEADER + 54.0), 10), date)


		var places := columns(vp)
		for pair in [["home_x", "home_club_id", "home_name"],
				["away_x", "away_club_id", "away_name"]]:
			var x := float(places[pair[0]])
			var club_id := str(fx.get(pair[1], ""))
			var caption: String = LeagueColumns.fit_name(str(fx.get(pair[2], "")), bold, 10,
				float(places["w"]))
			InterestNames.run(c, names, club_id, caption, Vector2(x, HEADER + 72.0), 10,
				LeagueInterestMark.ink(interest, club_id), bold)
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "play":
			_draw_play(c, rect, bold)
		elif kind == "league_head":
			LeagueExtra.draw_league_head(c, rect, str(item.get("competition", "")),
				int(item.get("matchday", 1)), fonts)
		elif kind == "result":
			var block := block_fixture(item["report"])
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 5)
			var home_id := str(block.get("home_club_id", ""))
			var away_id := str(block.get("away_club_id", ""))
			LeagueBlock.paint(c, rect, block, fonts, names,
				LeagueInterestMark.ink(interest, home_id),
				LeagueInterestMark.ink(interest, away_id))
		elif kind == "event":
			_draw_event(c, rect, item, fonts, interest)


func _draw_play(c: CanvasItem, rect: Rect2, bold: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, Color(0.96, 0.78, 0.30, 0.55), 1)
	var mid: float = rect.position.y + rect.size.y * 0.5 + UiChrome.RISE
	UiChrome.text_c(c, rect.get_center().x, mid, "▶ PLAY", 10, UiChrome.C_GOLD, bold)

func _draw_event(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary,
		interest: Dictionary) -> void:
	var e: Dictionary = item["event"]
	var clip: Dictionary = item.get("clip", {})
	var club := str(e.get("club_id", ""))
	var ink := LeagueInterestMark.ink(interest, club) if club != "" else UiChrome.C_TEXT
	if LeagueRoundup.is_goal(e):
		ink = UiChrome.C_GOLD


	var room := rect.size.x - 8.0
	if not clip.is_empty():
		room -= PLAY_W + 8.0
	LeagueMarks.line(c, rect.position, e, fonts, room, ink)
	if not clip.is_empty():
		var line := str(clip.get("commentary", ""))
		if line != "":
			var fit := maxi(int(room / 5.4), 12)
			UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 32.0),
				line.substr(0, fit), 10, UiChrome.C_SOFT, fonts["med"])


