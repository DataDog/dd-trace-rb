# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Faraday
        # Patcher for Faraday
        module Patcher
          def self.patched?
            Patcher.instance_variable_get(:@patched)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            require_relative "ssrf_detection_middleware"
            require_relative "connection_patch"
            require_relative "rack_builder_patch"

            ::Faraday::Middleware.register_middleware(datadog_appsec: SSRFDetectionMiddleware)
            configure_default_faraday_connection

            Patcher.instance_variable_set(:@patched, true)
          end

          def self.configure_default_faraday_connection
            if target_version&.>= Gem::Version.new("1.0.0")
              # Patch the default connection (e.g. +Faraday.get+)
              ::Faraday.default_connection.use(:datadog_appsec)

              # Patch new connection instances (e.g. +Faraday.new+)
              ::Faraday::Connection.prepend(ConnectionPatch)
            else
              # Patch the default connection (e.g. +Faraday.get+)
              #
              # We insert our middleware before the 'adapter', which is
              # always the last handler.
              idx = ::Faraday.default_connection.builder.handlers.size - 1
              ::Faraday.default_connection.builder.insert(idx, SSRFDetectionMiddleware)

              # Patch new connection instances (e.g. +Faraday.new+)
              ::Faraday::RackBuilder.prepend(RackBuilderPatch)
            end
          end
        end
      end
    end
  end
end
