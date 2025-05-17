# res://examples/estimate_pi.gd
extends Node

# Preload necessary classes
const EasyChartsDataFrame = preload("res://addons/easy_charts/utilities/classes/structures/data_frame.gd") # For type checking results

var N_CASES: int = 100_000
var OUTPUT_DATAFRAME: bool = false # Set to true to test DataFrame output
var MAX_THREADS_FOR_PI_SIM: int = 0 # Explicitly set to 1 thread for testing high case count
var BATCH_SIZE: int = 0 # New constant for batch size

var pi_model: SimModel
var _current_inside_circle_count: int = 0 # Accumulator for points inside the circle


func _ready() -> void:
	# Logger is an autoload, set its properties directly.
	# Assuming Logger autoload is correctly configured in Project Settings.
	Logger.min_log_level = Logger.LogLevel.INFO
	Logger.info("EstimatePi: Logger min_log_level set to INFO.")

	# 1. Create a SimModel instance
	pi_model = SimModel.new("PiEstimationModel", "Estimates Pi using Monte Carlo")
	Logger.info("EstimatePi: PiEstimationModel instance created.")

	var sm = pi_model.get_sim_manager()
	if sm and sm is Node and not sm.is_inside_tree():
		add_child(sm)
		sm.name = "PiEstimationSimManager"
		Logger.info("EstimatePi: Added SimManager from SimModel to the scene tree.")

	# 2. Define InVars and OutVars for Pi estimation
	var x_coord: InVar = InVar.new(&"x", "X Coordinate", InVar.DistributionType.UNIFORM, {"a": -1.0, "b": 1.0})
	var y_coord: InVar = InVar.new(&"y", "Y Coordinate", InVar.DistributionType.UNIFORM, {"a": -1.0, "b": 1.0})
	var is_inside_circle: OutVar = OutVar.new(&"inside_circle", "Is Point Inside Circle")
	Logger.info("EstimatePi: Input and Output variables for Pi defined.")

	# 3. Configure the simulation via the SimModel
	pi_model.configure_simulation(
		N_CASES,
		Callable(self, "_preprocess_pi"),
		Callable(self, "_run_pi"),
		Callable(self, "_postprocess_pi"),
		MAX_THREADS_FOR_PI_SIM,
		BATCH_SIZE,
		[x_coord, y_coord],
		[is_inside_circle],
		OUTPUT_DATAFRAME
	)
	Logger.info("EstimatePi: PiEstimationModel configured with %d cases, %d max threads, and batch size %d." % [N_CASES, MAX_THREADS_FOR_PI_SIM, BATCH_SIZE])

	# 4. Connect to the SimModel's signals
	pi_model.sim_model_simulation_started.connect(_on_model_simulation_started)
	pi_model.sim_model_simulation_progress.connect(_on_model_simulation_progress)
	pi_model.sim_model_simulation_completed.connect(_on_model_simulation_completed)
	pi_model.sim_model_simulation_batch_completed.connect(_on_model_simulation_batch_completed)
	pi_model.sim_model_simulation_error.connect(_on_model_simulation_error)
	Logger.info("EstimatePi: Connected to PiEstimationModel signals.")

	# 5. Run the simulation
	_current_inside_circle_count = 0 # Reset counter before starting
	Logger.info("EstimatePi: Attempting to start Pi estimation SimModel run...")
	if not pi_model.run_simulation():
		Logger.error("EstimatePi: Failed to start Pi estimation SimModel run. Check previous logs for reasons.")
	else:
		Logger.info("EstimatePi: Pi estimation SimModel run successfully initiated.")


func _preprocess_pi(case_obj: Case) -> Array:
	var x: float = case_obj.get_input_value(&"x").get_value()
	var y: float = case_obj.get_input_value(&"y").get_value()
	return [x, y]

func _run_pi(x: float, y: float) -> bool:
	return (x*x + y*y) <= 1.0 # Check if point is inside unit circle

func _postprocess_pi(case_obj: Case, is_inside: bool, p_out_val_pool: ObjectPool) -> void:
	# Only create and add OutVal if we are actually building a DataFrame
	if OUTPUT_DATAFRAME:
		var result_val: int = 1 if is_inside else 0
		
		var out_val_obj: OutVal = null
		if p_out_val_pool:
			out_val_obj = p_out_val_pool.acquire() as OutVal
		
		if not out_val_obj: # Fallback if pool fails or is null
			Logger.warning("EstimatePi (_postprocess_pi): Failed to acquire OutVal from pool. Creating directly.")
			out_val_obj = OutVal.new()
			if not out_val_obj:
				Logger.error("EstimatePi (_postprocess_pi): CRITICAL - Failed to create OutVal even with direct instantiation.")
				# Cannot add output value if creation totally fails
			else:
				out_val_obj._init(result_val) # Re-initialize with the new value
				case_obj.add_output_value(&"inside_circle", out_val_obj)
		else: # Successfully acquired from pool
			out_val_obj._init(result_val) # Re-initialize with the new value
			case_obj.add_output_value(&"inside_circle", out_val_obj)

	# Always accumulate for the direct Pi calculation
	if is_inside:
		_current_inside_circle_count += 1


func _on_model_simulation_started() -> void:
	Logger.info("EstimatePi: Pi SimModel signal: SIMULATION STARTED.")
	print("--- User Notification: Pi SimModel Simulation Has Started! ---")


