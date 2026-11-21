extends RefCounted

const Playlot := preload("playlot.gd")
const PlaylotArena := preload("playlot_arena.gd")
const PlaylotPlayer := preload("playlot_player.gd")

## What dot-moderation's live tools mean in a sandbox that may carry a run timer.
##
## Movement is `GSFpsAdminModifiers`, so the owning client predicts it. Health belongs to
## the arena layer and exists only while `pg_arena` is on, so god, buddha, hp and slay say
## "not on this server" when it is off rather than being absent — whether they mean
## anything is a cvar, not a build. A run belongs to the timer when a server links one
## ([code]addons/pg_timer[/code]), and its rule is that an admin's help can never make a time. Noclip abandons the run
## in progress, `PlaylotPlayer` taints any run made while noclipped or on a speed or
## gravity step, and a teleport by an admin ends the run.
##
## Blind and beacon are the two that are about a SCREEN rather than a body, and each is one
## flag on [PlaylotPlayer] that `PlaylotPlayerNet` replicates — the blind to its owner
## alone, the beacon to everybody — and that the client draws: `PlaylotHud` blacks the
## owner's screen out, `GSFxBeacon` rings the player on every screen and pings. The
## server decides; nothing about either is a client's to choose. Neither touches the timer:
## a blinded run is harder, not assisted, and a beacon is a thing other people see.
##
## [b]Both outlive a respawn here without being told to[/b], and so does everything else:
## a respawn in this game — the admin's, the course's, the arena's — is a teleport of the
## same body (`Playlot.spawn_player`), so nothing a handler set on the player is lost
## and `GSModTools.respawned` is never called. That is the right answer for blind and
## beacon, which are about the person rather than the body, and a death is exactly what a
## player being punished would otherwise use to end one.

## Ids are the session userid as a string; this game's player key is `u<userid>`.
static func key_of(id: StringName) -> StringName:
	return StringName("u%s" % String(id))


static func handlers(game: Playlot, arena: PlaylotArena) -> Dictionary:
	return {
		GSModTools.ACTION_NOCLIP: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			if p == null:
				return _absent(id)
			var on := bool(args["on"])
			if on:
				p.stop_run(&"noclip")
			return GSFpsAdminModifiers.set_noclip(p.controller, on),

		GSModTools.ACTION_FREEZE: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			return _absent(id) if p == null else GSFpsAdminModifiers.set_frozen(p.controller, bool(args["on"])),

		GSModTools.ACTION_SPEED: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			return _absent(id) if p == null else GSFpsAdminModifiers.set_speed(p.controller, float(args["scale"])),

		GSModTools.ACTION_GRAVITY: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			return _absent(id) if p == null else GSFpsAdminModifiers.set_gravity(p.controller, float(args["scale"])),

		GSModTools.ACTION_RESPAWN: func(id: StringName, _args: Dictionary) -> GSResult:
			if _player(game, id) == null:
				return _absent(id)
			game.spawn_player(key_of(id))
			return GSResult.success(null),

		GSModTools.ACTION_RENAME: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			if p == null:
				return _absent(id)
			p.display_name = str(args["name"]).strip_edges().substr(0, 32)
			return GSResult.success(p.display_name),

		GSModTools.ACTION_GOD: func(id: StringName, args: Dictionary) -> GSResult:
			var health := _health(arena, id)
			if health == null:
				return _no_health()
			health.invulnerable = bool(args["on"])
			return GSResult.success(health.invulnerable),

		GSModTools.ACTION_BUDDHA: func(id: StringName, args: Dictionary) -> GSResult:
			var health := _health(arena, id)
			if health == null:
				return _no_health()
			health.cannot_die = bool(args["on"])
			return GSResult.success(health.cannot_die),

		GSModTools.ACTION_HEALTH: func(id: StringName, args: Dictionary) -> GSResult:
			var health := _health(arena, id)
			if health == null:
				return _no_health()
			if not health.alive:
				return GSResult.fail(GSError.CODE_STATE, "They are dead.")
			health.health = minf(float(args["value"]), 250.0)
			return GSResult.success(health.health),

		GSModTools.ACTION_SLAY: func(id: StringName, _args: Dictionary) -> GSResult:
			var health := _health(arena, id)
			if health == null:
				return _no_health()
			if not health.alive:
				return GSResult.fail(GSError.CODE_STATE, "They are already dead.")
			var was_god := health.invulnerable
			var was_buddha := health.cannot_die
			health.invulnerable = false
			health.cannot_die = false
			health.invulnerable_until_tick = -1
			var damage := arena.hurt(&"", key_of(id), health.health + 1000.0, 0.0, GSHitGroup.CHEST, true)
			health.invulnerable = was_god
			health.cannot_die = was_buddha
			if damage == null or not damage.lethal:
				return GSResult.fail(GSError.CODE_STATE, "The slay was refused.",
					damage.refusal if damage != null else "")
			return GSResult.success(null),

		GSModTools.ACTION_SLAP: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			if p == null:
				return _absent(id)
			# A shove is movement, which every server here has; the damage is the arena's.
			p.controller.state.velocity += Vector3(3.0, 5.0, 3.0)
			p.controller.state.mode = GSFpsState.Mode.AIR
			# Speed nobody earned: an admin's help, which a course time must not carry.
			p.taint_run()
			var amount := float(args.get("damage", 0.0))
			if amount > 0.0 and _health(arena, id) != null:
				var _hurt := arena.hurt(&"", key_of(id), amount, 0.0, GSHitGroup.CHEST, true)
			return GSResult.success(null),

		GSModTools.ACTION_BLIND: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			if p == null:
				return _absent(id)
			# The screen and nothing else. A blinded player still moves, builds and runs
			# the course; an admin who wants them to stop as well has freeze, and one verb
			# that did both would be a verb nobody could use for only the first.
			p.blinded = bool(args["on"])
			return GSResult.success(p.blinded),

		GSModTools.ACTION_BEACON: func(id: StringName, args: Dictionary) -> GSResult:
			var p := _player(game, id)
			if p == null:
				return _absent(id)
			p.beacon = bool(args["on"])
			return GSResult.success(p.beacon),
	}


static func unsupported() -> Dictionary:
	return {
		GSModTools.ACTION_GIVE: "what a player holds here is the physics gun, the gravity gun and a loadout they choose",
		GSModTools.ACTION_STRIP: "a sandbox player without the physics gun has no game",
		GSModTools.ACTION_BURN: "nothing here burns a player",
	}


static func position_of(game: Playlot, id: StringName) -> Variant:
	var p := _player(game, id)
	return p.controller.state.position if p != null and not p.riding else null


## An admin moving somebody is a player leaving the course, so the run ends.
static func teleport(game: Playlot, id: StringName, to: Variant) -> void:
	var p := _player(game, id)

	if p == null or p.riding or not (to is Vector3):
		return

	# `teleport` stops a run itself.
	p.teleport(to as Vector3, p.controller.state.yaw)


static func _player(game: Playlot, id: StringName) -> PlaylotPlayer:
	return game.players.get(key_of(id)) if game != null else null


static func _health(arena: PlaylotArena, id: StringName) -> GSHealth:
	if arena == null or not arena.enabled:
		return null
	return arena.health_of(key_of(id))


static func _absent(id: StringName) -> GSResult:
	return GSResult.fail(GSError.CODE_STATE, "Player %s is not in the world." % String(id))


static func _no_health() -> GSResult:
	return GSResult.fail(
		GSError.CODE_UNSUPPORTED,
		"The arena is off, so nobody has health.",
		"pg_arena on"
	)
