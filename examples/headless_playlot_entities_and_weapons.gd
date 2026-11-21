extends "res://examples/headless_playlot_npc_chaser_and_spawn_providers.gd"

const WorkshopScript := preload("res://game/playlot_workshop.gd")

## An entity is a prop with a script, and the script is loaded by path.
##
## The scene is a bare `RigidBody3D`; the script comes from `meta` and is loaded by PATH, because a mounted pack's `class_name` globals are not registered in the host.
var _erts_at: Vector3
var _erts_npc: GSPropInstance
var _erts_body: PlaylotEntity
var _erts_mirrored_ent: bool
var _erts_before_count: int
var _erts_refused: GSPropInstance

func _test_entities_run_their_scripts() -> void:
	_section("entities that run their own scripts")

	# On the sandbox, deliberately: an NPC on the bhop map's gapped blocks falls off, and the
	# test would measure the terrain rather than the script.
	var loaded: GSResult = await playlot.change_map(&"pg_flatgrass")
	_check(loaded.ok, "the sandbox loads")

	playlot.spawn_player(&"bot")

	# Driven with an EMPTY command: `apply_command` leaves the pending command set, so the bot
	# arrives still holding forward and jump and auto-hops away; it also needs the third of a
	# second to fall onto the floor.
	await _drive(&"bot", GSFpsCommand.new(), 60)

	playlot.props.limits.spawn_interval = 0.0
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)

	_erts_at = Vector3(0.0, 1.2, 0.0)
	_erts_npc = playlot.props.spawn(&"npc_wanderer", &"bot", _erts_at)

	_check(_erts_npc != null, "an entity spawns")

	if _erts_npc == null:
		return

	_erts_body = _erts_npc.node as PlaylotEntity

	_check(_erts_body != null, "and its body is a PlaylotEntity, not a plain prop")
	_check(
		_erts_body != null and _erts_body.get_script() != null
		and _erts_body.get_script().resource_path
			== PlaylotSpawnables.script_of(_erts_npc.def),
		"running exactly the script its definition names",
		_erts_body.get_script().resource_path if _erts_body != null else "none"
	)
	_check(
		playlot.entities.has(_erts_body),
		"and it is on the list the simulation ticks"
	)

	# `_ready` has already run by the time the script is attached — the spawner adds
	# the body to the world before it emits — so `bind` is what an entity gets
	# instead, and an entity whose world never arrived would sit there being a crate.
	_check(_erts_body != null and _erts_body.game == playlot, "it knows its world")
	_check(_erts_body != null and _erts_body.instance == _erts_npc, "and its own row in the spawner")

	# It moves. Everything above is satisfied by an entity that does nothing at all.
	var before := _erts_body.global_position
	var ticks := 0
	var moved := 0.0

	while ticks < 240:
		await get_tree().physics_frame
		ticks += 1
		moved = maxf(moved, before.distance_to(_erts_body.global_position))

	_check(moved > 1.0, "and it walks about", "%.2f m" % moved)
	_check(_erts_body.age > 0.0, "counting simulated time, not wall time",
		"%.2f s" % _erts_body.age)
	await _test_entities_run_their_scripts_2()
	await _test_entities_run_their_scripts_3()

func _test_entities_run_their_scripts_2() -> void:

	# A held entity is furniture. Without that, the NPC fights the physics gun's
	# spring — the gun writes a velocity toward the goal and the NPC writes one
	# toward wherever it was walking — and the prop shudders between them.
	_erts_npc.held_by = &"bot"

	var held_at := _erts_body.global_position
	_erts_body.linear_velocity = Vector3.ZERO

	for _i in range(30):
		await get_tree().physics_frame

	_check(
		held_at.distance_to(_erts_body.global_position) < 0.6,
		"a held entity stops driving itself",
		"%.2f m" % held_at.distance_to(_erts_body.global_position)
	)

	_erts_npc.held_by = &""

	# A chaser goes toward somebody. The bot is at the origin-ish; put the chaser
	# out and check the distance closes, which is the one thing that distinguishes
	# this script from the wanderer.
	var player: PlaylotPlayer = playlot.players[&"bot"]
	var chaser := playlot.props.spawn(
		&"npc_chaser", &"bot", player.global_position + Vector3(14.0, 1.2, 0.0)
	)

	_check(chaser != null, "a chaser spawns")

	if chaser != null:
		var opening := chaser.position().distance_to(
			player.global_position
		)

		for _i in range(300):
			await get_tree().physics_frame

		var closing := chaser.position().distance_to(
			player.global_position
		)

		_check(
			closing < opening - 3.0,
			"and walks toward the player",
			"%.1f m -> %.1f m" % [opening, closing]
		)

	_test_a_chaser_commits(playlot)

	# A definition whose script is missing must not leave a body: it would sit there as a crate,
	# indistinguishable from an NPC with nothing to do.
	var broken := GSPropDef.make(&"npc_broken", PlaylotSpawnables.SCENE_ENTITY)
	broken.meta = {"kind": "entity", "script": "res://game/entities/nope.gd"}
	playlot.props.catalogue.add(broken)

	# Both refusals below log at ERROR on purpose.
	_erts_mirrored_ent = GSLog.mirror_to_engine
	GSLog.mirror_to_engine = false
	_erts_before_count = playlot.props.world_count()
	_erts_refused = playlot.props.spawn(&"npc_broken", &"bot", _erts_at)

	await get_tree().process_frame

