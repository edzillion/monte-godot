class_name PiJobFunctions extends RefCounted

# Preprocessing function for the Pi estimation job
func _preprocess(case: Case) -> Array[float]:
	var inval_x: InVal = case.get_input_value(0)
	var inval_y: InVal = case.get_input_value(1)
	if inval_x == null or inval_y == null:
		printerr("PiJobFunctions: _preprocess - Failed to get input values from Case.")
		return [0.0, 0.0] # Return default or handle error appropriately
	return [inval_x.get_value(), inval_y.get_value()]


# Run function for the Pi estimation job
func _run(case_args: Array) -> Array[bool]:
	if case_args == null or case_args.size() < 2:
		printerr("PiJobFunctions: _run - Invalid case_args provided.")
		return [false] # Return default or handle error
	var x: float = case_args[0]
	var y: float = case_args[1]
	var is_inside_circle: bool = (x * x + y * y) <= 1.0
	return [is_inside_circle]


# Postprocessing function for the Pi estimation job
func _postprocess(case_obj: Case, run_results: Array[bool]) -> void:
	if case_obj == null or run_results == null or run_results.is_empty():
		printerr("PiJobFunctions: _postprocess - Invalid arguments provided.")
		return
	var out_val_is_inside: OutVal = OutVal.new(&"is_inside", case_obj.id, run_results[0])
	case_obj.add_output_value(out_val_is_inside)
