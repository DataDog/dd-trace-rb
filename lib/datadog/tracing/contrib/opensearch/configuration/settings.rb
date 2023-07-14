# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module OpenSearch
        module Configuration
          # Custom settings for the OpenSearch integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.type :bool
              o.env_var Ext::ENV_ENABLED
              o.default true
            end

            option :analytics_enabled do |o|
              o.type :bool
              o.env_var Ext::ENV_ANALYTICS_ENABLED
              o.default false
            end

            option :analytics_sample_rate do |o|
              o.type :float
              o.env_var Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
            end

            option :quantize, default: {}

            option :service_name do |o|
              o.type :string, nil: true
              o.env_var Ext::ENV_SERVICE_NAME
              o.setter do |value|
                Contrib::SpanAttributeSchema.fetch_service_name(
                  value,
                  Ext::DEFAULT_PEER_SERVICE_NAME
                )
              end
            end
          end
        end
      end
    end
  end
end
