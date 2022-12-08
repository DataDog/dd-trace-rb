# typed: false

require 'English'

module SynchronizationHelpers
  def expect_in_fork(fork_expectations: nil)
    fork_expectations ||= proc { |status:, stdout:, stderr:|
      expect(status && status.success?).to be(true), "STDOUT:`#{stdout}` STDERR:`#{stderr}"
    }

    fork_stdout = Tempfile.new('ddtrace-rspec-expect-in-fork-stdout')
    fork_stderr = Tempfile.new('ddtrace-rspec-expect-in-fork-stderr')
    begin
      # Start in fork
      pid = fork do
        # Capture forked output
        $stdout.reopen(fork_stdout)
        $stderr.reopen(fork_stderr) # STDERR captures RSpec failures. We print it in case the fork fails on exit.

        yield
      end

      fork_stderr.close
      fork_stdout.close

      # Wait for fork to finish, retrieve its status.
      Process.wait(pid)
      status = $CHILD_STATUS if $CHILD_STATUS && $CHILD_STATUS.pid == pid

      # Capture forked execution information
      result = { status: status, stdout: File.read(fork_stdout.path), stderr: File.read(fork_stderr.path) }

      # Expect fork and assertions to have completed successfully.
      fork_expectations.call(**result)

      result
    ensure
      fork_stdout.unlink
      fork_stderr.unlink
    end
  end

  # Defaults to 5 second timeout
  def try_wait_until(attempts: 50, backoff: 0.1)
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

    raise('Wait time exhausted!')
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
