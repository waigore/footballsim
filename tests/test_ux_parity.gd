extends GdToolsTest


const DESKTOP := Vector2(1600, 900)
const PHONE := Vector2(913, 411)
const PHONE_PORTRAIT := Vector2(411, 914)
const TABLET := Vector2(1024, 600)

func _ids_from_doors(rects: Array) -> Array:
	var out: Array = []
	for b in rects:
		out.append(str(b["id"]))
	return out

func _assert_not_weaker(desktop: Array, handheld: Array, label: String) -> void:
	for id in desktop:
		assert_true(handheld.has(id), "%s: handheld lost intent '%s'" % [label, id])

func _settings_ids(vp: Vector2) -> Array:
	var sheet := SettingsScreen.new()
	var ids: Array = []
	for r in [
		SettingsLayout.minus_rect(vp),
		SettingsLayout.plus_rect(vp),
		SettingsLayout.track_rect(vp),
		SettingsLayout.hud_toggle_rect(vp),
		SettingsLayout.back_rect(vp),
	]:
		var id: String = sheet.button_at((r as Rect2).get_center(), vp)
		assert_gt(id.length(), 0, "settings door empty at %s" % vp)
		if not ids.has(id):
			ids.append(id)
	for seg in SettingsLayout.seg_rects(vp):
		var sid: String = sheet.button_at((seg as Rect2).get_center(), vp)
		assert_true(sid.begins_with("mode:"), "settings mode segment empty at %s" % vp)
		if not ids.has(sid):
			ids.append(sid)
	return ids

func _panel_nav_ids(vp: Vector2, touch: bool) -> Array:
	var panel := LeaguePanel.new()
	panel.touch = touch
	panel.cups = true
	panel.europe_on = true
	panel.open()
	panel.settle()
	var ids: Array = []
	var list: Array = panel.items()
	for i in range(list.size()):
		var item: Dictionary = list[i]
		var hit: String = panel.hit(panel.item_rect(vp, i).get_center(), vp)
		assert_eq(hit, str(item["id"]), "panel row %s missed at %s (touch=%s)" % [item["id"], vp, touch])
		ids.append(hit)
	return ids

func _control_ids(vp: Vector2, touch: bool) -> Array:
	var band := HudControlsBand.new()
	var paint := HudPaint.new(HudChrome.new(), vp)
	var game := {"paused": false, "mode": Prefs.DEFAULT_MODE, "speed": 1.0,
		"fast_mode": false, "camera_follow": true}
	var ids: Array = []
	for spec in band.control_specs(paint, game, touch):
		ids.append(str(spec[0]))
	return ids


func test_menu_door_intents_match_across_viewports() -> void:
	for has_match in [false, true]:
		var desk: Array = MenuScreen.door_ids(has_match)
		for vp in [PHONE, PHONE_PORTRAIT, TABLET]:
			var doors: Array = _ids_from_doors(MenuScreen.door_rects(vp, has_match))
			assert_eq(doors, desk, "menu door set drifted at %s (match=%s)" % [vp, has_match])
			for b in MenuScreen.door_rects(vp, has_match):
				var r: Rect2 = b["rect"]
				assert_gte(r.size.y, MenuScreen.DOOR_MIN, "menu door too short at %s" % vp)
				assert_gte(r.size.x, 44.0, "menu door too narrow at %s" % vp)


func test_settings_intents_match_across_viewports() -> void:
	var desk := _settings_ids(DESKTOP)
	assert_true(desk.has("track"), "desktop settings lost volume track")
	assert_true(desk.has("hud"), "desktop settings lost HUD switch")
	assert_true(desk.has("back"), "desktop settings lost back")
	assert_eq(Prefs.MODES.size(), 3, "match-view modes drifted")
	for mode in Prefs.MODES:
		assert_true(desk.has("mode:%s" % mode), "desktop settings lost mode %s" % mode)
	for vp in [PHONE, PHONE_PORTRAIT, TABLET]:
		_assert_not_weaker(desk, _settings_ids(vp), "settings@%s" % vp)


func test_confirm_intents_match_across_viewports() -> void:
	var prompt := ConfirmPrompt.new()
	var desk_ids: Array = []
	for r in [ConfirmPrompt.confirm_rect(DESKTOP), ConfirmPrompt.cancel_rect(DESKTOP)]:
		desk_ids.append(prompt.button_at(r.get_center(), DESKTOP))
	assert_eq(desk_ids, ["confirm", "cancel"], "desktop confirm intents drifted")
	for vp in [PHONE, PHONE_PORTRAIT, TABLET]:
		var ids: Array = []
		for r in [ConfirmPrompt.confirm_rect(vp), ConfirmPrompt.cancel_rect(vp)]:
			var rect: Rect2 = r
			assert_gte(rect.size.y, 44.0, "confirm door too short at %s" % vp)
			ids.append(prompt.button_at(rect.get_center(), vp))
		assert_eq(ids, desk_ids, "confirm intents drifted at %s" % vp)


func test_league_panel_intents_match_across_viewports() -> void:
	var desk := _panel_nav_ids(DESKTOP, false)
	assert_eq(desk.size(), LeaguePanel.ITEMS.size(), "desktop panel lost a nav row")
	for vp in [PHONE, TABLET]:
		_assert_not_weaker(desk, _panel_nav_ids(vp, true), "league panel@%s" % vp)

	for pair in [[DESKTOP, false], [PHONE, true], [PHONE_PORTRAIT, true]]:
		var vp: Vector2 = pair[0]
		var touch: bool = pair[1]
		var panel := LeaguePanel.new()
		panel.touch = touch
		panel.close()
		panel.settle()
		var tab: Rect2 = panel.tab_rect(vp)
		assert_gte(minf(tab.size.x, tab.size.y), 24.0, "panel tab collapsed at %s" % vp)
		assert_eq(panel.hit(tab.get_center(), vp), "panel",
			"closed panel tab is not hittable at %s (touch=%s)" % [vp, touch])


func test_hud_control_intents_are_not_weaker_on_phone() -> void:
	var desk := _control_ids(DESKTOP, false)
	var phone := _control_ids(PHONE, true)
	_assert_not_weaker(desk, phone, "HUD controls")

	assert_true(phone.has("teams"), "phone HUD lost the teams door")
	assert_false(desk.has("teams"), "desktop HUD unexpectedly gained teams on the bar")


func test_weekday_reveal_is_not_hover_only_on_touch() -> void:
	var over := DateOverlay.new()
	over.screen = {
		"mouse": Vector2.ZERO, "hints": DateHints.new(), "rows_hints": DateHints.new(),
		"touch": false, "holding": false,
	}
	assert_true(over.showing(), "desktop hover should reveal the weekday")
	over.screen["touch"] = true
	assert_false(over.showing(), "touch revealed the weekday without a hold")
	over.screen["holding"] = true
	assert_true(over.showing(), "touch hold did not reveal the weekday")
