extends "playlot_client_fx.gd"

const PlaylotMapSources := preload("client/playlot_map_sources.gd")



func _ready() -> void:
	# First, before anything can be drawn: the map arrives after this node is in the tree.
	_build_gate()

	playlot = Playlot.new()
	playlot.name = "Playlot"

	# A networked client is not authoritative, and this is where that is decided: set afterwards,
	# `Playlot._ready` would already have spent a map load believing it owned the world.
	if config == null:
		config = PlaylotConfig.new()

	# zee-gs-weapons' art is this game's copy of it, wherever this game is mounted.
	PlaylotZee.use_this_games_art()

	# The NPCs' clip sets, on a worker while the map below loads, not on the main thread under the cover.
	var _clips := PlaylotClientPrewarm.prefetch(config)

	# Looked up when nobody handed it over: a pack's client scene is instantiated by
	# `GSClientLink._on_load_game`, which sets nothing on it. The export still wins, so two shells
	# in one process keep their own links.
	if link == null and not platform.offline:
		link = platform.link as Node

	if link != null:
		config.authoritative = false

	# Before the playlot: `Playlot._ready` loads its first map inside `add_child`, and a
	# generated map asks `GSRegistry` for a seed source then. One registered afterwards is silently
	# ignored (a fixed seed is a legitimate fallback).
	presentation = PlaylotPresentation.new()
	presentation.name = "Presentation"
	presentation.client = self
	add_child(presentation)
	GSLog.result("playlot.client", "the presentation layer", presentation.setup())
	_wire_chat_window()

	playlot.config = config
	playlot.config_file = config_file
	# The map's toys are heard: a bounce, a knock, a switch, a honk. Before the first map.
	var _toys := playlot.toy_sound.connect(func(id: StringName, at: Vector3, strength: float) -> void:
		if presentation != null:
			var _played := presentation.on_toy(id, at, strength))
	add_child(playlot)

	# Custom maps the server's game names as dependencies (playlot-maps): fetched in
	# the same content sync as this game, so mounted by now. Added before any map change can
	# name one, which on a client is the HELLO still to come.
	_add_dependency_maps()
	# Solo in the client shell, the playlot added the packs the shell mounted itself, before its
	# first map (`Playlot.solo_map_dirs`), so a "Play map" link can start on one of them.

	# The playlot loads its own first map and this waits for it: `initial_map` is layered config, so loading
	# one here would ignore --pg-map. `booted` is checked BEFORE the await: change_map can finish without
	# suspending, ready_for_players is then already emitted, and awaiting it hangs on a black screen.
	if not playlot.booted:
		await playlot.ready_for_players

	if playlot.maps.current == null:
		var loaded: GSResult = await playlot.change_map(FALLBACK_MAP)

		if not loaded.ok:
			GSLog.error(CHANNEL, "could not load the first map", {
				"why": loaded.error.message
			})
			return

	_wire_gate_to_maps()

	if link != null:
		# The server creates the player and JOIN is what tells this client about it, so
		# there is nobody to adopt yet. Everything below that needs one checks.
		var netcode := _build_netcode()

		if not netcode.ok:
			GSLog.error(CHANNEL, "the netcode would not start", {
				"why": netcode.error.message
			})
			return

		# The view is NOT built here on a networked client: the camera is parented to the player, which does not
		# exist until JOIN lands (HELLO names you, JOIN creates you), so add_child would run on null.
		# In a WASM build that is a hard `RuntimeError: null function`. [method _adopt] builds it on JOIN.
	else:

		player = playlot.add_player(player_id, display_name)
		player.samples_input = true
		gate.freeze(player)

		# The sampler is built in the player's _ready, which has already run — so it is
		# built here instead. Setting the flag alone would leave a player who is
		# supposed to be driving and never samples anything, which reads as the input
		# being broken.
		player.sampler = PlaylotTouch.make_sampler(player.controller.tunables, _touch_ignores)

		_build_view()
		_build_view_switch()

	hud = PlaylotHud.new()
	hud.name = "Hud"
	hud.key_fn = key_for
	add_child(hud)
	hud.flash_source = presentation.fx if presentation != null else null
	_build_touch()
	_follow_hud()
	if link == null:
		hud.bind(playlot, player_id)
	# The vote's clock, handed over HERE rather than where the bridge is built: the netcode
	# comes up before the HUD exists, so the hand-over there found no HUD and every
	# connected client kept counting its own map session's clock through every extend.
	if bridge != null:
		hud.clock_view = bridge.clock_view
	else:
		# Offline the client IS the server: its own world confirms its hits. Connected, the
		# server's HIT event does (`_build_netcode`), and this world decides nothing.
		playlot.hit_landed.connect(_on_offline_hit)
	_sync_hud()

	# After the HUD, because for a CanvasItem tree order is draw order and a menu
	# that renders under the speedometer is one whose bottom row cannot be clicked.
	_build_client_services()
	_build_screens()
	_wire_presentation()
	# Last: a drop on the executable is handled now, and its notice needs the HUD and a loaded map.
	map_drop = PlaylotMapDrop.attach(self, Playlot.USER_MAPS_DIR, _map_id_taken, _on_maps_dropped, _map_converted_from)

	set_process(true)


