# res://scripts/var/out_var.gd
class_name OutVar extends RefCounted

## Aggregates all output values for a specific variable name across all simulation cases.
## It facilitates statistical analysis and data retrieval for a complete set of results
## for one output parameter.

#region Properties
var name: StringName = &"" ## The unique name of this output variable.

## Stores the raw output value for this variable from each case.
## The type of elements can vary (bool, float, string, etc.).
var all_raw_values: Array = []

## Stores the numeric representation (float) of each value in all_raw_values.
## This is used for statistical calculations. Values are mapped/converted.
## Can contain NAN if a raw value couldn't be converted.
var all_numeric_values: Array[float] = []

## Optional: A map to convert specific raw_values to chosen numeric values.
## E.g., {"Pass": 1.0, "Fail": 0.0}
var valmap: Dictionary = {}

## Optional: Inverse of valmap, generated if valmap is used.
## E.g., {1.0: "Pass", 0.0: "Fail"}
var nummap: Dictionary = {}

var first_case_is_median: bool = false ## True if the first value in arrays corresponds to a median case.
var n_cases: int = 0 ## Total number of values (cases) stored.
var n_draws: int = 0 ## Number of stochastic draws (n_cases - 1 if first_case_is_median).

var is_scalar: bool = true ## True if individual output values are scalar (not arrays/dicts).
var max_dim: int = 0     ## Max dimensionality of non-scalar values (0 for scalar).
#endregion


#region Initialization
func _init(p_name: StringName, p_all_raw_values_from_cases: Array, p_valmap_override: Dictionary = {}, p_first_case_is_median: bool = false, p_datasource: String = "") -> void:
	self.name = p_name
	self.all_raw_values = p_all_raw_values_from_cases.duplicate(true) # Deep copy
	self.valmap = p_valmap_override.duplicate(true) # Deep copy
	self.first_case_is_median = p_first_case_is_median

	self.n_cases = self.all_raw_values.size()
	if self.n_cases > 0 and self.first_case_is_median:
		self.n_draws = self.n_cases - 1
	else:
		self.n_draws = self.n_cases
		if self.n_cases == 0 and self.first_case_is_median: # Edge case: asked for median but no data
			self.first_case_is_median = false # Cannot be median if no data

	_process_values_and_maps()
	_determine_dimensionality()
#endregion


#region Internal Helpers
func _process_values_and_maps() -> void:
	if self.valmap.is_empty() and not self.all_raw_values.is_empty():
		var first_val = self.all_raw_values[0]
		# Heuristic: if first non-null value is string, try to build valmap.
		# For booleans, default Val conversion to 1.0/0.0 is often fine.
		# More sophisticated auto-detection could be added.
		var val_to_check = null
		for val_check in self.all_raw_values:
			if val_check != null:
				val_to_check = val_check
				break
		
		if val_to_check != null and typeof(val_to_check) == TYPE_STRING:
			_try_generate_valmap_for_strings()
		elif val_to_check != null and typeof(val_to_check) == TYPE_BOOL and not self.valmap.has(true) and not self.valmap.has(false):
			# If user provided a valmap for booleans, respect it. Otherwise, don't auto-create one here
			# as the Val class itself handles bool -> 1.0/0.0 for numeric_data.
			pass


	if not self.valmap.is_empty():
		_generate_nummap_from_valmap()

	_populate_all_numeric_values()


func _try_generate_valmap_for_strings() -> void:
	# Creates a simple valmap for unique string values, mapping them to floats (0.0, 1.0, ...).
	# Sorts unique strings to ensure deterministic mapping if order matters.
	var unique_strings_set: Dictionary = {} # Use dict as a set for uniqueness
	for raw_val in self.all_raw_values:
		if typeof(raw_val) == TYPE_STRING:
			unique_strings_set[raw_val] = true 
	
	if unique_strings_set.is_empty():
		return

	var sorted_unique_strings: Array = unique_strings_set.keys()
	sorted_unique_strings.sort() # Sort for deterministic mapping

	var next_numeric_val: float = 0.0
	for s_val in sorted_unique_strings:
		self.valmap[s_val] = next_numeric_val
		next_numeric_val += 1.0


