# res://src/utils/utils.gd
# class_name Utils # Not making it a class_name initially, to be used as an autoload
extends Node

## @brief General-purpose utility functions for the MonteGodot library.
## This script is intended to be used as an Autoload (singleton).

#region Static Methods


## @brief A safe way to get a value from a dictionary.
## Returns a default value if the key is not found or if the dictionary is null.
static func get_safe(dict: Dictionary, key: Variant, default_value: Variant = null) -> Variant:
	if dict == null or not dict is Dictionary:
		return default_value
	if dict.has(key):
		return dict[key]
	return default_value

#endregion 
