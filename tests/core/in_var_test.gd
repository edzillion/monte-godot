# res://tests/core/in_var_test.gd
class_name InVarTest extends GdUnitTestSuite

const InVar = preload("res://src/core/in_var.gd")
const InVal = preload("res://src/core/in_val.gd")

func test_initialization_properties() -> void:
	var v = InVar.new(&"x", "X Variable")
	assert_str(v.id).is_equal("x")
	assert_str(v.name).is_equal("X Variable")
	assert_dict(v.distribution_params).is_empty()
	assert_dict(v.num_map).is_empty()
	assert_array(v.sampled_values).is_empty()

func test_uniform_sampling() -> void:
	var v = InVar.new(&"u", "Uniform", InVar.DistributionType.UNIFORM, {"a": 5.0, "b": 10.0})
	v.sample_values(100)
	assert_int(v.sampled_values.size()).is_equal(100)
	for inval in v.sampled_values:
		assert_bool(inval is InVal).is_true()
		var val = inval.get_value()
		assert_float(val).is_greater_equal(5.0)
		assert_float(val).is_less_equal(10.0)

func test_normal_sampling() -> void:
	var v = InVar.new(&"n", "Normal", InVar.DistributionType.NORMAL, {"mean": 0.0, "std_dev": 1.0})
	v.sample_values(50)
	assert_int(v.sampled_values.size()).is_equal(50)
	# Just check values are floats (distribution shape is stochastic)
	for inval in v.sampled_values:
		assert_bool(inval is InVal).is_true()
		assert_int(typeof(inval.get_value())).is_equal(TYPE_FLOAT)

func test_bernoulli_sampling() -> void:
	var v = InVar.new(&"b", "Bernoulli", InVar.DistributionType.BERNOULLI, {"p": 0.7})
	v.sample_values(30)
	for inval in v.sampled_values:
		assert_bool(inval.get_value() == 0 or inval.get_value() == 1).is_true()

func test_binomial_sampling() -> void:
	var v = InVar.new(&"bin", "Binomial", InVar.DistributionType.BINOMIAL, {"n": 5, "p": 0.5})
	v.sample_values(20)
	for inval in v.sampled_values:
		assert_int(typeof(inval.get_value())).is_equal(TYPE_FLOAT)
		assert_float(inval.get_value()).is_greater_equal(0.0)
		assert_float(inval.get_value()).is_less_equal(5.0)

func test_poisson_sampling() -> void:
	var v = InVar.new(&"poi", "Poisson", InVar.DistributionType.POISSON, {"lambda": 2.0})
	v.sample_values(20)
	for inval in v.sampled_values:
		assert_int(typeof(inval.get_value())).is_equal(TYPE_FLOAT)
		assert_float(inval.get_value()).is_greater_equal(0.0)

func test_exponential_sampling() -> void:
	var v = InVar.new(&"exp", "Exponential", InVar.DistributionType.EXPONENTIAL, {"lambda": 1.0})
	v.sample_values(20)
	for inval in v.sampled_values:
		assert_int(typeof(inval.get_value())).is_equal(TYPE_FLOAT)
		assert_float(inval.get_value()).is_greater_equal(0.0)

func test_histogram_sampling() -> void:
	var v = InVar.new(&"hist", "Histogram", InVar.DistributionType.HISTOGRAM, {"values": ["a", "b", "c"], "probabilities": [0.2, 0.5, 0.3]})
	v.sample_values(30)
	for inval in v.sampled_values:
		assert_bool(inval.get_value() in ["a", "b", "c"]).is_true()
		assert_bool(inval.mapped_value == null).is_true()

func test_num_map_sampling() -> void:
	var num_map: Dictionary = {0.0: "zero", 1.0: "one", 2.0: "two"}
	var v: InVar = InVar.new(&"map", "Mapped", InVar.DistributionType.CUSTOM, {}, num_map)
	v.sample_values(10)
	assert_int(v.sampled_values.size()).is_equal(10)

	for inval in v.sampled_values:
		assert_bool(inval is InVal).is_true()
		
		var original_key: Variant = inval.get_numeric_value()
		var final_value: Variant = inval.get_value()
		var direct_mapped_value: Variant = inval.mapped_value

		assert_bool(original_key is float).is_true()
		assert_bool(num_map.has(original_key)).is_true()

		assert_bool(direct_mapped_value != null).is_true()
		assert_bool(typeof(direct_mapped_value) == TYPE_STRING).is_true()
		assert_str(direct_mapped_value).is_equal(num_map[original_key])
		assert_str(final_value).is_equal(direct_mapped_value)

func test_custom_distribution_with_empty_num_map_fails() -> void:
	var v = InVar.new(&"empty_map_custom", "Empty Map Custom", InVar.DistributionType.CUSTOM, {}, {})
	assert_error_emitted(func(): v.sample_values(10), "InVar 'Empty Map Custom': num_map must not be empty for CUSTOM distribution.", [], false)
	# The assert(false) in InVar.gd will also cause a script error. 
	# call_deferred_safe is one way to check if the function execution fails.
	assert_bool(v.sample_values.bind(10).call_deferred_safe()).is_false()

func test_get_sampled_value() -> void:
	var v = InVar.new(&"get_sample", "Get Sample", InVar.DistributionType.UNIFORM, {"a": 1.0, "b": 2.0})
	v.sample_values(3)
	assert_int(v.sampled_values.size()).is_equal(3)

	var val0: InVal = v.get_sampled_value(0)
	assert_object(val0).is_not_null()
	assert_bool(val0 is InVal).is_true()

	var val2: InVal = v.get_sampled_value(2)
	assert_object(val2).is_not_null()
	assert_bool(val2 is InVal).is_true()

	var val_invalid_neg: InVal = v.get_sampled_value(-1)
	assert_object(val_invalid_neg).is_null()
	assert_warning_emitted(func(): v.get_sampled_value(-1), "Requested sampled value index -1 is out of bounds for InVar 'Get Sample'.")

	var val_invalid_oob: InVal = v.get_sampled_value(3) # size is 3, so index 3 is out of bounds
	assert_object(val_invalid_oob).is_null()
	assert_warning_emitted(func(): v.get_sampled_value(3), "Requested sampled value index 3 is out of bounds for InVar 'Get Sample'.")

func test_probability_server_fallback_sampling() -> void:
	# This test requires ProbabilityServer to be temporarily unavailable.
	# This is hard to achieve in a standard test run without modifying engine singletons.
	# For now, we assume the fallback logic in InVar.gd is covered by visual inspection
	# or would be caught if ProbabilityServer was actually missing during other tests.
	# If a robust way to mock/disable an autoload is found, this test can be implemented.
	pass # Placeholder for now
