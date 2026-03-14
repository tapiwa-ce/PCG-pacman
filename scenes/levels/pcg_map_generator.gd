extends Node2D
class_name PCGMapGenerator

@export var source_id: int = 0
@export var wall_atlas_coords: Vector2i = Vector2i(1, 4)

# Floor tile used to stamp walkable space after generating walls
@export var floor_source_id: int = 0
@export var floor_atlas_coords: Vector2i = Vector2i(0, 2)

# Orange grid spacing (2 means every 2 tiles becomes a node)
@export var node_spacing: int = 2

# Wall bar length in tiles when placing blockers
@export var max_segment_len_tiles: int = 3

@export var rng_seed: int = 0
@export var auto_generate_on_ready: bool = true

# Density controls
@export var placement_attempts: int = 130
@export var placement_chance: float = 0.65

# Bias walls away from the ghost house (assumed near center)
@export var ghost_avoid_radius: float = 6.0
@export var ghost_avoid_strength: float = 0.6

# Keep N interior columns clear next to the left boundary when generating TL
@export var left_border_keep_clear_tiles: int = 1

# You asked for these lanes to always be open (replace walls with floor)
@export var force_clear_lane_left_x: int = 3
@export var force_clear_lane_right_x: int = 36
@export var force_clear_lane_y_min: int = 2
@export var force_clear_lane_y_max: int = 20


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tm: TileMapLayer

# Protected cells are walls you already placed manually (boundary and ghost house)
var _protected: Dictionary = {}

# Walls we generate only in the top left before mirroring
var _walls_tl: Dictionary = {}

var _bounds: Rect2i
var _left_x: int
var _right_x: int
var _top_y: int
var _bottom_y: int
var _width: int
var _height: int

# Real boundary extents detected from protected walls
var _border_left_x: int
var _border_right_x: int

# Interior area (inside boundary walls)
var _interior: Rect2i
var _center: Vector2

# Mirror exclusions (odd width = 1 line, even width = 2 lines)
var _mirror_cols: Array[int] = []
var _mirror_rows: Array[int] = []

# Region we generate/check in (top left quarter including mirror region)
var _tl_check_rect: Rect2i
var _baseline_components_tl: int = 1


func _ready() -> void:
	if auto_generate_on_ready:
		generate()


func generate() -> void:
	_tm = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if _tm == null:
		printerr("PCGMapGenerator: TileMapLayer not found.")
		return

	_rng.seed = Time.get_ticks_msec() if rng_seed == 0 else rng_seed

	_bounds = _tm.get_used_rect()
	if _bounds.size == Vector2i.ZERO:
		printerr("PCGMapGenerator: TileMapLayer has no used cells.")
		return

	_left_x = _bounds.position.x
	_right_x = _bounds.position.x + _bounds.size.x - 1
	_top_y = _bounds.position.y
	_bottom_y = _bounds.position.y + _bounds.size.y - 1

	_width = _right_x - _left_x + 1
	_height = _bottom_y - _top_y + 1

	_build_mirror_lines()

	# Clear everything that isn't a wall tile so we keep boundary + ghost house only
	_clear_non_wall_tiles(_bounds)
	_snapshot_protected(_bounds)

	# Boundary extents should come from the protected walls, not from used_rect
	_detect_boundary_extents_from_protected()

	_interior = Rect2i(
		Vector2i(_border_left_x + 1, _top_y + 1),
		Vector2i(
			max(1, (_border_right_x - _border_left_x + 1) - 2),
			max(1, (_bottom_y - _top_y + 1) - 2)
		)
	)

	_center = Vector2(_interior.position) + Vector2(_interior.size) * 0.5

	# Top left region up to the center of the map (used for generation + connectivity checking)
	var tl_max_x: int = (_left_x + _right_x) / 2
	var tl_max_y: int = (_top_y + _bottom_y) / 2
	_tl_check_rect = Rect2i(
		Vector2i(_border_left_x + 1, _top_y + 1),
		Vector2i(
			max(1, tl_max_x - (_border_left_x + 1) + 1),
			max(1, tl_max_y - (_top_y + 1) + 1)
		)
	)

	# This makes sure we don't generate walls that connect to the left boundary
	_clear_left_interior_strip_in_tl()

	_walls_tl.clear()

	# This baseline is used to reject placements that split TL into more components
	_baseline_components_tl = _count_floor_components_in_rect(_tl_check_rect, _protected, _walls_tl)

	var nodes: Array[Vector2i] = _build_nodes_in_rect(_tl_check_rect, node_spacing)
	if nodes.size() < 2:
		printerr("PCGMapGenerator: Not enough nodes in TL region. Try node_spacing=1.")
		return

	var node_set: Dictionary = {}
	for n: Vector2i in nodes:
		node_set[n] = true

	var parents: Dictionary = _dfs_spanning_tree(nodes, node_set, node_spacing)
	var edges: Array = _parents_to_edges(parents)
	edges.shuffle()

	var tries: int = 0
	while tries < placement_attempts and edges.size() > 0:
		if _rng.randf() < placement_chance:
			var e: Array = edges[_rng.randi_range(0, edges.size() - 1)] as Array
			var a: Vector2i = e[0] as Vector2i
			var b: Vector2i = e[1] as Vector2i
			_try_place_blocker_tl(a, b)
		tries += 1

	# Apply the generated TL walls and mirror to the other quarters
	_stamp_mirrored_from_tl()

	# Fill all non-wall interior with real floor tiles so AI and collisions remain stable
	_fill_interior_with_floor()

	# Force the two vertical lanes you requested to always be open
	_force_clear_vertical_lanes()

	# Make sure runtime tile data updates if your TileSet relies on it
	_tm.notify_runtime_tile_data_update()

	# Rebuild walkables and then spawn pellets using the updated walkables list
	_refresh_walkables_from_walls()
	call_deferred("_spawn_pellets_on_walkables")


