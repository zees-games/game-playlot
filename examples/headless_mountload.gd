extends GSGameCheckSuite

const PlaylotPaths := preload("../game/playlot_paths.gd")
const PlaylotWorldMaps := preload("../game/playlot_world_maps.gd")

## A maps pack mounted at runtime (through gs-cloud's mounter, with the config a client uses: replaced files allowed) is
## listed by [method PlaylotWorldMaps.add_map_docs] and its map loads through [GSMapLoader]: the data scene
## `maps/pg_data.tscn` is a PackedScene before and after the mount, from the game's own root.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mountload.tscn
## [/codeblock]

const CHECKS := 7
const FIXTURE := "res://examples/fixtures/maps/pg_brushes.json"
const VERSION := "9.9.9"


func _ready() -> void:
	GSLog.set_level(GSLog.Level.OFF)
	_run.call_deferred()


func _run() -> void:
	print("game-playlot: a maps pack mounted at runtime")
	var data := PlaylotPaths.rebase("res://maps/pg_data.tscn")
	_check(load(data) is PackedScene, "the data scene loads before the mount", data)

	var cfg := GSCloudConfig.new()
	cfg.cache_dir = "user://headless_mountload_cloud"
	cfg.allow_replace_files = true
	var store := GSCloudStore.new(cfg)
	_check((await store.open()).ok, "the store opens")

	var bytes := FileAccess.get_file_as_bytes(FIXTURE)
	var sha := _sha256(bytes)
	var made := GSCloudManifest.from_dict({
		"content_id": "gamemann/playlot-maps-mountload", "version": VERSION, "mount_root": "dot_cloud",
		"files": [{"path": "maps/pgc_mountload.json", "sha256": sha, "size": bytes.size()}],
	})
	_check(made.ok and store.put_bytes(bytes, sha).ok, "the pack's manifest and object are ready")
	var mounted: GSResult = await GSCloudMounter.new(cfg).mount(made.value, store)
	_check(mounted.ok, "the pack mounts", "" if mounted.ok else mounted.error.message)

	_check(load(data) is PackedScene, "the data scene still loads after the mount", data)
	var catalogue := GSMapCatalogue.new()
	var added := PlaylotWorldMaps.add_map_docs(catalogue, str(mounted.value) + "/maps")
	_check(added == 1 and catalogue.maps.size() == 1, "its document is listed", str(added))
	var loaded: GSResult = await GSMapLoader.new().load_map(catalogue.maps[0])
	_check(loaded.ok and loaded.value is PackedScene, "its map loads as a PackedScene",
			"" if loaded.ok else loaded.error.message)

	_wipe(cfg.cache_dir)
	_report(CHECKS)


func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _wipe(dir: String) -> void:
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
