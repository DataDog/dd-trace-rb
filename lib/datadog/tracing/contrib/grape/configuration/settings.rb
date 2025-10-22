# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'
require_relative '../../status_range_matcher'
require_relative '../../status_range_env_parser'

module Datadog
  module Tracing
    module Contrib
      module Grape
        module Configuration
          # Custom settings for the Grape integration
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

            option :service_name

            option :on_error do |o|
              o.type :proc, nilable: true
            end

            option :error_status_codes do |o|
              o.env Ext::ENV_ERROR_STATUS_CODES
              o.setter do |value|
                if value.nil?
                  # Fallback to global config, which is defaulted to server (500..599)
                  Datadog.configuration.tracing.http_error_statuses.server
                else
                  Tracing::Contrib::StatusRangeMatcher.new(value)
                end
              end
              o.env_parser do |v|
                Tracing::Contrib::StatusRangeEnvParser.call(v) if v
              end
            end
          end
        end
      end
    end
  end
end
