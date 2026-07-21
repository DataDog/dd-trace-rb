# frozen_string_literal: true

require_relative "../core/configuration/ext"
require_relative "../core/environment/socket"

module Datadog
  module OpenTelemetry
    # Shared resource building and signal-specific config fallback logic for Logs and Metrics.
    module SignalConfiguration
      private

      def create_resource
        resource_attributes = {}

        @settings.tags&.each do |key, value| # steep:ignore
          otel_key = case key
          when "service" then "service.name"
          when "env" then "deployment.environment"
          when "version" then "service.version"
          else key
          end
          resource_attributes[otel_key] = value
        end

        resource_attributes["service.name"] = @settings.service_without_fallback || resource_attributes["service.name"] || Datadog::Core::Environment::Ext::FALLBACK_SERVICE_NAME # steep:ignore
        resource_attributes["deployment.environment"] = @settings.env if @settings.env # steep:ignore
        resource_attributes["service.version"] = @settings.version if @settings.version # steep:ignore

        hostname = Datadog::Core::Environment::Socket.resolved_hostname(@settings) # steep:ignore
        if hostname
          if hostname == @settings.hostname # steep:ignore
            resource_attributes["host.name"] = hostname
          elsif !resource_attributes.key?("host.name")
            resource_attributes["host.name"] = hostname
          end
        end

        ::OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
      end

      # Returns the signal-specific option value when explicitly set,
      # otherwise falls back to the general OTLP exporter config or computed_default.
      def config_or_exporter_fallback(signal:, option_name:, computed_default: nil)
        signal_settings = @settings.opentelemetry.public_send(signal) # steep:ignore
        if signal_settings.using_default?(option_name)
          @settings.opentelemetry.exporter.public_send(option_name) || computed_default # steep:ignore
        else
          signal_settings.public_send(option_name)
        end
      end
    end
  end
end
