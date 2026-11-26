class_name LeagueSave
extends RefCounted

## One named god-mode season saved as a self-contained SQLite file.
##
## Creating a save copies the shipped seed (competitions, clubs, squads) into
## `user://saves/<slug>.sqlite`, adds the league tables the season owns —
## fixtures, results, match events, live table, season player stats — stamps a
## `save_meta` row per setting, and copies each active competition's regulations
## into its own `league_rules` row. Nothing about a save is shared with the
## single-match cache, so a seed refresh can never disturb a season in progress.
##
## A save can run more than one competition at once. One file, one clock, one
## `league_table` and `league_fixture` set keyed by `competition_id`; the active
## set lives in `save_competition` and in `save_meta.competitions`.

const DEFAULT_DIR := "user://saves"
const EXT := ".sqlite"

## Save directory this run uses (tests point it at a scratch folder).
static var dir := DEFAULT_DIR
static var current: LeagueSave = null

var slug := ""
var path := ""
var meta: Dictionary = {}
## The primary competition's regulations (the first active one). Kept flat so a
## single-league caller and a save written before multi-league read the same
## shape; `rules_by` is the full per-competition map.
var rules: Dictionary = {}
var rules_by: Dictionary = {}
## Active competition ids, in the order the player chose them.
var actives: Array = []
static var last_error := ""

# ------------------------------------------------------------------ files ---

## Copy the seed and lay out an empty multi-league season. Fixtures and the
## table are filled per active competition by the season layer (`LeagueSeason`),
## so this file stays about storage.
##
## `rules` is either one flat regulations dictionary (the same template for every
## active league) or a map of competition id -> regulations.
static func create(name: String, rules: Dictionary, seed: int = 0,
		competitions: Array = ["PL"]) -> LeagueSave:
	if not FileAccess.file_exists(PLDatabase.SEED_PATH):
		last_error = "the shipped seed is missing"
		return null
	DirAccess.make_dir_recursive_absolute(dir)
	var save := LeagueSave.new()
	save.slug = LeagueSaveCatalog.unique_slug(name)
	save.path = dir.path_join(save.slug + EXT)
	var bytes := FileAccess.get_file_as_bytes(PLDatabase.SEED_PATH)
	var out := FileAccess.open(save.path, FileAccess.WRITE)
	if out == null or bytes.is_empty():
		last_error = "cannot write %s" % save.path
		return null
	out.store_buffer(bytes)
	out.close()
	if not PLDatabase.open_path(save.path):
		last_error = "cannot open %s" % save.path
		return null
	LeagueSaveSchema.migrate()
	save.meta = {}
	save.put_meta("name", name.strip_edges() if name.strip_edges() != "" else "New League")
	save.put_meta("created_at", Time.get_datetime_string_from_system(true, true))
	save.put_meta("status", "in_progress")
	save.put_meta("seed", str(seed))
	save.put_meta("matchday", "1")
	save.actives = LeagueSaveSchema.valid(competitions)
	save.put_meta("competitions", ",".join(PackedStringArray(save.actives)))
	for i in range(save.actives.size()):
		var cid := str(save.actives[i])
		PLDatabase.execute(
			"INSERT INTO save_competition (competition_id, active, position) VALUES (?, 1, ?) "
			+ "ON CONFLICT(competition_id) DO UPDATE SET active = 1, position = excluded.position;",
			[cid, i])
	var primary_rules := _rules_for_input(rules, str(save.actives[0]) if not save.actives.is_empty() else "PL")
	save.put_meta("calendar_mode", str(primary_rules["calendar_mode"]))
	save.put_meta("advance_mode", str(primary_rules["advance_mode"]))
	for cid in save.actives:
		LeagueRules.write(str(cid), _rules_for_input(rules, str(cid)))
	save.rules_by = LeagueRules.read_all()
	save.rules = save.rules_by.get(str(save.actives[0]), primary_rules)
	var season := PLDatabase.row("SELECT value FROM metadata WHERE key = 'season_label';")
	save.put_meta("season_label", str(season.get("value", "")))
	PLRepository.shared().invalidate()
	current = save
	return save

## Coerce the create-time rules argument into one competition's flat dictionary.
static func _rules_for_input(rules: Dictionary, competition_id: String) -> Dictionary:
	if rules.has("win_points") or rules.is_empty():
		var base := LeagueRules.defaults("generated", "fixture_days", competition_id)
		for key in rules.keys():
			if base.has(key):
				base[key] = rules[key]
		return LeagueRules.normalize(base)
	return LeagueRules.normalize(rules.get(competition_id, {}) as Dictionary)

