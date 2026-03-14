extends Node2D
class_name Enemy

# =========================================================
# PCG-Generated Enemy Parameters (filled by PCGManager)
# =========================================================
var pcg_speed: float = 0.0
var pcg_prediction_offset: int = 0
var pcg_scatter_time: float = 0.0
var pcg_chase_time: float = 0.0
var pcg_frightened_time: float = 0.0
var pcg_frightened_speed_mult: float = 0.5
var pcg_direction_change_cooldown: float = 0.25
var pcg_spawn_delay: float = 0.0


# =========================================================
# BASE SPEEDS (CHANGED BY PCG, THEN BY BUFF)
# =========================================================
var speed: float = 0.0
@export var base_speed: float = 2.35   # PCG overwrites this!

var chase_speed: float = base_speed
var scatter_speed: float = base_speed
var eaten_speed: float = base_speed * 2
var frightened_speed: float = base_speed / 2.0

# Rare pellet slowdown multiplier (applied dynamically)
var slow_multiplier: float = 1.0       # 1.0 = normal speed

# Slowdown active flag
var slowdown_active: bool = false


# =========================================================
# NODE REFERENCES
# =========================================================
@export var spawn_point: Marker2D = null
@onready var spawn_position: Vector2 = spawn_point.global_position

@export var initial_direction: Vector2 = Vector2(0, 1)
var direction: Vector2 = initial_direction
var velocity: Vector2 = direction

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var anim_node_sm_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var colors_animation_player: AnimationPlayer = $ColorsAnimationPlayer

@export var enemy_ai: EnemyAI = null

@onready var shared_enemy_ai: SharedEnemyAI = get_tree().get_root().get_node("Level/SharedEnemyAI")
@onready var enemies_timers: EnemiesTimers = shared_enemy_ai.get_node("EnemiesTimers")

@export_group("Sound Files")
@export_file("*.wav","*.ogg") var frightened_sound_file_path: String = ""
@export_file("*.wav","*.ogg") var eaten_sound_file_path: String = ""
@export_file("*.wav","*.ogg") var enemy_going_home_sound_file_path: String = ""
@export_group("")


# =========================================================
# ENABLE / DISABLE
# =========================================================
func enable() -> void:
	set_physics_process(true)

func disable() -> void:
	set_physics_process(false)


# =========================================================
# VISUAL / ANIMATION STATE SIGNALS
# =========================================================
func on_game_ready() -> void:
	animation_tree.set("parameters/move/blend_position", Vector2.ZERO)
	animation_tree.set("parameters/idle/blend_position", direction)

func on_game_started() -> void:
	self.enable()

func on_level_cleared() -> void:
	self.disable()


# =========================================================
# HURT/HIT BOXES
# =========================================================
@onready var hurt_box: HurtBox = $HurtBox
@onready var hit_box: Area2D = $HitBox

func set_hurt_box_disabled(value: bool) -> void:
	for c in hurt_box.get_children():
		c.call_deferred("set_disabled", value)

func set_hit_box_disabled(value: bool) -> void:
	for c in hit_box.get_children():
		c.call_deferred("set_disabled", value)


signal died
func die() -> void:
	died.emit()


func on_player_died() -> void:
	self.disable()
	animation_tree.set("parameters/idle/blend_position", direction)
	anim_node_sm_playback.travel("idle")


func on_player_finished_dying() -> void:
	if Global.is_game_over:
		return
	self.global_position = spawn_position
	self.direction = initial_direction
	animation_tree.set("parameters/move/blend_position", direction)


func _initialize_signals() -> void:
	Global.game_ready.connect(on_game_ready)
	Global.game_started.connect(on_game_started)
	Global.level_cleared.connect(on_level_cleared)
	Global.player_died.connect(on_player_died)
	Global.player_finished_dying.connect(on_player_finished_dying)

	# Rare Pellet Slowdown
	Global.rare_pellet_buff_started.connect(_on_rare_start)
	Global.rare_pellet_buff_ended.connect(_on_rare_end)


# =========================================================
# RARE PELLET SLOWDOWN HANDLING
# =========================================================
func _on_rare_start(mult: float, _duration: float) -> void:
	# Player speed increases, enemies slow down significantly
	slowdown_active = true

	match Global.selected_difficulty:
		"Easy":
			slow_multiplier = 0.35     # enemies VERY slow
		"Medium":
			slow_multiplier = 0.50     # enemies moderate slow
		"Hard":
			slow_multiplier = 0.65     # enemies slightly slow
		_:
			slow_multiplier = 0.50

	_apply_current_state_speed()

func _on_rare_end() -> void:
	slowdown_active = false
	slow_multiplier = 1.0
	_apply_current_state_speed()

# Re-applies speed for current enemy state
func _apply_current_state_speed() -> void:
	match enemy_ai.current_state:
		EnemyAI.States.CHASE:
			speed = chase_speed * slow_multiplier
		EnemyAI.States.SCATTER:
			speed = scatter_speed * slow_multiplier
		EnemyAI.States.FRIGHTENED:
			speed = frightened_speed * slow_multiplier
		EnemyAI.States.EATEN:
			speed = eaten_speed      # eaten speed is NEVER slowed
		_:
			speed = chase_speed * slow_multiplier


