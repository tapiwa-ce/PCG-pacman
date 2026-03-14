extends Node
class_name Pellets

@export var normal_pellet_scene: PackedScene
@export var power_pellet_scene: PackedScene

@export_range(0.0, 1.0, 0.01) var normal_density: float = 0.55

# If symmetry fails for some reason, fallback will place up to this many
@export var power_pellets_target: int = 4

# Optional rule to keep pellets away from the center/ghost area
@export var min_distance_from_ghost_house: int = 0

@export var pellets_z_index: int = 10


var initial_pellets_count: int = 0
var remaining_pellets_count: int = 0

var initial_normal_pellets_count: int = 0
var remaining_normal_pellets_count: int = 0

var initial_power_pellets_count: int = 0
var remaining_power_pellets_count: int = 0


signal pellet_picked_up(value: int)
signal normal_pellet_picked_up(value: int)
signal power_pellet_picked_up(value: int)


func _ready() -> void:
	# Pellets are spawned after the PCG map is generated
	pass


func _get_or_create_group(name: String) -> Node:
	var g: Node = get_node_or_null(name)
	if g == null:
		g = Node2D.new()
		g.name = name
		add_child(g)
	return g


func clear_existing_pellets() -> void:
	for group: Node in get_children():
		for pellet: Node in group.get_children():
			pellet.queue_free()


func spawn_from_walkables(walkables: PackedVector2Array, tile_map_layer: TileMapLayer) -> void:
	if normal_pellet_scene == null:
		printerr("[PELLETS ERROR] normal_pellet_scene is not assigned.")
		return

	if power_pellet_scene == null:
		printerr("[PELLETS ERROR] power_pellet_scene is not assigned.")
		return

	if tile_map_layer == null:
		printerr("[PELLETS ERROR] TileMapLayer is null.")
		return

	var normal_group: Node = _get_or_create_group("Normal")
	var power_group: Node = _get_or_create_group("Power")

	clear_existing_pellets()

	if walkables.is_empty():
		printerr("[PELLETS ERROR] Walkables list is empty.")
		return

	var used_rect: Rect2i = tile_map_layer.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		printerr("[PELLETS ERROR] TileMapLayer used_rect is empty.")
		return

	var left_x: int = used_rect.position.x
	var right_x: int = used_rect.position.x + used_rect.size.x - 1
	var top_y: int = used_rect.position.y
	var bottom_y: int = used_rect.position.y + used_rect.size.y - 1

	var width: int = right_x - left_x + 1
	var height: int = bottom_y - top_y + 1

	var center: Vector2 = Vector2(used_rect.position) + Vector2(used_rect.size) * 0.5

	# Candidates are taken from walkables so pellets only land on paths
	var candidates: Array[Vector2i] = []
	for v in walkables:
		var cell: Vector2i = Vector2i(int(v.x), int(v.y))

		if min_distance_from_ghost_house > 0:
			if Vector2(cell).distance_to(center) < float(min_distance_from_ghost_house):
				continue

		candidates.append(cell)

	if candidates.is_empty():
		printerr("[PELLETS ERROR] No valid pellet spawn candidates.")
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	candidates.shuffle()

	var candidate_set: Dictionary = {}
	for c: Vector2i in candidates:
		candidate_set[c] = true

	# Mirror lines are computed from used_rect so power pellets can be mirrored safely
	var mirror_cols: Array[int] = []
	var mirror_rows: Array[int] = []

	if width % 2 == 1:
		mirror_cols.append(left_x + width / 2)
	else:
		mirror_cols.append(left_x + width / 2 - 1)
		mirror_cols.append(left_x + width / 2)

	if height % 2 == 1:
		mirror_rows.append(top_y + height / 2)
	else:
		mirror_rows.append(top_y + height / 2 - 1)
		mirror_rows.append(top_y + height / 2)

	mirror_cols.sort()
	mirror_rows.sort()

	# TL quarter limits inside the boundary and not on the mirror lines
	var tl_min_x: int = left_x + 1
	var tl_max_x: int = mirror_cols[0] - 1
	var tl_min_y: int = top_y + 1
	var tl_max_y: int = mirror_rows[0] - 1

	# Power pellets are placed as 1 in TL then mirrored to 4
	initial_power_pellets_count = 0
	var placed_power_cells: Array[Vector2i] = []
	var ok: bool = false

	for attempt in range(300):
		var pick: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]

		if pick.x < tl_min_x or pick.x > tl_max_x:
			continue
		if pick.y < tl_min_y or pick.y > tl_max_y:
			continue
		if mirror_cols.has(pick.x) or mirror_rows.has(pick.y):
			continue

		var mirrors: Array[Vector2i] = _make_4way_mirrors(pick, left_x, right_x, top_y, bottom_y)

		var all_valid: bool = true
		for m: Vector2i in mirrors:
			if mirror_cols.has(m.x) or mirror_rows.has(m.y):
				all_valid = false
				break
			if not candidate_set.has(m):
				all_valid = false
				break

		if not all_valid:
			continue

		placed_power_cells = mirrors
		ok = true
		break

	if ok:
		for cell_p: Vector2i in placed_power_cells:
			_spawn_one(power_group, power_pellet_scene, cell_p, tile_map_layer, true)
			initial_power_pellets_count += 1
	else:
		# Fallback if symmetry cannot be satisfied, just place up to target anywhere
		var power_target: int = max(0, power_pellets_target)
		var fallback_count: int = 0
		for i in range(candidates.size()):
			if fallback_count >= power_target:
				break
			_spawn_one(power_group, power_pellet_scene, candidates[i], tile_map_layer, true)
			initial_power_pellets_count += 1
			fallback_count += 1

	# Normal pellets use density and avoid landing on the power pellet cells
	initial_normal_pellets_count = 0
	var skip_cells: Dictionary = {}
	for c2: Vector2i in placed_power_cells:
		skip_cells[c2] = true

	for i in range(candidates.size()):
		var cell_n: Vector2i = candidates[i]

		if skip_cells.has(cell_n):
			continue

		if rng.randf() > normal_density:
			continue

		_spawn_one(normal_group, normal_pellet_scene, cell_n, tile_map_layer, false)
		initial_normal_pellets_count += 1

	initial_pellets_count = initial_normal_pellets_count + initial_power_pellets_count
	remaining_pellets_count = initial_pellets_count
	remaining_normal_pellets_count = initial_normal_pellets_count
	remaining_power_pellets_count = initial_power_pellets_count


