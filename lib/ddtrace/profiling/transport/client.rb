module Datadog
  module Profiling
    module Transport
      # Generic interface for profiling transports
      module Client
        def send_profiling_flush(flush)
          NotImplementedError.new
        end
      end
    end
  end
end
