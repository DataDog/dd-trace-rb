# frozen_string_literal: true

require_relative '../../core/environment/ext'
require_relative '../../core/environment/identity'
require_relative '../../core/environment/socket'
require_relative '../../core/transport/response'
require_relative '../../version'
require_relative '../configuration/ext'
require_relative '../sampling/ext'
require_relative 'otlp/encoder'
require_relative 'otlp/exporter'
require_relative 'trace_formatter'

module Datadog
  module Tracing
    module Transport
      # OTLP trace export. Selected by `OTEL_TRACES_EXPORTER=otlp`; replaces the Datadog agent
      # trace transport with a pure-Ruby OTLP http/json exporter.
      module OTLP
        module_function

        # Builds an OTLP trace {Transport} from the gem configuration.
        #
        # @param settings [Datadog::Core::Configuration::Settings]
        # @param agent_settings [Datadog::Core::Configuration::AgentSettings]
        # @param logger [Datadog::Core::Logger]
        # @return [Datadog::Tracing::Transport::OTLP::Transport]
        def build(settings:, agent_settings:, logger: Datadog.logger)
          otlp = settings.tracing.otlp

          endpoint = resolve_endpoint(otlp, agent_settings)
          headers = otlp.headers || otlp.headers_fallback
          timeout = otlp.timeout_millis || otlp.timeout_millis_fallback

          # Only http/json is supported this phase. Warn (don't fail) on a configured non-http/json
          # protocol so a grpc/http-protobuf misconfiguration isn't a silent no-op — traces are still
          # sent as http/json. Mirrors dd-trace-rs.
          protocol = otlp.protocol || otlp.protocol_fallback
          if protocol && protocol != Configuration::Ext::OTLP::PROTOCOL_HTTP_JSON
            logger.warn(
              "OTLP trace export only supports the http/json protocol; the configured protocol " \
              "#{protocol.inspect} is ignored and traces are sent as http/json."
            )
          end

          exporter = Exporter.new(
            endpoint: endpoint,
            headers: headers,
            timeout_millis: timeout,
            logger: logger,
          )

          encoder = Encoder.new(
            resource_attributes: resource_attributes(settings),
            scope_version: Core::Environment::Ext::GEM_DATADOG_VERSION,
            default_service: settings.service,
          )

          Transport.new(exporter: exporter, encoder: encoder, logger: logger)
        end

        # Resolves the OTLP traces endpoint following the configuration precedence:
        # 1. `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` (full URL, used as-is)
        # 2. `OTEL_EXPORTER_OTLP_ENDPOINT` (strip trailing `/`, append `/v1/traces`)
        # 3. computed `http://<agent_host>:4318/v1/traces`
        def resolve_endpoint(otlp, agent_settings)
          return otlp.endpoint if otlp.endpoint && !otlp.endpoint.empty?

          fallback = otlp.endpoint_fallback
          if fallback && !fallback.empty?
            return "#{fallback.sub(%r{/+\z}, "")}#{Configuration::Ext::OTLP::TRACES_PATH}"
          end

          host = agent_settings.hostname || 'localhost'
          "http://#{host}:#{Configuration::Ext::OTLP::DEFAULT_PORT}#{Configuration::Ext::OTLP::TRACES_PATH}"
        end

        # Builds the OTLP resource attributes as a KeyValue list.
        def resource_attributes(settings)
          attributes = []
          attributes << string_attribute('service.name', settings.service) if settings.service
          attributes << string_attribute('deployment.environment.name', settings.env) if settings.env
          attributes << string_attribute('service.version', settings.version) if settings.version
          attributes << string_attribute('telemetry.sdk.name', 'datadog')
          attributes << string_attribute('telemetry.sdk.language', Core::Environment::Ext::LANG)
          attributes << string_attribute('telemetry.sdk.version', Core::Environment::Ext::GEM_DATADOG_VERSION)
          # Added for parity with libdatadog-based languages.
          attributes << string_attribute('runtime-id', Core::Environment::Identity.id)
          attributes
        end

        def string_attribute(key, value)
          {key: key, value: {stringValue: value.to_s}}
        end

        # Transport that satisfies the {Datadog::Tracing::Writer} transport contract by encoding each
        # trace to OTLP http/json and sending it via the {Exporter}. Unsampled traces are dropped
        # before export, since OTLP endpoints perform no agent-side sampling.
        class Transport
          attr_reader :exporter, :encoder, :logger

          def initialize(exporter:, encoder:, logger:)
            @exporter = exporter
            @encoder = encoder
            @logger = logger
            @stats = Statistics.new
          end

          # @param traces [Array<Datadog::Tracing::TraceSegment>]
          # @return [Array<Response>]
          def send_traces(traces)
            traces.map do |trace|
              next Response.new(trace_count: 0) if drop?(trace)

              TraceFormatter.format!(trace)
              payload = encoder.encode(trace)
              logger.debug { "Flushing OTLP trace: #{payload}" }

              ok = exporter.export(payload)
              Response.new(trace_count: trace.spans.length, server_error: !ok)
            end
          end

          attr_reader :stats

          private

          # Drops a trace whose sampling priority is below AUTO_KEEP (mirrors dd-trace-js).
          def drop?(trace)
            priority = trace.sampling_priority
            !priority.nil? && priority < Sampling::Ext::Priority::AUTO_KEEP
          end
        end

        # Minimal transport response satisfying the {Datadog::Tracing::Writer} contract.
        class Response
          include Core::Transport::Response

          attr_reader :trace_count

          def initialize(trace_count:, server_error: false)
            @trace_count = trace_count
            @server_error = server_error
          end

          def ok?
            !@server_error
          end

          def server_error?
            @server_error
          end

          def internal_error?
            false
          end

          # OTLP endpoints don't return Datadog agent service sampling rates. Returning nil lets the
          # writer's after-send priority-sampler callback short-circuit cleanly instead of raising
          # (and swallowing) a NoMethodError on every flush.
          def service_rates
            nil
          end
        end

        # No-op statistics object compatible with the agent transport's `#stats`.
        class Statistics
          def reset!
          end
        end
      end
    end
  end
end
