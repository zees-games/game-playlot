extends "swep_launcher.gd"

## The multi-tool's spawn mode: puts the armed item down where you point. Left click places one,
## holding it places another every `pg_multi_spawn_repeat` seconds (0 = every tick). Right click is
## the client's: it opens the Q menu to change the item. Extends the launcher for its armed prop.
##
## [b]What is armed is a pick[/b] (`PlaylotMultitool.pick`): a prop or a weapon's pickup is spawned
## through the spawner (limits, budget, undo, ownership; a refusal is told by its `refused` signal),
## an addon item runs at the point, a build is handed to [member place_build] (the server's builds).

const PlaylotMultitool := preload("../playlot_multitool.gd")
const PlaylotProp := preload("../playlot_prop.gd")

## The session the addon items run for (0 offline), set by whoever builds the toy.
var session_id := 0

## (build name, at, yaw) -> GSResult, set by the server; unset, builds are refused.
var place_build := Callable()

var _since := 0.0


func _primary(space: Variant, origin: Vector3, aim: Vector3) -> GSResult:
	_since = 0.0
	return place(space, origin, aim)


## Right click is the client's (it opens the Q menu), so the launcher's hurl is not inherited.
func _secondary(_space: Variant, _origin: Vector3, _aim: Vector3) -> GSResult:
	return GSResult.fail(GSError.CODE_UNSUPPORTED, "")


## Held past the press: another every repeat interval, 0 every tick. null when none was due.
func _held(space: Variant, origin: Vector3, aim: Vector3, delta: float) -> GSResult:
	_since += delta
	var every := repeat_seconds()
	if _since < every:
		return null
	_since = 0.0 if every <= 0.0 else fmod(_since, every)
	return place(space, origin, aim)


func repeat_seconds() -> float:
	if game != null and game.config != null:
		return maxf(0.0, game.config.multi_spawn_repeat)
	return 0.15


## Puts the armed pick down at what [param aim] hits from [param origin].
func place(space: Variant, origin: Vector3, aim: Vector3) -> GSResult:
	if game == null or spawner == null:
		return GSResult.fail(GSError.CODE_STATE, "This tool has no world.")
	var parts := PlaylotMultitool.pick_parts(armed if armed != &"" else FALLBACK)
	var id := parts[1]
	var hit := aimed(space, origin, aim)
	var yaw := atan2(-aim.x, -aim.z)
	match parts[0]:
		"prop":
			return _put(StringName(id), origin, hit, yaw)
		"weapon":
			if game.weapon_def(StringName(id)) == null:
				return GSResult.fail(GSError.CODE_INVALID, "There is no weapon '%s'." % id)
			return _put(Playlot.pickup_id_of(StringName(id)), origin, hit, yaw)
		"addon":
			return game.activate_addon_item(id, session_id, hit["at"], wielder)
		"build":
			if not place_build.is_valid():
				return GSResult.fail(GSError.CODE_UNSUPPORTED, "Builds are put down by a server.")
			var placed: GSResult = place_build.call(id, hit["at"], yaw)
			return placed
	return GSResult.fail(GSError.CODE_INVALID, "Spawn mode cannot put down '%s'." % String(armed))


## {at, normal, hit}: the first thing along [param aim] within reach, else [code]near[/code] metres on.
func aimed(space: Variant, origin: Vector3, aim: Vector3) -> Dictionary:
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * tune(&"reach", 64.0))
		query.collide_with_areas = false
		var hit: Dictionary = (space as PhysicsDirectSpaceState3D).intersect_ray(query)
		if not hit.is_empty():
			return {"at": hit["position"], "normal": hit["normal"], "hit": true}
	return {"at": origin + aim * tune(&"near", 3.0), "normal": Vector3.UP, "hit": false}


## Upright, turned to face the player, and pushed off the surface by its half size along the normal.
func _put(prop_id: StringName, origin: Vector3, hit: Dictionary, yaw: float) -> GSResult:
	var def: GSPropDef = game.props.catalogue.get_prop(prop_id) if game.props.catalogue != null else null
	if def == null:
		return GSResult.fail(GSError.CODE_INVALID, "There is no prop '%s'." % String(prop_id))
	var turn := Basis(Vector3.UP, yaw + PI)
	var at: Vector3 = hit["at"]
	if bool(hit["hit"]):
		var half := PlaylotProp.extent_of(def) * 0.5
		var local: Vector3 = (turn.inverse() * (hit["normal"] as Vector3)).abs()
		at += (hit["normal"] as Vector3) * (local.dot(half) + tune(&"gap", 0.02))
	if _inside_wielder(origin, at, PlaylotProp.extent_of(def) * 0.5):
		return GSResult.fail(GSError.CODE_FORBIDDEN, "Too close: aim further away.")
	var prop: GSPropInstance = spawner.spawn(prop_id, wielder, at, turn)
	if prop == null:
		# The spawner's `refused` signal already told the player why.
		return GSResult.fail(GSError.CODE_FORBIDDEN, "")
	return GSResult.success(prop)


## Whether a box of [param half] size at [param at] would stand in the wielder, whose eye is [param eye]:
## held down, a pile grows back along the aim, and without this it swallows the player.
func _inside_wielder(eye: Vector3, at: Vector3, half: Vector3) -> bool:
	var reach := maxf(half.x, half.z) + tune(&"clearance", 0.45)
	if Vector2(at.x - eye.x, at.z - eye.z).length() >= reach:
		return false
	return at.y - half.y < eye.y + 0.2 and at.y + half.y > eye.y - 1.8
