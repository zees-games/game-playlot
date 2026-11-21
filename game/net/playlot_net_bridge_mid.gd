extends "playlot_net_bridge_base.gd"


## Builds the inventory's half of the wire, when the game has an inventory.
## Through [method _tell], never [method _broadcast]: [PlaylotInventoryNet] can reach ONE peer only.
func _attach_inventory() -> void:
	if game.inventory == null:
		return

	inventory_net = PlaylotInventoryNet.new()
	inventory_net.name = "Inventory"
	add_child(inventory_net)

	if net.is_server:
		inventory_net.bind_server(game.inventory)
		inventory_net.tell_fn = func(peer_id: int, body: PackedByteArray) -> void:
			_tell(peer_id, PlaylotEvents.Kind.INVENTORY, body)
		inventory_net.notice_fn = func(peer_id: int, text: String) -> void:
			_tell(peer_id, PlaylotEvents.Kind.NOTICE,
				PlaylotEvents.write_notice(player_for_peer(peer_id), text))
		inventory_net.charge_fn = _charge
		inventory_net.bag_key_fn = inventory_key_fn
	else:
		inventory_net.bind_client(game.inventory)
		inventory_net.ask_fn = func(body: PackedByteArray) -> void:
			_ask(PlaylotEvents.Ask.INVENTORY, body)
		inventory_net.refused.connect(func(reason: String) -> void:
			inventory_refused.emit(reason))


## Re-dresses a player whose avatar changed after they joined, and tells everybody.
func refresh_skins(session_id: int) -> void:
	if net == null or not net.is_server or not skin_fn.is_valid():
		return
	var player: PlaylotPlayer = game.players.get(_player_key(session_id))
	var dressed: Variant = skin_fn.call(session_id)
	if player == null or not (dressed is PackedInt32Array) or (dressed as PackedInt32Array) == player.skins:
		return
	player.set_skins(dressed)
	_broadcast(PlaylotEvents.Kind.JOIN, _join_body(session_id))


func add_player(
	peer_id: int, session_id: int, display_name: String, record_key: StringName = &""
) -> GSResult:
	if net == null or not net.is_server:
		return GSResult.fail(GSError.CODE_FORBIDDEN, "Only the server adds players.")

	var id := _player_key(session_id)

	if peer_id > 0:
		_player_of_peer[peer_id] = session_id
		_peer_of_player[session_id] = peer_id

	# add_player emits player_added, which _on_player_added answers by building the
	# entity and announcing the JOIN. The peer mapping is set FIRST so that handler
	# can find the peer this player belongs to.
	var player := game.add_player(id, display_name, record_key)

	if player == null:
		_player_of_peer.erase(peer_id)
		_peer_of_player.erase(session_id)
		return GSResult.fail(GSError.CODE_STATE, "The game refused the player.")

	if _ready_unseated.has(peer_id):
		_ready_unseated.erase(peer_id)
		_admit(peer_id)

	return GSResult.success(player)


## A player the game made itself (a bot, a test) gets an entity like one a peer asked for. Its peer
## id is zero, which is not the broadcast address by accident: [method _tell] refuses zero, because
## `net.send(msg, 0)` IS a broadcast and once sent every player's private message to everybody.
func _on_player_added(id: StringName) -> void:
	if net == null or not net.is_server:
		return

	var session_id := session_of(id)

	if _behaviours.has(session_id):
		return

	var player: PlaylotPlayer = game.players.get(id)
	if player == null:
		return

	# Dressed before the JOIN that describes them goes out, so nobody sees the stock look
	# first and the member's own a moment later.
	if skin_fn.is_valid():
		var dressed: Variant = skin_fn.call(session_id)
		if dressed is PackedInt32Array:
			player.set_skins(dressed)

	var identity := _build_entity(player, peer_for_player(session_id))
	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		GSLog.warn(CHANNEL, "could not replicate a player", {"error": str(registered.error)})
		return

	_broadcast(PlaylotEvents.Kind.JOIN, _join_body(session_id))
	roster_changed.emit(session_id)


func _on_player_removed(id: StringName) -> void:
	var session_id := session_of(id)
	if _behaviours.has(session_id):
		# The game removed it itself; the entity and the LEAVE are still ours.
		_release_entity(session_id)
		_broadcast(PlaylotEvents.Kind.LEAVE, PlaylotEvents.write_player(session_id))
		roster_changed.emit(session_id)


