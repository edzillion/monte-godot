# res://scripts/case/case.gd
class_name Case extends RefCounted

## Represents a single simulation run (case) with its own set of input and output values.

var id: int
var case_seed: int
var input_values: Array[InVal]
var output_values: Array[Variant] = []


func _init(p_id: int, p_seed: int = 0) -> void:
	id = p_id
	# If p_seed is 0, use a fixed default. Meaningful seed should be provided by caller if reproducibility is desired.
	case_seed = p_seed if p_seed != 0 else 1


func add_input_value(value: InVal) -> void:
	input_values.append(value)


func get_input_value(index: int) -> InVal:
	return input_values[index]


func add_output_value(value: Variant) -> void:
	output_values.append(value)


func get_output_values() -> Array[Variant]:
	return output_values.duplicate()


func clear_outputs() -> void:
	output_values.clear() 
