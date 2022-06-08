module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for dependency object
            class Dependency
              attr_reader :name, :version, :hash

              def initialize(name:, version:, hash: nil)
                @name = name
                @version = version
                @hash = hash
              end
            end
          end
        end
      end
    end
  end
end
