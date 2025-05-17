# res://src/core/sim_model.gd
class_name SimModel extends RefCounted

## @brief Encapsulates a complete simulation model, including its configuration,
## input/output variables, and the simulation manager instance.

#region Signals
signal sim_model_simulation_started
signal sim_model_simulation_progress(progress_percentage: float)
signal sim_model_simulation_completed(results: Variant, overall_duration_msec: float)
signal sim_model_simulation_batch_completed(batch_number: int, total_batches: int, batch_results: Array[Case], batch_duration_msec: float)
signal sim_model_simulation_error(error_message: String)
#endregion

#region Properties
var model_name: String # User-defined name for this specific SimModel instance
var model_description: String
var sim_manager: SimManager
var simulation_results: Variant = null
var is_configured: bool = false
#endregion

#region Constants
const AUTO_BATCH_DEFAULT_TARGET_PER_BATCH: int = 5000
const AUTO_BATCH_MINIMUM_SIZE: int = 500
const AUTO_BATCH_MAX_TOTAL_BATCHES: int = 1000
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

#region Initialization
func _init(p_model_name: String, p_model_description: String = "", p_sim_manager:SimManager = null) -> void:
	model_name = p_model_name
	model_description = p_model_description
	if p_sim_manager:
		sim_manager = p_sim_manager
	else:
		sim_manager = SimManager.new()
		# If SimManager is a Node and needs to be in the tree (e.g., for _process),
		# the entity creating the SimModel instance is responsible for adding sim_manager to the tree.
		# Example: get_tree().root.add_child(my_sim_model.sim_manager)

	# Connect to SimManager signals internally
	if sim_manager:
		sim_manager.simulation_started.connect(_on_sim_manager_started)
		sim_manager.simulation_progress.connect(_on_sim_manager_progress)
		sim_manager.simulation_completed.connect(_on_sim_manager_completed)
		sim_manager.simulation_error.connect(_on_sim_manager_error)
		sim_manager.simulation_batch_completed.connect(_on_sim_manager_batch_completed)

	Logger.info("SimModel '%s' initialized." % model_name)
#endregion


#region Public Methods
## @brief Configures the simulation by setting up the SimManager.
func configure_simulation(
		ncases: int,
		preprocess_callable: Callable,
		run_callable: Callable,
		postprocess_callable: Callable,
		p_max_threads: int,
		p_batch_size: int,
		input_vars: Array[InVar] = [],
		output_vars: Array[OutVar] = [],
		p_output_as_dataframe: bool = false
	) -> void:
	if not sim_manager:
		Logger.error("SimModel '%s': SimManager is not initialized. Cannot configure." % model_name)
		return

	sim_manager.n_cases = ncases
	sim_manager.max_threads = p_max_threads
	sim_manager.output_as_dataframe = p_output_as_dataframe
	sim_manager.batch_size = p_batch_size
	sim_manager.set_simulation_functions(preprocess_callable, run_callable, postprocess_callable)

	# Clear previous vars if any, to support reconfiguration
	sim_manager.input_variables.clear()
	sim_manager.output_variables.clear()
	for invar in input_vars:
		sim_manager.add_input_variable(invar)
	
	for outvar in output_vars:
		sim_manager.add_output_variable(outvar)
	
	is_configured = true
	simulation_results = null # Reset results on re-configuration
	Logger.info("SimModel '%s': Simulation configured with %d cases." % [model_name, ncases])


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
		Logger.warning("SimModel '%s': Simulation is already running." % model_name)
		return false
	
	simulation_results = null # Clear previous results before a new run
	Logger.info("SimModel '%s': Starting simulation run." % model_name)
	sim_manager.run_simulation() # SimManager will emit simulation_started
	return true


## @brief Retrieves the results from the last completed simulation run.
## Returns null if no simulation has completed or if called before completion.
func get_results() -> Variant:
	if sim_manager and sim_manager.is_running:
		Logger.warning("SimModel '%s': Simulation is still running. Results are not yet available or may be incomplete." % model_name)
		return null
	if simulation_results == null:
		Logger.info("SimModel '%s': No simulation results available. Run simulation first or wait for completion." % model_name)

	return simulation_results


## @brief Gets the underlying SimManager instance.
## Useful if direct access to SimManager's specific properties or signals is needed by the user.
func get_sim_manager() -> SimManager:
	return sim_manager

#endregion

#region Internal Signal Handlers (from SimManager)
func _on_sim_manager_started() -> void:
	emit_signal("sim_model_simulation_started")

func _on_sim_manager_progress(progress: float) -> void:
	emit_signal("sim_model_simulation_progress", progress)

func _on_sim_manager_completed(results_from_sim: Variant, overall_duration_msec: float) -> void:
	simulation_results = results_from_sim
	Logger.info("SimModel '%s': Simulation completed. Results stored. Overall time: %.2f ms" % [model_name, overall_duration_msec])
	emit_signal("sim_model_simulation_completed", simulation_results, overall_duration_msec)

func _on_sim_manager_error(error_msg: String) -> void:
	Logger.error("SimModel '%s': Received error from SimManager: %s" % [model_name, error_msg])
	emit_signal("sim_model_simulation_error", error_msg)

func _on_sim_manager_batch_completed(batch_number: int, total_batches: int, batch_duration_msec: float) -> void:
	# Note: SimManager's simulation_batch_completed signal currently doesn't pass batch_results. 
	# If it did, we'd pass them along here too.
	Logger.debug("SimModel '%s': Batch %d/%d completed in %.2f ms." % [model_name, batch_number, total_batches, batch_duration_msec])
	emit_signal("sim_model_simulation_batch_completed", batch_number, total_batches, [], batch_duration_msec) # Passing empty array for batch_results for now
#endregion


#region Cleanup
func free_sim_manager_if_owned() -> void:
	# This is a helper if the SimModel instance exclusively owns the SimManager
	# and it needs to be manually freed (e.g., if it was .new() and not added to tree elsewhere)
	if sim_manager and sim_manager is Node and not sim_manager.is_inside_tree():
		Logger.info("SimModel '%s': Freeing owned SimManager instance." % model_name)
		sim_manager.free()
		sim_manager = null
	# If sim_manager was added to the scene tree by external code, that code is responsible for queue_free().

# Note: Since SimModel is RefCounted, its own 'free()' is handled by reference counting.
# If SimManager is a child of a node in the main scene tree, it will be freed when its parent is freed.
# This method is for cases where SimModel might create a SimManager that isn't parented elsewhere.
#endregion 
