# res://scripts/val/out_val.gd
@tool # Still useful if we ever want to use OutVal as a type hint for exported vars in other resources
class_name OutVal extends Val

## @brief Represents a single output value from a simulation case.
##
## Stores the actual calculated result for a specific output variable
## within a given case, utilizing the raw_data and numeric_data fields
## inherited from the Val base class.

## The raw numerical value produced by the simulation's run step.
var num: float = 0.0

## The potentially mapped value, after applying any num_map defined in an OutVar.
## This could be a string, a different number, or any other data type.
var val: Variant


#region Initialization
## @param p_name The name of the output variable.
## @param p_n_case The case index this output value belongs to.
## @param p_raw_value_for_case The raw output value (e.g., bool, string, float).
## @param p_numeric_value_for_case Optional. A pre-calculated numeric representation (float).
## If NAN or not provided, the base Val class will attempt to derive numeric_data from p_raw_value_for_case.
func _init(p_name: StringName, p_n_case: int, p_raw_value_for_case: Variant, p_numeric_value_for_case: float = NAN):
	super._init(p_name, p_n_case, p_raw_value_for_case, p_numeric_value_for_case) # Call parent constructor
#endregion


#region Public Methods
# No specific public methods needed for OutVal beyond what Val provides currently.
# Specific getters like get_raw_data() and get_numeric_data() are inherited.
# The generic get_value() from Val will return raw_data by default.
#endregion


func _to_string() -> String:
	# Access inherited properties for the string representation
	return "OutVal(name: %s, case: %d, raw: %s, numeric: %s)" % [name, n_case, str(raw_data), str(numeric_data)] 