func _test_entities_run_their_scripts_3() -> void:

	_check(
		playlot.props.world_count() == _erts_before_count,
		"an entity whose script is missing leaves nothing in the world",
		"%d -> %d" % [_erts_before_count, playlot.props.world_count()]
	)
	_check(
		_erts_refused == null or not _erts_refused.is_alive(),
		"and its row is dead rather than counted against a budget"
	)

	# One that points at a real script which is not an entity is the same failure by
	# a different route, and it is the one a copy-paste actually produces.
	var wrong := GSPropDef.make(&"npc_wrong", PlaylotSpawnables.SCENE_ENTITY)
	wrong.meta = {"kind": "entity", "script": "res://game/playlot_config.gd"}
	playlot.props.catalogue.add(wrong)

	_erts_before_count = playlot.props.world_count()
	playlot.props.spawn(&"npc_wrong", &"bot", _erts_at)

	await get_tree().process_frame

	_check(
		playlot.props.world_count() == _erts_before_count,
		"and so does one whose script is not an entity"
	)
	GSLog.mirror_to_engine = _erts_mirrored_ent

	playlot.props.catalogue.remove(&"npc_broken")
	playlot.props.catalogue.remove(&"npc_wrong")
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)

	await get_tree().process_frame

	_check(playlot.entities.is_empty(), "clearing the world empties the tick list")
	_done()


## zee-gs-weapons: the pack in the menu, a server's rig firing from the eye, and a shot that shoves a crate.
##
## The aim is the check that matters: without `PlaylotPlayer.component()` a shot leaves northwards from the feet and every other number is still right.
var _zw_player: PlaylotPlayer
var _zw_eye: Vector3
var _zw_aim: Vector3
var _zw_crate: GSPropInstance
var _zw_shots: Array[GSShot]
var _zw_moved: int
var _zw_state

func _test_zee_weapons() -> void:
	_section("zee-gs-weapons")

	var zee := PlaylotZee.defs()

	# A delivered game has only what is vendored in assets/ (zee-gs-weapons tools/sync-art.sh).
	var models := ZeeWeaponArtTable.validate_models()
	_check(models.ok, "every model the weapon art table names is vendored",
		"" if models.ok else models.error.message)

	_check(zee.size() == ZeeWeaponIds.all().size(), "every weapon in the pack is offered",
		"%d of %d" % [zee.size(), ZeeWeaponIds.all().size()])

	var usable := 0
	var offered := 0
	for def in zee:
		if def.validate().ok:
			usable += 1
		if playlot.weapon_def(def.id) == def or playlot.weapon_def(def.id) != null:
			offered += 1
	_check(usable == zee.size(), "each one a usable definition with no script")
	_check(offered == zee.size(), "and each one in the game's own list, which the menu shows")
	_check(
		playlot.weapon_def(&"launcher") != null
			and not PlaylotZee.is_zee(playlot.weapon_def(&"launcher")),
		"the pack's launcher does not take the toy launcher's id"
	)
	_check(
		Array(PlaylotWeapons.categories(playlot.weapons)).has("sidearms"),
		"the menu's categories come from the pack's slots"
	)

	_zw_player = playlot.players[&"bot"]
	playlot.props.limits.spawn_interval = 0.0
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	_zw_player.teleport(Vector3(-60.0, 1.0, -60.0), 90.0)
	await get_tree().physics_frame

	var rig := PlaylotZee.arm(
		_zw_player, playlot.weapon_def(&"zee_pistol"), ZeeWeaponRig.Role.SERVER, true,
		playlot.tick_rate, playlot.current_tick(), null, playlot.ads_rules
	)
	_check(rig != null and _zw_player.zee_rig == rig, "a server's rig goes on the player")
	_check(rig != null and rig.ads_rules == playlot.ads_rules and rig.ads_move_scale() == 1.0,
		"and takes the game's zee_ads_rules without slowing an unaimed player")
	_check(_zw_player.component(&"GSFpsController") == _zw_player.controller,
		"and the player answers gs-weapon's controller lookup")

	# A crate four metres along the way the player faces.
	_zw_eye = _zw_player.eye_position()
	_zw_aim = _zw_player.aim_direction()
	_zw_crate = playlot.props.spawn(&"crate", &"bot", _zw_eye + _zw_aim * 4.0)
	await get_tree().physics_frame

	_zw_shots = []
	_zw_moved = 0
	_zw_state = _zw_player.controller.state

	for i in range(200):
		var held := GSFpsCommand.BUTTON_USER_0 if (i / 20) % 2 == 0 else 0
		var outcome := rig.simulate_tick(
			PlaylotZee.command_for(held, _zw_state.yaw, _zw_state.pitch, PlaylotZee.slot_of(rig)),
			playlot.current_tick() + i
		) if rig != null else null
		if outcome != null:
			_zw_shots.append_array(outcome.shots)
			_zw_moved += PlaylotZee.shove_props(_zw_player, outcome, true)
		if _zw_moved > 0:
			break

	_check(not _zw_shots.is_empty(), "it fires", "%d shots" % _zw_shots.size())
	await _test_zee_weapons_2()

