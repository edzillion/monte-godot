# res://scripts/var/in_var.gd
@tool
class_name InVar extends Resource

#region Properties
var name: StringName ## User-friendly name for the variable.
var description: String ## A more detailed description of what the variable represents.
var ndraws: int = 0 ## The number of random draws.
var var_idx: int = -1 ## The number/index of this input variable.
#endregion

#region Enums
## @brief Defines the type of probability distribution for the input variable.
enum DistributionType {
	UNIFORM,      # params: {"a": float, "b": float}
	NORMAL,       # params: {"mean": float, "std_dev": float}
	BERNOULLI,    # params: {"p": float} (output 0.0 or 1.0)
	BINOMIAL,     # params: {"n": int, "p": float}
	POISSON,      # params: {"lambda": float}
	EXPONENTIAL,  # params: {"lambda": float}
	GEOMETRIC,    # params: {"p": float}
	ERLANG,       # params: {"k": int, "lambda": float}
	HISTOGRAM,    # params: {"values": Array[float], "probabilities": Array[float]}
	PSEUDO_RANDOM,# params: {"c": float}
	CUSTOM        # params: Uses num_map directly or custom logic with distribution_params.
}

## @brief Defines the random sampling method to use. Placeholder for now.
enum SampleMethod {
	RANDOM, # Default, simple random sampling
	SOBOL,  # Placeholder for Sobol sequences
	LATIN_HYPERCUBE # Placeholder for Latin Hypercube Sampling
}
var sample_method: SampleMethod = SampleMethod.RANDOM ## The random sampling method to use.
#endregion

#region Exported Variables
@export var distribution_type: DistributionType = DistributionType.UNIFORM:
	set(value):
		distribution_type = value
		_update_distribution_info()
		_update_dict_from_exported_fields()
		if Engine.is_editor_hint():
			notify_property_list_changed()

@export_category("Distribution Info")
@export var distribution_info: String = ""

@export_category("Uniform Parameters")
@export var uniform_a: float = 0.0
@export var uniform_b: float = 1.0

@export_category("Normal Parameters")
@export var normal_mean: float = 0.0
@export var normal_std_dev: float = 1.0

@export_category("Bernoulli Parameters")
@export var bernoulli_p: float = 0.5

@export_category("Binomial Parameters")
@export var binomial_n: int = 1
@export var binomial_p: float = 0.5

@export_category("Poisson Parameters")
@export var poisson_lambda: float = 1.0

@export_category("Exponential Parameters")
@export var exponential_lambda: float = 1.0

@export_category("Geometric Parameters")
@export var geometric_p: float = 0.5

@export_category("Erlang Parameters")
@export var erlang_k: int = 1
@export var erlang_lambda: float = 1.0

@export_category("Histogram Parameters")
@export var histogram_values: Array[float] = []
@export var histogram_probabilities: Array[float] = []

@export_category("Pseudo-Random Parameters")
@export var pseudo_c: float = 0.1

#endregion

## @brief Optional mapping of numerical values to other data types (e.g., strings, objects).
var num_map: Dictionary = {}

# Stores parameters when distribution_type is CUSTOM or for initial programmatic setup.
var distribution_params: Dictionary = {}


func _init(
	p_name: StringName = &"", 
	p_distribution_type: DistributionType = DistributionType.UNIFORM, 
	p_distribution_params: Dictionary = {}, 
	p_description: String = "",
	p_ndraws: int = 0,
	p_sample_method: SampleMethod = SampleMethod.RANDOM,
	p_var_idx: int = -1
	) -> void:
	self.resource_name = p_name
	self.description = p_description
	self.ndraws = p_ndraws
	self.sample_method = p_sample_method
	self.var_idx = p_var_idx
	
	distribution_type = p_distribution_type # Set early
	
	if not p_distribution_params.is_empty():
		distribution_params = p_distribution_params.duplicate()
		_update_exported_fields_from_dict(distribution_params)
	else:
		_update_dict_from_exported_fields()

	set_distribution_type(p_distribution_type) # Call full setter


func set_distribution_type(value: DistributionType) -> void:
	distribution_type = value
	_update_distribution_info()
	_update_dict_from_exported_fields()
	if Engine.is_editor_hint():
		notify_property_list_changed()

func get_value() -> InVal:
	var raw_value: float = _generate_value_from_distribution()
	if not num_map.is_empty() and num_map.has(raw_value):
		return InVal.new(raw_value, num_map[raw_value])
	return InVal.new(raw_value)

