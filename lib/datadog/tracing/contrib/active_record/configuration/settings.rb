# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'
require_relative '../utils'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        module Configuration
          # Custom settings for the ActiveRecord integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

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

            option :service_name do |o|
              o.default do
                Contrib::SpanAttributeSchema.fetch_service_name(
                  '',
                  Utils.adapter_name
                )
              end
            end
          end
        end
      end
    end
  end
end