func _test_zee_weapons_2() -> void:

	if not _zw_shots.is_empty():
		var first := _zw_shots[0]
		_check(first.origin.distance_to(_zw_eye) < 0.5, "from the eye, not the feet",
			"%.2f m off" % first.origin.distance_to(_zw_eye))
		_check(first.direction.normalized().dot(_zw_aim) > 0.98, "the way the player is facing",
			"dot %.3f" % first.direction.normalized().dot(_zw_aim))

	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(_zw_moved > 0 and _zw_crate != null and _zw_crate.body().linear_velocity.dot(_zw_aim) > 0.5,
		"and with the arena off it shoves the crate it hits, away from the shooter",
		"%.2f m/s along the aim" % (_zw_crate.body().linear_velocity.dot(_zw_aim) if _zw_crate != null else 0.0))

	PlaylotZee.disarm(_zw_player)
	_check(_zw_player.zee_rig == null, "disarmed, the rig is gone")

	# [b]The pack is written at 64 Hz and this server runs 128[/b]; until gs-weapon scaled
	# a row by its authored_tick_rate every zee weapon here fired, reloaded and deployed
	# twice as fast. A second on an SMG's trigger is as many shots as at 64 Hz.
	var smg := PlaylotZee.arm(
		_zw_player, playlot.weapon_def(&"zee_smg"), ZeeWeaponRig.Role.SERVER, true,
		playlot.tick_rate, playlot.current_tick()
	)
	var rate := playlot.tick_rate
	_check(smg != null and smg.arsenal.tick_rate == rate,
		"a zee rig's arsenal runs at the server's rate", "%d Hz" % rate)
	if smg != null:
		var row := smg.current_def()
		var base := playlot.current_tick() + 1000
		var fired := 0
		for i in range(rate * 3):
			var held := GSFpsCommand.BUTTON_USER_0 if i >= rate * 2 else 0
			var out := smg.simulate_tick(
				PlaylotZee.command_for(held, _zw_state.yaw, _zw_state.pitch, PlaylotZee.slot_of(smg)),
				base + i
			)
			if out != null and out.used and i >= rate * 2:
				fired += 1
		var at_64 := int(ceil(float(ZeeWeaponPack.TICK_RATE) / float(row.use_interval_ticks)))
		_check(fired == at_64, "a second of SMG fire is as many shots at %d Hz as at 64" % rate,
			"%d here, %d at 64" % [fired, at_64])
		var reload_here := float(smg.arsenal.ticks_for(row, row.reload_ticks)) / float(rate)
		var deploy_here := float(smg.arsenal.ticks_for(row, row.deploy_ticks)) / float(rate)
		var tick64 := 1.0 / float(ZeeWeaponPack.TICK_RATE)
		_check(
			absf(reload_here - float(row.reload_ticks) * tick64) <= tick64
				and absf(deploy_here - float(row.deploy_ticks) * tick64) <= tick64,
			"and its reload and deploy take the same seconds",
			"reload %.3f s, deploy %.3f s" % [reload_here, deploy_here]
		)
	PlaylotZee.disarm(_zw_player)
	_test_shared_shot_sound()

	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	_done()


