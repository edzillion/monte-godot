# res://tests/core/case_test.gd
class_name CaseTest extends GdUnitTestSuite

const Case = preload("res://src/core/case.gd")
const InVal = preload("res://src/core/in_val.gd")
const OutVal = preload("res://src/core/out_val.gd")

func test_initialization() -> void:
	var c = Case.new(42, 12345)
	assert_int(c.case_id).is_equal(42)
	assert_int(c.seed).is_equal(12345)
	assert_bool(c.is_processed).is_false()
	assert_dict(c.input_values).is_empty()
	assert_dict(c.output_values).is_empty()

func test_add_and_get_input_value() -> void:
	var c = Case.new(1, 1)
	var inval = InVal.new(3.14)
	c.add_input_value(&"foo", inval)
	assert_bool(c.input_values.has(&"foo")).is_true()
	assert_object(c.get_input_value(&"foo")).is_equal(inval)

func test_add_and_get_output_value() -> void:
	var c = Case.new(2, 2)
	var outval = OutVal.new(42)
	c.add_output_value(&"bar", outval)
	assert_bool(c.output_values.has(&"bar")).is_true()
	assert_object(c.get_output_value(&"bar")).is_equal(outval)

func test_overwrite_input_value_warns() -> void:
	var c = Case.new(3, 3)
	var inval1 = InVal.new(1)
	var inval2 = InVal.new(2)
	c.add_input_value(&"dup", inval1)
	assert_warning_emitted(func(): c.add_input_value(&"dup", inval2), "Case 3: Input variable 'dup' already has a value. Overwriting not allowed by default.")
	# Should not overwrite, should keep first
	assert_object(c.get_input_value(&"dup")).is_equal(inval1)

func test_overwrite_output_value_allows() -> void:
	var c = Case.new(4, 4)
	var outval1 = OutVal.new(10)
	var outval2 = OutVal.new(20)
	c.add_output_value(&"dup", outval1)
	assert_warning_emitted(func(): c.add_output_value(&"dup", outval2), "Case 4: Output variable 'dup' already has a value. Overwriting.")
	# Should overwrite, should keep last
	assert_object(c.get_output_value(&"dup")).is_equal(outval2)

func test_get_input_value_missing_warns_and_returns_null() -> void:
	var c = Case.new(5, 5)
	assert_warning_emitted(func(): c.get_input_value(&"missing"), "Case 5: Input variable 'missing' not found.")
	assert_object(c.get_input_value(&"missing")).is_null() # Call again to get the null for assertion

func test_get_output_value_missing_returns_null() -> void:
	var c = Case.new(6, 6)
	assert_object(c.get_output_value(&"missing")).is_null()

func test_set_processed_flag() -> void:
	var c = Case.new(7, 7)
	assert_bool(c.is_processed).is_false()
	c.set_processed(true)
	assert_bool(c.is_processed).is_true()
	c.set_processed(false)
	assert_bool(c.is_processed).is_false() 