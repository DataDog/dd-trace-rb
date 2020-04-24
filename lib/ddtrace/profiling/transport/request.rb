require 'ddtrace/transport/request'
require 'ddtrace/profiling/transport/parcel'

module Datadog
  module Profiling
    module Transport
      # Profiling request
      class Request < Datadog::Transport::Request
        def initialize(events)
          super(Parcel.new(events))
        end
      end
    end
  end
end
