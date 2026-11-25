extends RefCounted

const PlaylotNetCommand := preload("playlot_net_command.gd")

## Where every other player stood on a mover's screen, for lag-compensated hulls (`mp_solidplayers_unlag`): this game's half of [GSPlayerHullView]. The addon owns the ring, the resolve rule and the fill maths; this class only says where Playlot keeps things.
## A command carries `view_lag_q`, `view_back` and `view_span` ([PlaylotNetCommand]), the behaviour keeps the last heard ([PlaylotPlayerNet]), the server records feet after each tick, the client answers from the interpolator. The hulls are the players' own bodies ([GSPlayerBodyRules.apply_hull] adds the capsule), so `game.players` is the body table.

var view := GSPlayerHullView.new()

var _game: Object = null
var _bridge: Object = null
var _wire_var: Object = null


static func session_of(id: Variant) -> int:
	return String(id).trim_prefix("u").to_int()


func _init(game: Object, bridge: Object, is_server: bool) -> void:
	_game = game
	_bridge = bridge
	view.is_server = is_server
	view.snap_fn = _snap
	view.view_fn = _sent
	view.client_fn = _drawn


## Runs [param work] for [param mover]'s step at [param tick] with the other hulls where the mover's last command said they were drawn.
func around(mover: Variant, tick: int, work: Callable) -> Variant:
	return view.around(_game.body_rules, mover, _game.players, tick, work)


## Whether a step is to be wrapped at all: players solid and the rule on.
func live() -> bool:
	return _game != null and _game.body_rules.solid and _game.body_rules.unlag


## The server's ring, after [param tick]'s moves. Kept while players are solid, so turning the rule on finds history already there.
func record(tick: int) -> void:
	if not view.is_server or _game == null or not _game.body_rules.solid:
		return
	var net: Object = _bridge.get(&"net")
	view.capacity = ceili(net.config.max_rewind_sec * float(_game.tick_rate)) + 4
	var positions := {}
	for id: Variant in _game.players:
		var body: Object = _game.players[id]
		if body != null and is_instance_valid(body) and body.get(&"controller") != null:
			positions[id] = body.controller.state.position
	view.record(tick, positions)


## Sets the lag and bracket on [param command] for [param tick] as this client draws the others now. Leaves none when the interpolator is not running yet.
func fill(command: PlaylotNetCommand, tick: int) -> void:
	command.view_lag_q = -1
	command.view_back = -1
	command.view_span = 0
	var net: Object = _bridge.get(&"net")
	if net == null or net.get(&"interpolator") == null or not net.clock.is_synced():
		return
	var drawn: float = float(net.clock.received_tick()) + clampf(net.clock.render_alpha(), -1.0, 2.0) + net.clock.receive_slip() - net.interpolator.delay_ticks()
	var q := GSPlayerHullView.lag_q_for(tick, drawn, PlaylotNetCommand.MAX_VIEW_LAG_Q)
	var pair: Vector2i = net.interpolator.bracket_at(float(tick) - float(q) * 0.25)
	var back_span := GSPlayerHullView.bracket_for(tick, pair, PlaylotNetCommand.VIEW_BACK_BITS, PlaylotNetCommand.VIEW_SPAN_BITS)
	command.view_lag_q = q
	command.view_back = back_span[0]
	command.view_span = back_span[1]


func _sent(mover: Variant) -> Variant:
	var behaviour: Object = _bridge.call(&"behaviour_for", session_of(mover))
	if behaviour == null:
		return null
	return [behaviour.last_view_q, behaviour.last_view_tick, behaviour.last_view_back, behaviour.last_view_span]


func _drawn(other: Variant, older: int, span: int, render: float) -> Variant:
	var theirs: Object = _bridge.call(&"behaviour_for", session_of(other))
	var net: Object = _bridge.get(&"net")
	if theirs == null or theirs.get(&"identity") == null or net == null or net.get(&"interpolator") == null:
		return null
	var id: int = (theirs.get(&"identity") as Object).get(&"net_id")
	if older >= 0:
		return net.interpolator.value_between(id, &"net_position", older, older + span, render, view.teleport_cut)
	return net.interpolator.value_at(id, &"net_position", render, view.teleport_cut)


func _snap(feet: Vector3) -> Vector3:
	if _wire_var == null and _game != null and _bridge != null:
		for id: Variant in _game.players:
			var behaviour: Object = _bridge.call(&"behaviour_for", session_of(id))
			if behaviour != null:
				_wire_var = behaviour.call(&"find_var", &"net_position")
				if _wire_var != null:
					break
	return _wire_var.wire_value(feet) if _wire_var != null else feet
