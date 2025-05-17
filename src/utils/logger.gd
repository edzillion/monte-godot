# res://src/utils/logger.gd
# class_name Logger # Not making it a class_name initially, to be used as an autoload
extends Node

## @brief A custom logger for the MonteGodot library.
## Designed to handle logging from multiple threads by buffering log messages
## per thread and then flushing them to the main Godot log/console.
## This script is intended to be used as an Autoload (singleton).

enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR,
	CRITICAL
}

#region Properties
var min_log_level: LogLevel = LogLevel.INFO

# For threaded logging - not fully implemented in this initial version
var thread_log_buffer: Dictionary = {} # {thread_id: Array[Dictionary]}
var main_thread_buffer: Array[Dictionary] = [] # For logs from the main thread
var buffer_mutex: Mutex = Mutex.new()
#endregion


#region Static Methods (Convenience wrappers if Autoloaded)
static func debug(message: String, context: Dictionary = {}) -> void:
	if Logger:
		Logger.log_message(LogLevel.DEBUG, message, context)
	else:
		print("[DEBUG] (Logger not ready): %s" % message)

static func info(message: String, context: Dictionary = {}) -> void:
	if Logger:
		Logger.log_message(LogLevel.INFO, message, context)
	else:
		print("[INFO] (Logger not ready): %s" % message)

static func warning(message: String, context: Dictionary = {}) -> void:
	if Logger:
		Logger.log_message(LogLevel.WARNING, message, context)
	else:
		push_warning("(Logger not ready): %s" % message)

static func error(message: String, context: Dictionary = {}) -> void:
	if Logger:
		Logger.log_message(LogLevel.ERROR, message, context)
	else:
		push_error("(Logger not ready): %s" % message)

static func critical(message: String, context: Dictionary = {}) -> void:
	if Logger:
		Logger.log_message(LogLevel.CRITICAL, message, context)
	else:
		push_error("(CRITICAL - Logger not ready): %s" % message)
#endregion


#region Core Logging Methods
func log_message(level: LogLevel, message: String, context: Dictionary = {}) -> void:
	if level < min_log_level:
		return

	var timestamp: String = Time.get_datetime_string_from_system(false, true) # UTC, include milliseconds
	var log_entry: Dictionary = {
		"timestamp": timestamp,
		"level": LogLevel.keys()[level],
		"message": message,
		"context": context,
		"thread_id": OS.get_thread_caller_id() # Correctly get current thread ID
	}

	# Basic immediate logging for now. Thread buffering to be fleshed out.
	_immediate_print(log_entry)


## @brief Immediately prints the log entry to the console.
## This will be replaced/augmented by buffer flushing logic.
func _immediate_print(log_entry: Dictionary) -> void:
	var level_str: String = log_entry["level"]
	var msg_str: String = log_entry["message"]
	var context_str: String = "" # TODO: Format context dictionary
	if not log_entry["context"].is_empty():
		context_str = " | Context: %s" % str(log_entry["context"])

	var formatted_message: String = "[%s] [%s] (Thread: %s) %s%s" % [
		log_entry["timestamp"],
		level_str,
		log_entry["thread_id"],
		msg_str,
		context_str
	]

	match log_entry["level"]:
		"DEBUG":
			print(formatted_message)
		"INFO":
			print(formatted_message)
		"WARNING":
			push_warning(formatted_message)
		"ERROR":
			push_error(formatted_message)
		"CRITICAL":
			push_error("CRITICAL: " + formatted_message)
		_: # Default to print for any other unforeseen level
			print(formatted_message)
#endregion


#region Threaded Logging (Conceptual - needs more work)
# func _process(_delta: float) -> void:
# 	# Periodically flush buffered logs from other threads
# 	flush_thread_buffers()

# func buffer_log_from_thread(log_entry: Dictionary) -> void:
# 	buffer_mutex.lock()
# 	var thread_id = log_entry["thread_id"]
# 	if not thread_log_buffer.has(thread_id):
# 		thread_log_buffer[thread_id] = []
# 	thread_log_buffer[thread_id].append(log_entry)
# 	buffer_mutex.unlock()

# func flush_thread_buffers() -> void:
# 	buffer_mutex.lock()
# 	var all_buffers = thread_log_buffer.duplicate()
# 	thread_log_buffer.clear()
# 	buffer_mutex.unlock()

# 	for thread_id in all_buffers:
# 		for entry in all_buffers[thread_id]:
# 			_immediate_print(entry)
#endregion 