class_name TestScratch
extends RefCounted

## A private `user://` folder for the test run that asks for it.
##
## Save and cache dirs used to be fixed names, and every checkout shares one
## Godot user directory, so two runs testing at once wrote the same SQLite file:
## one run deleting a save under the other surfaced as `disk I/O error` plus a
## wall of unrelated assertion failures. Folding the process id into the folder
## keeps concurrent runs — parallel workers, a second worktree, another agent —
## on their own files. Suites still clean their own folder as before.

## `user://<name>_<process>`: stable inside one run, private to it.
static func dir(name: String) -> String:
	return "user://%s_%d" % [name, OS.get_process_id()]

## The same, for a single file: the run's id goes before the extension so the
## reader still sees a `.cfg`.
static func file(name: String) -> String:
	var ext := name.get_extension()
	if ext == "":
		return dir(name)
	return "user://%s_%d.%s" % [name.trim_suffix("." + ext), OS.get_process_id(), ext]

## Make sure `folder` exists and holds nothing from a crashed earlier run.
static func clear(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
