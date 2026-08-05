# frozen_string_literal: true

require_relative "ext"

module Datadog
  module Tracing
    module Configuration
      # Resolves OpenTelemetry trace-export configuration for the native transport.
      module OTLP
        module_function

        def enabled?(settings)
          settings.exporter.to_s.downcase == Ext::OTLP::EXPORTER_OTLP &&
            settings.agent_protocol_version.nil?
        end

        def transport_options(settings, exporter_settings, agent_settings)
          protocol = settings.protocol || general_protocol(exporter_settings)
          {
            otlp_endpoint: endpoint(settings, exporter_settings, agent_settings),
            otlp_headers: settings.headers || exporter_settings.headers,
            otlp_timeout_millis: settings.timeout_millis || exporter_settings.timeout_millis,
            otlp_protocol: protocol.strip.downcase,
          }
        end

        def parse_headers(value)
          return {} if value.nil? || value.empty?

          value.split(",").each_with_object({}) do |entry, headers|
            key, separator, header_value = entry.partition("=")
            next if separator.empty?

            key = key.strip
            header_value = header_value.strip
            next if key.empty? || header_value.empty?

            headers[key] = header_value
          end
        end

        def endpoint(settings, exporter_settings, agent_settings)
          endpoint = settings.endpoint
          return endpoint unless endpoint.nil? || endpoint.empty?

          general_endpoint = exporter_settings.endpoint
          unless general_endpoint.nil? || general_endpoint.empty?
            return general_endpoint.sub(%r{/*\z}, "") + Ext::OTLP::TRACES_PATH
          end

          hostname = agent_settings.hostname || Ext::OTLP::DEFAULT_HOST
          hostname = "[#{hostname}]" if hostname.include?(":") && !hostname.start_with?("[")
          "http://#{hostname}:#{Ext::OTLP::DEFAULT_PORT}#{Ext::OTLP::TRACES_PATH}"
        end
        private_class_method :endpoint

        def general_protocol(exporter_settings)
          if exporter_settings.using_default?(:protocol)
            Ext::OTLP::DEFAULT_PROTOCOL
          else
            exporter_settings.protocol
          end
        end
        private_class_method :general_protocol
      end
    end
  end
end