func _spawn_one(group: Node, scene: PackedScene, cell: Vector2i, tile_map_layer: TileMapLayer, is_power: bool) -> void:
	var pellet: Node = scene.instantiate()
	if pellet == null:
		printerr("[PELLETS ERROR] Failed to instantiate pellet.")
		return

	group.add_child(pellet)

	# Convert tile cell to world position and place pellet at the tile center
	var local_pos: Vector2 = tile_map_layer.map_to_local(cell)
	var world_pos: Vector2 = tile_map_layer.to_global(local_pos)

	if pellet is Node2D:
		(pellet as Node2D).global_position = world_pos
	elif pellet is CanvasItem:
		(pellet as CanvasItem).global_position = world_pos

	if pellet is CanvasItem:
		(pellet as CanvasItem).z_index = pellets_z_index

	# Connect the pellet's picked_up signal to this manager
	if pellet.has_signal("picked_up"):
		pellet.connect("picked_up", Callable(self, "on_pellet_picked_up"))
		if is_power:
			pellet.connect("picked_up", Callable(self, "on_power_pellet_picked_up"))
		else:
			pellet.connect("picked_up", Callable(self, "on_normal_pellet_picked_up"))

	pellet.tree_exited.connect(on_scene_tree_exited_by_pellet)


func on_scene_tree_exited_by_pellet() -> void:
	var empty_count: int = 0
	for pellet_type_node: Node in get_children():
		if pellet_type_node.get_child_count() == 0:
			empty_count += 1
	if empty_count == get_child_count():
		Global.level_cleared.emit()


func on_pellet_picked_up(score_to_add: int) -> void:
	remaining_pellets_count -= 1
	Global.increase_score(score_to_add)
	pellet_picked_up.emit(score_to_add)


func on_normal_pellet_picked_up(score_to_add: int) -> void:
	remaining_normal_pellets_count -= 1
	normal_pellet_picked_up.emit(score_to_add)


func on_power_pellet_picked_up(score_to_add: int) -> void:
	remaining_power_pellets_count -= 1
	power_pellet_picked_up.emit(score_to_add)


func _mirror_v(c: Vector2i, left_x: int, right_x: int) -> Vector2i:
	return Vector2i(left_x + right_x - c.x, c.y)


func _mirror_h(c: Vector2i, top_y: int, bottom_y: int) -> Vector2i:
	return Vector2i(c.x, top_y + bottom_y - c.y)


func _make_4way_mirrors(c: Vector2i, left_x: int, right_x: int, top_y: int, bottom_y: int) -> Array[Vector2i]:
	var v: Vector2i = _mirror_v(c, left_x, right_x)
	var h: Vector2i = _mirror_h(c, top_y, bottom_y)
	var vh: Vector2i = _mirror_h(v, top_y, bottom_y)
	return [c, v, h, vh]
