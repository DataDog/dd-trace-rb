# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # AWS Lambda Runtime Interface Client integration.
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new("1.0.0")

          # @public_api Changing the integration name or integration options can cause breaking changes.
          register_as :aws_lambda_ric, auto_patch: true

          def self.version
            loaded_version = Gem.loaded_specs["aws_lambda_ric"]&.version
            return loaded_version if loaded_version
            return unless defined?(::AwsLambdaRIC::VERSION)

            Gem::Version.new(::AwsLambdaRIC::VERSION)
          rescue ArgumentError
            nil
          end

          def self.loaded?
            !!(defined?(::LambdaHandler) && ::LambdaHandler.instance_methods.include?(:call_handler))
          end

          def self.available?
            loaded? || super
          end

          def self.compatible?
            return false unless available?

            version.nil? || version >= MINIMUM_VERSION
          end

          def self.lambda_environment?
            DATADOG_ENV.key?("AWS_LAMBDA_RUNTIME_API")
          end

          def self.synchronous_writer?(settings)
            lambda_environment? && settings.tracing.instrumented_integrations.key?(:aws_lambda_ric)
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
