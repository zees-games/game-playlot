extends RefCounted

## The phone's controls (dot-mobile's [DotMobileControls] driving the client's own sampler): the buttons are fire, alt-fire, jump, crouch, the hold-to-open spawn menu, tool previous/next,
## the held scoreboard and the chat box.
## The look and move halves of the screen are [DotFpsTouchSampler]'s; dot-mobile's overlay draws and routes the buttons.

const CHANNEL := "playlot.touch"
const PlaylotPaths := preload("../playlot_paths.gd")

const FIRE := DotGameTouchLayout.FIRE
const ALT := DotGameTouchLayout.ALT
const JUMP := DotGameTouchLayout.JUMP
const CROUCH := DotGameTouchLayout.CROUCH
const MENU := &"spawn"
const PREV := DotGameTouchLayout.PREV
const NEXT := DotGameTouchLayout.NEXT
const BOARD := DotGameTouchLayout.BOARD
const CHAT := DotGameTouchLayout.CHAT


## The fps preset less use and reload, plus the spawn menu's Q in the slot use leaves.
static func touch_layout() -> DotGameTouchLayout:
	var res := DotGameTouchLayout.build(DotGameTouchLayout.FPS, {
		DotGameTouchLayout.USE: null,
		DotGameTouchLayout.RELOAD: null,
		MENU: {"slot": &"inner", "label": "Q"},
	})
	if not res.ok:
		DotLog.error(CHANNEL, "touch layout refused", {"error": str(res.error)})
		return DotGameTouchLayout.custom()
	return res.value

## The rows dot-mobile's overlay is set up with: [method touch_layout]'s, with jump and crouch held on the sampler.
static func layout() -> Array[Dictionary]:
	var rows := touch_layout().buttons()
	for row: Dictionary in rows:
		if row["id"] == JUMP:
			row["hold"] = DotFpsCommand.BUTTON_JUMP
		elif row["id"] == CROUCH:
			row["hold"] = DotFpsCommand.BUTTON_CROUCH
	return rows


var controls: DotMobileControls = null
## dot-ui's buttons inside the overlay, for the shell's DPI fit.
var buttons: DotTouchButtons:
	get:
		return controls.buttons if controls != null else null

var _handlers: Dictionary = {}


## Builds the overlay under [param host] (the HUD), following [param rules] (the server's) and driving [param sampler].
## [param handlers] maps a button id to a Callable taking `down: bool` (fire, alt, spawn menu, tool steps, board, chat);
## jump and crouch are held on the sampler by the overlay. The sampler's own `ignore_fn` (the Menu button's rectangle)
## moves to the overlay, which keeps a finger on it off the stick.
static func build(host: Control, sampler: DotFpsSampler, rules: DotMobileRules, handlers: Dictionary) -> RefCounted:
	var made = (load(PlaylotPaths.rebase("res://game/client/playlot_touch.gd")) as GDScript).new()
	made.call(&"_setup", host, sampler, rules, handlers)
	return made


func _setup(host: Control, sampler: DotFpsSampler, rules: DotMobileRules, handlers: Dictionary) -> void:
	_handlers = handlers
	controls = DotMobileControls.new()
	controls.name = "TouchControls"
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rules != null:
		controls.rules = rules
	controls.setup(sampler, layout())
	controls.button_pressed.connect(_route.bind(true))
	controls.button_released.connect(_route.bind(false))
	host.add_child(controls)


## True when the overlay is up and forwards [param event] itself, or [param event] is the mouse Godot emulates from a
## touch, which would click and turn the view a second time.
func takes(event: InputEvent) -> bool:
	if controls == null or not controls.touch:
		return false
	return controls.takes(event) or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION)


func active() -> bool:
	return controls != null and controls.touch


## Called every frame by the client: the overlay hides and lifts its fingers while a menu, the chat box or the console has the screen.
func sync(busy: bool) -> void:
	if controls != null:
		controls.paused = busy


func describe() -> Dictionary:
	return controls.describe() if controls != null else {"built": false}


func _route(id: StringName, down: bool) -> void:
	if _handlers.has(id):
		(_handlers[id] as Callable).call(down)


## A touch sampler where a phone is, the keyboard one otherwise; [param tunables] are the player's; [param ignore_fn] is asked with a screen position and keeps a button's finger off the stick.
static func make_sampler(tunables: DotFpsTunables, ignore_fn: Callable) -> DotFpsSampler:
	var sampler: DotFpsSampler
	if DotPlatform.has_touch():
		var touch := DotFpsTouchSampler.new(tunables)
		touch.ignore_fn = ignore_fn
		sampler = touch
	else:
		sampler = DotFpsSampler.new(tunables)
	DotFpsSampler.register_default_actions(sampler)
	return sampler