## Map directories of the content packs the server's game names (playlot-maps), mounted by now.
func _add_dependency_maps() -> void:
	if link == null:
		return
	for key: Variant in link.get("content_extra") if link.get("content_extra") != null else []:
		var parts := GSGameDescriptor.split_key(str(key))
		var _added := playlot.add_map_directory(
			GSCloudClient.mount_prefix_for(StringName(parts[0]), parts[1]).path_join("maps"))


## Why a dropped map cannot use [param id], or empty: a built-in or linked map keeps its id (`add_map_docs` keeps the first).
func _map_id_taken(id: StringName) -> String:
	var have: GSMapDef = playlot.maps.catalogue.get_map(id) if playlot.maps != null else null
	if have == null or str(have.meta.get("doc", "")).begins_with(Playlot.USER_MAPS_DIR):
		return ""
	return "%s is already one of this game's maps; give the dropped one another id" % id


## `{id, title}` of the map converted from the Garry's Mod map [param source] (gm_fork: pgc_fork), or empty.
func _map_converted_from(source: String) -> Dictionary:
	var map: GSMapDef = PlaylotMapSources.find(playlot.maps.catalogue, source) if playlot.maps != null else null
	return {} if map == null else {"id": map.id, "title": map.name_or_id()}


## After a drop: solo, the new maps join the catalogue at once; connected, they wait for a solo game. A dropped Garry's Mod
## map PLAYLOT has a conversion of plays that map at once, solo. Every line is shown.
func _on_maps_dropped(result: Dictionary) -> void:
	var converted: Array = (result.get("added", []) as Array).filter(func(e: Dictionary) -> bool: return e.has("source_map"))
	var shown := result.duplicate()
	shown["added"] = (result.get("added", []) as Array).filter(func(e: Dictionary) -> bool: return not e.has("source_map"))
	var lines: PackedStringArray = load(PlaylotMapDrop.INTAKE_SCRIPT).lines_for(shown)
	for e: Dictionary in converted:
		lines.append("%s is PLAYLOT's %s: pg_map %s" % [e["source_map"], e["title"], e["id"]])
	if not converted.is_empty() and link == null:
		playlot.change_map(StringName(str(converted[0]["id"])))
	var added: Array = shown["added"]
	if not added.is_empty():
		if link == null:
			var _n := playlot.add_map_directory(Playlot.USER_MAPS_DIR)
			# Dropped on the executable: the person asked to play it, so the game goes there.
			if str(result.get("source", "")) == "command line":
				playlot.change_map(StringName(str(added[0]["id"])))
			lines.append("Play it: pg_map %s" % " | pg_map ".join(PackedStringArray(added.map(func(e: Dictionary) -> String: return str(e["id"])))))
		else:
			lines.append("Saved to %s: dropped maps play in a solo game." % ProjectSettings.globalize_path(Playlot.USER_MAPS_DIR))
	if hud != null and not lines.is_empty():
		hud.notice("\n".join(lines))


