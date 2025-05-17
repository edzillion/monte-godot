# res://src/managers/sim_manager.gd
class_name SimManager extends Node

const EasyChartsDataFrame = preload("res://addons/easy_charts/utilities/classes/structures/data_frame.gd")
const EasyChartsMatrix = preload("res://addons/easy_charts/utilities/classes/structures/matrix.gd") # DataFrame uses Matrix
const CaseScript = preload("res://src/core/case.gd")
const InValScript = preload("res://src/core/in_val.gd")
const OutValScript = preload("res://src/core/out_val.gd")

# Constants for automatic batch sizing heuristic
const AUTO_BATCH_DEFAULT_TARGET_PER_BATCH: int = 5000
const AUTO_BATCH_MINIMUM_SIZE: int = 500
const AUTO_BATCH_MAX_TOTAL_BATCHES: int = 1000

## @brief Orchestrates the entire Monte Carlo simulation process.
##
## Manages input and output variables, generates and processes cases (potentially using threads),
## and aggregates results. It coordinates the preprocess, run, and postprocess stages.

#region Signals
signal simulation_started
signal simulation_progress(progress_percentage) # Overall progress across all batches
signal simulation_batch_completed(batch_number: int, total_batches: int, batch_duration_msec: float) # Progress per batch, added duration
signal simulation_completed(results: Variant, overall_duration_msec: float) # Added duration
signal simulation_error(error_message)
#endregion


#region Enums
#endregion


#region Constants
#endregion


#region Static Variables
#endregion


#region Export Variablesl default (all threads)
@export var output_as_dataframe: bool = false ## If true, results are converted to EasyCharts DataFrame
#endregion


#region Regular Variables
var n_cases: int # Total number of random cases to simulate.
var max_threads: int # Number of threads for group tasks.
var batch_size: int # Number of cases to process in a single batch.

var input_variables: Dictionary = {} ## {StringName: InVar}
var output_variables: Dictionary = {} ## {StringName: OutVar}

var _current_batch_cases: Array[Case] = [] # Cases for the current batch being processed
var _all_processed_cases: Array[Case] = [] # Accumulates all cases from all batches IF output_as_dataframe is true

var preprocess_callable: Callable
var run_callable: Callable
var postprocess_callable: Callable

var is_running: bool = false
var _stop_requested: bool = false # Placeholder for future stop functionality

var _current_batch_number: int = 0
var _total_batches: int = 0
var _actual_total_cases_processed_so_far: int = 0 # New counter for all processed cases

var _simulation_start_time_msec: int = 0 # For overall timing
var _current_batch_start_time_msec: int = 0 # For individual batch timing

var _group_task_id: int = -1

# For progress reporting within the current group task/batch
var _cases_processed_in_current_batch: int = 0
var _progress_mutex: Mutex = Mutex.new()
var _case_pool: ObjectPool
var _in_val_pool: ObjectPool # Added
var _out_val_pool: ObjectPool # Added
#endregion


#region Onready Variables
#endregion


#region Static Initialization
#endregion


#region Static Methods
#endregion

#region Helper Methods for Batch Sizing
func _calculate_automatic_batch_size(p_n_cases: int) -> int:
	if p_n_cases <= 0:
		Logger.debug("SimManager: AutoBatch - N_CASES is <= 0, returning default batch size 1.")
		return 1

	var calculated_batch_size: int = AUTO_BATCH_DEFAULT_TARGET_PER_BATCH
	Logger.debug("SimManager: AutoBatch - Initial target: %d" % calculated_batch_size)

	# If the default target per batch would result in too many total batches, adjust.
	if calculated_batch_size > 0 and (float(p_n_cases) / float(calculated_batch_size)) > float(AUTO_BATCH_MAX_TOTAL_BATCHES):
		calculated_batch_size = int(ceil(float(p_n_cases) / float(AUTO_BATCH_MAX_TOTAL_BATCHES)))
		Logger.debug("SimManager: AutoBatch - Adjusted for MAX_TOTAL_BATCHES (%d). New BS: %d" % [AUTO_BATCH_MAX_TOTAL_BATCHES, calculated_batch_size])

	# Ensure batch size isn't below our defined minimum.
	calculated_batch_size = max(calculated_batch_size, AUTO_BATCH_MINIMUM_SIZE)
	Logger.debug("SimManager: AutoBatch - After MINIMUM_SIZE (%d) check. New BS: %d" % [AUTO_BATCH_MINIMUM_SIZE, calculated_batch_size])

	# Ensure batch size isn't larger than the total number of cases.
	calculated_batch_size = min(calculated_batch_size, p_n_cases)
	Logger.debug("SimManager: AutoBatch - After N_CASES (%d) cap. New BS: %d" % [p_n_cases, calculated_batch_size])

	# Ensure it's at least 1.
	var final_batch_size: int = max(1, calculated_batch_size)
	Logger.info("SimManager: AutoBatch - Final calculated batch size: %d for N_CASES: %d" % [final_batch_size, p_n_cases])
	return final_batch_size
