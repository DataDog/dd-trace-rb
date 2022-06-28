module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for products object
        class Product
          attr_reader \
            :appsec,
            :profiler

          # @param appsec [Telemetry::V1::AppSec] Holds custom information about the appsec product
          # @param profiler [Telemetry::V1::Profiler] Holds custom information about the profiler product
          def initialize(appsec: nil, profiler: nil)
            @appsec = appsec
            @profiler = profiler
          end

          def to_h
            {
              appsec: @appsec.to_h,
              profiler: @profiler.to_h
            }
          end
        end
      end
    end
  end
end
