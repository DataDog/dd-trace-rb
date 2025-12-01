# frozen_string_literal: true

require_relative '../../core/configuration/ext'

module Datadog
  module OpenTelemetry
    module Configuration
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.normalize_temporality_preference(env_var_name)
          proc do |value|
            if value && value.to_s.downcase != 'delta' && value.to_s.downcase != 'cumulative'
              Datadog.logger.warn("#{env_var_name}=#{value} is not supported. Using delta instead.")
              'delta'
            else
              value
            end
          end
        end

        def self.normalize_protocol(env_var_name)
          proc do |value|
            if value && value.to_s.downcase != 'http/protobuf'
              Datadog.logger.warn("#{env_var_name}=#{value} is not supported. Using http/protobuf instead.")
            end
         
            'http/protobuf'
          end
        end

        def self.headers_parser(env_var_name)
          lambda do |value|
            return {} if value.nil? || value.empty?

            headers = {}
            header_items = value.split(',')
            header_items.each do |key_value|
              key, header_value = key_value.split('=', 2)
              # If header is malformed, return an empty hash
              if key.nil? || header_value.nil?
                Datadog.logger.warn("#{env_var_name} has malformed header: #{key_value.inspect}")
                return {}
              end

              key.strip!
              header_value.strip!
              if key.empty? || header_value.empty?
                Datadog.logger.warn("#{env_var_name} has empty key or value in: #{key_value.inspect}")
                return {}
              end

              headers[key] = header_value
            end
            headers
          end
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :opentelemetry do
              settings :exporter do
                option :protocol do |o|
                  o.type :string
                  o.setter(&Settings.normalize_protocol('OTEL_EXPORTER_OTLP_PROTOCOL'))
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
                  o.env_parser(&Settings.headers_parser('OTEL_EXPORTER_OTLP_HEADERS'))
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
                  o.setter(&Settings.normalize_temporality_preference('OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE'))
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
                  o.env_parser(&Settings.headers_parser('OTEL_EXPORTER_OTLP_METRICS_HEADERS'))
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
                  o.setter(&Settings.normalize_protocol('OTEL_EXPORTER_OTLP_METRICS_PROTOCOL'))
                end
              end
            end
          end
        end
      end
    end
  end
end
