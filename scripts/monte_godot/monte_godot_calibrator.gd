# res://scripts/monte_godot/monte_godot_calibrator.gd
class_name MonteGodotCalibrator extends RefCounted

signal calibration_update(message: String)
## Emitted to provide progress updates during calibration.

signal calibration_job_completed(super_batch_size: int, time_msec: int, peak_mem_bytes: int)
## Emitted when a single calibration job for a specific super_batch_size completes.

signal calibration_finished(results: Array[Dictionary])
## Emitted when the entire calibration process is finished.
## Results is an array of dictionaries, each with:
## {"super_batch_size": int, "time_msec": int, "peak_mem_bytes": int, "peak_mem_mb": float}

const DEFAULT_CALIBRATION_N_CASES: int = 10000 # Number of cases to run for each test point
const DEFAULT_SUPER_BATCH_SIZES_TO_TEST: Array[int] = [100, 500, 1000, 2500, 5000, 10000]

var _monte_godot_instance: MonteGodot = null
var _base_job_config: JobConfig = null
var _test_super_batch_sizes: Array[int] = []
var _calibration_n_cases: int = DEFAULT_CALIBRATION_N_CASES

var _current_test_idx: int = 0
var _results_array: Array[Dictionary] = []

func _init() -> void:
	_monte_godot_instance = MonteGodot.new()

## Starts the calibration process.
##
## Parameters:
##   p_base_job_config: The user's actual JobConfig, fully populated with their
##                      preprocess, run, postprocess callables, and InVars.
##   p_super_batch_sizes_to_test: Optional array of super_batch_sizes to test.
##                                Defaults to DEFAULT_SUPER_BATCH_SIZES_TO_TEST.
##   p_calibration_n_cases: Optional number of cases to run for each test point.
##                          Defaults to DEFAULT_CALIBRATION_N_CASES.
func run_calibration(
	p_base_job_config: JobConfig,
	p_super_batch_sizes_to_test: Array[int] = [],
	p_calibration_n_cases: int = -1
) -> void:
	if not p_base_job_config or not p_base_job_config.is_valid():
		push_error("MonteGodotCalibrator: Base JobConfig is null or invalid.")
		calibration_finished.emit([])
		return

	_base_job_config = p_base_job_config
	_results_array.clear()
	_current_test_idx = 0

	if p_super_batch_sizes_to_test.is_empty():
		_test_super_batch_sizes = DEFAULT_SUPER_BATCH_SIZES_TO_TEST.duplicate()
	else:
		_test_super_batch_sizes = p_super_batch_sizes_to_test.duplicate()
	
	_test_super_batch_sizes.sort()
	# Ensure no duplicates if user provides custom array
	var unique_sizes: Array[int] = []
	var last_size: int = -1
	for sbs in _test_super_batch_sizes:
		if sbs > 0 and sbs != last_size: # Ensure positive and unique
			unique_sizes.append(sbs)
			last_size = sbs
	_test_super_batch_sizes = unique_sizes
	
	if _test_super_batch_sizes.is_empty():
		push_warning("MonteGodotCalibrator: No valid super_batch_sizes to test.")
		calibration_finished.emit([])
		return

	if p_calibration_n_cases > 0:
		_calibration_n_cases = p_calibration_n_cases
	else:
		_calibration_n_cases = DEFAULT_CALIBRATION_N_CASES

	# Connect to the MonteGodot instance signals ONCE
	if not _monte_godot_instance.job_completed.is_connected(_on_monte_godot_job_completed):
		_monte_godot_instance.job_completed.connect(_on_monte_godot_job_completed)
	
	calibration_update.emit("Starting calibration with %d n_cases per test." % _calibration_n_cases)
	_run_next_calibration_job()


