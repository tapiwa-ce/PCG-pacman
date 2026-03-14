extends Node
class_name PCGManager

# ---------------------------------------------------------
# Cached scene references
# ---------------------------------------------------------
@onready var enemies_node: Enemies = get_tree().get_root().get_node("Level/Actors/Enemies")
@onready var pellets_node: Pellets = get_tree().get_root().get_node("Level/Pickables/Pellets")

# PCG factory (generates procedural params)
var factory: EnemyPCGFactory

# Prevent double-application of enemy PCG
var _applied: bool = false


# =========================================================
# READY
# =========================================================
func _ready() -> void:
	# Create and attach the PCG factory
	factory = EnemyPCGFactory.new()
	add_child(factory)

	# Read selected difficulty from Global
	var difficulty: String = Global.selected_difficulty
	var seed_value: int = difficulty.hash()
	factory.set_seed(seed_value)

	# Wait one frame so all Enemy nodes finish _ready()
	await get_tree().process_frame

	# Apply PCG systems
	_apply_pcg_to_all_enemies(difficulty)
	_apply_rare_pellets(difficulty)


# =========================================================
# APPLY PCG TO ENEMIES
# =========================================================
func _apply_pcg_to_all_enemies(difficulty: String) -> void:
	if _applied:
		return
	_applied = true

	if enemies_node == null:
		push_warning("PCGManager: Enemies node not found at Level/Actors/Enemies.")
		return

	for child in enemies_node.get_children():
		if child is Enemy:
			var enemy: Enemy = child
			var params: Dictionary = factory.generate_enemy(difficulty)

			# Enemy-level initialization (handled in enemy.gd)
			enemy.init_from_pcg(params)

			# Debug output (optional)
			print(
				"[PCG] ", difficulty, " enemy: ", enemy.name,
				" speed=", params["speed"],
				" pred=", params["prediction_offset"],
				" scatter=", params["scatter_time"]
			)


# =========================================================
# APPLY RARE GOLDEN PELLETS
# =========================================================
func _apply_rare_pellets(difficulty: String) -> void:
	# Make sure Pellets node exists
	if pellets_node == null:
		push_warning("PCGManager: Pellets node not found at Level/Pickables/Pellets.")
		return

	# Normal pellets are stored inside Pellets/Normal
	var normal_container = pellets_node.get_node("Normal")
	if normal_container == null:
		push_warning("PCGManager: Normal container not found under Pellets.")
		return

	# Collect all pellet nodes
	var all_pellets: Array = []
	for p in normal_container.get_children():
		all_pellets.append(p)

	if all_pellets.is_empty():
		return

	# Decide how many rare pellets based on difficulty
	var rare_count: int = 0
	if difficulty == "Easy":
		rare_count = 10
	elif difficulty == "Medium":
		rare_count = 5
	elif difficulty == "Hard":
		rare_count = 2
	else:
		rare_count = 5

	# Clamp to the amount of pellets we actually have
	if rare_count > all_pellets.size():
		rare_count = all_pellets.size()

	# Separate RNG for golden pellet selection
	var rng = RandomNumberGenerator.new()
	rng.randomize()  # offset so it differs from enemy PCG

	# Randomly pick distinct pellets to become "rare"
	# Randomly pick distinct pellets to become "rare"
	for i in range(rare_count):
		var idx = rng.randi_range(0, all_pellets.size() - 1)
		var pellet = all_pellets[idx]
		all_pellets.remove_at(idx)
		# Mark as rare & recolor to gold (no has_variable check)
		pellet.set_meta("is_rare_pellet", true)

# Try recolor the pellet itself
		pellet.modulate = Color(1.0, 0.84, 0.0)

# Try recolor the child sprite if it exists
				# Mark as rare
		pellet.set_meta("is_rare_pellet", true)

		# Try to recolor the pellet node itself
		pellet.modulate = Color(1.0, 0.84, 0.0)

		# Recolor Sprite2D if present
		var sprite: Sprite2D = pellet.get_node_or_null("Sprite2D")
		if sprite != null:
			sprite.modulate = Color(1.0, 0.84, 0.0)

		# Recolor AnimatedSprite2D if present
		var anim: AnimatedSprite2D = pellet.get_node_or_null("AnimatedSprite2D")
		if anim != null:
			anim.modulate = Color(1.0, 0.84, 0.0)
