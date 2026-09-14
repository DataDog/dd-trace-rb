require "stringio"

module CaptureStderr
  # Returns everything written to stderr while the block runs, including
  # GitHub Actions `::error::` annotations printed by code under test:
  # letting them through makes the CI runner surface them as job annotations
  # even for passing examples.
  def capture_stderr
    stderr = StringIO.new
    original_stderr, $stderr = $stderr, stderr

    begin
      yield
    ensure
      $stderr = original_stderr
    end

    stderr.string
  end
end

RSpec.configure do |config|
  config.include CaptureStderr
end