## Each weapon picked used to build its own layered shot on its first shot (~30 ms, ~30 nodes); the client's
## one PlaylotShotSound now plays every rig's.
func _test_shared_shot_sound() -> void:
	var sound := preload("res://game/client/playlot_shot_sound.gd").new()
	add_child(sound)
	var t0 := Time.get_ticks_usec()
	var warmed: bool = sound.warm()
	var warm_us := Time.get_ticks_usec() - t0
	if not warmed:
		_check(not ZeeShotLayers.available(), "the shared shot sound builds wherever gs-audio's stock is linked")
		sound.queue_free()
		return
	var first := ZeeShotFx.new()
	var second := ZeeShotFx.new()
	for fx in [first, second]:
		add_child(fx)
		sound.attach(fx)
	var heard: Array = []
	second.heard.connect(func(stream: AudioStream) -> void: heard.append(stream))
	var at := Vector3(-60.0, 1.5, -60.0)
	var played_a: bool = first.shot_sound.call(&"zee_pistol", GSWeaponOutcome.KIND_SHOT, at, false)
	var played_b: bool = second.shot_sound.call(&"zee_rifle", GSWeaponOutcome.KIND_SHOT, at, false)
	_check(played_a and played_b and sound.played == 2 and heard.size() == 1,
		"two armed rigs play their shots through the client's one layered shot, and still say what was heard",
		"%s %s, %d played, %d heard" % [played_a, played_b, sound.played, heard.size()])
	_check(sound.get_child_count() == 1 and first.get(&"_layers") == null and second.get(&"_layers") == null,
		"so neither rig builds layers of its own on its first shot")
	print("    bench shot layers built once: %.2f ms" % (warm_us / 1000.0))
	first.queue_free()
	second.queue_free()
	sound.queue_free()


## The Workshop in solo play: packs a player subscribed to land on the Q menu, only in solo.
var _wx_index: GSContentIndex
var _wx_own_weapons: int
var _wx_own_props: int
var _wx_changes: Array
var _wx_shop: WorkshopScript
var _wx_sidearm_def: PlaylotWeaponDef
var _wx_menu: PlaylotSpawnMenu
var _wx_stack: GSScreenStack
var _wx_player: PlaylotPlayer
var _wx_before: int

func _test_workshop() -> void:
	_section("the workshop")

	# The pack's files, written where a pack would be mounted: user://, which is not res://.
	var root := "user://workshop_fixture"
	DirAccess.make_dir_recursive_absolute(root.path_join("defs"))
	var sidearm := PlaylotZee.catalogue().get_def(&"pistol").duplicate() as GSWeaponDef
	sidearm.id = &"fixture_sidearm"
	sidearm.display_name = "Fixture Sidearm"
	var crate := GSPropDef.make(&"fixture_crate", "res://game/prop.tscn")
	crate.display_name = "Fixture Crate"
	var npc := GSNpcDef.make(&"fixture_guard", "")
	_check(ResourceSaver.save(sidearm, root + "/defs/sidearm.tres") == OK
		and ResourceSaver.save(crate, root + "/defs/crate.tres") == OK
		and ResourceSaver.save(npc, root + "/defs/guard.tres") == OK, "the fixture pack's definitions are written")

	var provides := {
		"schema": 1, "title": "Fixture Pack", "kinds": ["weapon", "prop", "npc"],
		"categories": [{"id": "sidearm", "name": "Sidearms"}, {"id": "stuff", "name": "Stuff"}],
		"entries": [
			{"kind": "weapon", "id": "fixture_sidearm", "name": "Fixture Sidearm", "def": "defs/sidearm.tres", "slot": 2, "category": "sidearm"},
			{"kind": "prop", "id": "fixture_crate", "name": "Fixture Crate", "def": "defs/crate.tres", "category": "stuff"},
			{"kind": "npc", "id": "fixture_guard", "name": "Fixture Guard", "def": "defs/guard.tres", "category": "stuff"},
		],
	}
	_wx_index = GSContentIndex.new()
	_wx_index.set_session(GSContentIndex.SESSION_SOLO)
	var added := _wx_index.add_pack({
		"content_id": "tmc/fixture-pack", "version": "1.0.0", "prefix": root,
		"session": "solo", "source": "subscription", "provides": provides,
	})
	_check(added.ok, "the pack is in the index", "" if added.ok else added.error.message)

	_wx_own_weapons = playlot.weapons.size()
	_wx_own_props = playlot.props.catalogue.size()
	_wx_changes = [0]
	playlot.workshop_changed.connect(func() -> void: _wx_changes[0] += 1)
	_wx_shop = playlot.follow_workshop(_wx_index)
	_check(_wx_changes[0] == 1, "following announces what is already mounted", str(_wx_changes[0]))

	_wx_sidearm_def = playlot.weapon_def(&"ws_fixture_sidearm")
	_check(_wx_sidearm_def != null and _wx_sidearm_def.meta.get("pack_title") == "Fixture Pack",
		"solo: the pack weapon is one of the game's weapons, labelled with its pack")
	_check(playlot.weapons.size() == _wx_own_weapons + 1, "and the game's own are untouched",
		"%d -> %d" % [_wx_own_weapons, playlot.weapons.size()])
	_check(playlot.props.catalogue.has(&"ws_fixture_crate"), "solo: the pack prop is in the prop catalogue")
	var guard := playlot.props.catalogue.get_prop(&"ws_fixture_guard")
	_check(guard != null and PlaylotSpawnables.kind_of(guard) == PlaylotSpawnables.Kind.ENTITY
		and guard.limit_group == &"npcs", "solo: the pack npc is an entity counted as an NPC")
	_check(playlot.props.catalogue.size() == _wx_own_props + 2, "and the game's own props are untouched")
	_check(_wx_shop.rows().size() == 3, "three rows for the menu", str(_wx_shop.rows().size()))

	# The menu: a tab per pack, the pack's items grouped by its categories, none on the built-in tabs.
	_wx_menu = PlaylotSpawnMenu.new()
	_wx_menu.catalogue = playlot.props.catalogue
	_wx_menu.weapons = playlot.weapons
	_wx_menu.set_pack_rows(_wx_shop.rows())
	add_child(_wx_menu)
	_wx_stack = GSScreenStack.new()
	add_child(_wx_stack)
	var _ready_result := _wx_stack.setup()
	var _registered := _wx_stack.register(_wx_menu)
	var _pushed := _wx_stack.push(_wx_menu.screen_id())
	await get_tree().process_frame

	var pack_tab := PlaylotSpawnMenu.Tab.size() as PlaylotSpawnMenu.Tab
	_wx_menu.show_tab(pack_tab)
	await get_tree().process_frame
	await _test_workshop_2()
	await _test_workshop_3()
	_wx_changes = []