func _generate_nummap_from_valmap() -> void:
	self.nummap.clear()
	for key in self.valmap:
		var val = self.valmap[key]
		if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT: # Ensure keys in nummap are numeric
			self.nummap[float(val)] = key
		else:
			push_warning("OutVar '%s': valmap contains non-numeric value '%s' for key '%s'. Cannot create nummap entry." % [self.name, str(val), str(key)])


func _populate_all_numeric_values() -> void:
	self.all_numeric_values.clear()
	self.all_numeric_values.resize(self.n_cases)

	for i in range(self.n_cases):
		var raw_val = self.all_raw_values[i]
		var numeric_val_candidate: float = NAN # Default to NAN

		if not self.valmap.is_empty() and self.valmap.has(raw_val):
			var mapped_val = self.valmap[raw_val]
			if typeof(mapped_val) == TYPE_FLOAT or typeof(mapped_val) == TYPE_INT:
				numeric_val_candidate = float(mapped_val)
			else:
				push_warning("OutVar '%s': valmap for raw value '%s' did not produce a number. Got '%s'." % [self.name, str(raw_val), str(mapped_val)])
		elif typeof(raw_val) == TYPE_BOOL:
			numeric_val_candidate = 1.0 if bool(raw_val) else 0.0
		elif typeof(raw_val) == TYPE_INT or typeof(raw_val) == TYPE_FLOAT:
			numeric_val_candidate = float(raw_val)
		
		self.all_numeric_values[i] = numeric_val_candidate


func _determine_dimensionality() -> void:
	self.is_scalar = true
	self.max_dim = 0
	if self.all_raw_values.is_empty():
		return

	for raw_val in self.all_raw_values:
		if raw_val == null: # Skip null values for dimensionality check
			continue
		var val_type: int = typeof(raw_val)
		if val_type == TYPE_ARRAY or val_type == TYPE_OBJECT: # TYPE_DICTIONARY is TYPE_OBJECT
			self.is_scalar = false
			self.max_dim = 1 # Simple indication of non-scalar
			# Further inspection (e.g., array[0] type, dict value types) could refine max_dim.
			break
#endregion


#region Public Methods
## @brief Retrieves an OutVal representation for a specific case index.
func get_outval_for_case(p_case_idx: int) -> OutVal:
	if p_case_idx < 0 or p_case_idx >= self.n_cases:
		push_error("OutVar '%s': Case index %d is out of bounds (%d cases)." % [self.name, p_case_idx, self.n_cases])
		return null

	var raw_value_for_case = self.all_raw_values[p_case_idx]
	var numeric_value_for_case: float = self.all_numeric_values[p_case_idx]

	# The OutVal constructor expects: name, n_case, raw_data, numeric_data_override (optional)
	return OutVal.new(self.name, p_case_idx, raw_value_for_case, numeric_value_for_case)


## @brief Returns a duplicate of all numeric values. Useful for direct statistical processing.
func get_all_numeric_values() -> Array[float]:
	return self.all_numeric_values.duplicate()


## @brief Returns a duplicate of all raw values.
func get_all_raw_values() -> Array:
	return self.all_raw_values.duplicate(true) # Deep copy if values can be complex


## @brief Calculates and returns basic statistics for the numeric values of this OutVar.
## Requires EZSTATS
## @return A Dictionary containing mean, median, std_dev, variance, min, max, or empty if stats cannot be calculated.
func calculate_stats() -> Dictionary:
	var stats_results: Dictionary = {}
	# The 'dof' parameter in EZSTATS is used for snapping (rounding) results.
	# It determines the step for godot_api.snapped(). 
	# E.g., 0.01 for 2 decimal places, 0.001 for 3 decimal places.
	var precision_step: float = 0.001 # Default to 3 decimal places
	var sanitized_results = EZSTATS.sanitize(self.all_numeric_values)
	stats_results = EZSTATS.all(sanitized_results, precision_step)
	
	# The keys in the dictionary returned by EZSTATS.all() are:
	# "Mean", "Median", "Spread", "Minima", "Maxima", "Variance", "Standev", "Mad"
	# We might want to add "Count" manually if not included by EZSTATS.all directly.
	if not stats_results.has("Count") and not stats_results.has("count"):
		stats_results["Count"] = sanitized_results.size()
		
	return stats_results
#endregion 
