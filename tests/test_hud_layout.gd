extends GdToolsTest

## Broadcast chrome: the commentary ticker sits above the control bar, so it
## must never cover a button and must stay inside the viewport at every size a
## desktop or handheld build can present.

const SIZES := [
	Vector2(1600, 900),
	Vector2(1920, 1080),
	Vector2(1280, 720),
	Vector2(1024, 600),
	Vector2(720, 1280),
	Vector2(2560, 1440),
]

func test_ticker_never_covers_the_control_bar() -> void:
	for vp in SIZES:
		var panel: Rect2 = HudLayout.commentary_rect(vp)
		var bar: Rect2 = HudLayout.controls_rect(vp)
		assert_false(panel.intersects(bar), "the commentary panel covers a control at %s" % vp)
		assert_false(bar.intersects(panel), "a control covers the commentary panel at %s" % vp)

func test_bottom_strip_stays_inside_the_viewport() -> void:
	for vp in SIZES:
		var panel: Rect2 = HudLayout.commentary_rect(vp)
		var bar: Rect2 = HudLayout.controls_rect(vp)
		assert_gte(panel.position.x, 0.0, "panel starts off-screen at %s" % vp)
		assert_lte(panel.position.x + panel.size.x, vp.x, "panel runs off the right edge at %s" % vp)
		assert_lte(panel.position.y + panel.size.y, vp.y, "panel runs off the bottom at %s" % vp)
		assert_gte(bar.position.x, 0.0, "control bar starts off-screen at %s" % vp)
		assert_lte(bar.position.x + bar.size.x, vp.x, "control bar runs off the right edge at %s" % vp)
