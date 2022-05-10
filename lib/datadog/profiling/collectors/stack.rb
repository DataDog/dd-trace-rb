# typed: false

module Datadog
  module Profiling
    module Collectors
      # Used to gather a stack trace from a given Ruby thread. Almost all of this class is implemented as native code.
      #
      # Methods prefixed with _native_ are implemented in `collectors_stack.c`
      class Stack

        # This method exists only to enable testing Datadog::Profiling::Collectors::Stack behavior using RSpec.
        # It SHOULD NOT be used for other purposes.
        def sample(thread, recorder_instance, metric_values_hash, labels_array, max_frames: 400)
          self.class._native_sample(thread, recorder_instance, metric_values_hash, labels_array, max_frames)
        end
      end
    end
  end
end
