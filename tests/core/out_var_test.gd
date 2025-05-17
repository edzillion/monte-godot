# res://tests/core/out_var_test.gd
class_name OutVarTest extends GdUnitTestSuite

const OutVar = preload("res://src/core/out_var.gd")
const OutVal = preload("res://src/core/out_val.gd")

func test_initialization_properties() -> void:
	var v = OutVar.new(&"score", "Score", "Total score", "points")
	assert_str(v.id).is_equal("score")
	assert_str(v.name).is_equal("Score")
	assert_str(v.description).is_equal("Total score")
	assert_str(v.units).is_equal("points")
	assert_array(v.result_values).is_empty()

func test_add_and_get_result_value() -> void:
	var v = OutVar.new(&"score", "Score")
	var outval = OutVal.new(99)
	v.add_result_value(outval)
	assert_int(v.result_values.size()).is_equal(1)
	assert_object(v.get_result_value(0)).is_equal(outval)

func test_clear_results() -> void:
	var v = OutVar.new(&"score", "Score")
	v.add_result_value(OutVal.new(1))
	v.add_result_value(OutVal.new(2))
	v.clear_results()
	assert_array(v.result_values).is_empty()

func test_get_result_value_out_of_bounds_returns_null() -> void:
	var v = OutVar.new(&"score", "Score")
	assert_object(v.get_result_value(0)).is_null()
	assert_warning_emitted(func(): v.get_result_value(0), "Requested result value index 0 is out of bounds for OutVar 'Score'.")
	v.add_result_value(OutVal.new(1))
	assert_object(v.get_result_value(1)).is_null()
	assert_warning_emitted(func(): v.get_result_value(1), "Requested result value index 1 is out of bounds for OutVar 'Score'.") 