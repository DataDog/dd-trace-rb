module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for dependency object
            class Dependency
              attr_reader \
                :hash,
                :name,
                :version

              def initialize(name:, version:, hash: nil)
                @hash = hash
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
