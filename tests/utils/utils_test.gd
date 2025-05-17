# res://tests/utils/utils_test.gd
class_name UtilsTest extends GdUnitTestSuite

# Assuming Utils is an autoload named 'Utils'
# const Utils = preload("res://src/utils/utils.gd") # Cannot preload an autoload script directly for static calls if it's not a class_name
# We will call its methods via Utils or directly if it becomes a class_name

func test_get_safe_key_exists() -> void:
	var d: Dictionary = {"a": 1, "b": "hello"}
	assert_int(Utils.get_safe(d, "a", 0)).is_equal(1)
	assert_str(Utils.get_safe(d, "b", "default")).is_equal("hello")

func test_get_safe_key_not_exists() -> void:
	var d: Dictionary = {"a": 1}
	assert_str(Utils.get_safe(d, "missing_key", "default_val")).is_equal("default_val")
	assert_object(Utils.get_safe(d, "another_key", null)).is_null()
	assert_int(Utils.get_safe(d, "int_key", 42)).is_equal(42)

func test_get_safe_different_key_types() -> void:
	var d: Dictionary = {10: "ten", Vector2.ZERO: "origin"}
	assert_str(Utils.get_safe(d, 10, "default")).is_equal("ten")
	assert_str(Utils.get_safe(d, Vector2.ZERO, "default")).is_equal("origin")
	assert_str(Utils.get_safe(d, "non_existent_string_key", "fallback")).is_equal("fallback")

func test_get_safe_default_value_is_returned_correctly() -> void:
	var d: Dictionary = {"present": 100}
	var default_array: Array = [1,2,3]
	var default_dict: Dictionary = {"x":1}
	
	assert_array(Utils.get_safe(d, "missing_key_arr", default_array)).is_equal(default_array)
	assert_dict(Utils.get_safe(d, "missing_key_dict", default_dict)).is_equal(default_dict)
	assert_object(Utils.get_safe(d, "missing_key_obj", self)).is_equal(self) # Test returning a non-primitive default 
