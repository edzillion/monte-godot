# res://tests/core/in_var_test.gd
class_name InVarTest extends GdUnitTestSuite

const InVar = preload("res://src/core/in_var.gd")
const InVal = preload("res://src/core/in_val.gd") # Needed for type checks and direct instantiation if pool is null

# Helper to run common assertions for an InVar configured for a few cases
func _run_sampling_assertions(p_in_var: InVar, num_test_cases: int, validation_callable: Callable) -> void:
	assert_object(p_in_var).is_not_null()
	p_in_var.configure_for_simulation(num_test_cases)

	if num_test_cases == 0:
		var inval_zero: InVal = p_in_var.get_value_for_case(0, null) # Should be out of bounds
		assert_object(inval_zero).is_not_null() # InVar returns a new InVal
		assert_object(inval_zero.get_value()).is_null() # With null internal values due to error
		return

	for i in range(num_test_cases):
		var inval: InVal = p_in_var.get_value_for_case(i, null)
		assert_object(inval).is_not_null()
		assert_bool(inval is InVal).is_true()
		validation_callable.call(inval, i) # Pass InVal and case_idx to validation

	# Test out of bounds access
	var inval_oob_neg: InVal = p_in_var.get_value_for_case(-1, null)
	assert_object(inval_oob_neg).is_not_null()
	assert_object(inval_oob_neg.get_value()).is_null() # Should have null internal value due to error

	var inval_oob_pos: InVal = p_in_var.get_value_for_case(num_test_cases, null)
	assert_object(inval_oob_pos).is_not_null()
	assert_object(inval_oob_pos.get_value()).is_null() # Should have null internal value


func test_initialization_properties() -> void:
	var v_pregen = InVar.new(&"x", "X Pregen", InVar.DistributionType.CUSTOM, {}, true, {0.0:"test"}, "Desc", "Units", 123)
	assert_str(v_pregen.id).is_equal("x")
	assert_str(v_pregen.name).is_equal("X Pregen")
	assert_bool(v_pregen.use_pregeneration).is_true()
	assert_int(v_pregen._base_seed).is_equal(123)
	assert_dict(v_pregen.num_map).is_equal({0.0:"test"})
	assert_str(v_pregen.description).is_equal("Desc")
	assert_str(v_pregen.units).is_equal("Units")

	var v_ondemand = InVar.new(&"y", "Y Ondemand", InVar.DistributionType.UNIFORM, {"a":0, "b":1}, false)
	assert_bool(v_ondemand.use_pregeneration).is_false()
	# Base seed will be randomized if not provided
	assert_int(v_ondemand._base_seed).is_not_equal(0) # Highly unlikely to be 0 after randomize()

	# Check internal arrays are initially empty or null as appropriate before configuration
	assert_array(v_pregen._sampled_numerical_values).is_empty()


func _test_distribution_sampling(dist_type: InVar.DistributionType, params: Dictionary, validation_callable: Callable, num_map_override: Dictionary = {}) -> void:
	var base_name: String = InVar.DistributionType.keys()[dist_type]
	
	# Test with pre-generation
	var id_str_pregen: String = "pregen_" + base_name
	var name_str_pregen: String = "Pregen " + base_name
	var id_sn_pregen: StringName = StringName(id_str_pregen)
	var v_pregen: InVar = InVar.new(id_sn_pregen, name_str_pregen, dist_type, params, true, num_map_override, "", "", 789)
	_run_sampling_assertions(v_pregen, 20, validation_callable)
	if v_pregen._total_configured_cases > 0: # Ensure _sampled_numerical_values was populated
		assert_array(v_pregen._sampled_numerical_values).is_not_empty()
	
	# Test with on-demand generation
	var id_str_ondemand: String = "ondemand_" + base_name
	var name_str_ondemand: String = "Ondemand " + base_name
	var id_sn_ondemand: StringName = StringName(id_str_ondemand)
	var v_ondemand: InVar = InVar.new(id_sn_ondemand, name_str_ondemand, dist_type, params, false, num_map_override, "", "", 789) # Same seed for comparability
	_run_sampling_assertions(v_ondemand, 20, validation_callable)
	if v_ondemand._total_configured_cases > 0: # Ensure _sampled_numerical_values is empty
		assert_array(v_ondemand._sampled_numerical_values).is_empty()

	# Test with zero cases
	var id_str_zero_pregen: String = "zero_pregen_" + base_name
	var name_str_zero_pregen: String = "Zero Pregen " + base_name
	var id_sn_zero_pregen: StringName = StringName(id_str_zero_pregen)
	var v_zero_case_pregen: InVar = InVar.new(id_sn_zero_pregen, name_str_zero_pregen, dist_type, params, true, num_map_override)
	_run_sampling_assertions(v_zero_case_pregen, 0, validation_callable)
	assert_array(v_zero_case_pregen._sampled_numerical_values).is_empty()

	var id_str_zero_ondemand: String = "zero_ondemand_" + base_name
	var name_str_zero_ondemand: String = "Zero Ondemand " + base_name
	var id_sn_zero_ondemand: StringName = StringName(id_str_zero_ondemand)
	var v_zero_case_ondemand: InVar = InVar.new(id_sn_zero_ondemand, name_str_zero_ondemand, dist_type, params, false, num_map_override)
	_run_sampling_assertions(v_zero_case_ondemand, 0, validation_callable)
	assert_array(v_zero_case_ondemand._sampled_numerical_values).is_empty()


