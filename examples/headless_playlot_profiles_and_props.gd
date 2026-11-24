extends GSGameCheckSuite

const PlaylotBindings := preload("../game/playlot_bindings.gd")
const Playlot := preload("../game/playlot.gd")
const PlaylotBrowser := preload("../game/client/playlot_browser.gd")
const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotProfileScreen := preload("../game/playlot_profile_screen.gd")
const PlaylotReadout := preload("../game/playlot_profile_readout.gd")
const PlaylotNetBridge := preload("../game/net/playlot_net_bridge.gd")
const PlaylotFlashlight := preload("../game/playlot_flashlight.gd")
const PlaylotGeometry := preload("../game/playlot_geometry.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotEntity := preload("../game/entities/playlot_entity.gd")
const PlaylotIcons := preload("../game/playlot_icons.gd")
const PlaylotMapSurvey := preload("../game/playlot_map_survey.gd")
const PlaylotPickup := preload("../game/playlot_pickup.gd")
const PlaylotBuilds := preload("../game/playlot_builds.gd")
const PlaylotPlayer := preload("../game/playlot_player.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")
const PlaylotProp := preload("../game/playlot_prop.gd")
const PlaylotProfiles := preload("../game/playlot_profiles.gd")
const PlaylotSpawnMenu := preload("../game/playlot_spawn_menu.gd")
const PlaylotSpawnables := preload("../game/playlot_spawnables.gd")
const PlaylotVehicle := preload("../game/playlot_vehicle.gd")
const PlaylotWeaponDef := preload("../game/weapons/playlot_weapon_def.gd")
const PlaylotWeapons := preload("../game/playlot_weapons.gd")
const PlaylotZee := preload("../game/playlot_zee.gd")
const PlaylotProjectiles := preload("../game/playlot_projectiles.gd")
const PlaylotEvents := preload("../game/net/playlot_events.gd")
const PlaylotAddons := preload("../game/playlot_addons.gd")
const PlaylotMaterials := preload("../game/playlot_materials.gd")
const ToolPhysprop := preload("../game/toolgun/tool_physprop.gd")
const PlaylotLimits := preload("../game/playlot_limits.gd")
const PlaylotNpcNet := preload("../game/net/playlot_npc_net.gd")

## Runs the whole playlot: a bot surfs a map from start to finish, its run is timed and filed, props are spawned and moved, and the map is changed underneath.
##
## The only run of the joins between the five addons, where the bugs live: timer ticked from the move, style change, zone effect, record to leaderboard, map change teardown, prop spawn and free. The bot's input is a scripted [GSFpsCommand]. Run: `godot --headless --path . res://examples/headless_playlot.tscn`

const TICK := 1.0 / 128.0

var _entered := 0
var _completed := 0

var playlot: Playlot = null


## A stand-in for the tool gun: a mode asks its gun for the game and nothing else.
class WireGun:
	extends RefCounted
	var game: Node = null


## [method _stopping]'s stand-in for a button: S held rather than a button pressed.
const BACK_KEY := -1


## playlot-maps' documents this suite surveys. See `_test_the_maps_are_surveyed`.
const CUSTOM_MAPS := ["pgc_plots", "pgc_quarry", "pgc_slopes", "pgc_town", "pgc_islands", "pgc_site", "pgc_warehouse", "pgc_canyon", "pgc_harbour", "pgc_bowl", "pgc_obstacle", "pgc_nature", "pgc_construct_small", "pgc_smallbase", "pgc_mountain_resort", "pgc_deadcity", "pgc_valley", "pgc_mallparking", "pgc_shambles", "pgc_fork", "pgc_balkans", "pgc_vyten", "pgc_southside", "pgc_asheville", "pgc_boreas", "pgc_bigisland", "pgc_rooftops", "pgc_york"]


## The Q menu's NPCs and pack weapons come from profiles, a game profile overrides an entry, and an
## admin's edit reaches the next spawn, a live NPC and a late joiner; a player's is refused.
var _p_fixture: PackedStringArray
var _p_profiles: PlaylotProfiles
var _p_rt: GSProfileRuntime
var _p_old_permit: Callable
var _p_live_body: PlaylotEntity

func _test_profiles() -> void:
	_section("profiles drive the menu and edit live")

	_p_fixture = PackedStringArray(["res://examples/fixtures/profiles"])
	_p_profiles = playlot.profiles
	_check(_p_profiles != null and _p_profiles.runtime != null, "the playlot builds its profiles and runtime")
	if _p_profiles == null:
		return

	# The menu, derived: a scratch catalogue so nothing leaks into the sections after.
	var scratch := PlaylotProfiles.new()
	scratch.setup(_p_fixture)
	var cat: GSPropCatalogue = playlot._prop_catalogue()
	var before := cat.props.size()
	var touched := scratch.apply_npcs(cat)
	_check(touched == 3, "three npc profiles touch the catalogue", str(touched))
	var chaser := cat.get_prop(&"npc_chaser")
	_check(chaser.display_name == "Fast Chaser", "a game-tier profile renames the entry it names")
	_check(float(chaser.meta["speed"]) == 9.0, "and changes the key it states")
	_check(float(chaser.meta["sight"]) == 40.0, "while a key it does not state keeps the catalogue's value")
	_check(chaser.category == &"pursuers", "menu.category regroups it")
	_check(chaser.icon_path == "res://assets/props/market/Textures/colormap.png", "menu.icon sets the entry's icon")
	_check(cat.get_prop(&"npc_hunter").icon_path == "", "and an entry without one keeps the drawn icon")
	_check(bool(cat.get_prop(&"npc_hopper").meta.get("hidden", false)), "menu.hidden hides an entry")
	var mini := cat.get_prop(&"mini_hunter")
	_check(mini != null and cat.props.size() == before + 1, "a new id with extra.base adds an entry")
	_check(
		mini != null and PlaylotSpawnables.script_of(mini) == PlaylotSpawnables.script_of(cat.get_prop(&"npc_hunter")),
		"cloned from its base's script"
	)
	_check(cat.get_prop(&"npc_soldier") != null and float(cat.get_prop(&"npc_soldier").meta["health"]) == 100.0, "entries without a profile are unchanged")

	var menu := PlaylotSpawnMenu.new()
	menu.catalogue = cat
	add_child(menu)
	var names: Array = menu._catalogue_defs(PlaylotSpawnables.Kind.ENTITY).map(func(d: GSPropDef) -> String: return String(d.id))
	menu.free()
	_check(names.slice(0, 2) == ["mini_hunter", "npc_chaser"], "menu.sort orders the entities", str(names.slice(0, 3)))
	_check(not names.has("npc_hopper"), "and the hidden one is not listed")

	var rows := [{"id": "zz_fx_a", "category": "Weapons"}, {"id": "zz_fx_b", "category": "Weapons"}, {"id": "zz_fx_c", "category": "Weapons"}, {"id": "plain", "category": "Weapons"}]
	var refined := scratch.refine_weapon_entries("zz_fixture", rows)
	_check(refined.map(func(r: Dictionary) -> String: return r["id"]) == ["zz_fx_b", "plain", "zz_fx_a"], "pack weapon rows are sorted by menu.sort and the hidden one dropped")
	_check(refined[0]["category"] == "Heavy" and refined[1]["category"] == "Weapons", "and regrouped by menu.category")
	scratch.release()

	# Live editing, through the playlot's own runtime and the console command's request.
	_p_profiles.npcs.roots = _p_fixture
	_p_profiles.npcs.clear_cache()
	_p_profiles.apply_npcs(playlot.props.catalogue)
	_p_rt = _p_profiles.runtime
	_p_old_permit = _p_rt.permit
	_p_rt.permit = func(actor: Variant, _flag: String) -> bool: return actor == "uid-admin"

	playlot.props.limits.spawn_interval = 0.0
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	var live := playlot.props.spawn(&"npc_chaser", &"bot", Vector3(0.0, 1.2, 0.0))
	_p_live_body = live.node as PlaylotEntity if live != null else null
	_check(_p_live_body != null and _p_live_body.tune(&"speed", 0.0) == 9.0, "a spawn reads the profile's speed")

	var req := GSConsoleProfileEdit.parse(PackedStringArray(["set", "npc", "npc_chaser", "speed", "12"]))
	var denied := _p_rt.handle_request("uid-player", req.value)
	_check(not denied.ok and denied.error.code == GSError.CODE_FORBIDDEN, "a non-admin's edit is refused")
	_check(float(playlot.props.catalogue.get_prop(&"npc_chaser").meta["speed"]) == 9.0, "and changes nothing")

	var done := _p_rt.handle_request("uid-admin", req.value)
	_check(done.ok, "an admin's profile_edit is accepted", "" if done.ok else done.error.message)
	var next := playlot.props.spawn(&"npc_chaser", &"bot", Vector3(3.0, 1.2, 0.0))
	var next_body := next.node as PlaylotEntity if next != null else null
	_check(next_body != null and next_body.tune(&"speed", 0.0) == 12.0, "the next spawn has the edited speed")
	_test_profiles_2()

func _test_profiles_2() -> void:

	var sight := GSConsoleProfileEdit.parse(PackedStringArray(["set", "npc", "npc_chaser", "sight", "77"]))
	_check(_p_rt.handle_request("uid-admin", sight.value).ok, "a second edit applies")
	_check(_p_live_body != null and _p_live_body.npc.def.sight_range == 77.0, "and re_apply gives the live NPC the new perception")
	var bad := GSConsoleProfileEdit.parse(PackedStringArray(["set", "npc", "npc_chaser", "health", "-5"]))
	_check(not _p_rt.handle_request("uid-admin", bad.value).ok, "an out-of-range edit is refused by the schema")

	# A late joiner: the snapshot, through the link's own encoding.
	var late := GSProfileRuntime.new()
	var late_set := GSNpcProfiles.make_set(PlaylotProfiles.GAME, _p_fixture)
	late.add_set(late_set)
	var old_send := _p_rt.send_to
	_p_rt.send_to = func(_peer: Variant, row: Dictionary) -> void:
		late.apply_row(GSNetProfileLink.decode_body(GSNetProfileLink.encode_body(row)).value)
	_p_rt.send_snapshot(7)
	_p_rt.send_to = old_send
	var seen := late_set.load_profile("npc_chaser")
	_check(seen.ok and float(seen.value.get_value("speed")) == 12.0 and float(seen.value.get_value("sight")) == 77.0, "a late joiner's snapshot carries both edited values")

	# Pack weapons are one kind behind one runtime layer.
	var fx := _p_profiles.weapons.add_pack("zz_fixture")
	fx.roots = _p_fixture
	var wreq := GSConsoleProfileEdit.parse(PackedStringArray(["set", "weapon", "fx_a", "slot", "4"]))
	var wdenied := _p_rt.handle_request("uid-player", wreq.value)
	_check(not wdenied.ok and wdenied.error.code == GSError.CODE_FORBIDDEN, "a non-admin's weapon edit is refused")
	_check(_p_profiles.weapon_layer().is_empty(), "and the weapon layer stays empty")
	var audit: Array = []
	var sink := func(rec: Dictionary) -> void: audit.append(rec)
	var old_level := GSLog.get_level()
	GSLog.set_level(GSLog.Level.INFO)
	GSLog.add_sink(sink)
	_check(_p_rt.handle_request("uid-admin", wreq.value).ok, "an admin's weapon edit is accepted")
	GSLog.remove_sink(sink)
	GSLog.set_level(old_level)
	var line: Dictionary = {}
	for rec: Dictionary in audit:
		if rec["message"] == "profile edited":
			line = rec["fields"]
	_check(not line.is_empty() and line.get("kind") == "weapon" and line.get("id") == "fx_a" and line.get("key") == "slot" and str(line.get("new")) == "4" and str(line.get("who")) != "", "and writes one audit line: who, kind, id, key, new value")
	_check(int(_p_profiles.weapon_layer().get("fx_a", {}).get("slot", 0)) == 4, "and lands in the layer the packs rebuild from")
	var packset := GSWeaponProfiles.make_set("zz_fixture", PlaylotProfiles.GAME, _p_fixture, _p_profiles.weapon_layer())
	_check(int(packset.load_profile("fx_a").value.get_value("slot")) == 4, "a pack's own set reads it")
	_p_rt.handle_request("uid-admin", GSProfileRuntime.make_request("reset", "weapon", "fx_a"))
	_check(_p_profiles.weapon_layer().is_empty(), "and a reset empties it")
	fx.roots = PackedStringArray()
	fx.clear_cache()
	packset.clear_cache()

	# Put the shared playlot back for the sections after this one.
	_p_rt.handle_request("uid-admin", GSProfileRuntime.make_request("reset", "npc", "npc_chaser"))
	_p_rt.permit = _p_old_permit
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	_p_profiles.npcs.roots = PackedStringArray()
	_p_profiles.npcs.clear_cache()
	_p_profiles.apply_npcs(playlot.props.catalogue)
	_check(float(playlot.props.catalogue.get_prop(&"npc_chaser").meta["speed"]) == 5.0, "with the file gone the entry returns to the catalogue's own")
	_done()


## The admin workbench: opens and closes on the screen stack, edits go out as requests and come
## back through the runtime, another admin's edit refreshes the open form, and only an admin gets in.
var _pw_profiles: PlaylotProfiles
var _pw_rt: GSProfileRuntime
var _pw_old_permit: Callable
var _pw_stack: GSScreenStack
var _pw_screen: PlaylotProfileScreen
var _pw_st: Dictionary

func _test_profile_workbench() -> void:
	_section("the profile workbench edits live through requests")
	var fixture := PackedStringArray(["res://examples/fixtures/profiles"])
	_pw_profiles = playlot.profiles
	_pw_rt = _pw_profiles.runtime
	_pw_old_permit = _pw_rt.permit
	_pw_rt.permit = func(actor: Variant, _flag: String) -> bool: return actor == "uid-admin"
	_pw_profiles.npcs.roots = fixture
	_pw_profiles.npcs.clear_cache()

	_pw_stack = GSScreenStack.new()
	_pw_stack.register_service = false
	_pw_stack.manage_mouse = false
	add_child(_pw_stack)
	_pw_stack.setup()
	_pw_screen = PlaylotProfileScreen.new()
	_pw_screen.profiles = _pw_profiles
	var sent: Array[Dictionary] = []
	_pw_screen.submit = func(req: Dictionary) -> GSResult:
		sent.append(req)
		var wire := GSNetProfileLink.decode_body(GSNetProfileLink.encode_body(req))
		if not wire.ok:
			return wire
		return _pw_rt.handle_request("uid-admin", wire.value)
	var targets: Array[String] = []
	_pw_screen.target_requested.connect(func(kind: String, id: String) -> void: targets.append(kind + "/" + id))
	_check(_pw_stack.register(_pw_screen).ok, "the screen registers")
	_check(_pw_stack.push(&"profiles").ok and _pw_stack.is_open(&"profiles"), "it opens")
	_check(_pw_screen.ids("npc").has("npc_chaser"), "it lists the NPC profiles the runtime can edit", str(_pw_screen.ids("npc")))

	_pw_screen.open_profile("npc", "npc_chaser")
	_check(_pw_screen.form != null and _pw_screen.form.row("speed") != null, "an NPC opens as a schema form")

	var spawn_at := _pw_rt.revision("npc", "npc_chaser")
	var _r := _pw_screen.form.set_value("speed", 12.0)
	_pw_screen.flush()
	_check(sent.size() == 1 and sent[0]["op"] == "set" and sent[0]["key"] == "speed", "a form edit is sent as a set request", str(sent))
	var seen := _pw_profiles.npcs.load_profile("npc_chaser")
	_check(seen.ok and float(seen.value.get_value("speed")) == 12.0, "and the runtime layer holds the new value")
	_check(_pw_rt.revision("npc", "npc_chaser") > spawn_at, "the revision moves")
	_check(_pw_screen._edited_count("npc", "npc_chaser") == 1, "the profile is marked edited live")

	var other := GSProfileRuntime.make_request("set", "npc", "npc_chaser", "sight", 55.0)
	_check(_pw_rt.handle_request("uid-admin", other).ok, "another admin edits the same profile")
	_pw_screen._process(0.0)
	_check(float(_pw_screen.form.values().get("sight", 0.0)) == 55.0, "the open form follows it", str(_pw_screen.form.values().get("sight")))
	_check(float(_pw_screen.form.values().get("speed", 0.0)) == 12.0, "and keeps the edit already there")

	_pw_screen.form.reset_key("speed")
	_pw_screen.flush()
	_check(sent.back()["op"] == "reset_key" and float(_pw_profiles.npcs.load_profile("npc_chaser").value.get_value("speed")) == 9.0, "a per-key reset goes back to the file's number")
	_pw_screen.reset_all()
	_check(_pw_screen._edited_count("npc", "npc_chaser") == 0, "reset all clears every live edit")
	var count := sent.size()
	_pw_screen.save()
	_check(sent.size() == count + 1 and sent.back()["op"] == "save", "save is its own request to the server layer")
	_pw_screen.request_target()
	_check(targets == ["npc/npc_chaser"], "the test-target button asks the client to spawn it", str(targets))

	var weapons := _pw_screen.ids("weapon")
	if not weapons.is_empty():
		_pw_screen.open_profile("weapon", weapons[0])
		_check(_pw_screen.form != null and _pw_screen.current_kind() == "weapon", "a weapon opens in the same form")
	else:
		_check(true, "no weapon profiles are loaded here, so none to open")

	var m4 := {"extra.damage": 29.0, "extra.rpm": 800.0, "extra.reload_seconds": 2.1, "magazine": 30}
	_pw_st = PlaylotReadout.weapon_stats(m4, 64.0)
	_check(is_equal_approx(float(_pw_st["burst_dps"]), 29.0 * 800.0 / 60.0), "burst DPS is damage times rounds per second", str(_pw_st))
	_test_profile_workbench_2()

func _test_profile_workbench_2() -> void:
	_check(float(_pw_st["sustained_dps"]) < float(_pw_st["burst_dps"]), "reloading lowers sustained DPS")
	var kill := PlaylotReadout.ttk(_pw_st, 100.0)
	_check(int(kill["shots"]) == 4 and is_equal_approx(float(kill["seconds"]), 3.0 * 60.0 / 800.0), "100 hp takes 4 shots, 3 intervals", str(kill))
	_check(float(PlaylotReadout.ttk(_pw_st, 1000.0)["seconds"]) > 34.0 * 60.0 / 800.0 + 2.0, "a kill longer than a magazine pays the reload")
	_check(PlaylotReadout.weapon_stats({}, 64.0).is_empty(), "a weapon with no damage has no readout")
	_check(_pw_screen._readout != null and _pw_screen._readout.text != "", "the workbench card carries a readout line")

	_pw_stack.pop(&"profiles")
	_check(not _pw_stack.is_open(&"profiles"), "it closes")

	var client := PlaylotClient.new()
	_check(client._may_edit_profiles(), "offline the player is the server and may edit")
	client.note_offline(&"props", 2)
	client.note_offline(&"kills")
	_check(int(client.offline_stats[&"props"]) == 2 and int(client.offline_stats[&"kills"]) == 1, "offline tallies feed the Tab board's stat columns")
	var bridge := PlaylotNetBridge.new()
	client.bridge = bridge
	_check(not client._may_edit_profiles(), "connected, nobody may edit until the server says so")
	client._profile_probing = true
	client._on_profile_reply(false, "profile edits need 'cvar'")
	_check(not client._may_edit_profiles(), "a refusal keeps a player out")
	client._profile_probing = true
	client._on_profile_reply(false, "no such profile")
	_check(client._may_edit_profiles(), "any other answer means an admin asked")
	client.bridge = null
	if bridge is Node:
		bridge.free()
	client.free()

	_pw_rt.permit = _pw_old_permit
	_pw_rt.handle_request("uid-admin", GSProfileRuntime.make_request("reset", "npc", "npc_chaser"))
	_pw_profiles.npcs.roots = PackedStringArray()
	_pw_profiles.npcs.clear_cache()
	_pw_stack.queue_free()
	_done()


## The first-person camera's motion, through the client's own `PlaylotPlayer.present_camera`
## once a physics tick: a drop dips and comes back, a hop does not, a strafe leans each way,
## speed widens the lens, a teleport drops it all, and with every setting at 0 nothing moves.
func _test_camera_motion() -> void:
	_section("the camera dips, leans and widens, and only when it should")

	var _lobby: GSResult = await playlot.change_map(&"pg_flatgrass")
	var feel := playlot.add_player(&"feel", "Feel")
	var camera := Camera3D.new()
	feel.add_child(camera)
	feel.enable_camera_motion()
	for i in 40:
		await get_tree().physics_frame
	var home := feel.controller.state.position
	var yaw := feel.controller.state.yaw
	var dt := 1.0 / float(Engine.physics_ticks_per_second)

	var run := func(command: GSFpsCommand, ticks: int, column: StringName) -> Array:
		feel.controller.apply_command(command)
		var out: Array = []
		for i in ticks:
			await get_tree().physics_frame
			feel.present_camera(camera, dt, 100.0)
			match column:
				&"dip": out.append(feel.camera_motion.eye_drop())
				&"roll": out.append(feel.camera_motion.roll())
				&"fov": out.append(camera.fov)
		return out

	var still := GSFpsCommand.new()
	still.yaw = yaw

	feel.teleport(home + Vector3(0.0, 7.0, 0.0), yaw)
	var drop: Array = await run.call(still, int(1.6 / dt), &"dip")
	_check(drop.min() < -0.04 and absf(float(drop.back())) < 0.005,
		"a 7 m drop dips the eye and it comes back",
		"deepest %.3f m, last %.4f" % [drop.min(), drop.back()])

	var hop := still.duplicate_command()
	hop.set_button(GSFpsCommand.BUTTON_JUMP, true)
	var hops: Array = await run.call(hop, int(1.5 / dt), &"dip")
	_check(hops.min() == 0.0, "a chain of hops (6.8 m/s each) never bobs the view", "deepest %.3f" % hops.min())

	var right := still.duplicate_command()
	right.move = Vector2(1.0, 0.0)
	var left := still.duplicate_command()
	left.move = Vector2(-1.0, 0.0)
	var lean_r: Array = await run.call(right, int(0.8 / dt), &"roll")
	var lean_l: Array = await run.call(left, int(0.8 / dt), &"roll")
	_check(absf(float(lean_r.back())) > 0.4 and absf(float(lean_r.back())) <= 2.0
		and signf(float(lean_r.back())) == -signf(float(lean_l.back())),
		"a strafe leans the view about a degree, each way",
		"right %.2f, left %.2f deg" % [lean_r.back(), lean_l.back()])

	feel.teleport(home + Vector3(0.0, 40.0, 0.0), yaw)
	feel.controller.state.velocity = GSFpsMotor.forward_for(yaw) * 22.0
	var lens: Array = await run.call(still, int(0.8 / dt), &"fov")
	_check(float(lens.back()) > 103.0 and float(lens.back()) < 106.0,
		"at 22 m/s the lens widens a few degrees", "%.2f" % lens.back())
	feel.teleport(home, yaw)
	feel.present_camera(camera, dt, 100.0)
	_check(feel.camera_motion.eye_drop() == 0.0 and feel.camera_motion.roll() == 0.0 and camera.fov == 100.0,
		"and a teleport drops all of it", "fov %.2f" % camera.fov)

	# The control: every setting at 0 and the same drop and strafe move nothing.
	feel.set_camera_motion_scales(0.0, 0.0, 0.0)
	feel.teleport(home + Vector3(0.0, 7.0, 0.0), yaw)
	var flat: Array = await run.call(still, int(1.6 / dt), &"dip")
	var level: Array = await run.call(right, int(0.8 / dt), &"roll")
	_check(flat.min() == 0.0 and level.min() == 0.0 and level.max() == 0.0,
		"with every camera motion setting at 0 nothing moves", "dip %.3f, roll %.2f" % [flat.min(), level.max()])

	playlot.remove_player(&"feel")
	_done()


func _section(title: String) -> void:
	_entered += 1
	print(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


## Runs the simulation for [param ticks], driving [param id] with [param command].
##
## Commands are applied and physics stepped per tick, so it reproduces on a loaded machine.
func _drive(
	id: StringName, command: GSFpsCommand, ticks: int
) -> void:
	var player: PlaylotPlayer = playlot.players[id]

	for _i in range(ticks):
		player.controller.apply_command(command.duplicate_command())
		await get_tree().physics_frame


# Picking players up

## Points [param id] at [param pitch] degrees (yaw 0, so along -Z) for [param ticks] ticks.
func _look(id: StringName, pitch: float, ticks: int) -> void:
	var look := GSFpsCommand.new()
	look.yaw = 0.0
	look.pitch = pitch
	await _drive(id, look, ticks)


func _beam_grab(holder: PlaylotPlayer) -> GSResult:
	return playlot.phys_gun_grab(
		holder, playlot.get_world_3d().direct_space_state,
		holder.eye_position(), holder.aim_direction(), Basis.IDENTITY, true
	)


var _ppu_pickup
var _ppu_held: PlaylotPlayer
var _ppu_took: GSResult
var _ppu_third: PlaylotPlayer

func _test_picking_players_up() -> void:
	_section("picking players up")

	var changed: GSResult = await playlot.change_map(&"pg_flatgrass")
	_check(changed.ok, "the sandbox loads")

	_ppu_pickup = playlot.pickup
	var holder := playlot.add_player(&"holder", "Holder")
	_ppu_held = playlot.add_player(&"held", "Held")

	# The empty corner the vehicles use, four metres apart along -Z, the holder facing the
	# other. Settled first, so nobody is falling when the beam reaches them.
	holder.teleport(Vector3(-60.0, 1.0, -40.0), 0.0)
	_ppu_held.teleport(Vector3(-60.0, 1.0, -44.0), 0.0)
	await _look(&"holder", 0.0, 30)
	await _look(&"held", 0.0, 30)
	var floor_y := _ppu_held.controller.state.position.y

	_ppu_took = _beam_grab(holder)
	_check(_ppu_took.ok, "the physics gun picks up the player in front of it", _ppu_took.error.message if not _ppu_took.ok else "")
	_check(_ppu_pickup.held_by(&"held") == &"holder" and _ppu_pickup.holding(&"holder") == &"held", "and both ends know who holds whom")
	_check(_ppu_held.riding, "and the held player stops walking", "a rider with no vehicle: not simulated, not predicted")
	_check(holder.phys_gun.held == null, "and no prop behind them was grabbed as well")

	# Look up: the held player goes up with the beam, whatever their own keys say.
	var up := 40.0
	holder.controller.state.pitch = up
	if holder.aim_direction().y < 0.0:
		up = -up
	var forward := GSFpsCommand.new()
	forward.move = Vector2(0.0, 1.0)
	_ppu_held.controller.apply_command(forward)
	await _look(&"holder", up, 60)
	var lifted := _ppu_held.controller.state.position.y - floor_y
	_check(lifted > 1.5, "looking up lifts them with the beam", "%.2f m off the floor" % lifted)
	var reach := _ppu_held.controller.state.position.distance_to(holder.controller.state.position)
	_check(reach < _ppu_pickup.reach + 1.0, "and they stay on the end of it", "%.2f m from the holder" % reach)
	_check(_ppu_held.global_position.is_equal_approx(_ppu_held.controller.state.position), "with the node and the movement state together")

	# Swing the beam down and let go mid-swing: a throw keeps the beam's velocity.
	await _look(&"holder", -up * 0.25, 4)
	playlot.phys_gun_release(holder)
	var thrown := _ppu_held.controller.state.velocity.length()
	_check(not _ppu_pickup.is_held(&"held") and not _ppu_held.riding, "letting go puts them back on their own legs")
	_check(thrown > 1.0, "and throws them with the beam's velocity", "%.2f m/s" % thrown)
	await _look(&"held", 0.0, 90)
	_check(_ppu_held.controller.state.time_since_grounded == 0.0, "and they land on their own feet", "%.2f s airborne" % _ppu_held.controller.state.time_since_grounded)

	# Immunity by role, and the override.
	_ppu_held.teleport(Vector3(-60.0, 1.0, -44.0), 0.0)
	await _look(&"holder", 0.0, 20)
	var roles := {&"held": PackedStringArray(["admin"]), &"holder": PackedStringArray()}
	_ppu_pickup.roles_fn = func(id: StringName) -> PackedStringArray: return roles.get(id, PackedStringArray())
	_ppu_pickup.immune_roles = PlaylotPickup.parse_roles("admin, vip")
	_ppu_took = _beam_grab(holder)
	_check(not _ppu_took.ok and not _ppu_pickup.is_held(&"held"), "an immune role cannot be picked up")
	_check(not _ppu_took.ok and _ppu_took.error.context.has("pickup"), "and the refusal says it was about a player, not a prop")
	_check(not _ppu_took.ok and _ppu_took.error.message.contains("admin"), "naming the role", _ppu_took.error.message if not _ppu_took.ok else "")
	_check(holder.phys_gun.held == null, "and nothing behind them is grabbed instead")
	roles[&"holder"] = PackedStringArray(["root"])
	_ppu_took = _beam_grab(holder)
	_check(_ppu_took.ok, "an override role picks them up anyway")
	_check(PlaylotPickup.parse_roles(" admin,,vip  root ") == PackedStringArray(["admin", "vip", "root"]), "a role list parses commas and spaces")

	# A holder who leaves lets go; a held player cannot pick anybody up.
	_ppu_took = _beam_grab(_ppu_held)
	_check(not _ppu_took.ok, "a held player cannot pick anybody up")
	_ppu_third = playlot.add_player(&"third", "Third")
	_ppu_third.teleport(Vector3(-60.0, 1.0, -36.0), 180.0)
	await _test_picking_players_up_2()

func _test_picking_players_up_2() -> void:
	await _look(&"third", 0.0, 10)
	playlot.remove_player(&"holder")
	await get_tree().physics_frame
	_check(not _ppu_pickup.is_held(&"held") and not _ppu_held.riding, "a holder leaving lets go of them")
	_check(_ppu_pickup.hold_count() == 0, "and holds nobody")

	# Off is off: the beam meets a player and does nothing to them.
	_ppu_pickup.enabled = false
	_ppu_held.teleport(Vector3(-60.0, 1.0, -40.0), 0.0)
	# Yaw 0 looks along -Z, from -36 toward them at -40. (It said 180 once, and this check
	# passed with the beam pointed at nobody.)
	var third_look := GSFpsCommand.new()
	third_look.yaw = 0.0
	await _drive(&"third", third_look, 20)
	_ppu_took = _beam_grab(_ppu_third)
	# Off, the beam skips players and falls through to the prop gun, which finds no prop.
	_check(not _ppu_pickup.is_held(&"held") and not _ppu_took.ok,
		"with picking up off, nobody is held", _ppu_took.error.message if not _ppu_took.ok else "held")

	_ppu_pickup.enabled = true
	_ppu_pickup.immune_roles = PackedStringArray()
	_ppu_pickup.roles_fn = Callable()

	# Creative mode: out of anybody's beam, and nobody's beam is theirs.
	_ppu_held.teleport(Vector3(-60.0, 1.0, -40.0), 0.0)
	await _drive(&"third", third_look, 10)
	var _creative := playlot.set_creative(&"held", true)
	_ppu_took = _beam_grab(_ppu_third)
	_check(not _ppu_took.ok and not _ppu_pickup.is_held(&"held") and _ppu_took.error.message.contains("creative"),
		"a player in creative mode cannot be picked up", _ppu_took.error.message if not _ppu_took.ok else "")
	var _off := playlot.set_creative(&"held", false)
	var _creative_third := playlot.set_creative(&"third", true)
	_ppu_took = _beam_grab(_ppu_third)
	_check(not _ppu_took.ok and not _ppu_pickup.is_held(&"held"), "and cannot pick anybody up")
	var _off_third := playlot.set_creative(&"third", false)
	_ppu_took = _beam_grab(_ppu_third)
	_check(_ppu_took.ok and _ppu_pickup.is_held(&"held"), "and with it off, both are ordinary again")
	playlot.phys_gun_release(_ppu_third)

	playlot.remove_player(&"held")
	playlot.remove_player(&"third")
	_done()


# Prop surfing

## Moves [param body] at [param velocity] for [param ticks] ticks, written every tick so
## nothing but this moves it, while [param rider] stands still on top.
func _slide(body: RigidBody3D, velocity: Vector3, rider: StringName, ticks: int) -> void:
	var still := GSFpsCommand.new()
	for i in ticks:
		body.linear_velocity = velocity
		body.angular_velocity = Vector3.ZERO
		await _drive(rider, still, 1)


func _test_riding_a_moving_prop() -> void:
	_section("riding a moving prop")

	# The lobby, whichever map the section before left loaded: the corner this uses is its.
	var on_lobby: GSResult = await playlot.change_map(&"pg_flatgrass")
	if not on_lobby.ok:
		_check(false, "the sandbox loads", on_lobby.error.message)
		_done()
		return

	var rider := playlot.add_player(&"surfer", "Surfer")
	playlot.props.limits.spawn_interval = 0.0
	# A 4 m platform floating in the empty vehicle corner, gravity off so only the test
	# moves it, and the rider stood on its middle.
	var deck := playlot.props.spawn(&"platform", &"surfer", Vector3(-60.0, 3.0, -60.0))
	var body := deck.body() as RigidBody3D if deck != null else null
	_check(body != null, "a platform to stand on")
	if body == null:
		_done()
		return
	body.gravity_scale = 0.0
	rider.teleport(Vector3(-60.0, 3.4, -60.0), 0.0)
	await _slide(body, Vector3.ZERO, &"surfer", 30)
	_check(rider.controller.state.is_grounded(), "the rider stands on it",
		"rider y %.2f, deck at %s, rider mask %d node mask %d, deck layer %d, ground %d" % [rider.controller.state.position.y, body.global_position, rider.collision_mask,
			rider.controller.tunables.collision_mask, body.collision_layer, rider.controller.state.ground_id])

	var start := rider.controller.state.position
	var deck_start := body.global_position
	await _slide(body, Vector3(3.0, 0.0, 0.0), &"surfer", 128)
	var moved := rider.controller.state.position.x - start.x
	var deck_moved := body.global_position.x - deck_start.x
	_check(deck_moved > 2.0 and absf(moved - deck_moved) < 0.4,
		"a moving prop carries whoever stands on it", "rider %.2f m, deck %.2f m" % [moved, deck_moved])
	_check(rider.global_position.is_equal_approx(rider.controller.state.position) and rider.controller.state.is_grounded(),
		"and they stay on it, node and state together")

	playlot.config.prop_surfing = false
	start = rider.controller.state.position
	deck_start = body.global_position
	await _slide(body, Vector3(-1.0, 0.0, 0.0), &"surfer", 64)
	moved = rider.controller.state.position.x - start.x
	_check(absf(moved) < 0.1 and body.global_position.x - deck_start.x < -0.4,
		"with prop surfing off, the deck slides out from under them", "rider %.2f m" % moved)
	playlot.config.prop_surfing = true

	var _gone := playlot.props.remove(deck.instance_id)
	playlot.remove_player(&"surfer")
	_done()


# Destruction

func _test_breaking_props() -> void:
	_section("breaking props")

	# The lobby, whichever map the section before left loaded: the corner this uses is its.
	var on_lobby: GSResult = await playlot.change_map(&"pg_flatgrass")
	if not on_lobby.ok:
		_check(false, "the sandbox loads", on_lobby.error.message)
		_done()
		return

	var player: PlaylotPlayer = playlot.players[&"bot"]
	playlot.props.limits.spawn_interval = 0.0
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	player.teleport(Vector3(-60.0, 1.0, -60.0), 90.0)
	await get_tree().physics_frame

	var eye := player.eye_position()
	var aim := player.aim_direction()
	var crate := playlot.props.spawn(&"crate", &"bot", eye + aim * 4.0)
	await get_tree().physics_frame

	# Off by default: a pistol emptied into a crate shoves it and breaks nothing.
	var rig := PlaylotZee.arm(
		player, playlot.weapon_def(&"zee_pistol"), ZeeWeaponRig.Role.SERVER, true,
		playlot.tick_rate, playlot.current_tick()
	)
	var _off := _fire_at_crates(rig, player, 120)
	_check(not playlot.config.destruction and crate.is_alive(), "with destruction off, shots break nothing")

	# On: the same shots, through the game's own shot handling, take its health and break it.
	playlot.config.destruction = true
	var before := playlot.props.world_count()
	crate.node.global_position = eye + aim * 4.0
	(crate.node as RigidBody3D).linear_velocity = Vector3.ZERO
	await get_tree().physics_frame
	var landed: Array = []
	var on_hit := func(by: StringName, victim: int, amount: float, _at: Vector3, killed: bool, _head: bool) -> void:
		landed.append([by, victim, amount, killed])
	playlot.hit_landed.connect(on_hit)
	var fired := _fire_at_crates(rig, player, 400, crate)
	playlot.hit_landed.disconnect(on_hit)
	var crate_key := Playlot.hit_victim_id(GSEntity.KIND_PROP, crate.instance_id)
	_check(not landed.is_empty() and landed.all(func(h: Array) -> bool: return h[0] == &"bot" and int(h[1]) == crate_key)
		and bool(landed[landed.size() - 1][3]) and landed.filter(func(h: Array) -> bool: return bool(h[3])).size() == 1,
		"every shot that took health is confirmed to the shooter, the last as the one that broke it",
		"%d confirmations for %d shots" % [landed.size(), fired])
	_check(not crate.is_alive(), "with it on, a pistol shoots a crate apart", "%d shots, health %.0f" % [fired, playlot.prop_damage.health_of(crate.instance_id)])
	var pieces := playlot.props.all_props().filter(func(p: GSPropInstance) -> bool: return p.def.id == &"debris")
	_check(pieces.size() > 0 and playlot.props.world_count() >= before - 1 + pieces.size(),
		"and leaves debris where it was", "%d pieces" % pieces.size())
	_check(pieces.size() > 0 and pieces[0].owner_id == &"", "owned by nobody")
	PlaylotZee.disarm(player)

	# Debris goes on its own.
	for i in range(int(playlot.config.debris_seconds * playlot.tick_rate) + 8):
		await get_tree().physics_frame
	var left := playlot.props.all_props().filter(func(p: GSPropInstance) -> bool: return p.def.id == &"debris")
	_check(left.is_empty(), "and the debris is cleared up after a few seconds", "%d left" % left.size())

	# A barrel goes up, and a crate beside it goes with it.
	var barrel := playlot.props.spawn(&"barrel", &"bot", Vector3(-50.0, 1.0, -60.0))
	var near := playlot.props.spawn(&"crate", &"bot", Vector3(-49.0, 0.6, -60.0))
	var far := playlot.props.spawn(&"crate", &"bot", Vector3(-40.0, 0.6, -60.0))
	await get_tree().physics_frame
	var _shot := playlot.hurt_prop(barrel.node, 100.0, &"bot")
	_check(not barrel.is_alive() and not near.is_alive() and far.is_alive(),
		"a barrel shot open goes up and takes the crate beside it, not the one ten metres off")
	_test_breaking_props_2()

func _test_breaking_props_2() -> void:

	# A protected owner's props do not break.
	var theirs := playlot.props.spawn(&"crate", &"other", Vector3(-45.0, 0.6, -55.0))
	playlot.props.set_protected(&"other", true)
	_check(not playlot.hurt_prop(theirs.node, 100.0, &"bot") and theirs.is_alive(), "a creative builder's crate does not break")
	playlot.props.set_protected(&"other", false)
	var slab := playlot.props.spawn(&"slab", &"bot", Vector3(-45.0, 1.0, -70.0))
	_check(slab != null and not playlot.hurt_prop(slab.node, 1000.0, &"bot") and slab.is_alive(),
		"and a slab, which somebody builds on, has no health to lose", "spawned %s" % (slab != null))

	playlot.config.destruction = false
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	_done()


## Holds and releases the trigger for up to [param ticks], every outcome through the game's own
## `player_shots_fired`; stops early once [param until] has broken. Returns the shots fired.
func _fire_at_crates(rig: ZeeWeaponRig, player: PlaylotPlayer, ticks: int, until: GSPropInstance = null) -> int:
	var fired := 0
	var state := player.controller.state
	for i in range(ticks):
		var held := GSFpsCommand.BUTTON_USER_0 if (i / 8) % 2 == 0 else 0
		var outcome := rig.simulate_tick(
			PlaylotZee.command_for(held, state.yaw, state.pitch, PlaylotZee.slot_of(rig)),
			playlot.current_tick() + i
		) if rig != null else null
		if outcome != null:
			fired += outcome.shots.size()
			playlot.player_shots_fired(player.player_id, outcome)
		if until != null and not until.is_alive():
			break
	return fired


# Buttons and doors
