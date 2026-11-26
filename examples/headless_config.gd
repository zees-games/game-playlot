extends GSGameCheckSuite

## PlaylotConfig through GSGameConfigBinder: fields, cvars, the arena and the shop reading them, strict refusal, the diff and the workbench round trip.
##
## [codeblock]
## godot --headless --path . res://examples/headless_config.tscn
## [/codeblock]

const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotAmbience := preload("../game/playlot_ambience.gd")
const PlaylotSpawnables := preload("../game/playlot_spawnables.gd")
const PlaylotWaves := preload("../game/playlot_waves.gd")
const PlaylotUserFiles := preload("../game/playlot_user_files.gd")
## One directory per suite process (the probe child is handed its parent's): user:// is shared by
## every copy of this project on a box, and two suites at once wrote and deleted each other's cfg files.
const ROOT_ARG := "--cfgroot="
var ROOT := _root()
const GAME := "game-playlot"
const CHECKS := 52
const SECTIONS := 6

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.FATAL)
	_run.call_deferred()


func _root() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(ROOT_ARG):
			return a.substr(ROOT_ARG.length())
	return "user://pg_cfgtest_%d" % OS.get_process_id()


func _run() -> void:
	if OS.get_cmdline_user_args().has("--probe"):
		_probe()
		return
	print("game-playlot: config binder")
	_entered += 1
	var config := PlaylotConfig.new()
	var binder := PlaylotConfig.make_binder(config)
	_check(GSAddonConfig.game_names("game-playlot") == PackedStringArray(["game-playground", "game-playlot"]), "the binder registers game-playground as game-playlot's former id", str(GSAddonConfig.game_names("game-playlot")))  # legacy id
	binder.strict = true
	_check(binder.load_layers().ok, "defaults load")
	_check(binder.diff().is_empty(), "no diff at the code defaults")
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	for k in ["arena_round_sec", "arena_score_limit", "arena_health", "arena_respawn_sec", "arena_friendly_fire", "wave_kill_reward", "arena_kill_reward", "max_players", "prop_budget", "map_seconds", "soldier_health_scale", "hunter_speed_scale", "wave_speed_scale", "move_speed", "jump_height", "move_gravity"]:
		_check(keys.has(k), "%s is exposed" % k)

	var console := GSConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, GSConVar.FLAG_ARCHIVE, console.has_name)
	console.set_cvar("pg_arena_score_limit", "7")
	_check(config.arena_score_limit == 7 and binder.source_of("arena_score_limit") == "cvar", "a cvar writes the field")
	_check(binder.diff_yaml().contains("arena_score_limit: 7"), "the diff names the edit")
	_npc_scales()
	_check(config.move_speed == 7.0 and config.jump_height == 1.15 and config.move_gravity == 20.0, "the movement defaults are the map layout constants")
	var schema_path := ROOT + "_config_schema.json"
	_check(binder.write_schema(schema_path).ok and FileAccess.file_exists(schema_path), "write_schema writes the schema")
	DirAccess.remove_absolute(schema_path)

	_strict_refuses_unknown()

	_entered += 1
	_pack_floor()
	_finished += 1

	_entered += 2
	_layers()
	_finished += 1
	_templates(binder)
	_finished += 1

	_entered += 1
	_user_files()
	_finished += 1

	_entered += 1
	var wb := GSGameWorkbench.new()
	wb.panel_mode = 1
	wb.config = {"enabled": false}
	for set: GSProfileSet in binder.profile_sets():
		wb.add_set(set, set.rel_path)
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var listed := PackedStringArray()
	for kind: String in wb.api.kinds():
		var got: GSResult = wb.api.handle(GSGameWorkbench.LOCAL_ACTOR, {"op": "get", "kind": kind, "id": binder.profile_id})
		if got.ok:
			listed.append_array(PackedStringArray((got.value as Dictionary).get("values", {}).keys()))
	var missing := PackedStringArray()
	for k in keys:
		if not listed.has(k):
			missing.append(k)
	_check(missing.is_empty() and binder.profile_sets().size() >= 4, "the workbench lists all %d keys over %d files" % [keys.size(), binder.profile_sets().size()], ",".join(missing))
	var res: GSResult = wb.api.handle(GSGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "config_world", "id": binder.profile_id, "key": "wave_kill_reward", "value": 90})
	_check(res.ok and config.wave_kill_reward == 90, "a workbench edit reaches the live config")
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/game-playlot/config_world/game.yml", "")
	_check(text.contains("wave_kill_reward: 90"), "the export holds the edit in the cfg layout")

	_ambience_cvars()

	wb.free()
	console.free()
	_finished += 2
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## A user:// file or folder under the old Playlot name is copied to the new path once, and the
## new path is what is read from then on.
func _user_files() -> void:
	var base := ROOT.path_join("user_files")
	_write("user_files/old.json", "{\"v\": 1}")
	_write("user_files/old_dir/sub/b.txt", "kept")
	var file := PlaylotUserFiles.adopt(base.path_join("new.json"), base.path_join("old.json"))
	_check(file == base.path_join("new.json") and FileAccess.get_file_as_string(file) == "{\"v\": 1}", "a former file is copied to the new path", file)
	var dir := PlaylotUserFiles.adopt(base.path_join("new_dir"), base.path_join("old_dir"))
	_check(FileAccess.get_file_as_string(dir.path_join("sub/b.txt")) == "kept", "a former folder is copied whole, nested files included", dir)
	_check(FileAccess.file_exists(base.path_join("old.json")), "the former file is left for an older build")
	_write("user_files/old.json", "{\"v\": 2}")
	PlaylotUserFiles.adopt(base.path_join("new.json"), base.path_join("old.json"))
	_check(FileAccess.get_file_as_string(base.path_join("new.json")) == "{\"v\": 1}", "once the new file exists the former one is never copied again")
	_check(PlaylotUserFiles.resolve("user://not_a_default.json") == "user://not_a_default.json" and PlaylotUserFiles.FORMER.size() == 8, "a path with no former name is returned as it is")
	for rel in ["old.json", "new.json", "old_dir/sub/b.txt", "new_dir/sub/b.txt", "old_dir/sub", "new_dir/sub", "old_dir", "new_dir", ""]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(base.path_join(rel)))


