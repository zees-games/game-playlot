extends GSGameCheckSuite

## Solo in the client shell: the map packs it mounted are in the catalogue before the first map, and its `start_map` (`--solo-map`, a hotspot "Play map" link) is that first map. With no host, an older shell or a map nobody has, the
## first map is `initial_map` as before. [codeblock]
## godot --headless --path . res://examples/headless_solomap.tscn [/codeblock]

const Playlot := preload("../game/playlot.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")

const CHECKS := 29
const SECTIONS := 4

## A map document in a directory standing in for a mounted pack's `maps/`.
const PACK_MAPS := "res://examples/fixtures/maps"
const PACK_MAP := &"pg_brushes"


## The shell's solo host as the game sees it, before `start_map` existed.
class FakeSolo:
	extends RefCounted
	var dirs := PackedStringArray()

	func map_dirs(_subdir: String) -> PackedStringArray:
		return dirs


## And with it.
class FakeSoloStart:
	extends FakeSolo
	var start_map: StringName = &""


## A shell that lists its packs' maps before they are downloaded (TmcSoloSession.available_maps / fetch_map). Its first
## download fails when [member fail_first] is set; a download "mounts" [constant PACK_MAPS] and says maps_changed.
class FakeSoloOnDemand:
	extends Node
	signal maps_changed()
	var dirs := PackedStringArray()
	var start_map: StringName = &""
	var rows: Array = []
	var fail_first := true
	var fetches: Array = []

	func map_dirs(_subdir: String) -> PackedStringArray:
		return dirs

	func available_maps() -> Array:
		return rows.duplicate(true)

	func fetch_map(id: StringName) -> GSResult:
		fetches.append(id)
		await Engine.get_main_loop().process_frame
		if fail_first:
			fail_first = false
			return GSResult.fail(GSError.CODE_NETWORK, "Could not download the map.", String(id))
		dirs = PackedStringArray([PACK_MAPS])
		maps_changed.emit()
		return GSResult.success("gamemann/%s@1.0.0" % id)


## gs-cloud as a map loader finds it, with the map's pack already mounted: ensure() fetches nothing.
class FakeMountedCloud:
	extends RefCounted
	var calls: Array = []
	var fetched := 0

	func is_mounted(_id: StringName, _version: String) -> bool:
		return true

	func ensure(id: StringName, version: String, groups: PackedStringArray = PackedStringArray(), url: String = "") -> GSResult:
		calls.append({"id": String(id), "version": version, "groups": groups, "url": url})
		return GSResult.success(false)


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-playlot: the shell's start map")
	_check(Playlot.solo_start_map() == &"" and Playlot.solo_map_dirs("maps").is_empty(),
		"with no solo host there is no start map and no mounted pack")
	_check(await _first_map(null) == "pg_flatgrass", "and the first map is initial_map")

	var old := FakeSolo.new()
	old.dirs = PackedStringArray([PACK_MAPS])
	var got := await _boot(old)
	_check(got[0] == "pg_flatgrass", "a shell with no start_map: initial_map", got[0])
	_check(got[1], "and the mounted pack's map is in the catalogue before it")

	var asked := FakeSoloStart.new()
	asked.dirs = PackedStringArray([PACK_MAPS])
	asked.start_map = PACK_MAP
	got = await _boot(asked)
	_check(got[0] == String(PACK_MAP), "a start map from the mounted pack is the first map", got[0])
	_check(got[1], "and it is in the catalogue")

	asked.start_map = &"pgc_not_a_map"
	_check(await _first_map(asked) == "pg_flatgrass", "a start map nobody has: initial_map")
	asked.start_map = &""
	_check(await _first_map(asked) == "pg_flatgrass", "an empty one: initial_map")
	asked.start_map = &"pg_generated"
	asked.dirs = PackedStringArray()
	_check(await _first_map(asked) == "pg_generated", "a built-in map can be the start map too")

	await _test_on_demand()
	await _test_late_listing()
	_test_content_maps()
	_report_sections(SECTIONS, SECTIONS, SECTIONS, CHECKS)


func _brushes_row() -> Dictionary:
	return {"id": String(PACK_MAP), "name": "Brushes", "map_kind": "sandbox", "pack": "gamemann/playlot-maps", "key": "gamemann/pg_brushes"}


## The manifest's list -> the map list -> a download when picked; a failed one said loudly and retried by picking again.
func _test_on_demand() -> void:
	print("== maps the packs list show before they are downloaded, and download when picked")
	var host := FakeSoloOnDemand.new()
	host.rows = [_brushes_row()]
	add_child(host)
	var game := await _boot_game(host)
	var def: GSMapDef = game.maps.catalogue.get_map(PACK_MAP)
	_check(def != null and Playlot.needs_download(def), "a map no pack is mounted for is listed, marked not downloaded")
	_check(def != null and not def.in_rotation, "and is kept out of the rotation until it is")
	var failed := []
	game.maps.change_failed.connect(func(m: GSMapDef, why: String) -> void: failed.append([m.id, why]))
	var first: GSResult = await game.change_map(PACK_MAP)
	_check(not first.ok and failed.size() == 1 and failed[0][0] == PACK_MAP, "a failed download fails the change loudly (change_failed)", str(failed))
	_check(String(game.maps.current.id) == "pg_flatgrass", "and the player stays on the map they were on")
	_check(Playlot.needs_download(game.maps.catalogue.get_map(PACK_MAP)), "the map stays listed, so picking it again retries")
	var again: GSResult = await game.change_map(PACK_MAP)
	_check(again.ok and game.maps.current != null and game.maps.current.id == PACK_MAP, "picking it again downloads and changes to it", str(again.error))
	_check(not Playlot.needs_download(game.maps.catalogue.get_map(PACK_MAP)), "its document replaced the placeholder")
	_check(host.fetches.size() == 2, "one download per pick", str(host.fetches))
	await _drop(game, host)


