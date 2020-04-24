require 'ddtrace/transport/parcel'
require 'ddtrace/transport/request'

module Datadog
  module Transport
    module Traces
      # Data transfer object for trace data
      class Parcel
        include Transport::Parcel

        attr_reader :trace_count

        def initialize(data, trace_count)
          super(data)
          @trace_count = trace_count
        end

        def count
          data.length
        end
      end

      # Traces request
      class Request < Transport::Request
        def initialize(data, trace_count)
          super(Parcel.new(data, trace_count))
        end
      end

      # Traces response
      module Response
        attr_reader :service_rates, :trace_count
      end
    end
  end
end
