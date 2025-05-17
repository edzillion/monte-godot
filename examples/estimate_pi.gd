# res://examples/estimate_pi.gd
extends Node

# Preload necessary classes if not relying on class_name global resolution entirely
# (though class_name should make them globally available)
# const SimManager = preload("res://src/managers/sim_manager.gd") # No longer directly used
const Model = preload("res://src/core/sim_model.gd")
const InVar = preload("res://src/core/in_var.gd")
const OutVar = preload("res://src/core/out_var.gd")
# const Case = preload("res://src/core/case.gd") # Not directly instantiated here
# const InVal = preload("res://src/core/in_val.gd") # Handled by InVar/Case
const OutVal = preload("res://src/core/out_val.gd")
const EasyChartsDataFrame = preload("res://addons/easy_charts/utilities/classes/structures/data_frame.gd") # For type checking results

var N_CASES: int = 100000
var OUTPUT_DATAFRAME: bool = false # Set to true to test DataFrame output
var _logger_instance = null # To store logger instance

var pi_model: Model


func _ready() -> void:
	if Engine.has_singleton("Logger"):
		_logger_instance = Engine.get_singleton("Logger")
		_logger_instance.min_log_level = Logger.LogLevel.INFO # Set desired log level
	else:
		print("EstimatePi: Logger not found. Autoload might not be configured.")

	# 1. Create a Model instance
	pi_model = Model.new("PiEstimationModel", "Estimates Pi using Monte Carlo")
	
	# Ensure SimManager (created by Model) is added to the tree if it's a Node and needs processing.
	# Model.get_sim_manager() gives access to the SimManager instance.
	var sm = pi_model.get_sim_manager()
	if sm and sm is Node and not sm.is_inside_tree():
		add_child(sm)
		sm.name = "PiEstimationSimManager" # Optional: give it a name in the tree
		_log_info("Added SimManager from Model to the scene tree.")

	# 2. Define InVars and OutVars
	var x_coord: InVar = InVar.new(&"x", "X Coordinate", InVar.DistributionType.UNIFORM, {"a": -1.0, "b": 1.0})
	var y_coord: InVar = InVar.new(&"y", "Y Coordinate", InVar.DistributionType.UNIFORM, {"a": -1.0, "b": 1.0})
	
	var is_inside_circle: OutVar = OutVar.new(&"inside_circle", "Is Point Inside Circle")

	# 3. Configure the simulation via the Model
	pi_model.configure_simulation(
		N_CASES,
		Callable(self, "_preprocess_pi"),
		Callable(self, "_run_pi"),
		Callable(self, "_postprocess_pi"),
		[x_coord, y_coord], # Input Variables
		[is_inside_circle], # Output Variables
		0, # max_threads (0 for default)
		OUTPUT_DATAFRAME # output_as_dataframe
	)

	# 4. Connect to the Model's signals
	pi_model.model_simulation_completed.connect(_on_model_simulation_completed)
	pi_model.model_simulation_progress.connect(_on_model_simulation_progress)
	pi_model.model_simulation_error.connect(_on_model_simulation_error)
	_log_info("Connected to Model signals.")

	# 5. Run the simulation
	_log_info("Starting Pi estimation model run...")
	if not pi_model.run_simulation():
		_log_error("Failed to start Pi estimation model run.")


func _preprocess_pi(case_obj: Case) -> Array:
	var x: float = case_obj.get_input_value(&"x").get_value()
	var y: float = case_obj.get_input_value(&"y").get_value()
	return [x, y]


func _run_pi(x: float, y: float) -> bool:
	# Check if the point (x, y) is inside the unit circle (x^2 + y^2 <= 1)
	return (x*x + y*y) <= 1.0


func _postprocess_pi(case_obj: Case, is_inside: bool) -> void:
	var result_val: int = 1 if is_inside else 0
	case_obj.add_output_value(&"inside_circle", OutVal.new(result_val))


