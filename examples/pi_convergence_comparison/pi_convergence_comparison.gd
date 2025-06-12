# res://examples/pi_convergence_comparison/pi_convergence_comparison.gd
class_name PiConvergenceComparison extends Node

## Compares Random vs SOBOL sampling methods for π estimation
## Shows convergence plots to demonstrate SOBOL's superior efficiency

var monte_godot: MonteGodot
var _pi_job_functions_instance: PiJobFunctions

@onready var _convergence_graph_node: Graph2D = $VBoxContainer/ConvergenceGraph
@onready var _error_graph_node: Graph2D = $VBoxContainer/ErrorGraph
@onready var _legend_label: RichTextLabel = $VBoxContainer/LegendLabel

var _random_convergence_series: LineSeries = null
var _sobol_convergence_series: LineSeries = null
var _random_error_series: LineSeries = null
var _sobol_error_series: LineSeries = null
var _pi_reference_series: LineSeries = null

const PI_VALUE: float = PI
const N_CASES: int = 1000000
const SUPER_BATCH_SIZE: int = 100000  # Scale up batch size proportionally
const INNER_BATCH_SIZE: int = 1000   # Scale up inner batch size too

const PiJobFunctionsScript: Script = preload("res://examples/calibration/pi_job_functions.gd")

# Data collection for convergence tracking
var _random_results: Array[bool] = []
var _sobol_results: Array[bool] = []
var _jobs_completed: int = 0

func _ready() -> void:
	monte_godot = MonteGodot.new()
	monte_godot.all_jobs_completed.connect(_on_all_jobs_completed)
	
	_pi_job_functions_instance = PiJobFunctionsScript.new()
	
	print("Starting π convergence comparison: Random vs SOBOL sampling")
	print("Total cases: %d, Super batch size: %d" % [N_CASES, SUPER_BATCH_SIZE])
	
	_start_comparison()

func _start_comparison() -> void:
	var jobs: Array[JobConfig] = []
	
	# Set a different random seed each run for true randomness
	var random_seed: int = Time.get_ticks_msec() % 1000000
	StatMath.set_seed(random_seed)
	print("Using random seed: %d for this run" % random_seed)
	
	# Pre-generate 2D SOBOL samples and store globally
	_sobol_2d_samples = StatMath.SamplingGen.generate_samples_2d(
		N_CASES,
		StatMath.SamplingGen.SamplingMethod.SOBOL
	)
	print("Generated %d 2D SOBOL samples for coordinated sampling" % _sobol_2d_samples.size())
	
	# Create Random sampling job
	var random_job: JobConfig = _create_pi_job("pi_random", StatMath.SamplingGen.SamplingMethod.RANDOM)
	jobs.append(random_job)
	print("Random job created using standard InVar approach")
	
	# Create SOBOL sampling job  
	var sobol_job: JobConfig = _create_pi_job("pi_sobol", StatMath.SamplingGen.SamplingMethod.SOBOL)
	jobs.append(sobol_job)
	print("SOBOL job created using proper 2D sampling from StatMath.SamplingGen")
	
	monte_godot.run_simulations(jobs)

func _create_pi_job(job_name: String, sampling_method: StatMath.SamplingGen.SamplingMethod) -> JobConfig:
	var job_config: JobConfig = JobConfig.new()
	job_config.job_name = job_name
	job_config.n_cases = N_CASES
	job_config.num_threads = 10
	job_config.super_batch_size = SUPER_BATCH_SIZE
	job_config.inner_batch_size = INNER_BATCH_SIZE
	job_config.first_case_is_median = false
	job_config.save_case_data = false
	
	# Set custom callables that handle 2D sampling properly
	if sampling_method == StatMath.SamplingGen.SamplingMethod.SOBOL:
		job_config.preprocess_callable = Callable(self, "_preprocess_2d_sobol")
		job_config.run_callable = Callable(self, "_run_2d_sobol")
		job_config.postprocess_callable = Callable(self, "_postprocess_2d_sobol")
		# SOBOL uses pre-generated 2D samples stored in _sobol_2d_samples
	else:
		# For random sampling, use the existing approach
		job_config.preprocess_callable = Callable(_pi_job_functions_instance, "_preprocess")
		job_config.run_callable = Callable(_pi_job_functions_instance, "_run")
		job_config.postprocess_callable = Callable(_pi_job_functions_instance, "_postprocess")
		
		# Create input variables with specified sampling method
		var x_var: InVar = InVar.new()
		x_var.name = "x"
		x_var.distribution_type = InVar.DistributionType.UNIFORM
		x_var.uniform_a = -1.0
		x_var.uniform_b = 1.0
		x_var.sample_method = sampling_method
		x_var.var_idx = 0
		
		var y_var: InVar = InVar.new()
		y_var.name = "y" 
		y_var.distribution_type = InVar.DistributionType.UNIFORM
		y_var.uniform_a = -1.0
		y_var.uniform_b = 1.0
		y_var.sample_method = sampling_method
		y_var.var_idx = 1
		
		job_config.in_vars = [x_var, y_var]
	
	return job_config

