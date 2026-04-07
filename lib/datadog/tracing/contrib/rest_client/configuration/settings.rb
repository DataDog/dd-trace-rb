# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'
require_relative '../../span_attribute_schema'

module Datadog
  module Tracing
    module Contrib
      module RestClient
        module Configuration
          # Custom settings for the RestClient integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
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

            option :distributed_tracing do |o|
              o.type :bool
              o.env Ext::ENV_DISTRIBUTED_TRACING
              o.default true
            end
            option :service_name do |o|
              o.env Ext::ENV_SERVICE_NAME
              o.default Contrib::SpanAttributeSchema.default_or_global_service_name(Ext::DEFAULT_PEER_SERVICE_NAME)
            end

            option :peer_service do |o|
              o.type :string, nilable: true
              o.env Ext::ENV_PEER_SERVICE
            end

            option :split_by_domain, default: false, type: :bool
          end
        end
      end
    end
  end
end