func _update_distribution_info() -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			distribution_info = "Uniform params: {a: float, b: float}"
		DistributionType.NORMAL:
			distribution_info = "Normal params: {mean: float, std_dev: float}"
		DistributionType.BERNOULLI:
			distribution_info = "Bernoulli param: {p: float (0.0-1.0)}"
		DistributionType.BINOMIAL:
			distribution_info = "Binomial params: {n: int >= 0, p: float (0.0-1.0)}"
		DistributionType.POISSON:
			distribution_info = "Poisson param: {lambda: float >= 0}"
		DistributionType.EXPONENTIAL:
			distribution_info = "Exponential param: {lambda: float > 0}"
		DistributionType.GEOMETRIC:
			distribution_info = "Geometric param: {p: float (0.0-1.0)}"
		DistributionType.ERLANG:
			distribution_info = "Erlang params: {k: int > 0, lambda: float > 0}"
		DistributionType.HISTOGRAM:
			distribution_info = "Histogram params: {values: Array[float], probabilities: Array[float]}"
		DistributionType.PSEUDO_RANDOM:
			distribution_info = "Pseudo-Random (Warcraft3/Dota) param: {c: float}"
		DistributionType.CUSTOM:
			distribution_info = "Custom. Uses num_map or custom logic in distribution_params."
		_:
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])


func _update_exported_fields_from_dict(params: Dictionary) -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			uniform_a = params.get("a", 0.0)
			uniform_b = params.get("b", 1.0)
		DistributionType.NORMAL:
			normal_mean = params.get("mean", 0.0)
			normal_std_dev = params.get("std_dev", 1.0)
		DistributionType.BERNOULLI:
			bernoulli_p = params.get("p", 0.5)
		DistributionType.BINOMIAL:
			binomial_n = params.get("n", 1)
			binomial_p = params.get("p", 0.5)
		DistributionType.POISSON:
			poisson_lambda = params.get("lambda", 1.0)
		DistributionType.EXPONENTIAL:
			exponential_lambda = params.get("lambda", 1.0)
		DistributionType.GEOMETRIC:
			geometric_p = params.get("p", 0.5)
		DistributionType.ERLANG:
			erlang_k = params.get("k", 1)
			erlang_lambda = params.get("lambda", 1.0)
		DistributionType.HISTOGRAM:
			histogram_values = params.get("values", [])
			histogram_probabilities = params.get("probabilities", [])
		DistributionType.PSEUDO_RANDOM:
			pseudo_c = params.get("c", 0.1)
		DistributionType.CUSTOM: pass
		_: 
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])


func _update_dict_from_exported_fields() -> void:
	match distribution_type:
		DistributionType.UNIFORM:
			distribution_params = {"a": uniform_a, "b": uniform_b}
		DistributionType.NORMAL:
			distribution_params = {"mean": normal_mean, "std_dev": normal_std_dev}
		DistributionType.BERNOULLI:
			distribution_params = {"p": bernoulli_p}
		DistributionType.BINOMIAL:
			distribution_params = {"n": binomial_n, "p": binomial_p}
		DistributionType.POISSON:
			distribution_params = {"lambda": poisson_lambda}
		DistributionType.EXPONENTIAL:
			distribution_params = {"lambda": exponential_lambda}
		DistributionType.GEOMETRIC:
			distribution_params = {"p": geometric_p}
		DistributionType.ERLANG:
			distribution_params = {"k": erlang_k, "lambda": erlang_lambda}
		DistributionType.HISTOGRAM:
			distribution_params = {"values": histogram_values, "probabilities": histogram_probabilities}
		DistributionType.PSEUDO_RANDOM:
			distribution_params = {"c": pseudo_c}
		DistributionType.CUSTOM: pass
		_: 
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])


