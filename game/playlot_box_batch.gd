extends RefCounted

const PlaylotMaterials := preload("playlot_materials.gd")

## Playlot's rules for [DotMapBoxBatch]: which of a map's boxes may be folded into the shared
## per-material, per-cell meshes. The folding itself is the addon's.
##
## Only `pg_box` bodies fold, and a box of a breakable material stays a mesh of its own so it can
## break and be hidden on its own.

const GROUP := DotMapBoxBatch.GROUP
const CELL := DotMapBoxBatch.CELL
const NODE_NAME := DotMapBoxBatch.NODE_NAME
## A box alone in its 64 m cell folds with the lone boxes of its material in a 256 m cell (pgc_town 621 -> 598 draws).
const COARSE := DotMapBoxBatch.CELL * 4.0


## Batches [param parent]'s plain `pg_box` bodies; `{boxes, nodes}`. Does nothing on a headless
## server unless [param force].
static func build(parent: Node3D, cell: float = CELL, force: bool = false) -> Dictionary:
	return DotMapBoxBatch.build(parent, cell, skip, force, COARSE)


## True leaves the box as its own mesh: not a `pg_box`, or a material that can break.
static func skip(body: Node3D, _mesh: MeshInstance3D) -> bool:
	if not body.has_meta(&"pg_box"):
		return true
	var matter := PlaylotMaterials.material_of(body)
	if matter == &"":
		return false
	var surface := PlaylotMaterials.surface(String(matter))
	return surface != null and surface.break_health > 0.0
