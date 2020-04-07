require 'English'

module SynchronizationHelpers
  def expect_in_fork
    # Start in fork
    pid = fork do
      yield
    end

    # Wait for fork to finish, retrieve its status.
    Process.wait(pid)
    status = $CHILD_STATUS if $CHILD_STATUS && $CHILD_STATUS.pid == pid

    # Expect fork and assertions to have completed successfully.
    expect(status && status.success?).to be true
  end

  def expect_in_thread
    # Start in thread
    t = Thread.new do
      yield
    end

    # Wait for thread to finish, retrieve its return value.
    status = t.value

    # Expect thread and assertions to have completed successfully.
    expect(status).to be true
  end

  def try_wait_until(options = {})
    attempts = options.fetch(:attempts, 10)
    backoff = options.fetch(:backoff, 0.1)

    loop do
      break if attempts <= 0 || yield(attempts)
      sleep(backoff)
      attempts -= 1
    end
  end

  def test_repeat
    # threading model is different on Java, we need to wait for a longer time
    # (like: be over 10 seconds to make sure handle the case "a flush just happened
    # a few milliseconds ago")
    return 300 if PlatformHelpers.jruby?
    30
  end

  class << self
    include SynchronizationHelpers
  end
end