func _run_next_calibration_job() -> void:
	if _current_test_idx >= _test_super_batch_sizes.size():
		_finish_calibration()
		return

	var test_sbs: int = _test_super_batch_sizes[_current_test_idx]

	# Create a derived JobConfig for this specific test run
	var test_job_config: JobConfig = _base_job_config.duplicate(true) # Deep duplicate
	
	# Fallback duplication if JobConfig.duplicate(true) is not sufficient or custom class behavior is needed
	# This assumes JobConfig.new can reconstruct from parts if duplicate() is not fully deep for callables or complex objects.
	if not test_job_config or not test_job_config.preprocess_callable.is_valid(): # Check if duplication worked as expected
		test_job_config = JobConfig.new(
			_base_job_config.job_name, # Keep original name prefix for identification
			_calibration_n_cases,
			_base_job_config.num_threads,
			test_sbs, # Current SBS to test
			_base_job_config.inner_batch_size,
			_base_job_config.preprocess_callable, # Assign callables directly
			_base_job_config.run_callable,
			_base_job_config.postprocess_callable,
			_base_job_config.in_vars.duplicate(true), # Deep duplicate InVars if they are resources
			_base_job_config.other_configs.duplicate(true) # Deep duplicate other configs
		)

	test_job_config.job_name = &"%s_Calib_NC%d_SBS%d" % [_base_job_config.job_name, _calibration_n_cases, test_sbs]
	test_job_config.n_cases = _calibration_n_cases
	test_job_config.super_batch_size = test_sbs
	test_job_config.save_case_data = false # Ensure we don't save case data during calibration
	test_job_config.first_case_is_median = _base_job_config.first_case_is_median # Preserve this setting

	calibration_update.emit("Testing Super Batch Size: %d" % test_sbs)
	
	var result = await _monte_godot_instance.run_simulations([test_job_config])
	if result != OK: # Check if MonteGodot itself reported an immediate failure to start
		push_error("MonteGodotCalibrator: Failed to start simulation for SBS %d (MonteGodot returned %s)." % [test_sbs, str(result)])
		var error_entry: Dictionary = {
			"super_batch_size": test_sbs,
			"time_msec": -1,
			"peak_mem_bytes": -1,
			"peak_mem_mb": -1.0,
			"error": "Failed to start MonteGodot simulation (Code: %s)" % str(result)
		}
		_results_array.append(error_entry)
		calibration_job_completed.emit(test_sbs, -1, -1) # Emit failure for this job
		_current_test_idx += 1
		_run_next_calibration_job() # Try next job


func _on_monte_godot_job_completed(job_name: StringName, _job_results: Array[Case], job_stats: Dictionary, _job_output_vars: Dictionary) -> void:
	# Check if the job_name matches what we expect for the current calibration step.
	# This is important if multiple systems might be using the same MonteGodot instance, though unlikely here.
	var expected_sbs: int = _test_super_batch_sizes[_current_test_idx]
	var expected_job_name_fragment = &"_Calib_NC%d_SBS%d" % [_calibration_n_cases, expected_sbs]

	if not str(job_name).contains(str(expected_job_name_fragment)):
		# This job_completed signal is not for the current calibration test point. Ignore.
		# This could happen if the MonteGodot instance was used by something else concurrently.
		# For this calibrator, we assume sequential, dedicated use of the _monte_godot_instance.
		return

	var time_taken_msec: int = -1
	var peak_mem: int = -1
	var error_str: String = ""

	if job_stats.has("error"):
		error_str = job_stats["error"]
		push_warning("MonteGodotCalibrator: Job '%s' (SBS: %d) failed: %s" % [job_name, expected_sbs, error_str])
	else:
		time_taken_msec = job_stats.get("total_execution_time_msec", -1)
		peak_mem = job_stats.get("peak_memory_bytes", -1)
		if time_taken_msec == -1 or peak_mem == -1:
			error_str = "Missing time or memory data in job_stats."
			push_warning("MonteGodotCalibrator: Job '%s' (SBS: %d) - %s" % [job_name, expected_sbs, error_str])
		else:
			calibration_update.emit("Super Batch Size %d: Time: %d ms, Peak Memory: %.2f MB" % [expected_sbs, time_taken_msec, float(peak_mem) / (1024.0*1024.0)])

	var result_entry: Dictionary = {
		"super_batch_size": expected_sbs,
		"time_msec": time_taken_msec,
		"peak_mem_bytes": peak_mem,
		"peak_mem_mb": float(peak_mem) / (1024.0 * 1024.0) if peak_mem > -1 else -1.0,
		"error": error_str
	}
	_results_array.append(result_entry)
	calibration_job_completed.emit(expected_sbs, time_taken_msec, peak_mem)

	_current_test_idx += 1
	_run_next_calibration_job()


func _finish_calibration() -> void:
	calibration_update.emit("Calibration finished. Results:")
	for res in _results_array:
		var error_msg = ""
		if not res["error"].is_empty():
			error_msg = " (Error: %s)" % res["error"]

		if res["time_msec"] == -1 or res["peak_mem_bytes"] == -1 and res["error"].is_empty(): # If no specific error but data is bad
			error_msg += " (Incomplete data received)"
		
		if res["time_msec"].is_nan() or res["peak_mem_mb"].is_nan(): # Check for NaN from calculations
			error_msg += " (Calculation resulted in NaN)"


		if res["time_msec"] == -1 or res["peak_mem_bytes"] == -1 or res["time_msec"].is_nan() or res["peak_mem_mb"].is_nan():
			calibration_update.emit("  Super Batch Size: %d - FAILED%s" % [res["super_batch_size"], error_msg])
		else:
			calibration_update.emit("  Super Batch Size: %d - Time: %4d ms - Peak Memory: %6.2f MB%s" % \
				[res["super_batch_size"], res["time_msec"], res["peak_mem_mb"], error_msg])
	
	if _monte_godot_instance and _monte_godot_instance.job_completed.is_connected(_on_monte_godot_job_completed):
		_monte_godot_instance.job_completed.disconnect(_on_monte_godot_job_completed)

	calibration_finished.emit(_results_array) 