# res://tests/stats/var_stat_test.gd
class_name VarStatTest extends GdUnitTestSuite


func test_initialization_empty() -> void:
	var vs: VarStat = VarStat.new()
	assert_int(vs.count).is_equal(0)
	assert_float(vs.mean).is_equal(0.0)
	assert_float(vs.median).is_equal(0.0)
	assert_float(vs.variance).is_equal(0.0)
	assert_float(vs.std_deviation).is_equal(0.0)
	assert_float(vs.min_value).is_equal(0.0)
	assert_float(vs.max_value).is_equal(0.0)


func test_initialization_with_data() -> void:
	var data: Array = [1, 2, 3, 4, 5]
	var vs: VarStat = VarStat.new(data)
	assert_int(vs.count).is_equal(5)
	assert_float(vs.mean).is_equal_approx(3.0, 0.001)
	assert_float(vs.median).is_equal_approx(3.0, 0.001)
	assert_float(vs.min_value).is_equal_approx(1.0, 0.001)
	assert_float(vs.max_value).is_equal_approx(5.0, 0.001)
	# Variance of [1,2,3,4,5] is 2.0. StdDev is sqrt(2) approx 1.414
	assert_float(vs.variance).is_equal_approx(2.0, 0.001)
	assert_float(vs.std_deviation).is_equal_approx(sqrt(2.0), 0.001)


func test_set_data_updates_stats() -> void:
	var vs: VarStat = VarStat.new()
	var data: Array = [10, 20, 30]
	vs.set_data(data)
	assert_int(vs.count).is_equal(3)
	assert_float(vs.mean).is_equal_approx(20.0, 0.001)
	assert_float(vs.median).is_equal_approx(20.0, 0.001)
	# Variance: ((10-20)^2 + (20-20)^2 + (30-20)^2) / 3 = (100 + 0 + 100) / 3 = 200/3 = 66.666...
	# StdDev: sqrt(66.666...) approx 8.165
	assert_float(vs.variance).is_equal_approx(200.0/3.0, 0.001)
	assert_float(vs.std_deviation).is_equal_approx(sqrt(200.0/3.0), 0.001)


func test_data_with_non_numeric_values() -> void:
	var data: Array = [1, "apple", 2, null, 3, true, "banana", 4.5]
	var vs: VarStat = VarStat.new(data)
	# Should filter to [1, 2, 3, 4.5]
	assert_int(vs.count).is_equal(4)
	# Mean of [1, 2, 3, 4.5] = 10.5 / 4 = 2.625
	assert_float(vs.mean).is_equal_approx(2.625, 0.001)
	# Median of sorted [1, 2, 3, 4.5] is (2+3)/2 = 2.5
	assert_float(vs.median).is_equal_approx(2.5, 0.001)


func test_single_data_point() -> void:
	var data: Array = [42.0]
	var vs: VarStat = VarStat.new(data)
	assert_int(vs.count).is_equal(1)
	assert_float(vs.mean).is_equal_approx(42.0, 0.001)
	assert_float(vs.median).is_equal_approx(42.0, 0.001)
	assert_float(vs.variance).is_equal_approx(0.0, 0.001)
	assert_float(vs.std_deviation).is_equal_approx(0.0, 0.001)
	assert_float(vs.min_value).is_equal_approx(42.0, 0.001)
	assert_float(vs.max_value).is_equal_approx(42.0, 0.001)


func test_all_same_data_points() -> void:
	var data: Array = [7.0, 7.0, 7.0, 7.0]
	var vs: VarStat = VarStat.new(data)
	assert_int(vs.count).is_equal(4)
	assert_float(vs.mean).is_equal_approx(7.0, 0.001)
	assert_float(vs.median).is_equal_approx(7.0, 0.001)
	assert_float(vs.variance).is_equal_approx(0.0, 0.001)
	assert_float(vs.std_deviation).is_equal_approx(0.0, 0.001)


func test_median_even_number_of_elements() -> void:
	var data: Array = [1, 2, 3, 4] # Median is (2+3)/2 = 2.5
	var vs: VarStat = VarStat.new(data)
	assert_float(vs.median).is_equal_approx(2.5, 0.001)

	data = [10, 50, 20, 40, 30, 60] # Sorted: [10,20,30,40,50,60]. Median: (30+40)/2 = 35
	vs.set_data(data)
	assert_float(vs.median).is_equal_approx(35.0, 0.001)


func test_median_odd_number_of_elements() -> void:
	var data: Array = [1, 2, 3, 4, 5] # Median is 3
	var vs: VarStat = VarStat.new(data)
	assert_float(vs.median).is_equal_approx(3.0, 0.001)

	data = [10, 50, 20, 40, 30] # Sorted: [10,20,30,40,50]. Median: 30
	vs.set_data(data)
	assert_float(vs.median).is_equal_approx(30.0, 0.001) 
