# res://scripts/monte_godot/monte_godot_calibrator.gd
class_name MonteGodotCalibrator extends RefCounted

signal calibration_update(message: String)
## Emitted to provide progress updates during calibration.

signal calibration_job_completed(super_batch_size: int, time_msec: int, peak_mem_bytes: int)
## Emitted when a single calibration job for a specific super_batch_size completes.

signal calibration_finished(results: Array[Dictionary])


const DEFAULT_SUPER_BATCH_SIZES_TO_TEST: Array[int] = [
	 10000, 12500, 15000, 17500, 
	 20000, 22500, 25000, 27500, 
	 30000, 32500, 35000, 37500, 
	 40000, 42500, 45000, 47500, 
	 50000, 52500, 55000, 57500, 
	 60000, 62500, 65000, 67500, 
	 70000, 72500, 75000, 77500,
	 80000, 82500, 85000, 87500, 
	 90000, 92500, 95000, 97500, 
	 100000, 102500, 105000, 107500, 
	 110000, 112500, 115000, 117500, 
	 120000, 122500, 125000, 127500, 
	 130000, 132500, 135000, 137500, 
	 140000, 142500, 145000, 147500, 
	 150000, 152500, 155000, 157500, 
	 160000, 162500, 165000, 167500, 
	 170000, 172500, 175000, 177500, 
	 180000, 182500, 185000, 187500, 
	 190000, 192500, 195000, 197500, 
	 #200000, 202500, 205000, 207500, 
	 #210000, 212500, 215000, 217500, 
	 #220000, 222500, 225000, 227500,
	 #230000, 232500, 235000, 237500,
	 #240000, 242500, 245000, 247500,
	 #250000, 252500, 255000, 257500,
	 #260000, 262500, 265000, 267500,
	 #270000, 272500, 275000, 277500,
	 #280000, 282500, 285000, 287500,
	 #290000, 292500, 295000, 297500,
	 #300000, 302500, 305000, 307500,
	 #310000, 312500, 315000, 317500,
	 #320000, 322500, 325000, 327500,
	 #330000, 332500, 335000, 337500,
	 #340000, 342500, 345000, 347500,
	 #350000, 352500, 355000, 357500,
	 #360000, 362500, 365000, 367500,
	# 370000, 372500, 375000, 377500,
	# 380000, 382500, 385000, 387500,
	# 390000, 392500, 395000, 397500,
	# 400000, 402500, 405000, 407500,
	# 410000, 412500, 415000, 417500,
	# 420000, 422500, 425000, 427500,
	# 430000, 432500, 435000, 437500,
	# 440000, 442500, 445000, 447500,
	#450000, 452500, 455000, 457500,
	#460000, 462500, 465000, 467500,
	#470000, 472500, 475000, 477500,
	#480000, 482500, 485000, 487500,
	#490000, 492500, 495000, 497500,
	#500000, 502500, 505000, 507500,
	#510000, 512500, 515000, 517500,
	#520000, 522500, 525000, 527500,
	#530000, 532500, 535000, 537500,
	#540000, 542500, 545000, 547500,
	#550000, 552500, 555000, 557500,
	#560000, 562500, 565000, 567500,
	#570000, 572500, 575000, 577500,
	#580000, 582500, 585000, 587500,
	#590000, 592500, 595000, 597500,
	#600000, 602500, 605000, 607500,
	#610000, 612500, 615000, 617500,
	#620000, 622500, 625000, 627500,
	#630000, 632500, 635000, 637500,
	#640000, 642500, 645000, 647500,
	#650000, 652500, 655000, 657500,
	#660000, 662500, 665000, 667500,
	#670000, 672500, 675000, 677500,
	#680000, 682500, 685000, 687500,
	#690000, 692500, 695000, 697500,
	#700000, 702500, 705000, 707500,
	]

var _monte_godot_instance: MonteGodot = null
var _base_job_config: JobConfig = null
var _test_super_batch_sizes: Array[int] = []
# var _calibration_n_cases: int = DEFAULT_CALIBRATION_N_CASES

