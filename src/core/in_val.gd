# res://src/core/in_val.gd
class_name InVal extends Val

## @brief Represents a single input value for a specific case.
##
## Inherits from Val and is used to store the actual input data point
## fed into a simulation run.

#region Initialization
func _init(p_num_value: Variant = null, p_mapped_value: Variant = null) -> void:
	super(p_num_value, p_mapped_value)
	# Additional InVal-specific initialization can go here if needed in the future
#endregion 
 
