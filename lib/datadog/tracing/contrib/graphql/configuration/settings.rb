# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'
require_relative 'error_extension_env_parser'
require_relative 'capture_variables'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        module Configuration
          # Custom settings for the GraphQL integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            # @!visibility private
            option :analytics_enabled do |o|
              o.type :bool, nilable: true
              o.env Ext::ENV_ANALYTICS_ENABLED
            end

            option :analytics_sample_rate do |o|
              o.type :float
              o.env Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
            end

            option :schemas do |o|
              o.type :array
              o.default []
            end

            option :service_name do |o|
              o.type :string, nilable: true
            end

            option :with_deprecated_tracer do |o|
              o.type :bool
              o.default false
            end

            option :with_unified_tracer do |o|
              o.env Ext::ENV_WITH_UNIFIED_TRACER
              o.type :bool
              o.default false
            end

            # Capture error extensions provided by the user in their GraphQL error responses.
            # The extensions can be anything, so the user is responsible for ensuring they are safe to capture.
            option :error_extensions do |o|
              o.env Ext::ENV_ERROR_EXTENSIONS
              o.type :array, nilable: false
              o.default []
              o.env_parser { |v| ErrorExtensionEnvParser.call(v) }
            end

            # Surface GraphQL errors in Error Tracking.
            option :error_tracking do |o|
              o.env Ext::ENV_ERROR_TRACKING
              o.type :bool
              o.default false
            end

            # Variables to capture in GraphQL operations
            option :capture_variables do |o|
              o.env Ext::ENV_CAPTURE_VARIABLES
              o.type :array, nilable: false
              o.default []
              o.setter { |variable_tags, _| CaptureVariables.new(variable_tags) }
            end

            # Variables to exclude from capture in GraphQL operations
            option :capture_variables_except do |o|
              o.env Ext::ENV_CAPTURE_VARIABLES_EXCEPT
              o.type :array, nilable: false
              o.default []
              o.setter { |variable_tags, _| CaptureVariables.new(variable_tags) }
            end
          end
        end
      end
    end
  end
end