## A strict binder refuses a layer with a key the config does not have.
func _strict_refuses_unknown() -> void:
	var bad := FileAccess.open(ROOT + "_config_bad.json", FileAccess.WRITE)
	bad.store_string('{"no_such_field": 1}')
	bad.close()
	var strict := PlaylotConfig.make_binder(PlaylotConfig.new(), ROOT + "_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute(ROOT + "_config_bad.json")


## The ambience set offers only pg_ambient* cvars.
func _ambience_cvars() -> void:
	var ambient := PlaylotAmbience.cvar_types()
	var odd := PackedStringArray()
	for name: String in ambient:
		if not name.begins_with("pg_ambient"):
			odd.append(name)
	_check(not ambient.is_empty() and odd.is_empty(), "the ambience set offers the pg_ambient* cvars", ",".join(odd))


## The pack ships only game/, maps/ and the committed addons/pg_*; solo play fetches every other addon the pack's requires.json names. A Zee* or Aw* addon left unnamed is a grey screen on playlot.app, so each is named: in requires.floor.json at a sound floor when a build_level guard backs one, else in requires.uses.json (no floor, so it never trails the addon's LEVEL).
## zee_weapons is the exception: Zee is a Workshop extra reached only through `game/playlot_zee.gd` by path, so derive must not find it (a hard zee was "This game needs zee-weapons" in solo).
func _pack_floor() -> void:
	var derived := GSAddonApi.derive("res://")
	for dir in DirAccess.get_directories_at("res://addons"):
		if dir.begins_with("pg_"):
			derived.merge(GSAddonApi.derive("res://addons/%s" % dir))
	var floors := {}
	var path := "res://" + GSAddonApi.FLOOR_FILE
	if FileAccess.file_exists(path):
		var parsed := GSAddonApi.parse(FileAccess.get_file_as_string(path), GSAddonApi.FLOOR_FILE)
		if parsed.ok:
			floors = parsed.value
	var uses := GSAddonApi.declared_uses("res://")
	var unnamed := PackedStringArray()
	for addon: String in derived:
		if not addon.begins_with("gs_") and not addon.begins_with("pg_") and not floors.has(addon) and not uses.has(addon):
			unnamed.append(addon)
	_check(not derived.has("zee_weapons"), "zee_weapons stays optional (no Zee class named outside game/playlot_zee.gd)", str(derived.keys()))
	_check(unnamed.is_empty(), "%s or %s names every addon the shell does not carry" % [GSAddonApi.FLOOR_FILE, GSAddonApi.USES_FILE], ",".join(unnamed))
	var audit := GSAddonApi.floor_audit(floors, derived, GSAddonApi.guarded("res://"))
	_check(not floors.is_empty() and audit.is_empty(), "its floors are sound", "; ".join(audit))


## Child process: loads the layers strictly over the test root and prints what the live config holds.
func _probe() -> void:
	var config := PlaylotConfig.new()
	var binder := PlaylotConfig.make_binder(config)
	binder.strict = true
	binder.roots = PackedStringArray([ProjectSettings.globalize_path(ROOT)])
	var loaded := binder.load_layers()
	var console := GSConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, GSConVar.FLAG_ARCHIVE, console.has_name)
	print("PROBE ok=%s secs=%s secs_src=%s budget=%s budget_src=%s cvar=%s score=%s score_src=%s max=%s max_src=%s" % [
		loaded.ok, config.map_seconds, binder.source_of("map_seconds"), config.prop_budget, binder.source_of("prop_budget"),
		console.find_cvar("pg_prop_budget").get_string(), config.arena_score_limit, binder.source_of("arena_score_limit"),
		config.max_players, binder.source_of("max_players")])
	get_tree().quit(0)


