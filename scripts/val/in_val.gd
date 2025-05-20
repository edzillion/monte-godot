# res://scripts/val/in_val.gd
class_name InVal extends Val

## @brief Represents a single input value for a specific case.
##
## Inherits from Val and is used to store the actual input data point
## fed into a simulation run.

# Note: mapped_value is inherited from Val and initialized by super().

#region Initialization
func _init(p_num_value: Variant = null, p_mapped_value: Variant = null) -> void:
	# Val._init now handles both p_num_value and p_mapped_value.
	super._init(p_num_value, p_mapped_value)
	
	# Additional InVal-specific initialization can go here if needed in the future.
	# For instance, if InVal needed to further process mapped_value after Val sets it.
#endregion 
 