func _on_all_jobs_completed(all_job_results: Dictionary) -> void:
	print("--- π Convergence Comparison: All Jobs Completed ---")
	
	# Extract results from both jobs
	for job_name: StringName in all_job_results.keys():
		var job_data: Dictionary = all_job_results[job_name]
		var output_vars: Dictionary = job_data.get("output_vars", {})
		
		if output_vars.has(&"is_inside"):
			var is_inside_out_var: OutVar = output_vars[&"is_inside"]
			var is_inside_values: Array = is_inside_out_var.get_all_raw_values()
			
			if job_name == &"pi_random":
				_random_results = _convert_to_bool_array(is_inside_values)
				print("Random sampling results collected: %d samples" % _random_results.size())
			elif job_name == &"pi_sobol":
				_sobol_results = _convert_to_bool_array(is_inside_values)
				print("SOBOL sampling results collected: %d samples" % _sobol_results.size())
	
	# Plot convergence comparison
	_plot_convergence_comparison()
	
	# Setup legend
	_setup_legend()
	
	# Print final statistics
	_print_final_statistics()

func _convert_to_bool_array(raw_values: Array) -> Array[bool]:
	var bool_array: Array[bool] = []
	bool_array.resize(raw_values.size())
	for i in range(raw_values.size()):
		bool_array[i] = raw_values[i] == true
	return bool_array

func _plot_convergence_comparison() -> void:
	if _random_results.is_empty() or _sobol_results.is_empty():
		push_error("Cannot plot comparison: missing results data")
		return
		
	print("Plotting convergence comparison...")
	
	# Calculate convergence data
	var random_convergence: Array[Vector2] = _calculate_pi_convergence(_random_results)
	var sobol_convergence: Array[Vector2] = _calculate_pi_convergence(_sobol_results)
	
	# Calculate error data
	print("Calculating random errors...")
	var random_errors: Array[Vector2] = _calculate_pi_errors(_random_results)
	print("Calculating SOBOL errors...")
	var sobol_errors: Array[Vector2] = _calculate_pi_errors(_sobol_results)
	
	# Plot convergence graph
	_setup_convergence_graph(random_convergence, sobol_convergence)
	
	# Plot error graph  
	_setup_error_graph(random_errors, sobol_errors)

func _calculate_pi_convergence(results: Array[bool]) -> Array[Vector2]:
	var convergence_points: Array[Vector2] = []
	var cumulative_inside: int = 0
	
	# Sample every 10th point for performance
	for i in range(results.size()):
		if results[i]:
			cumulative_inside += 1
		
		# Only add every 10th point or the last point
		if (i + 1) % 10 == 0 or i == results.size() - 1:
			var pi_estimate: float = 4.0 * float(cumulative_inside) / float(i + 1)
			convergence_points.append(Vector2(float(i + 1), pi_estimate))
	
	return convergence_points

