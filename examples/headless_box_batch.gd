extends DotGameCheckSuite

const PlaylotBoxBatch := preload("../game/playlot_box_batch.gd")
const PgData := preload("../maps/pg_data.gd")

## A box map is drawn as one mesh per material per cell, not one per box, and nothing a
## player collides with or breaks changes. This is the draw budget for the web renderer.
##
## [codeblock]
## godot --headless --path . res://examples/headless_box_batch.tscn
## [/codeblock]

const CHECKS := 9
const SECTIONS := 1


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _visible_meshes(root: Node) -> int:
	var n := 0
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var m := c as MeshInstance3D
		if m.is_visible_in_tree():
			n += 1
	return n


func _run() -> void:
	print("game-playlot: box batching")
	var boxes: Array = []
	for i in 40:
		boxes.append({"at": [float(i) * 2.0, 1, 0], "size": [1, 2, 1], "colour": "floor"})
	boxes.append({"at": [200, 1, 0], "size": [1, 2, 1], "colour": "floor"})
	boxes.append({"at": [0, 1, 5], "size": [1, 2, 1], "colour": "#ff0000"})
	boxes.append({"at": [2, 1, 5], "size": [1, 2, 1], "colour": "#ff000040"})
	var root := Node3D.new()
	add_child(root)
	PgData.build_into(root, {"boxes": boxes})
	var before := _visible_meshes(root)
	var got := PlaylotBoxBatch.build(root)
	var after := _visible_meshes(root)
	_check(before == 43, "43 boxes draw 43 meshes before batching (%d)" % before)
	_check(int(got["boxes"]) == 40, "the 40 opaque floor boxes of two cells fold (%s)" % [got])
	_check(after < before / 2, "the draws fall by more than half (%d -> %d)" % [before, after])
	_check(after == 5, "two floor cells, the far box, the lone red and the see-through one (%d)" % after)
	var bodies := 0
	for c in root.get_children():
		if c is StaticBody3D:
			bodies += 1
	_check(bodies == 43, "every box keeps its body (%d)" % bodies)
	var holder: Node = root.get_node(PlaylotBoxBatch.NODE_NAME)
	var merged: MeshInstance3D = holder.get_child(0)
	var box := merged.mesh.get_aabb()
	_check(box.size.x > 60.0 and box.size.x < 90.0, "a cell's mesh spans its boxes (%s)" % [box.size])
	_check(merged.mesh.surface_get_material(0) != null, "the merged mesh keeps the shared material")
	var again := PlaylotBoxBatch.build(root)
	_check(int(again["boxes"]) == 0, "a second pass folds nothing")
	var uses := _visible_meshes(root)
	_check(uses == after, "and the draws stay where they were (%d)" % uses)
	root.queue_free()
	_report_sections(1, 1, SECTIONS, CHECKS)
