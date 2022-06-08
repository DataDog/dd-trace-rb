module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for products object
            class Product
              attr_reader \
                :appsec,
                :profiler

              def initialize(appsec: nil, profiler: nil)
                @appsec = appsec
                @profiler = profiler
              end
            end
          end
        end
      end
    end
  end
end
