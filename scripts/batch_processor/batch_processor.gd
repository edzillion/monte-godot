# res://scripts/batch_processor/batch_processor.gd
class_name BatchProcessor extends RefCounted

# Thread control signals
signal processing_complete(results: Array)

# Thread management variables
var _control_thread: Thread = null
var _is_processing: bool = false
# _max_threads member can be used as a default if not provided in process()
# var _max_threads_default: int = -1 
var _results: Array = []
var _batch_index: int # Stores the starting index of the current batch being processed
var _keep_reference: Array = [] # To keep input data alive for the thread
var _current_task_executor: Callable


func _init() -> void:
	# This connection is for the BatchProcessor instance to handle its own completion,
	# primarily for cleanup like joining the thread.
	processing_complete.connect(_on_processing_complete)
	

func process(all_cases: Array[Case], task_executor_callable: Callable, batch_size: int = 10, max_threads_override: int = -1) -> bool:
	if not all_cases or all_cases.is_empty(): # Ensure this check is active
		push_warning("BatchProcessor: No tasks provided for processing.")
		return false

	if batch_size <= 0:
		push_error("BatchProcessor: batch_size must be greater than 0.")
		return false # Or assert(false) if it's a critical contract violation

	if _is_processing:
		push_error("BatchProcessor: Already processing a batch. Wait for completion first.")
		return false
	
	if not task_executor_callable:
		push_error("BatchProcessor: task_executor_callable cannot be null.")
		return false # Or assert(false)

	_is_processing = true
	_keep_reference.clear() 
	_keep_reference.append(all_cases.duplicate(true)) 
	_current_task_executor = task_executor_callable
	
	_control_thread = Thread.new()
	# Pass the duplicated tasks from _keep_reference[0] to ensure the thread has the persistent copy
	_control_thread.start(_process_batches.bind(_keep_reference[0], batch_size, max_threads_override))
	return true


func _process_batches(tasks_to_process: Array, batch_size: int, p_max_threads: int) -> void:
	_results.clear() # Clear previous results for this run
	if tasks_to_process.is_empty(): # Should have been caught by process(), but good to double check
		call_deferred("emit_signal", "processing_complete", [])
		return

	_results.resize(tasks_to_process.size()) # Pre-allocate based on current super-batch size
	var total_batches: int = ceil(float(tasks_to_process.size()) / batch_size)
	if total_batches == 0 and not tasks_to_process.is_empty(): # If tasks_to_process has items but batch_size is huge
		total_batches = 1
	elif tasks_to_process.is_empty(): # handles case where tasks_to_process is empty initially.
		total_batches = 0

	print("BatchProcessor._process_batches: Processing %d tasks in %d batches (batch size: %d) using up to %d threads." % 
		[tasks_to_process.size(), total_batches, batch_size, p_max_threads])
		
	for i: int in range(total_batches):
		_batch_index = i * batch_size
		var current_batch_end_idx: int = min(_batch_index + batch_size, tasks_to_process.size())
		var batch_cases: Array = tasks_to_process.slice(_batch_index, current_batch_end_idx)
		
		print("BatchProcessor._process_batches: Starting batch %d/%d (tasks %d-%d) with %d tasks." % 
			[i + 1, total_batches, _batch_index, current_batch_end_idx - 1, batch_cases.size()])
		
		var batch_group_name: String = "managed_batch_%d" % i
		
		var group_id: int = WorkerThreadPool.add_group_task(
			process_task.bind(batch_cases), # Bind the current batch_tasks slice
			batch_cases.size(),             # Number of tasks in this specific batch
			p_max_threads,                  # Max threads for this group
			false,                          # Low priority
			batch_group_name
		)
		WorkerThreadPool.wait_for_group_task_completion(group_id)
		print("BatchProcessor._process_batches: Batch %d/%d completed." % [i + 1, total_batches])
	
	call_deferred("emit_signal", "processing_complete", _results.duplicate(true))


# This function is executed by worker threads.
# p_worker_task_idx: The index within the 'batch_cases_ref' array (0 to N-1 for the current batch).
# batch_cases_ref: A reference to the array of cases for the current batch (bound via .bind()).
func process_task(p_worker_task_idx: int, batch_cases_ref: Array[Case]) -> void:
	if p_worker_task_idx < 0 or p_worker_task_idx >= batch_cases_ref.size():
		push_error("BatchProcessor.process_task: p_worker_task_idx out of bounds!")
		# Potentially place a null or error marker in results if that's desired for robustness
		return

	# Calculate global result index once
	var result_idx: int = _batch_index + p_worker_task_idx

	# Single check for global result index bounds
	if result_idx < 0 or result_idx >= _results.size():
		# Using p_worker_task_idx in error msg because it's related to the task data that failed
		push_error("BatchProcessor.process_task: Global result_idx %d (from batch_idx %d + worker_task_idx %d) out of bounds for _results size %d." % [result_idx, _batch_index, p_worker_task_idx, _results.size()])
		return

	# Ensure _current_task_executor is valid before calling
	if _current_task_executor == null or not _current_task_executor.is_valid():
		push_error("BatchProcessor.process_task: _current_task_executor is null or invalid.")
		_results[result_idx] = null # Or some error marker
		return

	var case: Case = batch_cases_ref[p_worker_task_idx]
	var single_task_result = _current_task_executor.call(case) 
	_results[result_idx] = single_task_result


func _on_processing_complete(_final_results: Array) -> void: 
	print("BatchProcessor._on_processing_complete: Processing complete signal received by self.")
	_is_processing = false
	
	if _control_thread != null and _control_thread.is_started():
		_control_thread.wait_to_finish()
		_control_thread = null
	
	# _keep_reference is cleared at the start of the next 'process' call.
	# _results are also cleared at the start of _process_batches
	print("BatchProcessor: Control thread finished. Ready for new processing.")
