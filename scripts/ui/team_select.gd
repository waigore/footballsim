extends Control


signal confirmed(home_id: String, away_id: String)
signal cancelled()

signal browse(page: String, id: String)

static var C_PANEL: Color = UiTheme.color(&"panel")
static var C_PANEL_LIGHT: Color = UiTheme.color(&"panel_light")
static var C_BORDER: Color = UiTheme.color(&"border")
static var C_TEXT: Color = UiTheme.color(&"text")
static var C_DIM: Color = UiTheme.color(&"dim")
static var C_GOLD: Color = UiTheme.color(&"gold")

var ids: Array = []


var league_filter := ""
var home_idx := 0
var away_idx := 1


var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)
var buttons: Array = []

var back_to_menu := false

var interest := InterestHold.new()
var menu_layer: InterestLayer = null

var followed := {}


var winner_mode := "draw"

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile
var style_cache := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = UiTheme.bold()
	f_med = UiTheme.medium()
	f_body = UiTheme.body()
	ids = TeamData.team_ids()
	ids.sort()


	interest.club_at = func(p: Vector2) -> String:
		var id := button_at(p)
		if id == "team_home":
			return home_id()
		if id == "team_away":
			return away_id()
		return ""
	interest.season_of = func(): return LeagueSeason.active
	interest.on_changed = func(): queue_redraw()
	menu_layer = InterestLayer.new()
	menu_layer.hold = interest
	menu_layer.screen = self
	add_child(menu_layer)

func setup(home_id: String, away_id: String) -> void:
	if ids.is_empty():
		ids = TeamData.team_ids(league_filter)
		ids.sort()
	home_idx = maxi(0, ids.find(home_id))
	away_idx = maxi(0, ids.find(away_id))
	if away_idx == home_idx:
		away_idx = (home_idx + 1) % ids.size()
	mouse = Vector2(-1000, -1000)


func set_league(competition_id: String) -> void:
	if competition_id == league_filter:
		return
	var home := home_id()
	var away := away_id()
	league_filter = competition_id
	ids = TeamData.team_ids(league_filter)
	ids.sort()
	if ids.is_empty():
		return
	home_idx = maxi(0, ids.find(home))
	away_idx = maxi(0, ids.find(away))
	if away_idx == home_idx:
		away_idx = (home_idx + 1) % ids.size()

func home_id() -> String:
	return str(ids[home_idx]) if not ids.is_empty() else "ENG-MUN1"

func away_id() -> String:
	return str(ids[away_idx]) if not ids.is_empty() else "ENG-MCI1"


func cycle(side: int, dir: int) -> void:
	if ids.size() < 2:
		return
	var index: int = home_idx if side == 0 else away_idx
	index = posmod(index + dir, ids.size())
	if index == (away_idx if side == 0 else home_idx):
		index = posmod(index + dir, ids.size())
	if side == 0:
		home_idx = index
	else:
		away_idx = index

func randomize_fixture() -> void:
	if ids.size() < 2:
		return
	home_idx = randi() % ids.size()
	away_idx = randi() % ids.size()
	if away_idx == home_idx:
		away_idx = (home_idx + 1) % ids.size()

func confirm() -> void:
	confirmed.emit(home_id(), away_id())


func click(id: String) -> void:
	if interest.click(id):
		return
	if id == "back" or id == "cancel":
		cancelled.emit()
	elif id == "home_prev":
		cycle(0, -1)
	elif id == "home_next":
		cycle(0, 1)
	elif id == "away_prev":
		cycle(1, -1)
	elif id == "away_next":
		cycle(1, 1)
	elif id == "random":
		randomize_fixture()
	elif id == "confirm":
		confirm()
	elif id == "league":
		browse.emit(WikiModel.LEAGUE, "")
	elif id.begins_with("league:"):
		set_league(id.substr(7))
	elif id.begins_with("win:"):
		winner_mode = id.substr(4)
	elif id == "team_home":
		browse.emit(WikiModel.TEAM, home_id())
	elif id == "team_away":
		browse.emit(WikiModel.TEAM, away_id())

func key(code: int) -> bool:
	if code == KEY_LEFT or code == KEY_A:
		cycle(0, -1)
	elif code == KEY_RIGHT or code == KEY_D:
		cycle(0, 1)
	elif code == KEY_UP or code == KEY_W:
		cycle(1, -1)
	elif code == KEY_DOWN or code == KEY_S:
		cycle(1, 1)
	elif code == KEY_TAB:
		randomize_fixture()
	elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		confirm()
	elif code == KEY_ESCAPE:
		cancelled.emit()
	elif code == KEY_L:
		browse.emit(WikiModel.LEAGUE, "")
	elif code >= KEY_1 and code <= KEY_9:
		var row := LeagueChrome.league_key_row(code, LeagueChrome.competition_rows())
		if row.is_empty():
			return false
		set_league(str(row["id"]))
	else:
		return false
	return true

func button_at(p: Vector2) -> String:
	if interest.is_open():
		return interest.menu.hit(p, design_vp())
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return b["id"]
	return ""


func _process(d: float) -> void:
	if interest.tick(d):
		queue_redraw()
	queue_redraw()

func _style(c: Color, r: int = 10, bc: Color = C_BORDER, bw: int = 1) -> StyleBoxFlat:
	var key := "%s|%d|%s|%d" % [c.to_html(), r, bc.to_html(), bw]
	if style_cache.has(key):
		return style_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.border_color = bc
	sb.set_border_width_all(bw)
	style_cache[key] = sb
	return sb

func rect(c: Color, r: Rect2, radius: int = 10, bc: Color = C_BORDER) -> void:
	draw_style_box(_style(c, radius, bc), r)

func text(pos: Vector2, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else f_med
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, ChromeDensity.read_size(size), color)

func text_c(center_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else f_med
	var px := ChromeDensity.read_size(size)
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	text(Vector2(center_x - w * 0.5, y), s, px, color, f)

func _add_button(id: String, r: Rect2) -> void:
	buttons.append({"id": id, "rect": r})


static func clubs_line(count: int, competition_name: String) -> String:
	if competition_name == "":
		return "%d CLUBS" % count
	return "%d %s CLUBS" % [count, competition_name.to_upper()]


func design_vp() -> Vector2:
	return get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)


func back_rect(vp: Vector2) -> Rect2:
	return Rect2(24.0, 12.0, 116.0, 44.0)

func _draw() -> void:
	TeamSelectPaint.paint(self)
