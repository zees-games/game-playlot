extends "playlot_client_base.gd"

## The client half of chat on the screen: the chat box wired to the wire, the server's own lines, and a routed line drawn with its channel's prefix and colour.


## Joins the chat box to the three things it needs, the sampler too: movement is POLLED, so
## without `suspended` typing "sw" walks the player back. dot-server's `chat_received` feeds only
## the server's own lines; a PLAYER's line goes through this game's wire, so both would draw twice.
func _wire_chat_window() -> void:
	var window: GSChatWindow = presentation.chat_window if presentation != null else null

	if window == null:
		return

	window.submitted.connect(_on_chat_submitted)
	window.opened.connect(func(_channel: StringName) -> void: platform.refresh_blocked())
	window.closed.connect(func() -> void: platform.refresh_blocked())

	var client_link := GSRegistry.get_service(&"dot_client_link")

	if client_link != null and client_link.has_signal("chat_received"):
		client_link.connect("chat_received", _on_server_chat_state)


## dot-server's chat payload: the server's own lines (a vote between games, "Ada joined the game.",
## an admin's `say`) come only this way. A player's line is never drawn from here; this game
## routes those over its own wire.
func _on_server_chat_state(payload: Dictionary) -> void:
	if str(payload.get("kind", "")) != "state":
		var window: GSChatWindow = presentation.chat_window if presentation != null else null
		var _drawn := GSGameChatClient.draw_server_line(window, payload)
		return

	if presentation != null:
		presentation.set_chat_relayed(bool(payload.get("relay", false)))


## What a player typed, on its way to the server. Nothing is filtered here: the server decides
## what a line may contain and its answer is the only one that counts.
func _on_chat_submitted(text: String, channel: StringName) -> void:
	if bridge != null:
		bridge.say(channel, text)
		return

	# No bridge is a single-player sandbox, where there is no server to decide anything.
	# Drawing it locally is better than a box that swallows what you type.
	if presentation != null and presentation.chat_window != null:
		presentation.chat_window.add_said("You", text, Color(0.62, 0.78, 1.0))


## A routed line off this game's own wire, filed by [GSChatClient] — which drops a
## duplicate and reports a gap.
func _on_chat_wire(wire: Dictionary) -> void:
	if chat != null:
		chat.receive(wire)


## A line [GSChatClient] accepted: in sequence, not a duplicate, on a known channel.
##
## The channel, a [GSChatChannel] both ends share, decides the prefix and colour.
func _on_chat_message(message: GSChatMessage, channel_id: StringName) -> void:
	if hud == null:
		return

	var chan := chat.channel(channel_id)
	var prefix := "%s " % chan.prefix if chan != null and chan.prefix != "" else ""

	var window: GSChatWindow = presentation.chat_window if presentation != null else null
	var colour := chan.colour if chan != null else Color(0.88, 0.90, 0.94)

	# In the chat box, and on the notice line only when there is no box: the notice line keeps what
	# is the game's (budget reached, a tool's refusal), never chat. A join or leave notice is a name
	# and no text, so `describe()` words it ("Guest 435 joined"); other kinds are drawn by their text.
	var text := message.describe() \
		if message.kind in [GSChatMessage.Kind.JOIN, GSChatMessage.Kind.LEAVE] \
		else message.text

	if message.is_from_server() or message.sender_name == "":
		if window != null:
			window.add_text("%s%s" % [prefix, text], Color(0.80, 0.82, 0.86))
		else:
			hud.notice("%s%s" % [prefix, text])

		return

	if window != null:
		window.add_said("%s%s" % [prefix, message.sender_name], message.text, colour)
	else:
		hud.notice("%s%s: %s" % [prefix, message.sender_name, message.text])
