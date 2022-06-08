module Datadog
  module Core
    module Telemetry
      module Schemas
        module Base
          module V1
            # Describes attributes for profiler object
            class Profiler
              attr_reader :version

              def initialize(version)
                @version = version
              end
            end
          end
        end
      end
    end
  end
end
