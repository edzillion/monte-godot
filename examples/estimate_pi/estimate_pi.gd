# res://examples/estimate_pi/estimate_pi.gd
class_name EstimatePi extends Node

## Estimates the value of pi using Monte Carlo integration.
## 
## This example demonstrates how to use MonteGodot to estimate the value of pi.
## It shows how to define a job configuration, preprocess and run functions,
## and postprocess the results.
## 
## The job configuration is defined in estimate_pi_job.tres.
## The preprocess function is defined in _estimate_pi_preprocess.
## The run function is defined in _estimate_pi_run.
## The postprocess function is defined in _estimate_pi_postprocess.
## 
## The final post-process function is defined in _final_post_process.

var _rng: RandomNumberGenerator

const TOTAL_CASES: int = 10_000_000 # Reduced for quicker testing of stats, was 100M
const SUPER_BATCH_SIZE: int = 1_000_000 # Was 5M
const INNER_BATCH_SIZE: int = 100_000 # Batch size for BatchProcessor's internal threading

var monte_godot: MonteGodot
var estimate_pi_job = preload("res://examples/estimate_pi/estimate_pi_job.tres")

func _ready():
	monte_godot = MonteGodot.new()
	monte_godot.all_jobs_completed.connect(_final_post_process)
	
	_rng = RandomNumberGenerator.new()
	var num_super_batches: int = int(ceil(float(TOTAL_CASES) / SUPER_BATCH_SIZE))
	print("Starting Pi estimation for %d total cases, in %d super-batches of size up to %d." % [TOTAL_CASES, num_super_batches, SUPER_BATCH_SIZE])
	
	
	_start_simulation()

func _start_simulation():
	estimate_pi_job.preprocess_callable = _estimate_pi_preprocess
	estimate_pi_job.run_callable = _estimate_pi_run
	estimate_pi_job.postprocess_callable = _estimate_pi_postprocess
	monte_godot.run_simulations([estimate_pi_job])
	

func _estimate_pi_preprocess(case:Case) -> Array:			
	return [case.get_input_value(0), case.get_input_value(1)]


func _estimate_pi_run(case_args: Array) -> Array:
	var x: float = case_args[0]
	var y: float = case_args[1]
	var is_inside_circle: bool = (x*x + y*y) <= 1.0
	return [is_inside_circle, x, y]


func _estimate_pi_postprocess(case_data: Case, run_output: Dictionary) -> void:
	#	current_pi_estimate = 4.0 * _total_inside_circle / _total_processed_count
	case_data.add_output_value(run_output.is_inside)


func _final_post_process(results):
	
	for job_name in results.keys():
		var job = results[job_name]
		print("Final results for: ", job_name)
		var cases = job.results
		var total_cases: int = cases.size()
		var total_inside_circle: int = 0
		for i in range(total_cases):
			if cases[i].output_values[0]:
				total_inside_circle += 1					

		var final_pi_estimate: float = 4.0 * total_inside_circle / total_cases
		print("Final Pi estimate after %d total processed cases: %f" % [total_cases, final_pi_estimate])
		print("Target total cases: %d" % TOTAL_CASES)
		print("------------------------------------")
		print("--- Performance Statistics ---")

		if job.stats and not job.stats.is_empty() and not job.stats.has("error"): 
			var stats_dict: Dictionary = job.stats

			print("Total cases processed: %d" % stats_dict.get("cases_processed", 0))
			print("Number of super-batches: %d" % stats_dict.get("num_super_batches", 0))
			print("Total execution time (orchestrator timer): %.3f seconds" % (stats_dict.get("total_execution_time_msec", 0) / 1000.0))

			var total_preprocess_msec: int = stats_dict.get("total_preprocess_time_msec", 0)
			var total_run_msec: int = stats_dict.get("total_run_time_msec", 0)
			var total_postprocess_msec: int = stats_dict.get("total_postprocess_time_msec", 0)
			
			var sum_of_all_stages_msec: int = total_preprocess_msec + \
											  total_run_msec + \
											  total_postprocess_msec
			print("Total time (sum of job stages): %.3f seconds" % (sum_of_all_stages_msec / 1000.0))
			
			var num_sb: int = stats_dict.get("num_super_batches", 0)
			if num_sb > 0:
				print("Average preprocess time per super-batch: %.3f ms" % stats_dict.get("avg_preprocess_time_per_super_batch_msec", 0.0))
				print("Average run time per super-batch: %.3f ms" % stats_dict.get("avg_run_time_per_super_batch_msec", 0.0))
				print("Average postprocess time per super-batch: %.3f ms" % stats_dict.get("avg_postprocess_time_per_super_batch_msec", 0.0))
			elif stats_dict.get("cases_processed", 0) > 0:
				print("Super-batch averages are not applicable (e.g., total cases less than one super-batch or stats were zeroed).")
			else:
				print("No performance stats recorded for super-batches (no cases processed or error during processing).")
		
		elif job.stats and job.stats.has("error"):
			print("Job encountered an error: %s" % job.stats.get("error", "Unknown error description."))
		elif TOTAL_CASES > 0:
			print("No valid performance statistics were recorded for this job, or an error occurred before stats could be gathered.")
		
		print("------------------------------------")
		get_tree().quit()
