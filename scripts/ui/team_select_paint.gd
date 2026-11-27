class_name TeamSelectPaint
extends RefCounted


static func arrow(sheet: Control, r: Rect2, glyph: String, id: String) -> void:
	var hovered: bool = r.has_point(sheet.mouse as Vector2)
	sheet.rect(sheet.C_PANEL_LIGHT if hovered else sheet.C_PANEL, r, 8,
		Color(1, 1, 1, 0.14 if hovered else 0.07))
	sheet.text_c(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.66, glyph, 24,
		sheet.C_TEXT if hovered else sheet.C_DIM, sheet.f_bold)
	sheet._add_button(id, r)


static func league_chips(sheet: Control, vp: Vector2) -> void:
	var rows: Array = LeagueChrome.competition_rows()
	if rows.size() < 2:
		return
	var rects: Array = LeagueChrome.picker_chip_rects(vp, rows.size())
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var chip: Rect2 = rects[i]
		var on: bool = str(row["id"]) == str(sheet.league_filter)
		sheet.rect(sheet.C_GOLD.darkened(0.1) if on else sheet.C_PANEL, chip, 6,
			sheet.C_GOLD if on else Color(1, 1, 1, 0.10))
		sheet.text_c(chip.get_center().x, chip.position.y + 16.0,
			LeagueChrome.competition_chip_label(row, chip.size.x), 10,
			Color(0.06, 0.06, 0.05) if on else sheet.C_DIM, sheet.f_bold)
		sheet._add_button("league:" + str(row["id"]), chip)

static func card(sheet: Control, r: Rect2, t: Dictionary, side: int) -> void:
	sheet.rect(sheet.C_PANEL, r, 14, Color(1, 1, 1, 0.10))
	sheet.draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 6, r.size.y - 2), t["color"])
	var cx := r.position.x + r.size.x * 0.5

	var club := str(t.get("id", ""))
	if club == "":
		club = str(sheet.home_id() if side == 0 else sheet.away_id())
	var name_ink: Color = sheet.C_GOLD if sheet.followed.has(club) else sheet.C_TEXT
	sheet.text_c(cx, r.position.y + r.size.y * 0.30, str(t["abbr"]), 54, name_ink, sheet.f_bold)
	sheet.text_c(cx, r.position.y + r.size.y * 0.50, str(t["name"]).to_upper(), 17, name_ink, sheet.f_med)
	sheet.text_c(cx, r.position.y + r.size.y * 0.64, str(t["nickname"]).to_upper(), 11, sheet.C_DIM, sheet.f_med)
	sheet.text_c(cx, r.position.y + r.size.y * 0.80,
		"%s  ·  %s" % [str(t["formation"]), str(t["manager"]).to_upper()], 10, sheet.C_GOLD, sheet.f_med)
	sheet.text_c(cx, r.position.y + r.size.y - 12.0, "VIEW CLUB  ›", 10, sheet.C_DIM, sheet.f_bold)
	var label: String = "HOME" if side == 0 else "AWAY"
	sheet.text_c(cx, r.position.y - 10, label, 11, sheet.C_DIM, sheet.f_bold)

static func doors(sheet: Control, vp: Vector2, card_bottom: float) -> void:
	for door in LeagueChrome.picker_doors(vp, card_bottom):
		var r: Rect2 = door["rect"]
		var hovered: bool = r.has_point(sheet.mouse as Vector2)
		if str(door["id"]) == "confirm":
			UiChrome.button(sheet, sheet.style_cache, r, "KICK OFF", sheet.f_bold, true, 16,
				"" if bool(sheet.touch) else "ENTER")
		else:

			sheet.rect(sheet.C_PANEL_LIGHT if hovered else sheet.C_PANEL, r, 10,
				Color(1, 1, 1, 0.10 if hovered else 0.06))
			var middle: float = r.position.y + r.size.y * 0.5
			var cap_y: float = middle + (UiChrome.RISE if bool(sheet.touch) else -UiChrome.RISE)
			sheet.text_c(r.get_center().x, cap_y, "RANDOM", 16, sheet.C_TEXT, sheet.f_bold)
			if not bool(sheet.touch):
				sheet.text_c(r.get_center().x, middle + UiChrome.HINT_DROP, "TAB", 10,
					sheet.C_DIM, sheet.f_med)
		sheet._add_button(str(door["id"]), r)