func _calculate_pi_errors(results: Array[bool]) -> Array[Vector2]:
	var error_points: Array[Vector2] = []
	var cumulative_inside: int = 0
	
	# Sample every 10th point for performance
	for i in range(results.size()):
		if results[i]:
			cumulative_inside += 1
		
		var pi_estimate: float = 4.0 * float(cumulative_inside) / float(i + 1)
		var absolute_error: float = abs(pi_estimate - PI_VALUE)
		
		# Debug: Print some key error points to see the trend
		if (i + 1) % (results.size() / 10) == 0:  # Print every 10% progress
			print("Error at sample %d: π_est=%.6f, error=%.6f" % [i + 1, pi_estimate, absolute_error])
		
		# Only add every 10th point or the last point
		if (i + 1) % 10 == 0 or i == results.size() - 1:
			error_points.append(Vector2(float(i + 1), absolute_error))
	
	return error_points

func _setup_convergence_graph(random_data: Array[Vector2], sobol_data: Array[Vector2]) -> void:
	if not _convergence_graph_node:
		push_error("Convergence graph node not found")
		return
	
	# Clear existing series
	for child in _convergence_graph_node.get_children():
		if child is LineSeries:
			child.queue_free()
	
	# Create Random series (orange)
	_random_convergence_series = LineSeries.new(Color.ORANGE, 2.0)
	_random_convergence_series.name = "RandomConvergence"
	_convergence_graph_node.add_child(_random_convergence_series)
	_random_convergence_series.set_data_from_Vector2_array(random_data)
	
	# Create SOBOL series (blue)
	_sobol_convergence_series = LineSeries.new(Color.DODGER_BLUE, 2.0)
	_sobol_convergence_series.name = "SOBOLConvergence"
	_convergence_graph_node.add_child(_sobol_convergence_series)
	_sobol_convergence_series.set_data_from_Vector2_array(sobol_data)
	
	# Create π reference line (black)
	_pi_reference_series = LineSeries.new(Color.BLACK, 1.0)
	_pi_reference_series.name = "PiReference"
	_convergence_graph_node.add_child(_pi_reference_series)
	var pi_line: Array[Vector2] = [Vector2(1.0, PI_VALUE), Vector2(float(N_CASES), PI_VALUE)]
	_pi_reference_series.set_data_from_Vector2_array(pi_line)
	
	# Configure graph
	_convergence_graph_node.title = "π Estimation Convergence: Random vs SOBOL"
	_convergence_graph_node.horizontal_title = "Number of Samples"
	_convergence_graph_node.vertical_title = "Estimated π Value"
	_convergence_graph_node.auto_scaling = true
	_convergence_graph_node.x_decimal_places = 0
	_convergence_graph_node.y_decimal_places = 4
	_convergence_graph_node.queue_redraw()
	
	print("Convergence graph updated with %d random points and %d SOBOL points" % [random_data.size(), sobol_data.size()])

func _setup_error_graph(random_errors: Array[Vector2], sobol_errors: Array[Vector2]) -> void:
	if not _error_graph_node:
		push_error("Error graph node not found")
		return
	
	# Clear existing series
	for child in _error_graph_node.get_children():
		if child is LineSeries:
			child.queue_free()
	
	# Create Random error series (orange)
	_random_error_series = LineSeries.new(Color.ORANGE, 2.0)
	_random_error_series.name = "RandomError"
	_error_graph_node.add_child(_random_error_series)
	_random_error_series.set_data_from_Vector2_array(random_errors)
	
	# Create SOBOL error series (blue)
	_sobol_error_series = LineSeries.new(Color.DODGER_BLUE, 2.0)
	_sobol_error_series.name = "SOBOLError"
	_error_graph_node.add_child(_sobol_error_series)
	_sobol_error_series.set_data_from_Vector2_array(sobol_errors)
	
	# Configure error graph with theoretical convergence reference
	_error_graph_node.title = "π Estimation Error: Random vs SOBOL"
	_error_graph_node.horizontal_title = "Number of Samples"
	_error_graph_node.vertical_title = "Absolute Error |π_est - π|"
	_error_graph_node.auto_scaling = true
	_error_graph_node.x_decimal_places = 0
	_error_graph_node.y_decimal_places = 4
	
	# Add theoretical 1/√n convergence reference line for random sampling
	_add_theoretical_convergence_line()
	
	_error_graph_node.queue_redraw()
	
	print("Error graph updated with %d random points and %d SOBOL points" % [random_errors.size(), sobol_errors.size()])