## Brings up the netcode and points it at the server's link, as the proven sibling client does.
func _build_netcode() -> GSResult:
	net = GSNetManager.new()
	net.name = "Net"
	net.is_server = false
	net.local_peer_id = multiplayer.get_unique_id() if multiplayer != null else 2
	net.auto_tick = false
	net.config_file = ""

	var net_config := GSNetConfig.new()
	net_config.tick_rate = playlot.tick_rate
	net_config.snapshot_rate = Playlot.snapshot_rate_for(playlot.tick_rate)
	net_config.enable_prediction = true
	net_config.enable_lag_compensation = false
	net_config.max_entities_per_snapshot = 0
	net_config.world_extent = 512.0
	# Both default off, else every snapshot replays the whole input lead. By name: a pack runs on its shell's gs-net.
	if &"reconcile_once_per_frame" in net_config:
		net_config.set(&"reconcile_once_per_frame", true)
	if &"skip_matching_replays" in net_config:
		net_config.set(&"skip_matching_replays", true)
	net.config = net_config
	add_child(net)

	var ready_result := net.setup()

	if not ready_result.ok:
		return ready_result

	bridge = PlaylotNetBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)

	var attached := bridge.attach(playlot, net, link)

	if not attached.ok:
		return attached

	# A restarted server counts revisions from 0 again, so forget the old ones first.
	var link_up := GSNetProfileLink.attach(net, playlot.profiles.runtime)
	if link_up != null:
		playlot.profiles.runtime.begin_sync()
		link_up.reply.connect(_on_profile_reply)
		_profile_admin = false
		_sync_profiles_entry()
		if presentation != null:
			presentation.profile_link = link_up
			presentation.bind_profile_replies()

	# Before the seal and in the server's order (after the bridge), or the actions stay local.
	GSLog.result("playlot.client", "avatar action message", GSGameAvatarActionMessage.register(net))
	workbench_remote = GSGameWorkbenchRemoteClient.attach(net)
	net.messages.seal()

	bridge.hello_received.connect(_on_hello)
	bridge.roster_changed.connect(_on_roster_changed)
	bridge.weapon_changed.connect(_on_weapon_changed)
	# gs-server's `chat_received` is NOT connected: [GSChatRouter] routes every line, and both would draw it twice.
	bridge.chat_received.connect(_on_chat_wire)
	bridge.builds_received.connect(func(list: Array) -> void:
		if menu != null:
			menu.set_builds(list)
	)
	bridge.selection_received.connect(func(state: Dictionary) -> void:
		_adopt_selection(bridge.mirror_of(int(state["net_id"])), str(state["name"]),
			state["settings"], str(state["refused"]))
	)
	bridge.combat_received.connect(_on_combat)
	_follow_server_rules()
	# The server's pg_ambient* set drives the quiet layer; the player's sliders multiply on top.
	if presentation != null and presentation.ambient != null:
		presentation.ambient.follow_settings(presentation.settings, playlot.ambient_rules)
	_build_ragdolls()
	bridge.body_fell.connect(func(figure: Node3D, death: GSPlayerDeath) -> void:
		if ragdolls != null and figure.is_inside_tree():
			_land_on_the_world()
			var _fell := ragdolls.spawn(figure, death)
	)
	_connect_bridge_notices()

	# Stock tunables until there is a player to ask; _adopt swaps them in when JOIN arrives.
	_sampler = PlaylotTouch.make_sampler(GSFpsTunables.new(), _touch_ignores)

	# Nothing may be sent before the peer says it can receive: gs-server's signon ends before
	# this scene exists, so earlier sends hit a missing node and the client never joins.
	if link.has_method("is_playing") and bool(link.call("is_playing")):
		bridge.ask_ready()
		workbench_remote.ask()
	elif link.has_signal("spawned"):
		link.connect("spawned", bridge.ask_ready, CONNECT_ONE_SHOT)
		link.connect("spawned", workbench_remote.ask, CONNECT_ONE_SHOT)

	# Nothing in gs-net writes an RTT sample; without one the clock believes the link is instant.
	if link.has_method("ping_ms"):
		bridge.rtt_source = func() -> float:
			return float(maxi(0, int(link.call("ping_ms"))))

	return net.start()