func _on_model_simulation_completed(_results_param: Variant) -> void:
	_log_info("Pi estimation MODEL simulation completed!")
	
	var actual_results: Variant = pi_model.get_results() # Use Model's method to get results

	if actual_results == null:
		_log_error("Model returned null results despite completion signal.")
		_cleanup_after_run()
		return

	if actual_results is EasyChartsDataFrame:
		var df = actual_results as EasyChartsDataFrame
		_log_info("Results are DataFrame with %d rows, %d columns. Name: %s" % [df.row_count(), df.column_count(), df.name])
		# For DataFrame, we need to parse it to get the 'is_inside_circle' data.
		# This example assumes the column is named "inside_circle" as per OutVar ID.
		var inside_circle_col_name: String = "inside_circle"
		if df.has_column(inside_circle_col_name):
			var inside_circle_data: Array = df.get_column_data(inside_circle_col_name)
			var inside_circle_count: int = 0
			for val in inside_circle_data:
				if val == 1:
					inside_circle_count += 1
			
			if df.row_count() > 0:
				var estimated_pi: float = 4.0 * float(inside_circle_count) / float(df.row_count())
				_print_pi_results(df.row_count(), inside_circle_count, estimated_pi)
			else:
				_log_warning("DataFrame has no rows, cannot estimate Pi.")
		else:
			_log_error("DataFrame does not contain expected column: '%s'" % inside_circle_col_name)
		_cleanup_after_run()
		return
	
	if actual_results is Array[Case]:
		var cases_array: Array[Case] = actual_results
		var inside_circle_count: int = 0
		for case_obj in cases_array:
			var out_val: OutVal = case_obj.get_output_value(&"inside_circle")
			if out_val and out_val.get_value() == 1:
				inside_circle_count += 1
		
		if cases_array.size() > 0:
			var estimated_pi: float = 4.0 * float(inside_circle_count) / float(cases_array.size())
			_print_pi_results(cases_array.size(), inside_circle_count, estimated_pi)
		else:
			_log_warning("No cases were processed, cannot estimate Pi.")
		_cleanup_after_run()
		return

	_log_error("Results are in an unexpected format. Type: %s" % typeof(actual_results))
	_cleanup_after_run()


func _print_pi_results(total_cases: int, inside_count: int, pi_val: float) -> void:
	var msg_title = "--- Pi Estimation Results (%s) ---" % ("DataFrame" if OUTPUT_DATAFRAME else "Array[Case]")
	var msg_total = "Total cases: %d" % total_cases
	var msg_inside = "Points inside circle: %d" % inside_count
	var msg_pi = "Estimated Pi: %f" % pi_val
	
	_log_info(msg_title)
	_log_info(msg_total)
	_log_info(msg_inside)
	_log_info(msg_pi)
	
	print(msg_title)
	print(msg_total)
	print(msg_inside)
	print(msg_pi)
	print("-------------------------------------")


func _on_model_simulation_progress(progress: float) -> void:
	if _logger_instance:
		_logger_instance.debug("Pi Model Progress: %.2f %%" % progress)
	else:
		print("Pi Model Progress: %.2f %%" % progress)


func _on_model_simulation_error(error_message: String) -> void:
	_log_error("Pi Model Simulation Error: %s" % error_message)
	_cleanup_after_run()


func _cleanup_after_run() -> void:
	# Clean up the Model and its SimManager
	# If SimManager was added as a child to this node, queue_free it.
	if pi_model:
		var sm = pi_model.get_sim_manager()
		if sm and sm is Node and sm.get_parent() == self:
			sm.queue_free()
			_log_info("Queued SimManager for freeing.")
		# Model can call a method to free its SimManager if it exclusively owns it and it wasn't parented elsewhere
		# pi_model.free_sim_manager_if_owned() # Use this if Model was responsible for a non-parented SM
		pi_model.free() # Free the RefCounted Model instance
		pi_model = null
	_log_info("Cleanup after run completed.")


# Logger helper methods
func _log_info(message: String) -> void:
	if _logger_instance:
		_logger_instance.info("EstimatePi: " + message)
	else:
		print("[INFO] EstimatePi: " + message)

func _log_warning(message: String) -> void:
	if _logger_instance:
		_logger_instance.warning("EstimatePi: " + message)
	else:
		push_warning("EstimatePi: " + message)

func _log_error(message: String) -> void:
	if _logger_instance:
		_logger_instance.error("EstimatePi: " + message)
	else:
		push_error("EstimatePi: " + message)

# Removed _exit_tree to ensure SimManager is handled in completion/error callbacks
# func _exit_tree() -> void:
# 	# Ensure SimManager is freed if it was added as a child
# 	if pi_model and pi_model.sim_manager and pi_model.sim_manager.get_parent() == self:
# 		pi_model.sim_manager.queue_free()
# 	if pi_model:
# 		pi_model.free() # Free the RefCounted Model instance
