# res://examples/estimate_pi.gd
extends Node

# References to our core library classes
# These might need to be preloaded if not using class_name directly in some contexts,
# but with autoloads and class_name, direct instantiation should work once Godot parses.
# const SimManager = preload("res://src/managers/sim_manager.gd") # Not needed if SimManager is a node in scene or autoloaded

# InVar and InVal might not be strictly needed for this simple Pi example if run uses case seed

var sim_manager: SimManager
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- Simulation Functions ---

# Preprocess: Takes a Case object, returns arguments for the run function.
# For this Pi example, the run function only needs the case's seed for its RNG.
func _preprocess_pi(current_case: Case) -> int:
	# if local_logger: local_logger.debug("Preprocessing Case: %d" % current_case.case_id)
	return current_case.seed


# Run: Simulates one point, returns true if in circle, false otherwise.
# Takes the seed from preprocess to initialize its own RNG for repeatability.
func _run_pi(case_seed: int) -> bool:
	var case_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	case_rng.seed = case_seed
	var x: float = case_rng.randf()
	var y: float = case_rng.randf()
	# if local_logger: local_logger.debug("Run Case with seed %d: (x=%f, y=%f)" % [case_seed, x,y])
	return (x*x + y*y) <= 1.0 # Check if point is within the unit circle


# Postprocess: Takes the Case and run output, logs the result to the Case.
func _postprocess_pi(current_case: Case, is_in_circle: bool) -> void:
	# if local_logger: local_logger.debug("Postprocessing Case: %d, InCircle: %s" % [current_case.case_id, is_in_circle])
	var result_val: OutVal = OutVal.new(1.0 if is_in_circle else 0.0) # Store 1 for in, 0 for out
	current_case.add_output_value(&"is_in_circle", result_val)


# --- Simulation Setup and Execution ---

func _ready() -> void:
	if Logger:
		Logger.info("EstimatePi: Script started. Logger instance obtained.")

	# Instantiate SimManager (assuming it's added to the scene or also autoloaded)
	# If SimManager is autoloaded: sim_manager = SimManager
	# If it needs to be instantiated as a child node:
	sim_manager = SimManager.new()
	add_child(sim_manager)
	sim_manager.name = "PiSimManager"

	# 1. Configure SimManager
	sim_manager.n_cases = 10000 # Number of points to simulate

	# 2. Define Output Variable
	var ov_is_in_circle: OutVar = OutVar.new(&"is_in_circle", "Point in Circle?", "1 if in unit circle, 0 otherwise")
	sim_manager.add_output_variable(ov_is_in_circle)

	# (Input Variables are not strictly necessary for this basic Pi example
	# as randomness is self-contained in _run_pi using the case seed)

	# 3. Set simulation functions
	sim_manager.set_simulation_functions(
		Callable(self, "_preprocess_pi"),
		Callable(self, "_run_pi"),
		Callable(self, "_postprocess_pi")
	)

	# 4. Connect to simulation completion signal
	sim_manager.simulation_completed.connect(Callable(self, "_on_simulation_completed"))
	sim_manager.simulation_progress.connect(Callable(self, "_on_simulation_progress"))
	sim_manager.simulation_error.connect(Callable(self, "_on_simulation_error"))

	# 5. Run the simulation
	if Logger:
		Logger.info("EstimatePi: Starting Pi estimation simulation...")
	sim_manager.run_simulation()


func _on_simulation_progress(progress_percentage: float) -> void:
	if Logger:
		Logger.info("EstimatePi: Simulation progress: %.2f%%" % progress_percentage)


func _on_simulation_error(error_message: String) -> void:
	if Logger:
		Logger.error("EstimatePi: Simulation error: %s" % error_message)


func _on_simulation_completed(results: Array) -> void:
	if Logger:
		Logger.info("EstimatePi: Simulation completed. Processing results...")

	if results.is_empty():
		if Logger:
			Logger.warning("EstimatePi: No results returned from simulation.")
		return

	var points_in_circle: int = 0
	var total_points: int = results.size()

	for case_result in results:
		if not case_result is Case:
			if Logger:
				Logger.warning("EstimatePi: Result item is not a Case object.")
			continue

		var out_val: OutVal = case_result.get_output_value(&"is_in_circle")
		if out_val and out_val.get_value() == 1.0:
			points_in_circle += 1

	if total_points > 0:
		var pi_estimate: float = 4.0 * (float(points_in_circle) / float(total_points))
		if Logger:
			Logger.info("EstimatePi: Total points simulated: %d" % total_points)
			Logger.info("EstimatePi: Points in circle: %d" % points_in_circle)
			Logger.info("EstimatePi: Estimated value of Pi: %f" % pi_estimate)
		print("Estimated Pi: %f" % pi_estimate) # Always print final estimate
	else:
		if Logger:
			Logger.warning("EstimatePi: Total points simulated was zero, cannot estimate Pi.")

	# Optional: Clean up SimManager if it was dynamically added and is no longer needed
	# sim_manager.queue_free() 