#endregion


#region Overridden Built-in Virtual Methods
func _init() -> void:
	pass # Pool initialized in _ready as batch_size might not be set yet


func _ready() -> void:
	Logger.info("SimManager initialized. Ready to configure and run simulations.")
	var initial_case_pool_size = batch_size if batch_size > 0 else 0 # Base initial size on batch_size if known
	_case_pool = ObjectPool.new(CaseScript, initial_case_pool_size, -1)
	Logger.info("SimManager: Case object pool initialized with initial size: %d" % _case_pool.get_pooled_count())

	# Initialize InVal and OutVal pools. Heuristic: batch_size * avg_vars_per_case.
	# For simplicity, let's start with batch_size or a fixed moderate number if batch_size isn't set yet.
	var initial_val_pool_size = batch_size if batch_size > 0 else 100 # Default to 100 if batch_size unknown
	_in_val_pool = ObjectPool.new(InValScript, initial_val_pool_size, -1)
	_out_val_pool = ObjectPool.new(OutValScript, initial_val_pool_size, -1)
	Logger.info("SimManager: InVal pool initialized (initial: %d), OutVal pool initialized (initial: %d)." % [_in_val_pool.get_pooled_count(), _out_val_pool.get_pooled_count()])


func _process(_delta: float) -> void:
	if not is_running or _group_task_id == -1: # Only process if a batch group task is active
		return

	_progress_mutex.lock()
	var processed_in_batch_count = _cases_processed_in_current_batch
	_progress_mutex.unlock()

	if _current_batch_cases.size() > 0:
		#var batch_progress_percentage = float(processed_in_batch_count) / float(_current_batch_cases.size()) * 100.0 # Progress within current batch

		var overall_completed_cases_before_this_batch = (_current_batch_number -1) * batch_size # Corrected base
		var overall_completed_cases = overall_completed_cases_before_this_batch + processed_in_batch_count

		var overall_progress_percentage = 0.0
		if n_cases > 0:
			overall_progress_percentage = float(overall_completed_cases) / float(n_cases) * 100.0

		if Time.get_ticks_msec() % 100 == 0 or processed_in_batch_count == _current_batch_cases.size(): # Throttle
			emit_signal("simulation_progress", overall_progress_percentage)

	if WorkerThreadPool.is_group_task_completed(_group_task_id):
		var batch_end_time_msec: int = Time.get_ticks_msec() # Batch completion time
		var batch_duration_msec: float = float(batch_end_time_msec - _current_batch_start_time_msec)

		WorkerThreadPool.wait_for_group_task_completion(_group_task_id) # Ensure this specific group task is awaited

		_progress_mutex.lock()
		var final_processed_count_for_batch = _cases_processed_in_current_batch
		_progress_mutex.unlock()

		if final_processed_count_for_batch != _current_batch_cases.size():
			Logger.warning("SimManager: Batch %d/%d task completed, but internal counter (%d) != batch case count (%d)." % [_current_batch_number, _total_batches, final_processed_count_for_batch, _current_batch_cases.size()])

		_actual_total_cases_processed_so_far += _current_batch_cases.size() # Increment actual processed count

		if output_as_dataframe:
			_all_processed_cases.append_array(_current_batch_cases)
		else:
			# If not storing for DataFrame, release cases back to pool immediately
			for case_obj in _current_batch_cases:
				if case_obj and _case_pool: # Defensive checks
					_case_pool.release(case_obj)

		Logger.info("SimManager: Batch %d/%d completed in %.2f ms. Processed %d cases. Total cases processed so far: %d. CasePool: %d, InValPool: %d, OutValPool: %d" % [
			_current_batch_number, _total_batches, batch_duration_msec, 
			_current_batch_cases.size(), _actual_total_cases_processed_so_far, 
			_case_pool.get_pooled_count() if _case_pool else -1,
			_in_val_pool.get_pooled_count() if _in_val_pool else -1,
			_out_val_pool.get_pooled_count() if _out_val_pool else -1
		])
		emit_signal("simulation_batch_completed", _current_batch_number, _total_batches, batch_duration_msec)

		var group_task_that_just_completed = _group_task_id # For clarity if needed
		_group_task_id = -1
		_cases_processed_in_current_batch = 0
		_current_batch_cases.clear() # Clear memory for this batch's Case objects. If not output_as_dataframe, refs should drop.

		if _current_batch_number < _total_batches:
			_current_batch_number += 1
			call_deferred("_process_next_batch") # Use call_deferred to avoid potential deep recursion if batches are very small/fast
		else:
			_complete_simulation_all_batches()
