# res://src/managers/sim_manager.gd
class_name SimManager extends Node

const EasyChartsDataFrame = preload("res://addons/easy_charts/utilities/classes/structures/data_frame.gd")
const EasyChartsMatrix = preload("res://addons/easy_charts/utilities/classes/structures/matrix.gd") # DataFrame uses Matrix
const CaseScript = preload("res://src/core/case.gd")
const InValScript = preload("res://src/core/in_val.gd")
const OutValScript = preload("res://src/core/out_val.gd")
const InVarScript = preload("res://src/core/in_var.gd")
const OutVarScript = preload("res://src/core/out_var.gd")

# Constants for automatic batch sizing heuristic
const AUTO_BATCH_DEFAULT_TARGET_PER_BATCH: int = 5000
const AUTO_BATCH_MINIMUM_SIZE: int = 500
const AUTO_BATCH_MAX_TOTAL_BATCHES: int = 1000

## @brief Orchestrates the entire Monte Carlo simulation process.
##
## Manages input and output variables, generates and processes cases (potentially using threads),
## and aggregates results. It coordinates the preprocess, run, and postprocess stages.

#region Signals
signal simulation_started(run_id: String)
signal simulation_progress(progress_percentage) # Overall progress across all batches
signal simulation_batch_completed(batch_number: int, total_batches: int, batch_duration_msec: float) # Progress per batch, added duration
signal simulation_completed(run_id: String, results: Variant, overall_duration_msec: float, actual_batch_size: int, total_batches_executed: int)
signal simulation_error(run_id: String, error_message: String)
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
var run_id: String # Unique ID for the current simulation run
var n_cases: int # Total number of random cases to simulate.
var max_threads: int # Number of threads for group tasks.
var batch_size: int # Number of cases to process in a single batch.

var input_variables: Dictionary = {} ## {StringName (id): InVar object}
var output_variables: Dictionary = {} ## {StringName (id): OutVar object}

# Ordered lists of variable IDs for consistent indexing
var _input_var_ids_ordered: Array[StringName] = []
var _output_var_ids_ordered: Array[StringName] = []

# ID to index maps, generated when simulation starts
var _input_id_to_idx_map: Dictionary = {}
var _output_id_to_idx_map: Dictionary = {}

var _current_batch_cases: Array[Case] = [] # Cases for the current batch being processed
var _all_processed_cases: Array[Case] = [] # Accumulates all cases from all batches IF output_as_dataframe is true

var preprocess_callable: Callable
var run_callable: Callable
var postprocess_callable: Callable

var is_running: bool = false
var _stop_requested: bool = false # Placeholder for future stop functionality

var _current_batch_number: int = 0
var _total_batches: int = 0
var _actual_total_cases_processed_so_far: int = 0

var _simulation_start_time_msec: int = 0
var _current_batch_start_time_msec: int = 0

var _group_task_id: int = -1

var _cases_processed_in_current_batch: int = 0
var _progress_mutex: Mutex = Mutex.new()
var _case_pool: ObjectPool
var _in_val_pool: ObjectPool
var _out_val_pool: ObjectPool
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

	if calculated_batch_size > 0 and (float(p_n_cases) / float(calculated_batch_size)) > float(AUTO_BATCH_MAX_TOTAL_BATCHES):
		calculated_batch_size = int(ceil(float(p_n_cases) / float(AUTO_BATCH_MAX_TOTAL_BATCHES)))
		Logger.debug("SimManager: AutoBatch - Adjusted for MAX_TOTAL_BATCHES (%d). New BS: %d" % [AUTO_BATCH_MAX_TOTAL_BATCHES, calculated_batch_size])

	calculated_batch_size = max(calculated_batch_size, AUTO_BATCH_MINIMUM_SIZE)
	Logger.debug("SimManager: AutoBatch - After MINIMUM_SIZE (%d) check. New BS: %d" % [AUTO_BATCH_MINIMUM_SIZE, calculated_batch_size])

	calculated_batch_size = min(calculated_batch_size, p_n_cases)
	Logger.debug("SimManager: AutoBatch - After N_CASES (%d) cap. New BS: %d" % [p_n_cases, calculated_batch_size])

	var final_batch_size: int = max(1, calculated_batch_size)
	Logger.info("SimManager: AutoBatch - Final calculated batch size: %d for N_CASES: %d" % [final_batch_size, p_n_cases])
	return final_batch_size
