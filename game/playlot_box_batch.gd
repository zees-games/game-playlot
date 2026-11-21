extends RefCounted

const PlaylotMaterials := preload("playlot_materials.gd")

## Draws a map's plain opaque boxes as a few meshes instead of one per box.
##
## The web renderer is draw-call bound, and a box map is hundreds of `MeshInstance3D`s that
## share a handful of per-colour materials. This folds the boxes of one material that lie in
## one [constant CELL]-metre cell into one [ArrayMesh], so the draws fall to materials x cells
## and a far cell is still culled whole. The boxes keep their bodies, shapes and (hidden)
## meshes, so collision, panes and the map survey read what they always did.

const GROUP := &"pg_batched"
## Metres a cell covers on x and z.
const CELL := 64.0
const NODE_NAME := "BoxBatch"


## Batches [param parent]'s `pg_box` bodies. Returns `{boxes, nodes}`: how many boxes were
## folded and how many meshes now draw them. Brushes, see-through boxes and breakable
## materials stay as they are.
static func build(parent: Node3D, cell: float = CELL) -> Dictionary:
	var groups := {}
	for child in parent.get_children():
		if not (child is StaticBody3D and child.has_meta(&"pg_box")) or child.has_meta(&"pg_batched_in"):
			continue
		var mesh := _plain_box_mesh(child)
		if mesh == null:
			continue
		var material := mesh.material_override as StandardMaterial3D
		if material == null or material.albedo_color.a < 0.999:
			continue
		var matter := PlaylotMaterials.material_of(child)
		if matter != &"":
			var surface := PlaylotMaterials.surface(String(matter))
			if surface != null and surface.break_health > 0.0:
				continue
		var at: Vector3 = (child as Node3D).position
		var key := [material, int(floorf(at.x / cell)), int(floorf(at.z / cell))]
		if not groups.has(key):
			groups[key] = {"material": material, "items": []}
		groups[key]["items"].append([child, mesh])
	var holder := Node3D.new()
	holder.name = NODE_NAME
	holder.add_to_group(GROUP)
	var boxes := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var items: Array = g["items"]
		if items.size() < 2:
			continue
		var node := _merge(items, g["material"])
		holder.add_child(node)
		for it in items:
			(it[1] as MeshInstance3D).visible = false
			(it[0] as Node).set_meta(&"pg_batched_in", true)
		boxes += items.size()
	if holder.get_child_count() == 0:
		holder.free()
		return {"boxes": 0, "nodes": 0}
	parent.add_child(holder)
	return {"boxes": boxes, "nodes": holder.get_child_count()}


static func _plain_box_mesh(body: Node) -> MeshInstance3D:
	var found: MeshInstance3D = null
	for part in body.get_children():
		if part is MeshInstance3D and (part as MeshInstance3D).mesh is BoxMesh:
			if found != null:
				return null
			found = part
		elif not (part is CollisionShape3D):
			return null
	return found


static func _merge(items: Array, material: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for it in items:
		var body: Node3D = it[0]
		var arrays: Array = ((it[1] as MeshInstance3D).mesh as BoxMesh).get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var t := body.transform
		var base := verts.size()
		for i in v.size():
			verts.append(t * v[i])
			normals.append((t.basis * n[i]).normalized())
		uvs.append_array(uv)
		for i in idx:
			indices.append(base + i)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node
