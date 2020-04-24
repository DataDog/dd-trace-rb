require 'ddtrace/transport/io/response'
require 'ddtrace/profiling/transport/response'

module Datadog
  module Profiling
    module Transport
      # IO transport behavior for profiling
      module IO
        # Response from IO transport for profiling
        class Response < Datadog::Transport::IO::Response
          include Profiling::Transport::Response
        end
      end
    end
  end
end