func _add_theoretical_convergence_line() -> void:
	# Add a theoretical 1/√n convergence line for comparison
	var theoretical_series: LineSeries = LineSeries.new(Color.GRAY, 1.0)
	theoretical_series.name = "TheoreticalConvergence"
	_error_graph_node.add_child(theoretical_series)
	
	# Generate theoretical 1/√n points (scaled to match actual random sampling)
	var theoretical_points: Array[Vector2] = []
	var scaling_constant: float = 0.08  # Adjusted to better match actual random sampling behavior
	
	for i in range(1, N_CASES + 1, N_CASES / 1000):  # Sample 1000 points starting from 1
		var theoretical_error: float = scaling_constant / sqrt(float(i))
		theoretical_points.append(Vector2(float(i), theoretical_error))
	
	theoretical_series.set_data_from_Vector2_array(theoretical_points)
	print("Added theoretical convergence line with %d points (scaling: %.3f)" % [theoretical_points.size(), scaling_constant])

func _setup_legend() -> void:
	if not _legend_label:
		push_warning("Legend label not found")
		return
	
	var legend_text: String = "[center][b]Legend:[/b] "
	legend_text += "[color=orange]Random Sampling[/color] | "
	legend_text += "[color=dodgerblue]SOBOL Sampling[/color] | "
	legend_text += "[color=gray]Theoretical 1/√n[/color] | "
	legend_text += "[color=black]π Reference (3.14159...)[/color][/center]"
	
	_legend_label.text = legend_text

func _print_final_statistics() -> void:
	if _random_results.is_empty() or _sobol_results.is_empty():
		return
	
	var random_inside: int = 0
	var sobol_inside: int = 0
	
	for result in _random_results:
		if result:
			random_inside += 1
	
	for result in _sobol_results:
		if result:
			sobol_inside += 1
	
	var random_pi_final: float = 4.0 * float(random_inside) / float(_random_results.size())
	var sobol_pi_final: float = 4.0 * float(sobol_inside) / float(_sobol_results.size())
	
	var random_error: float = abs(random_pi_final - PI_VALUE)
	var sobol_error: float = abs(sobol_pi_final - PI_VALUE)
	
	print("\n=== Final π Estimation Results ===")
	print("True π value: %.6f" % PI_VALUE)
	print("Random sampling:")
	print("  Final estimate: %.6f (error: %.6f)" % [random_pi_final, random_error])
	print("SOBOL sampling:")
	print("  Final estimate: %.6f (error: %.6f)" % [sobol_pi_final, sobol_error])
	print("Improvement factor: %.2fx %s error" % [random_error / sobol_error if sobol_error > 0 else float("inf"), "lower" if sobol_error < random_error else "higher"])
	print("===================================")

# Global storage for 2D SOBOL samples
var _sobol_2d_samples: Array[Vector2] = []

# Custom processing functions for 2D SOBOL sampling
func _preprocess_2d_sobol(case: Case) -> Array[float]:
	# Get the pre-generated 2D sample for this case from our global storage
	if case.id >= _sobol_2d_samples.size():
		push_error("Case ID %d exceeds available 2D samples (%d)" % [case.id, _sobol_2d_samples.size()])
		return [0.0, 0.0]
	
	var sample_point: Vector2 = _sobol_2d_samples[case.id]
	# Convert from [0,1] to [-1,1] for unit circle
	var x: float = sample_point.x * 2.0 - 1.0
	var y: float = sample_point.y * 2.0 - 1.0
	return [x, y]

func _run_2d_sobol(case_args: Array) -> Array[bool]:
	var x: float = case_args[0]
	var y: float = case_args[1]
	var is_inside_circle: bool = (x*x + y*y) <= 1.0
	return [is_inside_circle]

func _postprocess_2d_sobol(case_obj: Case, is_in_circle: Array[bool]) -> void:
	var out_val_is_inside: OutVal = OutVal.new(&"is_inside", case_obj.id, is_in_circle[0])
	case_obj.add_output_value(out_val_is_inside) 
