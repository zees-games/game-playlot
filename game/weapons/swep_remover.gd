extends "playlot_weapon.gd"

## Points at a prop and removes it. Right click removes everything you own.
##
## Extends a PATH rather than a class, for the reason in `swep_launcher.gd`.
##
## [b]It goes through `may_act_on`, which is the whole point.[/b] Whether a player may
## remove somebody else's crate is a server policy — a build server says no, a sandbox
## says yes, a competitive one says only for admins — and gs-props deliberately
## refuses to decide it inside the tool. So this asks, with the host's answer, and a
## remover on a build server is a remover that only removes your own things without
## anybody editing this file.
##
## [b]It does not use the undo stack.[/b] Undo is "take back what I just made", and a
## remover pointed at a tower somebody else built is not that. The prop goes through
## `remove`, which frees it and tells its owner's budget, and it is not put back by Z.


func _primary(space: Variant, origin: Vector3, aim: Vector3) -> GSResult:
	var prop := target(space, origin, aim)

	if prop == null:
		return GSResult.fail(GSError.CODE_STATE, "Nothing in range.")

	var allowed := may_act_on(prop, _may_touch_others())

	if not allowed.ok:
		return allowed

	# The instance id, not the node: `queue_free` is deferred, so a caller that
	# removed by node would still find it valid for the rest of the frame — which is
	# exactly the window in which a second click removes it again.
	spawner.remove(prop.instance_id, GSPropSpawner.REASON_PLAYER)

	return GSResult.success(prop)


func _secondary(_space: Variant, _origin: Vector3, _aim: Vector3) -> GSResult:
	if spawner == null:
		return GSResult.fail(GSError.CODE_STATE, "This weapon has no world.")

	var removed := spawner.clear_player(wielder, GSPropSpawner.REASON_PLAYER)

	return GSResult.success(removed)


## Whether this server lets a player touch what somebody else made.
func _may_touch_others() -> bool:
	return game == null or game.config == null or game.config.touch_others_props
