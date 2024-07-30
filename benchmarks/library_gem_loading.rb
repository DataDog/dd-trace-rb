require_relative 'lib/boot_basic'

require 'open3'

# This benchmark needs to be run in a clean environment where datadog is
# not loaded yet.
#
# Now that this benchmark is in its own file, it does not need
# to spawn a subprocess IF we would always execute this benchmark
# file by itself.
BasicBenchmarker.define(__FILE__) do
  before do
    if defined?(::Datadog::Core)
      raise "Datadog is already defined, this benchmark must be run in a clean environment"
    end
  end

  benchmark 'gem loading', time: 60 do
    pid = fork { require 'datadog' }

    _, status = Process.wait2(pid)
    raise unless status.success?
  end
end
