# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module ActiveSupport
        module Configuration
          # Custom settings for the ActiveSupport integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.env_var Ext::ENV_ENABLED
              o.default true
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_enabled do |o|
              o.env_var Ext::ENV_ANALYTICS_ENABLED
              o.default false
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_sample_rate do |o|
              o.env_var Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
              o.setter do |value|
                val_to_float(value)
              end
            end

            option :cache_service do |o|
              o.default do
                Contrib::SpanAttributeSchema.fetch_service_name(
                  '',
                  Ext::SERVICE_CACHE
                )
              end
            end
          end
        end
      end
    end
  end
end
