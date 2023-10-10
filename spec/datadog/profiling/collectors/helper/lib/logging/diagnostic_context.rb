# This file is used by the `thread_context_spec.rb`. It's used to simulate the file from the `logging` gem on the same
# partial path. See that file for more details.

# rubocop:disable Style/GlobalVars

$simulated_logging_gem_monkey_patched_thread_ready_queue = Queue.new
$simulated_logging_gem_monkey_patched_thread = Thread.start do
  $simulated_logging_gem_monkey_patched_thread_ready_queue << true
  sleep
end

# rubocop:enable Style/GlobalVars
