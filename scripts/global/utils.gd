extends Node


func generate_run_id() -> String:
	var time_dict = Time.get_time_dict_from_system()
	var time_str = "%02d:%02d" % [time_dict.hour, time_dict.minute]
	var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var random_code = ""
	for _i in range(4):
		random_code += chars[randi() % chars.length()]
	
	return "%s_%s" % [time_str, random_code] 

func deduplicate_array(arr:Array) -> Array:
	var deduped_array: Array = []
	var seen: Dictionary = {}
	for element in arr:
		if not seen.has(element):
			seen[element] = true
			deduped_array.append(element)	
	return deduped_array