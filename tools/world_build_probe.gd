extends SceneTree

## Times the drawn-world build of one map document (default pgc_fork) on a drawing display: per-step marks and the
## frame gaps while it builds. Needs a display (xvfb-run / gpu.sh run), never --headless:
##   godot --path . --script res://tools/world_build_probe.gd -- [--map=pgc_fork] [--slice=40]
## Prints a "world_build mark:" line per step and "world_build: total_ms=.. frames=.. worst_ms=.. over50=.. over100=..".
const PlaylotData := preload("../maps/pg_data.gd")

var _t0 := 0
var _last := 0
var _gaps: Array = []
var _building := false
var _keep := false


func _initialize() -> void:
	var map := "pgc_fork"
	var slice := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map = a.substr(6)
		elif a.begins_with("--slice="):
			slice = int(a.substr(8))
		elif a == "--keep-meshes":
			_keep = true
	var data: Node3D = PlaylotData.new()
	data.draw_world = false
	data.world_slice_ms = slice
	root.add_child(data)
	var path := "res://maps/custom/%s.json" % map
	if not FileAccess.file_exists(path):
		printerr("world_build: no document for ", map)
		quit(2)
		return
	data.configure_doc(path)
	data.draw_world = true
	data.free_box_meshes = not _keep
	data.world_mark = func(label: String) -> void:
		print("world_build mark: %s at %d ms" % [label, Time.get_ticks_msec() - _t0])
	_run.call_deferred(data)


func _run(data: Node3D) -> void:
	await process_frame
	_t0 = Time.get_ticks_msec()
	_last = _t0
	_building = true
	var got: DotResult = await data.load_world()
	_building = false
	var total := Time.get_ticks_msec() - _t0
	var worst := 0
	var o50 := 0
	var o100 := 0
	for g: int in _gaps:
		worst = maxi(worst, g)
		o50 += 1 if g > 50 else 0
		o100 += 1 if g > 100 else 0
	print("world_build: ok=%s drawn=%s total_ms=%d frames=%d worst_ms=%d over50=%d over100=%d" % [got.ok, data.drawn_world != null, total, _gaps.size(), worst, o50, o100])
	var c0 := Time.get_ticks_usec()
	var items := DotRenderWarmup.collect(data)
	print("world_build collect: ms=%.1f items=%s" % [(Time.get_ticks_usec() - c0) / 1000.0, str(items.size()) if items is Array else str(items)])
	quit(0)


func _process(_d: float) -> bool:
	if _building:
		var now := Time.get_ticks_msec()
		_gaps.append(now - _last)
		_last = now
	return false
