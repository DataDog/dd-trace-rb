require 'datadog/core/telemetry/schemas/utils/validation'

module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for dependency object
            class Dependency
              include Schemas::Utils::Validation

              ERROR_BAD_NAME_MESSAGE = ':name must be a non-empty String'.freeze
              ERROR_BAD_VERSION_MESSAGE = ':version must be of type String'.freeze
              ERROR_BAD_HASH_MESSAGE = ':hash must be of type String'.freeze

              attr_reader \
                :hash,
                :name,
                :version

              # @param name [String] Module name
              # @param version [String] Version of resolved module
              # @param hash [String] Dependency hash
              def initialize(name:, version: nil, hash: nil)
                validate(name: name, version: version, hash: hash)
                @hash = hash
                @name = name
                @version = version
              end

              private

              # Validates all arguments passed to the class on initialization
              #
              # @!visibility private
              def validate(name:, version:, hash:)
                raise ArgumentError, ERROR_BAD_NAME_MESSAGE unless valid_string?(name)
                raise ArgumentError, ERROR_BAD_VERSION_MESSAGE unless valid_optional_string?(version)
                raise ArgumentError, ERROR_BAD_HASH_MESSAGE unless valid_optional_string?(hash)
              end
            end
          end
        end
      end
    end
  end
end
