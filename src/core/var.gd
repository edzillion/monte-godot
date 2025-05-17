# res://src/core/var.gd
class_name Var extends RefCounted

## @brief Abstract base class for all variables (input and output).
##
## Serves as the foundation for InVar and OutVar, defining common properties
## and methods related to simulation variables.

#region Properties
var id: StringName ## Unique identifier for the variable.
var name: String ## User-friendly name for the variable.
var description: String ## A more detailed description of what the variable represents.
var units: String ## Units of measurement for the variable, if applicable.
#endregion


#region Initialization
func _init(p_id: StringName = &"", p_name: String = "", p_description: String = "", p_units: String = "") -> void:
	id = p_id
	name = p_name
	description = p_description
	units = p_units
#endregion
 
