require 'datadog/core/telemetry/schemas/utils/validation'
require 'datadog/core/telemetry/schemas/v1/base/product'

module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for application environment object
            class Application
              include Schemas::Utils::Validation

              ERROR_BAD_LANGUAGE_NAME_MESSAGE = ':language_name must be a non-empty String'.freeze
              ERROR_BAD_LANGUAGE_VERSION_MESSAGE = ':language_version must be a non-empty String'.freeze
              ERROR_BAD_SERVICE_NAME_MESSAGE = ':service_name must be a non-empty String'.freeze
              ERROR_BAD_TRACER_VERSION_MESSAGE = ':tracer_version must be a non-empty String'.freeze

              ERROR_BAD_ENV_MESSAGE = ':env must be of type String'.freeze
              ERROR_BAD_PRODUCTS_MESSAGE = ':products must be of type String'.freeze
              ERROR_BAD_RUNTIME_NAME_MESSAGE = ':runtime_name must be of type String'.freeze
              ERROR_BAD_RUNTIME_PATCHES_MESSAGE = ':runtime_patches must be of type String'.freeze
              ERROR_BAD_RUNTIME_VERSION_MESSAGE = ':runtime_version must be of type String'.freeze
              ERROR_BAD_SERVICE_VERSION_MESSAGE = ':service_version must be of type String'.freeze

              attr_reader \
                :env,
                :language_name,
                :language_version,
                :products,
                :runtime_name,
                :runtime_patches,
                :runtime_version,
                :service_name,
                :service_version,
                :tracer_version

              # @param env [String] Service's environment
              # @param language_name [String] 'ruby'
              # @param language_version [String] Version of language used
              # @param products [Base::Product] Contains information about specific products added to the environment
              # @param runtime_name [String] Runtime being used
              # @param runtime_patches [String] String of patches applied to the runtime
              # @param runtime_version [String] Runtime version; potentially the same as :language_version
              # @param service_name [String] Service’s name (DD_SERVICE)
              # @param service_version [String] Service’s version (DD_VERSION)
              # @param tracer_version [String] Version of the used tracer
              def initialize(language_name:, language_version:, service_name:, tracer_version:, env: nil, products: nil,
                             runtime_name: nil, runtime_patches: nil, runtime_version: nil, service_version: nil)
                validate(language_name: language_name, language_version: language_version, service_name: service_name,
                         tracer_version: tracer_version, env: env, products: products, runtime_name: runtime_name,
                         runtime_patches: runtime_patches, runtime_version: runtime_version,
                         service_version: service_version)
                @env = env
                @language_name = language_name
                @language_version = language_version
                @products = products
                @runtime_name = runtime_name
                @runtime_patches = runtime_patches
                @runtime_version = runtime_version
                @service_name = service_name
                @service_version = service_version
                @tracer_version = tracer_version
              end

              private

              # Validates all arguments passed to the class on initialization
              #
              # @!visibility private
              def validate(language_name:, language_version:, service_name:, tracer_version:, env:, products:,
                           runtime_name:, runtime_patches:, runtime_version:, service_version:)
                raise ArgumentError, ERROR_BAD_LANGUAGE_NAME_MESSAGE unless valid_string?(language_name)
                raise ArgumentError, ERROR_BAD_LANGUAGE_VERSION_MESSAGE unless valid_string?(language_version)
                raise ArgumentError, ERROR_BAD_SERVICE_NAME_MESSAGE unless valid_string?(service_name)
                raise ArgumentError, ERROR_BAD_TRACER_VERSION_MESSAGE unless valid_string?(tracer_version)
                raise ArgumentError, ERROR_BAD_PRODUCTS_MESSAGE if products && !products.is_a?(Base::Product)
                raise ArgumentError, ERROR_BAD_ENV_MESSAGE unless valid_optional_string?(env)
                raise ArgumentError, ERROR_BAD_RUNTIME_NAME_MESSAGE unless valid_optional_string?(runtime_name)
                raise ArgumentError, ERROR_BAD_RUNTIME_PATCHES_MESSAGE unless valid_optional_string?(runtime_patches)
                raise ArgumentError, ERROR_BAD_RUNTIME_VERSION_MESSAGE unless valid_optional_string?(runtime_version)
                raise ArgumentError, ERROR_BAD_SERVICE_VERSION_MESSAGE unless valid_optional_string?(service_version)
              end
            end
          end
        end
      end
    end
  end
end
