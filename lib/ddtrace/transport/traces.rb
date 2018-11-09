require 'ddtrace/transport/parcel'

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
    end
  end
end
