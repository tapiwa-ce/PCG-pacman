extends CharacterBody2D
class_name Player

# ---------------------------------------------------------
# BASE VARIABLES
# ---------------------------------------------------------
@export var speed: float = 150.0
@export var spawn_point: Marker2D = null

var spawn_position: Vector2 = Vector2(0.0, 0.0)

var movement_input_vector: Vector2 = Vector2(0, 0)
var initial_direction: Vector2 = Vector2(1, 0)
var direction: Vector2 = initial_direction
var next_direction: Vector2 = direction

# ---------------------------------------------------------
# RARE PELLET SPEED BUFF VARIABLES
# ---------------------------------------------------------
var base_speed: float = 150.0        # original movement speed
var speed_multiplier: float = 1.0    # modified by rare pellet buff
var buff_active: bool = false        # internal tracking


# ---------------------------------------------------------
# INPUT HANDLING
# ---------------------------------------------------------
func _unhandled_key_input(_event: InputEvent) -> void:
	movement_input_vector = Vector2.ZERO
	
	movement_input_vector.x = Input.get_axis("move_left", "move_right")
	if movement_input_vector.x != 0:
		return
	
	movement_input_vector.y = Input.get_axis("move_up", "move_down")


# ---------------------------------------------------------
# NODE REFERENCES
# ---------------------------------------------------------
@onready var next_direction_detector: Node2D = $NextDirectionRotator/NextDirectionDetector
@onready var next_direction_rotator: Node2D = $NextDirectionRotator
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var anim_node_sm_playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var hurt_box: HurtBox = $HurtBox
@onready var shared_enemy_ai: SharedEnemyAI = get_tree().get_root().get_node("Level/SharedEnemyAI")


# ---------------------------------------------------------
# CHECK IF NEXT DIRECTION IS FREE
# ---------------------------------------------------------
func can_go_in_next_direction() -> bool:
	for raycast in next_direction_detector.get_children():
		if raycast.is_colliding():
			return false
	return true


# ---------------------------------------------------------
# ENABLE / DISABLE PLAYER
# ---------------------------------------------------------
func enable() -> void:
	self.set_physics_process(true)
	self.set_process_unhandled_key_input(true)
	hurt_box.enable()

func disable() -> void:
	self.set_physics_process(false)
	self.set_process_unhandled_key_input(false)
	hurt_box.disable()


# ---------------------------------------------------------
# DEATH / ANIMATION EVENTS
# ---------------------------------------------------------
func die() -> void:
	self.disable()
	Global.decrease_lives()
	anim_node_sm_playback.travel("die")

func _on_animation_tree_animation_finished(anim_name: StringName) -> void:
	if anim_name == "die":
		Global.player_finished_dying.emit()


# ---------------------------------------------------------
# GAME STATE SIGNAL CALLBACKS
# ---------------------------------------------------------
func on_game_ready() -> void:
	animation_tree.set("parameters/idle/blend_position", next_direction)
	anim_node_sm_playback.travel("idle")

func on_game_started() -> void:
	self.enable()

func on_level_cleared() -> void:
	self.disable()
	animation_tree.set("parameters/idle/blend_position", next_direction)
	anim_node_sm_playback.travel("idle")

func on_finished_dying() -> void:
	if Global.is_game_over:
		return
	self.set_global_position(self.spawn_position)


# ---------------------------------------------------------
# RARE PELLET BUFF SIGNAL CALLBACKS
# ---------------------------------------------------------
func _on_buff_started(mult: float, _duration: float) -> void:
	"""
	Triggered by Global.rare_pellet_buff_started(multiplier, duration)
	"""
	buff_active = true
	speed_multiplier = mult
	_update_speed()

func _on_buff_ended() -> void:
	"""
	Triggered by Global.rare_pellet_buff_ended()
	"""
	buff_active = false
	speed_multiplier = 1.0
	_update_speed()

func _update_speed() -> void:
	# Keeps logic clean and centralized
	speed = base_speed * speed_multiplier


# ---------------------------------------------------------
# READY
# ---------------------------------------------------------
func _ready() -> void:
	# Store original speed
	base_speed = speed

	if spawn_point != null:
		spawn_position = spawn_point.global_position
	
	# GAME STATE SIGNALS
	Global.game_ready.connect(on_game_ready)
	Global.game_started.connect(on_game_started)
	Global.level_cleared.connect(on_level_cleared)
	Global.player_finished_dying.connect(on_finished_dying)
	
	# RARE PELLET SIGNALS
	Global.rare_pellet_buff_started.connect(_on_buff_started)
	Global.rare_pellet_buff_ended.connect(_on_buff_ended)
	Global.rare_pellet_bonus_display_requested.connect(_on_rare_bonus_popup)

	animation_tree.active = true
	self.disable()

func _on_rare_bonus_popup(value: int) -> void:
	if Global.is_game_over:
		return

	var display_scene: PackedScene = shared_enemy_ai.numbers_displayer_scene
	if display_scene == null:
		return

	var inst: NumbersDisplayer = display_scene.instantiate()
	inst.color = Color(1.0, 0.84, 0.0)  # Golden text
	inst.set_text("+" + str(value))
	inst.set_global_position(self.global_position)

	get_tree().get_root().add_child(inst)

# ---------------------------------------------------------
# MOVEMENT + ANIMATION LOOP
# ---------------------------------------------------------
func _physics_process(_delta: float) -> void:
	# Can we rotate / move to next direction?
	if can_go_in_next_direction():
		direction = next_direction
	
	# INPUT ROTATION UPDATE
	if movement_input_vector != Vector2.ZERO:
		next_direction = movement_input_vector

		if next_direction.x == -1:
			next_direction_rotator.rotation = deg_to_rad(180)
		elif next_direction.x == 1:
			next_direction_rotator.rotation = deg_to_rad(0)
		elif next_direction.y == -1:
			next_direction_rotator.rotation = deg_to_rad(-90)
		elif next_direction.y == 1:
			next_direction_rotator.rotation = deg_to_rad(90)
	
	# ANIMATIONS
	if velocity != Vector2.ZERO:
		animation_tree.set("parameters/move/blend_position", velocity)
		anim_node_sm_playback.travel("move")
	else:
		animation_tree.set("parameters/idle/blend_position", next_direction)
		anim_node_sm_playback.travel("idle")
	
	# MOVEMENT
	self.velocity = direction * speed
	self.move_and_slide()
