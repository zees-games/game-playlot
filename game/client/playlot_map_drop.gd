extends RefCounted

## Maps dropped on PLAYLOT's window or executable: map documents (`.json`), and folders and zips of them, copied into `user://maps` by gs-map's GSMapDropIntake (API 26) and added to the solo game's maps.
## A Garry's Mod map (a `.bsp`, a Workshop `.gma`, or a folder holding one) is claimed too: one PLAYLOT has a conversion of is that map (gm_fork is pgc_fork, entry `source_map` set), any other is refused with what to drop instead. Anything else is refused out loud.

const CHANNEL := "playlot.map_drop"
const NEEDS_LEVEL := 26
const INTAKE_SCRIPT := "res://addons/gs_map/core/gs_map_drop_intake.gd"
const DATA_MAP_SCRIPT := "res://maps/pg_data.gd"
## The map document kinds taken: the name from before the Playlot rename (what maps are written
## with) and the new one. Kept in step with maps/pg_data.gd's KINDS, which is loaded by path here.
const MAP_KINDS: Array[String] = ["playground_map", "playlot_map"]
const PlaylotMapSources := preload("playlot_map_sources.gd")
const PlaylotPaths := preload("../playlot_paths.gd")
## What the refusal says this game takes.
const TAKES := "a PLAYLOT map .json, or a folder or .zip of them"


## Adds the intake under [param parent], watching its window, and hands it the command line (a drop on the executable).
## [param on_result] gets each drop's result dictionary. [param converted] is `func(source: String) -> Dictionary`, the
## `{id, title}` of the map converted from a Source map, or empty. Null, with a warning, on a gs-map older than API 26.
static func attach(parent: Node, into: String, taken: Callable, on_result: Callable, converted: Callable = Callable()) -> Node:
	if GSAddonApi.build_level("gs_map") < NEEDS_LEVEL or not ResourceLoader.exists(INTAKE_SCRIPT):
		GSLog.warn(CHANNEL, "dropped maps are off: this build's gs-map is older than API %d" % NEEDS_LEVEL)
		return null
	var intake: Node = load(INTAKE_SCRIPT).new()
	intake.name = "MapDrop"
	intake.set(&"into", into)
	intake.call(&"add_acceptor", TAKES, func(path: String, to: String) -> Dictionary:
		return accept(path, to, int(intake.get(&"search_depth")), taken, converted))
	var _c := intake.connect(&"handled", on_result)
	parent.add_child(intake)
	var _r: Dictionary = intake.call(&"take_cmdline", drop_args(cmdline()), false)
	return intake


## The process's arguments, the engine's and the user's.
static func cmdline() -> PackedStringArray:
	var all := OS.get_cmdline_args()
	all.append_array(OS.get_cmdline_user_args())
	return all


