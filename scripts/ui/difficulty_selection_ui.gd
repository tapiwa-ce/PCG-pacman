"""
Author - Ajay Ludher
Difficulty selector screen for Pac-Man style game.
Handles button presses for Easy, Medium, Hard difficulties.
Stores the selected difficulty globally so it can be used for PCG and enemy AI setup.
"""

extends Control
class_name DifficultySelectionUI

# When a button is pressed, save the difficulty and switch to the main menu scene.

func _on_easy_button_pressed() -> void:
	Global.selected_difficulty = "Easy"
	print("Difficulty selected: Easy")
	get_tree().change_scene_to_file("res://scenes/ui/main_menu_ui.tscn")

func _on_medium_button_pressed() -> void:
	Global.selected_difficulty = "Medium"
	print("Difficulty selected: Medium")
	get_tree().change_scene_to_file("res://scenes/ui/main_menu_ui.tscn")

func _on_hard_button_pressed() -> void:
	Global.selected_difficulty = "Hard"
	print("Difficulty selected: Hard")
	get_tree().change_scene_to_file("res://scenes/ui/main_menu_ui.tscn")
