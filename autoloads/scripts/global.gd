extends Node
# If you like, you can uncomment this, but it's not required for the Autoload:
# class_name Global


# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
signal level_cleared
signal game_over
signal new_game_started

signal lives_changed
signal score_changed
signal high_score_changed

signal player_died
signal player_finished_dying
signal game_ready
signal game_started
signal rare_pellet_bonus_display_requested(value: int)
# Rare / golden pellet buff signals
signal rare_pellet_buff_started(multiplier: float, duration: float)
signal rare_pellet_buff_ended()


# -----------------------------------------------------------------------------
# Rare pellet buff state
# -----------------------------------------------------------------------------
var rare_pellet_buff_active: bool = false
var rare_pellet_buff_multiplier: float = 1.0
var _rare_pellet_timer: Timer


# -----------------------------------------------------------------------------
# Lives / difficulty / game state
# -----------------------------------------------------------------------------
var initial_lives: int = 2
var lives: int = initial_lives
var max_lives: int = 5
var is_game_over: bool = false

# This is what PCG and buffs use
var selected_difficulty: String = "Easy"


# -----------------------------------------------------------------------------
# Score & high score
# -----------------------------------------------------------------------------
@export var success_sound_file_path: String = "res://assets/audio/success.wav"

## Number of points to score to get an extra life initially.
var point_to_gain_life_base_cap: int = 4500
var points_to_gain_life_cap: int = point_to_gain_life_base_cap

# Current score
var score: int = 0:
	set = set_score

# High score (loaded/saved)
var high_score: int = 0


# -----------------------------------------------------------------------------
# Save game
# -----------------------------------------------------------------------------
const SAVE_GAME_FILE_PATH: String = "user://game_save.res"
var game_save: GameSave = GameSave.new()

var try_to_replace_corrupted_save_file: bool = false


# -----------------------------------------------------------------------------
# Core game state helpers
# -----------------------------------------------------------------------------
func reset() -> void:
	# Reset game status for a new run
	is_game_over = false
	set_score(0)
	set_lives(initial_lives)


func set_lives(value: int) -> void:
	lives = value
	lives_changed.emit()


func increase_lives(value: int = 1) -> void:
	if lives + value > max_lives:
		return
	set_lives(lives + value)


func decrease_lives(value: int = 1) -> void:
	var remaining_lives: int = lives - value

	if remaining_lives < 0:
		is_game_over = true
		game_over.emit()
		return

	set_lives(remaining_lives)
	player_died.emit()


# -----------------------------------------------------------------------------
# Score helpers
# -----------------------------------------------------------------------------
func set_score(value: int) -> void:
	score = value
	score_changed.emit()

	# Extra life every X points
	if score >= points_to_gain_life_cap:
		increase_lives()
		points_to_gain_life_cap += point_to_gain_life_base_cap
		AudioManager.play_sound_file(success_sound_file_path, AudioManager.TrackTypes.MUSIC)

	# High score tracking
	if score > high_score:
		set_high_score(score)


func increase_score(value: int) -> void:
	set_score(score + value)


func set_high_score(value: int) -> void:
	high_score = value
	high_score_changed.emit()


# -----------------------------------------------------------------------------
# Save / load
# -----------------------------------------------------------------------------
func save_game() -> void:
	game_save.high_score = high_score
	var res: Error = ResourceSaver.save(game_save, SAVE_GAME_FILE_PATH)

	if res != OK:
		if try_to_replace_corrupted_save_file:
			printerr("(!) ERROR: In: ", name, ": Couldn't create a new save game file!")
			return

		printerr("(!) ERROR: In: ", name, ": Couldn't save the game save file!")

		# Try to delete the possibly corrupted file
		printerr("Attempting to delete the save game file...")
		var file_removal_error: Error = DirAccess.remove_absolute(SAVE_GAME_FILE_PATH)
		if file_removal_error != OK:
			printerr("(!) ERROR: In: ", name, ": Couldn't remove the game save file!")
			return

		# Try to create a fresh one
		printerr("Attempting to create a new save game file...")
		try_to_replace_corrupted_save_file = true
		save_game()


func load_game() -> void:
	var game_save_exists: bool = FileAccess.file_exists(SAVE_GAME_FILE_PATH)

	if not game_save_exists:
		save_game()

	var game_save_to_load: Object = load(SAVE_GAME_FILE_PATH)

	if game_save_to_load == null:
		printerr("(!) ERROR: In: ", name, ": Couldn't load the game save file!")
		return

	set_high_score(game_save_to_load.high_score)


# -----------------------------------------------------------------------------
# Callbacks for other global events
# -----------------------------------------------------------------------------
func on_new_game_started() -> void:
	reset()


func on_player_died() -> void:
	# Keep progression even if the game didn't end
	save_game()


func on_game_over() -> void:
	save_game()


func on_level_cleared() -> void:
	save_game()


# -----------------------------------------------------------------------------
# Rare pellet buff logic
# -----------------------------------------------------------------------------
func _on_rare_pellet_timer_timeout() -> void:
	# Buff ended: reset state and notify listeners
	rare_pellet_buff_active = false
	rare_pellet_buff_multiplier = 1.0
	rare_pellet_buff_ended.emit()


func on_rare_pellet_picked() -> void:
	# Decide buff parameters from difficulty
	var diff := selected_difficulty
	var mult := 1.0
	var duration := 5.0
	var bonus_score := 0

	match diff:
		"Easy":
			mult = 1.60
			duration = 15.0
			bonus_score = 200
		"Medium":
			mult = 1.40
			duration = 10.0
			bonus_score = 400
		"Hard":
			mult = 1.20
			duration = 5.0
			bonus_score = 1000

	# Extra score for rare pellet (normal pellet already added its base score)
	increase_score(bonus_score)
	
	# Rare pellet picked up popup display
	rare_pellet_bonus_display_requested.emit(bonus_score)

	# Activate buff
	rare_pellet_buff_active = true
	rare_pellet_buff_multiplier = mult

	# Start timer so we know when to end the buff
	_rare_pellet_timer.start(duration)

	# Notify player/enemies that buff started
	rare_pellet_buff_started.emit(mult, duration)


# -----------------------------------------------------------------------------
# _ready: hook everything up
# -----------------------------------------------------------------------------
func _ready() -> void:
	assert(FileAccess.file_exists(success_sound_file_path))

	# Connect high-level game signals
	new_game_started.connect(on_new_game_started)
	player_died.connect(on_player_died)
	game_over.connect(on_game_over)
	level_cleared.connect(on_level_cleared)

	# Load saved data (high score)
	load_game()

	# Optional: wait for Level to exist before resetting
	var level_node: Level = get_tree().get_root().get_node_or_null("Level")
	if level_node != null:
		await level_node.ready
		reset()

	# Create the rare pellet buff timer
	_rare_pellet_timer = Timer.new()
	_rare_pellet_timer.one_shot = true
	add_child(_rare_pellet_timer)
	_rare_pellet_timer.timeout.connect(_on_rare_pellet_timer_timeout)
