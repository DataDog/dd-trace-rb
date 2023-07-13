# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Faraday
        module Configuration
          # Custom settings for the Faraday integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            DEFAULT_ERROR_HANDLER = lambda do |env|
              Tracing::Metadata::Ext::HTTP::ERROR_RANGE.cover?(env[:status])
            end

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

            option :distributed_tracing, default: true, type: :bool
            option :error_handler, type: :proc, experimental_default_proc: DEFAULT_ERROR_HANDLER
            option :split_by_domain, default: false, type: :bool

            option :service_name do |o|
              o.type :string, additional_types: [:nil]
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
