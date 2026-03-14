extends Node
class_name SharedEnemyAI

@onready var tile_map_layer: TileMapLayer = get_tree().get_root().get_node("Level/TileMapLayer")

# Wall atlas coords are passed in from the generator so both scripts agree
@export var wall_atlas_coords: Vector2i = Vector2i(1, 4)

# This list is what the enemy AI uses as valid tiles for movement/pathfinding
var walkable_tiles_list: PackedVector2Array = []


# Walkables are any interior cell that is not a wall tile.
# This works even if the generator stamps floors dynamically.
func rebuild_walkables_from_walls() -> void:
	walkable_tiles_list.clear()

	var r: Rect2i = tile_map_layer.get_used_rect()
	if r.size == Vector2i.ZERO:
		return

	var left_x: int = r.position.x
	var right_x: int = r.position.x + r.size.x - 1
	var top_y: int = r.position.y
	var bottom_y: int = r.position.y + r.size.y - 1

	for y in range(top_y + 1, bottom_y):
		for x in range(left_x + 1, right_x):
			var p: Vector2i = Vector2i(x, y)

			# If there is a wall tile here, it is not walkable
			if tile_map_layer.get_cell_source_id(p) != -1:
				if tile_map_layer.get_cell_atlas_coords(p) == wall_atlas_coords:
					continue

			walkable_tiles_list.append(p)


func get_walkables() -> PackedVector2Array:
	return walkable_tiles_list



@onready var enemies_timers: EnemiesTimers = $EnemiesTimers
@onready var scatter_timer: Timer = enemies_timers.get_node("ScatterDurationTimer")
@onready var chase_timer: Timer = enemies_timers.get_node("ChaseDurationTimer")

@onready var enemies: Enemies = get_tree().get_root().get_node("Level/Actors/Enemies")
var enemy_ai_list: Array[EnemyAI] = []

var frightened_enemy_ais_count: int = 0
var enemies_eaten_combo_count: int = 0

var enemy_base_score_value: int = 200
var enemy_score_value: int = enemy_base_score_value

@export var numbers_displayer_scene: PackedScene = null


func on_enemy_state_set(state: EnemyAI.States, enemy: Enemy) -> void:
	match state:
		EnemyAI.States.EATEN:
			frightened_enemy_ais_count -= 1
			enemies_eaten_combo_count += 1
			if frightened_enemy_ais_count >= 0:
				if enemies_eaten_combo_count > 1:
					enemy_score_value *= 2
				Global.increase_score(enemy_score_value)

				var numbers_displayer_instance: NumbersDisplayer = numbers_displayer_scene.instantiate()
				numbers_displayer_instance.color = Color(0.102, 0, 0.945, 1.0)
				numbers_displayer_instance.set_text(str(enemy_score_value))
				numbers_displayer_instance.set_global_position(enemy.get_global_position())
				get_tree().get_root().add_child(numbers_displayer_instance)

				total_enemies_eaten_count += 1

				if total_enemies_eaten_count >= enemies_to_eat_for_combo_bonus_cap:
					Global.increase_score(combo_bonus_score_value)

		EnemyAI.States.FRIGHTENED:
			frightened_enemy_ais_count += 1


func on_enemies_timers_frightened_timer_timeout() -> void:
	frightened_enemy_ais_count = 0
	enemies_eaten_combo_count = 0
	enemy_score_value = enemy_base_score_value


@export var initial_ais_state: EnemyAI.States = EnemyAI.States.SCATTER


func on_game_started() -> void:
	var timer_started: bool = false

	for enemy_ai: EnemyAI in enemy_ai_list:
		if not enemy_ai.is_initialized:
			await enemy_ai.initialized

		enemy_ai.set_state(initial_ais_state)

		match initial_ais_state:
			enemy_ai.States.CHASE:
				enemy_ai.background_state = enemy_ai.States.CHASE
				if not timer_started:
					timer_started = true
					chase_timer.start()

			enemy_ai.States.SCATTER:
				enemy_ai.background_state = enemy_ai.States.SCATTER
				if not timer_started:
					timer_started = true
					scatter_timer.start()

			_:
				printerr("(!) ERROR: In: " + self.get_name() + ": Unhandled state on game started!")

		enemy_ai.first_initialization = false



@onready var pellets: Pellets = get_tree().get_root().get_node("Level/Pickables/Pellets")
@onready var enemies_to_eat_for_combo_bonus_cap = pellets.initial_power_pellets_count * enemies.initial_enemies_count

var total_enemies_eaten_count: int = 0
var combo_bonus_score_value: int = 12000


func _ready() -> void:
	assert(numbers_displayer_scene != null)

	Global.game_ready.connect(on_game_started)
	enemies_timers.frightened_timer.timeout.connect(on_enemies_timers_frightened_timer_timeout)

	for enemy: Enemy in enemies.get_children():
		enemy_ai_list.append(enemy.enemy_ai)

	# Initial build, generator will rebuild after it finishes stamping floors and lanes
	rebuild_walkables_from_walls()

	for enemy_ai in enemy_ai_list:
		enemy_ai.state_set.connect(on_enemy_state_set)
