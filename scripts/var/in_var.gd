# res://scripts/var/in_var.gd
@tool
class_name InVar extends Resource

#region Properties
var ndraws: int = 0 ## The number of random draws.
var var_idx: int = -1 ## The number/index of this input variable.
var percentiles: Array[float] = [] ## Stores the pre-generated percentiles for this variable for all cases.
#endregion

#region Enums
## @brief Defines the type of probability distribution for the input variable.
enum DistributionType {
	UNIFORM,      # params: {"a": float, "b": float}
	NORMAL,       # params: {"mean": float, "std_dev": float}
	BERNOULLI,    # params: {"p": float} (output 0.0 or 1.0)
	BINOMIAL,     # params: {"n": int, "p": float}
	POISSON,      # params: {"lambda": float}
	EXPONENTIAL,  # params: {"lambda": float}
	GEOMETRIC,    # params: {"p": float}
	ERLANG,       # params: {"k": int, "lambda": float}
	HISTOGRAM,    # params: {"values": Array[float], "probabilities": Array[float]}
	PSEUDO_RANDOM,# params: {"c": float}
	SAMPLE_WITHOUT_REPLACEMENT, # params: {"deck_size": int, "sample_count": int, "sample_method_param": SamplingGen.SamplingMethod}
	CUSTOM        # params: Uses num_map directly or custom logic with distribution_params.
}

var sample_method: StatMath.SamplingGen.SamplingMethod = StatMath.SamplingGen.SamplingMethod.RANDOM ## The random sampling method to use.
#endregion

#region Exported Variables
@export_category("Description")
@export var name: StringName ## User-friendly name for the variable.
@export var description: String ## A more detailed description of what the variable represents.

@export var distribution_type: DistributionType = DistributionType.UNIFORM:
	set(value):
		distribution_type = value
		_update_distribution_info()
		_update_dict_from_exported_fields()
		if Engine.is_editor_hint():
			notify_property_list_changed()

@export_category("Distribution Info")
@export var distribution_info: String = ""

@export_category("Uniform Parameters")
@export var uniform_a: float = 0.0
@export var uniform_b: float = 1.0

@export_category("Normal Parameters")
@export var normal_mean: float = 0.0
@export var normal_std_dev: float = 1.0

@export_category("Bernoulli Parameters")
@export var bernoulli_p: float = 0.5

@export_category("Binomial Parameters")
@export var binomial_n: int = 1
@export var binomial_p: float = 0.5

@export_category("Poisson Parameters")
@export var poisson_lambda: float = 1.0

@export_category("Exponential Parameters")
@export var exponential_lambda: float = 1.0

@export_category("Geometric Parameters")
@export var geometric_p: float = 0.5

@export_category("Erlang Parameters")
@export var erlang_k: int = 1
@export var erlang_lambda: float = 1.0

@export_category("Histogram Parameters")
@export var histogram_values: Array[float] = []
@export var histogram_probabilities: Array[float] = []

@export_category("Pseudo-Random Parameters")
@export var pseudo_c: float = 0.1

@export_category("Sample Without Replacement Parameters")
@export var swr_deck_size: int = 52
@export var swr_sample_count: int = 5
@export var swr_actual_method: StatMath.SamplingGen.SamplingMethod = StatMath.SamplingGen.SamplingMethod.FISHER_YATES

#endregion

## @brief Optional mapping of numerical values to other data types (e.g., strings, objects).
var num_map: Dictionary = {}

# Stores parameters when distribution_type is CUSTOM or for initial programmatic setup.
var distribution_params: Dictionary = {}
var _nums: Array[float] = [] ## Stores the raw numerical values generated from percentiles.


func _init(
	p_name: StringName = &"", 
	p_distribution_type: DistributionType = DistributionType.UNIFORM, 
	p_distribution_params: Dictionary = {},
	p_description: String = "",
	p_ndraws: int = 0,
	p_sample_method: StatMath.SamplingGen.SamplingMethod = StatMath.SamplingGen.SamplingMethod.RANDOM,
	p_var_idx: int = -1,
	p_percentiles: Array[float] = []
	) -> void:
	self.resource_name = p_name
	self.description = p_description
	self.ndraws = p_ndraws
	self.sample_method = p_sample_method
	self.var_idx = p_var_idx
	
	distribution_type = p_distribution_type # Set early
	self.percentiles = p_percentiles.duplicate() # Store a copy
	
	if not p_distribution_params.is_empty():
		distribution_params = p_distribution_params.duplicate()
		_update_exported_fields_from_dict(distribution_params)
	else:
		_update_dict_from_exported_fields()

	generate_all_values()

	set_distribution_type(p_distribution_type) # Call full setter


