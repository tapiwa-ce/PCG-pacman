extends Node
class_name BourrinElroyMode

# The AI being controlled (Bourrin)
@export var enemy_ai: EnemyAIBourrin = null

# The Enemy node that owns the EnemyAI
@onready var enemy: Enemy = enemy_ai.enemy

# Timer on Cornichon that controls when Bourrin can enter Elroy mode
@onready var enemy_ai_to_wait_enable_ai_timer: Timer = _get_cornichon_enable_ai_timer()

@onready var pellets_node: Pellets = (
	get_tree().get_root().get_node("Level/Pickables/Pellets")
)

# Percent thresholds
var percentage_tier_1: float = 0.08
var percentage_tier_2: float = 0.04

# Runtime pellet counts
var remaining_pellets_count: int = 0
var tier_1_pellet_count_treshold: int = 0
var tier_2_pellet_count_treshold: int = 0


# --------------------------------------------------------------------
# HELPER: SAFE NODE LOOKUP (no ? operator)
# --------------------------------------------------------------------
func _get_cornichon_enable_ai_timer() -> Timer:
	var root = get_tree().get_root()

	var enemies_root = root.get_node_or_null("Level/Actors/Enemies")
	if enemies_root == null:
		return null

	var cornichon = enemies_root.get_node_or_null("EnemyCornichon")
	if cornichon == null:
		return null

	var ai_node = cornichon.get_node_or_null("EnemyAICornichon/EnableAITimer")
	return ai_node


# --------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------
func initialize_tiers_and_remaining_pellets() -> void:
	remaining_pellets_count = pellets_node.remaining_pellets_count

	tier_1_pellet_count_treshold = round(remaining_pellets_count * percentage_tier_1)
	tier_2_pellet_count_treshold = round(remaining_pellets_count * percentage_tier_2)

	if remaining_pellets_count <= 2:
		self.queue_free()

	if tier_1_pellet_count_treshold == tier_2_pellet_count_treshold:
		tier_1_pellet_count_treshold = 2
		tier_2_pellet_count_treshold = 1


func _ready() -> void:
	assert(enemy_ai != null)
	assert(enemy != null)

	if enemy_ai_to_wait_enable_ai_timer != null:
		enemy_ai_to_wait_enable_ai_timer.timeout.connect(on_enemy_to_wait_went_out)

	pellets_node.pellet_picked_up.connect(on_pellet_picked_up)
	Global.player_died.connect(on_player_died)

	initialize_tiers_and_remaining_pellets()


# --------------------------------------------------------------------
# SIGNAL HANDLERS
# --------------------------------------------------------------------
func on_pellet_picked_up(_value: int) -> void:
	remaining_pellets_count = pellets_node.remaining_pellets_count
	check_if_should_enable_elroy_mode()


func on_player_died() -> void:
	disable_elroy_mode()


func on_enemy_to_wait_went_out() -> void:
	check_if_should_enable_elroy_mode()


# --------------------------------------------------------------------
# MAIN LOGIC: Should Elroy mode activate?
# --------------------------------------------------------------------
func check_if_should_enable_elroy_mode() -> void:
	if remaining_pellets_count <= tier_2_pellet_count_treshold:
		enable_elroy_mode(true)
	elif remaining_pellets_count <= tier_1_pellet_count_treshold:
		enable_elroy_mode(false)


# --------------------------------------------------------------------
# ENABLE ELROY MODE (Ghost speeds up)
# --------------------------------------------------------------------
func enable_elroy_mode(go_faster_than_player: bool) -> void:
	enemy_ai.elroy_mode_enabled = true

	if go_faster_than_player:
		enemy.chase_speed = enemy.base_speed * 1.20
	else:
		enemy.chase_speed = enemy.base_speed * 1.08

	if enemy_ai.current_state == enemy_ai.States.CHASE:
		enemy.speed = enemy.chase_speed
	else:
		enemy_ai.set_state(enemy_ai.States.CHASE)


# --------------------------------------------------------------------
# DISABLE ELROY MODE (Ghost returns to normal speed)
# --------------------------------------------------------------------
@onready var shared_enemy_ai: SharedEnemyAI = (
	get_tree().get_root().get_node("Level/SharedEnemyAI")
)

func disable_elroy_mode() -> void:
	enemy_ai.elroy_mode_enabled = false

	# Restore default chase speed
	enemy.chase_speed = enemy.base_speed

	if enemy_ai.current_state == enemy_ai.States.CHASE:
		enemy.speed = enemy.chase_speed
	else:
		enemy_ai.set_state(shared_enemy_ai.initial_ais_state)
