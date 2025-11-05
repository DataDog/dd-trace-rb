# frozen_string_literal: true

require 'json'
require 'uri'
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
                    o.default 'grpc'
                  end

                  option :timeout do |o|
                    o.type :int
                    o.env 'OTEL_EXPORTER_OTLP_TIMEOUT'
                    o.default 10_000
                    o.env_parser { |value| value&.to_i }
                  end

                  option :headers do |o|
                    o.type :hash
                    o.env 'OTEL_EXPORTER_OTLP_HEADERS'
                    o.default { {} }
                    o.env_parser do |value|
                      return {} unless value && !value.empty?
                      JSON.parse(value)
                    rescue JSON::ParserError
                      Datadog.logger.warn("Failed to parse OTEL_EXPORTER_OTLP_HEADERS: #{value}")
                      {}
                    end
                  end

                  option :endpoint do |o|
                    o.type :string, nilable: true
                    o.env 'OTEL_EXPORTER_OTLP_ENDPOINT'
                    o.default do
                      settings = defined?(Datadog) && Datadog.respond_to?(:configuration) ? Datadog.configuration : nil
                      agent_host = settings&.agent&.host
                      unless agent_host
                        ext = Datadog::Core::Configuration::Ext
                        url = defined?(DATADOG_ENV) ? DATADOG_ENV[ext::Agent::ENV_DEFAULT_URL] : ENV['DD_TRACE_AGENT_URL']
                        if url
                          parsed = URI.parse(url) rescue nil
                          agent_host = parsed&.hostname
                        end
                        agent_host ||= defined?(DATADOG_ENV) ? DATADOG_ENV[ext::Agent::ENV_DEFAULT_HOST] : ENV['DD_AGENT_HOST']
                        agent_host ||= ext::Agent::HTTP::DEFAULT_HOST
                      end
                      protocol = defined?(DATADOG_ENV) ? DATADOG_ENV['OTEL_EXPORTER_OTLP_PROTOCOL'] : ENV['OTEL_EXPORTER_OTLP_PROTOCOL']
                      protocol ||= 'grpc'
                      port = protocol == 'http/protobuf' ? 4318 : 4317
                      "http://#{agent_host}:#{port}"
                    end
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
                    o.default 30_000
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
                    o.default do
                      metrics_protocol = defined?(DATADOG_ENV) ? DATADOG_ENV['OTEL_EXPORTER_OTLP_METRICS_PROTOCOL'] : ENV['OTEL_EXPORTER_OTLP_METRICS_PROTOCOL']
                      general_protocol = defined?(DATADOG_ENV) ? DATADOG_ENV['OTEL_EXPORTER_OTLP_PROTOCOL'] : ENV['OTEL_EXPORTER_OTLP_PROTOCOL']
                      general_endpoint = defined?(DATADOG_ENV) ? DATADOG_ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] : ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
                      
                      # If general endpoint is set, don't construct a default - let resolve_metrics_endpoint handle it
                      next nil if general_endpoint
                      
                      # Only construct default if a protocol is set
                      next nil unless metrics_protocol || general_protocol

                      settings = defined?(Datadog) && Datadog.respond_to?(:configuration) ? Datadog.configuration : nil
                      agent_host = settings&.agent&.host
                      unless agent_host
                        ext = Datadog::Core::Configuration::Ext
                        url = defined?(DATADOG_ENV) ? DATADOG_ENV[ext::Agent::ENV_DEFAULT_URL] : ENV['DD_TRACE_AGENT_URL']
                        if url
                          parsed = URI.parse(url) rescue nil
                          agent_host = parsed&.hostname
                        end
                        agent_host ||= defined?(DATADOG_ENV) ? DATADOG_ENV[ext::Agent::ENV_DEFAULT_HOST] : ENV['DD_AGENT_HOST']
                        agent_host ||= ext::Agent::HTTP::DEFAULT_HOST
                      end
                      protocol = metrics_protocol || general_protocol || 'grpc'
                      port = protocol == 'http/protobuf' ? 4318 : 4317
                      path = protocol == 'http/protobuf' ? '/v1/metrics' : ''
                      "http://#{agent_host}:#{port}#{path}"
                    end
                  end

                  option :headers do |o|
                    o.type :hash
                    o.env 'OTEL_EXPORTER_OTLP_METRICS_HEADERS'
                    o.default do
                      general_headers = ENV['OTEL_EXPORTER_OTLP_HEADERS']
                      if general_headers && !general_headers.empty?
                        JSON.parse(general_headers)
                      else
                        {}
                      end
                    rescue JSON::ParserError
                      {}
                    end
                    o.env_parser do |value|
                      return {} unless value && !value.empty?
                      JSON.parse(value)
                    rescue JSON::ParserError
                      Datadog.logger.warn("Failed to parse OTEL_EXPORTER_OTLP_METRICS_HEADERS: #{value}")
                      {}
                    end
                  end

                  option :timeout do |o|
                    o.type :int
                    o.env 'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT'
                    o.default do
                      general_timeout = ENV['OTEL_EXPORTER_OTLP_TIMEOUT']
                      general_timeout ? general_timeout.to_i : 10_000
                    end
                    o.env_parser { |value| value&.to_i }
                  end

                  option :protocol do |o|
                    o.type :string
                    o.env 'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL'
                    o.default do
                      general_protocol = ENV['OTEL_EXPORTER_OTLP_PROTOCOL']
                      general_protocol || 'grpc'
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