func _test_workshop_2() -> void:
	_check(_wx_menu.describe()["pack_tabs"] == ["Fixture Pack"] and _wx_menu.describe()["tab"] == "Fixture Pack",
		"the menu has a tab for the pack", str(_wx_menu.describe()["pack_tabs"]))
	_check(_wx_menu.shown().size() == 3 and _wx_menu.shown().has(&"ws_fixture_sidearm")
		and _wx_menu.shown().has(&"ws_fixture_crate") and _wx_menu.shown().has(&"ws_fixture_guard"),
		"holding its weapon, prop and npc", str(_wx_menu.shown()))
	_check(_wx_menu.card_for(&"ws_fixture_sidearm") != null and _wx_menu.card_for(&"ws_fixture_sidearm").tooltip_text.contains("Fixture Pack"),
		"each card says which pack it is from")
	_wx_menu.show_tab(PlaylotSpawnMenu.Tab.WEAPONS)
	await get_tree().process_frame
	_check(not _wx_menu.shown().has(&"ws_fixture_sidearm") and _wx_menu.shown().has(&"launcher"),
		"the Weapons tab keeps only the game's own")
	_wx_menu.show_tab(PlaylotSpawnMenu.Tab.PROPS)
	await get_tree().process_frame
	_check(not _wx_menu.shown().has(&"ws_fixture_crate"), "and so does the Props tab")
	_wx_menu.show_tab(PlaylotSpawnMenu.Tab.ENTITIES)
	await get_tree().process_frame
	_check(not _wx_menu.shown().has(&"ws_fixture_guard"), "and the Entities tab")

	# Spawning: the prop and the npc through the spawner, the weapon through a rig that fires.
	_wx_player = playlot.players[&"bot"]
	playlot.props.limits.spawn_interval = 0.0
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	_wx_player.teleport(Vector3(-60.0, 1.0, -60.0), 90.0)
	await get_tree().physics_frame
	var spawned_crate := playlot.props.spawn(&"ws_fixture_crate", &"bot", _wx_player.eye_position() + _wx_player.aim_direction() * 3.0)
	var spawned_guard := playlot.props.spawn(&"ws_fixture_guard", &"bot", _wx_player.eye_position() + _wx_player.aim_direction() * 6.0)
	await get_tree().physics_frame
	_check(spawned_crate != null and spawned_crate.node != null, "the pack prop spawns")
	_check(spawned_guard != null and spawned_guard.node != null
		and str(spawned_guard.node.get_script().resource_path).ends_with("npc_wanderer.gd"),
		"and the pack npc spawns running a script")

	var rig := PlaylotZee.arm(_wx_player, _wx_sidearm_def, ZeeWeaponRig.Role.SERVER, true,
		playlot.tick_rate, playlot.current_tick())
	_check(rig != null and rig.arsenal.catalogue.has(&"fixture_sidearm"),
		"the pack weapon arms: the rig holds an id the built-in pack does not have")
	var shots := 0
	var state := _wx_player.controller.state
	for i in range(120):
		var held := GSFpsCommand.BUTTON_USER_0 if (i / 10) % 2 == 0 else 0
		var outcome := rig.simulate_tick(
			PlaylotZee.command_for(held, state.yaw, state.pitch, PlaylotZee.slot_of(rig)),
			playlot.current_tick() + i
		) if rig != null else null
		if outcome != null:
			shots += outcome.shots.size()
	_check(shots > 0, "and it fires", str(shots))
	_check(PlaylotZee.catalogue().has(&"fixture_sidearm") == false,
		"without leaking into the table a server reads")
	PlaylotZee.disarm(_wx_player)
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)

	# A pack mounted later arrives; a map pack lists on the map menu.
	_wx_before = _wx_changes[0]
	var _late := _wx_index.add_pack({
		"content_id": "tmc/fixture-maps", "version": "1.0.0", "prefix": "res://",
		"session": "solo", "source": "subscription",
		"provides": {"schema": 1, "title": "Fixture Maps", "kinds": ["map"], "entries": [
			{"kind": "map", "id": "ws_lobby", "name": "Fixture Lobby", "scene": "maps/pg_flatgrass.tscn", "map_kind": "sandbox"},
			{"kind": "map", "id": "ws_arena", "name": "Fixture Arena", "scene": "maps/pg_flatgrass.tscn", "map_kind": "arena"},
		]},
	})
	_check(not playlot.maps.catalogue.available().filter(func(m: GSMapDef) -> bool: return m.id == &"ws_lobby").is_empty(),
		"solo: a sandbox map pack is on the map list")
	_check(playlot.maps.catalogue.available().filter(func(m: GSMapDef) -> bool: return m.id == &"ws_arena").is_empty(),
		"and a map of a kind the game does not accept is not")
	_check(_wx_changes[0] == _wx_before, "a pack with nothing for the menu does not redraw it")

