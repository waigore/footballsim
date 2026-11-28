extends GdToolsTest


var P := TestScratch.file("test_attr_view_issue411.cfg")


func after_each() -> void:
	if FileAccess.file_exists(P):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(P))


func _page(mode: String) -> Dictionary:
	var card := FCRatings.synthesize(78.0, "CM", 0)
	return {"role": "CM", "subs": card, "extras": {"international_reputation": 2},
		"ratings_matched": true, "view": mode}


func test_the_outfield_sheet_holds_every_non_glove_sub_stat() -> void:
	var cells := AttrView.flat("CM", FCRatings.synthesize(78.0, "CM", 0))
	var outfield := (FCRatings.sub_stat_keys() as Array).filter(
		func(k): return not str(k).begins_with("gk_"))
	assert_eq(cells.size(), outfield.size(), "the outfield sheet is not the full field set")
	for cell in cells:
		assert_between(int(cell[1]), 1, 99, "a sheet value fell outside a card range")


func test_the_keeper_sheet_shows_the_five_glove_stats_only() -> void:
	var cells := AttrView.flat("GK", FCRatings.synthesize(78.0, "GK", 0))
	assert_eq(cells.size(), 5, "the keeper sheet is not the glove set")


func test_every_sheet_key_has_a_short_label_and_a_title() -> void:
	for key in FCRatings.sub_stat_keys():
		if str(key).begins_with("gk_") and key != "gk_reflexes":
			continue
		assert_true(AttrView.short(str(key)).length() <= 4, "%s has no short label" % key)
		assert_ne(AttrView.title(str(key)), "", "%s has no title" % key)


func cells_in_sheet() -> int:
	return (FCRatings.sub_stat_keys() as Array).filter(
		func(k): return not str(k).begins_with("gk_")).size()


func test_grouped_rows_cover_the_sheet_in_six_bands() -> void:
	var rows := AttrView.rows("ST", FCRatings.synthesize(78.0, "ST", 0))
	assert_eq(rows.size(), 6, "the sheet is not grouped into six bands")
	var total := 0
	for row in rows:
		total += (row["cells"] as Array).size()
	assert_eq(total, cells_in_sheet(), "the grouped bands lost sub-stats")


func test_the_player_page_offers_both_modes_as_a_door() -> void:
	var page := WikiPlayer.page(TestSquad.id_of("ENG-MUN1", "B. Fernandes"), "SIMPLIFIED")
	var doors := _doors(page)
	assert_eq(doors.size(), 1, "the player page has no view door")
	var ids := (doors[0]["items"] as Array).map(func(d): return str(d["id"]))
	assert_true(ids.has("attrs:SIMPLIFIED"), "the page cannot go back to Simplified")
	assert_true(ids.has("attrs:FULL"), "the page cannot open the Full sheet")


func test_the_simplified_page_shows_face_bars_and_no_grid() -> void:
	var page := WikiPlayer.page(TestSquad.id_of("ENG-MUN1", "B. Fernandes"), "SIMPLIFIED")
	assert_eq(_kinds(page).count("bars"), 1, "Simplified lost its face bars")
	assert_eq(_kinds(page).count("grid"), 0, "Simplified opened the full sheet")
	assert_true(_bars_of(page) > 0, "the face bars carry no value")


func test_the_full_page_replaces_the_bars_with_the_sub_stat_grid() -> void:
	var page := WikiPlayer.page(TestSquad.id_of("ENG-MUN1", "B. Fernandes"), "FULL")
	assert_eq(_kinds(page).count("bars"), 0, "Full kept the face bars")
	assert_eq(_kinds(page).count("grid"), 1, "Full did not open the sub-stat grid")
	var grid: Dictionary = _first(page, "grid")
	assert_eq((grid.get("groups", []) as Array).size(), 6, "the grid is not the six bands")
	assert_true(int(grid.get("cols", 0)) >= 2, "the grid is not multi-column")


func test_the_squad_table_gains_the_face_columns_in_full() -> void:
	var simple := _squad_head(WikiTeam.page("ENG-MUN1"), "SIMPLIFIED")
	var full := _squad_head(WikiTeam.page("ENG-MUN1"), "FULL")
	assert_eq(simple.size(), 4, "the Simplified squad table lost a column")
	assert_eq(full.size(), 10, "the Full squad table did not add the six face columns")
	assert_eq(str(full[4]), "PAC", "the first face column is not pace")


func test_the_keeper_squad_row_does_not_invent_a_face_bar() -> void:
	var page := WikiTeam.page("ENG-MUN1")
	assert_true(page.has("blocks"), "the club page did not build")
	var bars := WikiTeam._bars({"role": "GK", "gk": {"div": 80, "han": 78, "kic": 70, "ref": 84, "spd": 60}})
	assert_eq(int(bars[0]), 80, "the keeper row lost diving")
	assert_eq(int(bars[5]), 0, "a keeper row invented a physical bar")


func _kinds(page: Dictionary) -> Array:
	return (page.get("blocks", []) as Array).map(func(b): return str(b.get("k", "")))


func _doors(page: Dictionary) -> Array:
	return (page.get("blocks", []) as Array).filter(func(b): return str(b.get("k", "")) == "door")


func _first(page: Dictionary, kind: String) -> Dictionary:
	for block in page.get("blocks", []):
		if str(block.get("k", "")) == kind:
			return block
	return {}


func _bars_of(page: Dictionary) -> int:
	var bars := _first(page, "bars")
	return (bars.get("items", []) as Array).size()


func _squad_head(page: Dictionary, mode: String) -> Array:
	var rebuilt := WikiTeam.page("ENG-MUN1", mode)
	for block in rebuilt.get("blocks", []):
		if str(block.get("k", "")) == "table" and (block.get("cols", []) as Array).size() > 0 \
				and str((block["cols"] as Array)[1]) == "PLAYER":
			return block["cols"]
	return []


func test_the_match_card_keeps_its_box_in_both_modes() -> void:
	var card := HudPlayerCard.new(Color.BLACK, Color.GOLD, Color.WHITE, Color.GRAY)
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		card.mode = "SIMPLIFIED"
		var simple := card.rect_for(vp)
		card.mode = "FULL"
		var full := card.rect_for(vp)
		assert_eq(simple, full, "the card changed size when the reading changed at %s" % vp)
		assert_false(full.intersects(HudLayout.stats_rect(vp)), "the card covers the stats at %s" % vp)
		assert_false(full.intersects(HudLayout.commentary_rect(vp)), "the card covers the ticker at %s" % vp)


func test_the_match_card_door_sits_inside_its_own_box() -> void:
	var card := HudPlayerCard.new(Color.BLACK, Color.GOLD, Color.WHITE, Color.GRAY)
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(800, 360)]:
		var box := card.rect_for(vp)
		var door: Rect2 = card.attrs_rect(vp)
		var profile: Rect2 = card.profile_rect(vp)
		assert_true(box.encloses(door), "the attribute door left the card at %s" % vp)
		assert_true(box.encloses(profile), "the profile door left the card at %s" % vp)
		assert_false(door.intersects(profile), "the two doors overlap at %s" % vp)
