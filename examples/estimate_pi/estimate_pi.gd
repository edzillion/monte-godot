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
	

func _estimate_pi_preprocess(case:Case) -> Array[float]:
	var inval_x: InVal = case.get_input_value(0)
	var inval_y: InVal = case.get_input_value(1)
	return [inval_x.get_value(), inval_y.get_value()]


func _estimate_pi_run(case_args: Array) -> Array[bool]:
	var x: float = case_args[0]
	var y: float = case_args[1]
	var is_inside_circle:bool = (x*x + y*y) <= 1.0
	return [is_inside_circle]    


func _estimate_pi_postprocess(case_obj: Case, is_in_circle: Array[bool]) -> void: # Expects bool
	var out_val_is_inside: OutVal = OutVal.new(&"is_inside", case_obj.id, is_in_circle[0])
	case_obj.add_output_value(out_val_is_inside)
	

func _final_post_process(all_job_results: Dictionary) -> void:
	print("--- Monte Carlo Simulation: Final Results ---")

	for job_name: StringName in all_job_results.keys():
		var job_data: Dictionary = all_job_results[job_name]
		print("--- Job: %s ---" % job_name)

		var output_vars: Dictionary = job_data.get("output_vars", {}) # StringName -> OutVar

		# --- Pi Estimation Specific Logic ---
		if output_vars.has(&"is_inside"):
			var is_inside_out_var: OutVar = output_vars[&"is_inside"]
			var is_inside_values: Array = is_inside_out_var.get_all_raw_values()
			var is_inside_count: int = is_inside_values.size()
			var total_inside_circle: int = 0
			for val_raw in is_inside_values:
				if val_raw == true:
					total_inside_circle += 1
			
			if is_inside_count > 0:
				var final_pi_estimate: float = 4.0 * total_inside_circle / is_inside_count
				print("Final Pi estimate: %f (from %d / %d)" % [final_pi_estimate, total_inside_circle, is_inside_count])
		
		# --- Print Statistics for All Output Variables ---
		if not output_vars.is_empty():
			print("-- Output Variable Statistics --")
			for var_name: StringName in output_vars.keys():
				var out_var_instance: OutVar = output_vars[var_name]
				var ov_stats: Dictionary = out_var_instance.calculate_stats() # Uses EZSTATS.all()
				print("  Variable: '%s'" % var_name)
				for stat_key in ov_stats.keys():
					print("    %s : %s" % [str(stat_key), str(ov_stats[stat_key])])
		
		# --- Orchestrator Performance ---
		var orchestrator_stats: Dictionary = job_data.get("stats", {})
		if orchestrator_stats.has("total_execution_time_msec"):
			print("-- Orchestrator Performance --")
			print("  Total job execution time: %.3f seconds" % (orchestrator_stats.get("total_execution_time_msec", 0) / 1000.0))

		print("------------------------------------")

	get_tree().quit()
