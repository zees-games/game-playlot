extends "res://examples/headless_playlot_spawn_menu.gd"

## A car spawned from the prop catalogue, driven, ridden in and got out of.
##
## A vehicle here is BOTH a vehicle and a [GSPropInstance]: on a prop budget, an undo stack, adopted rather than spawned, with wheels built by the game after the body, which no other suite runs.
var _v_driver: PlaylotPlayer
var _v_at: Vector3
var _v_spawned: GSPropInstance
var _v_vehicle: GSVehicleInstance
var _v_forward: GSFpsCommand
var _v_passenger: PlaylotPlayer

func _test_vehicles() -> void:
	_section("vehicles")

	var changed: GSResult = await playlot.change_map(&"pg_flatgrass")
	_check(changed.ok, "the sandbox loads")

	# The sandbox test above lets its player leave, so this one brings the bot back.
	_v_driver = playlot.add_player(&"bot", "Bot")
	playlot.props.limits.spawn_interval = 0.0

	# The corner of the plate opposite the jump course and the tower: flat and empty for sixty
	# metres, because a car crosses the sandbox in seconds and would measure the scenery.
	_v_at = Vector3(-60.0, 1.2, -60.0)
	_v_driver.teleport(_v_at + Vector3(2.5, 0.0, 0.0), 0.0)

	_v_spawned = playlot.props.spawn(&"buggy", &"bot", _v_at)

	_check(_v_spawned != null, "a buggy spawns out of the PROP catalogue")

	if _v_spawned == null:
		return

	_check(
		PlaylotSpawnables.kind_of(_v_spawned.def) == PlaylotSpawnables.Kind.VEHICLE,
		"and the catalogue says it is a vehicle"
	)

	_v_vehicle = playlot.vehicles.vehicle_for_node(_v_spawned.node)

	_check(_v_vehicle != null, "and it was adopted by the vehicle spawner")

	if _v_vehicle == null:
		return

	_check(_v_vehicle.chassis is GSVehicleWheeled, "with Godot's raycast wheels under it")

	var body := _v_spawned.node as PlaylotVehicle
	_check(body != null and body.wheel_count() == 4, "and four wheels actually built")
	_check(
		body != null and is_equal_approx(body.mass, _v_vehicle.def.tuning().mass),
		"and one mass, read off the tunables by both catalogues",
		"%.1f vs %.1f" % [
			body.mass if body != null else -1.0, _v_vehicle.def.tuning().mass
		]
	)

	# Let it settle onto its suspension before anything is measured. A raycast vehicle
	# spawned in the air is falling, and a "did it drive forward" measured through the
	# drop is measuring the drop.
	for _i in range(40):
		await get_tree().physics_frame

	_check(
		playlot.use_vehicle(&"bot").ok,
		"the bot standing beside it gets in"
	)
	_check(_v_driver.riding, "and stops being a player who walks")
	_check(_v_vehicle.driver() == &"bot", "in the driving seat")
	_check(
		_v_driver.get_parent() != playlot and _v_driver.is_inside_tree(),
		"with the rider's node carried by the vehicle",
		"which is what puts a rider's camera on it without a line about cameras"
	)

	# Forward. `move.y` is forward for a walking player and it is forward here.
	_v_forward = GSFpsCommand.new()
	_v_forward.move = Vector2(0.0, 1.0)
	await _test_vehicles_2()
	await _test_vehicles_3()
	await _test_vehicles_4()

