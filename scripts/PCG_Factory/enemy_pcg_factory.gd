extends Node
class_name EnemyPCGFactory

# Dedicated RNG so we can control the seed per run / difficulty.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func set_seed(seed: int) -> void:
	rng.seed = seed

# We keep this list for later (when we PCG AI types),
# but SOFT PCG won't actually swap AI scenes yet.
const AI_TYPES = [
	"EnemyAIAssassin",
	"EnemyAIBourrin",
	"EnemyAIChelou",
	"EnemyAICornichon"
]

# Difficulty-based parameter ranges.
# These are tuned around the original base_speed ≈ 2.35.
var difficulty_params := {
	"Easy": {
		"speed_min": 1.8, "speed_max": 2.2,

		# AI responsiveness
		"prediction_min": 1, "prediction_max": 2,

		# Timer durations
		"scatter_min": 4.0, "scatter_max": 6.0,
		"chase_min": 6.0,   "chase_max": 9.0,
		"frightened_min": 7.0, "frightened_max": 9.0,

		"frightened_speed_mult": 0.45,
		"direction_change_cooldown_min": 0.28,
		"direction_change_cooldown_max": 0.38,

		"spawn_delay_min": 0.0,
		"spawn_delay_max": 0.5,
		
		# No teleporting in Easy mode
		"teleport_enabled": false,
		"teleport_cooldown_min": 0.0,
		"teleport_cooldown_max": 0.0,
		"teleport_warning_min": 0.0,
		"teleport_warning_max": 0.0,
		"teleport_min_range": 0,
		"teleport_max_range": 0,
		"teleport_style_weights": {},
	},

	"Medium": {
		"speed_min": 2.2, "speed_max": 2.6,

		"prediction_min": 3, "prediction_max": 5,

		"scatter_min": 3.0, "scatter_max": 5.0,
		"chase_min": 6.0,   "chase_max": 8.0,
		"frightened_min": 4.0, "frightened_max": 6.0,

		"frightened_speed_mult": 0.55,
		"direction_change_cooldown_min": 0.18,
		"direction_change_cooldown_max": 0.28,

		"spawn_delay_min": 0.0,
		"spawn_delay_max": 0.3,
		
		# Medium mode has predictable assassin teleportation
		"teleport_enabled": true,

		# Less frequent, forgiving
		"teleport_cooldown_min": 8.0,
		"teleport_cooldown_max": 12.0,

		# Longer telegraph for fairness
		"teleport_warning_min": 0.55,
		"teleport_warning_max": 0.75,

		# Closer teleports, not too aggressive
		"teleport_min_range": 3,
		"teleport_max_range": 5,

		# Safe teleports only
		"teleport_style_weights": {
			"AMBUSH_BEHIND": 0.45,
			"RANDOM_NEAR": 0.45,
			"FLANK": 0.10,
			"PREDICTIVE": 0.0,
		},
	},

	"Hard": {
		"speed_min": 2.6, "speed_max": 3.2,

		"prediction_min": 4, "prediction_max": 8,

		"scatter_min": 2.0, "scatter_max": 4.0,
		"chase_min": 5.0,   "chase_max": 7.0,
		"frightened_min": 2.5, "frightened_max": 3.5,

		"frightened_speed_mult": 0.75,
		"direction_change_cooldown_min": 0.10,
		"direction_change_cooldown_max": 0.18,

		"spawn_delay_min": 0.0,
		"spawn_delay_max": 0.2,
		
		# Hard mode teleportation made scary
		"teleport_enabled": true,

		# More frequent teleports
		"teleport_cooldown_min": 5.0,
		"teleport_cooldown_max": 8.0,

		# Faster telegraph
		"teleport_warning_min": 0.35,
		"teleport_warning_max": 0.55,

		# Can teleport both close and medium distances
		"teleport_min_range": 1,
		"teleport_max_range": 8,

		# All four teleport styles unlocked
		"teleport_style_weights": {
			"AMBUSH_BEHIND": 0.25,
			"RANDOM_NEAR": 0.25,
			"FLANK": 0.25,
			"PREDICTIVE": 0.25,
		},
	},
}

# Main generator: one config per enemy instance.
func generate_enemy(difficulty: String) -> Dictionary:
	var params: Dictionary = {}

	# SOFT PCG: no AI type swap yet, but we keep the field for later.
	params["ai_type"] = ""

	# Fallback to Medium if something weird comes in.
	var bounds: Dictionary = difficulty_params.get(difficulty, difficulty_params["Medium"])

	# SPEED
	params["speed"] = rng.randf_range(bounds["speed_min"], bounds["speed_max"])

	# PREDICTION OFFSET (how far ahead AI predicts the player)
	params["prediction_offset"] = rng.randi_range(
		bounds["prediction_min"],
		bounds["prediction_max"]
	)

	# SCATTER DURATION (seconds before switching back to chase)
	params["scatter_time"] = rng.randf_range(
		bounds["scatter_min"],
		bounds["scatter_max"]
	)
	# CHASE TIME (how long the chase will continue)
	params["chase_time"] = rng.randf_range(bounds["chase_min"], bounds["chase_max"])
	
	# FRIGHTENED TIME (how long the AI will stay frightened)
	params["frightened_time"] = rng.randf_range(bounds["frightened_min"], bounds["frightened_max"])
	
	# FRIGHTENED SPEED MULT (how fast the AI will go while frightened)
	params["frightened_speed_mult"] = bounds["frightened_speed_mult"]
	
	#
	params["direction_change_cooldown"] = rng.randf_range(
		bounds["direction_change_cooldown_min"], bounds["direction_change_cooldown_max"]
	)
	
	# Once sent back home, Spawn Delay dictates when they spawn
	params["spawn_delay"] = rng.randf_range(
		bounds["spawn_delay_min"], bounds["spawn_delay_max"]
	)
	
		# --- Teleport PCG (Assassin only) ---
	var teleport_config := {}

	var tmin = bounds["teleport_cooldown_min"]
	var tmax = bounds["teleport_cooldown_max"]
	teleport_config["teleport_enabled"] = bounds["teleport_enabled"]
	teleport_config["teleport_cooldown"] = rng.randf_range(tmin, tmax)

	teleport_config["teleport_warning"] = rng.randf_range(
		bounds["teleport_warning_min"],
		bounds["teleport_warning_max"]
	)

	# Range in tiles (converted later in AI)
	teleport_config["teleport_min_range"] = bounds["teleport_min_range"]
	teleport_config["teleport_max_range"] = bounds["teleport_max_range"]

	# Weighted random style
	teleport_config["teleport_style"] = "AMBUSH_BEHIND"

	# Stylish word (PCG)
	teleport_config["teleport_word"] = "Ambush!"

	params["teleport"] = teleport_config

	return params
	

func _choose_weighted_style(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights.keys():
		total += weights[k]

	var roll := rng.randf() * total
	var cumulative := 0.0

	for k in weights.keys():
		cumulative += weights[k]
		if roll <= cumulative:
			return k
	
	return "RANDOM_NEAR"  # default fallback
	

const TELEPORT_WORDS := {
	"AMBUSH_BEHIND": ["Ambush!", "Behind You!", "Sneak!"],
	"RANDOM_NEAR": ["Jackpot!", "Surprise!", "Pop!"],
	"FLANK": ["Flank!", "Side Hit!", "Slide!"],
	"PREDICTIVE": ["Read You!", "Got You!", "Predict!"],
}

func _choose_teleport_word(style: String) -> String:
	var arr = TELEPORT_WORDS.get(style, ["Teleport!"])
	return arr[rng.randi_range(0, arr.size() - 1)]
