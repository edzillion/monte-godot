# res://src/core/in_var.gd
class_name InVar extends Var

## @brief Represents an input variable in the simulation.
##
## Extends Var to include details specific to input variables, such as
## their probability distribution and sampling logic. Values are pre-generated
## into a packed array during configuration for cache efficiency.

#region Enums
## @brief Defines the type of probability distribution for the input variable.
enum DistributionType {
	UNIFORM,      # params: {"a": float, "b": float}
	NORMAL,       # params: {"mean": float, "std_dev": float}
	BERNOULLI,    # params: {"p": float} (output 0.0 or 1.0)
	BINOMIAL,     # params: {"n": int, "p": float}
	POISSON,      # params: {"lambda": float}
	EXPONENTIAL,  # params: {"lambda": float} # Godot's randf_exp uses rate (lambda)
	HISTOGRAM,    # params: {"values": Array[float], "probabilities": Array[float]} # 'values' must be float for PackedFloat32Array
	CUSTOM        # params: Uses num_map directly. Keys of num_map are sampled.
}
#endregion


#region Properties
var distribution_type: DistributionType = DistributionType.CUSTOM
var num_map: Dictionary = {} # Maps raw numeric value (key) to final value (val)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _base_seed: int
var _total_configured_cases: int = 0

# Pre-generation settings
var use_pregeneration: bool = true # Switch to toggle pre-generation
var _sampled_numerical_values: PackedFloat32Array # Populated if use_pregeneration is true

# Cached distribution parameters (parsed from constructor's p_distribution_params)
var _param_uniform_a: float
var _param_uniform_b: float
var _param_normal_mean: float
var _param_normal_std_dev: float
var _param_bernoulli_p: float
var _param_binomial_n: int
var _param_binomial_p: float
var _param_poisson_lambda: float
var _param_exponential_lambda: float # Rate parameter
var _param_hist_values: PackedFloat32Array # Must be floats
var _param_hist_cumulative_probs: PackedFloat32Array # Pre-calculated for histogram sampling
var _custom_map_keys_as_float_array: PackedFloat32Array # For CUSTOM type, if keys are numeric

#endregion


#region Initialization
func _init(p_id: StringName, p_name: String, \
		p_distribution_type: DistributionType = DistributionType.CUSTOM, \
		p_distribution_params: Dictionary = {}, \
		p_use_pregeneration: bool = true, \
		p_num_map: Dictionary = {}, \
		p_description: String = "", p_units: String = "", p_seed: int = -1, \
		) -> void:
	super(p_id, p_name, p_description, p_units)
	distribution_type = p_distribution_type
	num_map = p_num_map
	use_pregeneration = p_use_pregeneration # Store the pre-generation preference

	if p_seed != -1:
		_base_seed = p_seed
	else:
		var temp_rng := RandomNumberGenerator.new()
		temp_rng.randomize()
		_base_seed = temp_rng.seed
	# _rng is already instantiated, we will seed it per case during generation.

	_cache_distribution_parameters(p_distribution_params)


