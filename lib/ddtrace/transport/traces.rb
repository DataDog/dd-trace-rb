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
      end

      # Traces request
      class Request < Transport::Request
        def initialize(data, trace_count, content_type)
          super(Parcel.new(data), trace_count, content_type)
        end
      end

      # Traces response
      module Response
        attr_reader :service_rates, :trace_count
      end
    end
  end
end