func _test_workshop_3() -> void:

	# Online: all of it is gone, from every list, and comes back with solo. The pack's tab is
	# the open one, so the fall back to Props is what is being checked.
	_wx_menu.show_tab(PlaylotSpawnMenu.Tab.size() as PlaylotSpawnMenu.Tab)
	_wx_index.set_session(GSContentIndex.SESSION_ONLINE)
	_check(playlot.weapon_def(&"ws_fixture_sidearm") == null and playlot.weapons.size() == _wx_own_weapons,
		"online: the pack weapon is not on the menu")
	_check(not playlot.props.catalogue.has(&"ws_fixture_crate") and not playlot.props.catalogue.has(&"ws_fixture_guard")
		and playlot.props.catalogue.size() == _wx_own_props, "online: the pack props and npcs are gone")
	_check(_wx_shop.rows().is_empty(), "online: no rows")
	_check(playlot.maps.catalogue.available().filter(func(m: GSMapDef) -> bool: return m.id == &"ws_lobby").is_empty(),
		"online: the pack map is gone")
	_wx_menu.set_pack_rows(_wx_shop.rows())
	await get_tree().process_frame
	_check(_wx_menu.describe()["pack_tabs"] == [] and _wx_menu.describe()["tab"] == "PROPS",
		"online: the menu has no pack tab, and the one that was open fell back")
	_check(_wx_changes[0] > _wx_before, "and the session change was announced")
	_wx_index.set_session(GSContentIndex.SESSION_SOLO)
	_check(playlot.weapon_def(&"ws_fixture_sidearm") != null and playlot.props.catalogue.has(&"ws_fixture_crate"),
		"back in solo they return")

	# The real zee pack, as a fixture of its own: all 27 weapons, grouped by its categories.
	# Found through addons/zee_weapons rather than as ../zee-gs-weapons: the link points
	# at the sibling checkout on a dev box and into .deps/ under CI, which clones no siblings.
	var zee_link := ProjectSettings.globalize_path("res://addons/zee_weapons")
	var zee_dir := ProjectSettings.globalize_path("res://").path_join("../zee-gs-weapons").simplify_path()
	var addons_dir := DirAccess.open(zee_link.get_base_dir())
	if addons_dir != null and addons_dir.is_link(zee_link):
		var target := addons_dir.read_link(zee_link)
		if target.is_relative_path():
			target = zee_link.get_base_dir().path_join(target)
		zee_dir = target.simplify_path().get_base_dir().get_base_dir()
	if FileAccess.file_exists(zee_dir.path_join("provides.json")):
		var zee_provides: Variant = JSON.parse_string(FileAccess.get_file_as_string(zee_dir.path_join("provides.json")))
		var _zee := _wx_index.add_pack({
			"content_id": "gamemann/zee-gs-weapons", "version": "1.0.0", "prefix": zee_dir,
			"session": "solo", "source": "subscription", "provides": zee_provides,
		})
		var zee_rows := _wx_shop.rows().filter(func(r: Dictionary) -> bool: return r["pack_title"] == "Zee Weapons")
		_check(zee_rows.size() == 27, "zee-gs-weapons' own provides.json lists 27 weapons", str(zee_rows.size()))
		_check(zee_rows.all(func(r: Dictionary) -> bool: return playlot.weapon_def(r["id"]) != null),
			"each a weapon the game can arm")
		var smg := playlot.weapon_def(&"ws_smg")
		var smg_rig := PlaylotZee.arm(_wx_player, smg, ZeeWeaponRig.Role.SERVER, true,
			playlot.tick_rate, playlot.current_tick())
		_check(smg_rig != null and smg_rig.arsenal.catalogue.has(&"smg"), "and a pack weapon that shares a built-in id arms with the built-in's art and rules")
		PlaylotZee.disarm(_wx_player)
	else:
		_check(false, "zee-gs-weapons is next to this game", zee_dir)

	_test_workshop_trails()

	_wx_menu.queue_free()
	_wx_stack.queue_free()
	playlot.unfollow_workshop()
	_check(playlot.weapon_def(&"ws_fixture_sidearm") == null and not playlot.props.catalogue.has(&"ws_fixture_crate")
		and playlot.weapons.size() == _wx_own_weapons and playlot.props.catalogue.size() == _wx_own_props,
		"unfollowing leaves the game's lists as they were")
	_done()


