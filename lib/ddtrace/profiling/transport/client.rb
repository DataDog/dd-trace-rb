module Datadog
  module Profiling
    module Transport
      # Generic interface for profiling transports
      module Client
        include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)

        def send_profiling_flush(flush)
          raise NotImplementedError
        end
      end
    end
  end
end
