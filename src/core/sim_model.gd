# res://src/core/sim_model.gd
class_name SimModel extends RefCounted

## @brief Encapsulates a complete simulation model, including its configuration,
## input/output variables, and the simulation manager instance.

#region Signals
signal sim_model_simulation_started(run_id: String)
signal sim_model_simulation_progress(progress_percentage: float)
signal sim_model_simulation_completed(run_id: String, results: Variant, overall_duration_msec: float, actual_batch_size: int, total_batches_executed: int)
signal sim_model_simulation_batch_completed(batch_number: int, total_batches: int, batch_results: Array[Case], batch_duration_msec: float)
signal sim_model_simulation_error(run_id: String, error_message: String)
#endregion

#region Properties
var model_name: String # User-defined name for this specific SimModel instance
var model_description: String
var sim_manager: SimManager # Should be type SimManager, ensure this is correct if path changed
var current_run_id: String # Store the run_id for the active/last run
var simulation_results: Variant = null
var is_configured: bool = false

# Configuration storage
var _num_cases: int
var _preprocess_callable: Callable
var _run_callable: Callable
var _postprocess_callable: Callable
var _max_threads: int
var _batch_size: int
var _input_vars: Array[InVar] # Store as array as received
var _output_vars: Array[OutVar] # Store as array as received
var _output_as_dataframe: bool
var _in_var_use_pregeneration_setting: bool = true # Default value

#endregion


#region Initialization
func _init(p_model_name: String, p_model_description: String = "", p_sim_manager:SimManager = null) -> void:
	model_name = p_model_name
	model_description = p_model_description
	if p_sim_manager:
		sim_manager = p_sim_manager
	else:
		# Assuming SimManager path is correct for instantiation if needed.
		# Check if src/managers/sim_manager.gd is the correct path.
		sim_manager = preload("res://src/managers/sim_manager.gd").new() 

	if sim_manager:
		sim_manager.simulation_started.connect(_on_sim_manager_started)
		sim_manager.simulation_progress.connect(_on_sim_manager_progress)
		sim_manager.simulation_completed.connect(_on_sim_manager_completed)
		sim_manager.simulation_error.connect(_on_sim_manager_error)
		sim_manager.simulation_batch_completed.connect(_on_sim_manager_batch_completed)

	Logger.info("SimModel '%s' initialized." % model_name)
#endregion


#region Public Methods
## @brief Configures the simulation parameters for a future run.
func configure_simulation(
		p_num_cases: int,
		p_preprocess_callable: Callable,
		p_run_callable: Callable,
		p_postprocess_callable: Callable,
		p_max_threads: int,
		p_batch_size: int,
		p_input_vars: Array[InVar] = [],
		p_output_vars: Array[OutVar] = [],
		p_output_as_dataframe: bool = false,
		p_in_var_use_pregeneration: bool = true # New parameter
	) -> void:

	_num_cases = p_num_cases
	_preprocess_callable = p_preprocess_callable
	_run_callable = p_run_callable
	_postprocess_callable = p_postprocess_callable
	_max_threads = p_max_threads
	_batch_size = p_batch_size
	_input_vars = p_input_vars
	_output_vars = p_output_vars
	_output_as_dataframe = p_output_as_dataframe
	_in_var_use_pregeneration_setting = p_in_var_use_pregeneration
	
	is_configured = true
	simulation_results = null # Reset results on re-configuration
	current_run_id = "" # Reset run ID on configure
	Logger.info("SimModel '%s': Simulation configured with %d cases. InVar Pregen: %s" % [model_name, _num_cases, str(_in_var_use_pregeneration_setting)])


