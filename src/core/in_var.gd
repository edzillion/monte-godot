# res://src/core/in_var.gd
class_name InVar extends Var

## @brief Represents an input variable in the simulation.
##
## Extends Var to include details specific to input variables, such as
## their probability distribution and sampling logic.

#region Enums
## @brief Defines the type of probability distribution for the input variable.
enum DistributionType {
	UNIFORM,      # params: {"a": float, "b": float}
	NORMAL,       # params: {"mean": float, "std_dev": float}
	BERNOULLI,    # params: {"p": float} (output 0 or 1)
	BINOMIAL,     # params: {"n": int, "p": float}
	POISSON,      # params: {"lambda": float}
	EXPONENTIAL,  # params: {"lambda": float}
	HISTOGRAM,    # params: {"values": Array, "probabilities": Array[float]}
	CUSTOM        # For user-defined or discrete mapped values not fitting standard distributions
}
#endregion


#region Properties
var distribution_type: DistributionType = DistributionType.CUSTOM
# var distribution_params: Dictionary = {} # No longer primary storage after _init
var num_map: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new() # Local RNG, used for CUSTOM type and for generating _base_seed if not provided.
var _base_seed: int # Seed for this InVar instance, used for deterministic on-demand generation
var _total_configured_cases: int = 0

# Cached distribution parameters
var _param_uniform_a: float
var _param_uniform_b: float
var _param_normal_mean: float
var _param_normal_std_dev: float
var _param_bernoulli_p: float
var _param_binomial_n: int
var _param_binomial_p: float
var _param_poisson_lambda: float
var _param_exponential_lambda: float
var _param_hist_values: Array
var _param_hist_probabilities: Array
#endregion


#region Initialization
func _init(p_id: StringName, p_name: String, \
		p_distribution_type: DistributionType = DistributionType.CUSTOM, \
		p_distribution_params: Dictionary = {}, \
		p_num_map: Dictionary = {}, \
		p_description: String = "", p_units: String = "", p_seed: int = -1) -> void:
	super(p_id, p_name, p_description, p_units)
	distribution_type = p_distribution_type
	# self.distribution_params = p_distribution_params # Store temporarily if needed, or parse directly
	num_map = p_num_map
	if p_seed != -1:
		_base_seed = p_seed
	else:
		var temp_rng := RandomNumberGenerator.new() # Temporary RNG to generate a random seed
		temp_rng.randomize()
		_base_seed = temp_rng.seed # Store it as the base seed
	_rng.seed = _base_seed # Initialize local _rng with the determined base_seed for consistent behavior if used before per-case re-seeding

	_cache_distribution_parameters(p_distribution_params)


func _cache_distribution_parameters(params: Dictionary) -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			_param_uniform_a = Utils.get_safe(params, "a", 0.0)
			_param_uniform_b = Utils.get_safe(params, "b", 1.0)
		DistributionType.NORMAL:
			_param_normal_mean = Utils.get_safe(params, "mean", 0.0)
			_param_normal_std_dev = Utils.get_safe(params, "std_dev", 1.0)
			_param_normal_std_dev = max(0.000001, _param_normal_std_dev) # Ensure positive
		DistributionType.BERNOULLI:
			_param_bernoulli_p = Utils.get_safe(params, "p", 0.5)
		DistributionType.BINOMIAL:
			_param_binomial_n = Utils.get_safe(params, "n", 1)
			_param_binomial_p = Utils.get_safe(params, "p", 0.5)
		DistributionType.POISSON:
			_param_poisson_lambda = Utils.get_safe(params, "lambda", 1.0)
			_param_poisson_lambda = max(0.000001, _param_poisson_lambda) # Ensure positive
		DistributionType.EXPONENTIAL:
			_param_exponential_lambda = Utils.get_safe(params, "lambda", 1.0)
			_param_exponential_lambda = max(0.000001, _param_exponential_lambda) # Ensure positive
		DistributionType.HISTOGRAM:
			_param_hist_values = Utils.get_safe(params, "values", [])
			_param_hist_probabilities = Utils.get_safe(params, "probabilities", [])
		DistributionType.CUSTOM:
			pass # No parameters from dictionary needed other than num_map
		_:
			push_warning("InVar '%s': Unknown distribution type '%s' during parameter caching." % [name, distribution_type])


#endregion


#region Public Methods
## @brief Configures the InVar for a simulation run with a total number of cases.
## This method does NOT generate all samples upfront.
func configure_for_simulation(total_cases: int) -> void:
	_total_configured_cases = total_cases
	Logger.debug("InVar '%s' configured for %d total cases with base seed %d." % [name, _total_configured_cases, _base_seed])


