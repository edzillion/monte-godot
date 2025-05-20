# src/core/job_config.gd
class_name JobConfig extends Resource

## Stores the configuration for a single Monte Carlo simulation job.
## This includes simulation parameters and the core processing callables.

signal configuration_changed

@export var job_name: String = "DefaultJob":
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
	other_configs = p_other_configs


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
	if num_threads <= 0:
		# Consider allowing -1 for auto-detection of max threads later
		push_warning("JobConfig '%s': num_threads must be positive." % job_name)
		return false
	return true 