# res://tests/utils/utils_test.gd
class_name UtilsTest extends GdUnitTestSuite

# Assuming Utils is an autoload named 'Utils'
# const Utils = preload("res://src/utils/utils.gd") # Cannot preload an autoload script directly for static calls if it's not a class_name
# We will call its methods via Engine.get_singleton("Utils") or directly if it becomes a class_name

func test_example_utility_function() -> void:
	var result: String = Engine.get_singleton("Utils").example_utility_function()
	assert_str(result).is_equal("This is an example utility function from Utils.")

func test_get_safe_key_exists() -> void:
	var d: Dictionary = {"a": 1, "b": "hello"}
	assert_int(Engine.get_singleton("Utils").get_safe(d, "a", 0)).is_equal(1)
	assert_str(Engine.get_singleton("Utils").get_safe(d, "b", "default")).is_equal("hello")

func test_get_safe_key_not_exists() -> void:
	var d: Dictionary = {"a": 1}
	assert_str(Engine.get_singleton("Utils").get_safe(d, "missing_key", "default_val")).is_equal("default_val")
	assert_object(Engine.get_singleton("Utils").get_safe(d, "another_key", null)).is_null()
	assert_int(Engine.get_singleton("Utils").get_safe(d, "int_key", 42)).is_equal(42)

func test_get_safe_null_dictionary() -> void:
	assert_str(Engine.get_singleton("Utils").get_safe(null, "any_key", "default_on_null_dict")).is_equal("default_on_null_dict")
	assert_object(Engine.get_singleton("Utils").get_safe(null, "any_key")).is_null() # Default default_value is null

func test_get_safe_not_a_dictionary() -> void:
	var not_a_dict_array: Array = [1, 2, 3]
	var not_a_dict_string: String = "I am a string"
	
	assert_str(Engine.get_singleton("Utils").get_safe(not_a_dict_array, "key", "default_on_invalid_type")).is_equal("default_on_invalid_type")
	assert_object(Engine.get_singleton("Utils").get_safe(not_a_dict_string, "key")).is_null()

func test_get_safe_different_key_types() -> void:
	var d: Dictionary = {10: "ten", Vector2.ZERO: "origin"}
	assert_str(Engine.get_singleton("Utils").get_safe(d, 10, "default")).is_equal("ten")
	assert_str(Engine.get_singleton("Utils").get_safe(d, Vector2.ZERO, "default")).is_equal("origin")
	assert_str(Engine.get_singleton("Utils").get_safe(d, "non_existent_string_key", "fallback")).is_equal("fallback")

func test_get_safe_default_value_is_returned_correctly() -> void:
	var d: Dictionary = {"present": 100}
	var default_array: Array = [1,2,3]
	var default_dict: Dictionary = {"x":1}
	
	assert_array(Engine.get_singleton("Utils").get_safe(d, "missing_key_arr", default_array)).is_equal(default_array)
	assert_dict(Engine.get_singleton("Utils").get_safe(d, "missing_key_dict", default_dict)).is_equal(default_dict)
	assert_object(Engine.get_singleton("Utils").get_safe(d, "missing_key_obj", self)).is_equal(self) # Test returning a non-primitive default 