func _cache_distribution_parameters(params: Dictionary) -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			_param_uniform_a = Utils.get_safe(params, "a", 0.0)
			_param_uniform_b = Utils.get_safe(params, "b", 1.0)
			if _param_uniform_a > _param_uniform_b: # Ensure a <= b
				var temp = _param_uniform_a
				_param_uniform_a = _param_uniform_b
				_param_uniform_b = temp
				push_warning("InVar '%s' (UNIFORM): 'a' > 'b', swapped them." % name)
		DistributionType.NORMAL:
			_param_normal_mean = Utils.get_safe(params, "mean", 0.0)
			_param_normal_std_dev = Utils.get_safe(params, "std_dev", 1.0)
			_param_normal_std_dev = max(0.000001, _param_normal_std_dev)
		DistributionType.BERNOULLI:
			_param_bernoulli_p = Utils.get_safe(params, "p", 0.5)
			_param_bernoulli_p = clampf(_param_bernoulli_p, 0.0, 1.0)
		DistributionType.BINOMIAL:
			_param_binomial_n = Utils.get_safe(params, "n", 1)
			_param_binomial_p = Utils.get_safe(params, "p", 0.5)
			_param_binomial_n = max(0, _param_binomial_n)
			_param_binomial_p = clampf(_param_binomial_p, 0.0, 1.0)
		DistributionType.POISSON:
			_param_poisson_lambda = Utils.get_safe(params, "lambda", 1.0)
			_param_poisson_lambda = max(0.000001, _param_poisson_lambda)
		DistributionType.EXPONENTIAL:
			_param_exponential_lambda = Utils.get_safe(params, "lambda", 1.0) # This is the rate for Godot's randf_exp
			_param_exponential_lambda = max(0.000001, _param_exponential_lambda)
		DistributionType.HISTOGRAM:
			var values_arr: Array = Utils.get_safe(params, "values", [])
			var probs_arr: Array = Utils.get_safe(params, "probabilities", [])
			if values_arr.size() != probs_arr.size() or values_arr.is_empty():
				push_error("InVar '%s' (HISTOGRAM): 'values' and 'probabilities' must be non-empty and of same size." % name)
				# Fallback to a single value to prevent crashes, though this is bad data.
				_param_hist_values = PackedFloat32Array([0.0])
				_param_hist_cumulative_probs = PackedFloat32Array([1.0])
			else:
				_param_hist_values = PackedFloat32Array()
				_param_hist_cumulative_probs = PackedFloat32Array()
				var current_sum: float = 0.0
				for i in range(values_arr.size()):
					var val = values_arr[i]
					var prob = probs_arr[i]
					if not (val is float or val is int):
						push_error("InVar '%s' (HISTOGRAM): All 'values' must be numeric. Found: %s" % [name, typeof(val)])
						# Skip this invalid entry or handle error appropriately
						continue
					if not (prob is float or prob is int) or prob < 0:
						push_error("InVar '%s' (HISTOGRAM): All 'probabilities' must be non-negative numbers. Found: %s" % [name, typeof(prob)])
						# Skip
						continue
					_param_hist_values.append(float(val))
					current_sum += float(prob)
					_param_hist_cumulative_probs.append(current_sum)
				# Normalize cumulative probabilities
				if current_sum > 0:
					for i in range(_param_hist_cumulative_probs.size()):
						_param_hist_cumulative_probs[i] /= current_sum
				else: # All probs were zero, create a fallback
					_param_hist_values = PackedFloat32Array([0.0])
					_param_hist_cumulative_probs = PackedFloat32Array([1.0])
					push_warning("InVar '%s' (HISTOGRAM): Sum of probabilities is zero. Defaulting to value 0 with prob 1." % name)

		DistributionType.CUSTOM:
			if num_map.is_empty():
				push_error("InVar '%s' (CUSTOM): num_map must not be empty." % name)
				assert(false, "CUSTOM InVar: num_map is empty.")
			else:
				_custom_map_keys_as_float_array = PackedFloat32Array()
				for key in num_map.keys():
					if not (key is float or key is int):
						push_error("InVar '%s' (CUSTOM): For pre-generation, all keys in num_map must be numeric (float/int). Found key: %s of type %s" % [name, str(key), typeof(key)])
						# This InVar will be problematic for pre-generation.
						# Consider an alternative or ensure keys are numeric for CUSTOM + pre-gen.
						# For now, we'll skip non-numeric keys for the float array.
						continue
					_custom_map_keys_as_float_array.append(float(key))
				if _custom_map_keys_as_float_array.is_empty() and not num_map.is_empty():
					push_error("InVar '%s' (CUSTOM): No numeric keys found in num_map for pre-generation into PackedFloat32Array." % name)
					# This means _generate_value_from_distribution_with_local_rng will fail for CUSTOM.
		_:
			push_warning("InVar '%s': Unknown distribution type '%s' during parameter caching." % [name, distribution_type])
#endregion


#region Core Logic
## @brief Configures the InVar for a simulation run and pre-generates all raw numerical values.
func configure_for_simulation(total_cases: int) -> void:
	_total_configured_cases = total_cases
	if _total_configured_cases <= 0:
		_sampled_numerical_values = PackedFloat32Array() # Ensure it's an empty packed array
		Logger.info("InVar '%s' configured for 0 cases. No values generated." % name)
		return

	if use_pregeneration:
		_sampled_numerical_values.resize(_total_configured_cases)
		Logger.debug("InVar '%s' starting pre-generation of %s values with base seed %d." % [name, Logger._format_int_with_underscores(_total_configured_cases), _base_seed])
		for i in range(_total_configured_cases):
			var current_case_seed: int = wrapi(_base_seed + i, -2147483648, 2147483647)
			_rng.seed = current_case_seed 
			_sampled_numerical_values[i] = _generate_value_from_distribution_with_local_rng()
		Logger.info("InVar '%s' successfully pre-generated %s numerical values." % [name, Logger._format_int_with_underscores(_total_configured_cases)])
	else:
		_sampled_numerical_values = PackedFloat32Array() # Ensure it's empty if not pre-generating
		Logger.info("InVar '%s' configured for on-demand generation for %s cases (base seed: %d)." % [name, Logger._format_int_with_underscores(_total_configured_cases), _base_seed])


