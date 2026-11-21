extends "res://addons/gs_npc_ai/runtime/gs_npc_ai_brain.gd"

## How an armed sandbox NPC decides: gs-npc-ai's tactical layer, with whatever it is holding.
##
## [codeblock]
## selector (reactive)
##   flee danger
##   sequence (reactive)  has a target?
##     selector
##       sequence (reactive)  melee weapon?          -> the attack slot -> close in, swing
##       sequence (reactive)  badly hurt?            -> cover, still shooting
##       sequence (reactive)  the squad's flank role -> round its side, shooting
##       suppress                                    -> hold the range band, shooting
##   search where it probably went
##   follow the owner (a friendly one)
##   walk the owner's waypoint route
##   patrol where players go
##   hold
## [/codeblock]
##
## [b]The brain decides; the body fires.[/b] Every leaf that may shoot sets [member wants_fire]
## and an aim point; the soldier entity turns that into a held trigger on its zee rig, so
## fire rate, magazine, reload and spread are the weapon's own — a shotgun NPC fires like a
## shotgun because it IS one, and nothing here knows what a shotgun is.
##
## [b]Extended by PATH.[/b] A brain inside a mounted pack cannot name a `class_name`.

const ROLE_FLANK_TACTICS := 0.5

## Set by a leaf when every fire gate is open this tick. Read and cleared by the soldier.
var wants_fire: bool = false

## Where to aim, when [member wants_fire].
var aim_at: Vector3 = Vector3.ZERO

## The entity this brain drives. Set before bind.
var body: Node3D = null

var _cover_until: float = -INF

## The waypoint being walked to, and the one before it (so a dead end turns round rather than
## sticking). See [method _walk_route].
var _wp: Node3D = null
var _wp_prev: Node3D = null

## How near, horizontally, counts as at a waypoint.
const WAYPOINT_ARRIVE := 1.4

## How far away the route is looked for when none is being walked.
const WAYPOINT_SEARCH := 80.0


func _build() -> void:
	tree = GSNpcAiSelector.new(&"root", [
		GSNpcAiLeaf.Action.new(&"flee", func(c: GSNpcAiContext) -> int: return flee_danger(c, _speed() * 1.3)),
		GSNpcAiSequence.reactive_with(&"fight", [
			GSNpcAiLeaf.Condition.new(&"has a target", func(_c: GSNpcAiContext) -> bool: return npc.has_target()),
			GSNpcAiSelector.new(&"engage", [
				GSNpcAiSequence.reactive_with(&"melee", [
					GSNpcAiLeaf.Condition.new(&"melee weapon", func(_c: GSNpcAiContext) -> bool:
						return _is_melee() and claim_attack_slot()),
					GSNpcAiLeaf.Action.new(&"close in", _close_in),
				] as Array[GSNpcAiNode]),
				GSNpcAiSequence.reactive_with(&"break off", [
					GSNpcAiLeaf.Condition.new(&"badly hurt", _should_break_off),
					GSNpcAiLeaf.Action.new(&"to cover", _to_cover),
				] as Array[GSNpcAiNode]),
				GSNpcAiSequence.reactive_with(&"flank", [
					GSNpcAiLeaf.Condition.new(&"flank role", func(_c: GSNpcAiContext) -> bool:
						return not _is_melee() and tactics() >= ROLE_FLANK_TACTICS and claim_role(ROLE_FLANK, 1)),
					GSNpcAiLeaf.Action.new(&"go round", _flank),
				] as Array[GSNpcAiNode]),
				GSNpcAiLeaf.Action.new(&"suppress", _suppress),
			] as Array[GSNpcAiNode]),
		] as Array[GSNpcAiNode]),
		GSNpcAiLeaf.Action.new(&"search", func(c: GSNpcAiContext) -> int: return search(c, _speed() * 0.7)),
		GSNpcAiLeaf.Action.new(&"follow", _follow_owner),
		GSNpcAiLeaf.Action.new(&"route", _walk_route),
		GSNpcAiLeaf.Action.new(&"patrol", func(c: GSNpcAiContext) -> int: return patrol_hot(c, _speed() * 0.5)),
		GSNpcAiLeaf.Action.new(&"hold", func(_c: GSNpcAiContext) -> int:
			halt()
			return GSNpcAiNode.Status.RUNNING),
	] as Array[GSNpcAiNode])


func _speed() -> float:
	return tune(&"speed", 4.5)


func _is_melee() -> bool:
	return body != null and bool(body.call("holds_melee"))


func _muzzle() -> Vector3:
	return body.call("muzzle") if body != null else npc.position()


## Opens the trigger for this tick if every gate in `ready_to_fire` is open.
func _consider_firing() -> void:
	if body == null or not bool(body.call("is_armed")):
		return

	var muzzle := _muzzle()

	if ready_to_fire(muzzle, 14.0):
		wants_fire = true
		aim_at = aim_solution(muzzle)


