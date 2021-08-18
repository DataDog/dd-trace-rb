# typed: false
require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/grpc/ext'

module Datadog
  module Contrib
    module GRPC
      module Configuration
        # Custom settings for the gRPC integration
        class Settings < Contrib::Configuration::Settings
          # Users may pass sensitive Info via metadata such as 'authorization' that they wish to exclude
          # https://github.com/grpc/grpc-go/blob/1c598a11a4e503e1cfd500999c040e72072dc16b/credentials/oauth/oauth.go#L50
          DEFAULT_METADATA = {
            server: {
              exclude: []
            },
            client: {
              exclude: []
            }
          }.freeze

          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float([Ext::ENV_ANALYTICS_SAMPLE_RATE, Ext::ENV_ANALYTICS_SAMPLE_RATE_OLD], 1.0) }
            o.lazy
          end

          option :service_name, default: Ext::SERVICE_NAME
          option :error_handler, default: Datadog::Tracer::DEFAULT_ON_ERROR
          option :metadata, default: DEFAULT_METADATA
        end
      end
    end
  end
end
