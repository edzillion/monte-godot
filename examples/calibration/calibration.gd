class_name Calibration extends Node

var calibrator: MonteGodotCalibrator

const DEFAULT_JOB_CONFIG_PATH_PI_EXAMPLE: String = "res://examples/estimate_pi/estimate_pi_job.tres"

# Example Pi estimation functions for the default Pi example job.
# If a different JobConfig is used, its callables must be set appropriately by the caller.
func _estimate_pi_preprocess(case:Case) -> Array:			
	return [case.get_input_value(0), case.get_input_value(1)]


func _estimate_pi_run(case_args: Array) -> Array[bool]:
	var x: float = case_args[0]
	var y: float = case_args[1]
	var is_inside_circle:bool = (x*x + y*y) <= 1.0
	return [is_inside_circle]    


func _estimate_pi_postprocess(case_obj: Case, is_in_circle: Array[bool]) -> void: # Expects bool
	var out_val_is_inside: OutVal = OutVal.new(&"is_inside", case_obj.id, is_in_circle[0])
	case_obj.add_output_value(out_val_is_inside)
	
	

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
		base_job_config.preprocess_callable = Callable(self, "_pi_preprocess")
		base_job_config.run_callable = Callable(self, "_pi_run")
		base_job_config.postprocess_callable = Callable(self, "_pi_postprocess")
		print("Info: Using placeholder Pi callables for default estimate_pi_job.tres.")
	
	# It is assumed that any other JobConfig passed will have its callables already set
	# or set by its own script if it's a custom JobConfig class instance.

	if not base_job_config.is_valid():
		printerr("Calibration Error: Loaded JobConfig is invalid after attempting to set callables. Path: %s" % p_job_config_path)
		push_warning("Ensure callables (preprocess, run, postprocess) are set and other parameters are correct in the JobConfig.")
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
	# Results are also available in the 'results' array passed to this signal handler
	# The MonteGodotCalibrator already prints a summary.
	# For programmatic use, the caller can connect to calibrator.calibration_finished
	# on their calibrator instance if they need the raw results array directly.