## @brief Generates and returns an InVal for a specific case index on demand, using an object pool.
func get_value_for_case(case_idx: int, p_in_val_pool: ObjectPool) -> InVal:
	var acquired_in_val: InVal = null
	if p_in_val_pool:
		acquired_in_val = p_in_val_pool.acquire() as InVal
	
	if not acquired_in_val:
		Logger.error("InVar '%s': Failed to acquire InVal from pool for case %d. Creating directly (fallback)." % [name, case_idx])
		acquired_in_val = InVal.new()
		if not acquired_in_val:
			Logger.critical("InVar '%s': CRITICAL - Failed to create InVal even with direct instantiation for case %d." % [name, case_idx])
			return null # Cannot proceed

	if case_idx < 0 or case_idx >= _total_configured_cases:
		Logger.error("InVar '%s': Requested case_idx %d is out of bounds (0-%d). Returning null InVal." % [name, case_idx, _total_configured_cases -1])
		acquired_in_val._init(null, null) # Re-init/reset to null state
		return acquired_in_val

	if not ProbabilityServer:
		# This is a critical failure for most distributions.
		# For CUSTOM, we might proceed if num_map is all that's needed.
		if distribution_type != DistributionType.CUSTOM or num_map.is_empty():
			Logger.error("InVar '%s': ProbabilityServer (gdstats) autoload not found. This InVar cannot generate a valid value and will return an InVal with null content." % name)
			acquired_in_val._init(null, null) # Re-init/reset to null state
			return acquired_in_val

	# Determine the seed for this specific case to ensure deterministic generation
	# GDScript integers are 64-bit. Seeds for PRNGs are often 32-bit.
	# We add them directly and then wrap to signed 32-bit range.
	var case_specific_seed: int = wrapi(_base_seed + case_idx, -2147483648, 2147483647)

	var raw_numeric_value: Variant
	
	match distribution_type:
		DistributionType.UNIFORM:
			assert(ProbabilityServer, "ProbabilityServer missing for UNIFORM")
			#ProbabilityServer.set_seed(case_specific_seed)
			raw_numeric_value = ProbabilityServer.randf_uniform(_param_uniform_a, _param_uniform_b)
		DistributionType.NORMAL:
			assert(ProbabilityServer, "ProbabilityServer missing for NORMAL")
			#ProbabilityServer.set_seed(case_specific_seed)
			raw_numeric_value = ProbabilityServer.randfn(_param_normal_mean, _param_normal_std_dev)
		DistributionType.BERNOULLI:
			assert(ProbabilityServer, "ProbabilityServer missing for BERNOULLI")
			#ProbabilityServer.set_seed(case_specific_seed)
			raw_numeric_value = ProbabilityServer.randi_bernoulli(_param_bernoulli_p)
		DistributionType.BINOMIAL:
			assert(ProbabilityServer, "ProbabilityServer missing for BINOMIAL")
			#ProbabilityServer.set_seed(case_specific_seed)
			raw_numeric_value = ProbabilityServer.randi_binomial(_param_binomial_p, _param_binomial_n)
		DistributionType.POISSON:
			assert(ProbabilityServer, "ProbabilityServer missing for POISSON")
			#ProbabilityServer.set_seed(case_specific_seed)
			raw_numeric_value = ProbabilityServer.randi_poisson(_param_poisson_lambda)
		DistributionType.EXPONENTIAL:
			assert(ProbabilityServer, "ProbabilityServer missing for EXPONENTIAL")
			#ProbabilityServer.set_seed(case_specific_seed)
			raw_numeric_value = ProbabilityServer.randf_exponential(_param_exponential_lambda)
		DistributionType.HISTOGRAM:
			assert(ProbabilityServer, "ProbabilityServer missing for HISTOGRAM")
			#ProbabilityServer.set_seed(case_specific_seed)
			if _param_hist_values.is_empty() or _param_hist_probabilities.is_empty() or _param_hist_values.size() != _param_hist_probabilities.size():
				Logger.warning("InVar '%s': Cached histogram values/probabilities invalid. Using 0." % name)
				raw_numeric_value = 0
			else:
				raw_numeric_value = ProbabilityServer.randv_histogram(_param_hist_values, _param_hist_probabilities)
		DistributionType.CUSTOM, _:
			_rng.seed = case_specific_seed # Re-seed local _rng for this specific case
			if num_map.is_empty():
				push_error("InVar '%s': num_map must not be empty for CUSTOM distribution." % name)
				assert(false, "num_map must not be empty for CUSTOM distribution.")
				raw_numeric_value = null # Ensure it has a value if assert doesn't stop
			else:
				var map_keys: Array = num_map.keys()
				if map_keys.is_empty():
					push_error("InVar '%s': num_map has no keys for CUSTOM distribution." % name)
					assert(false, "num_map has no keys for CUSTOM distribution.")
					raw_numeric_value = null # Ensure it has a value
				else:
					var random_idx: int = _rng.randi_range(0, map_keys.size() - 1)
					var random_key = map_keys[random_idx]
					raw_numeric_value = random_key

	var mapped_value: Variant = null
	if not num_map.is_empty():
		if num_map.has(raw_numeric_value):
			mapped_value = num_map[raw_numeric_value]
		elif distribution_type == DistributionType.CUSTOM and not raw_numeric_value == null:
			push_error("InVar '%s' (CUSTOM): Sanity check failed. raw_numeric_value '%s' not found in num_map keys." % [name, str(raw_numeric_value)])
			assert(false, "CUSTOM InVar: raw_numeric_value chosen from keys was not found in num_map.")

	acquired_in_val._init(raw_numeric_value, mapped_value) # Re-initialize the acquired InVal
	return acquired_in_val

# Removed old sample_values and get_sampled_value methods
#endregion