#endregion


#region Overridden Built-in Virtual Methods
func _init() -> void:
	pass

func _ready() -> void:
	Logger.info("SimManager initialized. Ready to configure and run simulations.")
	var initial_case_pool_size = batch_size if batch_size > 0 else AUTO_BATCH_DEFAULT_TARGET_PER_BATCH # Updated initial size heuristic
	_case_pool = ObjectPool.new(CaseScript, initial_case_pool_size, -1)
	Logger.info("SimManager: Case object pool initialized with initial size: %d" % _case_pool.get_pooled_count())

	var initial_val_pool_size = batch_size if batch_size > 0 else AUTO_BATCH_DEFAULT_TARGET_PER_BATCH 
	_in_val_pool = ObjectPool.new(InValScript, initial_val_pool_size * 5, -1) # Assume avg 5 InVals per Case initially
	_out_val_pool = ObjectPool.new(OutValScript, initial_val_pool_size * 5, -1) # Assume avg 5 OutVals per Case initially
	Logger.info("SimManager: InVal pool initialized (initial: %d), OutVal pool initialized (initial: %d)." % [_in_val_pool.get_pooled_count(), _out_val_pool.get_pooled_count()])


func _process(_delta: float) -> void:
	if not is_running or _group_task_id == -1:
		return

	_progress_mutex.lock()
	var processed_in_batch_count = _cases_processed_in_current_batch
	_progress_mutex.unlock()

	if _current_batch_cases.size() > 0:
		var overall_completed_cases_before_this_batch = (_current_batch_number -1) * batch_size
		var overall_completed_cases = overall_completed_cases_before_this_batch + processed_in_batch_count

		var overall_progress_percentage = 0.0
		if n_cases > 0:
			overall_progress_percentage = float(overall_completed_cases) / float(n_cases) * 100.0

		if Time.get_ticks_msec() % 100 == 0 or processed_in_batch_count == _current_batch_cases.size():
			emit_signal("simulation_progress", overall_progress_percentage)

	if WorkerThreadPool.is_group_task_completed(_group_task_id):
		var batch_end_time_msec: int = Time.get_ticks_msec()
		var batch_duration_msec: float = float(batch_end_time_msec - _current_batch_start_time_msec)

		WorkerThreadPool.wait_for_group_task_completion(_group_task_id)

		_progress_mutex.lock()
		var final_processed_count_for_batch = _cases_processed_in_current_batch
		_progress_mutex.unlock()

		if final_processed_count_for_batch != _current_batch_cases.size():
			Logger.warning("SimManager: Batch %d/%d task completed, but internal counter (%d) != batch case count (%d)." % [_current_batch_number, _total_batches, final_processed_count_for_batch, _current_batch_cases.size()])

		_actual_total_cases_processed_so_far += _current_batch_cases.size()

		if output_as_dataframe:
			_all_processed_cases.append_array(_current_batch_cases)
		else:
			for case_obj in _current_batch_cases:
				if case_obj and _case_pool:
					_case_pool.release(case_obj)

		Logger.info("SimManager: Batch %d/%d completed in %.2f ms. Processed %d cases. Total cases processed so far: %d. CasePool: %d, InValPool: %d, OutValPool: %d" % [
			_current_batch_number, _total_batches, batch_duration_msec, 
			_current_batch_cases.size(), _actual_total_cases_processed_so_far, 
			_case_pool.get_pooled_count() if _case_pool else -1,
			_in_val_pool.get_pooled_count() if _in_val_pool else -1,
			_out_val_pool.get_pooled_count() if _out_val_pool else -1
		])
		emit_signal("simulation_batch_completed", _current_batch_number, _total_batches, batch_duration_msec)

		_group_task_id = -1
		_cases_processed_in_current_batch = 0
		_current_batch_cases.clear()

		if _current_batch_number < _total_batches:
			_current_batch_number += 1
			call_deferred("_process_next_batch")
		else:
			_complete_simulation_all_batches()
#endregion