#endregion


#region Configuration Methods
## @brief Sets the user-defined functions for the simulation stages.
func set_simulation_functions(p_preprocess: Callable, p_run: Callable, p_postprocess: Callable) -> void:
	if not p_preprocess.is_valid() or not p_run.is_valid() or not p_postprocess.is_valid():
		var error_msg = "SimManager: One or more provided simulation callables are invalid."
		Logger.error(error_msg)
		emit_signal("simulation_error", error_msg)
		return
	preprocess_callable = p_preprocess
	run_callable = p_run
	postprocess_callable = p_postprocess
	Logger.info("SimManager: Simulation functions configured.")


## @brief Adds an input variable to the simulation.
func add_input_variable(in_var: InVar) -> void:
	if not in_var is InVar:
		Logger.error("SimManager: Invalid object passed to add_input_variable. Expected InVar.")
		return
	if input_variables.has(in_var.id):
		Logger.warning("SimManager: Input variable with id '%s' already exists. Overwriting." % in_var.id)
	input_variables[in_var.id] = in_var
	Logger.info("SimManager: Added InVar '%s' (id: %s)" % [in_var.name, in_var.id])


## @brief Adds an output variable to the simulation.
func add_output_variable(out_var: OutVar) -> void:
	if not out_var is OutVar:
		Logger.error("SimManager: Invalid object passed to add_output_variable. Expected OutVar.")
		return
	if output_variables.has(out_var.id):
		Logger.warning("SimManager: Output variable with id '%s' already exists. Overwriting." % out_var.id)
	output_variables[out_var.id] = out_var
	Logger.info("SimManager: Added OutVar '%s' (id: %s)" % [out_var.name, out_var.id])
#endregion


