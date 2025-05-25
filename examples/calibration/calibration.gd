class_name Calibration extends Node

var calibrator: MonteGodotCalibrator
var _pi_job_functions_instance: PiJobFunctions

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

	# Results are also available in the 'results' array passed to this signal handler
	# The MonteGodotCalibrator already prints a summary.
	# For programmatic use, the caller can connect to calibrator.calibration_finished
	# on their calibrator instance if they need the raw results array directly.
