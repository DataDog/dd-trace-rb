# frozen_string_literal: true

require 'json'
require_relative '../../core/configuration/ext'

module Datadog
  module OpenTelemetry
    module Configuration
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.json_parser(env_var_name)
          proc do |value|
            next {} if value.nil? || value.empty?
            parsed = JSON.parse(value)
            unless parsed.is_a?(Hash)
              Datadog.logger.warn("#{env_var_name} must be a JSON object (hash), got: #{parsed.class}")
              next {}
            end
            parsed
          rescue JSON::ParserError => exc
            Datadog.logger.warn("Failed to parse #{env_var_name}: #{exc.class}: #{exc}: #{value}")
            {}
          end
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :opentelemetry do
              settings :exporter do
                option :protocol do |o|
                  o.type :string
                  o.env 'OTEL_EXPORTER_OTLP_PROTOCOL'
                  o.default 'http/protobuf'
                end

                option :timeout_millis do |o|
                  o.type :int
                  o.env 'OTEL_EXPORTER_OTLP_TIMEOUT'
                  o.default 10_000
                end

                option :headers do |o|
                  o.type :hash
                  o.env 'OTEL_EXPORTER_OTLP_HEADERS'
                  o.default { {} }
                  o.env_parser(&Settings.json_parser('OTEL_EXPORTER_OTLP_HEADERS'))
                end

                option :endpoint do |o|
                  o.type :string, nilable: true
                  o.env 'OTEL_EXPORTER_OTLP_ENDPOINT'
                  o.default nil
                end
              end

              settings :metrics do
                # Metrics-specific options default to nil to detect unset state.
                # If a metrics-specific env var (e.g., OTEL_EXPORTER_OTLP_METRICS_TIMEOUT) is not set,
                # we fall back to the general OTLP env var (e.g., OTEL_EXPORTER_OTLP_TIMEOUT) per OpenTelemetry spec.
                option :enabled do |o|
                  o.type :bool
                  o.env 'DD_METRICS_OTEL_ENABLED'
                  o.default false
                end

                option :exporter do |o|
                  o.type :string
                  o.env 'OTEL_METRICS_EXPORTER'
                  o.default 'otlp'
                end

                option :export_interval_millis do |o|
                  o.type :int
                  o.env 'OTEL_METRIC_EXPORT_INTERVAL'
                  o.default 10_000
                end

                option :export_timeout_millis do |o|
                  o.type :int
                  o.env 'OTEL_METRIC_EXPORT_TIMEOUT'
                  o.default 7_500
                end

                option :temporality_preference do |o|
                  o.type :string
                  o.env 'OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE'
                  o.default 'delta'
                end

                option :endpoint do |o|
                  o.type :string, nilable: true
                  o.env 'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT'
                  o.default nil
                end

                option :headers do |o|
                  o.type :hash, nilable: true
                  o.env 'OTEL_EXPORTER_OTLP_METRICS_HEADERS'
                  o.default nil
                  o.env_parser(&Settings.json_parser('OTEL_EXPORTER_OTLP_METRICS_HEADERS'))
                end

                option :timeout_millis do |o|
                  o.type :int, nilable: true
                  o.env 'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT'
                  o.default nil
                end

                option :protocol do |o|
                  o.type :string, nilable: true
                  o.env 'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL'
                  o.default nil
                end
              end
            end
          end
        end
      end
    end
  end
end