#region Configuration Methods
func set_simulation_functions(p_preprocess: Callable, p_run: Callable, p_postprocess: Callable) -> void:
	if not p_preprocess.is_valid() or not p_run.is_valid() or not p_postprocess.is_valid():
		var error_msg = "SimManager: One or more provided simulation callables are invalid."
		Logger.error(error_msg)
		emit_signal("simulation_error", "", error_msg)
		return
	preprocess_callable = p_preprocess
	run_callable = p_run
	postprocess_callable = p_postprocess
	Logger.info("SimManager: Simulation functions configured.")


func add_input_variable(in_var: InVar) -> void:
	if not in_var is InVarScript:
		Logger.error("SimManager: Invalid object passed to add_input_variable. Expected InVar.")
		return
	if input_variables.has(in_var.id):
		Logger.warning("SimManager: Input variable with id '%s' already exists. Overwriting definition and position in order." % in_var.id)
		# Remove from ordered list if it exists to re-add at the end
		if _input_var_ids_ordered.has(in_var.id):
			_input_var_ids_ordered.erase(in_var.id)
	else:
		Logger.info("SimManager: Added InVar '%s' (id: %s)" % [in_var.name, in_var.id])
	
	input_variables[in_var.id] = in_var
	_input_var_ids_ordered.append(in_var.id) # Add to ordered list


func add_output_variable(out_var: OutVar) -> void:
	if not out_var is OutVarScript:
		Logger.error("SimManager: Invalid object passed to add_output_variable. Expected OutVar.")
		return
	if output_variables.has(out_var.id):
		Logger.warning("SimManager: Output variable with id '%s' already exists. Overwriting definition and position in order." % out_var.id)
		if _output_var_ids_ordered.has(out_var.id):
			_output_var_ids_ordered.erase(out_var.id)
	else:
		Logger.info("SimManager: Added OutVar '%s' (id: %s)" % [out_var.name, out_var.id])
	
	output_variables[out_var.id] = out_var
	_output_var_ids_ordered.append(out_var.id) # Add to ordered list
#endregion


