extends RefCounted

## Garry's Mod (Source engine) maps by their own names. A converted PLAYLOT map says which map it came from: dot-map-convert
## writes `source_frame.map` (`gm_fork.bsp`), and its attribution says "converted from gm_fork". That name is an alias for
## the PLAYLOT map, so `pg_map gm_fork`, a dropped gm_fork folder, its `.bsp` or its Workshop `.gma` all reach pgc_fork.
## PLAYLOT never loads a BSP itself; one it has no conversion of is refused with what to do instead.

## Files that are a Source map, or carry one (a Workshop addon).
const EXTENSIONS: PackedStringArray = ["bsp", "gma"]
## What a dropped Source map with no PLAYLOT conversion is told, after "Cannot load ". `%s` is the map's name.
const REFUSAL := "%s: a Garry's Mod (Source engine) map, and PLAYLOT cannot load .bsp or .gma files itself. Drop the PLAYLOT map .json converted from it instead (pg_map lists the maps PLAYLOT has)"

static var _converted: RegEx = null


## [param file]'s map name: no folder, no Source extension, lower case, and no Workshop id prefix
## (`326332456_gm_fork.gma` is gm_fork).
static func name_of(file: String) -> String:
	var name := file.rstrip("/").get_file()
	if EXTENSIONS.has(name.get_extension().to_lower()):
		name = name.get_basename()
	name = name.to_lower()
	var cut := name.find("_")
	if cut > 0 and name.substr(0, cut).is_valid_int() and cut + 1 < name.length():
		name = name.substr(cut + 1)
	return name


## The Source map [param doc] was converted from, by [method name_of], or empty when it says none.
static func source_of(doc: Dictionary) -> String:
	var frame: Variant = doc.get("source_frame")
	if frame is Dictionary and str((frame as Dictionary).get("map", "")).strip_edges() != "":
		return name_of(str((frame as Dictionary)["map"]))
	if _converted == null:
		_converted = RegEx.create_from_string("(?i)converted from ([a-z0-9_]+)")
	var hit := _converted.search(str(doc.get("attribution", "")))
	return name_of(hit.get_string(1)) if hit != null else ""


## The map in [param catalogue] converted from the Source map [param text] (`meta.source_map`), or null.
static func find(catalogue: DotMapCatalogue, text: String) -> DotMapDef:
	var wanted := name_of(text.strip_edges())
	if catalogue == null or wanted == "":
		return null
	for map in catalogue.maps:
		if str(map.meta.get("source_map", "")) == wanted:
			return map
	return null


## The Source maps in [param path], by [method name_of], sorted and once each: the file itself, or every Source file in a
## folder and the folders below it, [param depth] folders down (0 is no limit). Empty when there are none.
static func in_path(path: String, depth: int) -> PackedStringArray:
	var out := PackedStringArray()
	if DirAccess.dir_exists_absolute(path):
		_in_folder(path.rstrip("/"), depth, 0, out)
	elif EXTENSIONS.has(path.get_extension().to_lower()):
		out.append(name_of(path))
	out.sort()
	return out


static func _in_folder(dir: String, depth: int, level: int, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		var name := name_of(file)
		if EXTENSIONS.has(file.get_extension().to_lower()) and not out.has(name):
			out.append(name)
	if depth > 0 and level >= depth:
		return
	for sub in DirAccess.get_directories_at(dir):
		_in_folder(dir.path_join(sub), depth, level + 1, out)