## Every prop the spawner creates becomes a replicated entity, announced reliably AND replicated by
## snapshot: the snapshot moves it, the event says what it is. Props are named by PATH in the
## catalogue so a gs-cloud pack can deliver them (a mounted pack's `class_name`s are not registered).
func _on_prop_spawned(prop: GSPropInstance) -> void:
	if net == null or not net.is_server or prop == null or prop.node == null:
		return

	var body := prop.node as Node3D
	if body == null:
		return

		# A vehicle replicates through GSVehicleNetSync (wheel angle and full seats cannot be derived
		# from a position), so the catalogue decides the behaviour once, here. The table below is the
		# same on both ends and `_apply_prop` reads it the same way.
	var behaviour := _behaviour_for(prop.def)
	behaviour.name = "Net"
	behaviour.prop = body
	body.add_child(behaviour)

	var as_vehicle := behaviour as PlaylotVehicleNet

	if as_vehicle != null and game.vehicles != null:
		as_vehicle.vehicle = game.vehicles.vehicle_for_node(body)

	var identity := GSNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	# SERVER, not SHARED: nothing about a rigid body is predicted, so there is no owner
	# to share with. See PlaylotPropNet for why that is a decision and not a gap.
	identity.authority = GSNetIdentity.Authority.SERVER
	body.add_child(identity)

	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		GSLog.warn(CHANNEL, "could not replicate a prop", {"error": str(registered.error)})
		return

	_prop_nets[prop.instance_id] = behaviour
	behaviour.net_id_of = net_id_of_node
	behaviour.pull()

	_broadcast(PlaylotEvents.Kind.PROP, PlaylotEvents.write_prop(
		identity.net_id,
		prop.def.id,
		session_of(prop.owner_id),
		PlaylotSpawnables.kind_of(prop.def) == PlaylotSpawnables.Kind.ENTITY,
		body.global_position
	))


## Replicates everything [param spawner] spawns, as props are: a PROP event says what it is and a
## [PlaylotPropNet] moves it. Called by the module once the waves exist. Through the prop path,
## not a second one; the definition is found in [member npc_catalogue] when the prop catalogue lacks it.
func watch_npc_spawner(spawner: GSNpcSpawner, catalogue: GSNpcCatalogue) -> void:
	npc_catalogue = catalogue

	if spawner == null or net == null or not net.is_server:
		return

	spawner.spawned.connect(_on_npc_spawned)
	spawner.removed.connect(_on_npc_removed)
	# Before `removed`, while the body is there: how it falls, sent with the PROP_GONE.
	spawner.died.connect(func(npc: GSNpcInstance, by: StringName) -> void:
		var _fall := game.decide_npc_death(npc.node as Node3D, by, npc.def.max_health if npc.def != null else 0.0))


func _on_npc_spawned(npc: GSNpcInstance) -> void:
	var body := npc.node as Node3D

	if body == null or net == null or not net.is_server:
		return

	var behaviour := PlaylotPropNet.new()
	behaviour.name = "Net"
	behaviour.prop = body
	body.add_child(behaviour)

	var identity := GSNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	identity.authority = GSNetIdentity.Authority.SERVER
	body.add_child(identity)

	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		GSLog.warn(CHANNEL, "could not replicate an NPC", {"error": str(registered.error)})
		return

	_prop_nets[npc.instance_id] = behaviour
	_npc_kinds[npc.instance_id] = npc.def.id
	behaviour.net_id_of = net_id_of_node
	behaviour.pull()

	_broadcast(PlaylotEvents.Kind.PROP, PlaylotEvents.write_prop(
		identity.net_id, npc.def.id, 0, true, body.global_position
	))


func _on_npc_removed(npc: GSNpcInstance, reason: StringName) -> void:
	var behaviour: PlaylotPropNet = _prop_nets.get(npc.instance_id)
	_prop_nets.erase(npc.instance_id)
	_npc_kinds.erase(npc.instance_id)

	if behaviour == null or behaviour.identity == null or net == null:
		return

	var net_id: int = behaviour.identity.net_id
	net.registry.unregister(net_id)
	_broadcast(PlaylotEvents.Kind.PROP_GONE, PlaylotEvents.write_prop_gone(
		net_id, reason, _death_of(npc.node, reason)))


