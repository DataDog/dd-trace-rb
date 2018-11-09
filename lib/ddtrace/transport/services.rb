require 'ddtrace/transport/parcel'

module Datadog
  module Transport
    module Services
      # Data transfer object for service data
      class Parcel
        include Transport::Parcel

        def count
          data.size
        end

        def encode_with(encoder)
          encoder.encode_services(data)
        end
      end
    end
  end
end
