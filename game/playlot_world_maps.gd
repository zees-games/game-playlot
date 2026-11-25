extends "playlot_setup_props.gd"
## The map catalogue: the maps this build ships, the solo host's mounted packs and the documents a map folder holds.
## Split out of playlot_world.gd; static, so the server browser reads it without a game.

## The client shell's solo host, which mounts map packs for a game played with no server.
const SOLO_SERVICE := &"gs_solo"
## A converted map's Garry's Mod name (`meta.source_map`), its alias for `pg_map` and for a dropped .bsp.
const PlaylotMapSources := preload("client/playlot_map_sources.gd")


## The maps this build ships; a server with delivered maps loads a JSON catalogue. An instance method that forwards, and a static
## one beside it because the server browser needs the list without a game: a copy written into the menu went stale four times.
func _map_catalogue() -> GSMapCatalogue:
	return map_catalogue()


static func map_catalogue() -> GSMapCatalogue:
	var catalogue := GSMapCatalogue.new()

	var table := [
		# The base: a big flat plate of grass, and the default everywhere.
		[&"pg_flatgrass", "Flatgrass", GSMapDef.KIND_SANDBOX, 1],
		# The one map in this family that is not written down. A sandbox's content is
		# what the players build in it, so "somewhere new" is worth more here than
		# "somewhere good".
		[&"pg_generated", "Playlot: Generated", GSMapDef.KIND_SANDBOX, 1],
	]

	for row in table:
		var map := GSMapDef.new()
		map.id = row[0]
		map.display_name = row[1]
		map.kind = row[2]
		map.tier = row[3]
		map.scene_path = PlaylotPaths.rebase("res://maps/%s.tscn") % String(row[0])
		map.author = "playlot"
		catalogue.add(map)

	# Custom maps from playlot-maps, where a checkout links them in (gs-bootstrap's
	# `maps/custom`). A delivered server and client add the same documents from the mounted
	# pack instead, with [method add_map_directory].
	var _linked := add_map_docs(catalogue, PlaylotPaths.rebase(CUSTOM_MAPS_DIR))
	# Internal-use-only originals (`*_orig` ids) unzipped into the user folder, never shipped; a built-in or linked id wins.
	var _unzipped := add_map_docs(catalogue, USER_MAPS_DIR)

	return catalogue


## The `<pack>/<subdir>` directories of the map packs the client shell mounted for solo play (its `client/solo.json`, or the one
## map pack of a "Play map" link), from the host it publishes as `gs_solo`. Looked up by name and duck-typed: a delivered game
## may not name a host's class. Empty everywhere else (a server, a networked client, a run from the repository, a suite).
static func solo_map_dirs(subdir: String) -> PackedStringArray:
	var host: Object = GSRegistry.get_service(SOLO_SERVICE)
	if host == null or not host.has_method(&"map_dirs"):
		return PackedStringArray()
	return host.call(&"map_dirs", subdir)


## The map the client shell was asked to start solo on (`--solo-map`, a hotspot "Play map" link), or empty with no host, an
## older shell without `start_map`, or none asked. The first map is [member PlaylotConfig.initial_map] unless this names one
## the catalogue has.
static func solo_start_map() -> StringName:
	var host: Object = GSRegistry.get_service(SOLO_SERVICE)
	if host == null or not (&"start_map" in host):
		return &""
	return StringName(str(host.get(&"start_map")))


## Adds every map document (`*.json`) in [param dir] to [param catalogue], each built by [constant DATA_MAP_SCENE] with its path in
## `meta.doc` and the Source map it was converted from, if any, in `meta.source_map`. An unreadable document is left out with a WARN; an existing id is kept, so a delivered map never replaces a
## built-in one. Returns how many were added.
static func add_map_docs(catalogue: GSMapCatalogue, dir: String) -> int:
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var added := 0
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var made := doc_map(dir.path_join(file))
		if made == null or catalogue.get_map(made.id) != null:
			continue
		catalogue.add(made)
		added += 1
	return added


