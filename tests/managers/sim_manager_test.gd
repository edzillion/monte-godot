# res://tests/managers/sim_manager_test.gd
class_name SimManagerTest extends GdUnitTestSuite

const SimManager = preload("res://src/managers/sim_manager.gd")
const InVar = preload("res://src/core/in_var.gd")
const OutVar = preload("res://src/core/out_var.gd")
const Case = preload("res://src/core/case.gd")

var manager: SimManager

# Mock callables
var mock_preprocess_func: Callable
var mock_run_func: Callable
var mock_postprocess_func: Callable

var preprocess_spy # GdUnitSpy
var run_spy # GdUnitSpy
var postprocess_spy # GdUnitSpy

func before_test() -> void:
	manager = SimManager.new()
	add_child(manager) # Add to tree to allow _process to run if needed, and for signals

	# Create fresh mock callables and spies for each test
	mock_preprocess_func = func(_case: Case) -> Array: return [_case.case_id] 
	mock_run_func = func(run_input: Variant) -> Dictionary: return {"result": run_input}
	mock_postprocess_func = func(_case: Case, _run_output: Dictionary) -> void: pass
	
	# Note: Spying on lambdas/inline funcs directly is not straightforward.
	# If we need to spy on the mock callables, we might need to make them methods of a test helper object.
	# For now, we'll pass them and check their effects.

func test_initialization_default_values() -> void:
	assert_int(manager.n_cases).is_equal(0)
	assert_int(manager.max_threads).is_equal(0)
	assert_bool(manager.output_as_dataframe).is_false()
	assert_dict(manager.input_variables).is_empty()
	assert_dict(manager.output_variables).is_empty()
	assert_bool(manager.is_running).is_false()

func test_set_simulation_functions_valid() -> void:
	manager.set_simulation_functions(mock_preprocess_func, mock_run_func, mock_postprocess_func)
	assert_bool(manager.preprocess_callable.is_valid()).is_true()
	assert_bool(manager.run_callable.is_valid()).is_true()
	assert_bool(manager.postprocess_callable.is_valid()).is_true()
	assert_object(manager.preprocess_callable).is_equal(mock_preprocess_func)

func test_add_input_variable() -> void:
	var invar1: InVar = InVar.new(&"x", "Input X", InVar.DistributionType.BERNOULLI, {"a":0.0, "b":1.0})
	manager.add_input_variable(invar1)
	assert_dict(manager.input_variables).contains_same_key_value(&"x", invar1)	

	# Test overwriting (should warn, but replace)
	var invar1_new: InVar = InVar.new(&"x", "Input X New", InVar.DistributionType.EXPONENTIAL, {"a":0.0, "b":1.0})
	# Expected: warning in Godot log about overwriting input variable, but not asserted here.
	manager.add_input_variable(invar1_new)
	assert_object(manager.input_variables[&"x"]).is_equal(invar1_new) # Check it was replaced
	assert_str(manager.input_variables[&"x"].name).is_equal("Input X New")

func test_add_output_variable() -> void:
	var outvar1: OutVar = OutVar.new(&"y", "Output Y")
	manager.add_output_variable(outvar1)
	assert_dict(manager.output_variables).contains_same_key_value(&"y", outvar1)	

	# Test overwriting
	var outvar1_new: OutVar = OutVar.new(&"y", "Output Y New")
	# Expected: warning in Godot log about overwriting output variable, but not asserted here.
	manager.add_output_variable(outvar1_new)
	assert_object(manager.output_variables[&"y"]).is_equal(outvar1_new)
	assert_str(manager.output_variables[&"y"].name).is_equal("Output Y New")