func _on_prop_removed(prop: GSPropInstance, reason: StringName) -> void:
	if net == null or not net.is_server or prop == null:
		return

	var behaviour: PlaylotPropNet = _prop_nets.get(prop.instance_id)
	_prop_nets.erase(prop.instance_id)

	if behaviour == null or behaviour.identity == null:
		return

	var net_id: int = behaviour.identity.net_id
	net.registry.unregister(net_id)

	_broadcast(PlaylotEvents.Kind.PROP_GONE, PlaylotEvents.write_prop_gone(
		net_id, reason, _death_of(prop.node, reason)))


## A refusal goes to the one player who asked, not to everybody. A budget message is
## the most common thing this server says and it is nobody else's business.
func _on_prop_refused(player_id: StringName, prop_id: StringName, reason: String) -> void:
	var session_id := session_of(player_id)
	_tell(peer_for_player(session_id), PlaylotEvents.Kind.NOTICE,
		PlaylotEvents.write_notice(session_id, "Cannot spawn %s: %s" % [prop_id, reason]))


## Somebody's physics gun took hold of a prop or let go of one: everybody is told, so every
## client can draw the beam.
func _on_held_changed(id: StringName, prop: GSPropInstance, held: bool) -> void:
	if net == null or not net.is_server:
		return
	var session := session_of(id)
	var net_id := net_id_of_node(prop.node) if held and prop != null and prop.node != null else 0
	if net_id > 0:
		held_props[session] = net_id
	else:
		held_props.erase(session)
	_broadcast(PlaylotEvents.Kind.HELD, PlaylotEvents.write_held(session, net_id, prop.frozen if prop != null else false))


## A pane broke on the server: everybody removes their own copy of it. The shards are props
## and travel as props; this is only the box, which every client built itself.
func _on_pane_broken(index: int, _at: Vector3, _material: StringName) -> void:
	if net == null or not net.is_server:
		return
	_broadcast(PlaylotEvents.Kind.PANE, PlaylotEvents.write_pane(index))


## Tells everybody that somebody got in or out, not just the rider: the other clients must stop
## drawing a walking player and draw one sitting in a car, and a "get in" prompt over a full seat lies.
func announce_seat(
	vehicle: GSVehicleInstance, rider_id: StringName, seat: GSVehicleSeat, seated: bool
) -> void:
	if net == null or not net.is_server or vehicle == null:
		return

	var index := 0

	for i in vehicle.def.seats.size():
		if vehicle.def.seats[i].id == seat.id:
			index = i
			break

	_broadcast(PlaylotEvents.Kind.SEAT, PlaylotEvents.write_seat(
		session_of(rider_id), net_id_of_node(vehicle.node), index, seated
	))