func _close_in(ctx: GSNpcAiContext) -> int:
	var at := target_position(Vector3.INF)

	if at == Vector3.INF:
		return GSNpcAiNode.Status.FAILURE

	var flat := at - npc.position()
	flat.y = 0.0

	if flat.length() > tune(&"reach", 1.6):
		if has_reacted():
			steer_with_spacing(at, _speed(), ctx.delta)
		else:
			halt()
	else:
		halt()

	face(at - npc.position())

	if flat.length() <= tune(&"reach", 1.6) + 0.4:
		_consider_firing()

	return GSNpcAiNode.Status.RUNNING


func _should_break_off(ctx: GSNpcAiContext) -> bool:
	var careful := character.self_preservation if character != null else 0.5

	if ctx.has_condition(GSNpcAiConditions.HEAVY_DAMAGE) and careful >= 0.3:
		_cover_until = ctx.now + 3.0

	return ctx.now < _cover_until


func _to_cover(ctx: GSNpcAiContext) -> int:
	var status := take_cover(ctx, _speed())
	_consider_firing()
	return GSNpcAiNode.Status.RUNNING if status != GSNpcAiNode.Status.FAILURE else status


func _flank(ctx: GSNpcAiContext) -> int:
	var center := target_position(Vector3.INF)

	if center == Vector3.INF:
		return GSNpcAiNode.Status.FAILURE

	var here := npc.position()
	var radius := (tune(&"near", 8.0) + tune(&"far", 16.0)) * 0.5
	var point := GSNpcAiTactics.ring_point(center, here, radius, _enemy_facing(center), flank_lead)
	var flat := point - here
	flat.y = 0.0

	if flat.length() > 1.0:
		steer_with_spacing(point, _speed(), ctx.delta)
	else:
		halt()

	face(center - here)
	_consider_firing()
	return GSNpcAiNode.Status.RUNNING


func _suppress(ctx: GSNpcAiContext) -> int:
	var status := hold_range(ctx, _speed(), tune(&"near", 8.0), tune(&"far", 16.0))
	_consider_firing()
	return status


## A friendly NPC keeps near the player who spawned it when there is nobody to fight.
## FAILURE for a hostile one, or one with nobody to follow, which hands on to the patrol.
func _follow_owner(ctx: GSNpcAiContext) -> int:
	if tune(&"follow", 0.0) <= 0.0 or npc.owner_id == &"":
		return GSNpcAiNode.Status.FAILURE

	var owner_at := target_position_of(npc.owner_id)

	if owner_at == Vector3.INF:
		return GSNpcAiNode.Status.FAILURE

	var flat := owner_at - npc.position()
	flat.y = 0.0

	if flat.length() > 4.0:
		steer_with_spacing(owner_at, _speed(), ctx.delta)
	else:
		halt()
		face(flat)

	return GSNpcAiNode.Status.RUNNING


## Walks the waypoints the owner laid: to the nearest one, then on along its links, never back
## the way it came unless it is a dead end. FAILURE with no waypoint in reach, which hands on
## to the heat-map patrol, so an NPC with no route behaves exactly as before.
##
## [b]Ahead of the heat-map patrol and behind everything that fights[/b]: a route is what an
## NPC does with nothing to do, and a target, a danger or a search all come first.
func _walk_route(ctx: GSNpcAiContext) -> int:
	var game: Variant = body.get("game") if body != null else null

	if game == null or not game.has_method(&"nearest_waypoint"):
		return GSNpcAiNode.Status.FAILURE

	if _wp == null or not is_instance_valid(_wp) or not _wp.is_inside_tree():
		_wp = game.call(&"nearest_waypoint", npc.owner_id, npc.position(), WAYPOINT_SEARCH)
		_wp_prev = null

		if _wp == null:
			return GSNpcAiNode.Status.FAILURE

	var flat := _wp.global_position - npc.position()
	flat.y = 0.0

	if flat.length() <= WAYPOINT_ARRIVE:
		_wp = _next_waypoint()

		if _wp == null:
			return GSNpcAiNode.Status.FAILURE

		flat = _wp.global_position - npc.position()
		flat.y = 0.0

	steer_with_spacing(_wp.global_position, _speed() * 0.6, ctx.delta)
	return GSNpcAiNode.Status.RUNNING


## The waypoint after the current one: a linked one that is not the one just left (the first
## such, drawn by this NPC's seed and how many it has passed when there are several), else
## back the way it came.
func _next_waypoint() -> Node3D:
	var options: Array = []

	for other in _wp.call(&"neighbours"):
		if other != _wp_prev:
			options.append(other)

	var chosen: Node3D = _wp_prev

	if not options.is_empty():
		_visited += 1
		chosen = options[int(GSNpcAiNode.deterministic_unit(npc.seed, _visited) * options.size()) % options.size()]

	_wp_prev = _wp
	return chosen if chosen != null and is_instance_valid(chosen) else _wp_prev


var _visited: int = 0


func target_position_of(id: StringName) -> Vector3:
	if director == null or not director.has_method(&"candidate_position"):
		return Vector3.INF

	var found: Variant = director.call(&"candidate_position", id, Vector3.INF)
	return found if found is Vector3 else Vector3.INF