func _validate_property(property: Dictionary) -> void:
	if not Engine.is_editor_hint():
		return

	var prop_name: StringName = property.name

	if prop_name == &"distribution_info":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
		return

	var show_prop = false
	match distribution_type:
		DistributionType.UNIFORM:
			if prop_name in [&"uniform_a", &"uniform_b"]: 
				show_prop = true
		DistributionType.NORMAL:
			if prop_name in [&"normal_mean", &"normal_std_dev"]: 
				show_prop = true
		DistributionType.BERNOULLI:
			if prop_name == &"bernoulli_p": 
				show_prop = true
		DistributionType.BINOMIAL:
			if prop_name in [&"binomial_n", &"binomial_p"]: 
				show_prop = true
		DistributionType.POISSON:
			if prop_name == &"poisson_lambda": 
				show_prop = true
		DistributionType.EXPONENTIAL:
			if prop_name == &"exponential_lambda": 
				show_prop = true
		DistributionType.GEOMETRIC:
			if prop_name == &"geometric_p": 
				show_prop = true
		DistributionType.ERLANG:
			if prop_name in [&"erlang_k", &"erlang_lambda"]: 
				show_prop = true
		DistributionType.HISTOGRAM:
			if prop_name in [&"histogram_values", &"histogram_probabilities"]: 
				show_prop = true
		DistributionType.PSEUDO_RANDOM:
			if prop_name == &"pseudo_c": 
				show_prop = true
		DistributionType.CUSTOM: pass
		_: 
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])

	var all_param_props = [
		&"uniform_a", &"uniform_b", 
		&"normal_mean", &"normal_std_dev", 
		&"bernoulli_p",
		&"binomial_n", &"binomial_p",
		&"poisson_lambda",
		&"exponential_lambda",
		&"geometric_p",
		&"erlang_k", &"erlang_lambda",
		&"histogram_values", &"histogram_probabilities",
		&"pseudo_c"
	]

	if prop_name in all_param_props:
		if show_prop:
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			property.usage &= ~PROPERTY_USAGE_EDITOR


func _generate_value_from_distribution() -> float:
	match distribution_type:
		DistributionType.UNIFORM:
			return randf_range(uniform_a, uniform_b)
		DistributionType.NORMAL:
			return randfn(normal_mean, normal_std_dev)
		DistributionType.BERNOULLI:
			if ProbabilityServer: return float(ProbabilityServer.randi_bernoulli(bernoulli_p))
			push_warning("Bernoulli: ProbabilityServer not found. Using basic randf().")
			return 1.0 if randf() < bernoulli_p else 0.0
		DistributionType.BINOMIAL:
			if ProbabilityServer: return float(ProbabilityServer.randi_binomial(binomial_p, binomial_n))
			push_warning("Binomial: ProbabilityServer not found.")
			return 0.0 
		DistributionType.POISSON:
			if ProbabilityServer: return float(ProbabilityServer.randi_poisson(poisson_lambda))
			push_warning("Poisson: ProbabilityServer not found.")
			return 0.0
		DistributionType.EXPONENTIAL:
			if ProbabilityServer: return float(ProbabilityServer.randf_exponential(exponential_lambda))
			push_warning("Exponential: ProbabilityServer not found.")
			return 0.0
		DistributionType.GEOMETRIC:
			if ProbabilityServer: return float(ProbabilityServer.randi_geometric(geometric_p))
			push_warning("Geometric: ProbabilityServer not found.")
			return 0.0
		DistributionType.ERLANG:
			if ProbabilityServer: return float(ProbabilityServer.randf_erlang(erlang_k, erlang_lambda))
			push_warning("Erlang: ProbabilityServer not found.")
			return 0.0
		DistributionType.HISTOGRAM:
			if ProbabilityServer and not histogram_values.is_empty() and \
			   not histogram_probabilities.is_empty() and \
			   histogram_values.size() == histogram_probabilities.size():
				return float(ProbabilityServer.randv_histogram(histogram_values, histogram_probabilities))
			push_warning("Histogram: ProbabilityServer not found or params invalid/missing.")
			return 0.0
		DistributionType.PSEUDO_RANDOM:
			if ProbabilityServer: return float(ProbabilityServer.randi_pseudo(pseudo_c))
			push_warning("PseudoRandom: ProbabilityServer not found.")
			return 0.0
		DistributionType.CUSTOM:
			if not num_map.is_empty():
				var keys = num_map.keys()
				if keys.is_empty():
					push_error("CUSTOM: empty num_map.")
					return 0.0
				return float(keys[randi() % keys.size()])
			elif not distribution_params.is_empty() and \
				"values" in distribution_params and "probabilities" in distribution_params:
				if ProbabilityServer:
					var values_arr = distribution_params.get("values", [])
					var probs_arr = distribution_params.get("probabilities", [])
					if values_arr is Array and not values_arr.is_empty() and \
					   probs_arr is Array and not probs_arr.is_empty() and \
					   values_arr.size() == probs_arr.size():
						return float(ProbabilityServer.randv_histogram(values_arr, probs_arr))
					else:
						push_error("CUSTOM (histogram-like): invalid params.")
						return 0.0
				else:
					push_warning("CUSTOM (histogram-like): ProbabilityServer not found.")
					return 0.0
			else:
				push_error("CUSTOM: no num_map or valid histogram-like distribution_params.")
				return 0.0
		_:
			push_error("Unsupported distribution type: %s" % DistributionType.keys()[distribution_type])
			return 0.0