## Open an existing save and bind the game's static connection to it.
static func open(slug_or_path: String) -> LeagueSave:
	var file := slug_or_path
	if not file.ends_with(EXT):
		file = dir.path_join(slug_or_path + EXT)
	if not FileAccess.file_exists(file):
		return null
	if not PLDatabase.open_path(file):
		return null
	PLRepository.shared().invalidate()
	LeagueSaveSchema.migrate()
	var save := LeagueSave.new()
	save.path = file
	save.slug = file.get_file().trim_suffix(EXT)
	save.meta = save.read_meta()
	if save.meta.is_empty():
		PLDatabase.reset()
		return null
	save.actives = LeagueSaveSchema.valid(LeagueSaveSchema.active_from_disk())
	save.rules_by = LeagueRules.read_all()
	save.rules = save.rules_by.get(str(save.actives[0]), LeagueRules.read(str(save.actives[0])))
	LeagueSaveSchema.ensure_schema(save)
	current = save
	return save

## Leave the save; the next read lazily reopens the cached seed.
static func close() -> void:
	if current != null and current.path == PLDatabase.current_path():
		PLDatabase.reset()
	current = null
	PLRepository.shared().invalidate()

## Quick Save: play writes to the save as it goes, so this stamps the file and
## proves it is still bound and writable. False means the write did not land.
func touch() -> bool:
	if not ensure_open():
		return false
	var stamp := Time.get_datetime_string_from_system(true, true)
	if not put_meta("saved_at", stamp):
		return false
	meta["saved_at"] = stamp
	return true

## Save As: write this save's file under another name and leave the season on its
## own file — the copy is a named restore point. Naming the season's own save
## rewrites it in place. Returns the copy's slug, or "" when nothing was written.
func write_copy(name: String) -> String:
	var typed := name.strip_edges()
	if typed == "" or not ensure_open():
		return ""
	var slug := LeagueSaveCatalog.slugify(typed)
	if slug == "" or slug == self.slug:
		return self.slug if touch() else ""
	DirAccess.make_dir_recursive_absolute(dir)
	var target := dir.path_join(slug + EXT)
	# Close the live file first: a copy taken under an open handle can miss the
	# last commit.
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	var out := FileAccess.open(target, FileAccess.WRITE)
	if out == null or bytes.is_empty():
		last_error = "cannot write %s" % target
		ensure_open()
		return ""
	out.store_buffer(bytes)
	out.close()
	var copy := open(target)
	if copy == null:
		ensure_open()
		return ""
	copy.put_meta("name", typed)
	copy.put_meta("saved_at", Time.get_datetime_string_from_system(true, true))
	# Back to the season's own file so play continues where it was.
	ensure_open()
	current = self
	PLRepository.shared().invalidate()
	return slug

# ------------------------------------------------------------------- meta ---

## Every read and write goes to this save's own file, even when another save was
## bound in between (listing, switching seasons): rebind when needed.
func ensure_open() -> bool:
	if PLDatabase.current_path() == path and PLDatabase.get_db() != null:
		return true
	if not PLDatabase.open_path(path):
		return false
	PLRepository.shared().invalidate()
	return true

func read_meta() -> Dictionary:
	if not ensure_open():
		return {}
	var out := {}
	for row in PLDatabase.rows("SELECT key, value FROM save_meta;"):
		out[str(row["key"])] = str(row["value"])
	return out

func put_meta(key: String, value: String) -> bool:
	if not ensure_open():
		return false
	var ok := PLDatabase.execute(
		"INSERT INTO save_meta (key, value) VALUES (?, ?) "
		+ "ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
		[key, value],
	)
	if ok:
		meta[key] = value
	return ok

func name() -> String:
	return str(meta.get("name", slug))

func status() -> String:
	return str(meta.get("status", "in_progress"))

func set_status(value: String) -> void:
	put_meta("status", value)

func current_date() -> String:
	return str(meta.get("current_date", ""))

func set_date(value: String) -> bool:
	return put_meta("current_date", value)

func matchday() -> int:
	return int(meta.get("matchday", "1"))

func set_matchday(value: int) -> void:
	put_meta("matchday", str(maxi(value, 1)))

## The competitions this save runs, in the order they were chosen.
func competition_ids() -> Array:
	return actives.duplicate()

## One competition's regulations, from the save's own rows.
func rules_for(competition_id: String) -> Dictionary:
	if rules_by.has(competition_id):
		return rules_by[competition_id]
	return rules

## The shared clock policy. One clock, so every league's row carries it and a
## mid-season change applies to the next Continue.
func set_advance_mode(value: String) -> bool:
	var mode := value if LeagueRules.ADVANCE_MODES.has(value) else "fixture_days"
	var ok := true
	for cid in actives:
		var r := rules_for(str(cid)).duplicate(true)
		r["advance_mode"] = mode
		ok = LeagueRules.write(str(cid), r) and ok
		rules_by[str(cid)] = r
	rules = rules_for(str(actives[0])) if not actives.is_empty() else rules
	return put_meta("advance_mode", mode) and ok

func advance_mode() -> String:
	return str(meta.get("advance_mode", rules.get("advance_mode", "fixture_days")))

func reload() -> void:
	if not ensure_open():
		return
	meta = read_meta()
	actives = LeagueSaveSchema.valid(LeagueSaveSchema.active_from_disk())
	rules_by = LeagueRules.read_all()
	if not actives.is_empty():
		rules = rules_for(str(actives[0]))