#region Simulation Execution
func run_simulation(
		p_n_cases: int,
		p_preprocess_callable: Callable,
		p_run_callable: Callable,
		p_postprocess_callable: Callable,
		p_max_threads_override: int, # Renamed from p_max_threads for clarity if different from member
		p_batch_size_override: int,
		p_input_vars_dict: Dictionary, # Changed from Array[InVar] to Dictionary
		p_output_vars_dict: Dictionary, # Changed from Array[OutVar] to Dictionary
		p_output_as_dataframe: bool,
		p_in_var_use_pregeneration_override: bool # New parameter
	) -> bool:

	if is_running:
		Logger.warning("SimManager (Run ID: %s): Simulation is already running. Cannot start new one." % run_id)
		return false

	if not p_preprocess_callable.is_valid() or not p_run_callable.is_valid() or not p_postprocess_callable.is_valid():
		var error_msg = "SimManager: One or more provided simulation callables are invalid for run_simulation."
		Logger.error(error_msg)
		# emit_signal("simulation_error", "", error_msg) # run_id not generated yet
		return false
	
	# Use provided callables for this run
	preprocess_callable = p_preprocess_callable
	run_callable = p_run_callable
	postprocess_callable = p_postprocess_callable

	# Configure basic parameters for this run
	self.n_cases = p_n_cases
	self.max_threads = p_max_threads_override
	self.output_as_dataframe = p_output_as_dataframe
	
	# Clear and rebuild input/output variable structures for this run
	input_variables.clear()
	_input_var_ids_ordered.clear()
	_input_id_to_idx_map.clear()
	
	for id_key in p_input_vars_dict:
		var invar = p_input_vars_dict[id_key]
		if invar is InVarScript:
			input_variables[id_key] = invar
			_input_var_ids_ordered.append(id_key)
		else:
			Logger.error("SimManager: Invalid object found in p_input_vars_dict for key '%s'. Expected InVar." % str(id_key))
			# Potentially return false or skip this var

	for i in range(_input_var_ids_ordered.size()):
		_input_id_to_idx_map[_input_var_ids_ordered[i]] = i

	output_variables.clear()
	_output_var_ids_ordered.clear()
	_output_id_to_idx_map.clear()

	for id_key in p_output_vars_dict:
		var outvar = p_output_vars_dict[id_key]
		if outvar is OutVarScript:
			output_variables[id_key] = outvar
			_output_var_ids_ordered.append(id_key)
		else:
			Logger.error("SimManager: Invalid object found in p_output_vars_dict for key '%s'. Expected OutVar." % str(id_key))
			# Potentially return false or skip

	for i in range(_output_var_ids_ordered.size()):
		_output_id_to_idx_map[_output_var_ids_ordered[i]] = i
		
	# Validate essential configurations
	if self.n_cases <= 0:
		var n_cases_error_msg = "SimManager: Number of cases (n_cases) must be greater than 0."
		Logger.error(n_cases_error_msg)
		# emit_signal("simulation_error", "", n_cases_error_msg) # run_id not generated yet
		return false
	
	if input_variables.is_empty() and self.n_cases > 0:
		# Allow running with no input vars if preprocess can handle it or if n_cases is 0 (though already checked)
		Logger.warning("SimManager: Running simulation with no input variables defined.")

	# Determine actual batch size
	var effective_batch_size: int = p_batch_size_override
	if effective_batch_size == 0: # 0 triggers auto-calculation
		effective_batch_size = _calculate_automatic_batch_size(self.n_cases)
	
	effective_batch_size = min(effective_batch_size, self.n_cases) # Cannot be larger than n_cases
	effective_batch_size = max(1, effective_batch_size) # Must be at least 1
	
	self.batch_size = effective_batch_size # Store the finally determined batch size

	# Configure InVars with the override and total number of cases
	for id_key in input_variables:
		var iv = input_variables[id_key]
		if iv is InVarScript: # Double check type
			iv.use_pregeneration = p_in_var_use_pregeneration_override # Apply override
			iv.configure_for_simulation(self.n_cases)
		else:
			Logger.error("SimManager: Non-InVar object found in input_variables during configuration for key: %s. Skipping." % str(id_key))


	is_running = true
	_stop_requested = false
	_current_batch_number = 1
	_actual_total_cases_processed_so_far = 0
	_simulation_start_time_msec = Time.get_ticks_msec()
	
	# Generate Run ID (4-char alphanumeric)
	var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	run_id = ""
	for _i in range(4):
		run_id += chars[randi() % chars.length()]
	run_id += "_" + str(Time.get_ticks_msec() % 1000) # Add some timestamp to make it more unique quickly

	Logger.info("SimManager: Simulation run '%s' starting. N_Cases: %d, Threads: %s, BatchSize: %d, OutputAsDF: %s" % [
		run_id, self.n_cases, str(self.max_threads) if self.max_threads > 0 else "All", self.batch_size, str(self.output_as_dataframe)
	])
	emit_signal("simulation_started", run_id)

	if self.n_cases == 0: # Should have been caught earlier, but as a safeguard
		_complete_simulation_all_batches()
		return true # Technically started and completed.

	_total_batches = ceil(float(self.n_cases) / float(self.batch_size))
	
	# Ensure pools can handle at least one batch -- REMOVING ensure_capacity CALLS
	# var required_pool_size = self.batch_size
	# if _case_pool: _case_pool.ensure_capacity(required_pool_size)
	# if _in_val_pool: _in_val_pool.ensure_capacity(required_pool_size * input_variables.size() if not input_variables.is_empty() else required_pool_size)
	# if _out_val_pool: _out_val_pool.ensure_capacity(required_pool_size * output_variables.size() if not output_variables.is_empty() else required_pool_size)

	if output_as_dataframe:
		_all_processed_cases.clear()
		# _all_processed_cases.resize(self.n_cases) # Potentially pre-allocate if it helps, but nulls are an issue
	else:
		_all_processed_cases.clear() # Ensure it's clear if not used

	call_deferred("_process_next_batch")
	return true


