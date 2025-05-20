# src/core/case.gd
class_name Case extends RefCounted

## Represents a single simulation run (case) with its own set of input and output values.

var id: int
## The unique identifier for this case within its job.

var case_seed: int
## A seed value for this case, allowing for reproducible randomness if used by the run_callable.

var input_values: Dictionary = {}
## Stores input values for the case, typically populated before the preprocess step
## or by the InVar generation mechanism. Keys are usually StringNames representing variable names.

var output_values: Array[Variant] = []
## Stores output values for the case, typically populated during the postprocess step.
## The structure of this array depends on how `add_output_value` is used.


func _init(p_id: int, p_seed: int = 0) -> void:
	id = p_id
	# If p_seed is 0, use a fixed default. Meaningful seed should be provided by caller if reproducibility is desired.
	case_seed = p_seed if p_seed != 0 else 1


func add_input_value(key: StringName, value: Variant) -> void:
	input_values[key] = value


func get_input_value(key: StringName, default_value: Variant = null) -> Variant:
	return input_values.get(key, default_value)


func add_output_value(value: Variant) -> void:
	## Adds a value to the list of outputs for this case.
	## In the original Monaco, this would be `Case.addOutVal(val)`.
	output_values.append(value)


func get_output_values() -> Array[Variant]:
	return output_values.duplicate()


func clear_outputs() -> void:
	output_values.clear() 
