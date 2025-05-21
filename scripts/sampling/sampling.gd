# res://scripts/sampling/sampling.gd
class_name Sampling extends RefCounted

## Provides methods for generating random samples (percentiles) for Monte Carlo simulations.


## Generates random continuous percentiles for a given number of cases and input variables.
## Returns an Array of Arrays (effectively a 2D array) where results[case_idx][var_idx]
## is the random percentile (0.0 to 1.0) for that specific case and variable.
##
## Parameters:
##   p_num_cases: The number of simulation cases (e.g., rows).
##   p_num_vars: The number of input variables (e.g., columns).
##   p_seed: Optional. An integer seed for the random number generator. If 0, a random seed is used.
## Returns:
##   Array[Array[float]]: An array where each element is an array of floats (percentiles).
##                         Outer array corresponds to cases, inner array to variables.
static func generate_random_continuous_percentiles(p_num_cases: int, p_num_vars: int, p_seed: int = 0) -> Array:
	if p_num_cases <= 0:
		push_warning("Sampling: p_num_cases must be positive. Returning empty array.")
		return []
	if p_num_vars <= 0:
		push_warning("Sampling: p_num_vars must be positive. Returning empty array.")
		return []

	# Seed the random number generator if a specific seed is provided
	if p_seed != 0:
		seed(p_seed)

	var all_percentiles: Array = [] # This will be Array[Array[float]]
	for _i_case in range(p_num_cases):
		var case_percentiles: Array[float] = []
		for _j_var in range(p_num_vars):
			case_percentiles.append(randf()) # Generate a random float between 0.0 and 1.0
		all_percentiles.append(case_percentiles)

	return all_percentiles 