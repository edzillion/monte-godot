# res://src/stats/var_stat.gd
class_name VarStat extends RefCounted

## @brief Calculates and stores descriptive statistics for a collection of values.
##
## This class will provide methods to compute common statistical measures like
## mean, median, variance, standard deviation, etc., from a dataset (e.g., OutVals).
## It will be used to analyze the results of simulation runs.

#region Properties
var data: Array = [] ## The raw data (e.g., array of numbers) to calculate statistics on.

var mean: float = 0.0
var median: float = 0.0
var variance: float = 0.0
var std_deviation: float = 0.0
var min_value: float = 0.0
var max_value: float = 0.0
var count: int = 0
#endregion


#region Initialization
func _init(p_data: Array = []) -> void:
	if not p_data.is_empty():
		set_data(p_data)
#endregion


#region Public Methods
## @brief Sets the data for statistical calculation and triggers recalculation.
func set_data(p_data: Array) -> void:
	data = p_data.filter(func(x): return typeof(x) in [TYPE_INT, TYPE_FLOAT]) # Ensure numeric data
	count = data.size()
	if count > 0:
		_calculate_statistics()
	else:
		_reset_statistics()


## @brief Recalculates all statistics based on the current data.
func _calculate_statistics() -> void:
	if data.is_empty():
		_reset_statistics()
		return

	# Calculate Count
	count = data.size()

	# Calculate Min and Max
	min_value = data.min()
	max_value = data.max()

	# Calculate Mean
	var sum: float = 0.0
	for val in data:
		sum += float(val)
	mean = sum / float(count) if count > 0 else 0.0

	# Calculate Median
	var sorted_data: Array = data.duplicate()
	sorted_data.sort()
	if count % 2 == 1:
		median = float(sorted_data[count / 2])
	else:
		median = (float(sorted_data[count / 2 - 1]) + float(sorted_data[count / 2])) / 2.0 if count >= 2 else 0.0

	# Calculate Variance and Standard Deviation
	var sum_sq_diff: float = 0.0
	for val in data:
		sum_sq_diff += pow(float(val) - mean, 2)
	variance = sum_sq_diff / float(count) if count > 0 else 0.0
	std_deviation = sqrt(variance) if variance >= 0 else 0.0

	print("Statistics calculated for %d data points." % count)


## @brief Resets all calculated statistical values to defaults.
func _reset_statistics() -> void:
	mean = 0.0
	median = 0.0
	variance = 0.0
	std_deviation = 0.0
	min_value = 0.0
	max_value = 0.0
	count = 0
	print("Statistics reset.")
#endregion 