var _current_test_idx: int = 0
var _results_array: Array[Dictionary] = []

func _init() -> void:
	_monte_godot_instance = MonteGodot.new()


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
		push_warning("MonteGodotCalibrator: No valid super_batch_sizes (batch sizes to test) to test.")
		calibration_finished.emit([])
		return

	# _calibration_n_cases is no longer set from p_calibration_n_cases or DEFAULT_CALIBRATION_N_CASES here.
	# It will be set to test_sbs for each job.
	# The p_calibration_n_cases parameter to run_calibration is now ignored.
	if p_calibration_n_cases > 0:
		# This parameter is effectively ignored now as n_cases is set per test_sbs.
		# We can keep this to avoid breaking the signature or remove it later.
		print("MonteGodotCalibrator: Info - p_calibration_n_cases parameter is currently ignored.")

	# Connect to the MonteGodot instance signals ONCE
	if not _monte_godot_instance.job_completed.is_connected(_on_monte_godot_job_completed_individual_job_data_gathering): # Renamed old handler
		# This connection is for individual job data like peak memory if needed before all_jobs_completed
		# However, for sequencing the next calibration run, we will use all_jobs_completed.
		# For now, let's assume all necessary stats are in all_jobs_completed's payload or can be derived.
		# If specific per-job signals are needed for UI or detailed logging before a job set finishes,
		# a separate handler for job_completed could be maintained but NOT for sequencing.
		# Let's simplify and assume we only need the final stats from all_jobs_completed.
		# So, we might not even need to connect to job_completed if all_jobs_completed provides enough.
		# For now, let's remove the direct connection to the old sequencing handler.
		pass

	if not _monte_godot_instance.all_jobs_completed.is_connected(_on_monte_godot_all_jobs_completed_for_sequencing):
		_monte_godot_instance.all_jobs_completed.connect(_on_monte_godot_all_jobs_completed_for_sequencing)
	
	calibration_update.emit("Starting calibration. Each 'Super Batch Size' test point will run that many cases.") # Updated message
	_run_next_calibration_job()


func _run_next_calibration_job() -> void:
	if _current_test_idx >= _test_super_batch_sizes.size():
		_finish_calibration()
		return

	var test_sbs: int = _test_super_batch_sizes[_current_test_idx]
	# For this calibration mode, n_cases for the job IS the super_batch_size we are testing.
	var current_n_cases_for_job: int = test_sbs 

	# Create a derived JobConfig for this specific test run
	var test_job_config: JobConfig = _base_job_config.duplicate(true) # Deep duplicate

	# Explicitly re-assign callables to ensure they are correct on the duplicated instance
	# This is a safeguard in case duplicate(true) doesn't handle Callables perfectly for this use case.
	if test_job_config: # Only if duplication itself succeeded
		test_job_config.preprocess_callable = _base_job_config.preprocess_callable
		test_job_config.run_callable = _base_job_config.run_callable
		test_job_config.postprocess_callable = _base_job_config.postprocess_callable
	
	assert(test_job_config.preprocess_callable.is_valid(), "Calibrator: preprocess_callable is invalid after duplicate() but before explicit re-assignment.")
	assert(test_job_config.run_callable.is_valid(), "Calibrator: run_callable is invalid after duplicate() but before explicit re-assignment.")
	assert(test_job_config.postprocess_callable.is_valid(), "Calibrator: postprocess_callable is invalid after duplicate() but before explicit re-assignment.")
	
	
	
	# Fallback duplication if JobConfig.duplicate(true) is not sufficient or custom class behavior is needed
	# This assumes JobConfig.new can reconstruct from parts if duplicate() is not fully deep for callables or complex objects.
	if not test_job_config or not test_job_config.preprocess_callable.is_valid(): # Check if duplication worked as expected
		test_job_config = JobConfig.new(
			_base_job_config.job_name, # Keep original name prefix for identification
			current_n_cases_for_job, # n_cases is the SBS being tested
			_base_job_config.num_threads,
			test_sbs, # Current SBS to test (also used as super_batch_size for the job)
			_base_job_config.inner_batch_size,
			_base_job_config.preprocess_callable, # Assign callables directly
			_base_job_config.run_callable,
			_base_job_config.postprocess_callable,
			_base_job_config.in_vars.duplicate(true), # Deep duplicate InVars if they are resources
			_base_job_config.other_configs.duplicate(true) # Deep duplicate other configs
		)

	test_job_config.job_name = &"%s_Calib_NC%d_SBS%d" % [_base_job_config.job_name, current_n_cases_for_job, test_sbs]
	test_job_config.n_cases = current_n_cases_for_job
	test_job_config.super_batch_size = test_sbs # Ensure super_batch_size is also the SBS for one chunk
	test_job_config.save_case_data = false # Ensure we don't save case data during calibration
	test_job_config.first_case_is_median = _base_job_config.first_case_is_median # Preserve this setting
	test_job_config.inner_batch_size = 1000 # Force inner_batch_size for calibration runs

	calibration_update.emit("Testing Batch Size (n_cases = super_batch_size): %d, Inner Batch Size: %d" % [test_sbs, test_job_config.inner_batch_size]) # Updated message
	
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
		_run_next_calibration_job() # Try next job directly
		return # Ensure no further execution in this branch


