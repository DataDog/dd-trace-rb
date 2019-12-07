module SynchronizationHelpers
  def expect_in_fork
    read, write = IO.pipe

    pid = fork do
      read.close

      yield

      Marshal.dump(true, write)
    end

    # Wait for fork to finish, retrieve its output
    write.close
    result = read.read
    Process.wait(pid)

    # Expect fork and assertions to have completed successfully.
    # rubocop:disable Security/MarshalLoad
    expect(Marshal.load(result)).to be true
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
    return 300 if RUBY_PLATFORM == 'java'
    30
  end

  class << self
    include SynchronizationHelpers
  end
end
