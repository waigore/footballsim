extends GdToolsTest


func test_the_theme_resource_loads() -> void:
	assert_true(UiTheme.has_theme(), "the Theme resource did not load from %s" % UiTheme.PATH)
	var theme := UiTheme.theme()
	assert_not_null(theme, "the Theme resource is null")
	assert_not_null(theme.default_font, "the Theme has no default font")


func test_every_palette_key_lives_in_the_theme() -> void:
	var theme := UiTheme.theme()
	assert_not_null(theme, "the Theme resource is null")
	for key in UiTheme.color_keys():
		assert_true(theme.has_color(key, &"Colors"), "the Theme is missing colour %s" % key)
		assert_eq(UiTheme.color(key), theme.get_color(key, &"Colors"),
			"colour %s did not read back from the Theme" % key)


func test_the_chrome_modules_read_the_theme() -> void:
	assert_eq(UiChrome.C_BG, UiTheme.color(&"bg"), "UiChrome kept its own background")
	assert_eq(UiChrome.C_PANEL, UiTheme.color(&"panel"), "UiChrome kept its own panel")
	assert_eq(UiChrome.C_PANEL_LIGHT, UiTheme.color(&"panel_light"), "UiChrome kept a second panel")
	assert_eq(UiChrome.C_BORDER, UiTheme.color(&"border"), "UiChrome kept its own border")
	assert_eq(UiChrome.C_TEXT, UiTheme.color(&"text"), "UiChrome kept its own ink")
	assert_eq(UiChrome.C_DIM, UiTheme.color(&"dim"), "UiChrome kept its own dim")
	assert_eq(UiChrome.C_SOFT, UiTheme.color(&"soft"), "UiChrome kept its own soft ink")
	assert_eq(UiChrome.C_GOLD, UiTheme.color(&"gold"), "UiChrome kept its own gold")
	assert_eq(UiChrome.C_LIVE, UiTheme.color(&"live"), "UiChrome kept its own live green")
	assert_eq(UiChrome.C_DANGER, UiTheme.color(&"danger"), "UiChrome kept its own danger red")


func test_the_forks_point_at_the_same_palette() -> void:
	assert_eq(WikiChrome.PANEL, UiTheme.color(&"panel"), "the encyclopedia kept a second palette")
	assert_eq(WikiChrome.PANEL_LIGHT, UiTheme.color(&"panel_light"), "the encyclopedia kept a second panel")
	assert_eq(WikiChrome.BORDER, UiTheme.color(&"border"), "the encyclopedia kept a second border")
	assert_eq(WikiChrome.TEXT, UiTheme.color(&"text"), "the encyclopedia kept its own ink")
	assert_eq(WikiChrome.GOLD, UiTheme.color(&"gold"), "the encyclopedia kept its own gold")
	assert_eq(WikiChrome.DIM, UiTheme.color(&"soft"), "the encyclopedia kept a third dim")
	assert_eq(HudChrome.BORDER, UiTheme.color(&"border"), "the HUD kept a second border")
	assert_eq(MenuScreen.FOOT, UiTheme.color(&"soft"), "the menu kept its own footer ink")


func test_the_theme_carries_the_fonts() -> void:
	var bold := UiTheme.bold()
	var med := UiTheme.medium()
	var body := UiTheme.body()
	assert_not_null(bold, "the Theme has no bold font")
	assert_not_null(med, "the Theme has no medium font")
	assert_not_null(body, "the Theme has no body font")
	var fonts := UiChrome.fonts()
	assert_eq(fonts.get("bold"), bold, "UiChrome loaded its own bold font")
	assert_eq(fonts.get("med"), med, "UiChrome loaded its own medium font")
	assert_eq(fonts.get("body"), body, "UiChrome loaded its own body font")


func test_every_control_role_carries_a_font_size() -> void:
	for role in UiTheme.roles():
		assert_gt(UiTheme.font_size(role), 0, "role %s has no font size in the Theme" % role)


func test_every_shared_style_exists() -> void:
	for name in [&"panel", &"panel_light", &"sheet", &"chip"]:
		assert_not_null(UiTheme.box(&"Panel", name), "Panel/%s is missing" % name)
	for name in [&"normal", &"hover", &"pressed", &"primary", &"primary_hover", &"danger"]:
		assert_not_null(UiTheme.box(&"Button", name), "Button/%s is missing" % name)
	var door := UiTheme.box(&"Button", &"normal")
	assert_gt(door.bg_color.a, 0.0, "the default door has no fill")
	assert_gt(door.corner_radius_top_left, 0, "the default door has no radius")


func test_a_plain_control_inherits_the_theme() -> void:
	var theme := UiTheme.theme()
	assert_not_null(theme, "the Theme resource is null")
	var button := Button.new()
	button.theme = theme
	add_child(button)
	assert_gt(button.get_theme_font_size(&"font_size"), 0, "a themed door took no font size")
	assert_not_null(button.get_theme_stylebox(&"normal"), "a themed door took no style")
	button.queue_free()


func test_the_theme_owns_the_readability_floor() -> void:
	assert_gt(UiTheme.font_size(&"Caption"), 0, "the caption role has no size")
	assert_eq(ChromeDensity.read_size(1), ChromeDensity.MIN_READ,
		"the legacy reading floor moved without the Theme")
