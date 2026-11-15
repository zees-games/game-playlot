extends "playground_setup_props.gd"
## The map catalogue: the maps this build ships, the solo host's mounted packs and the documents a map folder holds.
## Split out of playground_world.gd; static, so the server browser reads it without a game.

## The client shell's solo host, which mounts map packs for a game played with no server.
const SOLO_SERVICE := &"dot_solo"


## The maps this build ships; a server with delivered maps loads a JSON catalogue. An instance method that forwards, and a static
## one beside it because the server browser needs the list without a game: a copy written into the menu went stale four times.
func _map_catalogue() -> DotMapCatalogue:
	return map_catalogue()


static func map_catalogue() -> DotMapCatalogue:
	var catalogue := DotMapCatalogue.new()

	var table := [
		# The base: a big flat plate of grass, and the default everywhere.
		[&"pg_flatgrass", "Flatgrass", DotMapDef.KIND_SANDBOX, 1],
		# The one map in this family that is not written down. A sandbox's content is
		# what the players build in it, so "somewhere new" is worth more here than
		# "somewhere good".
		[&"pg_generated", "Playlot: Generated", DotMapDef.KIND_SANDBOX, 1],
	]

	for row in table:
		var map := DotMapDef.new()
		map.id = row[0]
		map.display_name = row[1]
		map.kind = row[2]
		map.tier = row[3]
		map.scene_path = PlaygroundPaths.rebase("res://maps/%s.tscn") % String(row[0])
		map.author = "playground"
		catalogue.add(map)

	# Custom maps from playlot-maps, where a checkout links them in (dot-bootstrap's
	# `maps/custom`). A delivered server and client add the same documents from the mounted
	# pack instead, with [method add_map_directory].
	var _linked := add_map_docs(catalogue, PlaygroundPaths.rebase(CUSTOM_MAPS_DIR))
	# Internal-use-only originals (`*_orig` ids) unzipped into the user folder, never shipped; a built-in or linked id wins.
	var _unzipped := add_map_docs(catalogue, USER_MAPS_DIR)

	return catalogue


## The `<pack>/<subdir>` directories of the map packs the client shell mounted for solo play (its `client/solo.json`, or the one
## map pack of a "Play map" link), from the host it publishes as `dot_solo`. Looked up by name and duck-typed: a delivered game
## may not name a host's class. Empty everywhere else (a server, a networked client, a run from the repository, a suite).
static func solo_map_dirs(subdir: String) -> PackedStringArray:
	var host: Object = DotRegistry.get_service(SOLO_SERVICE)
	if host == null or not host.has_method(&"map_dirs"):
		return PackedStringArray()
	return host.call(&"map_dirs", subdir)


## The map the client shell was asked to start solo on (`--solo-map`, a hotspot "Play map" link), or empty with no host, an
## older shell without `start_map`, or none asked. The first map is [member PlaygroundConfig.initial_map] unless this names one
## the catalogue has.
static func solo_start_map() -> StringName:
	var host: Object = DotRegistry.get_service(SOLO_SERVICE)
	if host == null or not (&"start_map" in host):
		return &""
	return StringName(str(host.get(&"start_map")))


## Adds every map document (`*.json`) in [param dir] to [param catalogue], each built by [constant DATA_MAP_SCENE] with its path in
## `meta.doc`. An unreadable document is left out with a WARN; an existing id is kept, so a delivered map never replaces a
## built-in one. Returns how many were added.
static func add_map_docs(catalogue: DotMapCatalogue, dir: String) -> int:
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var added := 0
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var path := dir.path_join(file)
		var read: DotResult = _data_map_script().read_doc(path)
		if not read.ok:
			DotLog.warn(CHANNEL, "a map document was left out", {"path": path, "why": read.error.message})
			continue
		var doc: Dictionary = read.value
		var id := StringName(str(doc["id"]))
		if catalogue.get_map(id) != null:
			continue
		var map := DotMapDef.new()
		map.id = id
		map.display_name = str(doc.get("name", String(id)))
		map.kind = StringName(str(doc.get("map_kind", DotMapDef.KIND_SANDBOX)))
		map.tier = int(doc.get("tier", 1))
		map.author = str(doc.get("author", ""))
		map.scene_path = PlaygroundPaths.rebase(DATA_MAP_SCENE)
		map.meta["doc"] = path
		catalogue.add(map)
		added += 1
	return added


## `maps/pg_data.gd`, loaded when first wanted rather than preloaded: it extends the map
## base, which preloads the player, and this file is preloaded by both.
static func _data_map_script() -> GDScript:
	return load(PlaygroundPaths.rebase("res://maps/pg_data.gd")) as GDScript
