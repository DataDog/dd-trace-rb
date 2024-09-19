# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'
require_relative '../../span_attribute_schema'

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Configuration
          # Custom settings for the AWS integration
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

            option :service_name do |o|
              o.type :string, nilable: true
              o.default do
                Contrib::SpanAttributeSchema.fetch_service_name(
                  Ext::ENV_SERVICE_NAME,
                  Ext::DEFAULT_PEER_SERVICE_NAME
                )
              end
            end

            option :peer_service do |o|
              o.type :string, nilable: true
              o.env Ext::ENV_PEER_SERVICE
            end

            # Enables distributed trace propagation for SNS and SQS messages.
            # @default `DD_TRACE_AWS_PROPAGATION_ENABLED` environment variable, otherwise `false`
            # @return [Boolean]
            option :propagation do |o|
              o.type :bool
              o.env Ext::ENV_PROPAGATION_ENABLED
              o.default false
            end

            # Controls whether the local trace is parented to the SQS message consumed.
            # Possible values are:
            # `local`: The local active trace is used; SNS has no effect on trace parentage.
            # `distributed`: The local active trace becomes a child of the propagation context from the SQS message.
            #
            # This option is always disable (the equivalent to`local`) if `propagation` is disabled.
            # @default `DD_TRACE_AWS_TRACE_PARENTAGE_STYLE` environment variable, otherwise `local`
            # @return [String]
            option :parentage_style do |o|
              o.type :string
              o.env Ext::ENV_TRACE_PARENTAGE_STYLE
              o.default 'distributed'
            end
          end
        end
      end
    end
  end
end