## A listing that comes after the game started (the shell reads the manifests in the background) joins the list.
func _test_late_listing() -> void:
	print("== a listing that arrives after the start joins the map list")
	var host := FakeSoloOnDemand.new()
	add_child(host)
	var game := await _boot_game(host)
	_check(not game.maps.catalogue.has(PACK_MAP), "nothing listed yet")
	host.rows = [_brushes_row()]
	host.maps_changed.emit()
	_check(Playlot.needs_download(game.maps.catalogue.get_map(PACK_MAP)), "maps_changed brings the listed map in, not downloaded")
	await _drop(game, host)


## A map followed from the content index (its scene a `maps/<id>.json` document) is built by pg_data, and a mounted pack loads
## with no fetch and no address of the game's own: gs-cloud derives it from its content origin, never a game server.
func _test_content_maps() -> void:
	print("== a content-index map is built from its document, and a mounted pack loads with no fetch")
	var cat := GSMapCatalogue.new()
	var def := GSMapDef.new()
	def.id = PACK_MAP
	def.scene_path = PACK_MAPS.path_join("pg_brushes.json")
	def.content_id = &"gamemann/playlot-maps"
	def.content_version = "1.0.3"
	def.entry_key = "map:pg_brushes"
	_check(cat.add(def).ok, "a content-index map joins the catalogue", def.scene_path)
	var web := Playlot.shape_content_maps(cat, true)
	var got := cat.get_map(PACK_MAP)
	_check(web == 1 and got.scene_path.ends_with("pg_data.tscn"), "its scene becomes the document map scene (it was not a PackedScene)", got.scene_path)
	_check(str(got.meta.get("doc", "")) == PACK_MAPS.path_join("pg_brushes.json"), "with the document kept")
	_check(got.content_groups == PackedStringArray([String(PACK_MAP)]), "on the web only its own group is asked for")
	_check(String(got.content_id) == "gamemann/playlot-maps" and got.entry_key != "", "and it is still the pack's map")
	_check(Playlot.shape_content_maps(cat, true) == 0, "shaping twice changes nothing")

	var cloud := FakeMountedCloud.new()
	GSRegistry.register(GSMapLoader.CLOUD_SERVICE, cloud)
	var loader := GSMapLoader.new()
	var loaded: GSResult = await loader.load_map(got)
	GSRegistry.unregister_instance(GSMapLoader.CLOUD_SERVICE, cloud)
	_check(loaded.ok and loaded.value is PackedScene, "a mounted pack's map loads to a scene", str(loaded.error))
	_check(cloud.calls.size() == 1 and cloud.fetched == 0, "asking the cloud once, which fetches nothing", str(cloud.calls))
	var url := str(cloud.calls[0]["url"]) if cloud.calls.size() == 1 else "?"
	_check(url == "" and not url.contains("zeesgames") and not url.contains("modcommunity"),
		"with no address of its own: the cloud's content origin is used, never a game server", url)
	_check(_menu_marks_download(), "the game menu's map rows say which maps are not downloaded")



## The client's map rows (playlot_client_net.map_menu_rows) read needs_download: checked in its source, as the client cannot boot here.
func _menu_marks_download() -> bool:
	var src := FileAccess.get_file_as_string("res://game/playlot_client_net.gd")
	return src.contains("Playlot.needs_download(def)") and src.contains("\"not downloaded\"")


func _drop(game: Node, host: Node) -> void:
	remove_child(game)
	game.free()
	GSRegistry.unregister_instance(Playlot.SOLO_SERVICE, host)
	host.queue_free()
	await get_tree().process_frame


func _first_map(host: Object) -> String:
	return (await _boot(host))[0]


## Boots a playlot with [param host] as the `gs_solo` service (none when null) and returns
## [first map id, whether the pack map is in its catalogue].
func _boot(host: Object) -> Array:
	var game := await _boot_game(host)
	var first := String(game.maps.current.id) if game.maps != null and game.maps.current != null else ""
	var listed: bool = game.maps != null and game.maps.catalogue.has(PACK_MAP)
	remove_child(game)
	game.free()
	if host != null:
		GSRegistry.unregister_instance(Playlot.SOLO_SERVICE, host)
	await get_tree().process_frame
	return [first, listed]


## A booted playlot with [param host] as the `gs_solo` service (none when null), still in the tree.
func _boot_game(host: Object) -> Node:
	if host != null:
		GSRegistry.register(Playlot.SOLO_SERVICE, host)
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.map_seconds = 0.0
	config.initial_map = &"pg_flatgrass"
	config.authoritative = true
	var game := Playlot.new()
	game.config = config
	game.service_scope = &"solomap"
	add_child(game)
	for _i in range(120):
		await get_tree().process_frame
		if game.booted:
			break
	return game
