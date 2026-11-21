extends GSGameNetchaosServer

const Playlot := preload("../game/playlot.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPlatform := preload("../game/playlot_platform.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Playlot's side of `tools/netchaos.sh` (gs-game's GSGameNetchaosServer): the flat sandbox, the platform layer and the module.

var _game: Playlot = null
var _platform: PlaylotPlatform = null


func _configure() -> void:
	map_id = "pg_flatgrass"


func _prepare(label: String) -> Variant:
	return PlaylotPresentation.use_scratch_settings(label)


func _boot_world() -> void:
	if not (await boot_server()).ok:
		return
	var pg_config := PlaylotConfig.new()
	pg_config.records_directory = ""
	pg_config.initial_map = StringName(map_id)
	pg_config.map_seconds = 0.0
	_game = Playlot.new()
	_game.name = "Playlot"
	_game.config = pg_config
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_platform = PlaylotPlatform.new()
	_platform.name = "Identity"
	_platform.directory = "%s/identity" % data_dir
	add_child(_platform)
	var _identity: GSResult = await _platform.setup()
	var _p: GSResult = await server.modules.load_module("res://addons/gs_platform/gs_platform_module.gd")
	(load("res://game/playlot_module.gd") as GDScript).set("punishments_path", "%s/punishments.json" % data_dir)
	var loaded: GSResult = await server.modules.load_module("res://game/playlot_module.gd")
	if not loaded.ok:
		printerr("netchaos server: ", loaded.error)
		return
	for n in server.modules.loaded_names():
		var m: Object = server.modules.get_module(n)
		if m != null and m.get("net") != null:
			module = m
	if module != null and solid != "":
		var cv: GSConVar = server.console.find_cvar("mp_solidplayers")
		if cv != null:
			cv.force_set(solid)


func _players() -> Array:
	return _game.players.values() if _game != null else []
