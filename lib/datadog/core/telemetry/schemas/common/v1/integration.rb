module Datadog
  module Core
    module Telemetry
      module Schemas
        module Common
          module V1
            # Describes attributes for integration object
            class Integration
              attr_reader :name, :enabled, :version, :auto_enabled, :compatible, :error

              def initialize(name, enabled, version = nil, auto_enabled = nil, compatible = nil, error = nil)
                @name = name
                @enabled = enabled
                @version = version
                @auto_enabled = auto_enabled
                @compatible = compatible
                @error = error
              end
            end
          end
        end
      end
    end
  end
end
