require 'English'

module SynchronizationHelpers
  def expect_in_fork(fork_expectations: nil, timeout_seconds: 10, trigger_stacktrace_on_kill: false, debug: false)
    fork_expectations ||= proc { |status:, stdout:, stderr:|
      expect(status && status.success?).to be(true), "STDOUT:`#{stdout}` STDERR:`#{stderr}"
    }

    if debug
      rv = expect_in_fork_debug(fork_expectations: fork_expectations) do
        yield
      end
      return rv
    end

    fork_stdout = Tempfile.new('datadog-rspec-expect-in-fork-stdout')
    fork_stderr = Tempfile.new('datadog-rspec-expect-in-fork-stderr')
    begin
      # Start in fork
      pid = fork do
        # Capture forked output
        $stdout.reopen(fork_stdout)
        $stdout.sync = true
        $stderr.reopen(fork_stderr) # STDERR captures RSpec failures. We print it in case the fork fails on exit.
        $stderr.sync = true

        yield
      end

      # Wait for fork to finish, retrieve its status.
      # Enforce timeout to ensure test fork doesn't hang the test suite.
      _, status = try_wait_until(seconds: timeout_seconds) { Process.wait2(pid, Process::WNOHANG) }

      stdout = File.read(fork_stdout.path)
      stderr = File.read(fork_stderr.path)

      puts 'in child:'
      puts stdout
      puts stderr

      # Capture forked execution information
      result = {status: status, stdout: stdout, stderr: stderr}

      # Expect fork and assertions to have completed successfully.
      fork_expectations.call(**result)

      result
    rescue => e
      crash_note = nil

      if trigger_stacktrace_on_kill
        crash_note = ' (Crashing Ruby to get stacktrace as requested by `trigger_stacktrace_on_kill`)'
        begin
          Process.kill('SEGV', pid)
          warn "Waiting for child process to exit after SEGV signal... #{crash_note}"
          Process.wait(pid)
        rescue
          nil
        end
      end

      stdout = File.read(fork_stdout.path)
      stderr = File.read(fork_stderr.path)

      raise "Failure or timeout in `expect_in_fork`#{crash_note}, STDOUT: `#{stdout}`, STDERR: `#{stderr}`", cause: e
    ensure
      begin
        Process.kill('KILL', pid)
      rescue
        nil
      end # Prevent zombie processes on failure

      fork_stderr.close
      fork_stdout.close
      fork_stdout.unlink
      fork_stderr.unlink
    end
  end

  # Debug version of expect_in_fork that does not redirect I/O streams and
  # has no timeout on execution. The idea is to use it for interactive
  # debugging where you would set a break point in the fork.
  def expect_in_fork_debug(fork_expectations:, timeout_seconds: 10, trigger_stacktrace_on_kill: false)
    pid = fork do
      yield
    end
    _, status = Process.wait2(pid)
    fork_expectations.call(status: status, stdout: '', stderr: '')
  end

  # Waits for the condition provided by the block argument to return truthy.
  #
  # Waits for 5 seconds by default.
  #
  # Can be configured by setting either:
  #   * `seconds`, or
  #   * `attempts` and `backoff`
  #
  # @yieldreturn [Boolean] block executed until it returns truthy
  # @param [Numeric] seconds number of seconds to wait
  # @param [Integer] attempts number of attempts at checking the condition
  # @param [Numeric] backoff wait time between condition checking attempts
  def try_wait_until(seconds: nil, attempts: nil, backoff: nil)
    raise 'Provider either `seconds` or `attempts` & `backoff`, not both' if seconds && (attempts || backoff)

    spec = if seconds
      "#{seconds} seconds"
    elsif attempts || backoff
      "#{attempts} attempts with backoff: #{backoff}"
    else
      'none'
    end

    if seconds
      attempts = seconds * 10
      backoff = 0.1
    else
      # 5 seconds by default, but respect the provide values if any.
      attempts ||= 50
      backoff ||= 0.1
    end

    start_time = Datadog::Core::Utils::Time.get_time

    # It's common for tests to want to run simple tasks in a background thread
    # but call this method without the thread having even time to start.
    #
    # We add an extra attempt, interleaved by `Thread.pass`, in order to allow for
    # those simple cases to quickly succeed without a timed `sleep` call. This will
    # save simple test one `backoff` seconds sleep cycle.
    #
    # The total configured timeout is not reduced.
    (attempts + 1).times do |i|
      result = yield(attempts)
      return result if result

      if i == 0
        Thread.pass
      else
        sleep(backoff)
      end
    end

    elapsed = Datadog::Core::Utils::Time.get_time - start_time
    actual = "#{"%.2f" % elapsed} seconds, #{attempts} attempts with backoff #{backoff}" # rubocop:disable Style/FormatString

    raise("Wait time exhausted! Requested: #{spec}, waited: #{actual}")
  end

  def test_repeat
    # threading model is different on Java, we need to wait for a longer time
    # (like: be over 10 seconds to make sure handle the case "a flush just happened
    # a few milliseconds ago")
    return 300 if PlatformHelpers.jruby?

    30
  end

  singleton_class.include SynchronizationHelpers
end
