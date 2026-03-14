extends EnemyAI
class_name EnemyAIAssassin

# Sound played when the assassin actually teleports
@export_file("*.wav", "*.ogg") var teleport_sound_file: String = "res://assets/audio/teleport.wav"

# === TELEPORT PCG DATA (filled by EnemyPCGFactory / PCGManager) ===
var teleport_enabled: bool = false
var teleport_cooldown: float = 8.0        # seconds between teleports
var teleport_warning_time: float = 0.5    # how long the warning flash lasts
var teleport_min_range: int = 3           # in tiles
var teleport_max_range: int = 6           # in tiles
var teleport_style: String = "RANDOM_NEAR"
var teleport_word: String = "Teleport!"

# Internal state
var _teleport_ready: bool = true          # can we start a teleport?
var _teleport_pending: bool = false       # currently in warning / executing
var teleport_timer: Timer                 # cooldown timer

# Used to restore color after warning flash
var _saved_modulate: Color = Color(1, 1, 1, 1)

# Per-teleport style weights coming from PCG
var teleport_style_weights: Dictionary = {}

const TELEPORT_WORDS := {
	"AMBUSH_BEHIND": ["Ambush!", "Behind You!", "Sneak!"],
	"RANDOM_NEAR":   ["Jackpot!", "Surprise!", "Pop!"],
	"FLANK":         ["Flank!", "Side Hit!", "Slide!"],
	"PREDICTIVE":    ["Read You!", "Got You!", "Predict!"],
}

# -------------------------------------------------------------------
# BASE BEHAVIOUR OVERRIDES
# -------------------------------------------------------------------

func __update_chase_target_position() -> void:
	# Original assassin behaviour: target a few tiles ahead of player.
	chase_target_position = chase_target.global_position + (chase_target.direction * tile_size * 4)


func set_prediction_offset(value: int) -> void:
	prediction_offset = value


func set_scatter_time(value: float) -> void:
	scatter_duration = value


# -------------------------------------------------------------------
# TELEPORT COOLDOWN CALLBACK
# -------------------------------------------------------------------

func _on_teleport_cooldown_finished() -> void:
	_teleport_ready = true


# -------------------------------------------------------------------
# APPLY PCG CONFIG (called from PCGManager)
# This is where bad values could previously give timers a 0 / negative
# wait_time and crash. Now everything is clamped to safe minimums.
# -------------------------------------------------------------------

func apply_pcg_teleport_config(cfg: Dictionary) -> void:
	teleport_enabled = cfg.get("teleport_enabled", false)

	# --- Cooldown (seconds between teleports) ---
	var cd: float
	if cfg.has("teleport_cooldown_min"):
		cd = randf_range(
			float(cfg["teleport_cooldown_min"]),
			float(cfg["teleport_cooldown_max"])
		)
	else:
		cd = float(cfg.get("teleport_cooldown", teleport_cooldown))

	# Never allow zero / negative cooldown – Timer would assert
	teleport_cooldown = max(cd, 0.1)

	# --- Warning time (how long the assassin flashes before blink) ---
	var warn: float
	if cfg.has("teleport_warning_min"):
		warn = randf_range(
			float(cfg["teleport_warning_min"]),
			float(cfg["teleport_warning_max"])
		)
	else:
		warn = float(cfg.get("teleport_warning", teleport_warning_time))

	# Also clamp this – used inside create_timer(warn)
	teleport_warning_time = max(warn, 0.05)

	# --- Ranges in tiles (with defaults if PCG didn’t send them) ---
	teleport_min_range = int(cfg.get("teleport_min_range", teleport_min_range))
	teleport_max_range = int(cfg.get("teleport_max_range", teleport_max_range))

	# Store weights so we can roll a style per teleport
	teleport_style_weights = cfg.get("teleport_style_weights", {})

	# If our cooldown timer already exists, update it
	if teleport_timer:
		teleport_timer.wait_time = teleport_cooldown


# -------------------------------------------------------------------
# READY
# -------------------------------------------------------------------

func _ready() -> void:
	# Call EnemyAI._ready() first so base logic works.
	super._ready()

	# Create a dedicated teleport cooldown timer.
	teleport_timer = Timer.new()
	teleport_timer.one_shot = true
	add_child(teleport_timer)
	teleport_timer.timeout.connect(_on_teleport_cooldown_finished)
	teleport_timer.wait_time = teleport_cooldown


