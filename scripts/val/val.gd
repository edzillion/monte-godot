# res://scripts/val/val.gd
class_name Val extends RefCounted

## @brief Abstract base class for all values (input and output).
##
## This class forms the basis for InVal and OutVal, representing single data points
## within a simulation case.

#region Properties
## The raw numerical value, if applicable. Can be float, int, or other numeric types.
var num_value: Variant 
## The mapped or categorical value, can be any type.
var mapped_value: Variant 
### The ID of the InVar or OutVar this value is associated with.
#var variable_id: StringName = &""
#endregion


#region Initialization
func _init(p_num_value: Variant = null, p_mapped_value: Variant = null) -> void: # p_variable_id: StringName = &""
	if p_num_value == null:
		num_value = null
	elif typeof(p_num_value) == TYPE_INT or typeof(p_num_value) == TYPE_FLOAT:
		num_value = float(p_num_value)
	else:
		num_value = p_num_value # For strings or other types, store as-is
	mapped_value = p_mapped_value
	#variable_id = p_variable_id
#endregion


#region Public Methods
## @brief Gets the primary value. Prioritizes mapped_value if available, otherwise num_value.
func get_value() -> Variant:
	if mapped_value != null:
		return mapped_value
	return num_value

## @brief Gets the original numeric value, before any mapping.
func get_numeric_value() -> Variant:
	return num_value

## @brief Resets the Val object to a default state for reuse in an object pool.
func reset() -> void:
	num_value = null
	mapped_value = null
	# variable_id = &""
#endregion 
 