func _process_next_batch() -> void:
	if _stop_requested:
		Logger.info("SimManager (Run ID: %s): Stop requested by user. Halting batch processing." % run_id)
		_complete_simulation_all_batches()
		return

	var case_offset = (_current_batch_number - 1) * self.batch_size # Use self.batch_size
	var num_cases_in_this_batch = min(self.batch_size, n_cases - case_offset) # Use self.batch_size

	if num_cases_in_this_batch <= 0:
		Logger.info("SimManager (Run ID: %s): No more cases to process in new batch calculation. Finalizing." % run_id)
		_complete_simulation_all_batches()
		return

	Logger.info("SimManager (Run ID: %s): Preparing Batch %d/%d. Overall cases %d to %d (count: %d)." % [run_id, _current_batch_number, _total_batches, case_offset, case_offset + num_cases_in_this_batch - 1, num_cases_in_this_batch])
	_current_batch_start_time_msec = Time.get_ticks_msec()

	_current_batch_cases.clear()
	if num_cases_in_this_batch > 0:
		_current_batch_cases.resize(num_cases_in_this_batch)

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
		
		new_case.configure_and_reset(overall_case_index, case_seed, \
			_input_var_ids_ordered.size(), _input_id_to_idx_map, \
			_output_var_ids_ordered.size(), _output_id_to_idx_map, \
			_in_val_pool, _out_val_pool)

		for input_idx in range(_input_var_ids_ordered.size()):
			var in_var_id: StringName = _input_var_ids_ordered[input_idx]
			var in_var: InVar = input_variables[in_var_id]
			var sampled_in_val: InVal = in_var.get_value_for_case(overall_case_index, _in_val_pool) 
			if sampled_in_val:
				new_case.add_input_value_at_index(input_idx, sampled_in_val)
			else:
				Logger.error("SimManager: Failed to get sampled InVal for InVar '%s' (idx %d) for case %d." % [in_var_id, input_idx, overall_case_index])

		_current_batch_cases[i] = new_case

	if _current_batch_cases.is_empty() and num_cases_in_this_batch > 0:
		Logger.error("SimManager: Batch %d/%d prepared but _current_batch_cases is empty despite num_cases_in_this_batch = %d. Critical error." % [run_id, _current_batch_number, _total_batches, num_cases_in_this_batch])
		emit_signal("simulation_error", run_id, "Critical error preparing batch: empty case array.")
		is_running = false
		return

	if _current_batch_cases.is_empty() and num_cases_in_this_batch == 0:
		Logger.info("SimManager: No cases for current batch %d processing, likely end of simulation." % _current_batch_number)
		if _current_batch_number >= _total_batches :
			_complete_simulation_all_batches()
		else:
			Logger.warning("SimManager: Empty batch generated but not all batches are done. Check logic.")
			_current_batch_number +=1
			call_deferred("_process_next_batch")
		return

	var threads_for_group: int = max_threads
	if max_threads <= 0:
		threads_for_group = -1

	Logger.info("SimManager (Run ID: %s): Submitting %d cases for batch %d/%d as a group task, requesting %s threads." % [run_id, _current_batch_cases.size(), _current_batch_number, _total_batches, str(threads_for_group if threads_for_group != -1 else "all")])

	var group_action: Callable = Callable(self, "_process_case_group_element_for_batch")
	_cases_processed_in_current_batch = 0
	_group_task_id = WorkerThreadPool.add_group_task(group_action, _current_batch_cases.size(), threads_for_group, false, "SimManager Batch %d" % _current_batch_number)

	if _group_task_id == -1 :
		var error_msg = "SimManager (Run ID: %s): Failed to submit group task for batch %d/%d." % [run_id, _current_batch_number, _total_batches]
		Logger.error(error_msg)
		emit_signal("simulation_error", run_id, error_msg)
		is_running = false
		return