## The server's rule sets this end follows: bodies, drops, props, aim down sights, the camera, collision and ambience.
func _follow_server_rules() -> void:
	# The server's sv_ragdoll* set: this end draws the bodies.
	if link != null:
		var _bodies := playlot.ragdoll_rules.follow_cvars(link)
		var _drops = playlot.weapon_layer.rules.follow_cvars(link)
		var _toy_rules := playlot.toy_rules.follow_cvars(link)
		var _ads := playlot.ads_rules.follow_cvars(link)
		# The server's mp_forceview and mp_solidplayers: this end places its own camera and
		# predicts its own player.
		var _view := playlot.view_rules.follow_cvars(link)
		var _mobile := playlot.mobile_rules.follow_cvars(link)
		var _solid := playlot.body_rules.follow_cvars(link)
		var _ambient := playlot.ambient_rules.follow_cvars(link)
		_follow_arena(link)


## The bridge's hits, matches, progress, notices and the vote cue, to the HUD and the presentation.
func _connect_bridge_notices() -> void:
	bridge.hit_received.connect(_on_hit)
	bridge.match_received.connect(_on_match)
	bridge.progress_received.connect(_on_progress)
	bridge.notice_received.connect(func(_pid: int, text: String) -> void:
		if hud != null:
			hud.notice(text)
	)
	# A move in the bag the server refused has already sprung back by the time this fires;
	# the line is what says it was the server and not the grid.
	bridge.inventory_refused.connect(func(reason: String) -> void:
		if hud != null:
			hud.notice("Your bag: %s" % reason)
	)
	# The map's time left is handed to the HUD where the HUD is built, below.
	# The map vote's cue and countdown. The ballot itself arrives as chat; this is what
	# chat cannot carry.
	bridge.vote_cue_received.connect(func(info: Dictionary) -> void:
		var seconds_left := int(info.get("seconds_left", 0))
		if seconds_left > 0 and hud != null:
			hud.notice("%s in %d…" % [
				"Runoff" if bool(info.get("runoff", false)) else "Map vote", seconds_left
			])
		if presentation != null:
			presentation.on_vote_cue(StringName(str(info.get("cue", ""))))
	)



