# res://scripts/val/out_val.gd
@tool # Still useful if we ever want to use OutVal as a type hint for exported vars in other resources
class_name OutVal extends Val

## @brief Represents a single output value from a simulation case.
##
## Stores the actual calculated result for a specific output variable
## within a given case.

## The raw numerical value produced by the simulation's run step.
var num: float = 0.0

## The potentially mapped value, after applying any num_map defined in an OutVar.
## This could be a string, a different number, or any other data type.
var val: Variant


#region Initialization
func _init(p_name: StringName, p_n_case: int, p_output_value: Variant):
	# The super._init(p_name, p_n_case) is called by the .(p_name, p_n_case) syntax
	self.num_value = p_output_value
	# mapped_value will remain null unless explicitly set or a valmap is implemented.
#endregion


#region Public Methods
# No specific methods needed for OutVal yet, base Val methods are sufficient.
# func get_value() -> Variant:
#   return self.num_value # Base Val.get_value() already does this if mapped_value is null
#endregion


func _to_string() -> String:
	return "OutVal(num: %s, val: %s)" % [str(num), str(val)] 
