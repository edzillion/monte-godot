class_name Calibration extends Node

var calibrator: MonteGodotCalibrator
var _pi_job_functions_instance: PiJobFunctions

@onready var _max_memory_graph_node: Graph2D = $HBoxContainer/MaxMemory
@onready var _time_graph_node: Graph2D = $HBoxContainer/Time

var _max_memory_line_series: LineSeries = null
var _time_line_series: LineSeries = null

const DEFAULT_JOB_CONFIG_PATH_PI_EXAMPLE: String = "res://examples/estimate_pi/estimate_pi_job.tres"
const PiJobFunctionsScript: Script = preload("res://examples/calibration/pi_job_functions.gd")

func _ready() -> void:
	calibrator = MonteGodotCalibrator.new()
	# Connect signals to print handlers
	calibrator.calibration_update.connect(_on_calibration_update)
	calibrator.calibration_finished.connect(_on_calibration_finished)
	
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
	if _max_memory_graph_node and _time_graph_node:
		plot_calibration_results(results)
	else:
		push_warning("Calibration: Graph nodes not found, skipping plotting.")

	# For now, quit after attempting to plot or if plotting is skipped.
	# You might want to add a delay or user input before quitting if you want to see the graph.
	#get_tree().quit()


# --- Plotting Functions (merged from CalibrationPlotter) ---
func plot_calibration_results(results_data: Array[Dictionary]) -> void:
	if not _time_graph_node or not _max_memory_graph_node:
		printerr("Calibration.plot_calibration_results: One or both Graph2D nodes are not assigned.")
		return

	# Initialize Time Series
	if _time_line_series == null or not is_instance_valid(_time_line_series):
		_time_line_series = LineSeries.new(Color.SEA_GREEN, 2.0)
		_time_line_series.name = "TimeLineSeries"
		_time_graph_node.add_child(_time_line_series)

	# Initialize Memory Series
	if _max_memory_line_series == null or not is_instance_valid(_max_memory_line_series):
		_max_memory_line_series = LineSeries.new(Color.DODGER_BLUE, 2.0) # Different color for memory
		_max_memory_line_series.name = "MaxMemoryLineSeries"
		_max_memory_graph_node.add_child(_max_memory_line_series)

	if results_data.is_empty():
		push_warning("Calibration.plot_calibration_results: No results data provided to plot.")
		if is_instance_valid(_time_line_series): _time_line_series.clear_data()
		if is_instance_valid(_max_memory_line_series): _max_memory_line_series.clear_data()
		return

	var points_time: Array[Vector2] = []
	var points_memory: Array[Vector2] = []

	for result_entry in results_data:
		if not result_entry.has("super_batch_size"):
			push_warning("Calibration.plot_calibration_results: Result entry missing 'super_batch_size'. Entry: %s" % str(result_entry))
			continue

		var sbs: float = float(result_entry["super_batch_size"])

		# Process time data
		if result_entry.has("time_msec"):
			var time_ms: float = float(result_entry["time_msec"])
			if time_ms >= 0:
				points_time.append(Vector2(sbs, time_ms))
		else:
			push_warning("Calibration.plot_calibration_results: Result entry for SBS %f missing 'time_msec'." % sbs)

		# Process memory data
		if result_entry.has("peak_mem_percentage"):
			var mem_percentage: float = float(result_entry["peak_mem_percentage"])
			if mem_percentage >= 0:
				points_memory.append(Vector2(sbs, mem_percentage))
		else:
			push_warning("Calibration.plot_calibration_results: Result entry for SBS %f missing 'peak_mem_percentage'." % sbs)

	# --- Plot Time Graph ---
	if points_time.is_empty():
		push_warning("Calibration.plot_calibration_results: No valid data points found for time graph.")
		if is_instance_valid(_time_line_series): _time_line_series.clear_data()
	else:
		_time_line_series.set_data_from_Vector2_array(points_time)
		_time_line_series._recalculate_min_and_max_limits()
		_time_line_series.property_changed.emit()

		var time_data_min: Vector2 = _time_line_series.min_limits
		var time_data_max: Vector2 = _time_line_series.max_limits
		var time_padding_x: float = (time_data_max.x - time_data_min.x) * 0.1 if (time_data_max.x - time_data_min.x) > 0 else 1.0
		var time_padding_y: float = (time_data_max.y - time_data_min.y) * 0.1 if (time_data_max.y - time_data_min.y) > 0 else 1.0

		_time_graph_node.x_min = time_data_min.x - time_padding_x
		_time_graph_node.x_max = time_data_max.x + time_padding_x
		_time_graph_node.y_min = time_data_min.y - time_padding_y
		_time_graph_node.y_max = time_data_max.y + time_padding_y
		_time_graph_node.x_tick_count = 5 # Reduce X-axis ticks
		
		_time_graph_node.title = "Calibration: Batch Size vs. Time"
		_time_graph_node.horizontal_title = "Batch Size (Number of Cases)"
		_time_graph_node.vertical_title = "Time (milliseconds)"
		_time_graph_node.queue_redraw()
		print("Calibration: Plotted %d points on Time graph." % points_time.size())

	# --- Plot Max Memory Graph ---
	if points_memory.is_empty():
		push_warning("Calibration.plot_calibration_results: No valid data points found for max memory graph.")
		if is_instance_valid(_max_memory_line_series): _max_memory_line_series.clear_data()
	else:
		_max_memory_line_series.set_data_from_Vector2_array(points_memory)
		_max_memory_line_series._recalculate_min_and_max_limits()
		_max_memory_line_series.property_changed.emit()

		var mem_data_min: Vector2 = _max_memory_line_series.min_limits
		var mem_data_max: Vector2 = _max_memory_line_series.max_limits
		var mem_padding_x: float = (mem_data_max.x - mem_data_min.x) * 0.1 if (mem_data_max.x - mem_data_min.x) > 0 else 1.0
		var mem_padding_y: float = (mem_data_max.y - mem_data_min.y) * 0.1 if (mem_data_max.y - mem_data_min.y) > 0 else 1.0

		_max_memory_graph_node.x_min = mem_data_min.x - mem_padding_x
		_max_memory_graph_node.x_max = mem_data_max.x + mem_padding_x
		_max_memory_graph_node.y_min = mem_data_min.y - mem_padding_y
		_max_memory_graph_node.y_max = mem_data_max.y + mem_padding_y
		_max_memory_graph_node.x_tick_count = 5 # Reduce X-axis ticks

		_max_memory_graph_node.title = "Calibration: Batch Size vs. Max Memory (%)"
		_max_memory_graph_node.horizontal_title = "Batch Size (Number of Cases)"
		_max_memory_graph_node.vertical_title = "Max Memory (%)"
		_max_memory_graph_node.queue_redraw()
		print("Calibration: Plotted %d points on Max Memory graph." % points_memory.size())
	

# --- End Plotting Functions ---