# =========================================================
# ENEMY STATE HANDLING
# =========================================================
var going_home: bool = false

func on_chasing() -> void:
	set_hurt_box_disabled(true)
	set_hit_box_disabled(false)
	_apply_current_state_speed()
	going_home = false
	set_process(false)
	colors_animation_player.play("normal")
	AudioManager.stop_track(AudioManager.TrackTypes.ENEMIES)

func on_scattered() -> void:
	set_hurt_box_disabled(true)
	set_hit_box_disabled(false)
	_apply_current_state_speed()
	going_home = false
	set_process(false)
	colors_animation_player.play("normal")
	AudioManager.stop_track(AudioManager.TrackTypes.ENEMIES)

func on_eaten() -> void:
	set_hurt_box_disabled(true)
	set_hit_box_disabled(true)
	speed = eaten_speed          # NO slowdown applied here
	going_home = true
	set_process(false)
	AudioManager.play_sound_file(eaten_sound_file_path, AudioManager.TrackTypes.ENEMIES)
	await AudioManager.enemies_player.finished
	AudioManager.play_sound_file(enemy_going_home_sound_file_path, AudioManager.TrackTypes.ENEMIES)

func on_frightened() -> void:
	set_hurt_box_disabled(false)
	set_hit_box_disabled(true)
	_apply_current_state_speed()
	going_home = false
	set_process(true)
	colors_animation_player.play("frightened")
	AudioManager.play_sound_file(frightened_sound_file_path, AudioManager.TrackTypes.ENEMIES)


func on_enemy_ai_state_set(state: EnemyAI.States, _enemy: Enemy) -> void:
	match state:
		EnemyAI.States.CHASE:
			on_chasing()
		EnemyAI.States.SCATTER:
			on_scattered()
		EnemyAI.States.EATEN:
			on_eaten()
		EnemyAI.States.FRIGHTENED:
			on_frightened()
		_:
			printerr("Unhandled AI state in enemy.gd")


# =========================================================
# READY
# =========================================================
func _ready() -> void:
	set_process(false)
	assert(spawn_point != null)

	assert(FileAccess.file_exists(frightened_sound_file_path))
	assert(FileAccess.file_exists(eaten_sound_file_path))
	assert(FileAccess.file_exists(enemy_going_home_sound_file_path))

	enemy_ai.state_set.connect(on_enemy_ai_state_set)

	self.disable()
	_initialize_signals()

	direction = initial_direction
	animation_tree.active = true


# =========================================================
# MOVEMENT LOOP
# =========================================================
var can_move: bool = true

func _physics_process(_delta: float) -> void:
	if can_move:
		velocity = direction * speed
		self.global_position += velocity

		if velocity != Vector2.ZERO:
			if going_home:
				anim_node_sm_playback.travel("going_home")
				colors_animation_player.play("going_home")
			else:
				animation_tree.set("parameters/move/blend_position", direction)
				anim_node_sm_playback.travel("move")
		else:
			animation_tree.set("parameters/idle/blend_position", direction)
			anim_node_sm_playback.travel("idle")


# =========================================================
# PCG INITIALIZATION (CALLED ONCE AT LEVEL START)
# =========================================================
func init_from_pcg(params: Dictionary) -> void:
	pcg_speed = params["speed"]
	base_speed = pcg_speed

	chase_speed = pcg_speed
	scatter_speed = pcg_speed * 0.92
	eaten_speed = pcg_speed * 2.0
	frightened_speed = pcg_speed * params["frightened_speed_mult"]

	pcg_prediction_offset = params["prediction_offset"]
	if enemy_ai and enemy_ai.has_method("set_prediction_offset"):
		enemy_ai.set_prediction_offset(pcg_prediction_offset)

	if enemies_timers:
		if enemies_timers.has_method("set_scatter_time"):
			enemies_timers.set_scatter_time(params["scatter_time"])
		if enemies_timers.has_method("set_chase_time"):
			enemies_timers.set_chase_time(params["chase_time"])
		if enemies_timers.has_method("set_frightened_time"):
			enemies_timers.set_frightened_time(params["frightened_time"])

	pcg_direction_change_cooldown = params["direction_change_cooldown"]
	if enemy_ai and enemy_ai.has_method("set_direction_change_cooldown"):
		enemy_ai.set_direction_change_cooldown(pcg_direction_change_cooldown)

	pcg_spawn_delay = params["spawn_delay"]
	if pcg_spawn_delay > 0:
		self.disable()
		await get_tree().create_timer(pcg_spawn_delay).timeout
		self.enable()

	if enemy_ai is EnemyAIAssassin and params.has("teleport"):
		var assassin_ai := enemy_ai as EnemyAIAssassin
		assassin_ai.apply_pcg_teleport_config(params["teleport"])
