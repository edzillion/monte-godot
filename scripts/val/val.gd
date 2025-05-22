# res://scripts/val/val.gd
class_name Val extends RefCounted

## @brief Abstract base class for all values (input and output).
##
## This class forms the basis for InVal and OutVal, representing single data points
## within a simulation case.

#region Properties
var name: StringName = &""
var n_case: int = -1 # The case index this value belongs to.

## The original, raw data value. Can be any variant type (bool, string, float, int, etc.).
var raw_data: Variant 

## The processed numeric representation of the data, primarily for statistical calculations.
## This is always a float. It might be NAN if conversion from raw_data is not possible or defined.
var numeric_data: float = NAN
#endregion


#region Initialization
## @param p_name The name of the variable this value is associated with.
## @param p_n_case The case index (0-based) this value pertains to.
## @param p_raw_data The original raw value.
## @param p_numeric_data_override Optional. If provided and not NAN, this value will be used for numeric_data.
## Otherwise, an attempt will bemade to convert p_raw_data to a float.
func _init(p_name: StringName, p_n_case: int, p_raw_data: Variant, p_numeric_data_override: float = NAN) -> void:
	self.name = p_name
	self.n_case = p_n_case
	self.raw_data = p_raw_data

	if not is_nan(p_numeric_data_override):
		self.numeric_data = p_numeric_data_override
	else:
		if typeof(p_raw_data) == TYPE_BOOL:
			self.numeric_data = 1.0 if bool(p_raw_data) else 0.0
		elif typeof(p_raw_data) == TYPE_INT or typeof(p_raw_data) == TYPE_FLOAT:
			self.numeric_data = float(p_raw_data)
		# else, numeric_data remains NAN if no direct conversion or override
#endregion


#region Public Methods
## @brief Gets the primary, typically raw, value.
func get_value() -> Variant:
	return raw_data

## @brief Gets the original raw data value.
func get_raw_data() -> Variant:
	return raw_data

## @brief Sets the raw data value. Also attempts to update numeric_data unless it was overridden.
func set_raw_data(p_raw_data: Variant) -> void:
	self.raw_data = p_raw_data
	# Re-evaluate numeric_data if it wasn't explicitly set by an override
	# This logic assumes that if numeric_data was NAN, it means it was auto-derived.
	# If it was some other float, it means it was explicitly set or overridden.
	# A more robust way might be to have a flag like `_numeric_data_was_overridden`.
	# For now, a simple re-evaluation if it's NAN or matches the default conversion.
	var re_evaluate_numeric: bool = false
	if is_nan(self.numeric_data):
		re_evaluate_numeric = true
	else:
		# Check if current numeric_data corresponds to default conversion of old raw_data (if any)
		# This is imperfect. A flag `_numeric_overridden` would be better.
		# For now, if numeric_data is not NAN, assume it was intentional or from override.
		# We only auto-update if it *was* NAN.
		pass # Do not automatically change numeric_data if it has a non-NAN value
		
	if re_evaluate_numeric:
		if typeof(p_raw_data) == TYPE_BOOL:
			self.numeric_data = 1.0 if bool(p_raw_data) else 0.0
		elif typeof(p_raw_data) == TYPE_INT or typeof(p_raw_data) == TYPE_FLOAT:
			self.numeric_data = float(p_raw_data)
		else:
			self.numeric_data = NAN


## @brief Gets the processed numeric value (float). Could be NAN.
func get_numeric_data() -> float:
	return numeric_data

## @brief Explicitly sets the numeric data value.
func set_numeric_data(p_numeric_data: float) -> void:
	self.numeric_data = p_numeric_data

## @brief Resets the Val object to a default state for reuse in an object pool.
func reset() -> void:
	name = &""
	n_case = -1
	raw_data = null
	numeric_data = NAN
#endregion 
 
