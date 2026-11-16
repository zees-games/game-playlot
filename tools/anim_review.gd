extends Node

const PlaygroundClient := preload("../game/playground_client.gd")
const PlaygroundConfig := preload("../game/playground_config.gd")
const PlaygroundViewGrip := preload("../game/playground_view_grip.gd")
const PlaygroundPresentation := preload("../game/playground_presentation.gd")
const PlaygroundZee := preload("../game/playground_zee.gd")

## The animation review (docs/anim-review.md): the offline client plays each zee weapon's clips and the avatar's locomotion
## at --fps, and every frame is saved three times: first person (the root viewport), behind-right, and an opponent's view
## from in front (two SubViewports of the same world that see your body and the gun in its hand, and not the first-person
## arms or view model). Per clip it prints `ANIMREVIEW {json}` (a verdict from the numbers) and writes
## <out>/<weapon>/_frames/fp_<clip>/{f,t,o}_NNN.jpg, which tools/anim_review_shot.sh turns into sheets and clips.
##
## Run through tools/anim_review.sh. Arguments after `--`: --out DIR, --fps N, --only id,id (zee ids, or `all`; default
## one weapon per pose), --anims clip,clip, --no-avatar.

## Your own body draws only in the outside views; the first-person arms and view model only in the first-person one.
const BODY_LAYER := 1 << 18
const ARMS_LAYER := 1 << 17
## The opponent's view: standing this far in front of you, eyes at this height, looking at your chest.
const OPPONENT_AT := Vector3(0.4, 1.6, -4.0)
## The behind-right view, in the player's frame.
const BEHIND_AT := Vector3(1.4, 1.5, 2.0)
const WEAPON_CLIPS: PackedStringArray = ["idle", "draw", "fire", "reload", "ads", "sprint"]
const AVATAR_ANIMS := {"avatar_walk": [&"dot_fps_forward"], "avatar_strafe": [&"dot_fps_left"],
	"avatar_run": [&"dot_fps_forward", &"dot_fps_sprint"], "avatar_crouch": [&"dot_fps_crouch"], "avatar_jump": [&"dot_fps_jump"]}
## Seconds recorded per clip; an avatar clip records AVATAR_SECONDS.
const CLIP_SECONDS := {"idle": 1.0, "draw": 1.2, "fire": 1.5, "reload": 3.0, "ads": 1.5, "sprint": 1.5}
const AVATAR_SECONDS := 1.6
## Failure limits, metres and degrees. A step limit is per frame at 30 fps and scales with the run's fps.
const POP_M := 0.04
const POP_DEG := 25.0
## A shot's kick is one impulse at any fps.
const KICK_M := 0.09
## Frames (at 30 fps; scaled) a hand may sit off its grip, or the view model be missing, before the clip fails.
const OFF_GRIP_FRAMES := 2
const MISSING_FRAMES := 3
## Clips whose hands legitimately leave the grip (a magazine change, the draw's reach).
const HANDS_FREE: PackedStringArray = ["draw", "reload"]

var _client: PlaygroundClient = null
var _fps := 60
var _out := "screenshots/anim_review"
var _only: PackedStringArray = []
var _anims: PackedStringArray = []
var _avatar := true
var _tp_view: SubViewport = null
var _tp_cam: Camera3D = null
var _op_view: SubViewport = null
var _op_cam: Camera3D = null
var _home := Vector3.ZERO
var _home_yaw := 0.0
var _failed := 0


func _ready() -> void:
	if not _parse_args(OS.get_cmdline_user_args()):
		get_tree().quit(2)
		return
	PlaygroundPresentation.use_scratch_settings("anim_review")
	_client = PlaygroundClient.new()
	_client.name = "Client"
	var config := PlaygroundConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


## `--key=value` only: the game's map drop intake (DotMapDropIntake) takes any bare argument naming a
## folder that exists, such as the output folder, as a map dropped on the window.
func _parse_args(args: PackedStringArray) -> bool:
	for arg: String in args:
		var key := arg.get_slice("=", 0)
		var value := arg.substr(key.length() + 1)
		match key:
			"--out":
				_out = value
			"--fps":
				_fps = value.to_int()
			"--only":
				_only = value.split(",", false)
			"--anims":
				_anims = value.split(",", false)
			"--no-avatar":
				_avatar = false
			_:
				push_error("anim_review: unknown argument %s" % arg)
				return false
	if _fps < 15:
		push_error("anim_review: --fps must be at least 15, not %d" % _fps)
		return false
	return true


## The weapons to review: --only's ids, every one with a model for `all`, or the first of each pose.
func _weapons() -> Array[ZeeWeaponArt]:
	var picked: Array[ZeeWeaponArt] = []
	var poses: Dictionary = {}
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if not art.has_model():
			continue
		if _only.is_empty():
			if not poses.has(art.pose):
				poses[art.pose] = true
				picked.append(art)
		elif _only.has("all") or _only.has(String(art.id)):
			picked.append(art)
	return picked


