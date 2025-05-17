# res://examples/estimate_pi.gd
extends Node

# Preload necessary classes
const EasyChartsDataFrame = preload("res://addons/easy_charts/utilities/classes/structures/data_frame.gd") # For type checking results

@export var use_pregeneration: bool = true # Control InVar value generation strategy

var N_CASES: int = 1_000_000
var OUTPUT_DATAFRAME: bool = false # Set to true to test DataFrame output
var MAX_THREADS_FOR_PI_SIM: int = 0 # Explicitly set to 1 thread for testing high case count
var BATCH_SIZE: int = 10_000 # New constant for batch size

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
	var x_coord: InVar = InVar.new(&"x", "X Coordinate", InVar.DistributionType.UNIFORM, {"a": -1.0, "b": 1.0}, use_pregeneration)
	var y_coord: InVar = InVar.new(&"y", "Y Coordinate", InVar.DistributionType.UNIFORM, {"a": -1.0, "b": 1.0}, use_pregeneration)
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
		OUTPUT_DATAFRAME,
		use_pregeneration
	)
	Logger.info("EstimatePi: PiEstimationModel configured with %d cases, %d max threads, batch size %d, InVar Pregen: %s." % [N_CASES, MAX_THREADS_FOR_PI_SIM, BATCH_SIZE, str(use_pregeneration)])

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
	var x_inval: InVal = case_obj.get_input_value_by_id(&"x")
	var y_inval: InVal = case_obj.get_input_value_by_id(&"y")

	var x: float = 0.0
	var y: float = 0.0

	if x_inval:
		x = x_inval.get_value()
	else:
		push_warning("Pi Estimation (_preprocess_pi): InVal for 'x' not found in case %d. Defaulting to 0.0." % case_obj.case_id)
		# Or handle error more strictly if needed

	if y_inval:
		y = y_inval.get_value()
	else:
		push_warning("Pi Estimation (_preprocess_pi): InVal for 'y' not found in case %d. Defaulting to 0.0." % case_obj.case_id)
		# Or handle error more strictly

	return [x, y] # These become arguments for _run_pi

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


func _on_model_simulation_started(run_id: String) -> void:
	Logger.info("EstimatePi (Run ID: %s): Pi SimModel signal: SIMULATION STARTED." % run_id)
	print("--- User Notification: Pi SimModel Simulation Has Started! (Run ID: %s) ---" % run_id)


