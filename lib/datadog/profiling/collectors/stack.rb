# typed: false

module Datadog
  module Profiling
    module Collectors
      # Used to gather a stack trace from a given Ruby thread
      # Methods prefixed with _native_ are implemented in `collectors_stack.c`
      class Stack
        def sample(thread, recorder_instance, metric_values_hash, labels_array, max_frames: 400)
          self.class._native_sample(thread, recorder_instance, metric_values_hash, labels_array, max_frames)
        end
      end
    end
  end
end
