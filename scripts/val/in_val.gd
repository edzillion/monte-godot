# res://scripts/val/in_val.gd
@tool
class_name InVal extends RefCounted

## Stores a single input value for a case, including its raw numerical form,
## its potentially mapped value, and the percentile it represents.

## The raw numerical value drawn from the probability distribution.
var raw_value: Variant

## The potentially mapped value, if a num_map was used (e.g., string, different number).
## Defaults to raw_value if no mapping occurs.
var mapped_value: Variant

## The percentile (0.0 to 1.0) that the raw_value represents within its distribution.
## A value of -1.0 can indicate that the percentile was not specifically tracked or sourced
## from a pre-generated list for this InVal instance.
var percentile: float = -1.0 


func _init(p_raw_value: Variant, p_mapped_value: Variant = null, p_percentile: float = -1.0) -> void:
	raw_value = p_raw_value
	if p_mapped_value != null:
		mapped_value = p_mapped_value
	else:
		mapped_value = p_raw_value # Default mapped_value to raw_value if not provided
	percentile = p_percentile


func get_value() -> Variant:
	## Returns the mapped_value if it exists and is different from raw_value,
	## otherwise returns the raw_value. This is often the value used directly by the simulation.
	# This logic might need adjustment based on how you want to prioritize/use mapped_value vs raw_value.
	# For now, let's assume mapped_value is the primary one to get if it was specifically set.
	return mapped_value


func _to_string() -> String:
	return "InVal(num: %s, val: %s, pct: %s)" % [str(raw_value), str(mapped_value), str(percentile)]
 