func _test_vehicles_2() -> void:

	var before := _v_vehicle.position()
	await _drive(&"bot", _v_forward, 200)

	var travelled := _v_vehicle.position() - before

	_check(travelled.length() > 4.0, "it drives", "%.2f m" % travelled.length())
	_check(
		_v_vehicle.forward_speed() > 0.5,
		"FORWARDS, which is the one gs-vehicle says a car gets wrong",
		"%.2f m/s along its own -Z" % _v_vehicle.forward_speed()
	)
	_check(
		_v_driver.controller.state.position.distance_to(_v_vehicle.position()) < 4.0,
		"and the driver's replicated position went with it",
		"a passenger drawn where they got in is invisible in one process"
	)

	# Steering. Both directions, because a check that only measured "it turned" would
	# pass for a car that turns the wrong way — which is exactly the bug gs-vehicle
	# found in itself.
	var right := GSFpsCommand.new()
	right.move = Vector2(1.0, 1.0)

	var heading_before := -(_v_vehicle.node as Node3D).global_basis.z
	await _drive(&"bot", right, 160)
	var heading_after := -(_v_vehicle.node as Node3D).global_basis.z

	# Positive Y in a cross product of before × after means the turn was to the LEFT in
	# Godot's left-handed-looking convention, so a right turn is negative.
	var turn := heading_before.cross(heading_after).y

	_check(turn < -0.05, "steering right turns it right", "cross.y = %.3f" % turn)

	# A passenger, which is the case that only breaks with two people in it.
	_v_passenger = playlot.add_player(&"rider", "Rider")
	_v_passenger.teleport(_v_vehicle.position() + Vector3(0.0, 0.0, 4.0))

	_check(
		playlot.vehicles.ride.enter(_v_vehicle, &"rider", _v_passenger).ok,
		"a second player gets in as a passenger"
	)
	_check(_v_vehicle.occupant_count() == 2, "and the car has two people in it")
	_check(_v_vehicle.driver() == &"bot", "with the driver unchanged")

	var passenger_before := _v_passenger.controller.state.position
	await _drive(&"bot", _v_forward, 120)

	_check(
		_v_passenger.controller.state.position.distance_to(passenger_before) > 1.0,
		"the passenger is carried too",
		"%.2f m" % _v_passenger.controller.state.position.distance_to(passenger_before)
	)

	# Getting out, the half gs-vehicle says the bugs are in. Asserted on the SPEED first: a refusal
	# test against a stationary car passes without testing anything. Put back on a clean patch
	# pointed down the plate first, since the steering up to here leaves the end speed uncontrolled.
	(_v_vehicle.node as Node3D).global_transform = Transform3D(Basis.IDENTITY, _v_at)
	_v_vehicle.body().linear_velocity = Vector3.ZERO
	_v_vehicle.body().angular_velocity = Vector3.ZERO

func _test_vehicles_3() -> void:

	for _i in range(30):
		await get_tree().physics_frame

	await _drive(&"bot", _v_forward, 220)

	_check(
		_v_vehicle.speed() > _v_vehicle.def.tuning().max_exit_speed,
		"the car is going fast enough for the exit rule to have something to say",
		"%.2f m/s vs %.1f" % [_v_vehicle.speed(), _v_vehicle.def.tuning().max_exit_speed]
	)

	var moving := playlot.vehicles.ride.exit(_v_vehicle, &"rider")
	_check(
		not moving.ok,
		"and getting out at that speed is refused",
		"speed %.1f, limit %.1f" % [_v_vehicle.speed(), _v_vehicle.def.tuning().max_exit_speed]
	)

	var stop := GSFpsCommand.new()
	stop.set_button(GSFpsCommand.BUTTON_CROUCH, true)
	await _drive(&"bot", stop, 200)

	_check(_v_vehicle.speed() < 2.0, "the brake stops it", "%.2f m/s" % _v_vehicle.speed())

	var out := playlot.vehicles.ride.exit(_v_vehicle, &"rider")
	_check(out.ok, "and then the passenger can get out", str(out.error) if not out.ok else "")
	_check(not _v_passenger.riding, "and is walking again")
	_check(
		_v_passenger.global_position.distance_to(_v_vehicle.position()) > 0.9,
		"put down beside the car rather than inside it",
		"%.2f m" % _v_passenger.global_position.distance_to(_v_vehicle.position())
	)
	_check(
		_v_passenger.get_parent() == playlot,
		"and handed back to whoever had them before"
	)

	# How far it takes to stop, which "the brake stops it" never said: the brake once went to
	# Godot's wheels in newtons where it reads an impulse per step, stopping the buggy within a
	# couple of metres. Forces since gs-vehicle 4f4afaf.
	var foot := await _stopping(_v_vehicle, _v_at, &"bot", GSFpsCommand.BUTTON_CROUCH)
	var hand := await _stopping(_v_vehicle, _v_at, &"bot", GSFpsCommand.BUTTON_JUMP)
	print("  ..    the buggy from 50 km/h: brake (crouch) %.2f m, handbrake (jump) %.2f m" % [foot, hand])
	_check(foot > 7.0 and foot < 14.0, "the brake stops the buggy from 50 km/h in metres, not on the spot",
		"%.2f m" % foot)
	_check(hand > 6.8 and hand < 16.0, "and so does the handbrake", "%.2f m" % hand)
	# S: the brake while the buggy still rolls forward, reverse once it has stopped
	# (gs-vehicle's `brake_then_reverse`). On reverse thrust alone it was the engine's 35 %
	# against a brake several times that.
	var back := await _stopping(_v_vehicle, _v_at, &"bot", BACK_KEY)
	var reverse := GSFpsCommand.new()
	reverse.move = Vector2(0.0, -1.0)
	var stopped_at := _v_vehicle.position()
	await _drive(&"bot", reverse, 192)
	var heading := -(_v_vehicle.node as Node3D).global_transform.basis.z
	var backed := -(_v_vehicle.position() - stopped_at).dot(heading)
	print("  ..    the buggy from 50 km/h on S: %.2f m to a stop, then %.2f m back at %.2f m/s after 1.5 s more" % [back, backed, _v_vehicle.forward_speed()])
	_check(back < foot + 1.5, "S stops the buggy like the brake while it rolls forward, not on reverse thrust",
		"%.2f m against the brake's %.2f m" % [back, foot])
	_check(_v_vehicle.forward_speed() < -1.0 and backed > 1.0, "and once it has stopped, S held reverses it",
		"%.2f m/s, %.2f m back" % [_v_vehicle.forward_speed(), backed])
	# Stood still again, or it rolls away from the passenger put down beside it below.
	await _drive(&"bot", stop, 128)
	# Back beside the car, which those runs drove 60 m from where the passenger got out.
	_v_passenger.teleport(_v_vehicle.position() + Vector3(2.5, 0.0, 0.0))

