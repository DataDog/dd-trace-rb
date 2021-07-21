module Datadog
  module Profiling
    module Pprof
      # Pprof output data.
      # Includes encoded data and list of types.
      Payload = Struct.new(:data, :types) do
        def initialize(data, types)
          super
          self.types = types || []
        end

        def to_s
          data
        end
      end
    end
  end
end