func set_distribution_type(value: DistributionType) -> void:
	distribution_type = value
	_update_distribution_info()
	_update_dict_from_exported_fields()
	if Engine.is_editor_hint():
		notify_property_list_changed()


func get_value(p_case_idx: int) -> InVal:
	var debug_mode: bool = ProjectSettings.get_setting("monte_carlo/debug_mode", false)

	_update_dict_from_exported_fields() # Ensure params are fresh from editor changes

	if distribution_type == DistributionType.SAMPLE_WITHOUT_REPLACEMENT:
		var deck_size: int = distribution_params.get("deck_size", 52)
		var sample_count: int = distribution_params.get("sample_count", 5)
		var config_sample_method_val = distribution_params.get("sample_method_param", StatMath.SamplingGen.SamplingMethod.FISHER_YATES)
		
		var actual_sample_method_to_use: StatMath.SamplingGen.SamplingMethod
		if config_sample_method_val is StatMath.SamplingGen.SamplingMethod: # If it's already the enum type
			actual_sample_method_to_use = config_sample_method_val
		elif config_sample_method_val is int and StatMath.SamplingGen.SamplingMethod.values().has(config_sample_method_val):
			actual_sample_method_to_use = config_sample_method_val
		else:
			push_warning("InVar '%s': Invalid 'sample_method_param' (%s) in distribution_params for SAMPLE_WITHOUT_REPLACEMENT. Defaulting to FISHER_YATES." % [resource_name, str(config_sample_method_val)])
			actual_sample_method_to_use = StatMath.SamplingGen.SamplingMethod.FISHER_YATES

		if deck_size <= 0 or sample_count <= 0 or sample_count > deck_size:
			var err_msg_swr = "InVar '%s': Invalid 'deck_size' (%d) or 'sample_count' (%d) for SAMPLE_WITHOUT_REPLACEMENT." % [resource_name, deck_size, sample_count]
			push_error(err_msg_swr)
			if debug_mode: assert(false, err_msg_swr)
			return null

		var raw_val_array: Array[int] = StatMath.SamplingGen.draw_without_replacement(deck_size, sample_count, actual_sample_method_to_use)
		var mapped_val_output: Array = [] # This will hold the final mapped values or raw values if no map

		if not num_map.is_empty():
			for item_idx in raw_val_array:
				if num_map.has(item_idx):
					mapped_val_output.append(num_map[item_idx])
				else:
					mapped_val_output.append(item_idx) # Keep raw item if no map entry for it
			return InVal.new(raw_val_array, mapped_val_output, -1.0)
		else:
			# No num_map, so mapped_val_output should be the raw_val_array itself.
			return InVal.new(raw_val_array, raw_val_array, -1.0)

	# Original logic for other distribution types that use pre-generated _nums
	if _nums.is_empty() and not percentiles.is_empty():
		push_warning("InVar '%s': get_value() called but _nums is empty for non-SWR type. Did you forget to call generate_all_values()? Attempting to generate now." % resource_name)
		generate_all_values()
		if _nums.is_empty() and ndraws > 0:
			push_error("InVar '%s': Failed to populate _nums for non-SWR type. Check percentile data and ndraws." % resource_name)
			if debug_mode: assert(false, "InVar '%s': _nums empty after generation attempt for non-SWR type." % resource_name)
			return InVal.new(0.0, 0.0, -1.0)

	if p_case_idx < 0 or p_case_idx >= _nums.size():
		var err_msg = "InVar '%s': Case index %d is out of bounds for _nums (size: %d) for non-SWR type." % [resource_name, p_case_idx, _nums.size()]
		push_error(err_msg)
		if debug_mode: assert(false, err_msg)
		return InVal.new(0.0, 0.0, -1.0)

	var raw_num_single: float = _nums[p_case_idx]
	var raw_pct_single: float = -1.0

	if p_case_idx < 0 or p_case_idx >= percentiles.size():
		var err_msg_pct = "InVar '%s': Case index %d is out of bounds for percentiles array (size: %d) for non-SWR type. Cannot retrieve percentile." % [resource_name, p_case_idx, percentiles.size()]
		push_warning(err_msg_pct)
	else:
		raw_pct_single = percentiles[p_case_idx]

	var mapped_val_single: Variant = raw_num_single
	if not num_map.is_empty():
		if num_map.has(raw_num_single): # This assumes num_map keys are appropriate for float values for other types
			mapped_val_single = num_map[raw_num_single]
	
	return InVal.new(raw_num_single, mapped_val_single, raw_pct_single)


