extends EnemyAI
class_name EnemyAICornichon


func __update_chase_target_position() -> void:
	if enemy.global_position.distance_to(chase_target_position) <= tile_size * 8:
		set_destination_location(DestinationLocations.RANDOM_LOCATION)
	else:
		chase_target_position = chase_target.global_position

func set_prediction_offset(value: int) -> void:
	prediction_offset = value

func set_scatter_time(value: float) -> void:
	scatter_duration = value
