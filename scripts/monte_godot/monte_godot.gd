# res://scripts/monte_godot/monte_godot.gdd
class_name MonteGodot extends RefCounted

signal job_started(job_name: String)
## Emitted when an individual job configuration starts processing.

signal job_completed(job_name: String, job_results: Array[Case], job_stats: Dictionary, job_output_vars: Dictionary)
## Emitted when an individual job configuration finishes processing.
## `job_results` is an array of Case objects, now populated with output_values.
## `job_stats` is a Dictionary with timing and batching information.
## `job_output_vars` is a Dictionary mapping output variable StringNames to OutVar objects.

signal all_jobs_completed(all_aggregated_results: Dictionary)
## Emitted when all job configurations have been processed.
## `all_aggregated_results` is a Dictionary mapping job_name (String) to a sub-dictionary
## containing {"results": Array[Case], "stats": Dictionary, "output_vars": Dictionary}.

var _batch_processor: BatchProcessor
var _is_running_jobs: bool = false
var in_vars: Dictionary[StringName, InVar] = {}

var _job_configs: Array[JobConfig] = []
var _current_config: JobConfig = null

func _init() -> void:
	_batch_processor = BatchProcessor.new()


func run_simulations(p_job_configs: Array[JobConfig]) -> Variant:
	"""
	Asynchronously runs a series of Monte Carlo simulations based on the provided job configurations.
	This function is awaitable. The results are primarily delivered via signals.
	"""
	if _is_running_jobs:
		push_warning("MonteGodot: Already running simulations. New request ignored.")
		return FAILED

	if p_job_configs.is_empty():
		push_warning("MonteGodot: No job configurations provided.")
		all_jobs_completed.emit({})
		return OK

	_is_running_jobs = true
	var all_aggregated_results: Dictionary = {}

	_job_configs = p_job_configs

	for job_config: JobConfig in _job_configs:
		_current_config = job_config
		var overall_job_start_time_msec: int = Time.get_ticks_msec()
		var num_actual_super_batches: int = 0
		var current_job_name = _current_config.job_name

		if not _current_config.is_valid():
			push_warning("MonteGodot: Skipping invalid JobConfig: '%s'" % current_job_name)
			all_aggregated_results[current_job_name] = {"results": [], "stats": {"error": "Skipped - Invalid Config"}}
			job_completed.emit(current_job_name, [], {"error": "Invalid Config"}, {})
			continue

		# 0. Initialize Input Variables

		# Clear previous job's vars if any, to ensure fresh state for current job
		self.in_vars.clear()

		var temp_in_var_instances: Array[InVar] = []
		for i: int in range(_current_config.in_vars.size()):
			var in_var_resource: InVar = _current_config.in_vars[i]
			if not in_var_resource is InVar:
				push_error("Job '%s': Invalid InVar resource for '%s'. Skipping." % [_current_config.job_name, in_var_resource.name])
				continue

			# It's better to duplicate the resource if it might be shared or modified by other jobs concurrently
			# For now, assuming direct use is fine if jobs run sequentially or resources are unique per job config.
			# var in_var: InVar = in_var_resource.duplicate() # Optional: consider if duplication is needed.
			var in_var: InVar = in_var_resource
			in_var.ndraws = _current_config.n_cases			
			in_var.var_idx = i # Use the loop index as var_idx for consistent ordering
			temp_in_var_instances.append(in_var)
			self.in_vars[in_var.name] = in_var # Storing by name

		# Generate and distribute percentiles only if there are input variables and cases
		if not temp_in_var_instances.is_empty() and _current_config.n_cases > 0:
			var num_input_vars: int = temp_in_var_instances.size()
			# Assuming JobConfig has a 'seed' property or we manage seeding appropriately
			var job_seed: int = _current_config.seed if _current_config.has_method("get_seed") else 0 
			
			# Assuming StatMath and StatMath.SamplingGen are available as per user instruction.
			# No explicit check for their existence will be performed here.

			for var_idx: int in range(num_input_vars):
				var current_in_var: InVar = temp_in_var_instances[var_idx]
				
				# Get the sampling method directly from the InVar instance.
				# It's already of type StatMath.SamplingGen.SamplingMethod due to changes in InVar.gd.
				var sampling_method_to_use: StatMath.SamplingGen.SamplingMethod = current_in_var.sample_method

				# Derive a unique seed for this variable's percentile generation to ensure independence if desired
				var per_var_seed: int = job_seed + current_in_var.var_idx + 1 # Simple way to vary seed per var
				
				var var_percentiles: Array[float] = StatMath.SamplingGen.generate_samples_1d(_current_config.n_cases, sampling_method_to_use, per_var_seed)

				if var_percentiles.is_empty() and _current_config.n_cases > 0:
					push_error("MonteGodot: Job '%s', InVar '%s' (%d) - Failed to generate percentiles using StatMath.SamplingGen." % [current_job_name, current_in_var.name, current_in_var.var_idx])
					# Decide how to handle this: skip InVar, skip job, or use fallback?
					# For now, let InVar get an empty list, it will warn/error downstream.
					current_in_var.percentiles = []
				else:
					current_in_var.percentiles = var_percentiles
				
				current_in_var.generate_all_values() # This pre-calculates _drawn_values in InVar

		job_started.emit(current_job_name)
		print("MonteGodot: Starting job '%s' (n_cases: %d, threads: %d, super_batch_size: %d, inner_batch_size: %d)." %
			[current_job_name, _current_config.n_cases, _current_config.num_threads, _current_config.super_batch_size, _current_config.inner_batch_size])

		# 1. Generate All Cases for the Job (once)
		var all_cases_for_job: Array[Case] = []
		if _current_config.n_cases > 0 and self.in_vars.is_empty() and not _current_config.in_vars.is_empty():
			push_warning("MonteGodot: Job '%s' has n_cases > 0 but no InVars were successfully initialized. Cannot generate cases." % current_job_name)
			# This situation might arise if all InVar resources in the config were invalid.
			# Error handling for this scenario (e.g., skipping the job) is already partially covered by the percentile generation checks.

		for i: int in range(_current_config.n_cases):
			var case_obj: Case = Case.new(i) # i is the case_idx
			
			# Iterate through the initialized InVar instances for this job
			# We need to ensure they are added in the order of their var_idx for consistency
			# if downstream code relies on input_value index.
			var sorted_in_vars: Array[InVar] = get_input_vars_typed()
			# Sort InVars by their var_idx to ensure deterministic order of InVals in Case
			sorted_in_vars.sort_custom(func(a: InVar, b: InVar): return a.var_idx < b.var_idx)

			for in_var_instance: InVar in sorted_in_vars:
				# Get the specific InVal for this InVar and this case_idx (i)
				var specific_in_val: InVal = in_var_instance.get_value(i) 
				case_obj.add_input_value(specific_in_val)
			
			all_cases_for_job.append(case_obj)

		if all_cases_for_job.is_empty() and _current_config.n_cases > 0:
			push_error("MonteGodot: Job '%s' - Failed to generate cases." % current_job_name)
			all_aggregated_results[current_job_name] = {"results": [], "stats": {"error": "Case generation failed"}}
			job_completed.emit(current_job_name, [], {"error": "Case generation failed"}, {})
			continue

		var effective_super_batch_size: int = _current_config.super_batch_size
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

			print("MonteGodot: Job '%s', Super-batch %d/%d (cases %d-%d) starting." %
				[current_job_name, sb_idx + 1, num_actual_super_batches, super_batch_start_idx, super_batch_end_idx -1])

			# 2a. Preprocessing Stage for Super-batch
			var preprocessed_cases: Array[Case] # Stores the arrays of cases for the batch processor
			for case_obj: Case in current_super_batch_cases:
				var returned_case_obj: Case = preprocess_case(case_obj)
				preprocessed_cases.append(returned_case_obj)
			print("MonteGodot: Job '%s', Super-batch %d - Preprocessing complete (%d tasks prepared for run stage)." % [current_job_name, sb_idx + 1, preprocessed_cases.size()])

			var batch_processor_started: bool = _batch_processor.process(
				preprocessed_cases, # Pass the collected arrays of arguments
				run_case,
				_current_config.inner_batch_size,
				_current_config.num_threads
			)
			#generate_out_vars(_current_config.inner_batch_size)

			if not batch_processor_started:
				push_error("MonteGodot: Job '%s', Super-batch %d - Failed to start BatchProcessor." % [current_job_name, sb_idx + 1])
				# How to handle this error? For now, log and this SB might be skipped for results collection
				# Potentially add error markers to cases or job_stats
				continue # Skip to next super-batch
			
			print("MonteGodot: Job '%s', Super-batch %d - BatchProcessor initiated. Waiting..." % [current_job_name, sb_idx + 1])
			var batch_run_results_for_sb: Array = await _batch_processor.processing_complete
			print("MonteGodot: Job '%s', Super-batch %d - BatchProcessor completed (%d results)." % [current_job_name, sb_idx + 1, batch_run_results_for_sb.size()])

			# 4a. Postprocessing Stage for Super-batch
			if batch_run_results_for_sb.size() != current_super_batch_cases.size():
				push_warning("MonteGodot: Job '%s', Super-batch %d - Mismatch in case count (%d) and batch results (%d). Results might be misaligned." %
					[current_job_name, sb_idx + 1, current_super_batch_cases.size(), batch_run_results_for_sb.size()])
				# Continue processing with potentially misaligned data, or handle error more strictly?
				# For now, we'll proceed but this warning is critical.

			for i: int in range(current_super_batch_cases.size()):
				var original_case_obj: Case = current_super_batch_cases[i]
				
				if i < batch_run_results_for_sb.size() and batch_run_results_for_sb[i] is Case:
					var processed_case_data: Case = batch_run_results_for_sb[i]
					# Transfer results from the processed_case_data (from BatchProcessor) 
					# to the original_case_obj.
					original_case_obj.run_output = processed_case_data.run_output
					original_case_obj.start_time_msec = processed_case_data.start_time_msec
					original_case_obj.end_time_msec = processed_case_data.end_time_msec
					original_case_obj.runtime_msec = processed_case_data.runtime_msec
					# Any other fields set by run_case should be transferred here if necessary.
					# Note: sim_input_args was already on original_case_obj from its own preprocess_case call.
				else:
					# Handle missing or mismatched result for this case
					push_warning("MonteGodot: Job '%s', Super-batch %d, Case index %d - Missing or invalid result from BatchProcessor. Postprocessing may use stale/no run_output." % [current_job_name, sb_idx + 1, original_case_obj.id if original_case_obj else i])
					# original_case_obj.run_output might remain empty or from a previous state.

				# Now call postprocess_case on the original_case_obj, which now has the correct run_output.
				var postprocessed_original_case: Case = postprocess_case(original_case_obj)
				collected_processed_cases.append(postprocessed_original_case) 
				# Assuming postprocess_case modifies original_case_obj and returns it, 
				# or that collected_processed_cases should store these.
				# Current postprocess_case adds OutVals to the passed Case and returns it.
			
			print("MonteGodot: Job '%s', Super-batch %d - Postprocessing complete." % [current_job_name, sb_idx + 1])

		# End of super-batches loop for the current job
		var overall_job_duration_msec: int = Time.get_ticks_msec() - overall_job_start_time_msec

		var job_stats: Dictionary = {
			"total_execution_time_msec": overall_job_duration_msec,
			"num_super_batches": num_actual_super_batches,
			# TODO: Correctly calculate and store actual average times per SB if needed
			"avg_preprocess_time_per_super_batch_msec": 0.0, 
			"avg_run_time_per_super_batch_msec": 0.0,
			"avg_postprocess_time_per_super_batch_msec": 0.0,
			"cases_processed": collected_processed_cases.size()
		}

		# --- Create OutVar instances for the completed job --- 
		var current_job_out_vars: Dictionary = {}
		if not collected_processed_cases.is_empty():
			var unique_out_val_names: Dictionary = {} # Use as a set: StringName -> bool
			for case_obj: Case in collected_processed_cases:
				var case_out_vals: Array[OutVal] = case_obj.get_output_values()
				for ov: OutVal in case_out_vals:
					unique_out_val_names[ov.name] = true

			for out_var_name_sn: StringName in unique_out_val_names.keys():
				var all_raw_vals_for_name: Array = []
				# Placeholder for first_case_is_median logic for OutVars.
				# This might come from JobConfig or be a global setting.
				var first_is_median_for_outvar: bool = _current_config.first_case_is_median if _current_config else false
				var valmap_override_for_name: Dictionary = {} # Default to empty, OutVar can auto-gen if needed

				for case_obj: Case in collected_processed_cases:
					var case_out_vals: Array[OutVal] = case_obj.get_output_values()
					var found_in_case: bool = false
					for ov: OutVal in case_out_vals:
						if ov.name == out_var_name_sn:
							all_raw_vals_for_name.append(ov.get_raw_data())
							found_in_case = true
							break
					if not found_in_case:
						all_raw_vals_for_name.append(null) # Append null if specific OutVal not found
						# Consider if a warning is needed here, or if this is expected behavior
						# push_warning("MonteGodot: Job '%s', Case %d missing OutVal for '%s'. Appending null." % [current_job_name, case_obj.id, out_var_name_sn])
				
				if not all_raw_vals_for_name.is_empty():
					var new_out_var: OutVar = OutVar.new(
						out_var_name_sn,
						all_raw_vals_for_name,
						valmap_override_for_name,
						first_is_median_for_outvar
						# datasource could be passed if relevant
					)
					current_job_out_vars[out_var_name_sn] = new_out_var
				# else: No values collected, OutVar not created for this name.

		job_stats["output_variables_summary"] = current_job_out_vars # Adding the OutVars to stats for now
		# -----------------------------------------------------

		print("MonteGodot: Job '%s' completed. Total time: %.2f sec." % [current_job_name, float(overall_job_duration_msec) / 1000.0])

		all_aggregated_results[current_job_name] = {"results": collected_processed_cases, "stats": job_stats, "output_vars": current_job_out_vars}
		job_completed.emit(current_job_name, collected_processed_cases, job_stats, current_job_out_vars)

	_is_running_jobs = false
	all_jobs_completed.emit(all_aggregated_results)
	print("MonteGodot: All jobs completed.")
	return OK 

