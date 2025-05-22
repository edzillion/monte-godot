extends Node

func sanitize(sources: Array) -> Array[float]:
	var sanitized: Array[float] = []
	var type: int = 0
	
	for source in sources:
		type = typeof(source)
		match type:
			2, 3:
				sanitized.append(float(source))
			_:
				pass
	
	sanitized.sort()
	
	return sanitized

func mean(data: Array[float], dof: float) -> float:
	var sum: float = 0.0
	
	for datum in data:
		sum += datum
	
	return snapped((sum / data.size()), dof)

func median(data: Array[float], dof: float) -> float:
	if data.size() % 2 != 0:
		return snapped((data[int(data.size() / 2)]), dof)
	else:
		return snapped((0.5 * (data[int((data.size() - 1) / 2)] + data[int(data.size() / 2)])), dof)

func spread(data: Array[float], dof: float) -> float:
	return snapped((data.max() - data.min()), dof)

func minima(data: Array[float], dof: float) -> float:
	return snapped(data.min(), dof)

func maxima(data: Array[float], dof: float) -> float:
	return snapped(data.max(), dof)

func variance(data: Array[float], dof: float) -> float:
	var variance: float = 0.0
	var mean: float = mean(data, dof)
	
	for datum in data:
		variance += (datum - mean) ** 2
	
	return snapped((variance / data.size()), dof)

func standev(data: Array[float], dof: float) -> float:
	var variance: float = variance(data, dof)
	
	return snapped((variance ** 0.5), dof)

func mad(data: Array[float], dof: float) -> float:
	var median: float = median(data, dof)
	var deviations: Array[float] = []
	
	for datum in data:
		deviations.append(abs(datum - median))
	
	deviations.sort()
	
	return snapped((median(deviations, dof)), dof)

func all(sources: Array, dof: float) -> Dictionary:
	var results: Dictionary = {
		"Mean": 0.0,
		"Median": 0.0,
		"Spread": 0.0,
		"Minima": 0.0,
		"Maxima": 0.0,
		"Variance": 0.0,
		"Standev": 0.0,
		"Mad": 0.0
	}
	
	var data: Array[float] = sanitize(sources)
	
	results["Mean"] = mean(data, dof)
	results["Median"] = median(data, dof)
	results["Spread"] = spread(data, dof)
	results["Minima"] = minima(data, dof)
	results["Maxima"] = maxima(data, dof)
	results["Variance"] = variance(data, dof)
	results["Standev"] = standev(data, dof)
	results["Mad"] = mad(data, dof)
	
	return results
