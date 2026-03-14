extends EnemyAI
class_name EnemyAIBourrin


func __update_chase_target_position() -> void:
	chase_target_position = chase_target.global_position


var elroy_mode_enabled: bool = false

# @override
func on_scattered() -> void:
	if self.elroy_mode_enabled:
		self.set_state(self.States.CHASE)
		return
	
	set_destination_location(DestinationLocations.SCATTER_AREA)
	go_to_first_scatter_point()

func set_prediction_offset(value: int) -> void:
	prediction_offset = value

func set_scatter_time(value: float) -> void:
	scatter_duration = value
