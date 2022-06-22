module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for dependency object
        class Dependency
          ERROR_NIL_NAME_MESSAGE = ':name must not be nil'.freeze

          attr_reader \
            :hash,
            :name,
            :version

          # @param name [String] Module name
          # @param version [String] Version of resolved module
          # @param hash [String] Dependency hash
          def initialize(name:, version: nil, hash: nil)
            raise ArgumentError, ERROR_NIL_NAME_MESSAGE if name.nil?

            @hash = hash
            @name = name
            @version = version
          end
        end
      end
    end
  end
end
