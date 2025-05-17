# res://tests/core/case_test.gd
class_name CaseTest extends GdUnitTestSuite

const Case = preload("res://src/core/case.gd")
const InVal = preload("res://src/core/in_val.gd")
const OutVal = preload("res://src/core/out_val.gd")


func test_initialization_default() -> void:
	var c: Case = Case.new()
	assert_int(c.case_id).is_equal(-1)
	assert_int(c.seed).is_equal(0)
	assert_bool(c.is_processed).is_false()
	assert_array(c.input_values_array).is_empty()
	assert_array(c.output_values_array).is_empty()
	assert_dict(c._input_id_to_idx_map).is_empty()
	assert_dict(c._output_id_to_idx_map).is_empty()


func test_configure_and_reset() -> void:
	var c: Case = Case.new()
	var input_map: Dictionary = {&"in1": 0, &"in2": 1}
	var output_map: Dictionary = {&"out1": 0}
	
	c.configure_and_reset(101, 555, 2, input_map, 1, output_map, null, null)
	
	assert_int(c.case_id).is_equal(101)
	assert_int(c.seed).is_equal(555)
	assert_bool(c.is_processed).is_false()
	
	assert_int(c.input_values_array.size()).is_equal(2)
	assert_object(c.input_values_array[0]).is_null() # Arrays are resized and filled with null
	assert_object(c.input_values_array[1]).is_null()
	
	assert_int(c.output_values_array.size()).is_equal(1)
	assert_object(c.output_values_array[0]).is_null()
	
	assert_dict(c._input_id_to_idx_map).is_equal(input_map)
	assert_dict(c._output_id_to_idx_map).is_equal(output_map)


func test_indexed_access_input_values() -> void:
	var c: Case = Case.new()
	c.configure_and_reset(1, 1, 2, {&"x":0, &"y":1}, 0, {}, null, null)
	
	var inval1: InVal = InVal.new(1.0)
	var inval2: InVal = InVal.new(2.0)
	
	c.add_input_value_at_index(0, inval1)
	assert_object(c.get_input_value_at_index(0)).is_equal(inval1)
	
	c.add_input_value_at_index(1, inval2)
	assert_object(c.get_input_value_at_index(1)).is_equal(inval2)

	# Test overwrite at index
	var inval3: InVal = InVal.new(3.0)
	c.add_input_value_at_index(0, inval3) # Should overwrite inval1
	assert_object(c.get_input_value_at_index(0)).is_equal(inval3)
	
	# Test out of bounds access (getter)
	assert_object(c.get_input_value_at_index(-1)).is_null() # Expect warning
	assert_object(c.get_input_value_at_index(2)).is_null()  # Expect warning

	# Test out of bounds access (setter) - should produce error and not crash
	# GdUnit doesn't have a direct way to assert errors/warnings easily without custom setup.
	# We rely on manual log checking for these error paths for now.
	# c.add_input_value_at_index(2, InVal.new(99.0)) # Expect error


func test_indexed_access_output_values() -> void:
	var c: Case = Case.new()
	c.configure_and_reset(1, 1, 0, {}, 1, {&"res":0}, null, null)
	
	var outval1: OutVal = OutVal.new("A")
	c.add_output_value_at_index(0, outval1)
	assert_object(c.get_output_value_at_index(0)).is_equal(outval1)
	
	# Test overwrite at index
	var outval2: OutVal = OutVal.new("B")
	c.add_output_value_at_index(0, outval2)
	assert_object(c.get_output_value_at_index(0)).is_equal(outval2)

	# Test out of bounds access
	assert_object(c.get_output_value_at_index(1)).is_null() # Expect no warning for getter by default
	# c.add_output_value_at_index(1, OutVal.new("C")) # Expect error


func test_id_based_getters_and_output_setter() -> void:
	var c: Case = Case.new()
	var input_map: Dictionary = {&"id_in1": 0, &"id_in2": 1}
	var output_map: Dictionary = {&"id_out1": 0}
	c.configure_and_reset(2, 2, 2, input_map, 1, output_map, null, null)

	var inval1: InVal = InVal.new(10.0)
	# Inputs are set by SimManager using add_input_value_at_index.
	c.add_input_value_at_index(0, inval1) # Set input for id_in1
	
	# Test get_input_value_by_id
	assert_object(c.get_input_value_by_id(&"id_in1")).is_equal(inval1)
	assert_object(c.get_input_value_by_id(&"id_in2")).is_null() # Index 1 was not set yet
	assert_object(c.get_input_value_by_id(&"non_existent_in")).is_null() # Expect warning

	# Test add_output_value_by_id and get_output_value_by_id
	var outval1: OutVal = OutVal.new("ResultA")
	c.add_output_value_by_id(&"id_out1", outval1)
	assert_object(c.get_output_value_by_id(&"id_out1")).is_equal(outval1)
	assert_object(c.get_output_value_by_id(&"non_existent_out")).is_null()