func _update_distribution_info() -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			distribution_info = "Uniform params: {a: float, b: float}"
		DistributionType.NORMAL:
			distribution_info = "Normal params: {mean: float, std_dev: float}"
		DistributionType.BERNOULLI:
			distribution_info = "Bernoulli param: {p: float (0.0-1.0)}"
		DistributionType.BINOMIAL:
			distribution_info = "Binomial params: {n: int >= 0, p: float (0.0-1.0)}"
		DistributionType.POISSON:
			distribution_info = "Poisson param: {lambda: float >= 0}"
		DistributionType.EXPONENTIAL:
			distribution_info = "Exponential param: {lambda: float > 0}"
		DistributionType.GEOMETRIC:
			distribution_info = "Geometric param: {p: float (0.0-1.0)}"
		DistributionType.ERLANG:
			distribution_info = "Erlang params: {k: int > 0, lambda: float > 0}"
		DistributionType.HISTOGRAM:
			distribution_info = "Histogram params: {values: Array[float], probabilities: Array[float]}"
		DistributionType.PSEUDO_RANDOM:
			distribution_info = "Pseudo-Random (Warcraft3/Dota) param: {c: float}"
		DistributionType.SAMPLE_WITHOUT_REPLACEMENT:
			distribution_info = "Sample w/o Replacement params: {deck_size: int, sample_count: int, sample_method_param: SamplingGen.SamplingMethod}"
		DistributionType.CUSTOM:
			distribution_info = "Custom. Uses num_map or custom logic in distribution_params."
		_:
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])


func _update_exported_fields_from_dict(params: Dictionary) -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			uniform_a = params.get("a", 0.0)
			uniform_b = params.get("b", 1.0)
		DistributionType.NORMAL:
			normal_mean = params.get("mean", 0.0)
			normal_std_dev = params.get("std_dev", 1.0)
		DistributionType.BERNOULLI:
			bernoulli_p = params.get("p", 0.5)
		DistributionType.BINOMIAL:
			binomial_n = params.get("n", 1)
			binomial_p = params.get("p", 0.5)
		DistributionType.POISSON:
			poisson_lambda = params.get("lambda", 1.0)
		DistributionType.EXPONENTIAL:
			exponential_lambda = params.get("lambda", 1.0)
		DistributionType.GEOMETRIC:
			geometric_p = params.get("p", 0.5)
		DistributionType.ERLANG:
			erlang_k = params.get("k", 1)
			erlang_lambda = params.get("lambda", 1.0)
		DistributionType.HISTOGRAM:
			histogram_values = params.get("values", [])
			histogram_probabilities = params.get("probabilities", [])
		DistributionType.PSEUDO_RANDOM:
			pseudo_c = params.get("c", 0.1)
		DistributionType.SAMPLE_WITHOUT_REPLACEMENT:
			swr_deck_size = params.get("deck_size", 52)
			swr_sample_count = params.get("sample_count", 5)
			swr_actual_method = params.get("sample_method_param", StatMath.SamplingGen.SamplingMethod.FISHER_YATES)
		DistributionType.CUSTOM: pass
		_: 
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])