func _wants(clip: String) -> bool:
	return _anims.is_empty() or _anims.has(clip)


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	_client.mouse_capture_override = true
	_tp_view = _outside_view()
	_tp_cam = _tp_view.get_child(0) as Camera3D
	_op_view = _outside_view()
	_op_cam = _op_view.get_child(0) as Camera3D
	_home = _client.player.controller.state.position
	_home_yaw = float(_client.player.controller.state.yaw)
	var weapons := _weapons()
	if weapons.is_empty():
		push_error("anim_review: no weapon matches --only %s" % ",".join(_only))
		get_tree().quit(2)
		return
	for n in weapons.size():
		var art := weapons[n]
		var other := weapons[(n + 1) % weapons.size()]
		for clip in WEAPON_CLIPS:
			if _wants(clip):
				await _clip(art, clip, other)
	if _avatar:
		for clip: String in AVATAR_ANIMS:
			if _wants(clip):
				await _clip(weapons[0], clip, null)
	print("ANIMREVIEW_DONE %d failed" % _failed)
	get_tree().quit(0)


func _tool(art: ZeeWeaponArt) -> StringName:
	return StringName("zee_%s" % art.id)


## Puts the player back where it started, the weapon in hand and settled, and every input let go.
func _reset(art: ZeeWeaponArt) -> void:
	for clip: String in AVATAR_ANIMS:
		for action: StringName in AVATAR_ANIMS[clip]:
			Input.action_release(action)
	_client._primary_up()
	_client._set_reload(false)
	_client._aiming = false
	_client.player.teleport(_home, _home_yaw)
	_client._set_tool(_tool(art))
	await get_tree().create_timer(1.0).timeout


func _clip(art: ZeeWeaponArt, clip: String, other: ZeeWeaponArt) -> void:
	await _reset(art)
	var seconds := float(CLIP_SECONDS.get(clip, AVATAR_SECONDS))
	var frames := int(round(seconds * _fps))
	# What happens on which recorded frame; anything before frame 0 is done here.
	var at: Dictionary = {}
	match clip:
		"draw":
			if other != null and other.id != art.id:
				_client._set_tool(_tool(other))
				await get_tree().create_timer(1.0).timeout
			at[0] = func() -> void: _client._set_tool(_tool(art))
		"fire":
			at[0] = func() -> void: _client._primary_down()
			at[int(0.8 * _fps)] = func() -> void: _client._primary_up()
		"reload":
			# Spend a few rounds first: a full magazine does not reload.
			_client._primary_down()
			await get_tree().create_timer(0.4).timeout
			_client._primary_up()
			await get_tree().create_timer(0.6).timeout
			at[0] = func() -> void: _client._set_reload(true)
			at[2] = func() -> void: _client._set_reload(false)
		"ads":
			at[0] = func() -> void: _client._aiming = true
			at[int(1.0 * _fps)] = func() -> void: _client._aiming = false
		"sprint":
			at[0] = func() -> void:
				Input.action_press(&"dot_fps_forward")
				Input.action_press(&"dot_fps_sprint")
		_:
			if AVATAR_ANIMS.has(clip):
				var actions: Array = AVATAR_ANIMS[clip]
				at[0] = func() -> void:
					for action: StringName in actions:
						Input.action_press(action)
				if clip == "avatar_jump":
					at[3] = func() -> void: Input.action_release(&"dot_fps_jump")
	var dir := "%s/%s/_frames/fp_%s" % [_out, art.id, clip]
	var _made := DirAccess.make_dir_recursive_absolute(dir)
	# The outside views draw one frame behind their first staging: one staged draw before frame 0 is saved.
	await RenderingServer.frame_pre_draw
	_stage_views()
	await RenderingServer.frame_post_draw
	var samples: Array[Dictionary] = []
	var body := DotClipMetrics.new()
	for i in frames:
		if at.has(i):
			(at[i] as Callable).call()
		await RenderingServer.frame_pre_draw
		_stage_views()
		samples.append(_sample(float(i) / float(_fps), body))
		await RenderingServer.frame_post_draw
		var _f := get_viewport().get_texture().get_image().save_jpg("%s/f_%03d.jpg" % [dir, i], 0.9)
		var _t := _tp_view.get_texture().get_image().save_jpg("%s/t_%03d.jpg" % [dir, i], 0.9)
		var _o := _op_view.get_texture().get_image().save_jpg("%s/o_%03d.jpg" % [dir, i], 0.9)
	_report(art, clip, samples, body)


## A 480x540 view of the shared world that sees your body and the world gun but not the first-person arms or weapon.
func _outside_view() -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(480, 540)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.world_3d = get_viewport().world_3d
	add_child(view)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.cull_mask = 0xFFFFF & ~ARMS_LAYER
	var fp := get_viewport().get_camera_3d()
	if fp != null:
		cam.environment = fp.environment
	view.add_child(cam)
	return view


