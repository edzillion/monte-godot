@tool
extends EditorPlugin

func _enable_plugin() -> void:
	add_autoload_singleton("EZSTATS", "res://addons/ez_stats/ezstats.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("EZSTATS")
