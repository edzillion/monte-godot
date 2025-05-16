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
		assert_int(typeof(inval.get_value())).is_equal(TYPE_INT)
		assert_int(inval.get_value()).is_greater_equal(0)
		assert_int(inval.get_value()).is_less_equal(5)

func test_poisson_sampling() -> void:
	var v = InVar.new(&"poi", "Poisson", InVar.DistributionType.POISSON, {"lambda": 2.0})
	v.sample_values(20)
	for inval in v.sampled_values:
		assert_int(typeof(inval.get_value())).is_equal(TYPE_INT)
		assert_int(inval.get_value()).is_greater_equal(0)

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

func test_num_map_sampling() -> void:
	var num_map: Dictionary = {0.0: "zero", 1.0: "one", 2.0: "two"}
	var v: InVar = InVar.new(&"map", "Mapped", InVar.DistributionType.CUSTOM, {}, num_map)
	v.sample_values(10)
	assert_int(v.sampled_values.size()).is_equal(10)

	for inval in v.sampled_values:
		assert_bool(inval is InVal).is_true()
		
		var numeric_val: Variant = inval.get_value()
		Logger.debug("Test: inval.get_value() = %s (type: %s)" % [str(numeric_val), typeof(numeric_val)])
		Logger.debug("Test: inval.mapped_value = %s (type: %s)" % [str(inval.mapped_value), typeof(inval.mapped_value)])

		assert_bool(numeric_val is float).is_true()
		assert_bool(num_map.has(numeric_val)).is_true()

		assert_bool(inval.mapped_value != null).is_true()
		assert_bool(num_map.values().has(inval.mapped_value)).is_true()
		assert_float(inval.mapped_value).is_equal(num_map[numeric_val])