## A trail pack is data (kind `trail`, `def: trails.json`). The host carries gs-trail, not this
## game, so the rows and the equip follow what the host has; either way nothing breaks.
func _test_workshop_trails() -> void:
	var accepts: Variant = (JSON.parse_string(FileAccess.get_file_as_string("res://provides.json")) as Dictionary).get("accepts", {})
	_check(accepts is Dictionary and (accepts as Dictionary).get("kinds", []).has("trail"),
		"provides.json accepts trail packs, so the site offers them")
	var root := "user://workshop_trails"
	DirAccess.make_dir_recursive_absolute(root)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.ORANGE)
	var _png := img.save_png(root.path_join("spark.png"))
	var index_file := FileAccess.open(root.path_join("trails.json"), FileAccess.WRITE)
	index_file.store_string(JSON.stringify({"trails": [{"id": "spark", "title": "Spark", "image": "spark.png",
		"width": 0.4, "lifetime": 1.0, "color": "#ffffff", "blend": "add", "access": "public", "price": 0}]}))
	index_file.close()
	var added := _wx_index.add_pack({
		"content_id": "tmc/fixture-trails", "version": "1.0.0", "prefix": root + "/",
		"session": "solo", "source": "subscription",
		"provides": {"schema": 1, "title": "Fixture Trails", "kinds": ["trail"], "entries": [
			{"kind": "trail", "id": "spark", "name": "Spark", "thumbnail": "spark.png", "def": "trails.json"},
		]},
	})
	_check(added.ok, "a trail pack is in the index", "" if added.ok else added.error.message)
	var hosted := WorkshopScript.PlaylotTrails.available()
	var trail_rows := _wx_shop.rows().filter(func(r: Dictionary) -> bool: return r["kind"] == &"trail")
	_check(trail_rows.size() == (1 if hosted else 0) and (not hosted or trail_rows[0].get("trail") == "spark"),
		"its trail is a menu row exactly when the host carries gs-trail", "hosted=%s rows=%d" % [hosted, trail_rows.size()])
	var worn := _wx_shop.trails.equip(_wx_player, "spark")
	_check(worn.ok == hosted and (_wx_player.get_node_or_null("PackTrail") != null) == hosted,
		"and the player wears it then, and is refused cleanly otherwise", "" if worn.ok else worn.error.message)
	var off := _wx_shop.trails.equip(_wx_player, "off")
	_check(off.ok, "taking it off always works")


## Weapons: a script loaded by path, held rather than spawned.
var _w_defs: Array[PlaylotWeaponDef]
var _w_launcher: WeaponScript
var _w_fired: GSResult
var _w_stuck: GSPropInstance

func _test_weapons() -> void:
	_section("weapons")

	_w_defs = PlaylotWeapons.built_in()

	_check(_w_defs.size() >= 3, "the build ships an arsenal", "%d" % _w_defs.size())
	_check(
		# Not the weapons a linked spawn provider taught the game (`meta.provider`).
		playlot.weapons.filter(func(d: Variant) -> bool: return not d.meta.has("provider")).size()
			== _w_defs.size() + PlaylotZee.defs().size(),
		"and the game offers it, with zee-gs-weapons after it"
	)

	for def in _w_defs:
		_check(def.validate().ok, "'%s' is a usable definition" % def.id)

	_w_launcher = PlaylotWeapons.make(
		PlaylotWeapons.find(_w_defs, &"launcher")
	)

	_check(_w_launcher != null, "a weapon is built from its definition")
	_check(
		_w_launcher != null and _w_launcher.get_script().resource_path
			== PlaylotWeapons.find(_w_defs, &"launcher").script_path,
		"running exactly the script it names"
	)

	# The two ways a catalogue entry is wrong, and neither may hand back a working-
	# looking weapon: a base `PlaylotWeapon` whose buttons do nothing is
	# indistinguishable from a weapon that is fine and pointed at nothing.
	var mirrored_wpn := GSLog.mirror_to_engine
	GSLog.mirror_to_engine = false
	var missing := PlaylotWeaponDef.make(&"x", "X", "res://game/weapons/nope.gd")
	_check(
		PlaylotWeapons.make(missing) == null,
		"a weapon whose script is missing is refused"
	)

	var not_a_weapon := PlaylotWeaponDef.make(
		&"y", "Y", "res://game/playlot_config.gd"
	)
	_check(
		PlaylotWeapons.make(not_a_weapon) == null,
		"and so is one whose script is not a weapon"
	)
	GSLog.mirror_to_engine = mirrored_wpn

	# The launcher fires whatever the menu armed, which is what saves it having a
	# second list of ammunition and a second way to choose from it.
	playlot.props.limits.spawn_interval = 0.0
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)

	_w_launcher.equip(playlot, PlaylotWeapons.find(_w_defs, &"launcher"))
	_w_launcher.wielder = &"bot"
	_w_launcher.armed = &"beach_ball"

	_w_fired = _w_launcher.primary(null, Vector3(0.0, 6.0, 0.0), Vector3.FORWARD)

	_check(_w_fired.ok, "the launcher fires")
	await _test_weapons_2()
	_test_weapons_3()

