# frozen_string_literal: true

require 'rack/events'

require_relative '../../../core/remote/tie/tracing'
require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative '../http'
require_relative 'ext'
require_relative 'request_queue'
require_relative 'request_tagging'

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Rack::Events handler that instruments HTTP requests with Datadog tracing.
        #
        # Use this as an opt-in alternative to TraceMiddleware when your application
        # already uses Rack::Events:
        #
        #   use Rack::Events, [Datadog::Tracing::Contrib::Rack::EventHandler.new]
        #
        # Note: Rack::Events only intercepts StandardError subclasses in on_error.
        # Non-StandardError exceptions (e.g. SignalException) will not be recorded
        # as errors on the span, unlike TraceMiddleware which rescues Exception.
        class EventHandler
          include ::Rack::Events::Abstract
          include RequestTagging

          # Env keys used to share state across lifecycle callbacks within one request.
          RACK_ENV_ACTIVE = 'datadog.rack_events_active'
          RACK_ENV_REQUEST_TRACE = 'datadog.rack_events_request_trace'
          RACK_ENV_ORIGINAL_ENV = 'datadog.rack_events_original_env'
          RACK_ENV_PROXY_REQUEST_SPAN = 'datadog.rack_events_proxy_request_span'

          def on_start(request, _response)
            env = request.env

            # Rack-in-rack guard: if an outer TraceMiddleware or EventHandler already
            # opened a span for this request, skip to avoid creating a nested rack.request.
            return if env[Ext::RACK_ENV_REQUEST_SPAN]

            boot = Datadog::Core::Remote::Tie.boot

            if configuration[:distributed_tracing]
              trace_digest = Contrib::HTTP.extract(env)
              Tracing.continue_trace!(trace_digest) if trace_digest
            end

            open_proxy_spans(env) if configuration[:request_queuing]

            trace_options = {type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND}
            trace_options[:service] = configuration[:service_name] if configuration[:service_name]

            request_span = Tracing.trace(Ext::SPAN_REQUEST, **trace_options)
            request_span.resource = nil

            # When tracing and distributed tracing are both disabled, `.active_trace` will be `nil`.
            # Return a null object to continue operation.
            env[Ext::RACK_ENV_REQUEST_SPAN] = request_span
            env[RACK_ENV_REQUEST_TRACE] = Tracing.active_trace || TraceOperation.new
            env[RACK_ENV_ORIGINAL_ENV] = env.dup
            env[RACK_ENV_ACTIVE] = true

            Datadog::Core::Remote::Tie::Tracing.tag(boot, request_span)
          end

          def on_finish(request, response)
            env = request.env

            # Only act when this handler opened the span (guards rack-in-rack).
            return unless env.delete(RACK_ENV_ACTIVE)

            request_span = env[Ext::RACK_ENV_REQUEST_SPAN]
            return unless request_span

            request_trace = env[RACK_ENV_REQUEST_TRACE]
            original_env = env[RACK_ENV_ORIGINAL_ENV] || env
            status = response&.status
            headers = response&.headers

            set_request_tags!(request_trace, request_span, env, status, headers, nil, original_env)
            request_span.finish

            env[RACK_ENV_PROXY_REQUEST_SPAN]&.finish
          end

          def on_error(request, _response, error)
            env = request.env

            # Only act when this handler opened the span (guards rack-in-rack).
            # Don't finish here — on_finish is always called after on_error.
            return unless env[RACK_ENV_ACTIVE]

            env[Ext::RACK_ENV_REQUEST_SPAN]&.set_error(error)
          end

          private

          def open_proxy_spans(env)
            start_time = QueueTime.get_request_start(env)
            return unless start_time

            options = {
              service: configuration[:web_service_name],
              start_time: start_time,
              type: Tracing::Metadata::Ext::HTTP::TYPE_PROXY,
            }

            proxy_request_span = Tracing.trace(Ext::SPAN_HTTP_PROXY_REQUEST, **options)
            proxy_request_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
            proxy_request_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_REQUEST)
            proxy_request_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)

            queue_span = Tracing.trace(Ext::SPAN_HTTP_PROXY_QUEUE, **options)
            queue_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
            queue_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_QUEUE)
            queue_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)

            Contrib::Analytics.set_measured(queue_span)
            # Finish queue span immediately — it records only time spent waiting, not processing.
            queue_span.finish

            env[RACK_ENV_PROXY_REQUEST_SPAN] = proxy_request_span
          end
        end
      end
    end
  end
end
