# res://scripts/job_config/job_config.gd
class_name JobConfig extends Resource

## Stores the configuration for a single Monte Carlo simulation job.
## This includes simulation parameters and the core processing callables.

signal configuration_changed

@export var job_name: StringName = &"UnnamedJob":
	set(value):
		if job_name != value:
			job_name = value
			configuration_changed.emit()
## A descriptive name for this job, used for identifying results.

@export_group("Simulation Parameters")
@export var n_cases: int = 1000:
	set(value):
		if n_cases != value:
			n_cases = value
			configuration_changed.emit()
## The total number of random cases to run for this job.

@export var num_threads: int = 4:
	set(value):
		if num_threads != value:
			num_threads = value
			configuration_changed.emit()
## Number of threads to use for processing this job.
## A value of 0 or -1 might indicate using WorkerThreadPool.get_max_threads().


## If true, the first case generated will represent the median values of all InVars.
@export var first_case_is_median: bool = false:
	set(value):
		if first_case_is_median != value:
			first_case_is_median = value
			configuration_changed.emit()

## If true, the case data will be saved to a file.
@export var save_case_data: bool = false:
	set(value)	:
		if save_case_data != value:
			save_case_data = value
			configuration_changed.emit()



@export_group("Batching")
@export var super_batch_size: int = 100:
	set(value):
		if super_batch_size != value:
			super_batch_size = value
			configuration_changed.emit()
## Number of cases grouped into a "super batch". Relevant if your processing involves multiple levels of batching.

@export var inner_batch_size: int = 10:
	set(value):
		if inner_batch_size != value:
			inner_batch_size = value
			configuration_changed.emit()
## Number of cases grouped into an "inner batch" within a super batch.

@export_group("Variables")
@export var in_vars: Array[InVar] = []

@export_group("User Callables")
## These callables define the core logic of the simulation.
## They need to be set programmatically.

var preprocess_callable: Callable:
	set(value):
		if preprocess_callable != value:
			preprocess_callable = value
			configuration_changed.emit()
## Callable for the preprocessing step. Expected signature: func(case_data: Case) -> Variant

var run_callable: Callable:
	set(value):
		if run_callable != value:
			run_callable = value
			configuration_changed.emit()
## Callable for the main run step. Expected signature: func(processed_input: Variant) -> Variant

var postprocess_callable: Callable:
	set(value):
		if postprocess_callable != value:
			postprocess_callable = value
			configuration_changed.emit()
## Callable for the postprocessing step. Expected signature: func(case_data: Case, run_output: Variant) -> void

@export_group("Advanced")
@export var other_configs: Dictionary = {}:
	set(value):
		if other_configs != value:
			other_configs = value
			configuration_changed.emit()
## A dictionary for any other job-specific configurations (e.g., input variable distributions).


func _init(
	p_job_name: String = "DefaultJob",
	p_n_cases: int = 1000,
	p_num_threads: int = 4,
	p_super_batch_size: int = 100,
	p_inner_batch_size: int = 10,
	p_preprocess: Callable = Callable(),
	p_run: Callable = Callable(),
	p_postprocess: Callable = Callable(),
	p_in_vars: Array[InVar] = [],
	p_other_configs: Dictionary = {}
) -> void:
	job_name = p_job_name
	n_cases = p_n_cases
	num_threads = p_num_threads
	super_batch_size = p_super_batch_size
	inner_batch_size = p_inner_batch_size
	preprocess_callable = p_preprocess
	run_callable = p_run
	postprocess_callable = p_postprocess
	in_vars = p_in_vars
	other_configs = p_other_configs


func get_configured_invar_by_name(variable_name: StringName) -> InVar:
	## Retrieves a configured InVar instance for a given variable name.
	## Returns null if the variable_name is not found or if the configuration is invalid.
	for in_var in in_vars:
		if in_var.get("name") == variable_name:			
			if not in_var.get("distribution"):
				push_warning("JobConfig ('%s'): No distribution source for variable '%s'." % [job_name, variable_name])
				return null

			var new_in_var: InVar = in_var.duplicate()
			
			var num_map_override: Dictionary = in_var.get("num_map")
			if not num_map_override.is_empty():
				new_in_var.num_map = num_map_override.duplicate(true)
			
			# The seed from var_config_dict.get("seed") is not directly applied to InVar.
			# It needs to be handled by the SimManager or Case generation logic.
			return new_in_var
			
	push_warning("JobConfig ('%s'): Input variable configuration for '%s' not found." % [job_name, variable_name])
	return null


func is_valid() -> bool:
	if not preprocess_callable.is_valid():
		push_warning("JobConfig '%s': preprocess_callable is not set." % job_name)
		return false
	if not run_callable.is_valid():
		push_warning("JobConfig '%s': run_callable is not set." % job_name)
		return false
	if not postprocess_callable.is_valid():
		push_warning("JobConfig '%s': postprocess_callable is not set." % job_name)
		return false
	if n_cases <= 0:
		push_warning("JobConfig '%s': n_cases must be positive." % job_name)
		return false
	return true 
