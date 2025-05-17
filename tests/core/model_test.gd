# res://tests/core/model_test.gd
extends GdUnitTestSuite
@onready var scene_root = get_tree().root

# Test suite for the sim_model class

# const MockSimManager = preload("res://tests/mocks/mock_sim_manager.gd") # Removed
var sim_model: SimModel
# var mock_sim_manager: MockSimManager # Using a specific mock type # Changed type
var mock_sim_manager: SimManager # Will be a mock instance of SimManager

func before_test() -> void:
	mock_sim_manager = mock(SimManager) # Use GDUnit4 mock
	# Ensure mock_sim_manager is added to the scene tree if it needs _process or other Node functionalities.
	# For this basic test, if MockSimManager doesn't rely on tree processing, this might not be strictly necessary.
	# However, SimManager itself is a Node, so its mock likely should be too.
	scene_root.add_child(mock_sim_manager)
	sim_model = SimModel.new("TestModel", "A sim_model for testing", mock_sim_manager)
	# Add sim_model to tree if it were a Node, but it's RefCounted. SimManager (or its mock) is the Node.

func after_test() -> void:
	if sim_model: # sim_model is RefCounted, will be freed if no refs.
		sim_model = null
	# For GDUnit mocks of Nodes, direct freeing or remove_child might not be needed
	# as the mock framework might handle cleanup or they might not be actual scene tree nodes.
	# However, if we add it to the tree, we should remove it.
	if mock_sim_manager and is_instance_valid(mock_sim_manager) and mock_sim_manager.get_parent():
		mock_sim_manager.get_parent().remove_child(mock_sim_manager)
	# GDUnit mocks of RefCounted or Object don't need manual free usually.
	# If the mock is of a Node and was added to the tree, removing it is good.
	# The mock object itself will be managed by GDUnit or GC.
	# mock_sim_manager.free() # MockSimManager is a Node, so free it. # Let GDUnit handle mock lifecycle
	mock_sim_manager = null


func test_model_initialization() -> void:
	assert_str(sim_model.model_name).is_equal("TestModel")
	assert_str(sim_model.model_description).is_equal("A sim_model for testing")
	assert_object(sim_model.sim_manager).is_equal(mock_sim_manager).is_not_null()
	
	# Test initialization with default SimManager
	var model_with_default_sm = SimModel.new("DefaultSMModel")
	assert_object(model_with_default_sm.sim_manager).is_not_null()
	assert_bool(model_with_default_sm.sim_manager is SimManager).is_true()
	# model_with_default_sm.sim_manager.free() # Free the created SimManager if it was a Node
	# If SimManager.new() creates a Node that isn't added to tree, it might need manual free.
	# Our current SimManager is a Node, so it should be freed.
	if model_with_default_sm.sim_manager and model_with_default_sm.sim_manager is Node:
		model_with_default_sm.sim_manager.free()


func test_configure_simulation() -> void:
	var preprocess_func: Callable = func(_case): return []
	var run_func: Callable = func(_inputs): return null
	var postprocess_func: Callable = func(_case, _outputs): pass

	var invar1 = InVar.new(&"in1", "Input1")
	var outvar1 = OutVar.new(&"out1", "Output1")

	sim_model.configure_simulation(
		100, preprocess_func, run_func, postprocess_func, [invar1], [outvar1], 4, true
	)
	
	# mock_sim_manager is the one passed to SimModel constructor, so SimModel holds the reference.
	var actual_sim_manager_mock = sim_model.sim_manager 

	assert_int(actual_sim_manager_mock.n_cases).is_equal(100)
	assert_int(actual_sim_manager_mock.max_threads).is_equal(4)
	assert_bool(actual_sim_manager_mock.output_as_dataframe).is_true()
	
	verify(actual_sim_manager_mock).set_simulation_functions(preprocess_func, run_func, postprocess_func)
	verify(actual_sim_manager_mock).add_input_variable(invar1)
	verify(actual_sim_manager_mock).add_output_variable(outvar1)


func test_run_simulation() -> void:
	# Configure the simulation first
	var preprocess_func: Callable = func(_case): return []
	var run_func: Callable = func(_inputs): return null
	var postprocess_func: Callable = func(_case, _outputs): pass
	sim_model.configure_simulation(
		10, preprocess_func, run_func, postprocess_func, [], [], 0, false
	)

	var result: bool = sim_model.run_simulation()
	assert_bool(result).is_true()
	# mock_sim_manager is the one passed to SimModel constructor
	verify(sim_model.sim_manager).run_simulation() 


func test_get_results_placeholder() -> void:
	# Currently, get_results is a placeholder and returns null.
	# It also logs a warning if the simulation is running.
	var results = sim_model.get_results()
	assert_object(results).is_null()

	# Simulate SimManager running
	# mock_sim_manager is the one passed to SimModel constructor
	var actual_sim_manager_mock = sim_model.sim_manager
	actual_sim_manager_mock.is_running = true
	# No direct way to check for Logger.warning output with current setup,
	# but we can verify the method still returns null.
	results = sim_model.get_results()
	assert_object(results).is_null()
	actual_sim_manager_mock.is_running = false # Reset for other tests 
