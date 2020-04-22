require 'ddtrace/buffer'

module Datadog
  module Profiling
    # Profiling buffer that stores profiling events. The buffer has a maximum size and when
    # the buffer is full, a random event is discarded. This class is thread-safe.
    class Buffer < Datadog::Buffer; end
  end
end
