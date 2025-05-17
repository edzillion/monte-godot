# res://src/core/out_var.gd
class_name OutVar extends Var

## @brief Represents an output variable in the simulation.
##
## Extends Var to define variables that store the results or outcomes
## of the simulation runs.

#region Properties
## Stores the array of ncases output values (OutVal objects) after postprocessing.
var result_values: Array[OutVal] = []
#endregion


#region Initialization
func _init(p_id: StringName, p_name: String, p_description: String = "", p_units: String = "") -> void:
	super(p_id, p_name, p_description, p_units)
#endregion


#region Public Methods
## @brief Adds a processed output value for a specific case.
## This would typically be called from the postprocess stage.
func add_result_value(value: OutVal) -> void:
	result_values.append(value)


## @brief Clears all stored result values.
func clear_results() -> void:
	result_values.clear()


## @brief Gets a specific result value by index.
func get_result_value(case_idx: int) -> OutVal:
	if case_idx >= 0 and case_idx < result_values.size():
		return result_values[case_idx]
	push_warning("Requested result value index %d is out of bounds for OutVar '%s'." % [case_idx, name])
	return null
#endregion 