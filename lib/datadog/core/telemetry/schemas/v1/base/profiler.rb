module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
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
