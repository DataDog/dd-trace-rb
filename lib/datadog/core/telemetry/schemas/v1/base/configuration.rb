module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for additional payload or configuration object
            class Configuration
              attr_reader \
                :name,
                :value

              def initialize(name:, value: nil)
                @name = name
                @value = value
              end
            end
          end
        end
      end
    end
  end
end