func test_overwrite_values() -> void:
	var c: Case = Case.new()
	c.configure_and_reset(3, 3, 1, {&"dup_in":0}, 1, {&"dup_out":0}, null, null)

	# Test overwriting input AT INDEX, then getting by ID
	var inval1: InVal = InVal.new(1)
	var inval2: InVal = InVal.new(2)
	c.add_input_value_at_index(0, inval1) # Corresponds to "dup_in"
	assert_object(c.get_input_value_by_id(&"dup_in")).is_equal(inval1)
	c.add_input_value_at_index(0, inval2) # Overwriting at the index 0
	assert_object(c.get_input_value_by_id(&"dup_in")).is_equal(inval2) # Should now be inval2 when fetched by ID

	# Test overwriting output BY ID
	var outval1: OutVal = OutVal.new(10)
	var outval2: OutVal = OutVal.new(20)
	c.add_output_value_by_id(&"dup_out", outval1)
	assert_object(c.get_output_value_by_id(&"dup_out")).is_equal(outval1)
	c.add_output_value_by_id(&"dup_out", outval2) # This should overwrite
	assert_object(c.get_output_value_by_id(&"dup_out")).is_equal(outval2)


func test_get_value_by_id_missing_returns_null() -> void:
	var c: Case = Case.new()
	c.configure_and_reset(5, 5, 0, {}, 0, {}, null, null) # No vars configured
	assert_object(c.get_input_value_by_id(&"missing_in")).is_null() # Expect warning
	assert_object(c.get_output_value_by_id(&"missing_out")).is_null() # No warning by default for outputs


func test_set_processed_flag() -> void:
	var c: Case = Case.new() # No need to configure for this test
	assert_bool(c.is_processed).is_false()
	c.set_processed(true)
	assert_bool(c.is_processed).is_true()
	c.set_processed(false)
	assert_bool(c.is_processed).is_false()


func test_reset_method() -> void:
	var c: Case = Case.new()
	var input_map: Dictionary = {&"in1": 0}
	var output_map: Dictionary = {&"out1": 0}
	var mock_in_pool = mock(ObjectPool) # Using GdUnit's mock
	var mock_out_pool = mock(ObjectPool)

	c.configure_and_reset(10, 20, 1, input_map, 1, output_map, mock_in_pool, mock_out_pool)
	
	var inval: InVal = InVal.new(123)
	var outval: OutVal = OutVal.new("abc")
	c.add_input_value_at_index(0, inval)
	c.add_output_value_by_id(&"out1", outval)
	c.set_processed(true)
	
	# Call reset with new sizes
	c.reset(2, 3) # e.g. case is being reused for a different config (though configure_and_reset is typical)
	
	assert_int(c.case_id).is_equal(-1)
	assert_int(c.seed).is_equal(0)
	assert_bool(c.is_processed).is_false()
	
	assert_int(c.input_values_array.size()).is_equal(2) # New size
	assert_object(c.input_values_array[0]).is_null()   # Should be cleared
	assert_int(c.output_values_array.size()).is_equal(3) # New size
	assert_object(c.output_values_array[0]).is_null()  # Should be cleared
	
	assert_dict(c._input_id_to_idx_map).is_empty()
	assert_dict(c._output_id_to_idx_map).is_empty()

	# Verify values were released to pool
	verify(mock_in_pool).release(inval)
	verify(mock_out_pool).release(outval)
	
	# Test reset with 0 sizes (default)
	c.reset()
	assert_int(c.input_values_array.size()).is_equal(0)
	assert_int(c.output_values_array.size()).is_equal(0)

	# Clean up mocks if necessary (GdUnit usually handles this)
	if mock_in_pool is GdUnitMock: mock_in_pool.free()
	if mock_out_pool is GdUnitMock: mock_out_pool.free()
	
# The old test_initialization is covered by test_initialization_default and test_configure_and_reset
# The old test_add_and_get_input_value is covered by test_indexed_access_input_values and test_id_based_getters_and_output_setter
# The old test_add_and_get_output_value is covered by test_indexed_access_output_values and test_id_based_getters_and_output_setter
# The old test_overwrite_input_value_warns is replaced by test_overwrite_values
# The old test_overwrite_output_value_allows is replaced by test_overwrite_values
# The old test_get_input_value_missing_warns_and_returns_null is replaced by test_get_value_by_id_missing_returns_null
# The old test_get_output_value_missing_returns_null is part of test_get_value_by_id_missing_returns_null
# test_set_processed_flag remains similar.

# The old test_initialization is covered by test_initialization_default and test_configure_and_reset
# The old test_add_and_get_input_value is covered by test_indexed_access_input_values and test_id_based_getters_and_output_setter
# The old test_add_and_get_output_value is covered by test_indexed_access_output_values and test_id_based_getters_and_output_setter
# The old test_overwrite_input_value_warns is replaced by test_overwrite_values
# The old test_overwrite_output_value_allows is replaced by test_overwrite_values
# The old test_get_input_value_missing_warns_and_returns_null is replaced by test_get_value_by_id_missing_returns_null
# The old test_get_output_value_missing_returns_null is part of test_get_value_by_id_missing_returns_null
# test_set_processed_flag remains similar. 
