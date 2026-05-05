# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'
require_relative '../../span_attribute_schema'

module Datadog
  module Tracing
    module Contrib
      module MongoDB
        module Configuration
          # Custom settings for the MongoDB integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            DEFAULT_QUANTIZE = {show: [:collection, :database, :operation]}.freeze

            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            # @!visibility private
            option :analytics_enabled do |o|
              o.type :bool
              o.env Ext::ENV_ANALYTICS_ENABLED
              o.default false
            end

            option :analytics_sample_rate do |o|
              o.type :float
              o.env Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
            end

            option :quantize, type: :hash, default: DEFAULT_QUANTIZE

            option :service_name do |o|
              o.type :string, nilable: true
              o.env Ext::ENV_SERVICE_NAME
              o.default { Contrib::SpanAttributeSchema.default_or_global_service_name(Ext::DEFAULT_PEER_SERVICE_NAME) }
            end

            option :peer_service do |o|
              o.type :string, nilable: true
              o.env Ext::ENV_PEER_SERVICE
            end

            # Serializes the command to JSON format, which is the desired format for the agent and Datadog UI.
            # Setting this to false is deprecated and does not have any advantages.
            option :json_command do |o|
              o.type :bool
              o.env Ext::ENV_JSON_COMMAND
              o.default false
            end
          end
        end
      end
    end
  end
end
