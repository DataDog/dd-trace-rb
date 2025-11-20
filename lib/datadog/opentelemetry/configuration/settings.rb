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

        def self.add_settings!(base)
          base.class_eval do
            settings :opentelemetry do
              settings :exporter do
                option :protocol do |o|
                  o.type :string
                  o.env 'OTEL_EXPORTER_OTLP_PROTOCOL'
                  o.default 'http/protobuf'
                end

                option :timeout do |o|
                  o.type :int
                  o.env 'OTEL_EXPORTER_OTLP_TIMEOUT'
                  o.default 10_000
                end

                option :headers do |o|
                  o.type :hash
                  o.env 'OTEL_EXPORTER_OTLP_HEADERS'
                  o.default { {} }
                  o.env_parser do |value|
                    return {} unless value && !value.empty?
                    JSON.parse(value)
                  rescue JSON::ParserError  => exc
                    Datadog.logger.warn("Failed to parse OTEL_EXPORTER_OTLP_HEADERS: #{exc.class}: #{exc}: #{value}")
                    {}
                  end
                end

                option :endpoint do |o|
                  o.type :string, nilable: true
                  o.env 'OTEL_EXPORTER_OTLP_ENDPOINT'
                  o.default nil
                end
              end

              settings :metrics do
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

                option :export_interval do |o|
                  o.type :int
                  o.env 'OTEL_METRIC_EXPORT_INTERVAL'
                  o.default 10_000
                  o.env_parser { |value| value&.to_i }
                end

                option :export_timeout do |o|
                  o.type :int
                  o.env 'OTEL_METRIC_EXPORT_TIMEOUT'
                  o.default 7_500
                  o.env_parser { |value| value&.to_i }
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
                  o.env_parser do |value|
                    return {} unless value && !value.empty?
                    JSON.parse(value)
                  rescue JSON::ParserError => exc
                    Datadog.logger.warn("Failed to parse OTEL_EXPORTER_OTLP_METRICS_HEADERS: #{exc.class}: #{exc}: #{value}")
                    {}
                  end
                end

                option :timeout do |o|
                  o.type :int, nilable: true
                  o.env 'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT'
                  o.default nil
                  o.env_parser { |value| value&.to_i }
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
