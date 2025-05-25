class_name Calibration extends Node

var calibrator: MonteGodotCalibrator
var _pi_job_functions_instance: PiJobFunctions

@onready var _graph_node: Graph2D = $Graph2D

var _line_series: LineSeries = null

const DEFAULT_JOB_CONFIG_PATH_PI_EXAMPLE: String = "res://examples/estimate_pi/estimate_pi_job.tres"
const PiJobFunctionsScript: Script = preload("res://examples/calibration/pi_job_functions.gd")

func _ready() -> void:
	calibrator = MonteGodotCalibrator.new()
	# Connect signals to print handlers
	calibrator.calibration_update.connect(_on_calibration_update)
	calibrator.calibration_finished.connect(_on_calibration_finished)
	
	# Initialize graph node for plotting - check after nodes are ready
	if not _graph_node:
		push_warning("Calibration: Graph2D node not found at path specified in _graph_node. Plotting will be disabled.")

	run_config_calibration(DEFAULT_JOB_CONFIG_PATH_PI_EXAMPLE)


## Programmatically starts a calibration run.
## 
## Parameters:
##   p_job_config_path: Path to the base JobConfig resource (.tres).
##   p_calibration_n_cases_override: Optional. Number of cases for calibration runs. -1 uses calibrator default.
##   p_super_batch_sizes_to_test_override: Optional. Array of super batch sizes. Empty uses calibrator default.
func run_config_calibration(
	p_job_config_path: String,
	p_calibration_n_cases_override: int = -1,
	p_super_batch_sizes_to_test_override: Array[int] = []
) -> void:
	print("Starting calibration programmatically...")

	if p_job_config_path.is_empty():
		printerr("Calibration Error: Base JobConfig path cannot be empty.")
		return

	var base_job_config: JobConfig = load(p_job_config_path)
	if not base_job_config:
		printerr("Calibration Error: Could not load JobConfig from path: %s" % p_job_config_path)
		return
	
	# Special handling for the default Pi example to set its callables
	if p_job_config_path == DEFAULT_JOB_CONFIG_PATH_PI_EXAMPLE:
		# Instantiate or re-use the PiJobFunctions instance
		if _pi_job_functions_instance == null or not is_instance_valid(_pi_job_functions_instance):
			_pi_job_functions_instance = PiJobFunctionsScript.new()
		
		if not is_instance_valid(_pi_job_functions_instance): # Check if new() failed or instance is otherwise invalid
			printerr("Calibration Error: Failed to create or obtain a valid PiJobFunctions instance.")
			return # Critical error, cannot proceed with setting callables

		# Set callables to the methods on the PiJobFunctions instance
		base_job_config.preprocess_callable = Callable(_pi_job_functions_instance, "_preprocess")
		base_job_config.run_callable = Callable(_pi_job_functions_instance, "_run")
		base_job_config.postprocess_callable = Callable(_pi_job_functions_instance, "_postprocess")
		print("Info: Using callables from PiJobFunctions instance for default estimate_pi_job.tres.")
		
		# The EstimatePi scene instance and its add_child/queue_free logic are no longer needed here
		# as the callables are now from a RefCounted object.

	# It is assumed that any other JobConfig passed will have its callables already set
	# or set by its own script if it's a custom JobConfig class instance.

	if not base_job_config.is_valid():
		assert(false, "Calibration Error: Loaded JobConfig is invalid after attempting to set callables. Path: %s. Ensure callables (preprocess, run, postprocess) are set and other parameters are correct." % p_job_config_path)
		# The assert(false) will stop execution if assertions are enabled (default in debug).
		# The return statement might become redundant or you might choose to keep it
		# if you want to gracefully handle cases where assertions are disabled in release builds,
		# though for "Crash Early", you'd let it fail.
		return

	calibrator.run_calibration(base_job_config, p_super_batch_sizes_to_test_override, p_calibration_n_cases_override)