func _update_dict_from_exported_fields() -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			distribution_params = {"a": uniform_a, "b": uniform_b}
		DistributionType.NORMAL:
			distribution_params = {"mean": normal_mean, "std_dev": normal_std_dev}
		DistributionType.BERNOULLI:
			distribution_params = {"p": bernoulli_p}
		DistributionType.BINOMIAL:
			distribution_params = {"n": binomial_n, "p": binomial_p}
		DistributionType.POISSON:
			distribution_params = {"lambda": poisson_lambda}
		DistributionType.EXPONENTIAL:
			distribution_params = {"lambda": exponential_lambda}
		DistributionType.GEOMETRIC:
			distribution_params = {"p": geometric_p}
		DistributionType.ERLANG:
			distribution_params = {"k": erlang_k, "lambda": erlang_lambda}
		DistributionType.HISTOGRAM:
			distribution_params = {"values": histogram_values, "probabilities": histogram_probabilities}
		DistributionType.PSEUDO_RANDOM:
			distribution_params = {"c": pseudo_c}
		DistributionType.SAMPLE_WITHOUT_REPLACEMENT:
			distribution_params = {
				"deck_size": swr_deck_size, 
				"sample_count": swr_sample_count,
				"sample_method_param": swr_actual_method
				}
		DistributionType.CUSTOM: pass
		_: 
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])


func _validate_property(property: Dictionary) -> void:
	if not Engine.is_editor_hint():
		return

	var prop_name: StringName = property.name

	if prop_name == &"distribution_info":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
		return

	var show_prop = false
	match distribution_type:
		DistributionType.UNIFORM:
			if prop_name in [&"uniform_a", &"uniform_b"]: 
				show_prop = true
		DistributionType.NORMAL:
			if prop_name in [&"normal_mean", &"normal_std_dev"]: 
				show_prop = true
		DistributionType.BERNOULLI:
			if prop_name == &"bernoulli_p": 
				show_prop = true
		DistributionType.BINOMIAL:
			if prop_name in [&"binomial_n", &"binomial_p"]: 
				show_prop = true
		DistributionType.POISSON:
			if prop_name == &"poisson_lambda": 
				show_prop = true
		DistributionType.EXPONENTIAL:
			if prop_name == &"exponential_lambda": 
				show_prop = true
		DistributionType.GEOMETRIC:
			if prop_name == &"geometric_p": 
				show_prop = true
		DistributionType.ERLANG:
			if prop_name in [&"erlang_k", &"erlang_lambda"]: 
				show_prop = true
		DistributionType.HISTOGRAM:
			if prop_name in [&"histogram_values", &"histogram_probabilities"]: 
				show_prop = true
		DistributionType.PSEUDO_RANDOM:
			if prop_name == &"pseudo_c": 
				show_prop = true
		DistributionType.SAMPLE_WITHOUT_REPLACEMENT:
			if prop_name in [&"swr_deck_size", &"swr_sample_count", &"swr_actual_method"]:
				show_prop = true
		DistributionType.CUSTOM: pass # Custom shows no specific params by default here
		_: 
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])

	var all_param_props = [
		&"uniform_a", &"uniform_b", 
		&"normal_mean", &"normal_std_dev", 
		&"bernoulli_p",
		&"binomial_n", &"binomial_p",
		&"poisson_lambda",
		&"exponential_lambda",
		&"geometric_p",
		&"erlang_k", &"erlang_lambda",
		&"histogram_values", &"histogram_probabilities",
		&"pseudo_c",
		&"swr_deck_size", &"swr_sample_count", &"swr_actual_method"
	]

	if prop_name in all_param_props:
		if show_prop:
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			property.usage &= ~PROPERTY_USAGE_EDITOR


