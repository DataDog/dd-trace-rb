require 'ddtrace/transport/parcel'
require 'ddtrace/transport/request'

module Datadog
  module Transport
    module Traces
      # Data transfer object for trace data
      class Parcel
        include Transport::Parcel

        def count
          data.length
        end

        def encode_with(encoder)
          encoder.encode_traces(data)
        end
      end

      # Traces request
      class Request < Transport::Request
        def initialize(traces)
          super(Parcel.new(traces))
        end
      end

      # Traces response
      module Response
        attr_reader :service_rates
      end
    end
  end
end