#region Simulation Execution
## @brief Starts the Monte Carlo simulation process.
func run_simulation() -> void:
	if is_running:
		Logger.warning("SimManager: Simulation is already running.")
		return

	if not preprocess_callable.is_valid() or \
	   not run_callable.is_valid() or \
	   not postprocess_callable.is_valid():
		var error_msg = "SimManager: Simulation functions not properly configured."
		Logger.error(error_msg)
		emit_signal("simulation_error", error_msg)
		return

	if n_cases <= 0:
		Logger.info("SimManager: n_cases is %d. Nothing to simulate." % n_cases)
		_complete_simulation_all_batches()
		return

	if batch_size <= 0:
		Logger.error("SimManager: batch_size must be greater than 0.")
		emit_signal("simulation_error", "Invalid batch_size: must be > 0.")
		return
	if batch_size > n_cases: # Optimization: if batch_size is larger than n_cases, just use n_cases
		Logger.warning("SimManager: batch_size (%d) is greater than n_cases (%d). Setting batch_size to n_cases." % [batch_size, n_cases])
		batch_size = n_cases


	Logger.info("SimManager: Starting simulation with %d total cases, batch size %d." % [n_cases, batch_size])
	_simulation_start_time_msec = Time.get_ticks_msec() # Record overall start time HERE
	is_running = true
	_stop_requested = false
	_all_processed_cases.clear()
	_current_batch_cases.clear()
	_cases_processed_in_current_batch = 0
	_actual_total_cases_processed_so_far = 0 # Reset counter
	_group_task_id = -1 # Ensure it's reset

	_total_batches = int(ceil(float(n_cases) / float(batch_size)))
	_current_batch_number = 1 # Start with the first batch

	# Configure all input variables for the total n_cases.
	# Actual sampling will happen on demand per case.
	Logger.info("SimManager: Configuring all input variables for %d total cases..." % n_cases)
	for in_var_id in input_variables:
		var in_var: InVar = input_variables[in_var_id]
		in_var.configure_for_simulation(n_cases) # Changed from sample_values
	Logger.info("SimManager: Input variable configuration complete.")

	# Ensure pools are ready
	if not _case_pool: # Should be initialized in _ready, but defensive
		_case_pool = ObjectPool.new(CaseScript, batch_size if batch_size > 0 else 0, -1)
		Logger.warning("SimManager: Case pool re-initialized in run_simulation.")
	if not _in_val_pool:
		_in_val_pool = ObjectPool.new(InValScript, batch_size if batch_size > 0 else 100, -1)
		Logger.warning("SimManager: InVal pool re-initialized in run_simulation.")
	if not _out_val_pool:
		_out_val_pool = ObjectPool.new(OutValScript, batch_size if batch_size > 0 else 100, -1)
		Logger.warning("SimManager: OutVal pool re-initialized in run_simulation.")

	emit_signal("simulation_started")
	_process_next_batch() # Start the first batch


func _process_next_batch() -> void:
	if _stop_requested:
		Logger.info("SimManager: Stop requested by user. Halting batch processing.")
		_complete_simulation_all_batches()
		return

	var case_offset = (_current_batch_number - 1) * batch_size
	# Calculate number of cases for this specific batch (can be less than batch_size for the last batch)
	var num_cases_in_this_batch = min(batch_size, n_cases - case_offset)

	if num_cases_in_this_batch <= 0:
		Logger.info("SimManager: No more cases to process in new batch calculation (num_cases_in_this_batch = %d). Finalizing." % num_cases_in_this_batch)
		_complete_simulation_all_batches()
		return

	Logger.info("SimManager: Preparing Batch %d/%d. Overall cases %d to %d (count: %d)." % [_current_batch_number, _total_batches, case_offset, case_offset + num_cases_in_this_batch - 1, num_cases_in_this_batch])
	_current_batch_start_time_msec = Time.get_ticks_msec()

	_current_batch_cases.clear()
	if num_cases_in_this_batch > 0:
		_current_batch_cases.resize(num_cases_in_this_batch)

	# Generate Case objects ONLY for the current batch
	for i in range(num_cases_in_this_batch):
		var overall_case_index = case_offset + i

		var case_seed: int = wrapi(_simulation_start_time_msec + overall_case_index, -2147483648, 2147483647)

		var new_case: Case = null
		if _case_pool:
			new_case = _case_pool.acquire() as Case

		if not new_case:
			Logger.error("SimManager: Failed to acquire Case from pool. Creating Case directly.")
			new_case = CaseScript.new() as Case
			if not new_case: 
				Logger.critical("SimManager: CRITICAL - Failed to create Case object. Halting batch.")
				return
		
		new_case.case_id = overall_case_index
		new_case.seed = case_seed
		# Inject value pools into the case for its reset() method to use
		if _in_val_pool and _out_val_pool: # Ensure pools are valid
			new_case.set_value_pools(_in_val_pool, _out_val_pool)
		else:
			Logger.error("SimManager: InVal/OutVal pools not initialized when setting on Case. This is a bug.")

		for in_var_id in input_variables:
			var in_var: InVar = input_variables[in_var_id]
			# Pass the InVal pool to get_value_for_case
			var sampled_in_val: InVal = in_var.get_value_for_case(overall_case_index, _in_val_pool) 
			if sampled_in_val:
				new_case.add_input_value(in_var.id, sampled_in_val)
			else:
				Logger.error("SimManager: Failed to get sampled InVal (potentially from pool) for InVar '%s' for case %d." % [in_var.id, overall_case_index])

		_current_batch_cases[i] = new_case

	if _current_batch_cases.is_empty() and num_cases_in_this_batch > 0: # Should not happen if resize worked
		Logger.error("SimManager: Batch %d/%d prepared but _current_batch_cases is empty despite num_cases_in_this_batch = %d. Critical error." % [_current_batch_number, _total_batches, num_cases_in_this_batch])
		emit_signal("simulation_error", "Critical error preparing batch: empty case array.")
		is_running = false
		return

	if _current_batch_cases.is_empty() and num_cases_in_this_batch == 0: # This is fine, means last batch was exact.
		Logger.info("SimManager: No cases for current batch %d processing, likely end of simulation." % _current_batch_number)
		# This path should ideally be caught by `_current_batch_number < _total_batches` in _process loop
		if _current_batch_number >= _total_batches :
			_complete_simulation_all_batches()
		else: # Should not happen if logic is correct
			Logger.warning("SimManager: Empty batch generated but not all batches are done. Check logic.")
			_current_batch_number +=1
			call_deferred("_process_next_batch")
		return


	# Submit current batch to WorkerThreadPool
	var threads_for_group: int = max_threads
	if max_threads <= 0: # Treat 0 or negative as default (all threads)
		threads_for_group = -1

	Logger.info("SimManager: Submitting %d cases for batch %d/%d as a group task, requesting %s threads." % [_current_batch_cases.size(), _current_batch_number, _total_batches, str(threads_for_group if threads_for_group != -1 else "all")])

	var group_action: Callable = Callable(self, "_process_case_group_element_for_batch")
	_cases_processed_in_current_batch = 0 # Reset counter for this new batch
	_group_task_id = WorkerThreadPool.add_group_task(group_action, _current_batch_cases.size(), threads_for_group, false, "SimManager Batch %d" % _current_batch_number)

	if _group_task_id == -1 : # Check if group task submission failed
		var error_msg = "SimManager: Failed to submit group task for batch %d/%d." % [_current_batch_number, _total_batches]
		Logger.error(error_msg)
		emit_signal("simulation_error", error_msg)
		is_running = false
		return