# -------------------------------------------------------------------
# MAIN LOOP HOOK
# -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Let base AI handle pathfinding / normal movement.
	super._physics_process(delta)

	if teleport_enabled and not in_home:
		_check_teleport_trigger()


# -------------------------------------------------------------------
# TRIGGER LOGIC
# -------------------------------------------------------------------

func _check_teleport_trigger() -> void:
	if not _teleport_ready:
		return

	# Avoid unfair teleports while vulnerable or eaten.
	if current_state == States.FRIGHTENED:
		return
	if current_state == States.EATEN:
		return

	var dist_to_player := enemy.global_position.distance_to(chase_target.global_position)

	# Too close already? Don't blink on top of the player.
	if dist_to_player < float(teleport_min_range) * tile_size:
		return

	_start_teleport()


func _start_teleport() -> void:
	print("DEBUG: Style entering start_teleport = ", teleport_style)
	_teleport_ready = false
	_teleport_pending = true

	# Restart cooldown.
	if teleport_timer:
		teleport_timer.wait_time = teleport_cooldown
		teleport_timer.start()

	# Save current color and flash gold as a warning.
	_saved_modulate = enemy.modulate
	enemy.modulate = Color(1.0, 0.9, 0.4, 1.0) # golden-ish

	# Freeze movement while "charging" the teleport.
	enemy.can_move = false
	
	# Roll a fresh style for this teleport using PCG weights
	if teleport_style_weights.size() > 0:
		teleport_style = _choose_weighted_style(teleport_style_weights)
	else:
		teleport_style = "AMBUSH_BEHIND"

	teleport_word = _choose_teleport_word(teleport_style)

	# Run the async sequence.
	_do_teleport_sequence()


# -------------------------------------------------------------------
# TELEPORT SEQUENCE (warning -> teleport)
# -------------------------------------------------------------------

func _do_teleport_sequence() -> void:
	# Short warning time so player can react.
	await get_tree().create_timer(teleport_warning_time).timeout

	var target_pos: Vector2 = _compute_teleport_position()

	if target_pos != Vector2.ZERO:
		enemy.global_position = target_pos
		print("[Assassin] Teleport (", teleport_style, ") -> ", target_pos, " [", teleport_word, "]")

		# Play teleport sound
		if teleport_sound_file != "":
			AudioManager.play_sound_file(teleport_sound_file, AudioManager.TrackTypes.ENEMIES)
	else:
		print("[Assassin] Teleport cancelled (no valid tile).")

	# Restore visuals and movement.
	enemy.modulate = _saved_modulate
	enemy.can_move = true
	_teleport_pending = false


# -------------------------------------------------------------------
# TELEPORT DESTINATION SELECTION
# -------------------------------------------------------------------

func _compute_teleport_position() -> Vector2:
	print("DEBUG: compute_teleport_position using style = ", teleport_style)
	# We work in tile space and convert back to world.
	var player_cell: Vector2i = tile_map_layer.local_to_map(chase_target.global_position)

	match teleport_style:
		"AMBUSH_BEHIND":
			return _compute_ambush_position(player_cell)
		"FLANK":
			return _compute_flank_position(player_cell)
		"PREDICTIVE":
			return _compute_predictive_position(player_cell)
		"RANDOM_NEAR":
			return _compute_random_near_position(player_cell)
		_:
			return _compute_random_near_position(player_cell)


# -------------------------------------------------------------------
# STYLE HELPERS
# -------------------------------------------------------------------

func _compute_random_near_position(player_cell: Vector2i) -> Vector2:
	var candidates: Array[Vector2i] = _get_cells_in_range(player_cell, teleport_min_range, teleport_max_range)
	candidates = _filter_out_current_enemy_tile(candidates)

	return _pick_world_position_from_cells(candidates)


func _compute_ambush_position(player_cell: Vector2i) -> Vector2:
	var dir: Vector2 = chase_target.direction
	if dir == Vector2.ZERO:
		return _compute_random_near_position(player_cell)

	var dir_cell := Vector2i(sign(dir.x), sign(dir.y))
	if dir_cell == Vector2i(0, 0):
		return _compute_random_near_position(player_cell)

	var candidates: Array[Vector2i] = []
	for cell in shared_enemy_ai.walkable_tiles_list:
		var c: Vector2i = cell
		var offset: Vector2i = c - player_cell
		var dist := offset.length()
		if dist < float(teleport_min_range) or dist > float(teleport_max_range):
			continue
		# "Behind": opposite side of movement.
		if offset.x * dir_cell.x + offset.y * dir_cell.y >= 0:
			continue
		candidates.append(c)

	candidates = _filter_out_current_enemy_tile(candidates)
	if candidates.is_empty():
		return _compute_random_near_position(player_cell)

	# Prefer the one closest to a point directly behind the player.
	var target_center := player_cell - dir_cell * int(((teleport_min_range + teleport_max_range) / 2.0))
	return _pick_closest_to_cell(target_center, candidates)