## Shows your own body (and the gun in its hand) to the outside cameras only, and places them. Run after every _process,
## since the client puts the first-person body and gun back each frame.
func _stage_views() -> void:
	var me := _client.player
	var fp := get_viewport().get_camera_3d()
	if fp != null:
		fp.cull_mask = 0xFFFFF & ~BODY_LAYER
	for node: Variant in [_client.view_arms, _client.zee_view, _client.get("toy_view")]:
		if node is Node and is_instance_valid(node):
			_tag(node as Node, ARMS_LAYER)
	if me.character != null:
		if not me.character.is_body_visible():
			me.character.set_shown(true)
		if me.zee_world == null and _client.playground != null:
			PlaygroundZee.show_held(me, _client.playground.weapon_def(_client.tool))
		_tag(me.character, BODY_LAYER)
		if me.zee_world != null and is_instance_valid(me.zee_world):
			for mesh in me.zee_world.find_children("*", "GeometryInstance3D", true, false):
				(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var feet: Vector3 = me.controller.state.position
	var turn := Basis(Vector3.UP, deg_to_rad(float(me.controller.state.yaw)))
	_tp_cam.global_position = feet + turn * BEHIND_AT
	_tp_cam.look_at(feet + Vector3(0.0, 1.1, 0.0))
	_op_cam.global_position = feet + turn * OPPONENT_AT
	_op_cam.look_at(feet + Vector3(0.0, 1.3, 0.0))


func _tag(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for child in node.get_children():
		_tag(child, layer)


## One frame's numbers: the hands against the grip, and the view model's place in camera space.
func _sample(time: float, body: DotClipMetrics) -> Dictionary:
	var out := {"t": snappedf(time, 0.001)}
	var arms := _client.view_arms as DotPlayerViewArms
	if arms != null and _client.held_grip != null:
		out["hand"] = snappedf(arms.hand_error(_client.held_grip), 0.001)
	var hands := _client.zee_view as ZeeViewModel
	var cam := get_viewport().get_camera_3d()
	if hands != null and cam != null and hands.weapon_node() != null:
		var local := cam.global_transform.affine_inverse() * hands.weapon_node().global_transform
		out["pos"] = local.origin
		out["rot"] = local.basis.get_euler()
	var character := _client.player.character
	var figure: DotHumanoidFigure = character.call(&"_figure") if character != null else null
	if figure != null and figure.skeleton() != null:
		var state := _client.player.controller.state
		body.add(body.pose_sample(time, figure.skeleton(), state.position, state.is_grounded()))
	return out


func _hand_limit(art: ZeeWeaponArt) -> float:
	if art.pose in PlaygroundViewGrip.ONE_HAND:
		return 0.05
	return 0.13 if art.pose == &"heavy" else 0.10


func _report(art: ZeeWeaponArt, clip: String, samples: Array[Dictionary], body: DotClipMetrics) -> void:
	var why: PackedStringArray = []
	var step_scale := 30.0 / float(_fps)
	var pop_m := 0.0
	var pop_deg := 0.0
	var hand_max := 0.0
	var off_run := 0
	var off_worst := 0
	var missing := 0
	for i in samples.size():
		var s := samples[i]
		if not s.has("pos"):
			missing += 1
		if s.has("hand"):
			var err := float(s["hand"])
			hand_max = maxf(hand_max, err)
			off_run = off_run + 1 if err < 0.0 or err > _hand_limit(art) else 0
			off_worst = maxi(off_worst, off_run)
		if i > 0 and s.has("pos") and samples[i - 1].has("pos"):
			var moved: Vector3 = s["pos"] - samples[i - 1]["pos"]
			pop_m = maxf(pop_m, moved.length())
			var turned: Vector3 = (s["rot"] - samples[i - 1]["rot"]).abs()
			pop_deg = maxf(pop_deg, rad_to_deg(maxf(turned.x, maxf(turned.y, turned.z))))
	var pop_limit := KICK_M if clip == "fire" else POP_M * step_scale
	if pop_m > pop_limit:
		why.append("view model pop %.3f m > %.3f" % [pop_m, pop_limit])
	if pop_deg > POP_DEG * step_scale and clip != "fire":
		why.append("view model turn %.1f deg > %.1f" % [pop_deg, POP_DEG * step_scale])
	var off_limit := int(ceil(OFF_GRIP_FRAMES / step_scale))
	if not HANDS_FREE.has(clip) and off_worst > off_limit:
		why.append("hand off grip %d frames (worst %.3f m > %.3f)" % [off_worst, hand_max, _hand_limit(art)])
	if clip != "draw" and missing > int(ceil(MISSING_FRAMES / step_scale)):
		why.append("no view model for %d frames" % missing)
	for row: Dictionary in body.evaluate({}):
		if row.get("check", "") == "bone_pop" and not bool(row.get("pass", true)):
			why.append("tp body pop %s > %s deg" % [row["value"], row["limit"]])
	var verdict := "PASS" if why.is_empty() else "FAIL"
	_failed += 0 if why.is_empty() else 1
	print("ANIMREVIEW %s" % JSON.stringify({"weapon": String(art.id), "pose": String(art.pose), "clip": clip,
		"verdict": verdict, "why": "; ".join(why), "frames": samples.size(), "fps": _fps,
		"hand_max_m": snappedf(hand_max, 0.001), "pop_m": snappedf(pop_m, 0.001), "pop_deg": snappedf(pop_deg, 0.1)}))