## @brief Processes a single element of the case group for the current batch. Called by WorkerThreadPool.
## The 'p_batch_element_index' is the index of the case *within the _current_batch_cases array*.
## The '_p_userdata' is currently unused but part of the Callable signature for group tasks.
func _process_case_group_element_for_batch(p_batch_element_index: int, _p_userdata: Variant = null) -> void:
	# Logger.debug("SimManager: Worker thread (ID: %s) processing batch element index %d for batch %d." % [OS.get_thread_caller_id(), p_batch_element_index, _current_batch_number])

	if p_batch_element_index < 0 or p_batch_element_index >= _current_batch_cases.size():
		Logger.error("SimManager: _process_case_group_element_for_batch called with invalid index %d for batch %d. Current batch size: %d" % [p_batch_element_index, _current_batch_number, _current_batch_cases.size()])
		return

	var case_to_process: Case = _current_batch_cases[p_batch_element_index]
	if not case_to_process: # Should not happen if array is populated correctly
		Logger.error("SimManager: No case object found at batch index %d in _process_case_group_element_for_batch for batch %d." % [p_batch_element_index, _current_batch_number])
		return

	# Defensive checks for callables
	if not preprocess_callable.is_valid() or not run_callable.is_valid() or not postprocess_callable.is_valid():
		Logger.error("SimManager: A callable became invalid within threaded execution for batch %d, case %d (batch index %d)." % [_current_batch_number, case_to_process.case_id, p_batch_element_index])
		return # This element will not be processed, leading to count mismatch warning later.

	# a. Preprocess
	var preprocess_args: Array = [case_to_process]
	var run_inputs: Variant = preprocess_callable.callv(preprocess_args)

	# b. Run
	var run_outputs: Variant
	if run_inputs is Array:
		run_outputs = run_callable.callv(run_inputs)
	else:
		if run_inputs != null or run_callable.get_argument_count() > 0:
			run_outputs = run_callable.call(run_inputs)
		else:
			run_outputs = run_callable.call()

	# c. Postprocess - pass the OutVal pool
	var postprocess_args: Array = [case_to_process, run_outputs, _out_val_pool] # Added _out_val_pool
	postprocess_callable.callv(postprocess_args)

	case_to_process.set_processed(true)

	_progress_mutex.lock()
	_cases_processed_in_current_batch += 1
	_progress_mutex.unlock()


