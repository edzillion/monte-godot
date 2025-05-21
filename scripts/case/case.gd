# res://scripts/case/case.gd
class_name Case extends RefCounted

## Represents a single simulation run (case) with its own set of input and output values.

enum CaseStage {
	UNINITIALIZED,
	PREPROCESS,
	RUN,
	POSTPROCESS
}
var stage: CaseStage = CaseStage.UNINITIALIZED

var id: int
var case_seed: int
var _input_values: Array[InVal]
var _output_values: Array[OutVal]
var sim_input_args: Array # Stores the arguments for the RUN stage, after preprocessing
var run_output: Array # Stores the output of the RUN stage as arguments for the POSTPROCESS stage

var start_time_msec: int = 0
var end_time_msec: int = 0
var runtime_msec: int = 0


func _init(p_id: int, p_seed: int = 0) -> void:
	id = p_id
	# If p_seed is 0, use a fixed default. Meaningful seed should be provided by caller if reproducibility is desired.
	case_seed = p_seed if p_seed != 0 else 1
	_input_values = [] # Initialize arrays
	_output_values = []
	sim_input_args = [] # Initialize the new array


func add_input_value(value: InVal) -> void:
	_input_values.append(value)


func get_input_value(index: int) -> InVal:
	return _input_values[index]


func add_output_value(value: OutVal) -> void:
	_output_values.append(value)


func get_output_values() -> Array[OutVal]:
	return _output_values.duplicate()


func clear_outputs() -> void:
	_output_values.clear() 
