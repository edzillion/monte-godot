# src/core/monte_carlo.gd
class_name MonteCarlo extends RefCounted

signal job_started(job_name: String)
## Emitted when an individual job configuration starts processing.

signal job_completed(job_name: String, job_results: Array[Case], job_stats: Dictionary)
## Emitted when an individual job configuration finishes processing.
## `job_results` is an array of Case objects, now populated with output_values.
## `job_stats` is a Dictionary with timing and batching information.

signal all_jobs_completed(all_aggregated_results: Dictionary)
## Emitted when all job configurations have been processed.
## `all_aggregated_results` is a Dictionary mapping job_name (String) to a sub-dictionary
## containing {"results": Array[Case], "stats": Dictionary}.

var _batch_processor: BatchProcessor
var _is_running_jobs: bool = false


func _init() -> void:
	_batch_processor = BatchProcessor.new()


func run_simulations(p_job_configs: Array[JobConfig]) -> Variant:
	"""
	Asynchronously runs a series of Monte Carlo simulations based on the provided job configurations.
	This function is awaitable. The results are primarily delivered via signals.
	"""
	if _is_running_jobs:
		push_warning("MonteCarloOrchestrator: Already running simulations. New request ignored.")
		return FAILED

	if p_job_configs.is_empty():
		push_warning("MonteCarloOrchestrator: No job configurations provided.")
		all_jobs_completed.emit({})
		return OK

	_is_running_jobs = true
	var all_aggregated_results: Dictionary = {}

	for job_config: JobConfig in p_job_configs:
		var overall_job_start_time_msec: int = Time.get_ticks_msec()
		var total_job_preprocess_time_msec: int = 0
		var total_job_run_time_msec: int = 0
		var total_job_postprocess_time_msec: int = 0
		var num_actual_super_batches: int = 0

		var current_job_name: String = "UnnamedJob"
		if job_config:
			current_job_name = job_config.job_name
		else:
			push_warning("MonteCarloOrchestrator: Encountered a null JobConfig. Skipping.")
			all_aggregated_results[current_job_name] = {"results": [], "stats": {"error": "Skipped - Null JobConfig"}}
			continue

		if not job_config.is_valid():
			push_warning("MonteCarloOrchestrator: Skipping invalid JobConfig: '%s'" % current_job_name)
			all_aggregated_results[current_job_name] = {"results": [], "stats": {"error": "Skipped - Invalid Config"}}
			job_completed.emit(current_job_name, [], {"error": "Invalid Config"})
			continue

		job_started.emit(current_job_name)
		print("MonteCarloOrchestrator: Starting job '%s' (n_cases: %d, threads: %d, super_batch_size: %d, inner_batch_size: %d)." %
			[current_job_name, job_config.n_cases, job_config.num_threads, job_config.super_batch_size, job_config.inner_batch_size])

		# 1. Generate All Cases for the Job (once)
		var all_cases_for_job: Array[Case] = []
		for i: int in range(job_config.n_cases):
			var case_obj: Case = Case.new(i)
			case_obj.add_input_value(&"x", randf_range(-1.0, 1.0))
			case_obj.add_input_value(&"y", randf_range(-1.0, 1.0))
			all_cases_for_job.append(case_obj)

		if all_cases_for_job.is_empty() and job_config.n_cases > 0:
			push_error("MonteCarloOrchestrator: Job '%s' - Failed to generate cases." % current_job_name)
			all_aggregated_results[current_job_name] = {"results": [], "stats": {"error": "Case generation failed"}}
			job_completed.emit(current_job_name, [], {"error": "Case generation failed"})
			continue

		var effective_super_batch_size: int = job_config.super_batch_size
		if effective_super_batch_size <= 0 or effective_super_batch_size > all_cases_for_job.size():
			effective_super_batch_size = all_cases_for_job.size()

		num_actual_super_batches = 0
		if not all_cases_for_job.is_empty(): # only calculate if there are cases
			num_actual_super_batches = ceil(float(all_cases_for_job.size()) / effective_super_batch_size) if effective_super_batch_size > 0 else 1

		var collected_processed_cases: Array[Case] = [] # Cases are modified in-place, this collects references

		for sb_idx: int in range(num_actual_super_batches):
			var super_batch_start_idx: int = sb_idx * effective_super_batch_size
			var super_batch_end_idx: int = min(super_batch_start_idx + effective_super_batch_size, all_cases_for_job.size())
			var current_super_batch_cases: Array[Case] = all_cases_for_job.slice(super_batch_start_idx, super_batch_end_idx)

			if current_super_batch_cases.is_empty():
				continue

			print("MonteCarloOrchestrator: Job '%s', Super-batch %d/%d (cases %d-%d) starting." %
				[current_job_name, sb_idx + 1, num_actual_super_batches, super_batch_start_idx, super_batch_end_idx -1])

			# 2a. Preprocessing Stage for Super-batch
			var sb_preprocess_start_msec: int = Time.get_ticks_msec()
			var preprocessed_tasks_for_sb: Array = []
			for case_obj: Case in current_super_batch_cases:
				var preprocessed_data: Variant = job_config.preprocess_callable.call(case_obj)
				preprocessed_tasks_for_sb.append(preprocessed_data)
			total_job_preprocess_time_msec += Time.get_ticks_msec() - sb_preprocess_start_msec
			print("MonteCarloOrchestrator: Job '%s', Super-batch %d - Preprocessing complete (%d tasks)." % [current_job_name, sb_idx + 1, preprocessed_tasks_for_sb.size()])

			# 3a. Run with BatchProcessor for Super-batch
			var sb_run_start_msec: int = Time.get_ticks_msec()
			var batch_processor_started: bool = _batch_processor.process(
				preprocessed_tasks_for_sb,
				job_config.run_callable,
				job_config.inner_batch_size,
				job_config.num_threads
			)

			if not batch_processor_started:
				push_error("MonteCarloOrchestrator: Job '%s', Super-batch %d - Failed to start BatchProcessor." % [current_job_name, sb_idx + 1])
				# How to handle this error? For now, log and this SB might be skipped for results collection
				# Potentially add error markers to cases or job_stats
				continue # Skip to next super-batch
			
			print("MonteCarloOrchestrator: Job '%s', Super-batch %d - BatchProcessor initiated. Waiting..." % [current_job_name, sb_idx + 1])
			var batch_run_results_for_sb: Array = await _batch_processor.processing_complete
			total_job_run_time_msec += Time.get_ticks_msec() - sb_run_start_msec
			print("MonteCarloOrchestrator: Job '%s', Super-batch %d - BatchProcessor completed (%d results)." % [current_job_name, sb_idx + 1, batch_run_results_for_sb.size()])

			# 4a. Postprocessing Stage for Super-batch
			var sb_postprocess_start_msec: int = Time.get_ticks_msec()
			if batch_run_results_for_sb.size() != current_super_batch_cases.size():
				push_warning("MonteCarloOrchestrator: Job '%s', Super-batch %d - Mismatch in case count (%d) and batch results (%d)." %
					[current_job_name, sb_idx + 1, current_super_batch_cases.size(), batch_run_results_for_sb.size()])

			for i: int in range(current_super_batch_cases.size()):
				if i < batch_run_results_for_sb.size():
					var case_obj: Case = current_super_batch_cases[i]
					var run_output: Variant = batch_run_results_for_sb[i]
					job_config.postprocess_callable.call(case_obj, run_output)
				else:
					push_warning("MonteCarloOrchestrator: Job '%s', Super-batch %d - Missing batch result for case index %d (ID %s)." % [current_job_name, sb_idx + 1, i, current_super_batch_cases[i].id])
			total_job_postprocess_time_msec += Time.get_ticks_msec() - sb_postprocess_start_msec
			print("MonteCarloOrchestrator: Job '%s', Super-batch %d - Postprocessing complete." % [current_job_name, sb_idx + 1])
			
			collected_processed_cases.append_array(current_super_batch_cases)

		# End of super-batches loop for the current job
		var overall_job_duration_msec: int = Time.get_ticks_msec() - overall_job_start_time_msec

		var avg_preprocess_sb_msec: float = 0.0
		var avg_run_sb_msec: float = 0.0
		var avg_postprocess_sb_msec: float = 0.0

		if num_actual_super_batches > 0:
			avg_preprocess_sb_msec = float(total_job_preprocess_time_msec) / num_actual_super_batches
			avg_run_sb_msec = float(total_job_run_time_msec) / num_actual_super_batches
			avg_postprocess_sb_msec = float(total_job_postprocess_time_msec) / num_actual_super_batches

		var job_stats: Dictionary = {
			"total_execution_time_msec": overall_job_duration_msec,
			"total_preprocess_time_msec": total_job_preprocess_time_msec,
			"total_run_time_msec": total_job_run_time_msec,
			"total_postprocess_time_msec": total_job_postprocess_time_msec,
			"num_super_batches": num_actual_super_batches,
			"avg_preprocess_time_per_super_batch_msec": avg_preprocess_sb_msec,
			"avg_run_time_per_super_batch_msec": avg_run_sb_msec,
			"avg_postprocess_time_per_super_batch_msec": avg_postprocess_sb_msec,
			"cases_processed": collected_processed_cases.size()
		}

		print("MonteCarloOrchestrator: Job '%s' completed. Total time: %.2f sec." % [current_job_name, float(overall_job_duration_msec) / 1000.0])
		# For more detailed stats, print job_stats dictionary here if needed
		# print("Job Stats for '%s': %s" % [current_job_name, job_stats])

		all_aggregated_results[current_job_name] = {"results": collected_processed_cases, "stats": job_stats}
		job_completed.emit(current_job_name, collected_processed_cases, job_stats)

	_is_running_jobs = false
	all_jobs_completed.emit(all_aggregated_results)
	print("MonteCarloOrchestrator: All jobs completed.")
	return OK 