## @brief Finalizes the simulation after all batches are completed and emits completion signal.
func _complete_simulation_all_batches() -> void:
	if not is_running and _actual_total_cases_processed_so_far == 0 and n_cases > 0 : # Check actual processed
		Logger.warning("SimManager: _complete_simulation_all_batches called but simulation wasn't fully running or no cases processed. n_cases: %d, actual_processed: %d" % [n_cases, _actual_total_cases_processed_so_far])
		is_running = false
		_stop_requested = false
		# Potentially emit error or complete with empty if this state is problematic
		# For now, ensure is_running is false and return to prevent further issues.
		# emit_signal("simulation_error", "Simulation ended prematurely or with no processed cases despite n_cases > 0.")
		return

	if not is_running and n_cases == 0: # Specific case for 0 n_cases from start
		Logger.info("SimManager: Simulation completed with 0 cases as per configuration.")
		var duration_zero_case_run: float = float(Time.get_ticks_msec() - _simulation_start_time_msec) if _simulation_start_time_msec > 0 else 0.0
		emit_signal("simulation_completed", [], duration_zero_case_run)
		is_running = false # ensure
		return

	# Check if already completed (idempotency check)
	# If is_running is already false, and we had processed some cases or n_cases was >0 (and not the zero case run),
	# it implies completion logic might have run.
	if not is_running and (_actual_total_cases_processed_so_far > 0 or (n_cases > 0 and _actual_total_cases_processed_so_far == 0 and not _stop_requested)): # More robust check for prior completion
		Logger.info("SimManager: _complete_simulation_all_batches called again after completion or in an inconsistent state. Current actual processed: %d. Ignoring." % _actual_total_cases_processed_so_far)
		return

	is_running = false # Set this early
	_stop_requested = false

	var simulation_end_time_msec: int = Time.get_ticks_msec()
	var overall_duration_msec: float = float(simulation_end_time_msec - _simulation_start_time_msec) if _simulation_start_time_msec > 0 else 0.0

	Logger.info("SimManager: All %d batches completed. Total cases processed: %d. Overall time: %.2f ms." % [_total_batches if _total_batches > 0 else _current_batch_number, _actual_total_cases_processed_so_far, overall_duration_msec])
	if _actual_total_cases_processed_so_far != n_cases and n_cases > 0 :
		Logger.warning("SimManager: Final actual processed case count %d does not match requested n_cases %d." % [_actual_total_cases_processed_so_far, n_cases])


	var final_results: Variant = [] # Default to empty array; populated only if output_as_dataframe is true.
	if output_as_dataframe:
		if not _all_processed_cases.is_empty(): # Check if _all_processed_cases has content
			Logger.info("SimManager: Converting %d accumulated cases to DataFrame..." % _all_processed_cases.size())
			final_results = _convert_cases_to_dataframe(_all_processed_cases)
		elif _actual_total_cases_processed_so_far > 0: # Some cases were processed, but not stored for DataFrame
			Logger.warning("SimManager: output_as_dataframe is true, but no cases were accumulated in _all_processed_cases (e.g., if it was cleared prematurely). DataFrame will be empty despite %d cases processed." % _actual_total_cases_processed_so_far)
			# final_results remains an empty array
		else: # No cases processed at all
			Logger.info("SimManager: No cases processed, DataFrame will be empty.")
			# final_results remains an empty array


	emit_signal("simulation_completed", final_results, overall_duration_msec)

	# Clean up for next potential run
	if output_as_dataframe and not _all_processed_cases.is_empty():
		Logger.info("SimManager: Releasing %d accumulated Case objects back to pool." % _all_processed_cases.size())
		for case_obj in _all_processed_cases:
			if case_obj and _case_pool:
				_case_pool.release(case_obj)

	_all_processed_cases.clear() # Clear the accumulated results (if any)
	_current_batch_cases.clear() # Should be empty already but clear just in case
	_cases_processed_in_current_batch = 0
	_actual_total_cases_processed_so_far = 0 # Reset counter
	_current_batch_number = 0
	_total_batches = 0
	_group_task_id = -1 # Ensure reset
	Logger.info("SimManager: Simulation finalized and cleaned up.")


