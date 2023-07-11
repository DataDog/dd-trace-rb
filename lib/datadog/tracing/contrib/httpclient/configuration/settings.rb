# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Httpclient
        module Configuration
          # Custom settings for the Httpclient integration
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

            option :distributed_tracing, default: true

            option :service_name do |o|
              o.env_var Ext::ENV_SERVICE_NAME
              o.setter do |value|
                Contrib::SpanAttributeSchema.fetch_service_name(
                  value,
                  Ext::DEFAULT_PEER_SERVICE_NAME
                )
              end
            end

            option :error_status_codes do |o|
              o.env_var Ext::ENV_ERROR_STATUS_CODES
              o.setter do |value|
                val_to_list(value, Array(400...600), comma_separated_only: false)
              end
            end

            option :split_by_domain, default: false
          end
        end
      end
    end
  end
end
