class_name HudCommentary
extends RefCounted

## Bottom-left commentary ticker. The newest engine event owns the panel while
## it is fresh, then a live description of the pitch takes over. Split out of
## hud.gd so the broadcast overlay keeps its P3 size budget.

var text := ""
var label := ""
var minute := 0
var hold := 0.0
var ev_id := -1
var last_clock := -1.0

var panel_col := Color.BLACK
var gold := Color.WHITE
var text_col := Color.WHITE
var dim := Color.GRAY
var _box := StyleBoxFlat.new()

func _init(panel: Color, accent: Color, ink: Color, muted: Color) -> void:
	panel_col = panel
	gold = accent
	text_col = ink
	dim = muted
	_box.bg_color = panel
	_box.set_corner_radius_all(10)
	_box.set_border_width_all(1)
	_box.border_color = Color(1, 1, 1, 0.07)

## Keep the ticker honest: narrate the newest event while it is fresh, then
## describe the actual pitch state. A rewind (highlight replay) refreshes the
## cue immediately instead of leaving a future event on screen.
func tick(d: float, engine, game) -> void:
	if engine == null or game == null:
		return
	if game.paused:
		return
	var evs: Array = engine.events
	if evs.is_empty():
		# Fresh match / restart: forget the previous fixture's lines.
		text = ""
		label = ""
		ev_id = -1
		last_clock = -1.0
		return
	hold = maxf(0.0, hold - d)
	var now: float = float(engine.clock)
	var rewound: bool = now < last_clock - 0.75
	last_clock = now
	var ev: Dictionary = evs[evs.size() - 1]
	var eid: int = int(ev.get("id", -1))
	if eid != ev_id or rewound:
		ev_id = eid
		label = str(ev.get("type", "")).to_upper().replace("_", " ")
		text = str(ev.get("text", ""))
		minute = int(ev.get("minute", 0))
		hold = _freshness(label)
		if game.mode != "full" and game.fast_mode:
			hold *= 0.55
	if hold <= 0.0 or text == "":
		# A finished match has no live play left to narrate, so its last line —
		# the whistle — stays on screen instead of falling back to LIVE (#276).
		if str(engine.phase) == "full_time":
			return
		label = "LIVE"
		text = CommentaryLive.live(engine)
		minute = int(engine.minute_of(engine.clock))

## How long a line of this type stays on screen, in real seconds.
func _freshness(kind: String) -> float:
	var h := 3.2
	match kind:
		"GOAL":
			h = 5.5
		"SAVE", "SHOT", "HEADER", "BLOCK", "PENALTY", "PENALTY TAKEN":
			h = 4.2
		"CARD", "FOUL", "OFFSIDE", "HANDBALL", "INJURY":
			h = 3.6
		"TACTICS", "SUBSTITUTION":
			h = 5.0
		"CLEARANCE", "CROSS":
			h = 2.6
	return h

func _fit(s: String, max_chars: int) -> String:
	if s.length() <= max_chars:
		return s
	var cut := s.substr(0, max_chars)
	var space := cut.rfind(" ")
	if space > max_chars - 18:
		cut = cut.substr(0, space)
	return cut + "…"

## Sits above the control bar so the buttons are never covered.
func draw(c: CanvasItem, vp: Vector2, f_bold: Font, f_med: Font, game) -> void:
	var box := HudLayout.commentary_rect(vp)
	var w := box.size.x
	var h := box.size.y
	var x := box.position.x
	var y := box.position.y
	c.draw_style_box(_box, Rect2(x, y, w, h))
	c.draw_rect(Rect2(x + 1, y + 8, 3, h - 16), gold)
	if text == "":
		var home: Dictionary = game.engine.teams[0]["data"]
		var away: Dictionary = game.engine.teams[1]["data"]
		_text(c, Vector2(x + 16, y + 24), "%s IS READY" % str(home.get("stadium", "THE GROUND")).to_upper(), 13, text_col, f_bold)
		_text(c, Vector2(x + 16, y + 40), "%s v %s" % [home["name"], away["name"]], 10, dim, f_med)
		return
	var tag: String = label
	if game.in_highlight:
		tag = "◀ " + tag
	var col := gold if label == "GOAL" else text_col
	_text(c, Vector2(x + 16, y + 21), "%d'  %s" % [minute, tag], 10, gold, f_bold)
	_text(c, Vector2(x + 16, y + 39), _fit(text, int(w / 7.0)), 13, col, f_med)

func _text(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font) -> void:
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