func _on_model_simulation_completed(run_id: String, _results_param: Variant, overall_duration_msec: float, actual_batch_size: int, total_batches_executed: int) -> void:
	var average_batch_time_msec: float = 0.0
	if total_batches_executed > 0:
		average_batch_time_msec = overall_duration_msec / float(total_batches_executed)
	
	var log_message_run_id = "Run ID: %s" % run_id
	var log_message_details = "Cases: %s, Actual BatchSize: %s, Threads: %s, TotalBatches: %s" % [
		Logger._format_int_with_underscores(N_CASES), 
		Logger._format_int_with_underscores(actual_batch_size), 
		str(MAX_THREADS_FOR_PI_SIM if MAX_THREADS_FOR_PI_SIM > 0 else "All"),
		Logger._format_int_with_underscores(total_batches_executed)
	]
	var log_message_timing = "OverallTime: %.2f ms, AvgBatchTime: %.2f ms" % [
		overall_duration_msec, 
		average_batch_time_msec
	]

	Logger.info("EstimatePi: Pi SimModel signal: SIMULATION COMPLETED! %s. %s. %s" % [log_message_run_id, log_message_details, log_message_timing])
	print("--- User Notification: Pi SimModel Simulation Has Completed! (%s) --- " % log_message_run_id)
	print("    %s" % log_message_details)
	print("    %s" % log_message_timing)

	# Always calculate Pi using the accumulated count
	if N_CASES > 0:
		var estimated_pi: float = 4.0 * float(_current_inside_circle_count) / float(N_CASES)
		_print_pi_results(N_CASES, _current_inside_circle_count, estimated_pi, "Accumulated", run_id)
	else:
		Logger.warning("EstimatePi: N_CASES is 0, cannot estimate Pi from accumulated count.")

	# Optional: Process DataFrame if it was requested and generated
	var actual_results_from_model: Variant = pi_model.get_results() # get_results now also logs run_id internally
	if OUTPUT_DATAFRAME and actual_results_from_model is EasyChartsDataFrame:
		var df = actual_results_from_model as EasyChartsDataFrame
		Logger.info("EstimatePi (Run ID: %s): Results are DataFrame with %d rows, %d columns. Name: %s" % [run_id, df.row_count(), df.column_count(), df.name])
		var inside_circle_col_name: String = "inside_circle"
		if df.has_column(inside_circle_col_name):
			var inside_circle_data: Array = df.get_column_data(inside_circle_col_name)
			var df_inside_circle_count: int = 0
			for val in inside_circle_data:
				if val == 1:
					df_inside_circle_count += 1

			if df.row_count() > 0:
				var df_estimated_pi: float = 4.0 * float(df_inside_circle_count) / float(df.row_count())
				_print_pi_results(df.row_count(), df_inside_circle_count, df_estimated_pi, "DataFrame", run_id)
			else:
				Logger.warning("EstimatePi (Run ID: %s): DataFrame has no rows, cannot estimate Pi from DataFrame." % run_id)
		else:
			Logger.error("EstimatePi (Run ID: %s): DataFrame does not contain expected column: '%s'" % [run_id, inside_circle_col_name])
	elif OUTPUT_DATAFRAME and actual_results_from_model is Array[Case] and actual_results_from_model.is_empty():
		Logger.info("EstimatePi: OUTPUT_DATAFRAME was true, but SimModel returned an empty array (as expected from SimManager when no cases are stored for DataFrame). Pi from accumulated count is already reported.")
	elif not OUTPUT_DATAFRAME and actual_results_from_model is Array[Case] and actual_results_from_model.is_empty():
		Logger.info("EstimatePi: OUTPUT_DATAFRAME was false. SimModel returned an empty array (as expected from SimManager). Pi from accumulated count is already reported.")
	elif actual_results_from_model != null:
		Logger.warning("EstimatePi: SimModel results are in an unexpected format or state when OUTPUT_DATAFRAME is %s. Type: %s. Value: %s" % [str(OUTPUT_DATAFRAME), typeof(actual_results_from_model), str(actual_results_from_model)])

	_cleanup_after_run()


func _print_pi_results(total_cases: int, inside_count: int, pi_val: float, result_type: String, p_run_id: String = "N/A") -> void:
	var msg_title = "--- Pi Estimation Results (Type: %s, Run ID: %s) --- " % [result_type, p_run_id]
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


func _on_model_simulation_error(run_id: String, error_message: String) -> void:
	Logger.error("EstimatePi (Run ID: %s): Pi SimModel signal: SIMULATION ERROR - %s" % [run_id, error_message])
	print("--- User Notification: Pi SimModel Simulation Encountered an ERROR! (Run ID: %s) --- " % run_id)
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

# Called by SimManager for each case via run_callable
func _run_pi_case(case_obj: Case) -> Dictionary:
	# Retrieve input values by ID using the Case object's convenience method
	var x_inval: InVal = case_obj.get_input_value_by_id(&"x")
	var y_inval: InVal = case_obj.get_input_value_by_id(&"y")

	var x: float = 0.0
	var y: float = 0.0

	if x_inval:
		x = x_inval.get_value() # InVal.get_value() should return the final (potentially mapped) value
	else:
		push_warning("Pi Estimation: InVal for 'x' not found in case %d." % case_obj.case_id)
		# Decide on fallback or error handling if InVal is missing

	if y_inval:
		y = y_inval.get_value()
	else:
		push_warning("Pi Estimation: InVal for 'y' not found in case %d." % case_obj.case_id)

	var is_inside_circle: bool = (x*x + y*y) <= 1.0
	return {"is_inside": is_inside_circle, "x_val": x, "y_val": y}
