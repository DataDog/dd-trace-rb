# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        module Configuration
          # Custom settings for the GraphQL integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            option :analytics_enabled do |o|
              o.type :bool, nilable: true
              o.env Ext::ENV_ANALYTICS_ENABLED
            end

            option :analytics_sample_rate do |o|
              o.type :float
              o.env Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
            end

            option :schemas do |o|
              o.type :array, nilable: true
              o.after_set do |v|
                if v.is_a?(Array) && v.empty?
                  Datadog.logger.warn('No schema being instrumentated, because an empty array is given to option `schemas`')
                end
              end
            end

            option :service_name
          end
        end
      end
    end
  end
end