func _process_case_group_element_for_batch(p_batch_element_index: int, _p_userdata: Variant = null) -> void:
	if p_batch_element_index < 0 or p_batch_element_index >= _current_batch_cases.size():
		Logger.error("SimManager (Run ID: %s): _process_case_group_element_for_batch called with invalid index %d for batch %d. Current batch size: %d" % [run_id, p_batch_element_index, _current_batch_number, _current_batch_cases.size()])
		return

	var case_to_process: Case = _current_batch_cases[p_batch_element_index]
	if not case_to_process:
		Logger.error("SimManager (Run ID: %s): No case object found at batch index %d for batch %d." % [run_id, p_batch_element_index, _current_batch_number])
		return

	if not preprocess_callable.is_valid() or not run_callable.is_valid() or not postprocess_callable.is_valid():
		Logger.error("SimManager (Run ID: %s): A callable became invalid within threaded execution for batch %d, case %d (batch index %d)." % [run_id, _current_batch_number, case_to_process.case_id, p_batch_element_index])
		return

	var preprocess_args: Array = [case_to_process] # Preprocess receives the Case object, can use get_input_value_by_id
	var run_inputs: Variant = preprocess_callable.callv(preprocess_args)

	var run_outputs: Variant
	if run_inputs is Array:
		run_outputs = run_callable.callv(run_inputs)
	else:
		if run_inputs != null or run_callable.get_argument_count() > 0:
			run_outputs = run_callable.call(run_inputs)
		else:
			run_outputs = run_callable.call()

	# Postprocess receives Case, run_outputs, and the OutVal pool.
	# It can use case.add_output_value_by_id(id, out_val_from_pool)
	var postprocess_args: Array = [case_to_process, run_outputs, _out_val_pool]
	postprocess_callable.callv(postprocess_args)

	case_to_process.set_processed(true)

	_progress_mutex.lock()
	_cases_processed_in_current_batch += 1
	_progress_mutex.unlock()


func _complete_simulation_all_batches() -> void:
	var local_run_id = self.run_id if self.run_id else "UNKNOWN_RUN"

	if not is_running and _actual_total_cases_processed_so_far == 0 and n_cases > 0 :
		Logger.warning("SimManager (Run ID: %s): _complete_simulation_all_batches called but simulation wasn't fully running or no cases processed. n_cases: %d, actual_processed: %d" % [local_run_id, n_cases, _actual_total_cases_processed_so_far])
		is_running = false
		_stop_requested = false
		# Emit completion with 0 actual cases processed, but potentially configured batch size and total batches
		# If run_simulation itself returned early (e.g. n_cases = 0), self.batch_size might be the original user input (e.g. 0)
		# So we ensure that if n_cases was 0, we report 0 for batch size and total batches too.
		var final_batch_size_to_report = self.batch_size if n_cases > 0 else 0
		var final_total_batches_to_report = _total_batches if n_cases > 0 else 0
		emit_signal("simulation_completed", local_run_id, [], 0.0, final_batch_size_to_report, final_total_batches_to_report)
		return

	if not is_running and n_cases == 0:
		Logger.info("SimManager (Run ID: %s): Simulation completed with 0 cases as per configuration." % local_run_id)
		var duration_zero_case_run: float = float(Time.get_ticks_msec() - _simulation_start_time_msec) if _simulation_start_time_msec > 0 else 0.0
		emit_signal("simulation_completed", local_run_id, [], duration_zero_case_run, 0, 0)
		is_running = false
		return

	if not is_running and (_actual_total_cases_processed_so_far > 0 or (n_cases > 0 and _actual_total_cases_processed_so_far == 0 and not _stop_requested)):
		Logger.info("SimManager (Run ID: %s): _complete_simulation_all_batches called again after completion or in an inconsistent state. Current actual processed: %d. Ignoring." % [local_run_id, _actual_total_cases_processed_so_far])
		return

	is_running = false
	_stop_requested = false

	var simulation_end_time_msec: int = Time.get_ticks_msec()
	var overall_duration_msec: float = float(simulation_end_time_msec - _simulation_start_time_msec) if _simulation_start_time_msec > 0 else 0.0

	Logger.info("SimManager (Run ID: %s): All %d batches completed. Total cases processed: %d. Overall time: %.2f ms." % [local_run_id, _total_batches if _total_batches > 0 else _current_batch_number, _actual_total_cases_processed_so_far, overall_duration_msec])
	if _actual_total_cases_processed_so_far != n_cases and n_cases > 0 :
		Logger.warning("SimManager (Run ID: %s): Final actual processed case count %d does not match requested n_cases %d." % [local_run_id, _actual_total_cases_processed_so_far, n_cases])

	var final_results: Variant = []
	if output_as_dataframe:
		if not _all_processed_cases.is_empty():
			Logger.info("SimManager: Converting %d accumulated cases to DataFrame..." % _all_processed_cases.size())
			final_results = _convert_cases_to_dataframe(_all_processed_cases)
		elif _actual_total_cases_processed_so_far > 0:
			Logger.warning("SimManager: output_as_dataframe is true, but no cases were accumulated. DataFrame will be empty despite %d cases processed." % _actual_total_cases_processed_so_far)
		else:
			Logger.info("SimManager: No cases processed, DataFrame will be empty.")

	emit_signal("simulation_completed", local_run_id, final_results, overall_duration_msec, self.batch_size, _total_batches)

	if output_as_dataframe and not _all_processed_cases.is_empty():
		Logger.info("SimManager: Releasing %d accumulated Case objects back to pool." % _all_processed_cases.size())
		for case_obj in _all_processed_cases:
			if case_obj and _case_pool:
				_case_pool.release(case_obj)

	_all_processed_cases.clear()
	_current_batch_cases.clear()
	_cases_processed_in_current_batch = 0
	_actual_total_cases_processed_so_far = 0
	_current_batch_number = 0
	_total_batches = 0
	_group_task_id = -1
	_input_id_to_idx_map.clear() # Clear maps for next run
	_output_id_to_idx_map.clear()
	Logger.info("SimManager (Run ID: %s): Simulation finalized and cleaned up." % local_run_id)


