# res://tests/core/val_test.gd
class_name ValTest extends GdUnitTestSuite

const InVal = preload("res://src/core/in_val.gd")
const OutVal = preload("res://src/core/out_val.gd")

func test_inval_initialization_and_get_value() -> void:
	var v = InVal.new(42)
	assert_float(v.num_value).is_equal(42.0)
	assert_object(v.mapped_value).is_null()
	assert_float(v.get_value()).is_equal(42.0)

func test_inval_with_mapped_value() -> void:
	var v = InVal.new(7, "lucky")
	assert_float(v.num_value).is_equal(7.0)
	assert_str(v.mapped_value).is_equal("lucky")
	assert_str(v.get_value()).is_equal("lucky")

func test_outval_initialization_and_get_value() -> void:
	var v = OutVal.new(3.14)
	assert_float(v.num_value).is_equal(3.14)
	assert_object(v.mapped_value).is_null()
	assert_float(v.get_value()).is_equal(3.14)

func test_outval_with_mapped_value() -> void:
	var v = OutVal.new(1, "win")
	assert_float(v.num_value).is_equal(1.0)
	assert_str(v.mapped_value).is_equal("win")
	assert_str(v.get_value()).is_equal("win")

func test_get_value_prefers_mapped_value() -> void:
	var v = InVal.new(99, "special")
	assert_str(v.get_value()).is_equal("special")
	v = OutVal.new(0, "zero")
	assert_str(v.get_value()).is_equal("zero") 