## @brief Runs the configured simulation.
## Returns true if simulation started, false otherwise.
func run_simulation() -> bool:
	if not sim_manager:
		Logger.error("SimModel '%s': SimManager is not initialized. Cannot run." % model_name)
		return false
	if not is_configured:
		Logger.error("SimModel '%s': Simulation not configured. Call configure_simulation() first." % model_name)
		return false
	if sim_manager.is_running:
		Logger.warning("SimModel '%s' (Run ID: %s): Simulation is already running." % [model_name, sim_manager.run_id if sim_manager.run_id else "PREVIOUS_OR_UNKNOWN"])
		return false
	
	simulation_results = null # Clear previous results before a new run
	current_run_id = "" # Will be set by _on_sim_manager_started
	Logger.info("SimModel '%s': Attempting to start simulation run via SimManager." % model_name)

	# Convert InVar/OutVar arrays to Dictionaries {id: var_obj} for SimManager
	var input_vars_dict: Dictionary = {}
	for invar in _input_vars:
		if invar and invar.id:
			input_vars_dict[invar.id] = invar
	
	var output_vars_dict: Dictionary = {}
	for outvar in _output_vars:
		if outvar and outvar.id:
			output_vars_dict[outvar.id] = outvar

	# Call the refactored SimManager.run_simulation with all parameters
	var success: bool = sim_manager.run_simulation(
		_num_cases,
		_preprocess_callable,
		_run_callable,
		_postprocess_callable,
		_max_threads,
		_batch_size,
		input_vars_dict, 
		output_vars_dict,
		_output_as_dataframe,
		_in_var_use_pregeneration_setting # Pass the new flag
	)
	return success # Return the success status from SimManager


## @brief Retrieves the results from the last completed simulation run.
## Returns null if no simulation has completed or if called before completion.
func get_results() -> Variant:
	var log_run_id = current_run_id if current_run_id else (sim_manager.run_id if sim_manager and sim_manager.run_id else "UNKNOWN_RUN")
	if sim_manager and sim_manager.is_running:
		Logger.warning("SimModel '%s' (Run ID: %s): Simulation is still running. Results are not yet available." % [model_name, log_run_id])
		return null
	if simulation_results == null:
		Logger.info("SimModel '%s' (Run ID: %s): No simulation results available. Run simulation first or wait for completion." % [model_name, log_run_id])

	return simulation_results


## @brief Gets the underlying SimManager instance.
## Useful if direct access to SimManager's specific properties or signals is needed by the user.
func get_sim_manager() -> SimManager:
	return sim_manager

#endregion

#region Internal Signal Handlers (from SimManager)
func _on_sim_manager_started(p_run_id: String) -> void:
	current_run_id = p_run_id # Store the run_id for this model instance
	Logger.info("SimModel '%s' (Run ID: %s): Received SimManager 'simulation_started' signal." % [model_name, current_run_id])
	emit_signal("sim_model_simulation_started", current_run_id)

func _on_sim_manager_progress(progress: float) -> void:
	emit_signal("sim_model_simulation_progress", progress)

func _on_sim_manager_completed(p_run_id: String, results_from_sim: Variant, overall_duration_msec: float, actual_batch_size: int, total_batches_executed: int) -> void:
	if p_run_id != current_run_id and current_run_id != "": # Check if this completion is for the run we tracked
		Logger.warning("SimModel '%s': Received completion for run ID '%s', but was expecting/tracking run ID '%s'. Storing results anyway." % [model_name, p_run_id, current_run_id])
		simulation_results = results_from_sim
	current_run_id = p_run_id # Ensure current_run_id is updated to the one that completed.
	Logger.info("SimModel '%s' (Run ID: %s): Simulation completed. Results stored. Actual Batch: %d, Total Batches: %d, Time: %.2f ms" % [model_name, current_run_id, actual_batch_size, total_batches_executed, overall_duration_msec])
	emit_signal("sim_model_simulation_completed", current_run_id, simulation_results, overall_duration_msec, actual_batch_size, total_batches_executed)

func _on_sim_manager_error(p_run_id: String, error_msg: String) -> void:
	var log_run_id = p_run_id if p_run_id else current_run_id # Use p_run_id if available
	Logger.error("SimModel '%s' (Run ID: %s): Received error from SimManager: %s" % [model_name, log_run_id, error_msg])
	emit_signal("sim_model_simulation_error", log_run_id, error_msg)

func _on_sim_manager_batch_completed(batch_number: int, total_batches: int, _batch_results: Array[Case], batch_duration_msec: float) -> void:
	Logger.debug("SimModel '%s' (Run ID: %s): Batch %d/%d completed in %.2f ms." % [model_name, current_run_id if current_run_id else "N/A", batch_number, total_batches, batch_duration_msec])
	emit_signal("sim_model_simulation_batch_completed", batch_number, total_batches, _batch_results, batch_duration_msec)
#endregion


#region Cleanup
func free_sim_manager_if_owned() -> void:
	if sim_manager and sim_manager is Node and not sim_manager.is_inside_tree():
		Logger.info("SimModel '%s': Freeing owned SimManager instance." % model_name)
		sim_manager.free()
		sim_manager = null
#endregion 