## @brief Internal helper to generate a single value based on distribution_type using the local _rng.
## Assumes _rng has been seeded appropriately for the current case before this call.
func _generate_value_from_distribution_with_local_rng() -> float:
	match distribution_type:
		DistributionType.UNIFORM:
			return _rng.randf_range(_param_uniform_a, _param_uniform_b)
		DistributionType.NORMAL:
			return _rng.randfn(_param_normal_mean, _param_normal_std_dev)
		DistributionType.BERNOULLI:
			return 1.0 if _rng.randf() < _param_bernoulli_p else 0.0
		DistributionType.BINOMIAL:
			var successes: int = 0
			for _i in range(_param_binomial_n):
				if _rng.randf() < _param_binomial_p:
					successes += 1
			return float(successes)
		DistributionType.POISSON:
			# Knuth's algorithm for Poisson distribution
			if _param_poisson_lambda <= 0: return 0.0
			var l: float = exp(-_param_poisson_lambda)
			var k: int = 0
			var p: float = 1.0
			while true:
				k += 1
				p *= _rng.randf()
				if p <= l:
					break
			return float(k - 1)
		DistributionType.EXPONENTIAL:
			# Godot's randf_exp takes lambda (rate) directly.
			# Mean = 1/lambda. If _param_exponential_lambda is a mean, convert to rate.
			# Assuming _param_exponential_lambda IS the rate as per Godot's expectation.
			return _rng.randf_exp(_param_exponential_lambda)
		DistributionType.HISTOGRAM:
			if _param_hist_values.is_empty() or _param_hist_cumulative_probs.is_empty():
				push_warning("InVar '%s' (HISTOGRAM): Attempted to sample from uninitialized/invalid histogram. Returning 0.0." % name)
				return 0.0
			var r: float = _rng.randf()
			for i in range(_param_hist_cumulative_probs.size()):
				if r <= _param_hist_cumulative_probs[i]:
					return _param_hist_values[i]
			return _param_hist_values[_param_hist_values.size() - 1] # Should not happen if probs sum to 1
		DistributionType.CUSTOM:
			if _custom_map_keys_as_float_array.is_empty():
				push_error("InVar '%s' (CUSTOM): Cannot generate value, _custom_map_keys_as_float_array is empty. This means num_map had no numeric keys." % name)
				assert(false, "CUSTOM InVar: No numeric keys available for sampling.")
				return 0.0 # Fallback, though this indicates a config error
			var random_idx: int = _rng.randi_range(0, _custom_map_keys_as_float_array.size() - 1)
			return _custom_map_keys_as_float_array[random_idx]
		_:
			push_error("InVar '%s': Unknown distribution type '%s' in _generate_value. Returning 0.0." % [name, distribution_type])
			assert(false, "Unknown distribution type in _generate_value")
			return 0.0


## @brief Retrieves an InVal for a specific case index using pre-generated values and an object pool.
func get_value_for_case(case_idx: int, p_in_val_pool: ObjectPool) -> InVal:
	var acquired_in_val: InVal = null
	if p_in_val_pool:
		acquired_in_val = p_in_val_pool.acquire() as InVal
	
	if not acquired_in_val:
		Logger.error("InVar '%s': Failed to acquire InVal from pool for case %d. Creating directly." % [name, case_idx])
		acquired_in_val = InVal.new()
		if not acquired_in_val:
			Logger.critical("InVar '%s': CRITICAL - Failed to create InVal for case %d." % [name, case_idx])
			return null

	if case_idx < 0 or case_idx >= _total_configured_cases:
		var err_msg = "InVar '%s': Requested case_idx %s is out of bounds for %s configured cases." % [name, Logger._format_int_with_underscores(case_idx), Logger._format_int_with_underscores(_total_configured_cases)]
		Logger.error(err_msg)
		acquired_in_val._init(null, null)
		return acquired_in_val

	var raw_numeric_value: float
	if use_pregeneration:
		if _sampled_numerical_values.is_empty() and _total_configured_cases > 0:
			Logger.error("InVar '%s': Pre-generation was enabled, but _sampled_numerical_values is empty for case %s (total cases: %s)." % [name, Logger._format_int_with_underscores(case_idx), Logger._format_int_with_underscores(_total_configured_cases)])
			acquired_in_val._init(null,null)
			return acquired_in_val
		# Array bounds check already done by case_idx vs _total_configured_cases
		raw_numeric_value = _sampled_numerical_values[case_idx]
	else: # On-demand generation
		var current_case_seed: int = wrapi(_base_seed + case_idx, -2147483648, 2147483647)
		_rng.seed = current_case_seed # Seed the local RNG for this specific case
		raw_numeric_value = _generate_value_from_distribution_with_local_rng()
	
	var effective_mapped_value: Variant = null
	if not num_map.is_empty() and num_map.has(raw_numeric_value):
		effective_mapped_value = num_map[raw_numeric_value]
	
	acquired_in_val._init(raw_numeric_value, effective_mapped_value)
	return acquired_in_val

#endregion
