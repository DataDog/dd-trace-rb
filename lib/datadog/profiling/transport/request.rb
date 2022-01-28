# typed: true
require 'ddtrace/transport/request'
require 'datadog/profiling/transport/parcel'

module Datadog
  module Profiling
    module Transport
      # Profiling request
      class Request < Datadog::Transport::Request
        def initialize(flush)
          super(Parcel.new(flush))
        end
      end
    end
  end
end
