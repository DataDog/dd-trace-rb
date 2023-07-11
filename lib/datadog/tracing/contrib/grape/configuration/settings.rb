# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'
require_relative '../../status_code_matcher'

module Datadog
  module Tracing
    module Contrib
      module Grape
        module Configuration
          # Custom settings for the Grape integration
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
              o.setter do |value|
                val_to_bool(value) if value
              end
            end

            option :analytics_sample_rate do |o|
              o.env_var Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
              o.setter do |value|
                val_to_float(value)
              end
            end

            option :service_name

            option :error_statuses, default: nil do |o|
              o.setter do |new_value, _old_value|
                Contrib::StatusCodeMatcher.new(new_value) unless new_value.nil?
              end
            end
          end
        end
      end
    end
  end
end