# Example of how to run the Pi calibration specifically
func run_default_pi_example_calibration() -> void:
	print("--- Running Default Pi Example Calibration ---")
	run_config_calibration(DEFAULT_JOB_CONFIG_PATH_PI_EXAMPLE)


func _on_calibration_update(message: String) -> void:
	print("CALIBRATION UPDATE: %s" % message)


func _on_calibration_finished(results: Array[Dictionary]) -> void:
	print("--- CALIBRATION PROCESS FULLY COMPLETED ---")
	if results.is_empty():
		print("Calibration finished, but no results were generated.")
	else:
		print("Calibration Results (from calibration.gd):")
		for i in range(results.size()):
			var result_dict: Dictionary = results[i]
			print("  Result %d:" % (i + 1))
			for key in result_dict:
				print("    %s: %s" % [key, str(result_dict[key])]) # Ensure value is cast to string for printing

	# Plot results if graph node is available
	if _graph_node:
		plot_calibration_results(results)
	else:
		push_warning("Calibration: Graph node not found, skipping plotting.")

	# For now, quit after attempting to plot or if plotting is skipped.
	# You might want to add a delay or user input before quitting if you want to see the graph.
	#get_tree().quit()


# --- Plotting Functions (merged from CalibrationPlotter) ---
func plot_calibration_results(results_data: Array[Dictionary]) -> void:
	if not _graph_node:
		printerr("Calibration.plot_calibration_results: Graph2D node is not assigned.")
		return

	# Instantiate and add LineSeries if it doesn't exist or was freed
	if _line_series == null or not is_instance_valid(_line_series):

		_line_series = LineSeries.new(Color.SEA_GREEN, 2.0)
		_line_series.name = "DynamicLineSeries" # Give it a name for potential future reference/removal
		_graph_node.add_child(_line_series)
	# else, re-use existing _line_series

	if results_data.is_empty():
		push_warning("Calibration.plot_calibration_results: No results data provided to plot.")
		_line_series.clear_data()
		return

	var points: Array[Vector2] = []
	for result_entry in results_data:
		if result_entry.has("super_batch_size") and result_entry.has("time_msec"):
			var sbs: float = float(result_entry["super_batch_size"])
			var time_ms: float = float(result_entry["time_msec"])
			
			# Only plot valid time entries
			if time_ms >= 0:
				points.append(Vector2(sbs, time_ms))
		else:
			push_warning("Calibration.plot_calibration_results: Result entry is missing 'super_batch_size' or 'time_msec'. Entry: %s" % str(result_entry))

	if points.is_empty():
		push_warning("Calibration.plot_calibration_results: No valid data points found in results_data to plot.")
		_line_series.clear_data()
		return

	_line_series.set_data_from_Vector2_array(points)
	_line_series._recalculate_min_and_max_limits()
	_line_series.property_changed.emit()

	# Set Graph2D limits based on series data with some padding
	var data_min: Vector2 = _line_series.min_limits
	var data_max: Vector2 = _line_series.max_limits
	var padding_x: float = (data_max.x - data_min.x) * 0.1 if (data_max.x - data_min.x) > 0 else 1.0 # Avoid zero padding if only one point
	var padding_y: float = (data_max.y - data_min.y) * 0.1 if (data_max.y - data_min.y) > 0 else 1.0

	_graph_node.x_min = data_min.x - padding_x
	_graph_node.x_max = data_max.x + padding_x
	_graph_node.y_min = data_min.y - padding_y
	_graph_node.y_max = data_max.y + padding_y
	
	# _graph_node._update_graph_limits() # This might now be redundant or even counterproductive if auto_scaling is true, as it could expand again
	
	_graph_node.title = "Calibration: Batch Size vs. Time"
	_graph_node.horizontal_title = "Batch Size (Number of Cases)"
	_graph_node.vertical_title = "Time (milliseconds)"
	
	_graph_node.queue_redraw()
	
	print("Calibration: Plotted %d points." % points.size())
# --- End Plotting Functions ---
