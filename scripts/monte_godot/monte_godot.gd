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

		# Temporary debug print for n_cases used by MonteGodot for this job
		print("DEBUG MonteGodot: Job '%s' using n_cases: %d" % [current_job_name, _current_config.n_cases])

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

		# InVars are initialized and have their _drawn_values generated for all n_cases here.
		# We will now generate Case objects per super-batch instead of all at once.

		var effective_super_batch_size: int = _current_config.super_batch_size
		# Ensure effective_super_batch_size is at least 1 if n_cases > 0, and not larger than n_cases
		if _current_config.n_cases > 0:
			if effective_super_batch_size <= 0 or effective_super_batch_size > _current_config.n_cases:
				effective_super_batch_size = _current_config.n_cases
		else: # n_cases is 0
			effective_super_batch_size = 0 # No batches if no cases

		num_actual_super_batches = 0
		if _current_config.n_cases > 0 and effective_super_batch_size > 0:
			num_actual_super_batches = ceil(float(_current_config.n_cases) / effective_super_batch_size)
		elif _current_config.n_cases > 0: # e.g. n_cases = 10, effective_super_batch_size became n_cases
			num_actual_super_batches = 1

		var collected_processed_cases: Array[Case] = [] # Conditionally populated if _current_config.save_case_data is true
		var job_outputs_raw_data: Dictionary = {} # StringName (OutVal.name) -> Array (of raw OutVal data)
		var current_job_out_vars: Dictionary = {} # StringName (OutVar.name) -> OutVar instance
		
		var sorted_in_vars: Array[InVar] = get_input_vars_typed()
		# Sort InVars by their var_idx once, if needed for consistent InVal order in Cases.
		# Assuming get_input_vars_typed() and subsequent usage preserve any intended order or that order is managed by var_idx.
		sorted_in_vars.sort_custom(func(a: InVar, b: InVar): return a.var_idx < b.var_idx)

		for sb_idx: int in range(num_actual_super_batches):
			var super_batch_start_idx: int = sb_idx * effective_super_batch_size
			var super_batch_end_idx: int = min(super_batch_start_idx + effective_super_batch_size, _current_config.n_cases)
			
			var cases_for_this_super_batch: Array[Case] = []
			# 1. Generate Cases for the current super-batch
			if _current_config.n_cases > 0 and self.in_vars.is_empty() and not _current_config.in_vars.is_empty():
				push_warning("MonteGodot: Job '%s', Super-batch %d - Has n_cases > 0 but no InVars were successfully initialized. Cannot generate cases for this batch." % [current_job_name, sb_idx + 1])
				continue # Skip this super-batch
			
			for i: int in range(super_batch_start_idx, super_batch_end_idx): # Loop for current super-batch cases
				var case_obj: Case = Case.new(i) # i is the global case_idx
				for in_var_instance: InVar in sorted_in_vars:
					var specific_in_val: InVal = in_var_instance.get_value(i) 
					case_obj.add_input_value(specific_in_val)
				cases_for_this_super_batch.append(case_obj)

			if cases_for_this_super_batch.is_empty() and (super_batch_end_idx - super_batch_start_idx > 0):
				push_error("MonteGodot: Job '%s', Super-batch %d - Failed to generate cases for this batch (%d-%d)." % [current_job_name, sb_idx + 1, super_batch_start_idx, super_batch_end_idx -1])
				continue # Skip this super-batch
			elif cases_for_this_super_batch.is_empty(): # No cases to process in this range
				continue

			print("MonteGodot: Job '%s', Super-batch %d/%d (cases %d-%d) starting. Contains %d cases." %
				[current_job_name, sb_idx + 1, num_actual_super_batches, super_batch_start_idx, super_batch_end_idx -1, cases_for_this_super_batch.size()])

			# 2a. Preprocessing Stage for Super-batch
			# preprocess_case modifies case_obj in-place and returns it.
			for case_obj: Case in cases_for_this_super_batch:
				preprocess_case(case_obj) # Modifies case_obj directly
			print("MonteGodot: Job '%s', Super-batch %d - Preprocessing complete (%d tasks prepared for run stage)." % [current_job_name, sb_idx + 1, cases_for_this_super_batch.size()])

			var batch_processor_started: bool = _batch_processor.process(
				cases_for_this_super_batch, # Pass the cases for this super_batch
				run_case, # This is self.run_case, which takes a Case object
				_current_config.inner_batch_size,
				_current_config.num_threads
			)

			if not batch_processor_started:
				push_error("MonteGodot: Job '%s', Super-batch %d - Failed to start BatchProcessor." % [current_job_name, sb_idx + 1])
				continue # Skip to next super-batch
			
			print("MonteGodot: Job '%s', Super-batch %d - BatchProcessor initiated. Waiting..." % [current_job_name, sb_idx + 1])
			var batch_run_results_for_sb: Array = await _batch_processor.processing_complete
			print("MonteGodot: Job '%s', Super-batch %d - BatchProcessor completed (%d results)." % [current_job_name, sb_idx + 1, batch_run_results_for_sb.size()])

			# 4a. Postprocessing Stage for Super-batch
			if batch_run_results_for_sb.size() != cases_for_this_super_batch.size():
				push_warning("MonteGodot: Job '%s', Super-batch %d - Mismatch in case count (%d) and batch results (%d). Results might be misaligned." %
					[current_job_name, sb_idx + 1, cases_for_this_super_batch.size(), batch_run_results_for_sb.size()])

			for i: int in range(cases_for_this_super_batch.size()):
				var original_case_obj: Case = cases_for_this_super_batch[i]
				
				if i < batch_run_results_for_sb.size() and batch_run_results_for_sb[i] is Case:
					var processed_case_data: Case = batch_run_results_for_sb[i]
					original_case_obj.run_output = processed_case_data.run_output
					original_case_obj.start_time_msec = processed_case_data.start_time_msec
					original_case_obj.end_time_msec = processed_case_data.end_time_msec
					original_case_obj.runtime_msec = processed_case_data.runtime_msec
				else:
					push_warning("MonteGodot: Job '%s', Super-batch %d, Case index %d - Missing or invalid result from BatchProcessor. Postprocessing may use stale/no run_output." % [current_job_name, sb_idx + 1, original_case_obj.id if original_case_obj else i])

				var postprocessed_original_case: Case = postprocess_case(original_case_obj) # Modifies original_case_obj
				
				var case_out_vals: Array[OutVal] = postprocessed_original_case.get_output_values()
				for out_val_instance: OutVal in case_out_vals:
					var ov_name: StringName = out_val_instance.name
					if not job_outputs_raw_data.has(ov_name):
						job_outputs_raw_data[ov_name] = []
					job_outputs_raw_data[ov_name].append(out_val_instance.get_raw_data())

					# Temporary debug print for HandTypeResult aggregation (now commented out due to verbosity)
					# if ov_name == &"HandTypeResult":
					# 	print("DEBUG MonteGodot: Appended HandTypeResult for case_id %d. Current OutVar count for HandTypeResult: %d" % [original_case_obj.id, job_outputs_raw_data[ov_name].size()])

				if _current_config.save_case_data:
					collected_processed_cases.append(postprocessed_original_case)
			
			print("MonteGodot: Job '%s', Super-batch %d - Postprocessing complete." % [current_job_name, sb_idx + 1])
			
			# At this point, cases_for_this_super_batch and its Case objects (and their InVals)
			# will go out of scope with the next super-batch iteration, unless they were saved to collected_processed_cases.

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
		# Iterate through the aggregated raw data for each output variable name
		for out_var_name_sn: StringName in job_outputs_raw_data:
			var all_raw_vals_for_name: Array = job_outputs_raw_data[out_var_name_sn]
			
			# Placeholder for sourcing valmap_override. 
			# This could come from JobConfig (e.g., a Dictionary of valmaps per OutVar name)
			# or be determined by some other logic if needed. For now, default to empty.
			var valmap_override_for_name: Dictionary = {} 
			# TODO: Allow JobConfig to specify valmaps for specific OutVars by name.
			# var job_specific_valmaps = _current_config.get_valmap_for_outvar(out_var_name_sn) # Example
			
			if not all_raw_vals_for_name.is_empty():
				var new_out_var: OutVar = OutVar.new(
					out_var_name_sn,
					all_raw_vals_for_name,
					valmap_override_for_name,
					_current_config.first_case_is_median
					# datasource could be passed if relevant, e.g., if OutVals were imported
				)
				current_job_out_vars[out_var_name_sn] = new_out_var
			# else: No values collected for this name (should not happen if job_outputs_raw_data was populated correctly)

		job_stats["output_variables_summary"] = current_job_out_vars # Adding the OutVars to stats for now
		# -----------------------------------------------------

		print("MonteGodot: Job '%s' completed. Total time: %.2f sec." % [current_job_name, float(overall_job_duration_msec) / 1000.0])

		var results_to_emit: Array = []
		if _current_config.save_case_data:
			results_to_emit = collected_processed_cases
		# Else, results_to_emit remains an empty array by default, as Cases were not stored.
		
		all_aggregated_results[current_job_name] = {"results": results_to_emit, "stats": job_stats, "output_vars": current_job_out_vars}
		job_completed.emit(current_job_name, results_to_emit, job_stats, current_job_out_vars)

	_is_running_jobs = false
	all_jobs_completed.emit(all_aggregated_results) # This will also need adjustment if results are conditional
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
