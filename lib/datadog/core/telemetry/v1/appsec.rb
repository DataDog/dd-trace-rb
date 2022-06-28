module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for appsec object
        class AppSec
          ERROR_NIL_VERSION_MESSAGE = ':version must not be nil'.freeze

          attr_reader :version

          # @param version [String] Version of the appsec product
          def initialize(version:)
            raise ArgumentError, ERROR_NIL_VERSION_MESSAGE if version.nil?

            @version = version
          end

          def to_h
            {
              version: @version
            }
          end
        end
      end
    end
  end
end
