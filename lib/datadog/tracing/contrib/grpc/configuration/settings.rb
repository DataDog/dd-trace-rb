# typed: false

require 'datadog/tracing/span_operation'
require 'datadog/tracing/contrib/configuration/settings'
require 'datadog/tracing/contrib/grpc/ext'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Configuration
          # Custom settings for the gRPC integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
              o.lazy
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
              o.lazy
            end

            option :distributed_tracing, default: true
            option :service_name, default: Ext::DEFAULT_PEER_SERVICE_NAME
            option :error_handler, default: Tracing::SpanOperation::Events::DEFAULT_ON_ERROR
          end
        end
      end
    end
  end
end
