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
	assert_int(manager.n_cases).is_equal(1000)
	assert_int(manager.max_threads).is_equal(0)
	assert_bool(manager.output_as_dataframe).is_false()
	assert_dict(manager.input_variables).is_empty()
	assert_dict(manager.output_variables).is_empty()
	assert_array(manager.cases).is_empty()
	assert_bool(manager.is_running).is_false()

func test_set_simulation_functions_valid() -> void:
	manager.set_simulation_functions(mock_preprocess_func, mock_run_func, mock_postprocess_func)
	assert_true(manager.preprocess_callable.is_valid())
	assert_true(manager.run_callable.is_valid())
	assert_true(manager.postprocess_callable.is_valid())
	assert_object(manager.preprocess_callable).is_equal(mock_preprocess_func)

func test_set_simulation_functions_invalid_emits_error_signal() -> void:
	var invalid_callable = Callable() # Default invalid callable
	var signal_spy_error = spy_on_signal(manager, manager.simulation_error)
	
	manager.set_simulation_functions(invalid_callable, mock_run_func, mock_postprocess_func)
	assert_false(manager.preprocess_callable.is_valid()) # Should not be set
	signal_spy_error.assert_emitted("Invalid simulation functions provided.")

	signal_spy_error.reset()
	manager.set_simulation_functions(mock_preprocess_func, invalid_callable, mock_postprocess_func)
	signal_spy_error.assert_emitted("Invalid simulation functions provided.")

	signal_spy_error.reset()
	manager.set_simulation_functions(mock_preprocess_func, mock_run_func, invalid_callable)
	signal_spy_error.assert_emitted("Invalid simulation functions provided.")

func test_add_input_variable() -> void:
	var invar1: InVar = InVar.new(&"x", "Input X")
	manager.add_input_variable(invar1)
	assert_dict(manager.input_variables).has_key(&"x")
	assert_object(manager.input_variables[&"x"]).is_equal(invar1)

	# Test overwriting (should warn, but replace)
	var invar1_new: InVar = InVar.new(&"x", "Input X New")
	assert_warning_emitted(func(): manager.add_input_variable(invar1_new), "SimManager: Input variable with id 'x' already exists. Overwriting.")
	assert_object(manager.input_variables[&"x"]).is_equal(invar1_new) # Check it was replaced
	assert_str(manager.input_variables[&"x"].name).is_equal("Input X New")

func test_add_input_variable_invalid_type() -> void:
	var not_invar = Node.new()
	# This should push an error, but not easy to assert_error_emitted directly for push_error
	# We can check that the variable was NOT added.
	var original_count = manager.input_variables.size()
	manager.add_input_variable(not_invar) # type hint error
	assert_int(manager.input_variables.size()).is_equal(original_count) # Should not add

func test_add_output_variable() -> void:
	var outvar1: OutVar = OutVar.new(&"y", "Output Y")
	manager.add_output_variable(outvar1)
	assert_dict(manager.output_variables).has_key(&"y")
	assert_object(manager.output_variables[&"y"]).is_equal(outvar1)

	# Test overwriting
	var outvar1_new: OutVar = OutVar.new(&"y", "Output Y New")
	assert_warning_emitted(func(): manager.add_output_variable(outvar1_new), "SimManager: Output variable with id 'y' already exists. Overwriting.")
	assert_object(manager.output_variables[&"y"]).is_equal(outvar1_new)
	assert_str(manager.output_variables[&"y"].name).is_equal("Output Y New")

func test_add_output_variable_invalid_type() -> void:
	var not_outvar = Node.new()
	var original_count = manager.output_variables.size()
	manager.add_output_variable(not_outvar)
	assert_int(manager.output_variables.size()).is_equal(original_count)

# More tests to come for run_simulation, _process_single_case_task, etc. 