func _build_mirror_lines() -> void:
	_mirror_cols.clear()
	_mirror_rows.clear()

	if (_width % 2) == 1:
		_mirror_cols.append(_left_x + (_width / 2))
	else:
		_mirror_cols.append(_left_x + (_width / 2) - 1)
		_mirror_cols.append(_left_x + (_width / 2))

	if (_height % 2) == 1:
		_mirror_rows.append(_top_y + (_height / 2))
	else:
		_mirror_rows.append(_top_y + (_height / 2) - 1)
		_mirror_rows.append(_top_y + (_height / 2))


func _refresh_walkables_from_walls() -> void:
	var ai: Node = get_tree().get_root().get_node_or_null("Level/SharedEnemyAI")
	if ai != null and ai.has_method("rebuild_walkables_from_walls"):
		ai.set("wall_atlas_coords", wall_atlas_coords)
		ai.call("rebuild_walkables_from_walls")


func _spawn_pellets_on_walkables() -> void:
	var root := get_tree().get_root()

	var ai: Node = root.get_node_or_null("Level/SharedEnemyAI")
	if ai == null or not ai.has_method("get_walkables"):
		return

	var pellets: Node = root.get_node_or_null("Level/Pickables/Pellets")
	if pellets == null or not pellets.has_method("spawn_from_walkables"):
		return

	var walkables: PackedVector2Array = ai.call("get_walkables") as PackedVector2Array
	if walkables.is_empty():
		return

	pellets.call("spawn_from_walkables", walkables, _tm)


func _fill_interior_with_floor() -> void:
	# We stamp floor everywhere in the interior that is not a wall.
	# This avoids "empty map" issues where enemies rely on TileData / collisions.
	for y in range(_interior.position.y, _interior.position.y + _interior.size.y):
		for x in range(_interior.position.x, _interior.position.x + _interior.size.x):
			var p: Vector2i = Vector2i(x, y)

			# Never overwrite boundary/ghost house walls
			if _protected.has(p):
				continue

			# Keep wall tiles as walls
			if _tm.get_cell_source_id(p) != -1 and _tm.get_cell_atlas_coords(p) == wall_atlas_coords:
				continue

			_tm.set_cell(p, floor_source_id, floor_atlas_coords)


