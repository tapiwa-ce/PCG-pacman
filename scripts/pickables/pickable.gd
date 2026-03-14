extends Area2D
class_name Pickable

# ---------------------------------------------------------
# BASIC FIELDS (already existed)
# ---------------------------------------------------------
@export var score_value: int = 0
@export_file("*.ogg", "*.wav") var sound_file_path: String = ""

signal picked_up(value: int)

var is_rare: bool = false

func _ready() -> void:
	assert(self.score_value > 0)
	assert(FileAccess.file_exists(sound_file_path))
	
	if is_rare:
		self.modulate = Color(1.0, 0.84, 0.0)


func _on_area_entered(_area: Area2D) -> void:
	# ---------------------------------------------------------
	# 1. Emit normal pellet pickup score
	# ---------------------------------------------------------
	self.picked_up.emit(self.score_value)

	# ---------------------------------------------------------
	# 2. Play normal pellet sound
	# ---------------------------------------------------------
	AudioManager.play_sound_file(sound_file_path, AudioManager.TrackTypes.PICKUPS)

	# ---------------------------------------------------------
	# 3. RARE PELLET CHECK
	# ---------------------------------------------------------
	# PCGManager marks rare pellets with metadata "is_rare_pellet"
	if self.has_meta("is_rare_pellet") and self.get_meta("is_rare_pellet") == true:
		# Inform Global.gd that a rare pellet was picked
		Global.on_rare_pellet_picked()

	# ---------------------------------------------------------
	# 4. Remove pellet
	# ---------------------------------------------------------
	self.queue_free()