func _test_vehicles_4() -> void:

	# The hovercraft, which is the only thing proving the chassis is a subclass point
	# rather than a promise.
	var skiff_prop := playlot.props.spawn(&"skiff", &"bot", Vector3(-24.0, 1.5, 24.0))
	_check(skiff_prop != null, "a skiff spawns")

	if skiff_prop != null:
		var skiff := playlot.vehicles.vehicle_for_node(skiff_prop.node)
		_check(skiff != null and skiff.chassis is GSVehicleHover, "on the hover chassis")
		_check(
			(skiff_prop.node as PlaylotVehicle).wheel_count() == 0,
			"with no wheels built for it"
		)

		for _i in range(120):
			await get_tree().physics_frame

		_check(
			skiff != null and skiff.position().y > 0.55,
			"and it is still off the ground a second later",
			# Above its own half-height plus a margin: a skiff whose hover did nothing
			# would come to rest with its box on the floor at exactly 0.35.
			"y = %.2f" % (skiff.position().y if skiff != null else -1.0)
		)

	# Deleting the car with somebody in it. A rider left inside a freed vehicle is a
	# player parented to nothing: invisible, unkillable, and unable to enter anything
	# else for the rest of the round, with no error anywhere.
	_check(playlot.use_vehicle(&"rider").ok, "the passenger gets back in")

	playlot.props.remove(_v_spawned.instance_id, GSPropSpawner.REASON_ADMIN)
	await get_tree().physics_frame

	_check(
		not playlot.vehicles.ride.is_riding(&"rider")
		and not playlot.vehicles.ride.is_riding(&"bot"),
		"removing the PROP evacuates everybody in the vehicle"
	)
	_check(not _v_driver.riding, "and the driver is a walking player again")
	_check(
		playlot.vehicles.world_count() == 1,
		"and the vehicle spawner has let go of it, leaving only the skiff",
		"%d left" % playlot.vehicles.world_count()
	)

	playlot.remove_player(&"rider")
	_done()


## Metres [param vehicle] takes from 50 km/h to a standstill, put back at [param at] facing
## +Z first, with [param button] held by [param id] (crouch the brake, jump the handbrake,
## [constant BACK_KEY] for S, which stops at the moment it stops rolling forward).
func _stopping(vehicle: GSVehicleInstance, at: Vector3, id: StringName, button: int) -> float:
	# Facing +Z, into the plate: -Z from here meets the plate's edge at about z = -72, which
	# a buggy reaching 50 km/h gets to first.
	(vehicle.node as Node3D).global_transform = Transform3D(Basis(Vector3.UP, PI), at)
	vehicle.body().linear_velocity = Vector3.ZERO
	vehicle.body().angular_velocity = Vector3.ZERO
	for _i in range(30):
		await get_tree().physics_frame

	var player: PlaylotPlayer = playlot.players[id]
	var go := GSFpsCommand.new()
	go.move = Vector2(0.0, 1.0)
	var guard := 1200
	while vehicle.forward_speed() < 13.89 and guard > 0:
		player.controller.apply_command(go.duplicate_command())
		await get_tree().physics_frame
		guard -= 1

	print("  ..    %s: %.1f m/s after %d ticks of throttle" % [{GSFpsCommand.BUTTON_CROUCH: "brake", BACK_KEY: "S"}.get(button, "handbrake"), vehicle.forward_speed(), 1200 - guard])
	var start := vehicle.position()
	var stop := GSFpsCommand.new()
	if button == BACK_KEY:
		stop.move = Vector2(0.0, -1.0)
	else:
		stop.set_button(button, true)
	guard = 1200
	while (vehicle.forward_speed() > 0.0 if button == BACK_KEY else vehicle.speed() > 0.3) and guard > 0:
		player.controller.apply_command(stop.duplicate_command())
		await get_tree().physics_frame
		guard -= 1

	var end := vehicle.position()
	return Vector2(end.x - start.x, end.z - start.z).length()
