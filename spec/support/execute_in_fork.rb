require_relative 'platform_helpers'

# Adds support for running each RSpec examples in a forked process.
# All before/after/around hooks also run in the forked process.
# To use it, add `execute_in_fork: true` metadata to the example or example group.
# Example:
#   RSpec.describe 'My test', execute_in_fork: true do
module ForkableExample
  EXAMPLE_SENTINEL = Module.new
  MODULE_VALUE = Struct.new(:name)

  # Ensure we report the correct status code from the forked child
  def finish(reporter)
    if @metadata[:execute_in_fork] && Process.ppid != 1 # In a forked process
      # In the forked process, we signal our success/failure by the status code
      (super) ? exit(0) : exit(1)
    else
      super
    end
  end

  # The main patched method. At `RSpec::Core::Example#run`, we intercept the test run
  # as late as possible, but early enough to fork before any before/around hooks are run.
  # We have to do a bunch of inter-process communication, as RSpec uses global state
  # to communicate test successes and especially failures.
  #
  # `self.execution_result` in this method is `RSpec::Core::Example#execution_result`.
  #
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Security/MarshalLoad
  def run(example_group_instance, reporter)
    return super unless @metadata[:execute_in_fork]

    # Use a pipe to communicate between the parent and child process
    reader, writer = IO.pipe

    reader.binmode
    writer.binmode

    pid = fork do
      # Patch classes only in the forked process, as a defensive measure
      reporter.singleton_class.prepend(ForkableExample::Reporter)
      execution_result.singleton_class.prepend(ForkableExample::ExecutionResult)

      # Save the writer pipe in a convenient place
      reporter.instance_variable_set(:@fork_writer_pipe, writer)

      # Write some sentinel values to aid with Marshalling a few important objects.
      reporter.instance_variable_set(:@fork_example_sentinel, self)
      execution_result.instance_variable_set(:@fork_writer_pipe, writer)

      reader.close

      begin
        super
      ensure
        writer.close
      end
    end

    writer.close

    # Wait for forked process to finish
    _, status = Process.wait2(pid)

    # Unmarshal the test results from the forked process.
    # These come in as method calls, which we replicate here in the parent process.
    while (read_size = reader.gets) # Reads a header line, containing the size of the next object
      # Read the next object
      call = Marshal.load(reader.read(Integer(read_size)))

      args = call[:args]
      args.map! do |arg|
        # Some values are serializable, so we check for their sentinel
        if arg == EXAMPLE_SENTINEL
          self
        elsif arg.is_a?(MODULE_VALUE)
          ::Object.const_get(arg.name)
        elsif arg.is_a?(RSpec::Core::Notifications::ExampleNotification) && arg.example == EXAMPLE_SENTINEL
          ::RSpec::Core::Notifications::ExampleNotification.for(self)
        else
          arg
        end
      end

      # The receiver is a parent process object, let's find the right one
      receiver = case call[:receiver]
      when :reporter
        reporter
      when :execution_result
        execution_result
      else
        raise "Unknown receiver: #{call[:receiver]}"
      end

      receiver.send(call[:method], *args)
    end

    reader.close

    status.success? # We return the status code from the forked process as the boolean for success/failure
  ensure
    reader&.close
    writer&.close
  end

  # Patch a method in the forked process to capture its arguments.
  # We use Marshal to serialize the arguments, and write a sentinel instead when the value can't be serialized.
  # We also only capture the first method call, in a nested call chain, because in the parent process,
  # a call to the first method will trigger the nested calls naturally. Capturing nested calls causes duplicate calls
  # and failure.
  def self.patch(obj, method, receiver)
    obj.define_method(method) do |*args|
      original_args = args

      unless @fork_instrumenting # Nested calls are skipped, since they will be invoked by the first call site
        begin
          @fork_instrumenting = true

          args = args.map do |arg|
            if arg == @fork_example_sentinel
              EXAMPLE_SENTINEL
            elsif arg.is_a?(Module)
              MODULE_VALUE.new(arg.name)
            elsif arg.is_a?(::RSpec::Core::Notifications::ExampleNotification) && arg.example == @fork_example_sentinel
              ::RSpec::Core::Notifications::ExampleNotification.send(:new, EXAMPLE_SENTINEL)
            else
              arg
            end
          end

          dump = Marshal.dump({receiver: receiver, method: method, args: args})
          # Write a header hex int with the size of the next object dump
          @fork_writer_pipe.write(format("0x%x\n", dump.bytesize))
          @fork_writer_pipe.write(dump)
        end
      end

      super(*original_args)
    ensure
      @fork_instrumenting = false
    end
  end

  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Security/MarshalLoad

  # Patch the test reporter
  # We patch all methods, so we can delegate them to the same object in the parent process.
  module Reporter
    RSpec::Core::Reporter.instance_methods(false).each do |method|
      ForkableExample.patch(self, method, :reporter)
    end
  end

  # Patch the test execution result
  # We patch all methods, so we can delegate them to the same object in the parent process.
  module ExecutionResult
    # No need to patch methods ending in `?`, since they don't have side effects.
    ::RSpec::Core::Example::ExecutionResult.instance_methods(false).reject { |m| m.to_s.end_with?('?') }.each do |method|
      ForkableExample.patch(self, method, :execution_result)
    end
  end
end

RSpec::Core::Example.prepend(ForkableExample) if PlatformHelpers.supports_fork?
