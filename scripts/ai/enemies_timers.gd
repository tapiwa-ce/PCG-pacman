extends Node
class_name EnemiesTimers

var default_scatter_time: float = 0.0

@onready var pellets: Pellets = get_tree().get_root().get_node("Level/Pickables/Pellets")

@onready var scatter_timer: Timer = $ScatterDurationTimer
@onready var chase_timer: Timer = $ChaseDurationTimer
@onready var frightened_timer: Timer = $FrightenedDurationTimer


func stop_all_timers() -> void:
	for timer in self.get_children():
		timer.stop()


func on_power_pellet_picked_up(_value: int) -> void:
	self.frightened_timer.start()


func on_player_died() -> void:
	self.stop_all_timers()


func on_game_over() -> void:
	self.stop_all_timers()
	
# Called from Enemy.init_from_pcg() to adjust scatter duration procedurally.
func set_scatter_time(value: float) -> void:
	default_scatter_time = max(1.0, value)  # safety clamp
	scatter_timer.wait_time = default_scatter_time
	
func set_chase_time(value: float) -> void:
	chase_timer.wait_time = max(2.0, value)

func set_frightened_time(value: float) -> void:
	frightened_timer.wait_time = max(1.0, value)

func _ready() -> void:
	# Store whatever was set in the scene as the baseline.
	default_scatter_time = scatter_timer.wait_time
	
	pellets.power_pellet_picked_up.connect(on_power_pellet_picked_up)
	
	Global.player_died.connect(on_player_died)
	Global.game_over.connect(on_game_over)


func _on_scatter_duration_timer_timeout() -> void:
	chase_timer.start()


func _on_chase_duration_timer_timeout() -> void:
	scatter_timer.start()
