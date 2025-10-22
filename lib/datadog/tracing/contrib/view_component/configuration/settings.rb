# frozen_string_literal: true

require 'datadog/tracing/configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module ViewComponent
        module Configuration
          # Custom settings for the ViewComponent integration
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

            option :service_name
            option :component_base_path do |o|
              o.type :string
              o.default 'components/'
            end

            option :use_deprecated_instrumentation_name do |o|
              o.type :bool
              o.default false
            end
          end
        end
      end
    end
  end
end
