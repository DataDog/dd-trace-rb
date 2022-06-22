module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for profiler object
        class Profiler
          ERROR_NIL_VERSION_MESSAGE = ':version must not be nil'.freeze

          attr_reader :version

          # @param version [String] version of the profiler product
          def initialize(version:)
            raise ArgumentError, ERROR_NIL_VERSION_MESSAGE if version.nil?

            @version = version
          end
        end
      end
    end
  end
end
