require 'ddtrace/transport/parcel'

module Datadog
  module Profiling
    module Transport
      # Data transfer object for profiling data
      class Parcel
        include Datadog::Transport::Parcel

        def encode_with(encoder)
          # TODO: Determine encoding behavior
          encoder.encode(data)
        end
      end
    end
  end
end