func _unhandled_input(event: InputEvent) -> void:
	if _covered():
		return

	# The console first: this client reads bare letters (Q, 1, 2, F, E), so typing `seed` at the console would act.
	if presentation != null and presentation.swallows_input():
		return

	# Voice first, before the player check: somebody mid-signon or spectating can still talk, and a swallowed
	# release leaves the microphone open. `handle_event` sees both edges.
	if voice != null and voice.handle_event(event):
		get_viewport().set_input_as_handled()
		return

	# A click on the world with the pointer released takes it back and does nothing else: the
	# platform captures it first, and `_was_driving` (last frame's answer) says this click took the
	# pointer. Before the `player == null` guard, so a click while the world loads is not swallowed.
	if (
		event is InputEventMouseButton and (event as InputEventMouseButton).pressed
		and not _menu_is_open() and not _was_driving
	):
		return

	if player == null:
		return

	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_on_screen_touch(event)
		return

	# The mouse Godot emulates from a touch would click and turn the view a second time.
	if event is InputEventMouse and _touch != null and _touch.takes(event):
		return

	if event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
		return

	# Everything below moves the world; a click on a menu's own background would arrive here.
	if _menu_is_open() and not _is_menu_key(event):
		return

	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
		return

	if event is InputEventJoypadButton:
		_wheel_cycle(event)
		return

	if not (event is InputEventKey):
		return

	var key := event as InputEventKey

	# Every key below is a row of [PlaylotBindings], matched by its action so a key moved
	# on the Controls page moves what it does here. Escape alone is a keycode: no row has it.
	if key.is_action(PlaylotBindings.ROTATE):
		# Held, not toggled, and read on both edges: a rotate that stayed on after
		# the key came up would turn the prop every time the player looked around.
		_rotating = key.pressed
		return

	if key.is_action(PlaylotBindings.SPAWN_MENU):
		_on_menu_key(key)
		return

	if key.is_action(PlaylotBindings.PROFILES):
		if key.pressed and not key.is_echo():
			_toggle_profiles()
		return

	if key.is_action(PlaylotBindings.MAP_EDIT):
		if key.pressed and not key.is_echo():
			_toggle_map_edit()
		return

	if key.is_action(PlaylotBindings.MAP_EDIT_PICK):
		if key.pressed and not key.is_echo():
			_pick_map_edit()
		return

	# The Tab board, held: shown while the key is down, released when it comes up.
	if key.is_action(PlaylotBindings.SCOREBOARD) and not key.is_echo():
		if game_menu != null:
			if key.pressed:
				game_menu.scoreboard.open()
			else:
				game_menu.scoreboard.close()
		return

	if key.is_action(PlaylotBindings.DROP_WEAPON) and key.pressed and not key.is_echo() and _zee_rig() != null:
		bridge.ask_drop_weapon()
		return
	# R reloads a gun (the tool gun's R is its third button), else unfreezes; read on both edges.
	if key.is_action(PlaylotBindings.RELOAD) and (_zee_rig() != null or tool == TOOLGUN):
		_set_reload(key.pressed)
		return

	# Aim and quick melee moved onto keys, held like the trigger, with a zee gun in hand.
	if _zee_rig() != null and key.is_action(PlaylotBindings.AIM):
		_aiming = key.pressed
		return
	if _zee_rig() != null and key.is_action(PlaylotBindings.BASH):
		if key.pressed:
			_secondary_down()
		else:
			_secondary_up()
		return

	if not key.is_pressed() or key.is_echo():
		return

	_on_press_key(key)

	match key.physical_keycode:
		KEY_ESCAPE:
			# Only when no screen is up (the stack pops menus itself). Release, THEN open, never capture:
			# a browser refuses pointer lock just after Escape.
			if not _menu_is_open() and game_menu != null:
				game_menu.open()


## The keys read on press only (spawn, undo, vehicle, tools, view): the tail of [method _unhandled_input].
func _on_press_key(key: InputEventKey) -> void:
	if key.is_action(PlaylotBindings.SPAWN):
		_spawn()
	elif key.is_action(PlaylotBindings.UNDO):
		if bridge != null:
			bridge.ask_undo()
		else:
			playlot.undo(player_id)
	elif key.is_action(PlaylotBindings.VEHICLE):
		_use_vehicle()
	elif key.is_action(PlaylotBindings.FLASHLIGHT):
		_toggle_flashlight()
	elif key.is_action(PlaylotBindings.RELOAD):
		_unfreeze_all()
	elif key.is_action(PlaylotBindings.PHYS_GUN):
		_set_tool(TOOL_PHYS)
	elif key.is_action(PlaylotBindings.GRAV_GUN):
		_set_tool(TOOL_GRAV)
	elif key.is_action(PlaylotBindings.WEAPONS):
		_cycle_weapon()
	elif _wheel_cycle(key):
		pass
	elif key.is_action(GSMenuBindings.LOADOUT_ACTION) and loadout_menu != null and not arena_on:
		# B opens the loadout only in the arena (the menu is disabled outside it, so the key
		# reaches here): said, rather than a key that does nothing.
		if hud != null:
			hud.notice(LOADOUT_ARENA_ONLY)
	elif key.is_action(PlaylotBindings.VIEW):
		# The usual third-person toggle. It hands the player to a different CONTROLLER, so the
		# handover carries position, velocity and look: pressing it mid-jump must not stop you dead.
		_toggle_view()


## Offline, this world's own hit on another player: counted for the Tab board, then shown as a confirmed hit.
func _on_offline_hit(id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
	if id != player_id:
		return
	if killed:
		note_offline(&"kills")
	_on_hit(victim, amount, point, killed, headshot)