## [param args] without this game's config options and their values: gs-core reads `--pg-<key> <value>`,
## `--<addon>.<key> <value>` and `--config <dir>`, and a value that happens to be a folder is not a dropped map.
static func drop_args(args: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	while i < args.size():
		var a := args[i]
		i += 1
		var config_option := a.begins_with("--pg-") or a == "--config" or (a.begins_with("--") and a.contains("."))
		if config_option:
			if not a.contains("=") and i < args.size() and not args[i].begins_with("--"):
				i += 1
			continue
		out.append(a)
	return out


## The acceptor: `{}` when [param path] holds no PLAYLOT map document, else `{added, errors}`. Each document is checked by `maps/pg_data.gd` and written to `<into>/<id>.json`. [param taken] is `func(id: StringName) -> String`, a reason the id cannot be used or empty.
## [param depth] is how many folders down a folder is searched; 0 is no limit. With no document, a Source map in [param path] is answered by [method source_maps] through [param converted].
static func accept(path: String, into: String, depth: int, taken: Callable, converted: Callable = Callable()) -> Dictionary:
	var found: Array = []
	var errors := PackedStringArray()
	if DirAccess.dir_exists_absolute(path):
		_docs_in_folder(path.rstrip("/"), "", depth, 0, found)
	elif path.get_extension().to_lower() == "zip":
		_docs_in_zip(path, depth, found, errors)
	elif path.get_extension().to_lower() == "json":
		var doc := _map_doc(FileAccess.get_file_as_string(path))
		if not doc.is_empty():
			found.append([path.get_file(), doc])
	if found.is_empty() and errors.is_empty():
		return source_maps(PlaylotMapSources.in_path(path, depth), converted)
	if found.is_empty():
		return {"added": [], "errors": errors}
	var added: Array[Dictionary] = []
	var data_map: GDScript = load(PlaylotPaths.rebase(DATA_MAP_SCRIPT))
	var dir_made := DirAccess.make_dir_recursive_absolute(into)
	for pair: Array in found:
		var name := str(pair[0])
		var doc: Dictionary = pair[1]
		var checked: GSResult = data_map.validate(doc)
		if not checked.ok:
			errors.append("%s: %s" % [name, checked.error.message])
			continue
		var id := StringName(str(doc["id"]))
		var why := str(taken.call(id)) if taken.is_valid() else ""
		if why != "":
			errors.append("%s: %s" % [name, why])
			continue
		var target := into.path_join("%s.json" % id)
		var f := FileAccess.open(target, FileAccess.WRITE)
		if dir_made != OK or f == null:
			errors.append("%s: could not write %s (%s)" % [name, target, error_string(FileAccess.get_open_error())])
			continue
		var _w := f.store_string(JSON.stringify(doc, "\t"))
		f.close()
		added.append({"id": id, "title": str(doc.get("name", String(id))), "path": target})
	return {"added": added, "errors": errors}


## The Source maps [param names] as a drop result: each one [param converted] (`func(source) -> {id, title}`) knows is
## `{id, title, path: "", source_map}`, the PLAYLOT map to play, each other one an error saying what to drop instead.
## `{}` (not claimed) for no names.
static func source_maps(names: PackedStringArray, converted: Callable) -> Dictionary:
	if names.is_empty():
		return {}
	var added: Array[Dictionary] = []
	var errors := PackedStringArray()
	for name in names:
		var hit: Variant = converted.call(name) if converted.is_valid() else {}
		if hit is Dictionary and str((hit as Dictionary).get("id", "")) != "":
			added.append({"id": StringName(str(hit["id"])), "title": str(hit.get("title", hit["id"])), "path": "", "source_map": name})
		else:
			errors.append(PlaylotMapSources.REFUSAL % name)
	return {"added": added, "errors": errors}


## The dictionary [param text] parses to when it is a PLAYLOT map document (a kind in [constant MAP_KINDS]), else empty.
static func _map_doc(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and MAP_KINDS.has(str((parsed as Dictionary).get("kind", ""))):
		return parsed
	return {}


## Documents in [param dir] and the folders below it, [param level] folders down so far.
static func _docs_in_folder(dir: String, shown: String, depth: int, level: int, found: Array) -> void:
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if file.get_extension().to_lower() == "json":
			var doc := _map_doc(FileAccess.get_file_as_string(dir.path_join(file)))
			if not doc.is_empty():
				found.append([shown.path_join(file) if shown != "" else file, doc])
	if depth > 0 and level >= depth:
		return
	var subs := DirAccess.get_directories_at(dir)
	subs.sort()
	for sub in subs:
		_docs_in_folder(dir.path_join(sub), shown.path_join(sub) if shown != "" else sub, depth, level + 1, found)


static func _docs_in_zip(path: String, depth: int, found: Array, errors: PackedStringArray) -> void:
	var zip := ZIPReader.new()
	var opened := zip.open(path)
	if opened != OK:
		errors.append("%s: not a readable zip (%s)" % [path.get_file(), error_string(opened)])
		return
	var entries := zip.get_files()
	entries.sort()
	for entry in entries:
		if entry.get_extension().to_lower() != "json" or (depth > 0 and entry.count("/") > depth):
			continue
		var doc := _map_doc(zip.read_file(entry).get_string_from_utf8())
		if not doc.is_empty():
			found.append([entry, doc])
	var _closed := zip.close()