# Renamed old handler - this might be repurposed or removed if all_jobs_completed is sufficient
func _on_monte_godot_job_completed_individual_job_data_gathering(job_name: StringName, _job_results: Array[Case], job_stats: Dictionary, _job_output_vars: Dictionary) -> void:
	# This function is no longer responsible for sequencing via _run_next_calibration_job()
	# It could be used for logging detailed progress of individual jobs if needed.
	# For now, its sequencing role is removed.
	# We need to ensure the data for _results_array is correctly populated by the new handler.
	pass


func _on_monte_godot_all_jobs_completed_for_sequencing(all_aggregated_results: Dictionary) -> void:
	# Since the calibrator runs one job config at a time via MonteGodot,
	# all_aggregated_results will contain information for that single job.

	if all_aggregated_results.is_empty():
		push_warning("MonteGodotCalibrator: Received empty all_aggregated_results. Cannot process.")
		# Decide how to handle this - possibly log error and attempt next job or finish.
		_current_test_idx += 1
		_run_next_calibration_job()
		return

	# Extract the job name and its data (assuming one job was run)
	var actual_job_name: StringName = all_aggregated_results.keys()[0]
	var job_data: Dictionary = all_aggregated_results[actual_job_name]
	var job_stats: Dictionary = job_data.get("stats", {})

	# Check if the job_name matches what we expect for the current calibration step.
	if _current_test_idx >= _test_super_batch_sizes.size():
		# This can happen if _finish_calibration was already called due to some race or error.
		push_warning("MonteGodotCalibrator: _on_monte_godot_all_jobs_completed_for_sequencing called but _current_test_idx is out of bounds. Current idx: %d, SBS array size: %d. Ignoring." % [_current_test_idx, _test_super_batch_sizes.size()])
		return

	var expected_sbs: int = _test_super_batch_sizes[_current_test_idx]
	# The job name now reflects n_cases being equal to sbs
	var expected_job_name_fragment = &"_Calib_NC%d_SBS%d" % [expected_sbs, expected_sbs]

	if not str(actual_job_name).contains(str(expected_job_name_fragment)):
		push_warning("MonteGodotCalibrator: all_jobs_completed signal for job '%s' does not match expected fragment '%s' for current test SBS %d. Job name expected NC and SBS to be %d. Ignoring." % [actual_job_name, expected_job_name_fragment, expected_sbs, expected_sbs])
		# This might indicate a logic error or concurrent use. For now, we just return and don't advance.
		return

	var time_taken_msec: int = -1
	var peak_mem: int = -1
	var error_str: String = ""

	if job_stats.has("error") and not job_stats["error"].is_empty():
		error_str = job_stats["error"]
		push_warning("MonteGodotCalibrator: Job '%s' (SBS: %d) reported failure in all_jobs_completed: %s" % [actual_job_name, expected_sbs, error_str])
	else:
		time_taken_msec = job_stats.get("total_execution_time_msec", -1)
		peak_mem = job_stats.get("peak_memory_bytes", -1) # This is in bytes.
		
		if time_taken_msec == -1 or peak_mem == -1:
			if error_str.is_empty(): # Only set this if no specific error from job_stats
				error_str = "Missing time or memory data in job_stats from all_jobs_completed."
			push_warning("MonteGodotCalibrator: Job '%s' (SBS: %d) - %s" % [actual_job_name, expected_sbs, error_str])
		else:
			calibration_update.emit("Super Batch Size %d: Time: %d ms, Peak Memory: %.2f MB (from all_jobs_completed)" % [expected_sbs, time_taken_msec, float(peak_mem) / (1024.0*1024.0)])

	var peak_mem_mb: float = -1.0
	if peak_mem > -1:
		peak_mem_mb = float(peak_mem) / (1024.0 * 1024.0)

	var total_physical_memory_bytes: int = 0
	var mem_info: Dictionary = OS.get_memory_info()
	if mem_info.has("physical"):
		total_physical_memory_bytes = mem_info["physical"]
	
	var peak_mem_percentage: float = -1.0
	if peak_mem > -1 and total_physical_memory_bytes > 0:
		peak_mem_percentage = (float(peak_mem) / total_physical_memory_bytes) * 100.0

	var result_entry: Dictionary = {
		"super_batch_size": expected_sbs,
		"time_msec": time_taken_msec,
		# "peak_mem_bytes": peak_mem, # Removed as per request
		"peak_mem_mb": peak_mem_mb,
		"peak_mem_percentage": peak_mem_percentage,
		"error": error_str
	}
	_results_array.append(result_entry)
	# Emitting the old calibration_job_completed signal for compatibility with any external listeners,
	# but it's no longer used for internal sequencing by this class.
	calibration_job_completed.emit(expected_sbs, time_taken_msec, peak_mem)

	_current_test_idx += 1
	_run_next_calibration_job() # Direct call to run the next job