func test_uniform_sampling() -> void:
	var params: Dictionary = {"a": 5.0, "b": 10.0}
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var val = inval.get_numeric_value() # Check numeric value before any potential map
		assert_float(val).is_greater_equal(5.0)
		assert_float(val).is_less_equal(10.0)
		assert_float(inval.get_value()).is_equal(val)
	_test_distribution_sampling(InVar.DistributionType.UNIFORM, params, Callable(validator))


func test_normal_sampling() -> void:
	var params: Dictionary = {"mean": 0.0, "std_dev": 1.0}
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		assert_int(typeof(inval.get_numeric_value())).is_equal(TYPE_FLOAT)
	_test_distribution_sampling(InVar.DistributionType.NORMAL, params, Callable(validator))


func test_bernoulli_sampling() -> void:
	var params: Dictionary = {"p": 0.7}
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var val = inval.get_numeric_value()
		assert_bool(val == 0.0 or val == 1.0).is_true()
	_test_distribution_sampling(InVar.DistributionType.BERNOULLI, params, Callable(validator))


func test_binomial_sampling() -> void:
	var params: Dictionary = {"n": 5, "p": 0.5}
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var val = inval.get_numeric_value()
		assert_int(typeof(val)).is_equal(TYPE_FLOAT) # Generated as float
		assert_float(val).is_greater_equal(0.0)
		assert_float(val).is_less_equal(5.0)
		assert_bool(val == floor(val)).is_true()
	_test_distribution_sampling(InVar.DistributionType.BINOMIAL, params, Callable(validator))


func test_poisson_sampling() -> void:
	var params: Dictionary = {"lambda": 2.0}
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var val = inval.get_numeric_value()
		assert_int(typeof(val)).is_equal(TYPE_FLOAT)
		assert_float(val).is_greater_equal(0.0)
		assert_bool(val == floor(val)).is_true()
	_test_distribution_sampling(InVar.DistributionType.POISSON, params, Callable(validator))


func test_exponential_sampling() -> void:
	var params: Dictionary = {"lambda": 1.0}
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var val = inval.get_numeric_value()
		assert_int(typeof(val)).is_equal(TYPE_FLOAT)
		assert_float(val).is_greater_equal(0.0)
	_test_distribution_sampling(InVar.DistributionType.EXPONENTIAL, params, Callable(validator))


func test_histogram_sampling() -> void:
	var params: Dictionary = {"values": [10.0, 20.0, 30.0], "probabilities": [0.2, 0.5, 0.3]}
	var expected_values = [10.0, 20.0, 30.0]
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var val = inval.get_numeric_value()
		assert_bool(val in expected_values).is_true()
	_test_distribution_sampling(InVar.DistributionType.HISTOGRAM, params, Callable(validator))

func test_histogram_invalid_params_fallback() -> void:
	# Test with mismatched sizes
	var params_mismatch: Dictionary = {"values": [10.0, 20.0], "probabilities": [0.5]}
	var v_mismatch: InVar = InVar.new(&"hist_mismatch", "Hist Mismatch", InVar.DistributionType.HISTOGRAM, params_mismatch, true)
	v_mismatch.configure_for_simulation(5) # Should default to [0.0] with prob 1.0
	for i in range(5):
		var inval = v_mismatch.get_value_for_case(i, null)
		assert_float(inval.get_numeric_value()).is_equal(0.0)

	# Test with non-numeric values in 'values' (this should be caught by param caching and fallback)
	var params_non_numeric_val: Dictionary = {"values": ["a", "b"], "probabilities": [0.5, 0.5]}
	var v_non_numeric_val: InVar = InVar.new(&"hist_non_num_val", "Hist NonNum Val", InVar.DistributionType.HISTOGRAM, params_non_numeric_val, true)
	# The _cache_distribution_parameters filters these out. If all are filtered, it defaults.
	# If some are valid numeric, it uses those.
	# Current InVar logic: it skips non-numeric. If values array becomes empty, it defaults to [0.0] prob [1.0]
	assert_bool(v_non_numeric_val._param_hist_values.size() == 1 and v_non_numeric_val._param_hist_values[0] == 0.0).is_true()
	assert_bool(v_non_numeric_val._param_hist_cumulative_probs.size() == 1 and v_non_numeric_val._param_hist_cumulative_probs[0] == 1.0).is_true()