func _force_clear_vertical_lanes() -> void:
	# You wanted these columns to always be walkable.
	# If there's a wall there, we replace it with floor.
	_force_clear_column(force_clear_lane_left_x, force_clear_lane_y_min, force_clear_lane_y_max)
	_force_clear_column(force_clear_lane_right_x, force_clear_lane_y_min, force_clear_lane_y_max)


func _force_clear_column(x: int, y_min: int, y_max: int) -> void:
	for y in range(y_min, y_max + 1):
		var p: Vector2i = Vector2i(x, y)

		# Don't touch protected walls (in case your boundary overlaps this request)
		if _protected.has(p):
			continue

		# Replace walls with floor, also stamp floor if empty
		if _tm.get_cell_source_id(p) == -1:
			_tm.set_cell(p, floor_source_id, floor_atlas_coords)
		else:
			if _tm.get_cell_atlas_coords(p) == wall_atlas_coords:
				_tm.set_cell(p, floor_source_id, floor_atlas_coords)


func _clear_left_interior_strip_in_tl() -> void:
	# Clears the strip inside the left boundary, only within the TL region
	var x_start: int = _border_left_x + 1
	var x_end: int = _border_left_x + left_border_keep_clear_tiles

	for y in range(_tl_check_rect.position.y, _tl_check_rect.position.y + _tl_check_rect.size.y):
		for x in range(x_start, x_end + 1):
			var p: Vector2i = Vector2i(x, y)
			if _protected.has(p):
				continue
			if _tm.get_cell_source_id(p) != -1 and _tm.get_cell_atlas_coords(p) == wall_atlas_coords:
				_tm.erase_cell(p)


func _detect_boundary_extents_from_protected() -> void:
	_border_left_x = _left_x
	_border_right_x = _right_x
	if _protected.is_empty():
		return

	var min_x: int = 2147483647
	var max_x: int = -2147483648
	for k in _protected.keys():
		var p: Vector2i = k as Vector2i
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)

	_border_left_x = min_x
	_border_right_x = max_x


func _is_on_mirror(p: Vector2i) -> bool:
	return _mirror_cols.has(p.x) or _mirror_rows.has(p.y)


func _ghost_bias_allows(mid: Vector2i) -> bool:
	var d: float = _center.distance_to(Vector2(mid))
	if d >= ghost_avoid_radius:
		return true
	var t: float = clamp(1.0 - (d / ghost_avoid_radius), 0.0, 1.0)
	var keep_prob: float = lerp(1.0, 1.0 - ghost_avoid_strength, t)
	return _rng.randf() < keep_prob


func _try_place_blocker_tl(a: Vector2i, b: Vector2i) -> void:
	var dir := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	if dir == Vector2i.ZERO:
		return

	var mid := a + (b - a) / 2

	# Reject walls too close to the ghost house area
	if not _ghost_bias_allows(mid):
		return

	var perp := Vector2i(-dir.y, dir.x)
	if perp == Vector2i.ZERO:
		return

	var length := _rng.randi_range(1, max_segment_len_tiles)

	var bar: Array[Vector2i] = []
	var half := length / 2
	for i in range(-half, length - half):
		bar.append(mid + perp * i)

	var added: Array[Vector2i] = []
	for c: Vector2i in bar:
		if not _point_in_rect(c, _tl_check_rect):
			continue
		if _is_on_mirror(c):
			continue
		if c.x <= (_border_left_x + left_border_keep_clear_tiles):
			continue
		if _protected.has(c):
			continue

		if not _walls_tl.has(c):
			_walls_tl[c] = true
			added.append(c)

	# If this placement splits the TL region into more components, undo it
	if _count_floor_components_in_rect(_tl_check_rect, _protected, _walls_tl) > _baseline_components_tl:
		for c2: Vector2i in added:
			_walls_tl.erase(c2)


func _stamp_mirrored_from_tl() -> void:
	var all: Dictionary = {}

	for c_v in _walls_tl.keys():
		var c: Vector2i = c_v as Vector2i
		for p in [c, _mirror_v(c), _mirror_h(c), _mirror_h(_mirror_v(c))]:
			if _is_on_mirror(p):
				continue
			if _protected.has(p):
				continue
			if not _point_in_rect(p, _interior):
				continue
			all[p] = true

	for p_v in all.keys():
		var p: Vector2i = p_v as Vector2i
		_tm.set_cell(p, source_id, wall_atlas_coords)


