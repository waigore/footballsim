extends GdToolsTest

## One date form for the whole game (#99): `15/AUG/2026` everywhere, with the
## weekday kept for the hover hint instead of crowding the date itself. The
## overlay is driven here through plain dictionaries, so the pointer plumbing is
## measured without a rendered frame.

func _screen(chrome: DateHints) -> Dictionary:
	return {
		"mouse": Vector2(30.0, 20.0), "hints": chrome, "rows_hints": DateHints.new(),
		"touch": false, "holding": false,
	}

func test_a_date_reads_as_day_month_year() -> void:
	assert_eq(FixtureCalendar.day_label("2026-08-15"), "15/AUG/2026", "the date form moved")
	assert_eq(FixtureCalendar.day_label("2026-08-05"), "5/AUG/2026", "a day took a leading zero")
	assert_eq(FixtureCalendar.day_label("2027-12-31"), "31/DEC/2027", "the last day of a year is wrong")

func test_a_non_date_reads_as_nothing() -> void:
	assert_eq(FixtureCalendar.day_label(""), "", "an empty field produced a date")
	assert_eq(FixtureCalendar.day_label("2026-08"), "", "a month key produced a day")
	assert_eq(FixtureCalendar.weekday_label(""), "", "an empty field produced a weekday")

func test_the_weekday_follows_the_date() -> void:
	assert_eq(FixtureCalendar.weekday_label("2026-08-15"), "SAT", "a Saturday is mislabelled")
	assert_eq(FixtureCalendar.weekday_label("2026-08-17"), "MON", "a Monday is mislabelled")

func test_a_strip_answers_only_for_the_date_it_registered() -> void:
	var hints := DateHints.new()
	hints.add(Rect2(10.0, 10.0, 60.0, 12.0), "2026-08-15")
	assert_eq(str(hints.at(Vector2(20.0, 15.0)).get("date", "")), "2026-08-15",
		"the strip lost its date")
	assert_true(hints.at(Vector2(5.0, 5.0)).is_empty(), "a point on no strip answered")
	hints.add(Rect2(10.0, 10.0, 60.0, 12.0), "2026-08-15")
	assert_eq(hints.zones.size(), 1, "re-registering the same strip grew the list")
	hints.add(Rect2(10.0, 10.0, 60.0, 12.0), "")
	assert_eq(hints.zones.size(), 1, "a strip with no date was registered")
	hints.clear()
	assert_true(hints.at(Vector2(20.0, 15.0)).is_empty(), "clear left a strip behind")

func test_a_label_reports_the_strip_it_wrote() -> void:
	var font: Font = UiChrome.fonts()["bold"]
	var left := DateHints.strip(font, "15/AUG/2026", Vector2(100.0, 40.0), 10)
	assert_eq(left.position, Vector2(100.0, 30.0), "a strip starts above its baseline")
	assert_gt(left.size.x, 0.0, "a strip has no width")
	var right := DateHints.strip_right(font, "15/AUG/2026", 200.0, 40.0, 10)
	assert_eq(right.end.x, 200.0, "a right-aligned strip does not end at its edge")
	assert_eq(right.size.x, left.size.x, "the two strips measure differently")
	assert_eq(DateHints.width(font, "15/AUG/2026", 10), left.size.x, "width and strip disagree")

func test_an_overlay_attaches_above_the_body() -> void:
	var sheet := Control.new()
	var body := Control.new()
	sheet.add_child(body)
	var over := DateOverlay.attach(sheet, body, true)
	assert_eq(sheet.get_child_count(), 2, "the overlay was not added to the sheet")
	assert_eq(sheet.get_child(sheet.get_child_count() - 1), over, "the overlay does not paint last")
	assert_true(over.rows_local, "the row space was not recorded")
	assert_eq(over.body, body, "the overlay does not watch the body")
	sheet.free()

func test_the_overlay_reads_the_chrome_before_the_rows() -> void:
	var chrome := DateHints.new()
	chrome.add(Rect2(10.0, 10.0, 60.0, 12.0), "2026-08-15")
	var over := DateOverlay.new()
	over.screen = _screen(chrome)
	assert_eq(str(over.zone_at().get("date", "")), "2026-08-15", "the chrome date was not found")
	over.screen["mouse"] = Vector2(300.0, 20.0)
	assert_true(over.zone_at().is_empty(), "a point on no strip answered")
	over.screen = null
	assert_true(over.zone_at().is_empty(), "an overlay with no sheet answered")

func test_rows_are_read_in_the_space_they_were_laid_out_in() -> void:
	var rows := DateHints.new()
	rows.add(Rect2(10.0, 100.0, 60.0, 12.0), "2026-08-15")
	var over := DateOverlay.new()
	over.screen = _screen(DateHints.new())
	over.screen["rows_hints"] = rows
	over.body = {"position": Vector2(0.0, 50.0), "size": Vector2(400.0, 300.0),
		"scroll": 4.0, "hscroll": 6.0}
	# A league row sits in design space: the pointer moves back past the scroll.
	over.screen["mouse"] = Vector2(16.0, 100.0)
	assert_eq(str(over.zone_at().get("date", "")), "2026-08-15", "a league row was not found")
	# An encyclopedia row sits inside the body window instead.
	over.rows_local = true
	over.screen["mouse"] = Vector2(16.0, 150.0)
	assert_eq(str(over.zone_at().get("date", "")), "2026-08-15", "a page row was not found")
	over.screen["mouse"] = Vector2(16.0, 10.0)
	assert_true(over.zone_at().is_empty(), "a point outside the window answered")

func test_a_touch_screen_reveals_on_a_held_press_only() -> void:
	var over := DateOverlay.new()
	over.screen = _screen(DateHints.new())
	assert_true(over.showing(), "a mouse should reveal on hover")
	over.screen["touch"] = true
	assert_false(over.showing(), "a touch screen revealed without a press")
	over.screen["holding"] = true
	assert_true(over.showing(), "a held press did not reveal the weekday")
	over.screen = null
	assert_false(over.showing(), "an overlay with no sheet showed a bubble")
