require 'datadog/core/telemetry/schemas/utils/validation'

module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for appsec object
            class AppSec
              include Schemas::Utils::Validation

              ERROR_BAD_VERSION_MESSAGE = ':version must be a non-empty String'.freeze

              attr_reader :version

              # @param version [String] Version of the appsec product
              def initialize(version:)
                raise ArgumentError, ERROR_BAD_VERSION_MESSAGE unless valid_string?(version)

                @version = version
              end
            end
          end
        end
      end
    end
  end
end