func _generate_value_for_percentile(p_percentile: float) -> Dictionary:
	# Ensure distribution_params is up-to-date from exported fields if they were changed in editor
	if Engine.is_editor_hint():
		_update_dict_from_exported_fields()

	var debug_mode: bool = ProjectSettings.get_setting("monte_godot/debug_mode", false)

	var num: float = 0.0
	var pct_for_ppf: float = p_percentile

	match distribution_type:
		DistributionType.UNIFORM:
			num = StatMath.PpfFunctions.uniform_ppf(pct_for_ppf, self.uniform_a, self.uniform_b)
		DistributionType.NORMAL:
			num = StatMath.PpfFunctions.normal_ppf(pct_for_ppf, self.normal_mean, self.normal_std_dev)
		DistributionType.BERNOULLI:
			num = StatMath.PpfFunctions.bernoulli_ppf(pct_for_ppf, self.bernoulli_p)
		DistributionType.BINOMIAL:
			num = float(StatMath.PpfFunctions.binomial_ppf(pct_for_ppf, self.binomial_n, self.binomial_p))
		DistributionType.POISSON:
			num = float(StatMath.PpfFunctions.poisson_ppf(pct_for_ppf, self.poisson_lambda))
		DistributionType.EXPONENTIAL:
			num = StatMath.PpfFunctions.exponential_ppf(pct_for_ppf, self.exponential_lambda)
		DistributionType.GEOMETRIC:
			num = float(StatMath.PpfFunctions.geometric_ppf(pct_for_ppf, self.geometric_p))
		DistributionType.ERLANG:
			num = StatMath.PpfFunctions.gamma_ppf(pct_for_ppf, float(self.erlang_k), self.erlang_lambda)
		DistributionType.HISTOGRAM:
			num = StatMath.PpfFunctions.discrete_histogram_ppf(pct_for_ppf, self.histogram_values, self.histogram_probabilities)
		DistributionType.PSEUDO_RANDOM:
			push_warning("InVar '%s': PPF for PSEUDO_RANDOM is not straightforward. Returning percentile as num." % resource_name)
			num = pct_for_ppf
		DistributionType.SAMPLE_WITHOUT_REPLACEMENT: # This case should ideally not be hit if get_value handles it directly
			push_error("InVar '%s': _generate_value_for_percentile should not be called for SAMPLE_WITHOUT_REPLACEMENT." % resource_name)
			num = -1.0 # Error or placeholder
			if debug_mode: assert(false, "_generate_value_for_percentile called for SAMPLE_WITHOUT_REPLACEMENT")
		DistributionType.CUSTOM:
			if num_map.has(pct_for_ppf):
				num = num_map[pct_for_ppf]
			else:
				push_warning("InVar '%s': CUSTOM distribution: no num_map for percentile %f. Returning percentile as num." % [resource_name, pct_for_ppf])
				num = pct_for_ppf
		_:
			push_error("Unsupported distribution type for PPF: %s" % DistributionType.keys()[distribution_type])
			if debug_mode:
				assert(false, "Unsupported distribution type for PPF: %s" % DistributionType.keys()[distribution_type])

	return {"num": num, "pct": pct_for_ppf}

func generate_all_values() -> void:
	# For SAMPLE_WITHOUT_REPLACEMENT, values are generated on-the-fly in get_value().
	# This function primarily pertains to percentile-based distributions.
	if distribution_type == DistributionType.SAMPLE_WITHOUT_REPLACEMENT:
		_nums.clear() # Ensure _nums is clear as it's not used for SWR
		return

	_nums.clear()
	if percentiles.is_empty() and ndraws > 0:
		# If ndraws is set but percentiles aren't, it implies they should have been generated by Monte Godot
		push_warning("InVar '%s': generate_all_values() called with no percentiles but ndraws = %d. Values will not be generated." % [resource_name, ndraws])
		return
	if percentiles.is_empty() and ndraws == 0:
		# No percentiles and no samples expected, so nothing to do.
		return

	for p_idx in range(percentiles.size()):
		var percentile_val: float = percentiles[p_idx]
		var generated_output: Dictionary = _generate_value_for_percentile(percentile_val)
		var raw_num: float = generated_output.get("num", 0.0)
		_nums.append(raw_num)
	
	# Validate sizes if ndraws was specified and we have percentiles
	if ndraws > 0 and not percentiles.is_empty() and _nums.size() != percentiles.size():
		push_error("InVar '%s': Mismatch! Sampled values (%d) vs Percentiles (%d). Expected based on ndraws: %d" % [resource_name, _nums.size(), percentiles.size(), ndraws])
	elif ndraws > 0 and _nums.size() != ndraws and not percentiles.is_empty(): # Check against ndraws if percentiles were used
		push_warning("InVar '%s': Number of sampled values (%d) does not match ndraws (%d), but matches percentiles array size (%d)." % [resource_name, _nums.size(), ndraws, percentiles.size()])