func _write(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join(rel).get_base_dir())
	var f := FileAccess.open(ROOT.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _child() -> String:
	var out: Array = []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://examples/headless_config.tscn", "--", "--probe", ROOT_ARG + ROOT, "--pg-arena-score-limit=9", "--pg-max-players=12"], out, true)
	return "".join(PackedStringArray(out))


## A value set in a cfg file, the environment and argv each reaches the live config, and later layers win.
func _layers() -> void:
	_write("game/%s/config_server/game.yml" % GAME, "map_seconds: 1230.0\n")
	_write("game/%s/config_props/game.yml" % GAME, "prop_budget: 20\n")
	OS.set_environment("PLAYLOT_PROP_BUDGET", "44")
	var text := _child()
	_check(text.contains("PROBE ok=true"), "the layers load strictly in a fresh process", text.right(300))
	_check(text.contains("secs=1230") and text.contains("secs_src=yml"), "a cfg file reaches the live config")
	_check(text.contains("budget=44") and text.contains("budget_src=env") and text.contains("cvar=44"), "the environment beats a second file and reaches the cvar")
	_check(text.contains("score=9") and text.contains("score_src=argv"), "argv alone reaches the config")
	_check(text.contains("max=12") and text.contains("max_src=argv"), "a second argv flag reaches it too")
	OS.unset_environment("PLAYLOT_PROP_BUDGET")
	# The prefix under the old Playlot name still works, and the new one wins when both are set.
	OS.set_environment(PlaylotConfig.FORMER_ENV_PREFIX + "PROP_BUDGET", "33")
	text = _child()
	_check(text.contains("budget=33") and text.contains("budget_src=env"), "the former environment prefix is still read", text.right(300))
	OS.set_environment("PLAYLOT_PROP_BUDGET", "44")
	text = _child()
	_check(text.contains("budget=44") and text.contains("budget_src=env"), "the new environment prefix wins over the former one", text.right(300))
	OS.unset_environment("PLAYLOT_PROP_BUDGET")
	OS.unset_environment(PlaylotConfig.FORMER_ENV_PREFIX + "PROP_BUDGET")
	_write("game/%s/config_arena/game.yml" % GAME, "map_seconds: 99.0\n")
	_check(_child().contains("PROBE ok=false"), "strict: a key in the wrong file is refused")
	for f in ["config_server", "config_props", "config_arena", "config_world"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("game/%s/%s/game.yml" % [GAME, f])))


## The shipped cfg files hold every key, in step with PlaylotConfig, and change nothing as they are.
func _templates(binder: GSGameConfigBinder) -> void:
	var files := binder.template_files()
	# One file per config set (server, props, arena, world and whatever an addon adds), counted off the binder so a new set does not leave a stale number here.
	_check(files.size() >= 4 and files.size() == binder.profile_sets().size(), "one shipped cfg file per config set", "%d files, %d sets" % [files.size(), binder.profile_sets().size()])
	var stale := PackedStringArray()
	for path: String in files:
		if not FileAccess.file_exists("res://" + path) or FileAccess.get_file_as_string("res://" + path) != files[path]:
			stale.append(path)
	_check(stale.is_empty(), "the shipped files match the config (run addons/gs_game/qa/gs_game_cfg_templates.gd)", ",".join(stale))


func _npc_scales() -> void:
	var cat := PlaylotSpawnables.catalogue()
	var soldier := float(cat.get_prop(&"npc_soldier").meta["health"])
	var elite := float(cat.get_prop(&"npc_soldier_elite").meta["health"])
	var hunter := float(cat.get_prop(&"npc_hunter").meta["speed"])
	PlaylotSpawnables.apply_npc_scales(cat, 2.0, 1.5)
	PlaylotSpawnables.apply_npc_scales(cat, 2.0, 1.5)
	_check(is_equal_approx(float(cat.get_prop(&"npc_soldier").meta["health"]), soldier * 2.0), "soldier_health_scale doubles a soldier, once")
	_check(is_equal_approx(float(cat.get_prop(&"npc_soldier_elite").meta["health"]), elite * 2.0), "and the elite")
	_check(is_equal_approx(float(cat.get_prop(&"npc_hunter").meta["speed"]), hunter * 1.5), "hunter_speed_scale scales a hunter, once")
	PlaylotSpawnables.apply_npc_scales(cat, 1.0, 1.0)
	_check(is_equal_approx(float(cat.get_prop(&"npc_soldier").meta["health"]), soldier), "scale 1.0 restores the catalogue")
	var base := PlaylotWaves.catalogue()
	var fast := PlaylotWaves.catalogue(2.0)
	_check(is_equal_approx(float(fast.get_npc(&"runner").meta["speed"]), float(base.get_npc(&"runner").meta["speed"]) * 2.0), "wave_speed_scale scales the wave kinds")