func _admit(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if not _player_of_peer.has(peer_id):
		_ready_unseated[peer_id] = true
		return

	var fresh := not _ready_peers.has(peer_id)
	_ready_peers[peer_id] = true
	if not net.peers().has(peer_id):
		net.add_peer(peer_id)

	var session_id := int(_player_of_peer[peer_id])

	_tell(peer_id, PlaylotEvents.Kind.HELLO, PlaylotEvents.write_hello(
		session_id, game.tick_rate, net.clock.tick,
		game.maps.current.id if game.maps.current != null else &"",
		_movement_of_game()
	))

	for other in _behaviours.keys():
		_tell(peer_id, PlaylotEvents.Kind.JOIN, _join_body(int(other)))

	# Who is being carried. A joiner who missed the SEAT would predict a held player.
	for id in game.players:
		if game.pickup.is_held(id):
			_tell(peer_id, PlaylotEvents.Kind.SEAT, PlaylotEvents.write_seat(session_of(id), 0, 0, true))

	# What everybody is already holding. A WEAPON event is sent once, when it changes, so a
	# joiner would otherwise see nobody's gun until its holder switched.
	for other in _tool_of.keys():
		_tell(peer_id, PlaylotEvents.Kind.WEAPON, PlaylotEvents.write_weapon(
			int(other), _tool_of[other]
		))
	# And every pane broken on this map, so the joiner's copy of the map has the same holes.
	for index: int in game.broken_panes:
		_tell(peer_id, PlaylotEvents.Kind.PANE, PlaylotEvents.write_pane(index))
	# And what everybody is holding, for the same reason: HELD is sent when it changes.
	for holder in held_props.keys():
		_tell(peer_id, PlaylotEvents.Kind.HELD, PlaylotEvents.write_held(int(holder), int(held_props[holder]), false))

	weapon_net.send_snapshot(peer_id, game.weapon_layer)
	# The map's toys, by net id in toy order: the joiner's own copies are paired with them.
	if not _toys_body.is_empty():
		_tell(peer_id, PlaylotEvents.Kind.TOYS, _toys_body)

	# The time left now: on a quiet map the clock's next change never comes.
	if clock_fn.is_valid():
		_tell(peer_id, PlaylotEvents.Kind.CLOCK, PlaylotEvents.write_clock(clock_fn.call()))

	_tell_world_props(peer_id)

	# Grenades already in the air: a launch is sent once, so a joiner never saw them.
	if game.projectiles != null:
		for launch: Dictionary in game.projectiles.join_launches():
			_tell(peer_id, PlaylotEvents.Kind.PROJECTILE, PlaylotEvents.write_launch(
				int(launch["serial"]), launch["spawn"], launch["owner_id"], bool(launch["sticks"])
			))

	# Their own bag, whole, to them alone: a reconnecting player already has one.
	if inventory_net != null:
		inventory_net.admit(peer_id, session_id)

	# Once, so a READY said twice does not replay the backlog and the join line.
	if fresh:
		peer_admitted.emit(peer_id)


## Every prop and wave NPC already in the world, so a late joiner does not walk into unseen things.
func _tell_world_props(peer_id: int) -> void:
	for instance_id in _prop_nets.keys():
		var prop := game.props.get_prop(int(instance_id))
		var behaviour: PlaylotPropNet = _prop_nets[instance_id]
		if behaviour == null or behaviour.identity == null:
			continue
		# A wave NPC is in the table, not in the prop spawner.
		if prop == null and _npc_kinds.has(instance_id):
			_tell(peer_id, PlaylotEvents.Kind.PROP, PlaylotEvents.write_prop(
				behaviour.identity.net_id, _npc_kinds[instance_id], 0, true, behaviour.net_position
			))
			continue
		if prop == null:
			continue
		_tell(peer_id, PlaylotEvents.Kind.PROP, PlaylotEvents.write_prop(
			behaviour.identity.net_id,
			prop.def.id,
			session_of(prop.owner_id),
			PlaylotSpawnables.kind_of(prop.def) == PlaylotSpawnables.Kind.ENTITY,
			behaviour.net_position
		))


func _on_map_ready(map: GSMapDef) -> void:
	_broadcast(PlaylotEvents.Kind.MAP, PlaylotEvents.write_map(map.id))
	_register_toys()
	# Re-announced after a map change: a client rebuilt its world and needs to be told
	# who is in it again. gs-map's own sync replaces the world and nothing else.
	for session_id in _behaviours.keys():
		_broadcast(PlaylotEvents.Kind.JOIN, _join_body(int(session_id)))


## Server: an entity for each of the map's toys, and TOYS naming them.
func _register_toys() -> void:
	if net == null or not net.is_server or game == null:
		return
	_release_toys()
	var ids := PackedInt64Array()
	if game.toys != null:
		for toy in game.toys.toys:
			var behaviour := _toy_entity(toy, toy, 0)
			if behaviour == null:
				break
			ids.append(behaviour.identity.net_id)
	_toys_body = PlaylotEvents.write_toys(game.maps.current.id if game.maps.current != null else &"", ids)
	_broadcast(PlaylotEvents.Kind.TOYS, _toys_body)


## Tells one player what their tool gun has selected. The prop is named by the net id it
## replicates under, so the client can find its own mirror of it.
func _tell_selection(session_id: int, report: Dictionary) -> void:
	var node: Variant = report.get("node")
	var net_id := net_id_of_node(node) if node is Node else 0
	_tell(peer_for_player(session_id), PlaylotEvents.Kind.SELECTION, PlaylotEvents.write_selection(
		net_id, str(report.get("name", "")), report.get("settings", {}), str(report.get("refused", ""))
	))


## Puts one of this player's saved builds down in front of them. Client side.
func ask_load_build(build_name: String) -> void:
	_ask(PlaylotEvents.Ask.ARM_PROP, PlaylotEvents.write_arm(
		PlaylotEvents.ARM_LOAD_BUILD, StringName(build_name)
	))


## Asks the server to start an addon's menu entry, [param key] being `addon/item`, with the
## point the player is looking at. Client side.
func ask_addon_item(key: String, at: Vector3) -> void:
	_ask(PlaylotEvents.Ask.ARM_PROP, PlaylotEvents.write_arm(
		PlaylotEvents.ARM_ADDON_ITEM, StringName(key), JSON.stringify([at.x, at.y, at.z])
	))


## A player's saved builds, to that player. Server side.
func send_builds(peer_id: int, list: Array) -> void:
	_tell(peer_id, PlaylotEvents.Kind.BUILDS, PlaylotEvents.write_builds(list))


## A line on one player's HUD. Server side.
func tell_notice(peer_id: int, text: String) -> void:
	_tell(peer_id, PlaylotEvents.Kind.NOTICE,
		PlaylotEvents.write_notice(player_for_peer(peer_id), text))


func _drop_toy(session_id: int) -> void:
	var toy: PlaylotWeapon = _toy_of.get(session_id)
	if toy != null:
		toy.holster()
	_toy_of.erase(session_id)


func _select_tool(session_id: int, id: StringName, tool_id: StringName) -> void:
	if not game.players.has(id):
		return
	if tool_id != &"phys" and tool_id != &"grav":
		return

	# Whatever the old tool was holding is let go. A player who swaps to the gravity gun
	# with a crate on the end of the physics gun would otherwise leave it hanging in the
	# air, owned by a tool they are no longer using and released by nothing.
	var player: PlaylotPlayer = game.players.get(id)
	if player != null:
		game.phys_gun_release(player)
		player.grav_gun.drop()
		PlaylotZee.disarm(player)
	_drop_toy(session_id)

	_tool_of[session_id] = tool_id
	_broadcast(PlaylotEvents.Kind.WEAPON, PlaylotEvents.write_weapon(session_id, tool_id))


func _apply_weapon(reader: GSNetReader) -> void:
	var held := PlaylotEvents.read_weapon(reader)
	if not bool(held["ok"]):
		return
	PlaylotZee.show_held(
		game.players.get(_player_key(int(held["player_id"]))),
		game.weapon_def(held["weapon_id"] as StringName)
	)
	weapon_changed.emit(int(held["player_id"]), held["weapon_id"] as StringName)


func _apply_held(reader: GSNetReader) -> void:
	var holding := PlaylotEvents.read_held(reader)
	if not bool(holding["ok"]):
		return
	if int(holding["net_id"]) > 0:
		held_props[int(holding["player_id"])] = int(holding["net_id"])
	else:
		held_props.erase(int(holding["player_id"]))


## Every launch to every client, so each flies a copy and draws the arc. Sent once, not replicated as an
## entity: a grenade lives seconds and its path is a pure function of where it left and how fast.
func _on_projectile_launched(flying: RefCounted) -> void:
	_broadcast(PlaylotEvents.Kind.PROJECTILE, PlaylotEvents.write_launch(
		int(flying.get("serial")), flying.get("spawn"), flying.get("owner_id"), bool(flying.get("sticks"))
	))


## The local thrower's own launches, flown now; [method _apply_projectile] adopts them when
## the server's launch arrives. Returns how many.
func predict_launches(outcome: GSWeaponOutcome, owner_body: Node = null) -> int:
	if game.projectiles == null or game.projectiles.authority or outcome == null:
		return 0

	var rid := (owner_body as CollisionObject3D).get_rid() if owner_body is CollisionObject3D else RID()

	for spawn: GSWeaponSpawn in outcome.spawns:
		var _f: Variant = game.projectiles.predict(spawn, _player_key(local_player_id), rid)

	return outcome.spawns.size()


## Where it went off, which the client's copy does not decide for itself — see
## PlaylotProjectiles.
func _on_projectile_detonated(serial: int, at: Vector3, radius: float) -> void:
	var told: Dictionary = game.projectiles.take_told(serial)
	_broadcast(PlaylotEvents.Kind.PROJECTILE, PlaylotEvents.write_detonate(
		serial, at, radius, int(told.get("fx", 0)), float(told.get("seconds", 0.0))
	))


func _apply_projectile(reader: GSNetReader) -> void:
	if game.projectiles == null:
		return

	match reader.read_uint(PlaylotEvents.PROJECTILE_SUB_BITS):
		PlaylotEvents.ProjectileTell.LAUNCH:
			var launch := PlaylotEvents.read_launch(reader)
			if bool(launch["ok"]):
				var _flying: Variant = game.projectiles.launch_told(
					launch["spawn"], launch["owner_id"], int(launch["serial"]),
					launch["owner_id"] == _player_key(local_player_id)
				)
		PlaylotEvents.ProjectileTell.DETONATE:
			var blast := PlaylotEvents.read_detonate(reader)
			if bool(blast["ok"]):
				game.projectiles.detonate_remote(
					int(blast["serial"]), blast["position"], float(blast["radius"]),
					int(blast["fx"]), float(blast["seconds"])
				)
		PlaylotEvents.ProjectileTell.BLIND:
			var blind := PlaylotEvents.read_blind(reader)
			if bool(blind["ok"]):
				game.projectiles.blind_remote(float(blind["seconds"]), float(blind["strength"]))


func _movement_of_game() -> Vector3:
	var c := game.config
	return Vector3(c.move_speed, c.jump_height, c.move_gravity) if c != null else Vector3(7.0, 1.15, 20.0)


func _adopt_movement(movement: Vector3) -> void:
	if movement != Vector3.ZERO:
		game.set_movement(movement.x, movement.y, movement.z)


func _apply_hello(reader: GSNetReader) -> void:
	var hello := PlaylotEvents.read_hello(reader)
	if not bool(hello["ok"]):
		return

	local_player_id = int(hello["player_id"])

	# Before anything else arrives for it: the bag that follows is this identity's.
	if inventory_net != null:
		inventory_net.on_hello(local_player_id)

	# The server's tick rate, before anything is derived from it and before sync_from_server, whose clock
	# converts through tick_rate. A client counting at its export's 60 against a server on 128 has every time wrong.
	_adopt_tick_rate(int(hello["tick_rate"]))
	_adopt_movement(hello["movement"])

	var rtt := float(rtt_source.call()) if rtt_source.is_valid() else 0.0
	net.clock.sync_from_server(int(hello["server_tick"]), maxf(0.0, rtt))

	var map_id: StringName = hello["map_id"]
	if map_id != &"" and (game.maps.current == null or game.maps.current.id != map_id):
		game.change_map(map_id)

	_claim_local_player()

	hello_received.emit(local_player_id)


## Puts the whole client (game, timers, netcode clock and the ENGINE) on the server's tick rate.
## Four places hold it and must move together: `game.tick_rate`; `net.config.tick_rate`;
## `net.clock.tick_rate` (built at `setup()`); `Engine.physics_ticks_per_second`. A server never calls this.
func _adopt_tick_rate(rate: int) -> void:
	if net == null or net.is_server or game == null or rate <= 0 or rate == game.tick_rate:
		return

	var before := game.tick_rate

	if not game.set_tick_rate(rate):
		return

	net.config.tick_rate = game.tick_rate
	net.clock.tick_rate = game.tick_rate
		# gs-net API 7 has GSNetClock.adopt_tick_rate(), which also raises the engine's step cap to a
		# quarter second of ticks (8 steps are 62.5 ms at 128 Hz). A shell built before it gets the same
		# rule here; remove this branch when the oldest shell is API 7.
	if GSAddonApi.build_level("gs_net") >= 7:
		GSNetClock.adopt_tick_rate(game.tick_rate)
	else:
		Engine.max_physics_steps_per_frame = maxi(Engine.max_physics_steps_per_frame, ceili(0.25 * float(game.tick_rate)))
		Engine.physics_ticks_per_second = game.tick_rate

	GSLog.info(CHANNEL, "adopted the server's tick rate", {
		"was": before, "now": game.tick_rate, "engine": Engine.physics_ticks_per_second,
	})


## Who owns a mirrored player on this client: this client for its own player, 0 otherwise. Matched by
## session id, not sent on the wire. Never the local peer for anybody else (it would predict somebody
## whose keys it never had); a local peer of 0 claims nothing (0 is the server's owner id).
func _mirror_owner(session_id: int) -> int:
	if net == null or net.local_peer_id <= 0:
		return 0

	if local_player_id != 0 and session_id == local_player_id:
		return net.local_peer_id

	return 0


## The local player's mirror, claimed if it arrived before HELLO said whose it was. Belt and braces:
## a JOIN reaching this peer before its HELLO would leave the local player unpredicted for the rest
## of the session (see [method _apply_join]). A vehicle is never claimed: a rigid body is not predicted.
func _claim_local_player() -> void:
	var mine: PlaylotPlayerNet = _behaviours.get(local_player_id)

	if mine == null or mine.identity == null or not mine.identity.is_registered():
		return

	var claimed := _mirror_owner(local_player_id)

	if claimed == 0 or mine.identity.owner_peer_id == claimed:
		return

	GSLog.debug(CHANNEL, "claimed the local player after HELLO", {
		"session": local_player_id, "net_id": mine.identity.net_id,
	})
	var _changed := net.registry.change_owner(mine.identity.net_id, claimed)


func _on_ride_entered(
	vehicle: GSVehicleInstance, rider_id: StringName, seat: GSVehicleSeat
) -> void:
	announce_seat(vehicle, rider_id, seat, true)


## Somebody was picked up or let go. A SEAT with no vehicle: the held client stops
## predicting and adopts the server's position, which is all being carried needs — and
## exactly what a client older than picking up does with it.
func _on_pickup_changed(_holder_id: StringName, target_id: StringName, held: bool) -> void:
	if net == null or not net.is_server:
		return
	_broadcast(PlaylotEvents.Kind.SEAT, PlaylotEvents.write_seat(session_of(target_id), 0, 0, held))


func _on_ride_exited(
	vehicle: GSVehicleInstance,
	rider_id: StringName,
	seat: GSVehicleSeat,
	_at: Vector3
) -> void:
	announce_seat(vehicle, rider_id, seat, false)


## A client's copy of "that player is in a car". The client does not run the ride (no vehicle
## spawner, exit sweep or seats), so it only stops predicting a player who is no longer walking: a
## predicted controller simulating a passenger fights the snapshots' position every tick.
func _apply_seat(reader: GSNetReader) -> void:
	var info := PlaylotEvents.read_seat(reader)

	if not bool(info["ok"]):
		return

	var behaviour: PlaylotPlayerNet = _behaviours.get(int(info["player_id"]))

	if behaviour == null or behaviour.player == null:
		return

	# The vehicle too, when this client has it, so the body sits facing the car's way.
	var vehicle_net: PlaylotPropNet = _prop_nets.get(int(info["vehicle_net_id"]))
	var vehicle_node: Node3D = null
	if vehicle_net != null and is_instance_valid(vehicle_net.prop):
		vehicle_node = vehicle_net.prop as Node3D
	if int(info["vehicle_net_id"]) == 0:
		# Vehicle 0 is a player held by a physics gun (PlaylotPickup): not predicted,
		# not seated, and no seat_changed, because nobody got into anything.
		behaviour.player.set_held(bool(info["seated"]))
		return
	behaviour.player.set_riding(bool(info["seated"]), vehicle_node)
	seat_changed.emit(int(info["player_id"]), bool(info["seated"]))


func _apply_prop_gone(reader: GSNetReader) -> void:
	var info := PlaylotEvents.read_prop_gone(reader)
	if not bool(info["ok"]):
		return

	var net_id := int(info["net_id"])

	var behaviour: PlaylotPropNet = _prop_nets.get(net_id)
	_prop_nets.erase(net_id)

	if behaviour == null:
		return

	if net != null:
		net.registry.unregister(net_id)

	if behaviour.prop != null and is_instance_valid(behaviour.prop):
		# A killed NPC goes down the way the server picked, copied from its drawn figure
		# before the mirror goes.
		var figure := behaviour.prop.get_node_or_null(^"Figure") as Node3D
		if info.has("death") and figure != null:
			body_fell.emit(figure, info["death"])
		behaviour.prop.queue_free()

	props_changed.emit()


## To every READY peer, one at a time, and never to peer 0 (`net.send(msg, 0)` is an `rpc()` to every
## socket, and a peer connects before its client builds `Server/Playground`, so an early JOIN hit a
## missing node). [method _admit] tells it everything on READY.
func _broadcast(kind: int, body: PackedByteArray) -> void:
	if net == null or not net.is_server or body.is_empty():
		return
	for peer_id in _ready_peers.keys():
		net.send(PlaylotEvent.new(kind, body), int(peer_id))


## To one peer, and never to peer 0, the broadcast address: a bot given peer id 0 once got every
## private per-player message sent to every client. A player with no peer is simply not told.
func _tell(peer_id: int, kind: int, body: PackedByteArray) -> void:
	if net == null or not net.is_server or peer_id <= 0 or body.is_empty():
		return
	net.send(PlaylotEvent.new(kind, body), peer_id)