## The map built by [constant DATA_MAP_SCENE] from the document at [param path] (its path in `meta.doc`, the Source map it was
## converted from in `meta.source_map`), or null with a WARN when the document cannot be read.
static func doc_map(path: String) -> GSMapDef:
	var read: GSResult = _data_map_script().read_doc(path)
	if not read.ok:
		GSLog.warn(CHANNEL, "a map document was left out", {"path": path, "why": read.error.message})
		return null
	var doc: Dictionary = read.value
	var map := GSMapDef.new()
	map.id = StringName(str(doc["id"]))
	map.display_name = str(doc.get("name", String(map.id)))
	map.kind = StringName(str(doc.get("map_kind", GSMapDef.KIND_SANDBOX)))
	map.tier = int(doc.get("tier", 1))
	map.author = str(doc.get("author", ""))
	map.scene_path = PlaylotPaths.rebase(DATA_MAP_SCENE)
	map.meta["doc"] = path
	var source := PlaylotMapSources.source_of(doc)
	if source != "":
		map.meta["source_map"] = source
	return map


## Turns the maps a followed content pack lists (gs-map's [method GSMapCatalogue.follow_content]) into maps this game can build. A playlot-maps entry's `scene` is its document, `maps/<id>.json`, which is no PackedScene, so the loader would refuse it ("A map's scene path must point at a PackedScene"), and a switch on the web, where the pack mounts after the first map, would fail.
## Each such def keeps its content id, version and entry key (so ensure finds the pack mounted, and an unfollow still drops it) and is built by [constant DATA_MAP_SCENE] from the document. On the web its download group is the map's own, so the first switch fetches that map's world files and nothing else. Returns how many were shaped.
static func shape_content_maps(catalogue: GSMapCatalogue, web: bool = OS.has_feature("web")) -> int:
	if catalogue == null:
		return 0
	var shaped := 0
	for map in catalogue.maps:
		if map.entry_key == "" or not map.scene_path.ends_with(".json"):
			continue
		var path := map.scene_path
		var made := doc_map(path) if FileAccess.file_exists(path) else null
		map.scene_path = PlaylotPaths.rebase(DATA_MAP_SCENE)
		map.meta["doc"] = path
		if made != null:
			if made.meta.has("source_map"):
				map.meta["source_map"] = made.meta["source_map"]
			if map.author == "":
				map.author = made.author
		if web and map.content_groups.is_empty():
			map.content_groups = PackedStringArray([String(map.id)])
		shaped += 1
	return shaped


## Placeholders for the maps the solo host lists as downloadable but has not mounted ([code]available_maps()[/code] on the `gs_solo` host: `{id, name, map_kind, pack, key}` rows from the map pack's manifest), so the list shows every map whether or not the player chose to download them all.
## Each is marked `meta.download` (and `meta.pack`), is out of the rotation, and is fetched by [method PlaylotWorld.change_map] when picked. An id the catalogue has is skipped. Empty with no host or an older shell. Returns how many were added.
static func add_solo_available(catalogue: GSMapCatalogue) -> int:
	var host: Object = GSRegistry.get_service(SOLO_SERVICE)
	if catalogue == null or host == null or not host.has_method(&"available_maps"):
		return 0
	var added := 0
	for row: Variant in host.call(&"available_maps"):
		if not (row is Dictionary):
			continue
		var id := StringName(str((row as Dictionary).get("id", "")))
		if id == &"" or catalogue.get_map(id) != null:
			continue
		var map := GSMapDef.new()
		map.id = id
		map.display_name = str(row.get("name", String(id)))
		var kind := str(row.get("map_kind", ""))
		map.kind = StringName(kind) if kind != "" else GSMapDef.KIND_SANDBOX
		map.scene_path = PlaylotPaths.rebase(DATA_MAP_SCENE)
		map.author = "playlot"
		map.in_rotation = false
		map.meta["download"] = true
		map.meta["pack"] = str(row.get("pack", ""))
		if not map.validate().ok or not catalogue.add(map).ok:
			continue
		added += 1
	return added


## True for a map listed by [method add_solo_available] that is not downloaded yet.
static func needs_download(map: GSMapDef) -> bool:
	return map != null and bool(map.meta.get("download", false))


## `maps/pg_data.gd`, loaded when first wanted rather than preloaded: it extends the map
## base, which preloads the player, and this file is preloaded by both.
static func _data_map_script() -> GDScript:
	return load(PlaylotPaths.rebase("res://maps/pg_data.gd")) as GDScript