func _mirror_v(c: Vector2i) -> Vector2i:
	return Vector2i(_left_x + _right_x - c.x, c.y)

func _mirror_h(c: Vector2i) -> Vector2i:
	return Vector2i(c.x, _top_y + _bottom_y - c.y)


func _clear_non_wall_tiles(bounds: Rect2i) -> void:
	# Removes anything that isn't a wall tile, so we only keep boundary and ghost house
	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var p: Vector2i = Vector2i(x, y)
			if _tm.get_cell_source_id(p) == -1:
				continue
			if _tm.get_cell_atlas_coords(p) != wall_atlas_coords:
				_tm.erase_cell(p)


func _snapshot_protected(bounds: Rect2i) -> void:
	_protected.clear()
	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var p: Vector2i = Vector2i(x, y)
			if _tm.get_cell_source_id(p) == -1:
				continue
			if _tm.get_cell_atlas_coords(p) == wall_atlas_coords:
				_protected[p] = true


func _build_nodes_in_rect(r: Rect2i, step: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var y: int = r.position.y
	while y <= r.position.y + r.size.y - 1:
		var x: int = r.position.x
		while x <= r.position.x + r.size.x - 1:
			out.append(Vector2i(x, y))
			x += step
		y += step
	return out


func _dfs_spanning_tree(nodes: Array[Vector2i], node_set: Dictionary, step: int) -> Dictionary:
	nodes.sort_custom(Callable(self, "_node_sort"))

	var start: Vector2i = nodes[0]
	var stack: Array[Vector2i] = [start]
	var visited: Dictionary = { start: true }
	var parent: Dictionary = {}

	while not stack.is_empty():
		var current: Vector2i = stack.back()

		var neighbors: Array[Vector2i] = []
		var dirs: Array[Vector2i] = [
			Vector2i(step, 0), Vector2i(-step, 0),
			Vector2i(0, step), Vector2i(0, -step)
		]

		for d: Vector2i in dirs:
			var nb: Vector2i = current + d
			if node_set.has(nb) and not visited.has(nb):
				neighbors.append(nb)

		if neighbors.is_empty():
			stack.pop_back()
			continue

		var next: Vector2i = neighbors[_rng.randi_range(0, neighbors.size() - 1)]
		visited[next] = true
		parent[next] = current
		stack.append(next)

	return parent


func _parents_to_edges(parent: Dictionary) -> Array:
	var edges: Array = []
	for child_v in parent.keys():
		var child: Vector2i = child_v as Vector2i
		var p: Vector2i = parent[child] as Vector2i
		edges.append([p, child])
	return edges


func _count_floor_components_in_rect(r: Rect2i, protected: Dictionary, walls: Dictionary) -> int:
	var seen: Dictionary = {}
	var components: int = 0

	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var start: Vector2i = Vector2i(x, y)
			if seen.has(start):
				continue
			if protected.has(start) or walls.has(start):
				continue

			components += 1
			var q: Array[Vector2i] = [start]
			seen[start] = true

			while not q.is_empty():
				var cur: Vector2i = q.pop_front()
				for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var nb: Vector2i = cur + d
					if seen.has(nb):
						continue
					if not _point_in_rect(nb, r):
						continue
					if protected.has(nb) or walls.has(nb):
						continue
					seen[nb] = true
					q.append(nb)

	return components


func _point_in_rect(p: Vector2i, r: Rect2i) -> bool:
	return p.x >= r.position.x and p.x < r.position.x + r.size.x \
		and p.y >= r.position.y and p.y < r.position.y + r.size.y


func _node_sort(a: Vector2i, b: Vector2i) -> bool:
	return (a.y < b.y) or (a.y == b.y and a.x < b.x)


func signi(v: int) -> int:
	if v > 0:
		return 1
	elif v < 0:
		return -1
	return 0