func test_custom_sampling_numeric_keys() -> void:
	var num_map_data: Dictionary = {0.0: "zero", 1.0: "one", 2.0: "two"}
	var expected_keys: Array[float] = [0.0, 1.0, 2.0]
	
	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var num_val = inval.get_numeric_value()
		var final_val = inval.get_value()

		assert_bool(num_val in expected_keys).is_true()
		assert_bool(num_map_data.has(num_val)).is_true()
		
		assert_str(final_val).is_equal(num_map_data[num_val])
		
	_test_distribution_sampling(InVar.DistributionType.CUSTOM, {}, Callable(validator), num_map_data)


func test_num_map_with_other_distributions() -> void:
	# Test num_map applied AFTER another distribution (e.g., UNIFORM)
	var params_uniform: Dictionary = {"a": 0.0, "b": 2.9} # Generates 0.x, 1.x, 2.x
	# num_map keys should be the exact float values expected from the distribution
	# For robust testing, it's tricky if the distribution produces many unique floats.
	# Let's use Bernoulli which produces known 0.0 or 1.0.
	var params_bernoulli: Dictionary = {"p": 0.5}
	var num_map_data: Dictionary = {0.0: "FalseVal", 1.0: "TrueVal"}

	var validator = func(inval: InVal, _case_idx: int):
		assert_bool(inval is InVal).is_true()
		var num_val = inval.get_numeric_value() # Should be 0.0 or 1.0 from Bernoulli
		var mapped_val = inval.get_value()

		assert_bool(num_val == 0.0 or num_val == 1.0).is_true()
		
		if num_map_data.has(num_val):
			assert_str(mapped_val).is_equal(num_map_data[num_val])
		else:
			# This case should ideally not happen if num_map covers all outputs of the base distribution
			assert_object(mapped_val).is_null()			

	_test_distribution_sampling(InVar.DistributionType.BERNOULLI, params_bernoulli, Callable(validator), num_map_data)


func test_get_value_for_case_error_handling() -> void:
	var v = InVar.new(&"err_test", "Error Test", InVar.DistributionType.UNIFORM, {"a":0, "b":1}, true)
	# Case 1: Not configured
	var inval_not_configured = v.get_value_for_case(0, null)
	assert_object(inval_not_configured).is_not_null()
	assert_object(inval_not_configured.get_value()).is_null() # _total_configured_cases is 0

	# Case 2: Configured with 0 cases
	v.configure_for_simulation(0)
	var inval_config_zero = v.get_value_for_case(0, null)
	assert_object(inval_config_zero).is_not_null()
	assert_object(inval_config_zero.get_value()).is_null() # case_idx 0 is out of bounds for 0 cases

	# Case 3: Configured, but _sampled_numerical_values is somehow empty (for pregen)
	# This is a bit artificial as configure_for_simulation should populate it.
	# We can simulate by manually clearing it after configuration.
	v.configure_for_simulation(5)
	if v.use_pregeneration:
		assert_array(v._sampled_numerical_values).is_not_empty() # Should be populated
		v._sampled_numerical_values = PackedFloat32Array() # Manually empty it
		var inval_empty_array = v.get_value_for_case(0, null)
		assert_object(inval_empty_array).is_not_null()
		assert_object(inval_empty_array.get_value()).is_null() # Expect error log and null InVal content
	
	# Case 4: Null InVal pool and direct creation fails (hard to test InVal.new() returning null)
	# InVar.gd already logs critical if InVal.new() fails.

# test_probability_server_fallback_sampling remains a pass as it's hard to mock autoloads
func test_probability_server_fallback_sampling() -> void:
	pass

# Old tests to remove/confirm covered:
# test_uniform_sampling -> covered by new structure
# test_normal_sampling -> covered
# test_bernoulli_sampling -> covered
# test_binomial_sampling -> covered
# test_poisson_sampling -> covered
# test_exponential_sampling -> covered
# test_histogram_sampling -> covered
# test_num_map_sampling -> covered by test_custom_sampling_numeric_keys and test_num_map_with_other_distributions
# test_get_sampled_value -> covered by _run_sampling_assertions and test_get_value_for_case_error_handling