func _test_weapons_2() -> void:

	if _w_fired.ok:
		var shot := _w_fired.value as GSPropInstance

		_check(shot.def.id == &"beach_ball", "the prop the menu armed")
		_check(
			shot.body().linear_velocity.length() > 10.0,
			"at a muzzle velocity",
			"%.1f m/s" % shot.body().linear_velocity.length()
		)

		# A muzzle velocity, not an impulse. An impulse is divided by the mass, which
		# is right for a punt and exactly wrong here: a launcher whose boulder leaves
		# at a fortieth of the speed of its ball is one nobody can aim.
		_w_launcher.armed = &"boulder"

		var heavy := _w_launcher.primary(null, Vector3(0.0, 6.0, 0.0), Vector3.FORWARD)

		_check(
			heavy.ok and is_equal_approx(
				(heavy.value as GSPropInstance).body().linear_velocity.length(),
				shot.body().linear_velocity.length()
			),
			"and a 900 kg prop leaves as fast as a 2 kg one"
		)

	# Armed with something the catalogue no longer has — a map change can do that —
	# it falls back rather than being refused with "no such prop", which reads as the
	# weapon being broken rather than as the ammunition being gone.
	_w_launcher.armed = &"nothing_like_this"

	var fallback := _w_launcher.primary(null, Vector3(0.0, 6.0, 0.0), Vector3.FORWARD)

	_check(fallback.ok, "an armed prop that no longer exists falls back")

	# The impulse gun shoves what is near it, and leaves frozen props alone: freezing
	# is how a builder says "this is finished", and a blast that undid it would make
	# the two tools fight.
	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)

	var loose := playlot.props.spawn(&"crate", &"bot", Vector3(2.0, 1.0, 0.0))
	_w_stuck = playlot.props.spawn(&"crate", &"bot", Vector3(-2.0, 1.0, 0.0))

	GSPhysGun.set_frozen(_w_stuck, true)

	var impulse := PlaylotWeapons.make(PlaylotWeapons.find(_w_defs, &"impulse"))
	impulse.equip(playlot, PlaylotWeapons.find(_w_defs, &"impulse"))
	impulse.wielder = &"bot"

	loose.body().linear_velocity = Vector3.ZERO

	var blast := impulse.primary(null, Vector3.ZERO, Vector3.FORWARD)

	# Two steps, not one: an impulse is not readable in `linear_velocity` until the step that
	# consumes it has run, and one physics frame lands before that step.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(blast.ok and int(blast.value) >= 1, "the impulse gun moves something")
	_check(
		loose.body().linear_velocity.length() > 1.0,
		"a loose prop is shoved",
		"%.1f m/s" % loose.body().linear_velocity.length()
	)

func _test_weapons_3() -> void:
	_check(
		_w_stuck.body().linear_velocity.length() < 0.5,
		"and a frozen one is left alone",
		"%.1f m/s" % _w_stuck.body().linear_velocity.length()
	)

	# The remover's right click clears what you own, and goes through the spawner so
	# the budget it frees is real.
	var remover := PlaylotWeapons.make(PlaylotWeapons.find(_w_defs, &"remover"))
	remover.equip(playlot, PlaylotWeapons.find(_w_defs, &"remover"))
	remover.wielder = &"bot"

	var cleared := remover.secondary(null, Vector3.ZERO, Vector3.FORWARD)

	_check(cleared.ok and int(cleared.value) >= 2, "the remover clears your props")
	_check(playlot.props.player_count(&"bot") == 0, "and the budget goes with them")

	playlot.props.clear_all(GSPropSpawner.REASON_ADMIN)
	_done()
