# res://scripts/val/out_val.gd
@tool # Still useful if we ever want to use OutVal as a type hint for exported vars in other resources
class_name OutVal extends Val

## Stores a single output value from a simulation case.

## The raw numerical value produced by the simulation's run step.
var num: float = 0.0

## The potentially mapped value, after applying any num_map defined in an OutVar.
## This could be a string, a different number, or any other data type.
var val: Variant


func _init(p_num: float = 0.0, p_val: Variant = null) -> void:
	num = p_num
	if p_val != null:
		val = p_val
	else:
		# If no specific mapped value is provided, default to the raw numerical value.
		val = p_num


func _to_string() -> String:
	return "OutVal(num: %s, val: %s)" % [str(num), str(val)] 