static func chrome_doors(sheet: Control, vp: Vector2) -> void:

	var back: Rect2 = sheet.back_rect(vp)
	var back_hover: bool = back.has_point(sheet.mouse as Vector2)
	sheet.rect(sheet.C_PANEL_LIGHT if back_hover else sheet.C_PANEL, back, 8,
		Color(1, 1, 1, 0.14 if back_hover else 0.07))
	sheet.text_c(back.position.x + back.size.x * 0.5, back.position.y + back.size.y * 0.66,
		"‹  MENU" if bool(sheet.back_to_menu) else "‹  BACK", 13,
		sheet.C_TEXT if back_hover else sheet.C_DIM, sheet.f_bold)
	sheet._add_button("back", back)


	var league_btn := Rect2(vp.x - 24.0 - 138.0, 12.0, 138.0, 44.0)
	var league_hover: bool = league_btn.has_point(sheet.mouse as Vector2)
	sheet.rect(sheet.C_PANEL_LIGHT if league_hover else sheet.C_PANEL, league_btn, 8,
		Color(1, 1, 1, 0.14 if league_hover else 0.07))
	sheet.text_c(league_btn.position.x + league_btn.size.x * 0.5,
		league_btn.position.y + league_btn.size.y * 0.66, "◈  LEAGUE", 13,
		sheet.C_TEXT if league_hover else sheet.C_DIM, sheet.f_bold)
	sheet._add_button("league", league_btn)

static func paint(sheet: Control) -> void:
	var vp: Vector2 = sheet.design_vp()
	sheet.buttons.clear()
	sheet.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.025, 0.032, 0.94))
	sheet.draw_rect(Rect2(0, 0, vp.x, 3), Color(0, 0, 0, 0.5))
	sheet.draw_rect(Rect2(0, vp.y - 3, vp.x, 3), Color(0, 0, 0, 0.5))


	var head: Dictionary = LeagueChrome.picker_header(vp)
	UiChrome.wordmark_c(sheet, vp.x * 0.5, float(head["wordmark_y"]), 12, sheet.f_bold)
	UiChrome.rule(sheet, vp.x * 0.5, float(head["rule_y"]), float(head["rule_w"]))
	if bool(head["title"]):
		UiChrome.text_c(sheet, vp.x * 0.5, float(head["title_y"]), "SELECT FIXTURE",
			int(head["title_size"]), sheet.C_TEXT, sheet.f_bold)
	league_chips(sheet, vp)

	var card_w := minf(vp.x * 0.30, 460.0)
	var card_h := minf(vp.y * 0.32, 250.0)
	var gap := clampf(vp.x * 0.14, 130.0, 220.0)
	var card_y := vp.y * 0.42 - card_h * 0.5
	var home_rect := Rect2(vp.x * 0.5 - gap * 0.5 - card_w, card_y, card_w, card_h)
	var away_rect := Rect2(vp.x * 0.5 + gap * 0.5, card_y, card_w, card_h)

	if sheet.ids.is_empty():
		sheet.text_c(vp.x * 0.5, vp.y * 0.55, "NO SQUAD DATA", 20, sheet.C_DIM, sheet.f_bold)
		return

	var season = LeagueSeason.active
	sheet.followed = LeagueInterestMark.set_of(season.state().get("interests", [])) \
		if season != null else {}
	var home: Dictionary = TeamData.get_team(str(sheet.home_id()))
	var away: Dictionary = TeamData.get_team(str(sheet.away_id()))
	card(sheet, home_rect, home, 0)
	card(sheet, away_rect, away, 1)

	sheet._add_button("team_home", home_rect)
	sheet._add_button("team_away", away_rect)

	var arrow_s := 46.0
	var ay := card_y + card_h * 0.5 - arrow_s * 0.5
	arrow(sheet, Rect2(home_rect.position.x - arrow_s - 12.0, ay, arrow_s, arrow_s), "‹", "home_prev")
	arrow(sheet, Rect2(home_rect.position.x + home_rect.size.x + 12.0, ay, arrow_s, arrow_s), "›", "home_next")
	arrow(sheet, Rect2(away_rect.position.x - arrow_s - 12.0, ay, arrow_s, arrow_s), "‹", "away_prev")
	arrow(sheet, Rect2(away_rect.position.x + away_rect.size.x + 12.0, ay, arrow_s, arrow_s), "›", "away_next")

	sheet.text_c(vp.x * 0.5, card_y + card_h * 0.50, "v", 22, sheet.C_DIM, sheet.f_med)


	var venue: String = LeagueColumns.fit_caption(str(home.get("stadium", "")).to_upper(),
		sheet.f_med, 10, gap - 24.0)
	if venue != "":
		sheet.text_c(vp.x * 0.5, ay + arrow_s + 22.0, venue, 10, sheet.C_DIM, sheet.f_med)

	LeagueChrome.winner_control(sheet, vp, card_y + card_h, str(sheet.winner_mode), sheet.f_bold)


	doors(sheet, vp, card_y + card_h)


	for spec in LeagueChrome.picker_hints(sheet, bool(sheet.touch), bool(sheet.back_to_menu)):
		sheet.text_c(vp.x * 0.5, vp.y + float(spec[0]), str(spec[1]), int(spec[2]),
			spec[3] as Color, sheet.f_med)

	chrome_doors(sheet, vp)