func _compute_flank_position(player_cell: Vector2i) -> Vector2:
	var dir: Vector2 = chase_target.direction
	if dir == Vector2.ZERO:
		return _compute_random_near_position(player_cell)

	var dir_cell := Vector2i(sign(dir.x), sign(dir.y))
	if dir_cell == Vector2i(0, 0):
		return _compute_random_near_position(player_cell)

	# Perpendicular direction (left/right).
	var side: Vector2i = Vector2i(-dir_cell.y, dir_cell.x)
	if randi() % 2 == 0:
		side = -side

	var candidates: Array[Vector2i] = []
	for cell in shared_enemy_ai.walkable_tiles_list:
		var c: Vector2i = cell
		var offset: Vector2i = c - player_cell
		var dist := offset.length()
		if dist < float(teleport_min_range) or dist > float(teleport_max_range):
			continue
		# Only consider cells roughly on the chosen flank side.
		if offset.x * side.x + offset.y * side.y <= 0:
			continue
		candidates.append(c)

	candidates = _filter_out_current_enemy_tile(candidates)
	if candidates.is_empty():
		return _compute_random_near_position(player_cell)

	var target_center := player_cell + side * int(((teleport_min_range + teleport_max_range) / 2.0))
	return _pick_closest_to_cell(target_center, candidates)


func _compute_predictive_position(player_cell: Vector2i) -> Vector2:
	var dir: Vector2 = chase_target.direction
	if dir == Vector2.ZERO:
		return _compute_random_near_position(player_cell)

	# Project player position prediction_offset tiles ahead.
	var predicted_world := chase_target.global_position + dir * tile_size * float(prediction_offset)
	var predicted_cell: Vector2i = tile_map_layer.local_to_map(predicted_world)

	var candidates: Array[Vector2i] = _get_cells_in_range(predicted_cell, teleport_min_range, teleport_max_range)
	candidates = _filter_out_current_enemy_tile(candidates)

	if candidates.is_empty():
		return _compute_random_near_position(player_cell)

	return _pick_closest_to_cell(predicted_cell, candidates)


# -------------------------------------------------------------------
# LOW-LEVEL TILE HELPERS
# -------------------------------------------------------------------

# Get all walkable cells within [min_r, max_r] distance of center_cell.
func _get_cells_in_range(center_cell: Vector2i, min_r: int, max_r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in shared_enemy_ai.walkable_tiles_list:
		var c: Vector2i = cell
		var dist := (c - center_cell).length()
		if dist >= float(min_r) and dist <= float(max_r):
			out.append(c)
	return out


func _filter_out_current_enemy_tile(cells: Array[Vector2i]) -> Array[Vector2i]:
	var enemy_cell: Vector2i = tile_map_layer.local_to_map(enemy.global_position)
	var filtered: Array[Vector2i] = []
	for c in cells:
		if c != enemy_cell:
			filtered.append(c)
	return filtered


func _pick_world_position_from_cells(cells: Array[Vector2i]) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var idx := randi() % cells.size()
	var cell: Vector2i = cells[idx]
	return tile_map_layer.map_to_local(cell)


func _pick_closest_to_cell(target_cell: Vector2i, cells: Array[Vector2i]) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO

	var best_cell: Vector2i = cells[0]
	var best_dist := float((best_cell - target_cell).length())

	for i in range(1, cells.size()):
		var c: Vector2i = cells[i]
		var d := float((c - target_cell).length())
		if d < best_dist:
			best_dist = d
			best_cell = c

	return tile_map_layer.map_to_local(best_cell)


# -------------------------------------------------------------------
# STYLE / FLAVOUR HELPERS
# -------------------------------------------------------------------

func _choose_weighted_style(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])

	if total <= 0.0:
		return "AMBUSH_BEHIND"  # safe fallback

	var roll := randf() * total
	var cumulative := 0.0

	for k in weights.keys():
		cumulative += float(weights[k])
		if roll <= cumulative:
			return k

	return "AMBUSH_BEHIND"


func _choose_teleport_word(style: String) -> String:
	var arr = TELEPORT_WORDS.get(style, ["Teleport!"])
	return arr[randi() % arr.size()]
