module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for integration object
            class Integration
              attr_reader \
                :auto_enabled,
                :compatible,
                :enabled,
                :error,
                :name,
                :version

              def initialize(enabled:, name:, auto_enabled: nil, compatible: nil, error: nil, version: nil)
                @auto_enabled = auto_enabled
                @compatible = compatible
                @enabled = enabled
                @error = error
                @name = name
                @version = version
              end
            end
          end
        end
      end
    end
  end
end