func _on_model_simulation_completed(_results_param: Variant, overall_duration_msec: float) -> void:
	var total_batches_float: float = 0.0
	if BATCH_SIZE > 0 and N_CASES > 0:
		total_batches_float = ceil(float(N_CASES) / float(BATCH_SIZE))
	
	var average_batch_time_msec: float = 0.0
	if total_batches_float > 0:
		average_batch_time_msec = overall_duration_msec / total_batches_float
	
	var log_message_details = "Cases: %d, BatchSize: %d, Threads: %s, TotalBatches: %d" % [
		N_CASES, 
		BATCH_SIZE, 
		str(MAX_THREADS_FOR_PI_SIM if MAX_THREADS_FOR_PI_SIM > 0 else "All"),
		int(total_batches_float)
	]
	var log_message_timing = "OverallTime: %.2f ms, AvgBatchTime: %.2f ms" % [
		overall_duration_msec, 
		average_batch_time_msec
	]

	Logger.info("EstimatePi: Pi SimModel signal: SIMULATION COMPLETED! %s. %s" % [log_message_details, log_message_timing])
	print("--- User Notification: Pi SimModel Simulation Has Completed! ---")
	print("    %s" % log_message_details)
	print("    %s" % log_message_timing)

	# Always calculate Pi using the accumulated count
	if N_CASES > 0:
		var estimated_pi: float = 4.0 * float(_current_inside_circle_count) / float(N_CASES)
		_print_pi_results(N_CASES, _current_inside_circle_count, estimated_pi, "Accumulated")
	else:
		Logger.warning("EstimatePi: N_CASES is 0, cannot estimate Pi from accumulated count.")

	# Optional: Process DataFrame if it was requested and generated
	var actual_results_from_model: Variant = pi_model.get_results()
	if OUTPUT_DATAFRAME and actual_results_from_model is EasyChartsDataFrame:
		var df = actual_results_from_model as EasyChartsDataFrame
		Logger.info("EstimatePi: Results are DataFrame with %d rows, %d columns. Name: %s" % [df.row_count(), df.column_count(), df.name])
		var inside_circle_col_name: String = "inside_circle"
		if df.has_column(inside_circle_col_name):
			var inside_circle_data: Array = df.get_column_data(inside_circle_col_name)
			var df_inside_circle_count: int = 0
			for val in inside_circle_data:
				if val == 1:
					df_inside_circle_count += 1

			if df.row_count() > 0:
				var df_estimated_pi: float = 4.0 * float(df_inside_circle_count) / float(df.row_count())
				_print_pi_results(df.row_count(), df_inside_circle_count, df_estimated_pi, "DataFrame")
			else:
				Logger.warning("EstimatePi: DataFrame has no rows, cannot estimate Pi from DataFrame.")
		else:
			Logger.error("EstimatePi: DataFrame does not contain expected column: '%s'" % inside_circle_col_name)
	elif OUTPUT_DATAFRAME and actual_results_from_model is Array[Case] and actual_results_from_model.is_empty():
		Logger.info("EstimatePi: OUTPUT_DATAFRAME was true, but SimModel returned an empty array (as expected from SimManager when no cases are stored for DataFrame). Pi from accumulated count is already reported.")
	elif not OUTPUT_DATAFRAME and actual_results_from_model is Array[Case] and actual_results_from_model.is_empty():
		Logger.info("EstimatePi: OUTPUT_DATAFRAME was false. SimModel returned an empty array (as expected from SimManager). Pi from accumulated count is already reported.")
	elif actual_results_from_model != null:
		Logger.warning("EstimatePi: SimModel results are in an unexpected format or state when OUTPUT_DATAFRAME is %s. Type: %s. Value: %s" % [str(OUTPUT_DATAFRAME), typeof(actual_results_from_model), str(actual_results_from_model)])

	_cleanup_after_run()


func _print_pi_results(total_cases: int, inside_count: int, pi_val: float, result_type: String) -> void:
	var msg_title = "--- Pi Estimation Results (%s) ---" % result_type
	var msg_total = "Total cases: %d" % total_cases
	var msg_inside = "Points inside circle: %d" % inside_count
	var msg_pi = "Estimated Pi: %f" % pi_val

	Logger.info("EstimatePi: " + msg_title)
	Logger.info("EstimatePi: " + msg_total)
	Logger.info("EstimatePi: " + msg_inside)
	Logger.info("EstimatePi: " + msg_pi)

	print(msg_title)
	print(msg_total)
	print(msg_inside)
	print(msg_pi)
	print("-------------------------------------")


func _on_model_simulation_progress(progress: float) -> void:
	var progress_message = "EstimatePi: Pi SimModel signal: PROGRESS UPDATE - %.2f %%" % progress
	Logger.debug(progress_message)

	if fmod(progress, 10.0) < 0.1 or progress > 99.9:
		print("--- User Notification: Simulation Progress: %.2f %% ---" % progress)


func _on_model_simulation_batch_completed(batch_number: int, total_batches: int, _batch_results: Array[Case], batch_duration_msec: float) -> void:
	var batch_msg = "EstimatePi: Pi SimModel signal: BATCH COMPLETED - Batch %d of %d in %.2f ms." % [batch_number, total_batches, batch_duration_msec]
	Logger.info(batch_msg)
	print("--- User Notification: Batch %d / %d completed (Took: %.2f ms) ---" % [batch_number, total_batches, batch_duration_msec])


func _on_model_simulation_error(error_message: String) -> void:
	Logger.error("EstimatePi: Pi SimModel signal: SIMULATION ERROR - %s" % error_message)
	print("--- User Notification: Pi SimModel Simulation Encountered an ERROR! ---")
	print("Error details: %s" % error_message)
	_cleanup_after_run()


func _cleanup_after_run() -> void:
	if pi_model:
		var sm = pi_model.get_sim_manager()
		if sm and sm is Node and sm.get_parent() == self:
			sm.queue_free()
			Logger.info("EstimatePi: Queued SimManager for freeing.")
		pi_model = null
	Logger.info("EstimatePi: Cleanup after run completed.")