func get_input_vars_typed() -> Array[InVar]:
	var typed_in_vars: Array[InVar] = []
	var values_array: Array = self.in_vars.values()
	for val in values_array:
		if val is InVar:
			typed_in_vars.append(val)
		else:
			push_error("MonteGodot: Non-InVar type found in self.in_vars. This should not happen. Value: %s" % str(val))
	return typed_in_vars

func preprocess_case(case_obj: Case) -> Case:
	case_obj.stage = Case.CaseStage.PREPROCESS

	case_obj.sim_input_args = _current_config.preprocess_callable.call(case_obj)
	
	return case_obj

func run_case(case: Case) -> Case:
	case.stage = Case.CaseStage.RUN
	case.start_time_msec = Time.get_ticks_msec()
	var case_args: Array[int] = case.sim_input_args
	case.run_output = _current_config.run_callable.call(case_args)
	case.end_time_msec = Time.get_ticks_msec()
	case.runtime_msec = case.end_time_msec - case.start_time_msec	

	return case

func postprocess_case(case: Case) -> Case:
	case.stage = Case.CaseStage.POSTPROCESS
	# case.run_output directly contains the raw output values from the run_callable
	# E.g., if run_callable returns [true, 0.5, 0.3], then case.run_output is that array.
	var raw_run_outputs: Array = case.run_output 
	_current_config.postprocess_callable.call(case, raw_run_outputs) # Pass the case and the raw outputs
	
	return case

func final_postprocess(all_results: Dictionary) -> void:
	pass
