# res://src/core/case.gd
class_name Case extends RefCounted

## @brief Represents a single simulation run (a "case").
##
## Each Case object holds a unique set of input values (InVal instances)
## in an array, corresponding to an ordered list of input variables (InVar instances),
## and it will later store output values (OutVal instances) similarly.
## It also manages a unique seed for any stochastic processes within the run function.

#region Properties
var case_id: int = -1 ## A unique identifier for this specific simulation case.

## Array storing InVal instances for this case. Index corresponds to InVar order.
var input_values_array: Array[InVal]

## Array storing OutVal instances for this case. Index corresponds to OutVar order.
var output_values_array: Array[OutVal]

var seed: int = 0 ## A repeatable random seed for this case, for use in the run function.
var is_processed: bool = false ## Flag to indicate if this case has been processed by the run function.

# References to global value pools, injected by SimManager
var _in_val_pool_ref: ObjectPool = null
var _out_val_pool_ref: ObjectPool = null

var _num_expected_input_vars: int = 0
var _num_expected_output_vars: int = 0

# ID to Index maps, provided by SimManager
var _input_id_to_idx_map: Dictionary = {}
var _output_id_to_idx_map: Dictionary = {}
#endregion


#region Initialization
# Parameterless _init for object pooling.
func _init() -> void:
	# Call reset to ensure a clean state on direct instantiation too.
	# Initial array sizes will be 0 until configured.
	reset(0, 0) # Initialize with zero expected vars
#endregion


#region Public Methods
## @brief Configures the case for a specific number of input/output variables and resets its state.
## This method should be called by SimManager after acquiring a Case from the pool.
func configure_and_reset(p_case_id: int, p_seed: int, 
		p_num_input_vars: int, p_input_id_map: Dictionary, 
		p_num_output_vars: int, p_output_id_map: Dictionary, 
		p_in_pool: ObjectPool, p_out_pool: ObjectPool) -> void:
	set_value_pools(p_in_pool, p_out_pool)
	reset(p_num_input_vars, p_num_output_vars) # Reset with correct sizes first
	case_id = p_case_id
	seed = p_seed
	_input_id_to_idx_map = p_input_id_map
	_output_id_to_idx_map = p_output_id_map


## @brief Sets the value pools to be used when resetting this case.
func set_value_pools(p_in_val_pool: ObjectPool, p_out_val_pool: ObjectPool) -> void:
	_in_val_pool_ref = p_in_val_pool
	_out_val_pool_ref = p_out_val_pool


## @brief Adds an input value (InVal) to this case at a specific index.
func add_input_value_at_index(idx: int, val: InVal) -> void:
	if idx < 0 or idx >= input_values_array.size():
		push_error("Case %d: Input index %d out of bounds for array size %d." % [case_id, idx, input_values_array.size()])
		assert(false, "Input index out of bounds")
		return
	if input_values_array[idx] != null and _in_val_pool_ref: # Should be null after reset
		push_warning("Case %d: Overwriting existing InVal at index %d. Releasing old one." % [case_id, idx])
		_in_val_pool_ref.release(input_values_array[idx])
	input_values_array[idx] = val


## @brief Retrieves an input value (InVal) from a given index.
func get_input_value_at_index(idx: int) -> InVal:
	if idx < 0 or idx >= input_values_array.size():
		push_warning("Case %d: Input index %d out of bounds for array size %d." % [case_id, idx, input_values_array.size()])
		return null
	return input_values_array[idx]


## @brief Convenience method to retrieve an input value (InVal) by its InVar ID.
func get_input_value_by_id(in_var_id: StringName) -> InVal:
	if not _input_id_to_idx_map.has(in_var_id):
		push_warning("Case %d: Input variable ID '%s' not found in ID-to-Index map." % [case_id, in_var_id])
		return null
	var idx: int = _input_id_to_idx_map[in_var_id]
	return get_input_value_at_index(idx)


## @brief Adds an output value (OutVal) to this case at a specific index.
func add_output_value_at_index(idx: int, val: OutVal) -> void:
	if idx < 0 or idx >= output_values_array.size():
		push_error("Case %d: Output index %d out of bounds for array size %d." % [case_id, idx, output_values_array.size()])
		assert(false, "Output index out of bounds")
		return
	if output_values_array[idx] != null and _out_val_pool_ref: # Should be null after reset
		push_warning("Case %d: Overwriting existing OutVal at index %d. Releasing old one." % [case_id, idx])
		_out_val_pool_ref.release(output_values_array[idx])
	output_values_array[idx] = val


## @brief Retrieves an output value (OutVal) from a given index.
func get_output_value_at_index(idx: int) -> OutVal:
	if idx < 0 or idx >= output_values_array.size():
		# print("Case %d: Output index %d out of bounds for array size %d." % [case_id, idx, output_values_array.size()])
		return null
	return output_values_array[idx]


## @brief Convenience method to add an output value (OutVal) by its OutVar ID.
## This is typically called from the postprocess function.
func add_output_value_by_id(out_var_id: StringName, val: OutVal) -> void:
	if not _output_id_to_idx_map.has(out_var_id):
		push_error("Case %d: Output variable ID '%s' not found in ID-to-Index map. Cannot add value." % [case_id, out_var_id])
		# If the OutVal was potentially acquired from a pool, and we can't add it, it might need releasing.
		# However, the caller (postprocess) is responsible for OutVal lifecycle if it can't be added here.
		# For now, we just error and don't add.
		return
	var idx: int = _output_id_to_idx_map[out_var_id]
	add_output_value_at_index(idx, val)


## @brief Convenience method to retrieve an output value (OutVal) by its OutVar ID.
func get_output_value_by_id(out_var_id: StringName) -> OutVal:
	if not _output_id_to_idx_map.has(out_var_id):
		# It's normal for output values to not exist before postprocessing or if not set for a specific ID.
		# push_warning("Case %d: Output variable ID '%s' not found in ID-to-Index map." % [case_id, out_var_id])
		return null
	var idx: int = _output_id_to_idx_map[out_var_id]
	return get_output_value_at_index(idx)


## @brief Marks the case as processed.
func set_processed(status: bool = true) -> void:
	is_processed = status


## @brief Resets the Case object to a default state for reuse in an object pool.
## If value pools are set, it releases contained InVal/OutVal objects back to them.
## Sizes the internal arrays based on the number of expected variables.
func reset(num_input_vars: int = 0, num_output_vars: int = 0) -> void:
	case_id = -1
	seed = 0
	is_processed = false
	
	_num_expected_input_vars = num_input_vars
	_num_expected_output_vars = num_output_vars

	# Release existing InVal objects and clear/resize array
	if _in_val_pool_ref and not input_values_array.is_empty():
		for inval_to_release in input_values_array:
			if inval_to_release: # Ensure it's not null before releasing
				_in_val_pool_ref.release(inval_to_release)
	input_values_array.clear()
	if _num_expected_input_vars > 0:
		input_values_array.resize(_num_expected_input_vars)
		# Arrays of objects are filled with null by default after resize.

	# Release existing OutVal objects and clear/resize array
	if _out_val_pool_ref and not output_values_array.is_empty():
		for outval_to_release in output_values_array:
			if outval_to_release: # Ensure it's not null before releasing
				_out_val_pool_ref.release(outval_to_release)
	output_values_array.clear()
	if _num_expected_output_vars > 0:
		output_values_array.resize(_num_expected_output_vars)
	
	_input_id_to_idx_map.clear()
	_output_id_to_idx_map.clear()

	# Pool references (_in_val_pool_ref, _out_val_pool_ref) are managed by SimManager via set_value_pools or configure_and_reset.
#endregion 
