# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Rack
        module Configuration
          # Custom settings for the Rack integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            DEFAULT_HEADERS = {
              response: %w[
                Content-Type
                X-Request-ID
              ]
            }.freeze

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

            option :application
            option :distributed_tracing do |o|
              o.type :bool
              o.env Ext::ENV_DISTRIBUTED_TRACING
              o.default true
            end

            option :headers do |o|
              o.type :hash
              o.env Ext::ENV_HEADERS
              o.default DEFAULT_HEADERS
              o.env_parser { |value| Core::Configuration::Option.parse_json_env(value) }
            end

            option :middleware_names do |o|
              o.type :bool
              o.env Ext::ENV_MIDDLEWARE_NAMES
              o.default false
            end

            option :quantize do |o|
              o.type :hash
              o.env Ext::ENV_QUANTIZE
              o.default({})
              o.env_parser { |value| parse_quantize_env(value) }
            end

            option :request_queuing do |o|
              o.type :bool
              o.env Ext::ENV_REQUEST_QUEUING
              o.default false
            end

            option :service_name do |o|
              o.type :string, nilable: true
              o.env Ext::ENV_SERVICE_NAME
            end

            option :web_service_name do |o|
              o.type :string
              o.env Ext::ENV_WEB_SERVICE_NAME
              o.default Ext::DEFAULT_PEER_WEBSERVER_SERVICE_NAME
            end
          end
        end
      end
    end
  end
end