func _convert_cases_to_dataframe(p_processed_cases: Array[Case]) -> EasyChartsDataFrame:
	if p_processed_cases.is_empty():
		Logger.warning("SimManager: No cases provided to _convert_cases_to_dataframe. Returning empty DataFrame.")
		return EasyChartsDataFrame.new(EasyChartsMatrix.new())

	var headers: PackedStringArray = ["CaseID"]
	# Use ordered IDs for headers
	for invar_id_str in _input_var_ids_ordered:
		headers.append(str(invar_id_str))
	for outvar_id_str in _output_var_ids_ordered:
		headers.append(str(outvar_id_str))
	
	var case_ids_as_labels: PackedStringArray = []
	var data_rows: Array = []

	for case_obj in p_processed_cases:
		if not case_obj is Case:
			Logger.warning("SimManager: Non-Case object found during DataFrame conversion. Skipping. ID: %s" % str(case_obj))
			continue
		case_ids_as_labels.append(str(case_obj.case_id))
		var current_row_data: Array = [case_obj.case_id]

		for input_idx in range(_input_var_ids_ordered.size()):
			var inval: InVal = case_obj.get_input_value_at_index(input_idx)
			# InVal now stores raw_value and mapped_value. We need to decide what goes into DataFrame.
			# Let's prioritize mapped_value if it exists, else raw_value.
			var value_to_log = inval.get_value() if inval else null # Assuming InVal.get_value() gives final value
			current_row_data.append(value_to_log)

		for output_idx in range(_output_var_ids_ordered.size()):
			var outval: OutVal = case_obj.get_output_value_at_index(output_idx)
			# Assuming OutVal.get_value() gives the value to log.
			var value_to_log = outval.get_value() if outval else null
			current_row_data.append(value_to_log)

		data_rows.append(current_row_data)

	if data_rows.is_empty() and not p_processed_cases.is_empty() :
		Logger.warning("SimManager: DataFrame data_rows is empty after processing %d cases. Returning empty DataFrame." % p_processed_cases.size())
		return EasyChartsDataFrame.new(EasyChartsMatrix.new(), headers if not headers.is_empty() else PackedStringArray())

	var matrix_data = EasyChartsMatrix.new(data_rows)
	var df_name = "SimulationResults_Batched_" + Time.get_datetime_string_from_system(true, true).replace(":", "-").replace(" ", "_")
	var df: EasyChartsDataFrame = EasyChartsDataFrame.new(matrix_data, headers, case_ids_as_labels, df_name)
	if df:
		Logger.info("SimManager: Results converted to DataFrame '%s' (%d rows, %d cols)" % [df.name, df.row_count(), df.column_count()])
	else:
		Logger.error("SimManager: Failed to create DataFrame object even with data.")
		return EasyChartsDataFrame.new(EasyChartsMatrix.new()) # Return empty on failure
	return df
#endregion

#endregion


#region Subclasses
#endregion


#region State
#endregion


#region Events
#endregion 
