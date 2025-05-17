# res://tests/utils/logger_test.gd
class_name LoggerTest extends GdUnitTestSuite

const Logger = preload("res://src/utils/logger.gd") # Preload for enum access
var logger_instance # To hold Engine.get_singleton("Logger")

func before_test() -> void:
	logger_instance = Engine.get_singleton("Logger")
	# Reset min_log_level before each test to ensure consistency
	logger_instance.min_log_level = Logger.LogLevel.INFO

func test_log_level_filtering_info_default() -> void:
	# Default min_log_level is INFO
	# DEBUG should be ignored
	# INFO, WARNING, ERROR, CRITICAL should be logged

	# Spy on _immediate_print to see if it's called
	var spy = spy_on(logger_instance, "_immediate_print")

	logger_instance.log_message(Logger.LogLevel.DEBUG, "Test Debug Message")
	assert_not_called(spy) # DEBUG < INFO

	spy.reset()
	logger_instance.log_message(Logger.LogLevel.INFO, "Test Info Message")
	assert_called_once(spy)
	var args_info = spy.last_signal_args()
	assert_str(args_info[0]["level"]).is_equal("INFO")
	assert_str(args_info[0]["message"]).is_equal("Test Info Message")

	# For WARNING, ERROR, CRITICAL, we can also test for Godot's built-in signals
	spy.reset()
	assert_warning_emitted(func(): logger_instance.log_message(Logger.LogLevel.WARNING, "Test Warning"), "[WARNING] (Thread: %s) Test Warning" % OS.get_thread_caller_id(), [], true) # Partial match for formatted msg
	# Check if _immediate_print was still called
	assert_called_once(spy)
	var args_warn = spy.last_signal_args()
	assert_str(args_warn[0]["level"]).is_equal("WARNING")

	spy.reset()
	assert_error_emitted(func(): logger_instance.log_message(Logger.LogLevel.ERROR, "Test Error"), "[ERROR] (Thread: %s) Test Error" % OS.get_thread_caller_id(), [], true) # Partial match
	assert_called_once(spy)
	var args_error = spy.last_signal_args()
	assert_str(args_error[0]["level"]).is_equal("ERROR")

	spy.reset()
	# For CRITICAL, the timestamp makes exact matching hard. Focus on key parts.
	# Expected format: "CRITICAL: [%s] [CRITICAL] (Thread: %s) %s%s"
	var critical_msg_body = "Test Critical"
	var expected_critical_substring = "CRITICAL: " # Start of the message
	var expected_critical_substring2 = "[CRITICAL] (Thread: %s) %s" % [OS.get_thread_caller_id(), critical_msg_body]
	
	var callable_crit = func(): logger_instance.log_message(Logger.LogLevel.CRITICAL, critical_msg_body)
	assert_error_emitted(callable_crit)
	# To verify further, one might need to capture stdout/stderr if possible, or trust the spy.
	# For now, assert_error_emitted confirms push_error was called. We also check the spy.

	assert_called_once(spy)
	var args_crit = spy.last_signal_args()
	assert_str(args_crit[0]["level"]).is_equal("CRITICAL")


func test_set_min_log_level() -> void:
	var spy = spy_on(logger_instance, "_immediate_print")

	logger_instance.min_log_level = Logger.LogLevel.WARNING

	logger_instance.log_message(Logger.LogLevel.DEBUG, "Debug Post Change")
	logger_instance.log_message(Logger.LogLevel.INFO, "Info Post Change")
	assert_not_called(spy) # Both DEBUG and INFO are < WARNING

	spy.reset()
	logger_instance.log_message(Logger.LogLevel.WARNING, "Warning Post Change")
	assert_called_once(spy)
	var args_warn = spy.last_signal_args()
	assert_str(args_warn[0]["level"]).is_equal("WARNING")
	assert_str(args_warn[0]["message"]).is_equal("Warning Post Change")

	# Test setting it back down
	logger_instance.min_log_level = Logger.LogLevel.DEBUG
	spy.reset()
	logger_instance.log_message(Logger.LogLevel.DEBUG, "Debug After Lowering Level")
	assert_called_once(spy)
	var args_debug = spy.last_signal_args()
	assert_str(args_debug[0]["level"]).is_equal("DEBUG")


func test_static_methods_call_instance_log_message() -> void:
	# We'll spy on the instance method log_message to verify static methods call it
	var spy_log_message = spy_on(logger_instance, "log_message")

	Logger.debug("Static Debug")
	assert_called_with(spy_log_message, [Logger.LogLevel.DEBUG, "Static Debug", {}])

	spy_log_message.reset()
	Logger.info("Static Info", {"user": "test"})
	assert_called_with(spy_log_message, [Logger.LogLevel.INFO, "Static Info", {"user": "test"}])

	spy_log_message.reset()
	Logger.warning("Static Warning")
	assert_called_with(spy_log_message, [Logger.LogLevel.WARNING, "Static Warning", {}])

	spy_log_message.reset()
	Logger.error("Static Error")
	assert_called_with(spy_log_message, [Logger.LogLevel.ERROR, "Static Error", {}])

	spy_log_message.reset()
	Logger.critical("Static Critical")
	assert_called_with(spy_log_message, [Logger.LogLevel.CRITICAL, "Static Critical", {}])


func test_log_message_format_and_context() -> void:
	var spy = spy_on(logger_instance, "_immediate_print")
	logger_instance.min_log_level = Logger.LogLevel.DEBUG # Ensure it logs

	var context_data: Dictionary = {"module": "TestModule", "value": 123}
	logger_instance.log_message(Logger.LogLevel.INFO, "Contextual Message", context_data)

	assert_called_once(spy)
	var log_entry: Dictionary = spy.last_signal_args()[0]

	assert_true(log_entry.has("timestamp"))
	assert_str(log_entry["level"]).is_equal("INFO")
	assert_str(log_entry["message"]).is_equal("Contextual Message")
	assert_dict(log_entry["context"]).is_equal(context_data)
	assert_true(log_entry.has("thread_id"))
	# We can't easily check exact timestamp, but check it's a string
	assert_str(log_entry["timestamp"]).is_not_empty()

	# Test that the formatted message from _immediate_print includes context if present
	# by checking the emitted warning/error for a message with context.
	logger_instance.min_log_level = Logger.LogLevel.WARNING
	var warning_msg_with_ctx := "Warning with context"
	var warning_ctx := {"detail": "extra info"}
	# Expected format by _immediate_print: "[%s] [%s] (Thread: %s) %s | Context: %s"
	# We are checking against push_warning's output, which prepends its own stuff potentially.
	# The actual string in push_warning will be: "[TIMESTAMP_REMOVED_FOR_TEST] [WARNING] (Thread: ...) MSG | Context: ..."
	var expected_warning_content = "[WARNING] (Thread: %s) %s | Context: %s" % [OS.get_thread_caller_id(), warning_msg_with_ctx, str(warning_ctx)]
	
	assert_warning_emitted(func(): logger_instance.log_message(Logger.LogLevel.WARNING, warning_msg_with_ctx, warning_ctx), expected_warning_content, [], true)