## @brief Converts an array of Case objects to an EasyCharts DataFrame.
func _convert_cases_to_dataframe(p_processed_cases: Array[Case]) -> EasyChartsDataFrame:
	if p_processed_cases.is_empty(): # Guard against empty array
		Logger.warning("SimManager: No cases provided to _convert_cases_to_dataframe. Returning empty DataFrame.")
		var empty_matrix_for_df = EasyChartsMatrix.new() # Matrix might need to be non-null
		return EasyChartsDataFrame.new(empty_matrix_for_df) # Ensure EasyChartsDataFrame handles empty matrix gracefully

	var headers: PackedStringArray = []
	var case_ids_as_labels: PackedStringArray = []
	var data_rows: Array = [] # Array of arrays for matrix data

	# Determine headers from the first case (assuming all cases have same InVar/OutVar structure)
	var first_case: Case = p_processed_cases[0]
	headers.append("CaseID")
	for invar_id in first_case.input_values.keys():
		headers.append(str(invar_id))
	for outvar_id in first_case.output_values.keys():
		headers.append(str(outvar_id))

	# Populate data_rows and case_ids_as_labels
	for case_obj in p_processed_cases:
		if not case_obj is Case: # Defensive check
			Logger.warning("SimManager: Non-Case object found in p_processed_cases during DataFrame conversion. Skipping. ID: %s" % str(case_obj))
			continue
		case_ids_as_labels.append(str(case_obj.case_id))
		var current_row_data: Array = []
		current_row_data.append(case_obj.case_id)

		# Add InVal values - ensure order matches headers for robustness
		for invar_id_key in first_case.input_values.keys(): # Iterate using first_case keys for order
			var inval: InVal = case_obj.get_input_value(invar_id_key) # Use the key from header loop
			current_row_data.append(inval.get_value() if inval else null)

		# Add OutVal values - ensure order matches headers
		for outvar_id_key in first_case.output_values.keys(): # Iterate using first_case keys for order
			var outval: OutVal = case_obj.get_output_value(outvar_id_key) # Use the key from header loop
			current_row_data.append(outval.get_value() if outval else null)

		data_rows.append(current_row_data)

	if data_rows.is_empty() and not p_processed_cases.is_empty() : # All cases were invalid?
		Logger.warning("SimManager: DataFrame data_rows is empty after processing %d cases. Returning empty DataFrame." % p_processed_cases.size())
		var empty_matrix_for_df_2 = EasyChartsMatrix.new()
		return EasyChartsDataFrame.new(empty_matrix_for_df_2, headers if not headers.is_empty() else PackedStringArray())


	var matrix_data = EasyChartsMatrix.new(data_rows)
	var df_name = "SimulationResults_Batched_" + Time.get_datetime_string_from_system(true, true).replace(":", "-").replace(" ", "_")
	var df: EasyChartsDataFrame = EasyChartsDataFrame.new(matrix_data, headers, case_ids_as_labels, df_name)
	if df:
		Logger.info("SimManager: Results converted to DataFrame '%s' (%d rows, %d cols)" % [df.name, df.row_count(), df.column_count()])
	else: # Should not happen if EasyChartsDataFrame.new is robust
		Logger.error("SimManager: Failed to create DataFrame object even with data. Returning.")
		# This should ideally return an empty DataFrame or handle error, not implicitly return null if df creation fails
		# For now, assuming EasyChartsDataFrame.new returns a valid (potentially empty) object or crashes itself.
		# To be safe, let's ensure we return *something* of the expected type if it could be null.
		var empty_df_on_failure = EasyChartsDataFrame.new(EasyChartsMatrix.new())
		return empty_df_on_failure if not df else df
	return df
#endregion

#endregion


#region Subclasses
#endregion


#region State
#endregion


#region Events
#endregion 
