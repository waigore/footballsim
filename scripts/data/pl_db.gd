class_name PLDatabase
extends RefCounted

## One SQLite connection to the cached Premier League seed.
##
## The shipped seed (`res://data/pl_seed.sqlite`) is read-only inside the
## export; the game runs against a copy in the user cache so in-sim stats can be
## written on every platform. The copy is named after the seed's `db_version`,
## so bumping the version in the snapshot both flushes old in-sim stats and
## replaces a stale cached database on first use.

const SEED_PATH := "res://data/pl_seed.sqlite"
const CACHE_DIR := "user://cache"
const CACHE_PREFIX := "pl_seed_v"

static var cache_dir := CACHE_DIR
static var _db: SQLite = null
static var _open_path := ""
static var _version := -1

## Cache directory this run uses (tests point it at a scratch folder).
static func cache_directory() -> String:
	return cache_dir

## Seed version stamped in the shipped database, or -1 when the asset is gone.
static func seed_version() -> int:
	if _version >= 0:
		return _version
	if not FileAccess.file_exists(SEED_PATH):
		push_error("Premier League seed is missing: %s" % SEED_PATH)
		return -1
	DirAccess.make_dir_recursive_absolute(cache_directory())
	# Parallel test workers share one user cache; a fixed probe name races
	# (one process truncates or deletes while another queries metadata).
	var probe := cache_directory().path_join("_seed_probe_%d.sqlite" % OS.get_process_id())
	var out := FileAccess.open(probe, FileAccess.WRITE)
	if out == null:
		push_error("cannot stage the seed for reading: %s" % probe)
		return -1
	out.store_buffer(FileAccess.get_file_as_bytes(SEED_PATH))
	out.close()
	var probe_db := SQLite.new()
	probe_db.path = probe
	if not probe_db.open_db():
		push_error("cannot read the shipped seed: %s" % probe_db.error_message)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
		return -1
	var version := -1
	if probe_db.query("SELECT value FROM metadata WHERE key = 'db_version';") and not probe_db.query_result.is_empty():
		version = int(str(probe_db.query_result[0]["value"]))
	probe_db.close_db()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
	_version = version
	return version

static func cache_path() -> String:
	return cache_directory().path_join("%s%d.sqlite" % [CACHE_PREFIX, maxi(seed_version(), 0)])

## Copy the seed into the cache when it is missing, leave a current copy alone,
## and delete copies made from older seeds: their in-sim stats are stale.
static func ensure_cache() -> String:
	var version := seed_version()
	if version < 0:
		return ""
	var target := cache_directory().path_join("%s%d.sqlite" % [CACHE_PREFIX, version])
	var target_name := target.get_file()
	DirAccess.make_dir_recursive_absolute(cache_directory())
	for name in DirAccess.get_files_at(cache_directory()):
		if name.begins_with(CACHE_PREFIX) and name != target_name:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_directory().path_join(name)))
	if not FileAccess.file_exists(target):
		# Write aside, then rename, so a peer opening the final path never
		# sees an empty file mid-copy under --parallel.
		var tmp := cache_directory().path_join("_seed_copy_%d.sqlite" % OS.get_process_id())
		var out := FileAccess.open(tmp, FileAccess.WRITE)
		if out == null:
			push_error("cannot write the cached seed: %s" % tmp)
			return ""
		out.store_buffer(FileAccess.get_file_as_bytes(SEED_PATH))
		out.close()
		if not FileAccess.file_exists(target):
			if DirAccess.rename_absolute(
				ProjectSettings.globalize_path(tmp),
				ProjectSettings.globalize_path(target)
			) != OK and not FileAccess.file_exists(target):
				push_error("cannot publish the cached seed: %s" % target)
				DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
				return ""
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	return target

## Live connection, opened on first use. Null on failure so callers can show an
## empty state instead of crashing the match.
static func get_db() -> SQLite:
	if _db != null:
		return _db
	var path := ensure_cache()
	if path == "":
		return null
	var db := SQLite.new()
	db.path = path
	db.foreign_keys = true
	if not db.open_db():
		push_error("cannot open the cached seed: %s" % db.error_message)
		return null
	_db = db
	_open_path = path
	return _db

static func close() -> void:
	if _db != null:
		_db.close_db()
	_db = null
	_open_path = ""
	_version = -1

## Bind the static connection to another SQLite file: a league save owns its
## whole universe, so the engine, repository and encyclopedia read the save
## while it is active. `reset()` returns to the cached seed.
static func open_path(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		push_error("save database is missing: %s" % path)
		return false
	close()
	var db := SQLite.new()
	db.path = path
	db.foreign_keys = true
	if not db.open_db():
		push_error("cannot open the save: %s" % db.error_message)
		return false
	_db = db
	_open_path = path
	return true


## Rows of a SELECT as plain dictionaries. The addon hands back StringName
## keys, so each key is copied to a String once and callers stay simple.
static func rows(sql: String, bindings: Array = []) -> Array:
	var db := get_db()
	if db == null:
		return []
	var ok: bool = db.query(sql) if bindings.is_empty() else db.query_with_bindings(sql, bindings)
	if not ok:
		push_error("seed query failed: %s (%s)" % [sql, db.error_message])
		return []
	var out: Array = []
	for row in db.query_result:
		var clean := {}
		for key in row:
			clean[str(key)] = row[key]
		out.append(clean)
	return out

static func row(sql: String, bindings: Array = []) -> Dictionary:
	var found := rows(sql, bindings)
	return found[0] if not found.is_empty() else {}

## Write path for in-sim stats: one statement per call, wrapped by the caller in
## a transaction so the match never pays for a round trip per player.
static func execute(sql: String, bindings: Array = []) -> bool:
	var db := get_db()
	if db == null:
		return false
	if not db.query_with_bindings(sql, bindings):
		push_error("seed write failed: %s (%s)" % [sql, db.error_message])
		return false
	return true

static func transaction(sql: String) -> bool:
	return execute(sql)

## Test hook: forget the connection and the cached seed version.
static func reset() -> void:
	close()
	_version = -1

static func current_path() -> String:
	return _open_path