func _finish_calibration() -> void:
	calibration_update.emit("Calibration finished. Results:")
	for res in _results_array:
		var error_msg = ""
		if not res["error"].is_empty():
			error_msg = " (Error: %s)" % res["error"]

		if (res["time_msec"] == -1 or res["peak_mem_mb"] == -1.0) and res["error"].is_empty(): # If no specific error but data is bad
			error_msg += " (Incomplete data received)"
		

		# Check for FAILED condition based on sentinel values, .is_nan() checks removed as per user request
		if res["time_msec"] == -1 or res["peak_mem_mb"] == -1.0:
			calibration_update.emit("  Super Batch Size: %d - FAILED%s" % [res["super_batch_size"], error_msg])
		else:
			var percentage_str: String = "N/A"
			if res["peak_mem_percentage"] > -1.0:
				percentage_str = "%.2f%% of total" % res["peak_mem_percentage"]
			
			calibration_update.emit("  Super Batch Size: %d - Time: %4d ms - Peak Memory: %6.2f MB (%s)%s" % \
				[res["super_batch_size"], res["time_msec"], res["peak_mem_mb"], percentage_str, error_msg])
	
	if _monte_godot_instance and _monte_godot_instance.job_completed.is_connected(_on_monte_godot_job_completed_individual_job_data_gathering):
		_monte_godot_instance.job_completed.disconnect(_on_monte_godot_job_completed_individual_job_data_gathering)
	if _monte_godot_instance and _monte_godot_instance.all_jobs_completed.is_connected(_on_monte_godot_all_jobs_completed_for_sequencing):
		_monte_godot_instance.all_jobs_completed.disconnect(_on_monte_godot_all_jobs_completed_for_sequencing)

	calibration_finished.emit(_results_array) 
